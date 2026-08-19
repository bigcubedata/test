//! 带 IRQ 或多寄存器的中坚板:
//! 18(Jaleco SS88006)、32(Irem G-101)、33/48(Taito TC0190/TC0690)、
//! 65(Irem H3001)、73(VRC3)、75(VRC1)、80(Taito X1-005)、
//! 112(NTDEC/Asder)、163(南晶 FC-001,国产原创游戏常用)。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

// ---------------- mapper 18:Jaleco SS88006 ----------------

#[derive(Serialize, Deserialize)]
pub struct Jaleco18 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr: [u8; 8],
    mirroring: Mirroring,
    irq_reload: u16,
    irq_counter: u16,
    irq_enable: bool,
    irq_size: u8, // 0:16 位,1:12,2:8,3:4
    irq_pending: bool,
}

impl Jaleco18 {
    pub fn new(prg_len: usize, chr_len: usize) -> Jaleco18 {
        Jaleco18 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 3],
            chr: [0; 8],
            mirroring: Mirroring::Vertical,
            irq_reload: 0,
            irq_counter: 0,
            irq_enable: false,
            irq_size: 0,
            irq_pending: false,
        }
    }

    fn set_nibble(r: &mut u8, val: u8, high: bool) {
        if high {
            *r = *r & 0x0F | (val & 0x0F) << 4;
        } else {
            *r = *r & 0xF0 | val & 0x0F;
        }
    }
}

impl MapperImpl for Jaleco18 {
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
            0 => self.prg[0] as usize % banks,
            1 => self.prg[1] as usize % banks,
            2 => self.prg[2] as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        let sub = (addr & 3) as usize;
        match addr & 0xF003 {
            0x8000..=0x8003 => {
                if sub < 2 {
                    Self::set_nibble(&mut self.prg[0], val, sub == 1);
                } else {
                    Self::set_nibble(&mut self.prg[1], val, sub == 3);
                }
            }
            0x9000..=0x9001 => Self::set_nibble(&mut self.prg[2], val, sub == 1),
            0xA000..=0xE003 if addr < 0xE000 => {
                let base = ((addr >> 12) - 0xA) as usize * 2 + (sub >> 1);
                Self::set_nibble(&mut self.chr[base], val, sub & 1 == 1);
            }
            0xE000..=0xE003 => {
                let shift = sub * 4;
                self.irq_reload =
                    self.irq_reload & !(0x000F << shift) | ((val & 0x0F) as u16) << shift;
            }
            0xF000 => {
                self.irq_counter = self.irq_reload;
                self.irq_pending = false;
            }
            0xF001 => {
                self.irq_enable = val & 1 != 0;
                self.irq_size = match val >> 1 & 7 {
                    s if s & 4 != 0 => 3,
                    s if s & 2 != 0 => 2,
                    s if s & 1 != 0 => 1,
                    _ => 0,
                };
                self.irq_pending = false;
            }
            0xF002 => {
                self.mirroring = match val & 3 {
                    0 => Mirroring::Horizontal,
                    1 => Mirroring::Vertical,
                    2 => Mirroring::SingleA,
                    _ => Mirroring::SingleB,
                };
            }
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

    fn cpu_tick(&mut self) {
        if !self.irq_enable {
            return;
        }
        let mask: u16 = match self.irq_size {
            3 => 0x000F,
            2 => 0x00FF,
            1 => 0x0FFF,
            _ => 0xFFFF,
        };
        let low = self.irq_counter & mask;
        if low == 0 {
            self.irq_pending = true;
            self.irq_counter = self.irq_counter & !mask | mask; // 回卷
        } else {
            self.irq_counter = self.irq_counter & !mask | (low - 1);
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}

// ---------------- mapper 32:Irem G-101 ----------------

#[derive(Serialize, Deserialize)]
pub struct Irem32 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 2],
    chr: [u8; 8],
    mode: bool,
    mirroring: Mirroring,
}

impl Irem32 {
    pub fn new(prg_len: usize, chr_len: usize) -> Irem32 {
        Irem32 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 2],
            chr: [0; 8],
            mode: false,
            mirroring: Mirroring::Vertical,
        }
    }
}

