//! Mapper 1: MMC1(SxROM 全家)。串行移位写入、三种 PRG 模式、4/8KB CHR、
//! 连续周期写忽略(RMW 双写),SUROM 512KB 经 CHR 寄存器 bit4 选高低 256KB。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Mmc1 {
    prg_len: usize,
    chr_len: usize,
    chr_is_ram: bool,
    shift: u8,
    shift_count: u8,
    control: u8,
    chr0: u8,
    chr1: u8,
    prg: u8,
    cycle: u64,
    last_write_cycle: u64,
}

impl Mmc1 {
    pub fn new(prg_len: usize, chr_len: usize, chr_is_ram: bool) -> Mmc1 {
        Mmc1 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            chr_is_ram,
            shift: 0,
            shift_count: 0,
            control: 0x0C, // 上电:PRG 模式 3(固定末 bank 在 $C000)
            chr0: 0,
            chr1: 0,
            prg: 0,
            cycle: 0,
            last_write_cycle: u64::MAX - 1,
        }
    }

    /// SUROM/SXROM:PRG 超过 256KB 时,CHR0 bit4 选择 256KB 半区。
    fn prg_256k_base(&self) -> usize {
        if self.prg_len > 256 * 1024 && self.chr0 & 0x10 != 0 {
            256 * 1024
        } else {
            0
        }
    }

    fn prg_bank_count(&self) -> usize {
        (self.prg_len.min(256 * 1024) / 0x4000).max(1)
    }

    fn chr_index(&self, addr: u16) -> usize {
        let a = addr as usize & 0x0FFF;
        let banks4k = (self.chr_len / 0x1000).max(1);
        if self.control & 0x10 == 0 {
            // 8KB 模式:低位忽略
            let bank = (self.chr0 & 0x1E) as usize % banks4k.max(2);
            bank * 0x1000 + (addr as usize & 0x1FFF)
        } else if addr < 0x1000 {
            (self.chr0 as usize % banks4k) * 0x1000 + a
        } else {
            (self.chr1 as usize % banks4k) * 0x1000 + a
        }
    }
}

impl MapperImpl for Mmc1 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        let banks = self.prg_bank_count();
        let base = self.prg_256k_base();
        let bank_reg = (self.prg & 0x0F) as usize;
        let off = addr as usize & 0x3FFF;
        let idx = match (self.control >> 2) & 0x03 {
            0 | 1 => {
                // 32KB 模式
                let bank = (bank_reg & !1) % banks;
                bank * 0x4000 + (addr as usize & 0x7FFF)
            }
            2 => {
                // 固定第一个 bank 在 $8000
                if addr < 0xC000 {
                    off
                } else {
                    (bank_reg % banks) * 0x4000 + off
                }
            }
            _ => {
                // 模式 3:固定最后 bank 在 $C000
                if addr < 0xC000 {
                    (bank_reg % banks) * 0x4000 + off
                } else {
                    (banks - 1) * 0x4000 + off
                }
            }
        };
        PrgTarget::Rom(base + idx)
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgWrite::Handled;
        }
        // 连续 CPU 周期的第二次写被硬件忽略(RMW 指令的 dummy write + write)
        let consecutive = self.cycle == self.last_write_cycle.wrapping_add(1);
        self.last_write_cycle = self.cycle;
        if consecutive {
            return PrgWrite::Handled;
        }
        if val & 0x80 != 0 {
            self.shift = 0;
            self.shift_count = 0;
            self.control |= 0x0C;
            return PrgWrite::Handled;
        }
        self.shift |= (val & 1) << self.shift_count;
        self.shift_count += 1;
        if self.shift_count == 5 {
            let v = self.shift;
            match (addr >> 13) & 0x03 {
                0 => self.control = v,
                1 => self.chr0 = v,
                2 => self.chr1 = v,
                _ => self.prg = v,
            }
            self.shift = 0;
            self.shift_count = 0;
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        let i = self.chr_index(addr);
        if self.chr_is_ram {
            ChrTarget::Ram(i)
        } else {
            ChrTarget::Rom(i)
        }
    }

    fn mirroring(&self) -> Mirroring {
        match self.control & 0x03 {
            0 => Mirroring::SingleA,
            1 => Mirroring::SingleB,
            2 => Mirroring::Vertical,
            _ => Mirroring::Horizontal,
        }
    }

    fn cpu_tick(&mut self) {
        self.cycle += 1;
    }
}
