//! Konami VRC 家族:VRC2/VRC4(mapper 21/22/23/25)与 VRC6(24/26,含扩展音源)。
//!
//! 各编号的寄存器地址线不同,统一归一化成 (A0,A1) 再分派。
//! VRC2 子集(无 IRQ/无单屏镜像)由游戏自身不触碰对应寄存器而自然兼容;
//! $6000-$7FFF 一律提供 PRG RAM(覆盖 VRC2 一位 latch 的读回行为)。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

/// VRC4/6/7 共用的 IRQ 单元:8 位向上计数,扫描线模式带 341/3 预分频。
#[derive(Default, Serialize, Deserialize)]
pub struct VrcIrq {
    latch: u8,
    counter: u8,
    enabled: bool,
    enable_after_ack: bool,
    cycle_mode: bool,
    prescaler: i16,
    pub pending: bool,
}

impl VrcIrq {
    pub fn write_latch_lo(&mut self, v: u8) {
        self.latch = self.latch & 0xF0 | v & 0x0F;
    }
    pub fn write_latch_hi(&mut self, v: u8) {
        self.latch = self.latch & 0x0F | (v & 0x0F) << 4;
    }
    pub fn write_latch(&mut self, v: u8) {
        self.latch = v;
    }
    pub fn write_control(&mut self, v: u8) {
        self.pending = false;
        self.enable_after_ack = v & 1 != 0;
        self.enabled = v & 2 != 0;
        self.cycle_mode = v & 4 != 0;
        if self.enabled {
            self.counter = self.latch;
            self.prescaler = 341;
        }
    }
    pub fn ack(&mut self) {
        self.pending = false;
        self.enabled = self.enable_after_ack;
    }
    pub fn tick(&mut self) {
        if !self.enabled {
            return;
        }
        if self.cycle_mode {
            self.clock();
        } else {
            self.prescaler -= 3;
            if self.prescaler <= 0 {
                self.prescaler += 341;
                self.clock();
            }
        }
    }
    fn clock(&mut self) {
        if self.counter == 0xFF {
            self.counter = self.latch;
            self.pending = true;
        } else {
            self.counter += 1;
        }
    }
}

/// 把各编号的寄存器地址归一化成 (A0, A1)。
fn normalize_lines(mapper: u16, addr: u16) -> (u16, u16) {
    let a = addr as u32;
    let (a0, a1) = match mapper {
        21 => ((a >> 1 | a >> 6) & 1, (a >> 2 | a >> 7) & 1),
        22 => ((a >> 1) & 1, a & 1),
        25 => ((a >> 1 | a >> 3) & 1, (a | a >> 2) & 1),
        _ => ((a | a >> 2) & 1, (a >> 1 | a >> 3) & 1), // 23
    };
    (a0 as u16, a1 as u16)
}

// ---------------- VRC2 / VRC4 ----------------

#[derive(Serialize, Deserialize)]
pub struct Vrc24 {
    mapper: u16,
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    prg0: u8,
    prg1: u8,
    swap: bool,
    chr: [u16; 8], // 9 位 bank
    mirroring: Mirroring,
    irq: VrcIrq,
    /// mapper 22(VRC2a):CHR 寄存器值右移一位
    chr_shift: bool,
}

impl Vrc24 {
    pub fn new(mapper: u16, prg_len: usize, chr_len: usize) -> Vrc24 {
        Vrc24 {
            mapper,
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram: chr_len == 0,
            prg0: 0,
            prg1: 0,
            swap: false,
            chr: [0; 8],
            mirroring: Mirroring::Vertical,
            irq: VrcIrq::default(),
            chr_shift: mapper == 22,
        }
    }
}

