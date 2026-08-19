//! 简单 discrete 板:统一的 SimpleLatch 框架 + 若干位组合特殊的小板。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Serialize, Deserialize)]
pub enum PrgWindow {
    /// 32K 切换
    Bank32,
    /// 16K 在 $8000 切换,末 bank 固定 $C000
    Bank16Low,
    /// 16K 在 $C000 切换,首 bank 固定 $8000
    Bank16High,
    /// 无切换(≤32K 全镜像)
    Fixed,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
pub enum MirrorCtrl {
    None,
    /// 单屏:val 该位选 A/B
    SingleBit(u8),
    /// 水平/垂直:val 该位 1=H 0=V
    HvBit(u8),
    /// mapper 97 式:val>>6 双位
    TwoBit97,
}

/// 一个寄存器锁存器覆盖的一类板。
#[derive(Clone, Copy, Serialize, Deserialize)]
pub struct LatchCfg {
    pub reg_lo: u16,
    pub reg_hi: u16,
    /// NINA-03/06 类:要求 addr & 0x100 != 0
    pub reg_bit8: bool,
    pub prg_window: PrgWindow,
    pub prg_shift: u8,
    pub prg_mask: u8,
    pub chr_shift: u8,
    pub chr_mask: u8,
    pub mirror: MirrorCtrl,
    pub conflicts: bool,
}

impl LatchCfg {
    pub fn basic() -> LatchCfg {
        LatchCfg {
            reg_lo: 0x8000,
            reg_hi: 0xFFFF,
            reg_bit8: false,
            prg_window: PrgWindow::Bank32,
            prg_shift: 0,
            prg_mask: 0,
            chr_shift: 0,
            chr_mask: 0,
            mirror: MirrorCtrl::None,
            conflicts: false,
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct SimpleLatch {
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    cfg: LatchCfg,
    prg_sel: u8,
    chr_sel: u8,
    mirroring: Mirroring,
}

impl SimpleLatch {
    pub fn new(cfg: LatchCfg, prg_len: usize, chr_len: usize, m: Mirroring) -> SimpleLatch {
        SimpleLatch {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram: chr_len == 0,
            cfg,
            prg_sel: 0,
            chr_sel: 0,
            mirroring: m,
        }
    }
}

impl MapperImpl for SimpleLatch {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) && self.cfg.reg_lo >= 0x8000 {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        match self.cfg.prg_window {
            PrgWindow::Fixed => PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len),
            PrgWindow::Bank32 => {
                let banks = (self.prg_len / 0x8000).max(1);
                PrgTarget::Rom(
                    (self.prg_sel as usize % banks) * 0x8000 + (addr as usize & 0x7FFF),
                )
            }
            PrgWindow::Bank16Low => {
                let banks = (self.prg_len / 0x4000).max(1);
                let off = addr as usize & 0x3FFF;
                if addr < 0xC000 {
                    PrgTarget::Rom((self.prg_sel as usize % banks) * 0x4000 + off)
                } else {
                    PrgTarget::Rom((banks - 1) * 0x4000 + off)
                }
            }
            PrgWindow::Bank16High => {
                let banks = (self.prg_len / 0x4000).max(1);
                let off = addr as usize & 0x3FFF;
                if addr < 0xC000 {
                    PrgTarget::Rom(off)
                } else {
                    PrgTarget::Rom((self.prg_sel as usize % banks) * 0x4000 + off)
                }
            }
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) && self.cfg.reg_lo >= 0x8000 {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        let in_range = addr >= self.cfg.reg_lo
            && addr <= self.cfg.reg_hi
            && (!self.cfg.reg_bit8 || addr & 0x100 != 0);
        if in_range {
            let v = if self.cfg.conflicts && addr >= 0x8000 {
                val & rom_at
            } else {
                val
            };
            if self.cfg.prg_mask != 0 {
                self.prg_sel = v >> self.cfg.prg_shift & self.cfg.prg_mask;
            }
            if self.cfg.chr_mask != 0 {
                self.chr_sel = v >> self.cfg.chr_shift & self.cfg.chr_mask;
            }
            match self.cfg.mirror {
                MirrorCtrl::None => {}
                MirrorCtrl::SingleBit(b) => {
                    self.mirroring = if v >> b & 1 != 0 {
                        Mirroring::SingleB
                    } else {
                        Mirroring::SingleA
                    };
                }
                MirrorCtrl::HvBit(b) => {
                    self.mirroring = if v >> b & 1 != 0 {
                        Mirroring::Horizontal
                    } else {
                        Mirroring::Vertical
                    };
                }
                MirrorCtrl::TwoBit97 => {
                    self.mirroring = match v >> 6 {
                        0 => Mirroring::SingleA,
                        1 => Mirroring::Horizontal,
                        2 => Mirroring::Vertical,
                        _ => Mirroring::SingleB,
                    };
                }
            }
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let banks = (self.chr_len / 0x2000).max(1);
        let i = (self.chr_sel as usize % banks) * 0x2000 + (addr as usize & 0x1FFF);
        if self.chr_is_ram {
            ChrTarget::Ram(i)
        } else {
            ChrTarget::Rom(i)
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

/// 按编号构造 SimpleLatch 配置(能被此框架覆盖的编号)。
pub fn simple_latch_for(number: u16, submapper: u8) -> Option<LatchCfg> {
    let mut c = LatchCfg::basic();
    match number {
        34 => {
            // BNROM(NINA-001 由 Cartridge 侧按 CHR 大小改走 Nina001)
            c.prg_mask = 0xFF;
        }
        38 => {
            c.reg_lo = 0x7000;
            c.reg_hi = 0x7FFF;
            c.prg_mask = 3;
            c.chr_shift = 2;
            c.chr_mask = 3;
        }
        70 => {
            c.prg_window = PrgWindow::Bank16Low;
            c.prg_shift = 4;
            c.prg_mask = 0x0F;
            c.chr_mask = 0x0F;
        }
        78 => {
            c.prg_window = PrgWindow::Bank16Low;
            c.prg_mask = 7;
            c.chr_shift = 4;
            c.chr_mask = 0x0F;
            // submapper 3 = Holy Diver(H/V);默认 1 = 单屏(Cosmo Carrier)
            c.mirror = if submapper == 3 {
                MirrorCtrl::HvBit(3)
            } else {
                MirrorCtrl::SingleBit(3)
            };
        }
        79 | 146 => {
            c.reg_lo = 0x4020;
            c.reg_hi = 0x5FFF;
            c.reg_bit8 = true;
            c.prg_shift = 3;
            c.prg_mask = 1;
            c.chr_mask = 7;
        }
        93 => {
            c.prg_window = PrgWindow::Bank16Low;
            c.prg_shift = 4;
            c.prg_mask = 7;
        }
        94 => {
            c.prg_window = PrgWindow::Bank16Low;
            c.prg_shift = 2;
            c.prg_mask = 0x1F;
        }
        97 => {
            c.prg_window = PrgWindow::Bank16High;
            c.prg_mask = 0x0F;
            c.mirror = MirrorCtrl::TwoBit97;
        }
        107 => {
            c.prg_shift = 1;
            c.prg_mask = 3;
            c.chr_mask = 7;
        }
        113 => {
            // HES:PRG 3 位 + CHR 4 位(bit6 为高位),HV bit7
            c.reg_lo = 0x4020;
            c.reg_hi = 0x5FFF;
            c.reg_bit8 = true;
            c.prg_shift = 3;
            c.prg_mask = 7;
            c.chr_mask = 7; // 高位在 Nina113 特化中处理:此处仅低 3 位
            c.mirror = MirrorCtrl::HvBit(7);
        }
        133 => {
            c.reg_lo = 0x4020;
            c.reg_hi = 0x5FFF;
            c.reg_bit8 = true;
            c.prg_shift = 2;
            c.prg_mask = 1;
            c.chr_mask = 3;
        }
        140 => {
            c.reg_lo = 0x6000;
            c.reg_hi = 0x7FFF;
            c.prg_shift = 4;
            c.prg_mask = 3;
            c.chr_mask = 0x0F;
        }
        145 => {
            c.reg_lo = 0x4020;
            c.reg_hi = 0x5FFF;
            c.reg_bit8 = true;
            c.chr_shift = 7;
            c.chr_mask = 1;
        }
        148 => {
            c.prg_shift = 3;
            c.prg_mask = 1;
            c.chr_mask = 7;
            c.conflicts = true;
        }
        149 => {
            c.chr_shift = 7;
            c.chr_mask = 1;
            c.conflicts = true;
        }
        152 => {
            c.prg_window = PrgWindow::Bank16Low;
            c.prg_shift = 4;
            c.prg_mask = 7;
            c.chr_mask = 0x0F;
            c.mirror = MirrorCtrl::SingleBit(7);
        }
        _ => return None,
    }
    Some(c)
}

// ---------------- 位组合特殊的小板 ----------------

/// mapper 34 NINA-001:寄存器在 $7FFD-$7FFF。
#[derive(Serialize, Deserialize)]
pub struct Nina001 {
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: [u8; 2],
}

impl Nina001 {
    pub fn new(prg_len: usize, chr_len: usize) -> Nina001 {
        Nina001 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: [0, 1],
        }
    }
}

impl MapperImpl for Nina001 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x8000).max(1);
        PrgTarget::Rom((self.prg as usize % banks) * 0x8000 + (addr as usize & 0x7FFF))
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x7FFD => self.prg = val & 1,
            0x7FFE => self.chr[0] = val & 0x0F,
            0x7FFF => self.chr[1] = val & 0x0F,
            0x6000..=0x7FFC => return PrgWrite::Ram((addr - 0x6000) as usize),
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
        Mirroring::Vertical
    }
}

/// mapper 87:CHR 两位对调,寄存器在 $6000-$7FFF。
#[derive(Serialize, Deserialize)]
pub struct M87 {
    prg_len: usize,
    chr_len: usize,
    chr: u8,
    mirroring: Mirroring,
}

impl M87 {
    pub fn new(prg_len: usize, chr_len: usize, m: Mirroring) -> M87 {
        M87 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr: 0,
            mirroring: m,
        }
    }
}

impl MapperImpl for M87 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len)
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            self.chr = (val & 1) << 1 | val >> 1 & 1;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let banks = (self.chr_len / 0x2000).max(1);
        ChrTarget::Rom((self.chr as usize % banks) * 0x2000 + (addr as usize & 0x1FFF))
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

/// mapper 89(Sunsoft-2B):CHR 高位在 bit7。
#[derive(Serialize, Deserialize)]
pub struct M89 {
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: u8,
    mirroring: Mirroring,
}

impl M89 {
    pub fn new(prg_len: usize, chr_len: usize) -> M89 {
        M89 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: 0,
            mirroring: Mirroring::SingleA,
        }
    }
}

