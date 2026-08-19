//! Mapper trait 与枚举分派,以及一批 discrete 逻辑简单 mapper。
//!
//! 枚举而非 trait object:serde 直接派生、无虚表开销、匹配分支可内联。

use super::{mmc1::Mmc1, mmc3::Mmc3, Mirroring, RomError};
use serde::{Deserialize, Serialize};

/// CPU $4020-$FFFF 的翻译结果。
pub enum PrgTarget {
    Rom(usize),
    Ram(usize),
    Value(u8),
    None,
}

/// PPU $0000-$1FFF 的翻译结果。
pub enum ChrTarget {
    Rom(usize),
    Ram(usize),
}

/// CPU 写 $4020-$FFFF 的处理结果。
pub enum PrgWrite {
    Handled,
    Ram(usize),
}

pub trait MapperImpl {
    /// 读地址翻译(允许副作用;无副作用的 mapper 直接转发 peek)。
    fn cpu_map(&mut self, addr: u16) -> PrgTarget {
        self.cpu_peek(addr)
    }
    fn cpu_peek(&self, addr: u16) -> PrgTarget;
    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite;
    fn ppu_map(&mut self, addr: u16) -> ChrTarget;
    fn mirroring(&self) -> Mirroring;
    /// 每个 CPU 周期一次(VRC/FME-7 类 IRQ 计数)。
    fn cpu_tick(&mut self) {}
    /// PPU 总线每次出现地址时通知(MMC3 A12、MMC2 latch 等)。
    fn ppu_addr_notify(&mut self, _addr: u16, _ppu_cycle: u64) {}
    fn irq_asserted(&self) -> bool {
        false
    }
    /// 扩展音源输出(线性混入 APU)。
    fn audio(&mut self) -> f32 {
        0.0
    }
}

#[derive(Serialize, Deserialize)]
pub enum Mapper {
    Nrom(Nrom),
    Mmc1(Mmc1),
    Uxrom(Uxrom),
    Cnrom(Cnrom),
    Mmc3(Mmc3),
    Axrom(Axrom),
    Gxrom(Gxrom),
    ColorDreams(ColorDreams),
    Camerica(Camerica),
}

macro_rules! delegate {
    ($self:ident, $m:ident => $e:expr) => {
        match $self {
            Mapper::Nrom($m) => $e,
            Mapper::Mmc1($m) => $e,
            Mapper::Uxrom($m) => $e,
            Mapper::Cnrom($m) => $e,
            Mapper::Mmc3($m) => $e,
            Mapper::Axrom($m) => $e,
            Mapper::Gxrom($m) => $e,
            Mapper::ColorDreams($m) => $e,
            Mapper::Camerica($m) => $e,
        }
    };
}

impl Mapper {
    pub fn new(
        number: u16,
        submapper: u8,
        prg_len: usize,
        chr_len: usize,
        header_mirroring: Mirroring,
    ) -> Result<Mapper, RomError> {
        let chr_ram = chr_len == 0;
        Ok(match number {
            0 => Mapper::Nrom(Nrom {
                prg_len,
                chr_ram,
                mirroring: header_mirroring,
            }),
            1 => Mapper::Mmc1(Mmc1::new(prg_len, chr_len, chr_ram)),
            2 => Mapper::Uxrom(Uxrom {
                prg_len,
                chr_ram: true, // UxROM 全部 CHR RAM;若头带 CHR ROM 也照常工作
                bank: 0,
                conflicts: submapper != 1,
                mirroring: header_mirroring,
                fixed_first: false,
            }),
            180 => Mapper::Uxrom(Uxrom {
                // Crazy Climber:固定第一个 bank,切换 $C000
                prg_len,
                chr_ram: true,
                bank: 0,
                conflicts: false,
                mirroring: header_mirroring,
                fixed_first: true,
            }),
            3 => Mapper::Cnrom(Cnrom {
                prg_len,
                chr_ram,
                bank: 0,
                conflicts: submapper != 1,
                mirroring: header_mirroring,
            }),
            4 => Mapper::Mmc3(Mmc3::new(prg_len, header_mirroring)),
            7 => Mapper::Axrom(Axrom {
                prg_len,
                chr_ram,
                bank: 0,
                screen_b: false,
                conflicts: submapper == 2,
            }),
            66 => Mapper::Gxrom(Gxrom {
                prg_len,
                chr_ram,
                prg_bank: 0,
                chr_bank: 0,
                mirroring: header_mirroring,
            }),
            11 => Mapper::ColorDreams(ColorDreams {
                prg_len,
                chr_ram,
                prg_bank: 0,
                chr_bank: 0,
                mirroring: header_mirroring,
            }),
            71 => Mapper::Camerica(Camerica {
                prg_len,
                bank: 0,
                mirroring: header_mirroring,
                fire_hawk: submapper == 1,
            }),
            n => return Err(RomError::UnsupportedMapper(n)),
        })
    }

