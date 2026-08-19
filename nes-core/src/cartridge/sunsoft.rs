//! Sunsoft 系:
//! - FME-7 / Sunsoft 5B(mapper 69,Gimmick!):全能 banking + 16 位周期 IRQ + AY 子集音源
//! - Sunsoft-3(mapper 67):16 位 IRQ(两次写装载)
//! - Sunsoft-4(mapper 68):NT 可指向 CHR ROM(After Burner II)

use super::mapper::{ChrTarget, MapperImpl, NtRead, NtWrite, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

// ---------------- 5B 音源(AY-3-8910 子集) ----------------

#[derive(Serialize, Deserialize)]
pub struct Ay38910 {
    regs: [u8; 16],
    sel: u8,
    tone_counters: [u16; 3],
    tone_out: [bool; 3],
    noise_counter: u16,
    noise_lfsr: u32,
    env_counter: u32,
    env_step: u8,
    env_hold: bool,
    env_alt: bool,
    divider: u8,
}

impl Default for Ay38910 {
    fn default() -> Ay38910 {
        Ay38910 {
            regs: [0; 16],
            sel: 0,
            tone_counters: [0; 3],
            tone_out: [false; 3],
            noise_counter: 0,
            noise_lfsr: 1,
            env_counter: 0,
            env_step: 0,
            env_hold: false,
            env_alt: false,
            divider: 0,
        }
    }
}

impl Ay38910 {
    pub fn select(&mut self, v: u8) {
        self.sel = v & 0x0F;
    }

    pub fn write(&mut self, v: u8) {
        self.regs[self.sel as usize] = v;
        if self.sel == 13 {
            // 包络重启
            self.env_step = 0;
            self.env_counter = 0;
            self.env_hold = false;
            self.env_alt = false;
        }
    }

    fn tone_period(&self, ch: usize) -> u16 {
        let lo = self.regs[ch * 2] as u16;
        let hi = (self.regs[ch * 2 + 1] & 0x0F) as u16;
        (hi << 8 | lo).max(1)
    }

    /// 每 CPU 周期;内部再 /16 得 AY 时基。
    fn tick(&mut self) {
        self.divider += 1;
        if self.divider < 16 {
            return;
        }
        self.divider = 0;
        for ch in 0..3 {
            self.tone_counters[ch] += 1;
            if self.tone_counters[ch] >= self.tone_period(ch) {
                self.tone_counters[ch] = 0;
                self.tone_out[ch] = !self.tone_out[ch];
            }
        }
        let np = (self.regs[6] & 0x1F).max(1) as u16;
        self.noise_counter += 1;
        if self.noise_counter >= np {
            self.noise_counter = 0;
            let fb = (self.noise_lfsr ^ self.noise_lfsr >> 3) & 1;
            self.noise_lfsr = self.noise_lfsr >> 1 | fb << 16;
        }
        // 包络
        let ep = ((self.regs[12] as u32) << 8 | self.regs[11] as u32).max(1);
        self.env_counter += 1;
        if self.env_counter >= ep {
            self.env_counter = 0;
            if !self.env_hold {
                self.env_step += 1;
                if self.env_step > 15 {
                    let shape = self.regs[13] & 0x0F;
                    let cont = shape & 8 != 0;
                    let att = shape & 4 != 0;
                    let alt = shape & 2 != 0;
                    let hold = shape & 1 != 0;
                    let _ = att;
                    if !cont || hold {
                        self.env_hold = true;
                        self.env_step = 15;
                        if !cont {
                            self.env_alt = true; // 停在 0
                        } else if alt {
                            self.env_alt = !self.env_alt;
                        }
                    } else {
                        self.env_step = 0;
                        if alt {
                            self.env_alt = !self.env_alt;
                        }
                    }
                }
            }
        }
    }

    fn env_level(&self) -> u8 {
        let shape = self.regs[13] & 0x0F;
        let attack = shape & 4 != 0;
        let mut s = self.env_step.min(15);
        let mut rising = attack;
        if self.env_alt {
            rising = !rising;
        }
        if !rising {
            s = 15 - s;
        }
        s
    }

    fn output(&self) -> f32 {
        let mut sum = 0.0f32;
        let enables = self.regs[7];
        let noise_bit = self.noise_lfsr & 1 != 0;
        for ch in 0..3 {
            let tone_on = enables >> ch & 1 == 0;
            let noise_on = enables >> (ch + 3) & 1 == 0;
            let mut high = true;
            if tone_on {
                high &= self.tone_out[ch];
            }
            if noise_on {
                high &= noise_bit;
            }
            if !tone_on && !noise_on {
                high = true;
            }
            if high {
                let vreg = self.regs[8 + ch];
                let level = if vreg & 0x10 != 0 {
                    self.env_level()
                } else {
                    vreg & 0x0F
                };
                // 近似 3dB/级的对数音量
                if level > 0 {
                    sum += (2f32).powf((level as f32 - 15.0) / 2.0);
                }
            }
        }
        sum * 0.16
    }
}

// ---------------- FME-7 / 5B(mapper 69)----------------

#[derive(Serialize, Deserialize)]
pub struct Fme7 {
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    command: u8,
    chr: [u8; 8],
    prg6000: u8, // bit6 = RAM,bit7 = enable
    prg: [u8; 3],
    mirroring: Mirroring,
    irq_enable: bool,
    irq_count_enable: bool,
    irq_counter: u16,
    irq_pending: bool,
    pub ay: Ay38910,
}

impl Fme7 {
    pub fn new(prg_len: usize, chr_len: usize) -> Fme7 {
        Fme7 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram: chr_len == 0,
            command: 0,
            chr: [0; 8],
            prg6000: 0,
            prg: [0; 3],
            mirroring: Mirroring::Vertical,
            irq_enable: false,
            irq_count_enable: false,
            irq_counter: 0,
            irq_pending: false,
            ay: Ay38910::default(),
        }
    }
}