impl MapperImpl for M89 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
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
        if addr >= 0x8000 {
            self.prg = val >> 4 & 7;
            self.chr = (val & 7) | (val >> 4 & 8);
            self.mirroring = if val & 8 != 0 {
                Mirroring::SingleB
            } else {
                Mirroring::SingleA
            };
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let banks = (self.chr_len / 0x2000).max(1);
        ChrTarget::Rom((self.chr as usize % banks) * 0x2000 + (addr as usize & 0x1FFF))
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

/// mapper 184(Sunsoft-1):两个 4K CHR 槽,寄存器 $6000-$7FFF。
#[derive(Serialize, Deserialize)]
pub struct M184 {
    prg_len: usize,
    chr_len: usize,
    chr: [u8; 2],
    mirroring: Mirroring,
}

impl M184 {
    pub fn new(prg_len: usize, chr_len: usize, m: Mirroring) -> M184 {
        M184 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr: [0, 1],
            mirroring: m,
        }
    }
}

impl MapperImpl for M184 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len)
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            self.chr[0] = val & 7;
            self.chr[1] = (val >> 4 & 7) | 4;
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

/// mapper 185:CNROM 拷贝保护(CHR 使能检查)。
#[derive(Serialize, Deserialize)]
pub struct M185 {
    prg_len: usize,
    chr_enabled: bool,
    mirroring: Mirroring,
}

