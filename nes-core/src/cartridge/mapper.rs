//! Mapper trait 与枚举分派,以及一批 discrete 逻辑简单 mapper。
//!
//! 枚举而非 trait object:serde 直接派生、无虚表开销、匹配分支可内联。

use super::irq_boards::{Asder112, Irem32, Irem65, Jaleco18, Nanjing163, Taito33, Taito80, Vrc1, Vrc3};
use super::misc::{simple_latch_for, Jaleco7292, M184, M185, M86, M87, M89, Nina001, SimpleLatch};
use super::mmc2::Mmc2;
use super::mmc3::{Mmc3, Mmc3Variant};
use super::mmc5::Mmc5;
use super::namco::{Namco108, N163, N175};
use super::sunsoft::{Fme7, Sunsoft3, Sunsoft4};
use super::vrc::{Vrc24, Vrc6};
use super::vrc7::Vrc7;
use super::{mmc1::Mmc1, Mirroring, RomError};
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

/// Nametable 读地址翻译(MMC5/N163/Sunsoft-4 可指到 ExRAM/CHR/填充值)。
pub enum NtRead {
    Ciram(usize, usize),
    Ext(usize, usize),
    Chr(usize),
    Value(u8),
}

/// Nametable 写翻译。
pub enum NtWrite {
    Ciram(usize, usize),
    Ext(usize, usize),
    Chr(usize),
    Handled,
}