impl MapperImpl for Fme7 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        let banks = (self.prg_len / 0x2000).max(1);
        if (0x6000..0x8000).contains(&addr) {
            let off = (addr - 0x6000) as usize;
            if self.prg6000 & 0x40 != 0 {
                if self.prg6000 & 0x80 != 0 {
                    return PrgTarget::Ram((self.prg6000 as usize & 7) * 0x2000 + off);
                }
                return PrgTarget::None; // RAM 未使能
            }
            return PrgTarget::Rom(((self.prg6000 & 0x3F) as usize % banks) * 0x2000 + off);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
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
            0x6000..=0x7FFF => {
                if self.prg6000 & 0xC0 == 0xC0 {
                    return PrgWrite::Ram(
                        (self.prg6000 as usize & 7) * 0x2000 + (addr - 0x6000) as usize,
                    );
                }
            }
            0x8000..=0x9FFF => self.command = val & 0x0F,
            0xA000..=0xBFFF => match self.command {
                0..=7 => self.chr[self.command as usize] = val,
                8 => self.prg6000 = val,
                9..=0xB => self.prg[self.command as usize - 9] = val & 0x3F,
                0xC => {
                    self.mirroring = match val & 3 {
                        0 => Mirroring::Vertical,
                        1 => Mirroring::Horizontal,
                        2 => Mirroring::SingleA,
                        _ => Mirroring::SingleB,
                    }
                }
                0xD => {
                    self.irq_enable = val & 1 != 0;
                    self.irq_count_enable = val & 0x80 != 0;
                    self.irq_pending = false;
                }
                0xE => self.irq_counter = self.irq_counter & 0xFF00 | val as u16,
                _ => self.irq_counter = self.irq_counter & 0x00FF | (val as u16) << 8,
            },
            0xC000..=0xDFFF => self.ay.select(val),
            0xE000..=0xFFFF => self.ay.write(val),
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
        if self.irq_count_enable {
            let (n, overflow) = self.irq_counter.overflowing_sub(1);
            self.irq_counter = n;
            if overflow && self.irq_enable {
                self.irq_pending = true;
            }
        }
        self.ay.tick();
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }

    fn audio(&mut self) -> f32 {
        self.ay.output()
    }
}

// ---------------- Sunsoft-3(mapper 67)----------------

#[derive(Serialize, Deserialize)]
pub struct Sunsoft3 {
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: [u8; 4],
    mirroring: Mirroring,
    irq_enable: bool,
    irq_counter: u16,
    irq_pending: bool,
    irq_write_hi: bool,
}

impl Sunsoft3 {
    pub fn new(prg_len: usize, chr_len: usize) -> Sunsoft3 {
        Sunsoft3 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: [0; 4],
            mirroring: Mirroring::Vertical,
            irq_enable: false,
            irq_counter: 0,
            irq_pending: false,
            irq_write_hi: true,
        }
    }
}

