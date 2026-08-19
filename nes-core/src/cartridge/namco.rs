//! Namco 系:
//! - Namco 108/118 家族(mapper 206/88/154/95/76):MMC3 前身,无 IRQ
//! - N163(mapper 19):CHR/NT 全可控 + 15 位 IRQ + 波表音源(1-8 通道)
//! - Namco 175/340(mapper 210):N163 去掉 IRQ/音源/NT 控制

use super::mapper::{ChrTarget, MapperImpl, NtRead, NtWrite, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

// ---------------- Namco 108 家族 ----------------

#[derive(Serialize, Deserialize)]
pub struct Namco108 {
    pub variant: u16, // 206/88/154/95/76
    prg_len: usize,
    chr_len: usize,
    regs: [u8; 8],
    select: u8,
    mirroring: Mirroring,
}

impl Namco108 {
    pub fn new(variant: u16, prg_len: usize, chr_len: usize, m: Mirroring) -> Namco108 {
        Namco108 {
            variant,
            prg_len,
            chr_len: chr_len.max(0x2000),
            regs: [0; 8],
            select: 0,
            mirroring: m,
        }
    }
}

impl MapperImpl for Namco108 {
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
            0 => self.regs[6] as usize % banks,
            1 => self.regs[7] as usize % banks,
            2 => banks - 2,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            if addr & 1 == 0 {
                self.select = val & 7;
                if self.variant == 154 {
                    self.mirroring = if val & 0x40 != 0 {
                        Mirroring::SingleB
                    } else {
                        Mirroring::SingleA
                    };
                }
            } else {
                self.regs[(self.select & 7) as usize] = val;
            }
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let a = addr as usize;
        let banks1k = (self.chr_len / 0x400).max(1);
        let i = match self.variant {
            76 => {
                // 2K 槽 ×4,R2-R5
                let slot = 2 + (a >> 11);
                let bank = self.regs[slot] as usize;
                (bank % (banks1k / 2).max(1)) * 0x800 + (a & 0x7FF)
            }
            _ => {
                let hi_or = if matches!(self.variant, 88 | 154) { 0x40 } else { 0 };
                if a < 0x1000 {
                    let bank = (self.regs[a >> 11] & 0xFE) as usize;
                    (bank % banks1k) * 0x400 + (a & 0x7FF)
                } else {
                    let bank = (self.regs[2 + ((a - 0x1000) >> 10)] as usize) | hi_or;
                    (bank % banks1k) * 0x400 + (a & 0x3FF)
                }
            }
        };
        ChrTarget::Rom(i)
    }

    fn nt_map(&mut self, addr: u16) -> NtRead {
        if self.variant == 95 {
            // NAMCOT-3425:NT 选择来自 CHR R0/R1 的 bit5
            let a = (addr as usize - 0x2000) & 0xFFF;
            let table = a / 0x400;
            let off = a & 0x3FF;
            let page = (self.regs[table >> 1] >> 5 & 1) as usize;
            return NtRead::Ciram(page, off);
        }
        let (p, o) = super::mapper::standard_nt(self.mirroring(), addr);
        NtRead::Ciram(p & 1, o)
    }

    fn nt_write_map(&mut self, addr: u16, _val: u8) -> NtWrite {
        if self.variant == 95 {
            let a = (addr as usize - 0x2000) & 0xFFF;
            let table = a / 0x400;
            let off = a & 0x3FF;
            let page = (self.regs[table >> 1] >> 5 & 1) as usize;
            return NtWrite::Ciram(page, off);
        }
        let (p, o) = super::mapper::standard_nt(self.mirroring(), addr);
        NtWrite::Ciram(p & 1, o)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- N163 音源 ----------------

#[derive(Serialize, Deserialize)]
pub struct N163Audio {
    pub ram: Vec<u8>, // 128 字节
    addr: u8,
    auto_inc: bool,
    enabled: bool,
    /// 15 CPU 周期轮转一个通道
    divider: u8,
    cur_channel: u8,
    outputs: [f32; 8],
}

impl Default for N163Audio {
    fn default() -> N163Audio {
        N163Audio {
            ram: vec![0; 128],
            addr: 0,
            auto_inc: false,
            enabled: true,
            divider: 0,
            cur_channel: 0,
            outputs: [0.0; 8],
        }
    }
}

impl N163Audio {
    fn active_channels(&self) -> u8 {
        (self.ram[0x7F] >> 4 & 7) + 1
    }

    pub fn write_addr(&mut self, v: u8) {
        self.addr = v & 0x7F;
        self.auto_inc = v & 0x80 != 0;
    }

    pub fn write_data(&mut self, v: u8) {
        self.ram[self.addr as usize] = v;
        if self.auto_inc {
            self.addr = (self.addr + 1) & 0x7F;
        }
    }

    pub fn read_data(&mut self) -> u8 {
        let v = self.ram[self.addr as usize];
        if self.auto_inc {
            self.addr = (self.addr + 1) & 0x7F;
        }
        v
    }

    fn sample(&self, index: u32) -> f32 {
        let byte = self.ram[(index as usize / 2) & 0x7F];
        let s = if index & 1 == 0 { byte & 0x0F } else { byte >> 4 };
        s as f32 - 8.0
    }

    /// 每 CPU 周期调用;硬件按 15 周期/通道轮转。
    fn tick(&mut self) {
        self.divider += 1;
        if self.divider < 15 {
            return;
        }
        self.divider = 0;
        let n = self.active_channels();
        let ch = 7 - (self.cur_channel % n) as usize;
        self.cur_channel = (self.cur_channel + 1) % n;
        let base = 0x40 + ch * 8;
        let freq = self.ram[base] as u32
            | (self.ram[base + 2] as u32) << 8
            | (self.ram[base + 4] as u32 & 3) << 16;
        let len = (256 - (self.ram[base + 4] as u32 & 0xFC)) & 0xFF;
        let len = if len == 0 { 256 } else { len };
        let vol = (self.ram[base + 7] & 0x0F) as f32;
        let mut phase = self.ram[base + 1] as u32
            | (self.ram[base + 3] as u32) << 8
            | (self.ram[base + 5] as u32) << 16;
        phase = (phase + freq) % (len << 16);
        self.ram[base + 1] = phase as u8;
        self.ram[base + 3] = (phase >> 8) as u8;
        self.ram[base + 5] = (phase >> 16) as u8;
        let offset = self.ram[base + 6] as u32;
        let idx = (phase >> 16) + offset;
        self.outputs[ch] = if self.enabled {
            self.sample(idx) * vol
        } else {
            0.0
        };
    }

    fn output(&self) -> f32 {
        let n = self.active_channels() as usize;
        let sum: f32 = self.outputs[8 - n..].iter().sum();
        // 4bit×vol15 → 归一;多通道时轮转本身会降低有效音量,做轻度补偿
        sum * 0.0011 * (1.0 + n as f32 * 0.09)
    }
}

// ---------------- N163 本体 ----------------

#[derive(Serialize, Deserialize)]
pub struct N163 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr: [u8; 8],
    nt: [u8; 4],
    /// $E800 bit6/7:允许 $0000/$1000 侧用 >=0xE0 的值选 CIRAM
    ciram_lo_enable: bool,
    ciram_hi_enable: bool,
    irq_counter: u16,
    irq_enable: bool,
    irq_pending: bool,
    pub audio: N163Audio,
    sound_disable: bool,
}

impl N163 {
    pub fn new(prg_len: usize, chr_len: usize) -> N163 {
        N163 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 3],
            chr: [0; 8],
            nt: [0xE0; 4],
            ciram_lo_enable: true,
            ciram_hi_enable: true,
            irq_counter: 0,
            irq_enable: false,
            irq_pending: false,
            audio: N163Audio::default(),
            sound_disable: false,
        }
    }

    fn chr_slot(&self, slot: usize, allow_ciram: bool, addr: u16) -> NtRead {
        let v = self.chr[slot];
        if allow_ciram && v >= 0xE0 {
            NtRead::Ciram((v & 1) as usize, addr as usize & 0x3FF)
        } else {
            let banks = (self.chr_len / 0x400).max(1);
            NtRead::Chr((v as usize % banks) * 0x400 + (addr as usize & 0x3FF))
        }
    }
}

