//! Mapper 4: MMC3/MMC6。八个 bank 寄存器、两种 PRG/CHR 布局、
//! 基于真实 A12 上升沿(带低电平时长滤波)的扫描线 IRQ。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

/// A12 在计数前必须保持低电平的最短 PPU dot 数。
/// 精灵取数窗口内的高电平脉冲间隔(约 4 dots)不会重复计数,
/// 而每条扫描线一次的 bg→sprite 表切换(低电平持续百余 dots)正常计数。
const A12_FILTER_DOTS: u64 = 10;

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
    a12_high: bool,
    a12_low_since: u64,
}

impl Mmc3 {
    pub fn new(prg_len: usize, header_mirroring: Mirroring) -> Mmc3 {
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
            a12_high: false,
            a12_low_since: 0,
        }
    }

    fn prg_banks(&self) -> usize {
        (self.prg_len / 0x2000).max(1)
    }

    fn clock_irq(&mut self) {
        if self.irq_counter == 0 || self.irq_reload {
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else {
            self.irq_counter -= 1;
        }
        if self.irq_counter == 0 && self.irq_enabled {
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
        let bank = match eff >> 10 {
            // $0000-$0FFF(逻辑):两个 2KB bank,寄存器低位忽略
            0 | 1 => (self.regs[0] & 0xFE) as usize * 0x400 + (eff & 0x7FF),
            2 | 3 => (self.regs[1] & 0xFE) as usize * 0x400 + (eff & 0x7FF),
            4 => self.regs[2] as usize * 0x400 + (eff & 0x3FF),
            5 => self.regs[3] as usize * 0x400 + (eff & 0x3FF),
            6 => self.regs[4] as usize * 0x400 + (eff & 0x3FF),
            _ => self.regs[5] as usize * 0x400 + (eff & 0x3FF),
        };
        ChrTarget::Rom(bank)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }

    fn ppu_addr_notify(&mut self, addr: u16, ppu_cycle: u64) {
        let high = addr & 0x1000 != 0;
        if high {
            if !self.a12_high && ppu_cycle.wrapping_sub(self.a12_low_since) >= A12_FILTER_DOTS {
                self.clock_irq();
            }
            self.a12_high = true;
        } else {
            if self.a12_high {
                self.a12_low_since = ppu_cycle;
            }
            self.a12_high = false;
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending
    }
}