impl MapperImpl for Sunsoft3 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x4000).max(1);
        let off = addr as usize & 0x3FFF;
        if addr < 0xC000 {
            PrgTarget::Rom((self.prg as usize % banks) * 0x4000 + off)
        } else {
            PrgTarget::Rom((banks - 1) * 0x4000 + off)
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xF800 {
            0x8800 => self.chr[0] = val & 0x3F,
            0x9800 => self.chr[1] = val & 0x3F,
            0xA800 => self.chr[2] = val & 0x3F,
            0xB800 => self.chr[3] = val & 0x3F,
            0xC800 => {
                if self.irq_write_hi {
                    self.irq_counter = self.irq_counter & 0x00FF | (val as u16) << 8;
                } else {
                    self.irq_counter = self.irq_counter & 0xFF00 | val as u16;
                }
                self.irq_write_hi = !self.irq_write_hi;
            }
            0xD800 => {
                self.irq_enable = val & 0x10 != 0;
                self.irq_write_hi = true;
                self.irq_pending = false;
            }
            0xE800 => {
                self.mirroring = match val & 3 {
                    0 => Mirroring::Vertical,
                    1 => Mirroring::Horizontal,
                    2 => Mirroring::SingleA,
                    _ => Mirroring::SingleB,
                }
            }
            0xF800 => self.prg = val & 0x0F,
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 11) as usize & 3;
        let banks = (self.chr_len / 0x800).max(1);
        ChrTarget::Rom((self.chr[slot] as usize % banks) * 0x800 + (addr as usize & 0x7FF))
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn cpu_tick(&mut self) {
        if self.irq_enable {
            let (n, overflow) = self.irq_counter.overflowing_sub(1);
            self.irq_counter = n;
            if overflow {
                self.irq_pending = true;
                self.irq_enable = false;
            }
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}

// ---------------- Sunsoft-4(mapper 68)----------------

#[derive(Serialize, Deserialize)]
pub struct Sunsoft4 {
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: [u8; 4],
    nt_banks: [u8; 2],
    nt_from_chr: bool,
    mirroring: Mirroring,
}

impl Sunsoft4 {
    pub fn new(prg_len: usize, chr_len: usize) -> Sunsoft4 {
        Sunsoft4 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: [0; 4],
            nt_banks: [0; 2],
            nt_from_chr: false,
            mirroring: Mirroring::Vertical,
        }
    }

    fn nt_page(&mut self, addr: u16) -> NtRead {
        let (p, o) = super::mapper::standard_nt(self.mirroring, addr);
        if self.nt_from_chr {
            let bank = (self.nt_banks[p & 1] as usize | 0x80) & 0xFF;
            let banks = (self.chr_len / 0x400).max(1);
            NtRead::Chr((bank % banks) * 0x400 + o)
        } else {
            NtRead::Ciram(p & 1, o)
        }
    }
}

impl MapperImpl for Sunsoft4 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x4000).max(1);
        let off = addr as usize & 0x3FFF;
        if addr < 0xC000 {
            PrgTarget::Rom((self.prg as usize & 0x0F).min(banks - 1) * 0x4000 + off)
        } else {
            PrgTarget::Rom((banks - 1) * 0x4000 + off)
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xF000 {
            0x8000 => self.chr[0] = val,
            0x9000 => self.chr[1] = val,
            0xA000 => self.chr[2] = val,
            0xB000 => self.chr[3] = val,
            0xC000 => self.nt_banks[0] = val | 0x80,
            0xD000 => self.nt_banks[1] = val | 0x80,
            0xE000 => {
                self.mirroring = match val & 3 {
                    0 => Mirroring::Vertical,
                    1 => Mirroring::Horizontal,
                    2 => Mirroring::SingleA,
                    _ => Mirroring::SingleB,
                };
                self.nt_from_chr = val & 0x10 != 0;
            }
            0xF000 => self.prg = val & 0x0F,
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let slot = (addr >> 11) as usize & 3;
        let banks = (self.chr_len / 0x800).max(1);
        ChrTarget::Rom((self.chr[slot] as usize % banks) * 0x800 + (addr as usize & 0x7FF))
    }

    fn nt_map(&mut self, addr: u16) -> NtRead {
        self.nt_page(addr)
    }

    fn nt_write_map(&mut self, addr: u16, _val: u8) -> NtWrite {
        match self.nt_page(addr) {
            NtRead::Ciram(p, o) => NtWrite::Ciram(p, o),
            _ => NtWrite::Handled,
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}