impl MapperImpl for N163 {
    fn cpu_map(&mut self, addr: u16) -> PrgTarget {
        match addr {
            0x4800..=0x4FFF => PrgTarget::Value(self.audio.read_data()),
            0x5000..=0x57FF => {
                PrgTarget::Value(self.irq_counter as u8)
            }
            0x5800..=0x5FFF => {
                PrgTarget::Value((self.irq_counter >> 8) as u8 | (self.irq_enable as u8) << 7)
            }
            _ => self.cpu_peek(addr),
        }
    }

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
            0 => (self.prg[0] & 0x3F) as usize % banks,
            1 => (self.prg[1] & 0x3F) as usize % banks,
            2 => (self.prg[2] & 0x3F) as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x4800..=0x4FFF => self.audio.write_data(val),
            0x5000..=0x57FF => {
                self.irq_counter = self.irq_counter & 0xFF00 | val as u16;
                self.irq_pending = false;
            }
            0x5800..=0x5FFF => {
                self.irq_counter = self.irq_counter & 0x00FF | ((val & 0x7F) as u16) << 8;
                self.irq_enable = val & 0x80 != 0;
                self.irq_pending = false;
            }
            0x6000..=0x7FFF => return PrgWrite::Ram((addr - 0x6000) as usize),
            0x8000..=0xB7FF => {
                let slot = ((addr - 0x8000) / 0x800) as usize;
                self.chr[slot] = val;
            }
            0xB800..=0xBFFF => {} // 部分板为音源禁用
            0xC000..=0xDFFF => {
                let slot = ((addr - 0xC000) / 0x800) as usize & 3;
                self.nt[slot] = val;
            }
            0xE000..=0xE7FF => {
                self.prg[0] = val & 0x3F;
                self.sound_disable = val & 0x40 != 0;
                self.audio.enabled = !self.sound_disable;
            }
            0xE800..=0xEFFF => {
                self.prg[1] = val & 0x3F;
                self.ciram_lo_enable = val & 0x40 == 0;
                self.ciram_hi_enable = val & 0x80 == 0;
            }
            0xF000..=0xF7FF => self.prg[2] = val & 0x3F,
            0xF800..=0xFFFF => self.audio.write_addr(val),
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 10) as usize & 7;
        let allow = if addr < 0x1000 {
            self.ciram_lo_enable
        } else {
            self.ciram_hi_enable
        };
        match self.chr_slot(slot, allow, addr) {
            NtRead::Chr(i) => ChrTarget::Rom(i),
            // pattern 区映射 CIRAM 的用法极罕见,这里按 CHR 兜底(TODO:M5 打磨)
            _ => {
                let banks = (self.chr_len / 0x400).max(1);
                ChrTarget::Rom(
                    (self.chr[slot] as usize % banks) * 0x400 + (addr as usize & 0x3FF),
                )
            }
        }
    }

    fn nt_map(&mut self, addr: u16) -> NtRead {
        let slot = ((addr as usize - 0x2000) & 0xFFF) / 0x400;
        let v = self.nt[slot & 3];
        if v >= 0xE0 {
            NtRead::Ciram((v & 1) as usize, addr as usize & 0x3FF)
        } else {
            let banks = (self.chr_len / 0x400).max(1);
            NtRead::Chr((v as usize % banks) * 0x400 + (addr as usize & 0x3FF))
        }
    }

    fn nt_write_map(&mut self, addr: u16, _val: u8) -> NtWrite {
        let slot = ((addr as usize - 0x2000) & 0xFFF) / 0x400;
        let v = self.nt[slot & 3];
        if v >= 0xE0 {
            NtWrite::Ciram((v & 1) as usize, addr as usize & 0x3FF)
        } else {
            NtWrite::Handled // CHR ROM 不可写
        }
    }

    fn mirroring(&self) -> Mirroring {
        Mirroring::Vertical // 未用:nt_map 已覆盖
    }

    fn cpu_tick(&mut self) {
        if self.irq_enable && self.irq_counter < 0x7FFF {
            self.irq_counter += 1;
            if self.irq_counter == 0x7FFF {
                self.irq_pending = true;
            }
        }
        self.audio.tick();
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }

    fn audio(&mut self) -> f32 {
        self.audio.output()
    }
}

