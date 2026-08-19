//! Mapper 4: MMC3/MMC6。八个 bank 寄存器、两种 PRG/CHR 布局、
//! 基于真实 A12 上升沿(带低电平时长滤波)的扫描线 IRQ。

use super::mapper::{ChrTarget, MapperImpl, NtRead, NtWrite, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

/// MMC3 板变体。
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Mmc3Variant {
    Normal,
    /// 118:nametable 由 CHR bank 寄存器 bit7 控制
    TxSrom,
    /// 119:CHR bank bit6 选 8K CHR RAM
    TqRom,
}

/// A12 上升沿计数前必须保持低电平的最短 PPU dot 数(波形滤波)。
/// 取数节奏里 NT+AT 的 4-dot 低间隙不计数;行首(8-dot 低)与
/// 精灵窗切换(几十 dot 低)正常计数。
const A12_FILTER_LOW_DOTS: u16 = 5;

#[derive(Serialize, Deserialize)]
pub struct Mmc3 {
    prg_len: usize,
    regs: [u8; 8],
    bank_select: u8,
    mirroring: Mirroring,
    four_screen: bool,
    ram_enable: bool,
    ram_protect: bool,
    irq_latch: u8,
    irq_counter: u8,
    irq_reload: bool,
    irq_enabled: bool,
    irq_pending: bool,
    /// MMC3 rev-A / MMC6 的"旧"IRQ 行为:仅在计数值由非 0 递减到 0
    /// (或强制重装)时触发,latch=0 时不反复触发
    alt_irq: bool,
    a12_prev_high: bool,
    a12_low_run: u16,
    pub variant: Mmc3Variant,
}

impl Mmc3 {
    pub fn new(prg_len: usize, submapper: u8, header_mirroring: Mirroring) -> Mmc3 {
        Mmc3 {
            prg_len,
            regs: [0; 8],
            bank_select: 0,
            mirroring: if header_mirroring == Mirroring::FourScreen {
                Mirroring::FourScreen
            } else {
                header_mirroring
            },
            four_screen: header_mirroring == Mirroring::FourScreen,
            ram_enable: true,
            ram_protect: false,
            irq_latch: 0,
            irq_counter: 0,
            irq_reload: false,
            irq_enabled: false,
            irq_pending: false,
            // NES 2.0:submapper 1 = MMC6,4 = MMC3A(旧行为)
            alt_irq: submapper == 1 || submapper == 4,
            a12_prev_high: false,
            a12_low_run: 0,
            variant: Mmc3Variant::Normal,
        }
    }

    /// TxSROM:各 nametable 的页来自对应 CHR 寄存器的 bit7。
    fn txsrom_page(&self, addr: u16) -> usize {
        let table = ((addr as usize - 0x2000) & 0xFFF) / 0x400;
        let reg = if self.bank_select & 0x80 == 0 {
            // 2K 组在 $0000:R0 管 NT0/1,R1 管 NT2/3
            self.regs[table >> 1]
        } else {
            self.regs[2 + table]
        };
        (reg >> 7) as usize
    }

    fn prg_banks(&self) -> usize {
        (self.prg_len / 0x2000).max(1)
    }

    fn clock_irq(&mut self) {
        let was = self.irq_counter;
        let forced = self.irq_reload;
        if self.irq_counter == 0 || self.irq_reload {
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else {
            self.irq_counter -= 1;
        }
        let fire = if self.alt_irq {
            self.irq_counter == 0 && (was != 0 || forced)
        } else {
            self.irq_counter == 0
        };
        if fire && self.irq_enabled {
            self.irq_pending = true;
        }
    }
}

impl MapperImpl for Mmc3 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            if self.ram_enable {
                return PrgTarget::Ram((addr - 0x6000) as usize);
            }
            return PrgTarget::None;
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = self.prg_banks();
        let off = addr as usize & 0x1FFF;
        let mode1 = self.bank_select & 0x40 != 0;
        let bank = match (addr >> 13) & 0x03 {
            0 => {
                if mode1 {
                    banks - 2
                } else {
                    self.regs[6] as usize % banks
                }
            }
            1 => self.regs[7] as usize % banks,
            2 => {
                if mode1 {
                    self.regs[6] as usize % banks
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
            if self.ram_enable && !self.ram_protect {
                return PrgWrite::Ram((addr - 0x6000) as usize);
            }
            return PrgWrite::Handled;
        }
        if addr < 0x8000 {
            return PrgWrite::Handled;
        }
        let even = addr & 1 == 0;
        match (addr >> 13) & 0x03 {
            0 => {
                if even {
                    self.bank_select = val;
                } else {
                    let r = (self.bank_select & 0x07) as usize;
                    self.regs[r] = val;
                }
            }
            1 => {
                if even {
                    if !self.four_screen {
                        self.mirroring = if val & 1 != 0 {
                            Mirroring::Horizontal
                        } else {
                            Mirroring::Vertical
                        };
                    }
                } else {
                    self.ram_enable = val & 0x80 != 0;
                    self.ram_protect = val & 0x40 != 0;
                }
            }
            2 => {
                if even {
                    self.irq_latch = val;
                } else {
                    self.irq_counter = 0;
                    self.irq_reload = true;
                }
            }
            _ => {
                if even {
                    self.irq_enabled = false;
                    self.irq_pending = false;
                } else {
                    self.irq_enabled = true;
                }
            }
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let a = addr as usize;
        let invert = (self.bank_select & 0x80 != 0) as usize * 0x1000;
        let eff = a ^ invert;
        let (reg, i) = match eff >> 10 {
            // $0000-$0FFF(逻辑):两个 2KB bank,寄存器低位忽略
            0 | 1 => (self.regs[0], (self.regs[0] & 0xFE) as usize * 0x400 + (eff & 0x7FF)),
            2 | 3 => (self.regs[1], (self.regs[1] & 0xFE) as usize * 0x400 + (eff & 0x7FF)),
            4 => (self.regs[2], self.regs[2] as usize * 0x400 + (eff & 0x3FF)),
            5 => (self.regs[3], self.regs[3] as usize * 0x400 + (eff & 0x3FF)),
            6 => (self.regs[4], self.regs[4] as usize * 0x400 + (eff & 0x3FF)),
            _ => (self.regs[5], self.regs[5] as usize * 0x400 + (eff & 0x3FF)),
        };
        if self.variant == Mmc3Variant::TqRom {
            // bit6 选 8K CHR RAM
            if reg & 0x40 != 0 {
                let base = match eff >> 10 {
                    0 | 1 => (reg & 0x3E) as usize * 0x400 + (eff & 0x7FF),
                    2 | 3 => (reg & 0x3E) as usize * 0x400 + (eff & 0x7FF),
                    _ => (reg & 0x3F) as usize * 0x400 + (eff & 0x3FF),
                };
                return ChrTarget::Ram(base);
            }
        }
        ChrTarget::Rom(i)
    }

    fn nt_map(&mut self, addr: u16) -> NtRead {
        if self.variant == Mmc3Variant::TxSrom {
            return NtRead::Ciram(self.txsrom_page(addr), addr as usize & 0x3FF);
        }
        let (p, o) = super::mapper::standard_nt(self.mirroring(), addr);
        if p < 2 {
            NtRead::Ciram(p, o)
        } else {
            NtRead::Ext(p - 2, o)
        }
    }

    fn nt_write_map(&mut self, addr: u16, _val: u8) -> NtWrite {
        if self.variant == Mmc3Variant::TxSrom {
            return NtWrite::Ciram(self.txsrom_page(addr), addr as usize & 0x3FF);
        }
        let (p, o) = super::mapper::standard_nt(self.mirroring(), addr);
        if p < 2 {
            NtWrite::Ciram(p, o)
        } else {
            NtWrite::Ext(p - 2, o)
        }
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn ppu_dot(&mut self, bus_addr: u16) {
        let high = bus_addr & 0x1000 != 0;
        if high {
            if !self.a12_prev_high && self.a12_low_run >= A12_FILTER_LOW_DOTS {
                self.clock_irq();
            }
            self.a12_low_run = 0;
        } else {
            self.a12_low_run = self.a12_low_run.saturating_add(1);
        }
        self.a12_prev_high = high;
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}