/// 头部镜像的标准翻译。
pub fn standard_nt(m: Mirroring, addr: u16) -> (usize, usize) {
    let a = (addr as usize).wrapping_sub(0x2000) & 0xFFF;
    let table = a / 0x400;
    let off = a & 0x3FF;
    let page = match m {
        Mirroring::Horizontal => table >> 1,
        Mirroring::Vertical => table & 1,
        Mirroring::SingleA => 0,
        Mirroring::SingleB => 1,
        Mirroring::FourScreen => table,
    };
    (page, off)
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
    /// PPU 总线每次真实读写时通知(MMC2/MMC4 latch、MMC5 取数流)。
    fn ppu_addr_notify(&mut self, _addr: u16, _ppu_cycle: u64) {}
    /// 每个 PPU dot 一次,携带当前保持在地址总线上的地址(MMC3 的 A12 波形)。
    fn ppu_dot(&mut self, _bus_addr: u16) {}
    /// $2000/$2001 写入时同步(MMC5 需要精灵尺寸与渲染开关)。
    fn ppu_ctrl_update(&mut self, _ctrl: u8, _mask: u8) {}
    /// Nametable 翻译;默认按 mirroring()。
    fn nt_map(&mut self, addr: u16) -> NtRead {
        let (p, o) = standard_nt(self.mirroring(), addr);
        if p < 2 {
            NtRead::Ciram(p, o)
        } else {
            NtRead::Ext(p - 2, o)
        }
    }
    fn nt_write_map(&mut self, addr: u16, _val: u8) -> NtWrite {
        let (p, o) = standard_nt(self.mirroring(), addr);
        if p < 2 {
            NtWrite::Ciram(p, o)
        } else {
            NtWrite::Ext(p - 2, o)
        }
    }
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
    Mmc2(Mmc2),
    Mmc5(Mmc5),
    N163(N163),
    N175(N175),
    Namco108(Namco108),
    Fme7(Fme7),
    Sunsoft3(Sunsoft3),
    Sunsoft4(Sunsoft4),
    Vrc24(Vrc24),
    Vrc6(Vrc6),
    Vrc7(Vrc7),
    SimpleLatch(SimpleLatch),
    Nina001(Nina001),
    M86(M86),
    M87(M87),
    M89(M89),
    M184(M184),
    M185(M185),
    Jaleco7292(Jaleco7292),
    Jaleco18(Jaleco18),
    Irem32(Irem32),
    Irem65(Irem65),
    Taito33(Taito33),
    Taito80(Taito80),
    Vrc1(Vrc1),
    Vrc3(Vrc3),
    Asder112(Asder112),
    Nanjing163(Nanjing163),
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
            Mapper::Mmc2($m) => $e,
            Mapper::Mmc5($m) => $e,
            Mapper::N163($m) => $e,
            Mapper::N175($m) => $e,
            Mapper::Namco108($m) => $e,
            Mapper::Fme7($m) => $e,
            Mapper::Sunsoft3($m) => $e,
            Mapper::Sunsoft4($m) => $e,
            Mapper::Vrc24($m) => $e,
            Mapper::Vrc6($m) => $e,
            Mapper::Vrc7($m) => $e,
            Mapper::SimpleLatch($m) => $e,
            Mapper::Nina001($m) => $e,
            Mapper::M86($m) => $e,
            Mapper::M87($m) => $e,
            Mapper::M89($m) => $e,
            Mapper::M184($m) => $e,
            Mapper::M185($m) => $e,
            Mapper::Jaleco7292($m) => $e,
            Mapper::Jaleco18($m) => $e,
            Mapper::Irem32($m) => $e,
            Mapper::Irem65($m) => $e,
            Mapper::Taito33($m) => $e,
            Mapper::Taito80($m) => $e,
            Mapper::Vrc1($m) => $e,
            Mapper::Vrc3($m) => $e,
            Mapper::Asder112($m) => $e,
            Mapper::Nanjing163($m) => $e,
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
            4 => Mapper::Mmc3(Mmc3::new(prg_len, submapper, header_mirroring)),
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
            5 => Mapper::Mmc5(Mmc5::new(prg_len, chr_len)),
            9 => Mapper::Mmc2(Mmc2::new(false, prg_len, chr_len)),
            10 => Mapper::Mmc2(Mmc2::new(true, prg_len, chr_len)),
            19 => Mapper::N163(N163::new(prg_len, chr_len)),
            210 => Mapper::N175(N175::new(
                prg_len,
                chr_len,
                header_mirroring,
                submapper != 1,
            )),
            21 | 22 | 23 | 25 => Mapper::Vrc24(Vrc24::new(number, prg_len, chr_len)),
            24 | 26 => Mapper::Vrc6(Vrc6::new(number, prg_len, chr_len)),
            67 => Mapper::Sunsoft3(Sunsoft3::new(prg_len, chr_len)),
            68 => Mapper::Sunsoft4(Sunsoft4::new(prg_len, chr_len)),
            69 => Mapper::Fme7(Fme7::new(prg_len, chr_len)),
            76 | 88 | 95 | 154 | 206 => Mapper::Namco108(Namco108::new(
                number,
                prg_len,
                chr_len,
                header_mirroring,
            )),
            118 => {
                let mut m = Mmc3::new(prg_len, submapper, header_mirroring);
                m.variant = Mmc3Variant::TxSrom;
                Mapper::Mmc3(m)
            }
            119 => {
                let mut m = Mmc3::new(prg_len, submapper, header_mirroring);
                m.variant = Mmc3Variant::TqRom;
                Mapper::Mmc3(m)
            }
            85 => Mapper::Vrc7(Vrc7::new(prg_len, chr_len)),
            34 if chr_len > 0x2000 => Mapper::Nina001(Nina001::new(prg_len, chr_len)),
            18 => Mapper::Jaleco18(Jaleco18::new(prg_len, chr_len)),
            32 => Mapper::Irem32(Irem32::new(prg_len, chr_len)),
            33 => Mapper::Taito33(Taito33::new(false, prg_len, chr_len)),
            48 => Mapper::Taito33(Taito33::new(true, prg_len, chr_len)),
            65 => Mapper::Irem65(Irem65::new(prg_len, chr_len)),
            72 => Mapper::Jaleco7292(Jaleco7292::new(false, prg_len, chr_len, header_mirroring)),
            92 => Mapper::Jaleco7292(Jaleco7292::new(true, prg_len, chr_len, header_mirroring)),
            73 => Mapper::Vrc3(Vrc3::new(prg_len)),
            75 => Mapper::Vrc1(Vrc1::new(prg_len, chr_len)),
            80 => Mapper::Taito80(Taito80::new(prg_len, chr_len)),
            86 => Mapper::M86(M86::new(prg_len, chr_len, header_mirroring)),
            87 => Mapper::M87(M87::new(prg_len, chr_len, header_mirroring)),
            89 => Mapper::M89(M89::new(prg_len, chr_len)),
            112 => Mapper::Asder112(Asder112::new(prg_len, chr_len)),
            163 => Mapper::Nanjing163(Nanjing163::new(prg_len)),
            184 => Mapper::M184(M184::new(prg_len, chr_len, header_mirroring)),
            185 => Mapper::M185(M185::new(prg_len, header_mirroring)),
            74 => {
                let mut m = Mmc3::new(prg_len, submapper, header_mirroring);
                m.variant = Mmc3Variant::M74;
                Mapper::Mmc3(m)
            }
            189 => {
                let mut m = Mmc3::new(prg_len, submapper, header_mirroring);
                m.variant = Mmc3Variant::M189;
                Mapper::Mmc3(m)
            }
            n => match simple_latch_for(n, submapper) {
                Some(cfg) => Mapper::SimpleLatch(SimpleLatch::new(
                    cfg,
                    prg_len,
                    chr_len,
                    header_mirroring,
                )),
                None => return Err(RomError::UnsupportedMapper(n)),
            },
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
    pub fn ppu_dot(&mut self, bus_addr: u16) {
        delegate!(self, m => m.ppu_dot(bus_addr))
    }
    /// 是否需要逐 dot 的 A12 波形(热路径优化:多数 mapper 直接跳过)。
    pub fn wants_ppu_dot(&self) -> bool {
        matches!(
            self,
            Mapper::Mmc3(_) | Mapper::Taito33(_) | Mapper::Nanjing163(_)
        )
    }
    /// 是否需要每次 PPU 总线读的通知(MMC2/MMC4 latch、MMC5 取数流)。
    pub fn wants_ppu_notify(&self) -> bool {
        matches!(self, Mapper::Mmc2(_) | Mapper::Mmc5(_))
    }
    pub fn ppu_ctrl_update(&mut self, ctrl: u8, mask: u8) {
        delegate!(self, m => m.ppu_ctrl_update(ctrl, mask))
    }
    pub fn nt_map(&mut self, addr: u16) -> NtRead {
        delegate!(self, m => m.nt_map(addr))
    }
    pub fn nt_write_map(&mut self, addr: u16, val: u8) -> NtWrite {
        delegate!(self, m => m.nt_write_map(addr, val))
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