// ---------------- Namco 175/340(mapper 210)----------------

#[derive(Serialize, Deserialize)]
pub struct N175 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr: [u8; 8],
    mirroring: Mirroring,
    /// submapper 1 = Namco 175(header 镜像);2 = 340($E000 高位控镜像)
    pub namco340: bool,
}

impl N175 {
    pub fn new(prg_len: usize, chr_len: usize, m: Mirroring, namco340: bool) -> N175 {
        N175 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 3],
            chr: [0; 8],
            mirroring: m,
            namco340,
        }
    }
}

impl MapperImpl for N175 {
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
            0 => (self.prg[0] & 0x3F) as usize % banks,
            1 => (self.prg[1] & 0x3F) as usize % banks,
            2 => (self.prg[2] & 0x3F) as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x6000..=0x7FFF => return PrgWrite::Ram((addr - 0x6000) as usize),
            0x8000..=0xBFFF => {
                let slot = ((addr - 0x8000) / 0x800) as usize;
                self.chr[slot] = val;
            }
            0xE000..=0xE7FF => {
                self.prg[0] = val & 0x3F;
                if self.namco340 {
                    self.mirroring = match val >> 6 {
                        0 => Mirroring::SingleA,
                        1 => Mirroring::Vertical,
                        2 => Mirroring::Horizontal,
                        _ => Mirroring::SingleB,
                    };
                }
            }
            0xE800..=0xEFFF => self.prg[1] = val & 0x3F,
            0xF000..=0xF7FF => self.prg[2] = val & 0x3F,
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 10) as usize & 7;
        let banks = (self.chr_len / 0x400).max(1);
        ChrTarget::Rom((self.chr[slot] as usize % banks) * 0x400 + (addr as usize & 0x3FF))
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}