impl M185 {
    pub fn new(prg_len: usize, m: Mirroring) -> M185 {
        M185 {
            prg_len,
            chr_enabled: false,
            mirroring: m,
        }
    }
}

impl MapperImpl for M185 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        PrgTarget::Rom((addr as usize - 0x8000) % self.prg_len)
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if addr >= 0x8000 {
            // 常见板:低 2 位非零且非 $13 时使能 CHR
            self.chr_enabled = val & 0x0F != 0 && val != 0x13;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        if self.chr_enabled {
            ChrTarget::Rom(addr as usize & 0x1FFF)
        } else {
            // 未使能:返回超界索引让取数得到"垃圾"——用固定偏移制造非法图形
            ChrTarget::Rom(0x1FFF)
        }
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

/// mapper 72(JF-17)与 92(JF-19):带 strobe 的锁存。
#[derive(Serialize, Deserialize)]
pub struct Jaleco7292 {
    is_92: bool,
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: u8,
    prg_strobe: bool,
    chr_strobe: bool,
    mirroring: Mirroring,
}

impl Jaleco7292 {
    pub fn new(is_92: bool, prg_len: usize, chr_len: usize, m: Mirroring) -> Jaleco7292 {
        Jaleco7292 {
            is_92,
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: 0,
            prg_strobe: false,
            chr_strobe: false,
            mirroring: m,
        }
    }
}

impl MapperImpl for Jaleco7292 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x4000).max(1);
        let off = addr as usize & 0x3FFF;
        let switched = (self.prg as usize % banks) * 0x4000 + off;
        let fixed_last = (banks - 1) * 0x4000 + off;
        let fixed_first = off;
        if self.is_92 {
            // JF-19:$8000 固定首,$C000 切换
            if addr < 0xC000 {
                PrgTarget::Rom(fixed_first)
            } else {
                PrgTarget::Rom(switched)
            }
        } else if addr < 0xC000 {
            PrgTarget::Rom(switched)
        } else {
            PrgTarget::Rom(fixed_last)
        }
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if addr >= 0x8000 {
            let p = val & 0x80 != 0;
            let c = val & 0x40 != 0;
            if p && !self.prg_strobe {
                self.prg = val & 0x0F;
            }
            if c && !self.chr_strobe {
                self.chr = val & 0x0F;
            }
            self.prg_strobe = p;
            self.chr_strobe = c;
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let banks = (self.chr_len / 0x2000).max(1);
        ChrTarget::Rom((self.chr as usize % banks) * 0x2000 + (addr as usize & 0x1FFF))
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}

/// mapper 86(JF-13):$6000 低区寄存器,CHR 位拼接。
#[derive(Serialize, Deserialize)]
pub struct M86 {
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr: u8,
    mirroring: Mirroring,
}

impl M86 {
    pub fn new(prg_len: usize, chr_len: usize, m: Mirroring) -> M86 {
        M86 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr: 0,
            mirroring: m,
        }
    }
}

impl MapperImpl for M86 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = (self.prg_len / 0x8000).max(1);
        PrgTarget::Rom((self.prg as usize % banks) * 0x8000 + (addr as usize & 0x7FFF))
    }
    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x7000).contains(&addr) {
            self.prg = val >> 4 & 3;
            self.chr = (val & 3) | (val >> 4 & 4);
        }
        PrgWrite::Handled
    }
    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let banks = (self.chr_len / 0x2000).max(1);
        ChrTarget::Rom((self.chr as usize % banks) * 0x2000 + (addr as usize & 0x1FFF))
    }
    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}
