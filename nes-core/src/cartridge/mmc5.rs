//! Mapper 5:MMC5。
//!
//! 覆盖:PRG 四模式(ROM/RAM 槽)、CHR A/B 双组、$5105 nametable 映射
//! (CIRAM/ExRAM/填充)、ExAttr 扩展属性模式、扫描线 IRQ(NT 连读检测)、
//! 乘法器、ExRAM、音源(2 方波 + 8bit PCM)。
//! 垂直分屏($5200-5202)暂未实现(极少游戏使用,M5 打磨项)。

use super::mapper::{ChrTarget, MapperImpl, NtRead, NtWrite, PrgTarget, PrgWrite};
use super::Mirroring;
use serde::{Deserialize, Serialize};

const LENGTH_TABLE: [u8; 32] = [
    10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
];
const DUTY: [[u8; 8]; 4] = [
    [0, 1, 0, 0, 0, 0, 0, 0],
    [0, 1, 1, 0, 0, 0, 0, 0],
    [0, 1, 1, 1, 1, 0, 0, 0],
    [1, 0, 0, 1, 1, 1, 1, 1],
];

#[derive(Default, Serialize, Deserialize)]
struct Mmc5Pulse {
    duty: u8,
    halt: bool,
    constant: bool,
    volume: u8,
    env_start: bool,
    env_divider: u8,
    env_decay: u8,
    period: u16,
    timer: u16,
    seq: u8,
    length: u8,
    enabled: bool,
    odd: bool,
}