    pub fn cpu_map(&mut self, addr: u16) -> PrgTarget {
        delegate!(self, m => m.cpu_map(addr))
    }
    pub fn cpu_peek(&self, addr: u16) -> PrgTarget {
        delegate!(self, m => m.cpu_peek(addr))
    }
    pub fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        delegate!(self, m => m.cpu_write(addr, val, rom_at))
    }
    pub fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        delegate!(self, m => m.ppu_map(addr))
    }
    pub fn mirroring(&self) -> Mirroring {
        delegate!(self, m => m.mirroring())
    }
    pub fn cpu_tick(&mut self) {
        delegate!(self, m => m.cpu_tick())
    }
    pub fn ppu_addr_notify(&mut self, addr: u16, ppu_cycle: u64) {
        delegate!(self, m => m.ppu_addr_notify(addr, ppu_cycle))
    }
    pub fn irq_asserted(&self) -> bool {
        delegate!(self, m => m.irq_asserted())
    }
    pub fn audio(&mut self) -> f32 {
        delegate!(self, m => m.audio())
    }
}

/// $6000-$7FFF → PRG RAM,$8000+ 由调用者处理的公共小工具。
fn prg_ram_or(addr: u16) -> Option<PrgTarget> {
    if (0x6000..0x8000).contains(&addr) {
        Some(PrgTarget::Ram((addr - 0x6000) as usize))
    } else if addr < 0x8000 {
        Some(PrgTarget::None)
    } else {
        None
    }
}

fn chr(chr_ram: bool, index: usize) -> ChrTarget {
    if chr_ram {
        ChrTarget::Ram(index)
    } else {
        ChrTarget::Rom(index)
    }
}

// ---------------- Mapper 0: NROM ----------------

#[derive(Serialize, Deserialize)]
pub struct Nrom {
    prg_len: usize,
    chr_ram: bool,
    mirroring: Mirroring,
}

impl MapperImpl for Nrom {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len)
    }
    fn cpu_write(&mut self, addr: u16, _val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            PrgWrite::Ram((addr - 0x6000) as usize)
        } else {
            PrgWrite::Handled
        }
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(self.chr_ram, addr as usize)
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- Mapper 2 / 180: UxROM ----------------

#[derive(Serialize, Deserialize)]
pub struct Uxrom {
    prg_len: usize,
    chr_ram: bool,
    bank: u8,
    conflicts: bool,
    mirroring: Mirroring,
    /// mapper 180(Crazy Climber):固定 bank 在 $8000,可切在 $C000
    fixed_first: bool,
}

impl MapperImpl for Uxrom {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        let banks = (self.prg_len / 0x4000).max(1);
        let off = (addr as usize) & 0x3FFF;
        let bank = if self.fixed_first {
            if addr < 0xC000 {
                0
            } else {
                self.bank as usize % banks
            }
        } else if addr < 0xC000 {
            self.bank as usize % banks
        } else {
            banks - 1
        };
        PrgTarget::Rom(bank * 0x4000 + off)
    }
    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            self.bank = if self.conflicts { val & rom_at } else { val };
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(self.chr_ram, addr as usize)
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- Mapper 3: CNROM ----------------

