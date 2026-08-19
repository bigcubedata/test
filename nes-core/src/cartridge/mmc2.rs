//! Mapper 9(MMC2,Punch-Out!!)与 10(MMC4,Fire Emblem):
//! CHR 双 4K 槽,各带 $FD/$FE 两个 latch,由特定 pattern 地址的读自动切换。
//! latch 在本次取数完成后生效(在 ppu_map 内先解析再更新,天然满足)。

use super::mapper::{ChrTarget, MapperImpl, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct Mmc2 {
    is_mmc4: bool,
    prg_len: usize,
    chr_len: usize,
    prg: u8,
    chr_fd: [u8; 2],
    chr_fe: [u8; 2],
    latch_fe: [bool; 2],
    mirroring: Mirroring,
}

impl Mmc2 {
    pub fn new(is_mmc4: bool, prg_len: usize, chr_len: usize) -> Mmc2 {
        Mmc2 {
            is_mmc4,
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg: 0,
            chr_fd: [0; 2],
            chr_fe: [0; 2],
            latch_fe: [true; 2],
            mirroring: Mirroring::Vertical,
        }
    }
}

impl MapperImpl for Mmc2 {
    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        if (0x6000..0x8000).contains(&addr) {
            return PrgTarget::Ram((addr - 0x6000) as usize);
        }
        if addr < 0x8000 {
            return PrgTarget::None;
        }
        if self.is_mmc4 {
            let banks = (self.prg_len / 0x4000).max(1);
            let off = addr as usize & 0x3FFF;
            if addr < 0xC000 {
                PrgTarget::Rom((self.prg as usize % banks) * 0x4000 + off)
            } else {
                PrgTarget::Rom((banks - 1) * 0x4000 + off)
            }
        } else {
            let banks = (self.prg_len / 0x2000).max(1);
            let off = addr as usize & 0x1FFF;
            if addr < 0xA000 {
                PrgTarget::Rom((self.prg as usize % banks) * 0x2000 + off)
            } else {
                // $A000-$FFFF 固定最后三个 8K
                let idx = banks - 3 + ((addr as usize - 0xA000) >> 13);
                PrgTarget::Rom(idx * 0x2000 + off)
            }
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        if (0x6000..0x8000).contains(&addr) {
            return PrgWrite::Ram((addr - 0x6000) as usize);
        }
        match addr & 0xF000 {
            0xA000 => self.prg = val & 0x0F,
            0xB000 => self.chr_fd[0] = val & 0x1F,
            0xC000 => self.chr_fe[0] = val & 0x1F,
            0xD000 => self.chr_fd[1] = val & 0x1F,
            0xE000 => self.chr_fe[1] = val & 0x1F,
            0xF000 => {
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
        let side = (addr >> 12) as usize & 1;
        let bank = if self.latch_fe[side] {
            self.chr_fe[side]
        } else {
            self.chr_fd[side]
        };
        let banks = (self.chr_len / 0x1000).max(1);
        let i = (bank as usize % banks) * 0x1000 + (addr as usize & 0xFFF);
        // 取数完成后更新 latch
        let a = addr & 0x3FFF;
        if self.is_mmc4 {
            match a & 0x1FF8 {
                0x0FD8 | 0x1FD8 => self.latch_fe[side] = false,
                0x0FE8 | 0x1FE8 => self.latch_fe[side] = true,
                _ => {}
            }
        } else {
            // MMC2:$0FD8/$0FE8 精确地址,$1FD8-$1FDF/$1FE8-$1FEF 范围
            match a {
                0x0FD8 => self.latch_fe[0] = false,
                0x0FE8 => self.latch_fe[0] = true,
                0x1FD8..=0x1FDF => self.latch_fe[1] = false,
                0x1FE8..=0x1FEF => self.latch_fe[1] = true,
                _ => {}
            }
        }
        ChrTarget::Rom(i)
    }

    fn mirroring(&self) -> Mirroring {
        self.mirroring
    }
}