impl MapperImpl for Vrc24 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x2000).max(1);
        let off = addr as usize & 0x1FFF;
        let bank = match (addr >> 13) & 3 {
            0 => {
                if self.swap {
                    banks - 2
                } else {
                    self.prg0 as usize % banks
                }
            }
            1 => self.prg1 as usize % banks,
            2 => {
                if self.swap {
                    self.prg0 as usize % banks
                } else {
                    banks - 2
                }
            }
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgWrite::Handled;
        }
        let (a0, a1) = normalize_lines(self.mapper, addr);
        let sub = a1 << 1 | a0;
        match addr & 0xF000 {
            0x8000 => self.prg0 = val & 0x1F,
            0xA000 => self.prg1 = val & 0x1F,
            0x9000 => match sub {
                0 | 1 => {
                    self.mirroring = match val & 3 {
                        0 => Mirroring::Vertical,
                        1 => Mirroring::Horizontal,
                        2 => Mirroring::SingleA,
                        _ => Mirroring::SingleB,
                    }
                }
                _ => self.swap = val & 2 != 0, // VRC4 swap 模式
            },
            0xB000 | 0xC000 | 0xD000 | 0xE000 => {
                let slot = (((addr >> 12) - 0xB) * 2 + a1) as usize;
                let half = a0;
                let cur = self.chr[slot];
                self.chr[slot] = if half == 0 {
                    cur & 0x1F0 | (val & 0x0F) as u16
                } else {
                    cur & 0x00F | ((val & 0x1F) as u16) << 4
                };
            }
            0xF000 => match sub {
                0 => self.irq.write_latch_lo(val),
                1 => self.irq.write_latch_hi(val),
                2 => self.irq.write_control(val),
                _ => self.irq.ack(),
            },
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 10) as usize & 7;
        let mut bank = self.chr[slot] as usize;
        if self.chr_shift {
            bank >>= 1;
        }
        let banks = (self.chr_len / 0x400).max(1);
        let i = (bank % banks) * 0x400 + (addr as usize & 0x3FF);
        if self.chr_is_ram {
            ChrTarget::Ram(i)
        } else {
            ChrTarget::Rom(i)
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn cpu_tick(&mut self) {
        self.irq.tick();
    }

    fn irq_asserted(&self) -> bool {
        self.irq.pending
    }
}

// ---------------- VRC6 ----------------

#[derive(Default, Serialize, Deserialize)]
struct Vrc6Pulse {
    vol: u8,
    duty: u8,
    constant: bool,
    period: u16,
    enabled: bool,
    timer: u16,
    step: u8,
}

impl Vrc6Pulse {
    fn tick(&mut self) {
        if !self.enabled {
            return;
        }
        if self.timer == 0 {
            self.timer = self.period;
            self.step = (self.step + 1) & 15;
        } else {
            self.timer -= 1;
        }
    }
    fn output(&self) -> u8 {
        if !self.enabled {
            return 0;
        }
        if self.constant || self.step <= self.duty {
            self.vol
        } else {
            0
        }
    }
}

#[derive(Default, Serialize, Deserialize)]
struct Vrc6Saw {
    rate: u8,
    period: u16,
    enabled: bool,
    timer: u16,
    acc: u8,
    step: u8,
}