#[derive(Serialize, Deserialize)]
pub struct Cnrom {
    prg_len: usize,
    chr_ram: bool,
    bank: u8,
    conflicts: bool,
    mirroring: Mirroring,
}

impl MapperImpl for Cnrom {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len)
    }
    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            self.bank = if self.conflicts { val & rom_at } else { val };
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(
            self.chr_ram,
            (self.bank as usize) * 0x2000 + (addr as usize & 0x1FFF),
        )
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- Mapper 7: AxROM ----------------

#[derive(Serialize, Deserialize)]
pub struct Axrom {
    prg_len: usize,
    chr_ram: bool,
    bank: u8,
    screen_b: bool,
    conflicts: bool,
}

impl MapperImpl for Axrom {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        let banks = (self.prg_len / 0x8000).max(1);
        PrgTarget::Rom((self.bank as usize % banks) * 0x8000 + (addr as usize & 0x7FFF))
    }
    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            let v = if self.conflicts { val & rom_at } else { val };
            self.bank = v & 0x0F;
            self.screen_b = v & 0x10 != 0;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(self.chr_ram, addr as usize)
    }
    fn mirroring(&self) -> Mirroring {
        if self.screen_b {
            Mirroring::SingleB
        } else {
            Mirroring::SingleA
        }
    }
}

// ---------------- Mapper 66: GxROM ----------------

#[derive(Serialize, Deserialize)]
pub struct Gxrom {
    prg_len: usize,
    chr_ram: bool,
    prg_bank: u8,
    chr_bank: u8,
    mirroring: Mirroring,
}

impl MapperImpl for Gxrom {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        let banks = (self.prg_len / 0x8000).max(1);
        PrgTarget::Rom((self.prg_bank as usize % banks) * 0x8000 + (addr as usize & 0x7FFF))
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            self.prg_bank = (val >> 4) & 0x03;
            self.chr_bank = val & 0x03;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(
            self.chr_ram,
            (self.chr_bank as usize) * 0x2000 + (addr as usize & 0x1FFF),
        )
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- Mapper 11: Color Dreams ----------------

#[derive(Serialize, Deserialize)]
pub struct ColorDreams {
    prg_len: usize,
    chr_ram: bool,
    prg_bank: u8,
    chr_bank: u8,
    mirroring: Mirroring,
}

impl MapperImpl for ColorDreams {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        let banks = (self.prg_len / 0x8000).max(1);
        PrgTarget::Rom((self.prg_bank as usize % banks) * 0x8000 + (addr as usize & 0x7FFF))
    }
    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr >= 0x8000 {
            let v = val & rom_at; // Color Dreams 板有总线冲突
            self.prg_bank = v & 0x03;
            self.chr_bank = v >> 4;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        chr(
            self.chr_ram,
            (self.chr_bank as usize) * 0x2000 + (addr as usize & 0x1FFF),
        )
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

// ---------------- Mapper 71: Camerica ----------------

#[derive(Serialize, Deserialize)]
pub struct Camerica {
    prg_len: usize,
    bank: u8,
    mirroring: Mirroring,
    fire_hawk: bool,
}

impl MapperImpl for Camerica {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if let Some(t) = prg_ram_or(addr) {
            return t;
        }
        let banks = (self.prg_len / 0x4000).max(1);
        let off = (addr as usize) & 0x3FFF;
        if addr < 0xC000 {
            PrgTarget::Rom((self.bank as usize % banks) * 0x4000 + off)
        } else {
            PrgTarget::Rom((banks - 1) * 0x4000 + off)
        }
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr {
            0x8000..=0x9FFF if self.fire_hawk => {
                self.mirroring = if val & 0x10 != 0 {
                    Mirroring::SingleB
                } else {
                    Mirroring::SingleA
                };
            }
            0xC000..=0xFFFF => self.bank = val,
            _ => {}
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        ChrTarget::Ram(addr as usize)
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}