impl MapperImpl for Irem32 {
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
                if self.mode {
                    banks - 2
                } else {
                    self.prg[0] as usize % banks
                }
            }
            1 => self.prg[1] as usize % banks,
            2 => {
                if self.mode {
                    self.prg[0] as usize % banks
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
        match addr & 0xF007 {
            0x8000..=0x8007 => self.prg[0] = val & 0x1F,
            0x9000..=0x9007 => {
                self.mode = val & 2 != 0;
                self.mirroring = if val & 1 != 0 {
                    Mirroring::Horizontal
                } else {
                    Mirroring::Vertical
                };
            }
            0xA000..=0xA007 => self.prg[1] = val & 0x1F,
            0xB000..=0xB007 => self.chr[(addr & 7) as usize] = val,
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

// ---------------- mapper 33/48:Taito TC0190 / TC0690 ----------------

#[derive(Serialize, Deserialize)]
pub struct Taito33 {
    pub with_irq: bool, // 48
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 2],
    chr2k: [u8; 2],
    chr1k: [u8; 4],
    mirroring: Mirroring,
    irq_latch: u8,
    irq_counter: u8,
    irq_reload: bool,
    irq_enable: bool,
    irq_pending: bool,
    a12_prev: bool,
    a12_low_run: u16,
}

impl Taito33 {
    pub fn new(with_irq: bool, prg_len: usize, chr_len: usize) -> Taito33 {
        Taito33 {
            with_irq,
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 2],
            chr2k: [0; 2],
            chr1k: [0; 4],
            mirroring: Mirroring::Vertical,
            irq_latch: 0,
            irq_counter: 0,
            irq_reload: false,
            irq_enable: false,
            irq_pending: false,
            a12_prev: false,
            a12_low_run: 0,
        }
    }

    fn clock_irq(&mut self) {
        if self.irq_counter == 0 || self.irq_reload {
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else {
            self.irq_counter -= 1;
        }
        if self.irq_counter == 0 && self.irq_enable {
            self.irq_pending = true;
        }
    }
}

impl MapperImpl for Taito33 {
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
            0 => self.prg[0] as usize % banks,
            1 => self.prg[1] as usize % banks,
            2 => banks - 2,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xE003 {
            0x8000 => {
                self.prg[0] = val & 0x3F;
                if !self.with_irq {
                    self.mirroring = if val & 0x40 != 0 {
                        Mirroring::Horizontal
                    } else {
                        Mirroring::Vertical
                    };
                }
            }
            0x8001 => self.prg[1] = val & 0x3F,
            0x8002 => self.chr2k[0] = val,
            0x8003 => self.chr2k[1] = val,
            0xA000..=0xA003 => self.chr1k[(addr & 3) as usize] = val,
            0xC000 => self.irq_latch = val.wrapping_sub(1), // TC0690:latch = v-1(近似 XOR 行为)
            0xC001 => {
                self.irq_counter = 0;
                self.irq_reload = true;
            }
            0xC002 => self.irq_enable = true,
            0xC003 => {
                self.irq_enable = false;
                self.irq_pending = false;
            }
            0xE000 => {
                if self.with_irq {
                    self.mirroring = if val & 0x40 != 0 {
                        Mirroring::Horizontal
                    } else {
                        Mirroring::Vertical
                    };
                }
            }
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let a = addr as usize;
        let banks1k = (self.chr_len / 0x400).max(1);
        let i = if a < 0x1000 {
            let slot = a >> 11;
            ((self.chr2k[slot] as usize * 2) % banks1k) * 0x400 + (a & 0x7FF)
        } else {
            let slot = (a - 0x1000) >> 10;
            (self.chr1k[slot] as usize % banks1k) * 0x400 + (a & 0x3FF)
        };
        ChrTarget::Rom(i)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn ppu_dot(&mut self, bus_addr: u16) {
        if !self.with_irq {
            return;
        }
        let high = bus_addr & 0x1000 != 0;
        if high {
            if !self.a12_prev && self.a12_low_run >= 5 {
                self.clock_irq();
            }
            self.a12_low_run = 0;
        } else {
            self.a12_low_run = self.a12_low_run.saturating_add(1);
        }
        self.a12_prev = high;
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}

// ---------------- mapper 65:Irem H3001 ----------------

#[derive(Serialize, Deserialize)]
pub struct Irem65 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr: [u8; 8],
    mirroring: Mirroring,
    irq_reload: u16,
    irq_counter: u16,
    irq_enable: bool,
    irq_pending: bool,
}

impl Irem65 {
    pub fn new(prg_len: usize, chr_len: usize) -> Irem65 {
        Irem65 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0, 1, 0xFE],
            chr: [0; 8],
            mirroring: Mirroring::Vertical,
            irq_reload: 0,
            irq_counter: 0,
            irq_enable: false,
            irq_pending: false,
        }
    }
}

impl MapperImpl for Irem65 {
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
            0 => self.prg[0] as usize % banks,
            1 => self.prg[1] as usize % banks,
            2 => self.prg[2] as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr {
            0x8000 => self.prg[0] = val,
            0xA000 => self.prg[1] = val,
            0xC000 => self.prg[2] = val,
            0x9001 => {
                self.mirroring = if val & 0x80 != 0 {
                    Mirroring::Horizontal
                } else {
                    Mirroring::Vertical
                };
            }
            0x9003 => {
                self.irq_enable = val & 0x80 != 0;
                self.irq_pending = false;
            }
            0x9004 => {
                self.irq_counter = self.irq_reload;
                self.irq_pending = false;
            }
            0x9005 => self.irq_reload = self.irq_reload & 0x00FF | (val as u16) << 8,
            0x9006 => self.irq_reload = self.irq_reload & 0xFF00 | val as u16,
            0xB000..=0xB007 => self.chr[(addr & 7) as usize] = val,
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

    fn cpu_tick(&mut self) {
        if self.irq_enable && self.irq_counter > 0 {
            self.irq_counter -= 1;
            if self.irq_counter == 0 {
                self.irq_pending = true;
                self.irq_enable = false;
            }
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}

// ---------------- mapper 73:VRC3 ----------------

#[derive(Serialize, Deserialize)]
pub struct Vrc3 {
    prg_len: usize,
    prg: u8,
    irq_latch: u16,
    irq_counter: u16,
    irq_enable: bool,
    irq_enable_after_ack: bool,
    irq_8bit: bool,
    irq_pending: bool,
}

impl Vrc3 {
    pub fn new(prg_len: usize) -> Vrc3 {
        Vrc3 {
            prg_len,
            prg: 0,
            irq_latch: 0,
            irq_counter: 0,
            irq_enable: false,
            irq_enable_after_ack: false,
            irq_8bit: false,
            irq_pending: false,
        }
    }
}

impl MapperImpl for Vrc3 {
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
        let nib = (val & 0x0F) as u16;
        match addr & 0xF000 {
            0x8000 => self.irq_latch = self.irq_latch & 0xFFF0 | nib,
            0x9000 => self.irq_latch = self.irq_latch & 0xFF0F | nib << 4,
            0xA000 => self.irq_latch = self.irq_latch & 0xF0FF | nib << 8,
            0xB000 => self.irq_latch = self.irq_latch & 0x0FFF | nib << 12,
            0xC000 => {
                self.irq_pending = false;
                self.irq_enable_after_ack = val & 1 != 0;
                self.irq_enable = val & 2 != 0;
                self.irq_8bit = val & 4 != 0;
                if self.irq_enable {
                    self.irq_counter = self.irq_latch;
                }
            }
            0xD000 => {
                self.irq_pending = false;
                self.irq_enable = self.irq_enable_after_ack;
            }
            0xF000 => self.prg = val & 7,
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        ChrTarget::Ram(addr as usize & 0x1FFF)
    }

    fn mirroring(&self) -> Mirroring {
        Mirroring::Vertical
    }

    fn cpu_tick(&mut self) {
        if !self.irq_enable {
            return;
        }
        if self.irq_8bit {
            let low = self.irq_counter & 0xFF;
            if low == 0xFF {
                self.irq_pending = true;
                self.irq_counter = self.irq_counter & 0xFF00 | self.irq_latch & 0xFF;
            } else {
                self.irq_counter += 1;
            }
        } else if self.irq_counter == 0xFFFF {
            self.irq_pending = true;
            self.irq_counter = self.irq_latch;
        } else {
            self.irq_counter += 1;
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}

// ---------------- mapper 75:VRC1 ----------------

#[derive(Serialize, Deserialize)]
pub struct Vrc1 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr: [u8; 2],
    mirroring: Mirroring,
}

impl Vrc1 {
    pub fn new(prg_len: usize, chr_len: usize) -> Vrc1 {
        Vrc1 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 3],
            chr: [0; 2],
            mirroring: Mirroring::Vertical,
        }
    }
}

impl MapperImpl for Vrc1 {
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
            0 => self.prg[0] as usize % banks,
            1 => self.prg[1] as usize % banks,
            2 => self.prg[2] as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xF000 {
            0x8000 => self.prg[0] = val & 0x0F,
            0x9000 => {
                self.mirroring = if val & 1 != 0 {
                    Mirroring::Horizontal
                } else {
                    Mirroring::Vertical
                };
                self.chr[0] = self.chr[0] & 0x0F | (val >> 1 & 1) << 4;
                self.chr[1] = self.chr[1] & 0x0F | (val >> 2 & 1) << 4;
            }
            0xA000 => self.prg[1] = val & 0x0F,
            0xC000 => self.prg[2] = val & 0x0F,
            0xE000 => self.chr[0] = self.chr[0] & 0x10 | val & 0x0F,
            0xF000 => self.chr[1] = self.chr[1] & 0x10 | val & 0x0F,
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let side = (addr >> 12) as usize & 1;
        let banks = (self.chr_len / 0x1000).max(1);
        ChrTarget::Rom((self.chr[side] as usize % banks) * 0x1000 + (addr as usize & 0xFFF))
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- mapper 80:Taito X1-005 ----------------

#[derive(Serialize, Deserialize)]
pub struct Taito80 {
    prg_len: usize,
    chr_len: usize,
    prg: [u8; 3],
    chr2k: [u8; 2],
    chr1k: [u8; 4],
    mirroring: Mirroring,
    ram_enable: bool,
}

impl Taito80 {
    pub fn new(prg_len: usize, chr_len: usize) -> Taito80 {
        Taito80 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: [0; 3],
            chr2k: [0; 2],
            chr1k: [0; 4],
            mirroring: Mirroring::Vertical,
            ram_enable: false,
        }
    }
}

impl MapperImpl for Taito80 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        // X1-005 的 128 字节内部 RAM 映射在 $7F00-$7FFF
        if (0x7F00..0x8000).contains(&addr) {
            if self.ram_enable {
                return PrgTarget::Ram((addr & 0x7F) as usize);
            }
            return PrgTarget::None;
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x2000).max(1);
        let off = addr as usize & 0x1FFF;
        let bank = match (addr >> 13) & 3 {
            0 => self.prg[0] as usize % banks,
            1 => self.prg[1] as usize % banks,
            2 => self.prg[2] as usize % banks,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x7EF0 => self.chr2k[0] = val,
            0x7EF1 => self.chr2k[1] = val,
            0x7EF2..=0x7EF5 => self.chr1k[(addr - 0x7EF2) as usize] = val,
            0x7EF6 | 0x7EF7 => {
                self.mirroring = if val & 1 != 0 {
                    Mirroring::Vertical
                } else {
                    Mirroring::Horizontal
                };
            }
            0x7EF8 | 0x7EF9 => self.ram_enable = val == 0xA3,
            0x7EFA | 0x7EFB => self.prg[0] = val,
            0x7EFC | 0x7EFD => self.prg[1] = val,
            0x7EFE | 0x7EFF => self.prg[2] = val,
            0x7F00..=0x7FFF => {
                if self.ram_enable {
                    return PrgWrite::Ram((addr & 0x7F) as usize);
                }
            }
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let a = addr as usize;
        let banks1k = (self.chr_len / 0x400).max(1);
        let i = if a < 0x1000 {
            let slot = a >> 11;
            ((self.chr2k[slot] as usize) % banks1k) * 0x400 + (a & 0x7FF)
        } else {
            let slot = (a - 0x1000) >> 10;
            (self.chr1k[slot] as usize % banks1k) * 0x400 + (a & 0x3FF)
        };
        ChrTarget::Rom(i)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- mapper 112:NTDEC/Asder ----------------

#[derive(Serialize, Deserialize)]
pub struct Asder112 {
    prg_len: usize,
    chr_len: usize,
    select: u8,
    regs: [u8; 8],
    mirroring: Mirroring,
}

impl Asder112 {
    pub fn new(prg_len: usize, chr_len: usize) -> Asder112 {
        Asder112 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            select: 0,
            regs: [0; 8],
            mirroring: Mirroring::Vertical,
        }
    }
}

impl MapperImpl for Asder112 {
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
            0 => self.regs[0] as usize % banks,
            1 => self.regs[1] as usize % banks,
            2 => banks - 2,
            _ => banks - 1,
        };
        PrgTarget::Rom(bank * 0x2000 + off)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xE001 {
            0x8000 => self.select = val & 7,
            0xA000 => self.regs[self.select as usize] = val,
            0xE000 => {
                self.mirroring = if val & 1 != 0 {
                    Mirroring::Horizontal
                } else {
                    Mirroring::Vertical
                };
            }
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let a = addr as usize;
        let banks1k = (self.chr_len / 0x400).max(1);
        let i = if a < 0x1000 {
            let slot = 2 + (a >> 11);
            ((self.regs[slot] & 0xFE) as usize % banks1k) * 0x400 + (a & 0x7FF)
        } else {
            let slot = 4 + ((a - 0x1000) >> 10);
            (self.regs[slot] as usize % banks1k) * 0x400 + (a & 0x3FF)
        };
        ChrTarget::Rom(i)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- mapper 163:南晶 FC-001(国产原创游戏)----------------

#[derive(Serialize, Deserialize)]
pub struct Nanjing163 {
    prg_len: usize,
    reg: [u8; 4], // $5000/$5100/$5200/$5300
    security: u8,
    trigger: bool,
    /// 自动 CHR RAM 半屏切换(标题动画用)
    auto_switch: bool,
    scanline: u16,
    a12_prev: bool,
    a12_low_run: u16,
    chr_half: usize,
}

impl Nanjing163 {
    pub fn new(prg_len: usize) -> Nanjing163 {
        Nanjing163 {
            prg_len,
            reg: [0; 4],
            security: 0,
            trigger: false,
            auto_switch: false,
            scanline: 0,
            a12_prev: false,
            a12_low_run: 0,
            chr_half: 0,
        }
    }
}

impl MapperImpl for Nanjing163 {
    fn cpu_map(&mut self, addr: u16) -> PrgTarget {
        match addr {
            0x5100..=0x51FF => PrgTarget::Value(self.security),
            0x5500..=0x55FF => PrgTarget::Value(if self.trigger { self.security } else { 0 }),
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
        let banks = (self.prg_len / 0x8000).max(1);
        let bank = ((self.reg[0] & 0x0F) as usize | ((self.reg[2] & 0x0F) as usize) << 4) % banks;
        PrgTarget::Rom(bank * 0x8000 + (addr as usize & 0x7FFF))
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x5000..=0x50FF => {
                self.reg[0] = val;
                self.auto_switch = val & 0x80 != 0;
            }
            0x5100..=0x51FF => {
                if val == 6 {
                    self.trigger = false;
                }
            }
            0x5200..=0x52FF => self.reg[2] = val,
            0x5300..=0x53FF => self.security = val,
            0x5400..=0x54FF => self.trigger = true,
            0x6000..=0x7FFF => return PrgWrite::Ram((addr - 0x6000) as usize),
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        // 8K CHR RAM;auto_switch 时整个 pattern 空间指向当前 4K 半区(中屏切换)
        let a = addr as usize & 0x1FFF;
        if self.auto_switch {
            ChrTarget::Ram(self.chr_half * 0x1000 + (a & 0x0FFF))
        } else {
            ChrTarget::Ram(a)
        }
    }

    fn ppu_dot(&mut self, bus_addr: u16) {
        // 用 A12 波形近似扫描线计数:239 行分界切半区
        let high = bus_addr & 0x1000 != 0;
        if high {
            if !self.a12_prev && self.a12_low_run >= 5 {
                self.scanline += 1;
                if self.scanline >= 241 {
                    self.scanline = 0;
                }
                self.chr_half = if self.scanline < 128 { 0 } else { 1 };
            }
            self.a12_low_run = 0;
        } else {
            self.a12_low_run = self.a12_low_run.saturating_add(1);
        }
        self.a12_prev = high;
    }

    fn mirroring(&self) -> Mirroring {
        Mirroring::Vertical
    }
}