impl Vrc6Saw {
    fn tick(&mut self) {
        if !self.enabled {
            return;
        }
        if self.timer == 0 {
            self.timer = self.period;
            self.step += 1;
            if self.step & 1 == 0 {
                self.acc = self.acc.wrapping_add(self.rate);
            }
            if self.step >= 14 {
                self.step = 0;
                self.acc = 0;
            }
        } else {
            self.timer -= 1;
        }
    }
    fn output(&self) -> u8 {
        if self.enabled {
            self.acc >> 3
        } else {
            0
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct Vrc6 {
    swapped: bool, // mapper 26:A0/A1 互换
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    prg16: u8,
    prg8: u8,
    chr: [u8; 8],
    mirroring: Mirroring,
    irq: VrcIrq,
    halt: bool,
    pulse1: Vrc6Pulse,
    pulse2: Vrc6Pulse,
    saw: Vrc6Saw,
}

impl Vrc6 {
    pub fn new(mapper: u16, prg_len: usize, chr_len: usize) -> Vrc6 {
        Vrc6 {
            swapped: mapper == 26,
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram: chr_len == 0,
            prg16: 0,
            prg8: 0,
            chr: [0; 8],
            mirroring: Mirroring::Vertical,
            irq: VrcIrq::default(),
            halt: false,
            pulse1: Vrc6Pulse::default(),
            pulse2: Vrc6Pulse::default(),
            saw: Vrc6Saw::default(),
        }
    }
}

impl MapperImpl for Vrc6 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks8 = (self.prg_len / 0x2000).max(1);
        match addr {
            0x8000..=0xBFFF => {
                let banks16 = (self.prg_len / 0x4000).max(1);
                PrgTarget::Rom(
                    (self.prg16 as usize % banks16) * 0x4000 + (addr as usize & 0x3FFF),
                )
            }
            0xC000..=0xDFFF => {
                PrgTarget::Rom((self.prg8 as usize % banks8) * 0x2000 + (addr as usize & 0x1FFF))
            }
            _ => PrgTarget::Rom((banks8 - 1) * 0x2000 + (addr as usize & 0x1FFF)),
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgWrite::Handled;
        }
        let mut sub = addr & 3;
        if self.swapped {
            sub = (sub & 1) << 1 | (sub >> 1) & 1;
        }
        match (addr & 0xF000, sub) {
            (0x8000, _) => self.prg16 = val & 0x0F,
            (0xC000, _) => self.prg8 = val & 0x1F,
            (0x9000, 0) => {
                self.pulse1.vol = val & 0x0F;
                self.pulse1.duty = val >> 4 & 7;
                self.pulse1.constant = val & 0x80 != 0;
            }
            (0x9000, 1) => self.pulse1.period = self.pulse1.period & 0xF00 | val as u16,
            (0x9000, 2) => {
                self.pulse1.period = self.pulse1.period & 0x0FF | ((val & 0x0F) as u16) << 8;
                self.pulse1.enabled = val & 0x80 != 0;
                if !self.pulse1.enabled {
                    self.pulse1.step = 0;
                }
            }
            (0x9000, 3) => self.halt = val & 1 != 0,
            (0xA000, 0) => {
                self.pulse2.vol = val & 0x0F;
                self.pulse2.duty = val >> 4 & 7;
                self.pulse2.constant = val & 0x80 != 0;
            }
            (0xA000, 1) => self.pulse2.period = self.pulse2.period & 0xF00 | val as u16,
            (0xA000, 2) => {
                self.pulse2.period = self.pulse2.period & 0x0FF | ((val & 0x0F) as u16) << 8;
                self.pulse2.enabled = val & 0x80 != 0;
                if !self.pulse2.enabled {
                    self.pulse2.step = 0;
                }
            }
            (0xB000, 0) => self.saw.rate = val & 0x3F,
            (0xB000, 1) => self.saw.period = self.saw.period & 0xF00 | val as u16,
            (0xB000, 2) => {
                self.saw.period = self.saw.period & 0x0FF | ((val & 0x0F) as u16) << 8;
                self.saw.enabled = val & 0x80 != 0;
                if !self.saw.enabled {
                    self.saw.acc = 0;
                    self.saw.step = 0;
                }
            }
            (0xB000, 3) => {
                self.mirroring = match val >> 2 & 3 {
                    0 => Mirroring::Vertical,
                    1 => Mirroring::Horizontal,
                    2 => Mirroring::SingleA,
                    _ => Mirroring::SingleB,
                };
            }
            (0xD000, s) => self.chr[s as usize] = val,
            (0xE000, s) => self.chr[4 + s as usize] = val,
            (0xF000, 0) => self.irq.write_latch(val),
            (0xF000, 1) => self.irq.write_control(val),
            (0xF000, 2) => self.irq.ack(),
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 10) as usize & 7;
        let banks = (self.chr_len / 0x400).max(1);
        let i = (self.chr[slot] as usize % banks) * 0x400 + (addr as usize & 0x3FF);
        if self.chr_is_ram {
            ChrTarget::Ram(i)
        } else {
            ChrTarget::Rom(i)
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn cpu_tick(&mut self) {
        self.irq.tick();
        if !self.halt {
            self.pulse1.tick();
            self.pulse2.tick();
            self.saw.tick();
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq.pending
    }

    fn audio(&mut self) -> f32 {
        // 两方波 0-15 + 锯齿 0-31,幅度对齐 APU 方波量级
        let sum = self.pulse1.output() as f32 + self.pulse2.output() as f32
            + self.saw.output() as f32;
        sum * 0.0062
    }
}