impl Mmc5Pulse {
    fn quarter(&mut self) {
        if self.env_start {
            self.env_start = false;
            self.env_decay = 15;
            self.env_divider = self.volume;
        } else if self.env_divider == 0 {
            self.env_divider = self.volume;
            if self.env_decay > 0 {
                self.env_decay -= 1;
            } else if self.halt {
                self.env_decay = 15;
            }
        } else {
            self.env_divider -= 1;
        }
    }
    fn half(&mut self) {
        if !self.halt && self.length > 0 {
            self.length -= 1;
        }
    }
    fn tick(&mut self) {
        self.odd = !self.odd;
        if self.odd {
            return;
        }
        if self.timer == 0 {
            self.timer = self.period;
            self.seq = (self.seq + 1) & 7;
        } else {
            self.timer -= 1;
        }
    }
    fn output(&self) -> u8 {
        if !self.enabled || self.length == 0 || DUTY[self.duty as usize][self.seq as usize] == 0 {
            0
        } else if self.constant {
            self.volume
        } else {
            self.env_decay
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct Mmc5 {
    prg_len: usize,
    chr_len: usize,
    prg_mode: u8,
    chr_mode: u8,
    ram_protect1: u8,
    ram_protect2: u8,
    exram_mode: u8,
    nt_mapping: u8,
    fill_tile: u8,
    fill_attr: u8,
    prg_ram_bank: u8, // $5113
    prg_regs: [u8; 4], // $5114-5117
    chr_a: [u16; 8],
    chr_b: [u16; 4],
    chr_hi: u8, // $5130
    last_set_b: bool,
    pub exram: Vec<u8>, // 1KB
    // IRQ / 扫描线检测
    irq_target: u8,
    irq_enable: bool,
    irq_pending: bool,
    in_frame: bool,
    scanline: u8,
    last_nt_addr: u16,
    nt_consec: u8,
    idle_cycles: u8,
    pt_fetches: u16,
    // ExAttr
    exattr_last: u8,
    // PPU 状态
    sprite16: bool,
    // 乘法器
    mul_a: u8,
    mul_b: u8,
    // 音源
    pulse1: Mmc5Pulse,
    pulse2: Mmc5Pulse,
    pcm: u8,
    frame_div: u16,
    half_toggle: bool,
}

impl Mmc5 {
    pub fn new(prg_len: usize, chr_len: usize) -> Mmc5 {
        Mmc5 {
            prg_len,
            chr_len: chr_len.max(0x2000),
            prg_mode: 3,
            chr_mode: 3,
            ram_protect1: 0,
            ram_protect2: 0,
            exram_mode: 0,
            nt_mapping: 0,
            fill_tile: 0,
            fill_attr: 0,
            prg_ram_bank: 0,
            prg_regs: [0xFF; 4],
            chr_a: [0; 8],
            chr_b: [0; 4],
            chr_hi: 0,
            last_set_b: false,
            exram: vec![0; 1024],
            irq_target: 0,
            irq_enable: false,
            irq_pending: false,
            in_frame: false,
            scanline: 0,
            last_nt_addr: 0xFFFF,
            nt_consec: 0,
            idle_cycles: 0,
            pt_fetches: 0,
            exattr_last: 0,
            sprite16: false,
            mul_a: 0xFF,
            mul_b: 0xFF,
            pulse1: Mmc5Pulse::default(),
            pulse2: Mmc5Pulse::default(),
            pcm: 0,
            frame_div: 0,
            half_toggle: false,
        }
    }

    fn prg_banks8(&self) -> usize {
        (self.prg_len / 0x2000).max(1)
    }

    /// $8000-$FFFF 槽位翻译。返回 (is_ram, index)。
    fn prg_slot(&self, addr: u16) -> (bool, usize) {
        let banks = self.prg_banks8();
        let off = addr as usize & 0x1FFF;
        let rom = |bank: usize| (false, (bank % banks) * 0x2000 + off);
        let ram = |bank: usize| (true, (bank & 7) * 0x2000 + off);
        let reg = |i: usize| self.prg_regs[i];
        let sel = (addr >> 13) & 3; // 0:$8000 1:$A000 2:$C000 3:$E000
        match self.prg_mode {
            0 => rom(((reg(3) >> 2) as usize) * 4 + sel as usize),
            1 => match sel {
                0 | 1 => {
                    let r = reg(1);
                    if r & 0x80 != 0 {
                        rom(((r & 0x7F) >> 1) as usize * 2 + sel as usize)
                    } else {
                        ram((r >> 1) as usize * 2 + sel as usize)
                    }
                }
                _ => rom(((reg(3) & 0x7F) >> 1) as usize * 2 + (sel as usize - 2)),
            },
            2 => match sel {
                0 | 1 => {
                    let r = reg(1);
                    if r & 0x80 != 0 {
                        rom(((r & 0x7F) >> 1) as usize * 2 + sel as usize)
                    } else {
                        ram((r >> 1) as usize * 2 + sel as usize)
                    }
                }
                2 => {
                    let r = reg(2);
                    if r & 0x80 != 0 {
                        rom((r & 0x7F) as usize)
                    } else {
                        ram(r as usize)
                    }
                }
                _ => rom((reg(3) & 0x7F) as usize),
            },
            _ => match sel {
                3 => rom((reg(3) & 0x7F) as usize),
                s => {
                    let r = reg(s as usize);
                    if r & 0x80 != 0 {
                        rom((r & 0x7F) as usize)
                    } else {
                        ram(r as usize)
                    }
                }
            },
        }
    }

    fn chr_index(&self, set_b: bool, addr: u16) -> usize {
        let m = self.chr_mode.min(3);
        let bank_size = 0x2000usize >> m; // mode0:8K … mode3:1K
        let a = addr as usize & 0x1FFF;
        let reg_val = if set_b {
            let a4 = a & 0x0FFF;
            let idx = match m {
                3 => a4 >> 10,
                2 => (a4 >> 11) * 2 + 1,
                _ => 3,
            };
            self.chr_b[idx.min(3)]
        } else {
            let idx = match m {
                3 => a >> 10,
                2 => (a >> 11) * 2 + 1,
                1 => (a >> 12) * 4 + 3,
                _ => 7,
            };
            self.chr_a[idx.min(7)]
        };
        let banks = (self.chr_len / bank_size).max(1);
        (reg_val as usize % banks) * bank_size + (a % bank_size)
    }

    /// 取数相位:每行 84 次 pattern 读(64 bg + 16 sprite + 4 prefetch)。
    fn fetch_is_sprite(&self) -> bool {
        (64..80).contains(&self.pt_fetches)
    }

    fn scanline_detected(&mut self) {
        if !self.in_frame {
            self.in_frame = true;
            self.scanline = 0;
        } else {
            self.scanline = self.scanline.wrapping_add(1);
            if self.scanline == self.irq_target && self.irq_target != 0 {
                self.irq_pending = true;
            }
        }
        self.pt_fetches = 0;
    }
}

impl MapperImpl for Mmc5 {
    fn cpu_map(&mut self, addr: u16) -> PrgTarget {
        match addr {
            0x5204 => {
                let v = (self.irq_pending as u8) << 7 | (self.in_frame as u8) << 6;
                self.irq_pending = false;
                PrgTarget::Value(v)
            }
            _ => self.cpu_peek(addr),
        }
    }

    fn cpu_peek(&self, addr: u16) -> PrgTarget {
        match addr {
            0x5010 => PrgTarget::Value(0x01),
            0x5015 => {
                let v = (self.pulse1.length > 0) as u8 | ((self.pulse2.length > 0) as u8) << 1;
                PrgTarget::Value(v)
            }
            0x5204 => PrgTarget::Value((self.irq_pending as u8) << 7 | (self.in_frame as u8) << 6),
            0x5205 => {
                PrgTarget::Value((self.mul_a as u16 * self.mul_b as u16) as u8)
            }
            0x5206 => {
                PrgTarget::Value(((self.mul_a as u16 * self.mul_b as u16) >> 8) as u8)
            }
            0x5C00..=0x5FFF => {
                if self.exram_mode >= 2 {
                    PrgTarget::Value(self.exram[(addr & 0x3FF) as usize])
                } else {
                    PrgTarget::None
                }
            }
            0x6000..=0x7FFF => {
                PrgTarget::Ram((self.prg_ram_bank as usize & 7) * 0x2000 + (addr as usize - 0x6000))
            }
            0x8000..=0xFFFF => {
                let (is_ram, i) = self.prg_slot(addr);
                if is_ram {
                    PrgTarget::Ram(i)
                } else {
                    PrgTarget::Rom(i)
                }
            }
            _ => PrgTarget::None,
        }
    }

    fn cpu_write(&mut self, addr: u16, val: u8, _rom_at: u8) -> PrgWrite {
        match addr {
            0x5000 => {
                self.pulse1.duty = val >> 6;
                self.pulse1.halt = val & 0x20 != 0;
                self.pulse1.constant = val & 0x10 != 0;
                self.pulse1.volume = val & 0x0F;
            }
            0x5002 => self.pulse1.period = self.pulse1.period & 0x700 | val as u16,
            0x5003 => {
                self.pulse1.period = self.pulse1.period & 0xFF | ((val & 7) as u16) << 8;
                if self.pulse1.enabled {
                    self.pulse1.length = LENGTH_TABLE[(val >> 3) as usize];
                }
                self.pulse1.seq = 0;
                self.pulse1.env_start = true;
            }
            0x5004 => {
                self.pulse2.duty = val >> 6;
                self.pulse2.halt = val & 0x20 != 0;
                self.pulse2.constant = val & 0x10 != 0;
                self.pulse2.volume = val & 0x0F;
            }
            0x5006 => self.pulse2.period = self.pulse2.period & 0x700 | val as u16,
            0x5007 => {
                self.pulse2.period = self.pulse2.period & 0xFF | ((val & 7) as u16) << 8;
                if self.pulse2.enabled {
                    self.pulse2.length = LENGTH_TABLE[(val >> 3) as usize];
                }
                self.pulse2.seq = 0;
                self.pulse2.env_start = true;
            }
            0x5010 => {} // PCM 模式/IRQ:略
            0x5011 => self.pcm = val,
            0x5015 => {
                self.pulse1.enabled = val & 1 != 0;
                if !self.pulse1.enabled {
                    self.pulse1.length = 0;
                }
                self.pulse2.enabled = val & 2 != 0;
                if !self.pulse2.enabled {
                    self.pulse2.length = 0;
                }
            }
            0x5100 => self.prg_mode = val & 3,
            0x5101 => self.chr_mode = val & 3,
            0x5102 => self.ram_protect1 = val & 3,
            0x5103 => self.ram_protect2 = val & 3,
            0x5104 => self.exram_mode = val & 3,
            0x5105 => self.nt_mapping = val,
            0x5106 => self.fill_tile = val,
            0x5107 => {
                let b = val & 3;
                self.fill_attr = b | b << 2 | b << 4 | b << 6;
            }
            0x5113 => self.prg_ram_bank = val & 7,
            0x5114..=0x5117 => self.prg_regs[(addr - 0x5114) as usize] = val,
            0x5120..=0x5127 => {
                self.chr_a[(addr - 0x5120) as usize] = val as u16 | (self.chr_hi as u16) << 8;
                self.last_set_b = false;
            }
            0x5128..=0x512B => {
                self.chr_b[(addr - 0x5128) as usize] = val as u16 | (self.chr_hi as u16) << 8;
                self.last_set_b = true;
            }
            0x5130 => self.chr_hi = val & 3,
            0x5203 => self.irq_target = val,
            0x5204 => self.irq_enable = val & 0x80 != 0,
            0x5205 => self.mul_a = val,
            0x5206 => self.mul_b = val,
            0x5C00..=0x5FFF => {
                // 模式 0/1:渲染期可写;模式 2:随时;模式 3:只读。放宽为模式<3 可写
                if self.exram_mode < 3 {
                    self.exram[(addr & 0x3FF) as usize] = val;
                }
            }
            0x6000..=0x7FFF => {
                if self.ram_protect1 == 2 && self.ram_protect2 == 1 {
                    return PrgWrite::Ram(
                        (self.prg_ram_bank as usize & 7) * 0x2000 + (addr as usize - 0x6000),
                    );
                }
            }
            0x8000..=0xFFFF => {
                if self.ram_protect1 == 2 && self.ram_protect2 == 1 {
                    let (is_ram, i) = self.prg_slot(addr);
                    if is_ram {
                        return PrgWrite::Ram(i);
                    }
                }
            }
            _ => {}
        }
        PrgWrite::Handled
    }

    fn ppu_map(&mut self, addr: u16) -> ChrTarget {
        // ExAttr:背景 pattern 用每 tile 的 4K bank
        if self.exram_mode == 1 && self.in_frame && !self.fetch_is_sprite() {
            let bank = (self.exattr_last & 0x3F) as usize | (self.chr_hi as usize) << 6;
            let banks = (self.chr_len / 0x1000).max(1);
            return ChrTarget::Rom((bank % banks) * 0x1000 + (addr as usize & 0xFFF));
        }
        let use_b = if !self.in_frame {
            // 渲染外($2007):用最后写入的组
            self.last_set_b && self.sprite16
        } else if self.sprite16 {
            !self.fetch_is_sprite()
        } else {
            false
        };
        ChrTarget::Rom(self.chr_index(use_b, addr))
    }

    fn nt_map(&mut self, addr: u16) -> NtRead {
        let q = ((addr as usize - 0x2000) & 0xFFF) / 0x400;
        let off = addr as usize & 0x3FF;
        let is_attr = off >= 0x3C0;
        // ExAttr:记录 tile 对应的 ExRAM 项;属性从 ExRAM 顶 2 位合成
        if self.exram_mode == 1 && !is_attr {
            self.exattr_last = self.exram[off];
        }
        if self.exram_mode == 1 && is_attr && self.in_frame && !self.fetch_is_sprite() {
            let b = self.exattr_last >> 6;
            let attr = b | b << 2 | b << 4 | b << 6;
            return NtRead::Value(attr);
        }
        match self.nt_mapping >> (q * 2) & 3 {
            0 => NtRead::Ciram(0, off),
            1 => NtRead::Ciram(1, off),
            2 => {
                if self.exram_mode < 2 {
                    NtRead::Value(self.exram[off])
                } else {
                    NtRead::Value(0)
                }
            }
            _ => {
                if is_attr {
                    NtRead::Value(self.fill_attr)
                } else {
                    NtRead::Value(self.fill_tile)
                }
            }
        }
    }

    fn nt_write_map(&mut self, addr: u16, val: u8) -> NtWrite {
        let q = ((addr as usize - 0x2000) & 0xFFF) / 0x400;
        let off = addr as usize & 0x3FF;
        match self.nt_mapping >> (q * 2) & 3 {
            0 => NtWrite::Ciram(0, off),
            1 => NtWrite::Ciram(1, off),
            2 => {
                if self.exram_mode < 2 {
                    self.exram[off] = val;
                }
                NtWrite::Handled
            }
            _ => NtWrite::Handled,
        }
    }

    fn mirroring(&self) -> Mirroring {
        Mirroring::Vertical // 未用:nt_map 已覆盖
    }

    fn ppu_addr_notify(&mut self, addr: u16, _ppu_cycle: u64) {
        self.idle_cycles = 0;
        if (0x2000..0x3000).contains(&addr) {
            let off = addr & 0x3FF;
            if off < 0x3C0 {
                if addr == self.last_nt_addr {
                    self.nt_consec += 1;
                    if self.nt_consec == 2 {
                        self.scanline_detected();
                    }
                } else {
                    self.nt_consec = 0;
                }
                self.last_nt_addr = addr;
            }
        } else if addr < 0x2000 {
            self.pt_fetches = self.pt_fetches.saturating_add(1);
            self.nt_consec = 0;
            self.last_nt_addr = 0xFFFF;
        }
    }

    fn ppu_ctrl_update(&mut self, ctrl: u8, mask: u8) {
        self.sprite16 = ctrl & 0x20 != 0;
        if mask & 0x18 == 0 {
            self.in_frame = false;
        }
    }

    fn cpu_tick(&mut self) {
        self.idle_cycles = self.idle_cycles.saturating_add(1);
        if self.idle_cycles > 100 {
            self.in_frame = false;
        }
        // 音源
        self.pulse1.tick();
        self.pulse2.tick();
        self.frame_div += 1;
        if self.frame_div >= 7457 {
            self.frame_div = 0;
            self.pulse1.quarter();
            self.pulse2.quarter();
            self.half_toggle = !self.half_toggle;
            if self.half_toggle {
                self.pulse1.half();
                self.pulse2.half();
            }
        }
    }

    fn irq_asserted(&self) -> bool {
        self.irq_pending && self.irq_enable
    }

    fn audio(&mut self) -> f32 {
        let p = self.pulse1.output() as f32 + self.pulse2.output() as f32;
        p * 0.006 + self.pcm as f32 * 0.0006
    }
}
