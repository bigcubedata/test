//! 2C02 PPU:逐 dot 渲染。
//!
//! 341 dots × 262 扫描线(NTSC),奇帧渲染开启时预渲染行短一个 dot。
//! loopy v/t/x/w 全模型;背景 8-dot 取数节奏;精灵评估状态机(含 overflow 硬件 bug);
//! sprite 0 hit 精确到 dot;所有渲染取数走真实 PPU 总线(mapper 能看到 A12)。

use crate::cartridge::Mirroring;
use crate::nes::Nes;
use serde::{Deserialize, Serialize};

pub const W: usize = 256;
pub const H: usize = 240;

#[derive(Serialize, Deserialize)]
pub struct Ppu {
    // 寄存器
    pub ctrl: u8,
    pub mask: u8,
    vblank: bool,
    suppress_vbl: bool,
    sprite0_hit: bool,
    sprite_overflow: bool,
    pub oam_addr: u8,
    // loopy
    v: u16,
    t: u16,
    fine_x: u8,
    w: bool,
    read_buffer: u8,
    pub open_bus: u8,
    /// 每一位最后被驱动的时刻(PPU dot 计),约 600ms 未刷新即衰减为 0
    ob_stamp: [u64; 8],
    // 位置
    pub scanline: u16, // 0-239 可见,240 post,241-260 vblank,261 pre-render
    pub dot: u16,      // 0-340
    odd_frame: bool,
    pub frame: u64,
    pub ppu_cycles: u64,
    // 背景管线
    nt_latch: u8,
    at_latch: u8,
    pt_lo_latch: u8,
    pt_hi_latch: u8,
    bg_lo: u16,
    bg_hi: u16,
    at_lo: u16,
    at_hi: u16,
    // OAM 与精灵
    pub oam: Vec<u8>,     // 256
    sec_oam: Vec<u8>,     // 32
    eval_n: u8,           // 主 OAM 精灵下标
    eval_m: u8,           // 字节下标(overflow bug 用)
    eval_copy: u8,        // 正在拷贝的剩余字节
    sec_index: u8,        // 次级 OAM 已填精灵数
    eval_done: bool,
    sprite0_next: bool, // 下一行含 sprite 0
    sprite0_cur: bool,  // 当前行含 sprite 0
    spr_pat_lo: [u8; 8],
    spr_pat_hi: [u8; 8],
    spr_attr: [u8; 8],
    spr_x: [u8; 8],
    spr_count: u8,
    // 输出
    #[serde(skip)]
    pub fb: Vec<u16>, // 256*240,值 = 强调位<<6 | 调色板值
    pub frame_ready: bool,
    pub palette: [u8; 32],
}

impl Default for Ppu {
    fn default() -> Ppu {
        Ppu {
            ctrl: 0,
            mask: 0,
            vblank: false,
            suppress_vbl: false,
            sprite0_hit: false,
            sprite_overflow: false,
            oam_addr: 0,
            v: 0,
            t: 0,
            fine_x: 0,
            w: false,
            read_buffer: 0,
            open_bus: 0,
            ob_stamp: [0; 8],
            scanline: 0,
            dot: 0,
            odd_frame: false,
            frame: 0,
            ppu_cycles: 0,
            nt_latch: 0,
            at_latch: 0,
            pt_lo_latch: 0,
            pt_hi_latch: 0,
            bg_lo: 0,
            bg_hi: 0,
            at_lo: 0,
            at_hi: 0,
            oam: vec![0; 256],
            sec_oam: vec![0xFF; 32],
            eval_n: 0,
            eval_m: 0,
            eval_copy: 0,
            sec_index: 0,
            eval_done: false,
            sprite0_next: false,
            sprite0_cur: false,
            spr_pat_lo: [0; 8],
            spr_pat_hi: [0; 8],
            spr_attr: [0; 8],
            spr_x: [0; 8],
            spr_count: 0,
            fb: vec![0; W * H],
            frame_ready: false,
            palette: [
                // 上电近似值,无关紧要
                0x09, 0x01, 0x00, 0x01, 0x00, 0x02, 0x02, 0x0D, 0x08, 0x10, 0x08, 0x24, 0x00,
                0x00, 0x04, 0x2C, 0x09, 0x01, 0x34, 0x03, 0x00, 0x04, 0x00, 0x14, 0x08, 0x3A,
                0x00, 0x02, 0x00, 0x20, 0x2C, 0x08,
            ],
        }
    }
}

impl Ppu {
    /// 软复位:控制/掩码/滚动锁存清零(v 与 OAM 保留,近似硬件)。
    pub fn soft_reset(&mut self) {
        self.ctrl = 0;
        self.mask = 0;
        self.w = false;
        self.t = 0;
        self.fine_x = 0;
        self.read_buffer = 0;
        self.odd_frame = false;
        self.scanline = 0;
        self.dot = 0;
    }

    pub fn rendering(&self) -> bool {
        self.mask & 0x18 != 0
    }

    /// 约 600ms 的 PPU dot 数。
    const OB_DECAY: u64 = 3_221_590;

    fn ob_refresh(&mut self, mask: u8, value: u8) {
        self.open_bus = self.open_bus & !mask | value & mask;
        for (i, s) in self.ob_stamp.iter_mut().enumerate() {
            if mask >> i & 1 != 0 {
                *s = self.ppu_cycles;
            }
        }
    }

    fn ob_get(&mut self) -> u8 {
        for (i, s) in self.ob_stamp.iter().enumerate() {
            if self.ppu_cycles.wrapping_sub(*s) > Self::OB_DECAY {
                self.open_bus &= !(1 << i);
            }
        }
        self.open_bus
    }

    pub fn nmi_line(&self) -> bool {
        self.vblank && self.ctrl & 0x80 != 0
    }

    fn palette_read(&self, addr: u16) -> u8 {
        let mut i = (addr & 0x1F) as usize;
        if i >= 16 && i % 4 == 0 {
            i -= 16;
        }
        self.palette[i]
    }

    fn palette_write(&mut self, addr: u16, val: u8) {
        let mut i = (addr & 0x1F) as usize;
        if i >= 16 && i % 4 == 0 {
            i -= 16;
        }
        self.palette[i] = val & 0x3F;
    }

    fn inc_coarse_x(&mut self) {
        if self.v & 0x001F == 31 {
            self.v &= !0x001F;
            self.v ^= 0x0400;
        } else {
            self.v += 1;
        }
    }

    fn inc_y(&mut self) {
        if self.v & 0x7000 != 0x7000 {
            self.v += 0x1000;
        } else {
            self.v &= !0x7000;
            let mut y = (self.v & 0x03E0) >> 5;
            if y == 29 {
                y = 0;
                self.v ^= 0x0800;
            } else if y == 31 {
                y = 0;
            } else {
                y += 1;
            }
            self.v = self.v & !0x03E0 | y << 5;
        }
    }

    fn copy_horizontal(&mut self) {
        self.v = self.v & !0x041F | self.t & 0x041F;
    }

    fn copy_vertical(&mut self) {
        self.v = self.v & !0x7BE0 | self.t & 0x7BE0;
    }
}

impl Nes {
    // ---------------- PPU 总线 ----------------

    /// 渲染与 $2007 的取数总线($0000-$3EFF;调色板不在总线上)。
    fn ppu_bus_read(&mut self, addr: u16) -> u8 {
        let addr = addr & 0x3FFF;
        self.cart.mapper.ppu_addr_notify(addr, self.ppu.ppu_cycles);
        if addr < 0x2000 {
            self.cart.chr_read(addr)
        } else {
            let (page, off) = self.nt_resolve(addr);
            if page < 2 {
                self.ciram[page * 0x400 + off]
            } else {
                self.cart.ext_vram[(page - 2) * 0x400 + off]
            }
        }
    }

    fn ppu_bus_write(&mut self, addr: u16, val: u8) {
        let addr = addr & 0x3FFF;
        self.cart.mapper.ppu_addr_notify(addr, self.ppu.ppu_cycles);
        if addr < 0x2000 {
            self.cart.chr_write(addr, val);
        } else {
            let (page, off) = self.nt_resolve(addr);
            if page < 2 {
                self.ciram[page * 0x400 + off] = val;
            } else {
                self.cart.ext_vram[(page - 2) * 0x400 + off] = val;
            }
        }
    }

    fn nt_resolve(&self, addr: u16) -> (usize, usize) {
        let a = (addr as usize - 0x2000) & 0xFFF;
        let table = a / 0x400;
        let off = a & 0x3FF;
        let page = match self.cart.mirroring() {
            Mirroring::Horizontal => table >> 1,
            Mirroring::Vertical => table & 1,
            Mirroring::SingleA => 0,
            Mirroring::SingleB => 1,
            Mirroring::FourScreen => table,
        };
        (page, off)
    }

    // ---------------- 寄存器接口($2000-$2007)----------------

    pub(crate) fn ppu_reg_read(&mut self, reg: u16) -> u8 {
        match reg {
            2 => {
                let vbl = self.ppu.vblank;
                // 恰在置位前 1 dot 读:本帧 vblank 标志被整个抹除(读到 clear 且无 NMI)。
                // 置位后 0/+1 dot 读的 NMI 抑制由"读清标志 → 周期末采不到边沿"自然产生。
                if self.ppu.scanline == 241 && self.ppu.dot == 1 {
                    self.ppu.suppress_vbl = true;
                }
                let val = (vbl as u8) << 7
                    | (self.ppu.sprite0_hit as u8) << 6
                    | (self.ppu.sprite_overflow as u8) << 5
                    | self.ppu.ob_get() & 0x1F;
                self.ppu.vblank = false;
                self.ppu.w = false;
                self.ppu.ob_refresh(0xE0, val);
                val
            }
            4 => {
                let val = if self.ppu.rendering()
                    && (self.ppu.scanline < 240 || self.ppu.scanline == 261)
                    && (1..=64).contains(&self.ppu.dot)
                {
                    0xFF // 次级 OAM 清空窗口
                } else {
                    let i = self.ppu.oam_addr as usize;
                    let mut b = self.ppu.oam[i];
                    if i % 4 == 2 {
                        b &= 0xE3; // 属性字节的未实现位
                    }
                    b
                };
                self.ppu.ob_refresh(0xFF, val);
                val
            }
            7 => {
                let addr = self.ppu.v & 0x3FFF;
                let val;
                if addr >= 0x3F00 {
                    // 调色板直读(6 位),缓冲装载调色板"下方"的 nametable
                    let buf = self.ppu_bus_read(addr & 0x2FFF);
                    self.ppu.read_buffer = buf;
                    let g = if self.ppu.mask & 1 != 0 { 0x30 } else { 0x3F };
                    val = self.ppu.palette_read(addr) & g | self.ppu.ob_get() & 0xC0;
                    self.ppu.ob_refresh(0x3F, val);
                } else {
                    val = self.ppu.read_buffer;
                    let buf = self.ppu_bus_read(addr);
                    self.ppu.read_buffer = buf;
                    self.ppu.ob_refresh(0xFF, val);
                }
                self.increment_v();
                val
            }
            _ => self.ppu.ob_get(),
        }
    }

    pub(crate) fn ppu_reg_write(&mut self, reg: u16, val: u8) {
        self.ppu.ob_refresh(0xFF, val);
        match reg {
            0 => {
                self.ppu.ctrl = val;
                self.ppu.t = self.ppu.t & !0x0C00 | ((val & 3) as u16) << 10;
                // NMI 使能的边沿由 tick 的电平检测自然产生
            }
            1 => self.ppu.mask = val,
            3 => self.ppu.oam_addr = val,
            4 => {
                let rendering_now = self.ppu.rendering()
                    && (self.ppu.scanline < 240 || self.ppu.scanline == 261);
                if rendering_now {
                    // 渲染期写 OAM:数据丢失,地址高位 +4(硬件 glitch)
                    self.ppu.oam_addr = self.ppu.oam_addr.wrapping_add(4);
                } else {
                    self.ppu.oam[self.ppu.oam_addr as usize] = val;
                    self.ppu.oam_addr = self.ppu.oam_addr.wrapping_add(1);
                }
            }
            5 => {
                if !self.ppu.w {
                    self.ppu.t = self.ppu.t & !0x001F | (val >> 3) as u16;
                    self.ppu.fine_x = val & 7;
                } else {
                    self.ppu.t = self.ppu.t & !0x73E0
                        | ((val & 7) as u16) << 12
                        | ((val >> 3) as u16) << 5;
                }
                self.ppu.w = !self.ppu.w;
            }
            6 => {
                if !self.ppu.w {
                    self.ppu.t = self.ppu.t & 0x00FF | ((val & 0x3F) as u16) << 8;
                } else {
                    self.ppu.t = self.ppu.t & 0xFF00 | val as u16;
                    self.ppu.v = self.ppu.t;
                    // mapper 观察 v 直变(A12)
                    let v = self.ppu.v;
                    let cyc = self.ppu.ppu_cycles;
                    self.cart.mapper.ppu_addr_notify(v & 0x3FFF, cyc);
                }
                self.ppu.w = !self.ppu.w;
            }
            7 => {
                let addr = self.ppu.v & 0x3FFF;
                if addr >= 0x3F00 {
                    self.ppu.palette_write(addr, val);
                } else {
                    self.ppu_bus_write(addr, val);
                }
                self.increment_v();
            }
            _ => {}
        }
    }

    fn increment_v(&mut self) {
        let rendering_now =
            self.ppu.rendering() && (self.ppu.scanline < 240 || self.ppu.scanline == 261);
        if rendering_now {
            // 渲染期访问 $2007:粗 X 与 Y 同时递增(硬件怪癖)
            self.ppu.inc_coarse_x();
            self.ppu.inc_y();
        } else {
            let step = if self.ppu.ctrl & 0x04 != 0 { 32 } else { 1 };
            self.ppu.v = self.ppu.v.wrapping_add(step) & 0x7FFF;
            // 递增后的地址会出现在 PPU 地址总线上(MMC3 的 A12 能看到)
            let v = self.ppu.v;
            let cyc = self.ppu.ppu_cycles;
            self.cart.mapper.ppu_addr_notify(v & 0x3FFF, cyc);
        }
    }

    // ---------------- 逐 dot 推进 ----------------

    pub(crate) fn ppu_step(&mut self) {
        self.ppu.ppu_cycles += 1;
        let sl = self.ppu.scanline;
        let dot = self.ppu.dot;
        let rendering = self.ppu.rendering();

        match sl {
            0..=239 => {
                if rendering {
                    self.render_line_dot(sl, dot, false);
                }
                if dot >= 1 && dot <= 256 && sl < 240 {
                    if !rendering {
                        self.output_pixel_blank(sl, dot);
                    }
                }
            }
            241 => {
                if dot == 1 {
                    if !self.ppu.suppress_vbl {
                        self.ppu.vblank = true;
                    }
                    self.ppu.suppress_vbl = false;
                    self.ppu.frame_ready = true;
                }
            }
            261 => {
                if dot == 1 {
                    self.ppu.vblank = false;
                    self.ppu.sprite0_hit = false;
                    self.ppu.sprite_overflow = false;
                }
                if rendering {
                    self.render_line_dot(sl, dot, true);
                    if (280..=304).contains(&dot) {
                        self.ppu.copy_vertical();
                    }
                }
            }
            _ => {}
        }

        // 位置推进。奇帧渲染开启时预渲染行短 1 dot:
        // 判定发生在处理完 (261,340) 回卷之际(blargg 10-even_odd_timing 校准),
        // 等效实现为跳过 (0,0) 空闲 dot。
        self.ppu.dot += 1;
        if self.ppu.dot > 340 {
            self.ppu.dot = 0;
            self.ppu.scanline += 1;
            if self.ppu.scanline > 261 {
                self.ppu.scanline = 0;
                self.ppu.frame += 1;
                self.ppu.odd_frame = !self.ppu.odd_frame;
                if self.ppu.odd_frame && self.ppu.rendering() {
                    self.ppu.dot = 1;
                }
            }
        }
    }

    /// 可见行与预渲染行的公共渲染工作(rendering 已确认开启)。
    ///
    /// 每 dot 顺序:移位 → 像素输出 → 总线取数 → dot 末重装移位寄存器。
    /// 这个顺序保证:px0 采样到预取 tile0 的 bit7,px8 恰好切换到 tile1。
    fn render_line_dot(&mut self, sl: u16, dot: u16, pre: bool) {
        // ---- 移位(2-257, 322-337),先于像素采样 ----
        if (2..=257).contains(&dot) || (322..=337).contains(&dot) {
            self.ppu.bg_lo <<= 1;
            self.ppu.bg_hi <<= 1;
            self.ppu.at_lo <<= 1;
            self.ppu.at_hi <<= 1;
        }
        // ---- 像素输出(1-256,可见行)----
        if !pre && (1..=256).contains(&dot) {
            self.output_pixel(sl, dot);
        }
        // ---- 背景取数节奏(1-256, 321-336)----
        let fetch_zone = (1..=256).contains(&dot) || (321..=336).contains(&dot);
        if fetch_zone {
            match dot % 8 {
                1 => {
                    let a = 0x2000 | self.ppu.v & 0x0FFF;
                    self.ppu.nt_latch = self.ppu_bus_read(a);
                }
                3 => {
                    let v = self.ppu.v;
                    let a = 0x23C0 | v & 0x0C00 | v >> 4 & 0x38 | v >> 2 & 0x07;
                    let at = self.ppu_bus_read(a);
                    let shift = (v >> 4 & 4 | v & 2) as u8;
                    self.ppu.at_latch = at >> shift & 0x03;
                }
                5 => {
                    let a = self.bg_pattern_addr(false);
                    self.ppu.pt_lo_latch = self.ppu_bus_read(a);
                }
                7 => {
                    let a = self.bg_pattern_addr(true);
                    self.ppu.pt_hi_latch = self.ppu_bus_read(a);
                }
                0 => {
                    self.ppu.inc_coarse_x();
                }
                _ => {}
            }
        }
        if dot == 256 {
            self.ppu.inc_y();
        }
        if dot == 257 {
            self.ppu.copy_horizontal();
        }
        // 337/339 的多余 NT 取数(MMC5 依赖其一)
        if dot == 337 || dot == 339 {
            let a = 0x2000 | self.ppu.v & 0x0FFF;
            self.ppu.nt_latch = self.ppu_bus_read(a);
        }
        // ---- dot 末重装:9,17,...,257 与 329,337 ----
        if (dot >= 9 && dot <= 257 && dot % 8 == 1) || dot == 329 || dot == 337 {
            self.reload_bg_shifters();
        }

        // ---- 精灵 ----
        if !pre {
            match dot {
                1..=64 => {
                    if dot == 1 {
                        self.ppu.sec_oam.iter_mut().for_each(|b| *b = 0xFF);
                        self.ppu.eval_n = 0;
                        self.ppu.eval_m = 0;
                        self.ppu.eval_copy = 0;
                        self.ppu.sec_index = 0;
                        self.ppu.eval_done = false;
                        self.ppu.sprite0_next = false;
                    }
                }
                65..=256 => {
                    if dot % 2 == 0 {
                        self.sprite_eval_step(sl);
                    }
                }
                _ => {}
            }
        }
        if (257..=320).contains(&dot) {
            self.ppu.oam_addr = 0;
            let unit = ((dot - 257) / 8) as usize;
            let sub = (dot - 257) % 8;
            match sub {
                1 | 3 => {
                    // 垃圾 NT 取数(维持总线节奏)
                    let a = 0x2000 | self.ppu.v & 0x0FFF;
                    self.ppu_bus_read(a);
                }
                5 => {
                    let a = self.sprite_pattern_addr(sl, unit, false);
                    let v = self.ppu_bus_read(a);
                    self.ppu.spr_pat_lo[unit] = self.finish_sprite_fetch(unit, v);
                }
                7 => {
                    let a = self.sprite_pattern_addr(sl, unit, true);
                    let v = self.ppu_bus_read(a);
                    self.ppu.spr_pat_hi[unit] = self.finish_sprite_fetch(unit, v);
                }
                _ => {}
            }
            if dot == 257 {
                // 锁存本行精灵计数与 sprite0 标记(供 258+ 取数与下一行输出)
                self.ppu.spr_count = self.ppu.sec_index;
                self.ppu.sprite0_cur = self.ppu.sprite0_next;
                for i in 0..8 {
                    self.ppu.spr_attr[i] = self.ppu.sec_oam[i * 4 + 2];
                    self.ppu.spr_x[i] = self.ppu.sec_oam[i * 4 + 3];
                }
            }
        }

    }

    fn reload_bg_shifters(&mut self) {
        self.ppu.bg_lo = self.ppu.bg_lo & 0xFF00 | self.ppu.pt_lo_latch as u16;
        self.ppu.bg_hi = self.ppu.bg_hi & 0xFF00 | self.ppu.pt_hi_latch as u16;
        let a = self.ppu.at_latch;
        self.ppu.at_lo = self.ppu.at_lo & 0xFF00 | if a & 1 != 0 { 0xFF } else { 0 };
        self.ppu.at_hi = self.ppu.at_hi & 0xFF00 | if a & 2 != 0 { 0xFF } else { 0 };
    }

    fn bg_pattern_addr(&self, high: bool) -> u16 {
        let fine_y = self.ppu.v >> 12 & 7;
        let table = if self.ppu.ctrl & 0x10 != 0 { 0x1000 } else { 0 };
        table + (self.ppu.nt_latch as u16) * 16 + fine_y + if high { 8 } else { 0 }
    }

    /// 每 2 dots 一步的精灵评估(在偶数 dot 调用)。
    fn sprite_eval_step(&mut self, sl: u16) {
        if self.ppu.eval_done {
            return;
        }
        let p = &mut self.ppu;
        let height = if p.ctrl & 0x20 != 0 { 16u16 } else { 8 };
        if p.eval_copy > 0 {
            // 拷贝该精灵其余字节
            let byte = 4 - p.eval_copy;
            let v = p.oam[(p.eval_n as usize * 4 + byte as usize) & 0xFF];
            p.sec_oam[(p.sec_index as usize * 4 + byte as usize) & 0x1F] = v;
            p.eval_copy -= 1;
            if p.eval_copy == 0 {
                p.sec_index += 1;
                p.eval_n = p.eval_n.wrapping_add(1);
                if p.eval_n == 0 || p.eval_n >= 64 {
                    p.eval_done = true;
                }
                p.eval_n %= 64;
            }
            return;
        }
        if p.sec_index < 8 {
            let y = p.oam[p.eval_n as usize * 4];
            p.sec_oam[p.sec_index as usize * 4] = y;
            let row = sl.wrapping_sub(y as u16);
            if row < height {
                if p.eval_n == 0 {
                    p.sprite0_next = true;
                }
                p.eval_copy = 3;
            } else {
                p.eval_n = p.eval_n.wrapping_add(1);
                if p.eval_n >= 64 {
                    p.eval_done = true;
                    p.eval_n = 0;
                }
            }
        } else {
            // 已满 8 个:overflow 扫描(带 m 斜向递增的硬件 bug)
            let y = p.oam[(p.eval_n as usize * 4 + p.eval_m as usize) & 0xFF];
            let row = sl.wrapping_sub(y as u16);
            if row < height {
                p.sprite_overflow = true;
                p.eval_done = true; // 后续 m 递增行为对可观测结果无影响,收束
            } else {
                p.eval_n = p.eval_n.wrapping_add(1);
                p.eval_m = (p.eval_m + 1) & 3; // bug:无进位联动
                if p.eval_n >= 64 {
                    p.eval_done = true;
                    p.eval_n = 0;
                }
            }
        }
    }

    fn sprite_pattern_addr(&self, sl: u16, unit: usize, high: bool) -> u16 {
        let base = unit * 4;
        let y = self.ppu.sec_oam[base] as u16;
        let tile = self.ppu.sec_oam[base + 1] as u16;
        let attr = self.ppu.sec_oam[base + 2];
        let mut row = sl.wrapping_sub(y) & 0x1F;
        let h16 = self.ppu.ctrl & 0x20 != 0;
        let height = if h16 { 16 } else { 8 };
        if row >= height {
            row = 0; // 空槽(y=FF)
        }
        if attr & 0x80 != 0 {
            row = height - 1 - row; // 垂直翻转
        }
        if h16 {
            let table = (tile & 1) << 12;
            let tile16 = tile & 0xFE | row >> 3;
            table | tile16 * 16 | row & 7 | if high { 8 } else { 0 }
        } else {
            let table = if self.ppu.ctrl & 0x08 != 0 { 0x1000 } else { 0 };
            table | tile * 16 | row | if high { 8 } else { 0 }
        }
    }

    /// 空槽置零(透明);水平翻转在装载时反转位序。
    fn finish_sprite_fetch(&self, unit: usize, mut v: u8) -> u8 {
        if unit >= self.ppu.spr_count as usize {
            return 0;
        }
        if self.ppu.spr_attr[unit] & 0x40 != 0 {
            v = v.reverse_bits();
        }
        v
    }

    fn output_pixel(&mut self, sl: u16, dot: u16) {
        let px = (dot - 1) as usize;
        let mask = self.ppu.mask;
        let show_bg = mask & 0x08 != 0 && (px >= 8 || mask & 0x02 != 0);
        let show_spr = mask & 0x10 != 0 && (px >= 8 || mask & 0x04 != 0);

        // 背景像素
        let mut bg_pat = 0u8;
        let mut bg_pal = 0u8;
        if show_bg {
            let bit = 15 - self.ppu.fine_x;
            bg_pat = ((self.ppu.bg_hi >> bit & 1) << 1 | self.ppu.bg_lo >> bit & 1) as u8;
            bg_pal = ((self.ppu.at_hi >> bit & 1) << 1 | self.ppu.at_lo >> bit & 1) as u8;
        }

        // 精灵像素:第一个不透明者胜
        let mut spr_pat = 0u8;
        let mut spr_pal = 0u8;
        let mut spr_behind = false;
        let mut spr_is0 = false;
        if show_spr && sl != 0 {
            for i in 0..self.ppu.spr_count as usize {
                let sx = self.ppu.spr_x[i] as usize;
                if px < sx || px > sx + 7 {
                    continue;
                }
                let bit = 7 - (px - sx);
                let pat = ((self.ppu.spr_pat_hi[i] >> bit & 1) << 1
                    | self.ppu.spr_pat_lo[i] >> bit & 1) as u8;
                if pat == 0 {
                    continue;
                }
                spr_pat = pat;
                spr_pal = self.ppu.spr_attr[i] & 0x03;
                spr_behind = self.ppu.spr_attr[i] & 0x20 != 0;
                spr_is0 = i == 0 && self.ppu.sprite0_cur;
                break;
            }
        }

        if std::env::var_os("NES_DEBUG_S0").is_some() && sl == 3 && px == 8 {
            eprintln!(
                "probe sl=3 px=8 mask={:02X} bg={bg_pat} spr={spr_pat} cnt={} x0={}",
                self.ppu.mask, self.ppu.spr_count, self.ppu.spr_x[0]
            );
        }
        // sprite 0 hit
        if spr_is0 && spr_pat != 0 && bg_pat != 0 && px != 255 && !self.ppu.sprite0_hit {
            self.ppu.sprite0_hit = true;
            if std::env::var_os("NES_DEBUG_S0").is_some() {
                eprintln!("s0-hit sl={sl} px={px} mask={:02X}", self.ppu.mask);
            }
        }

        // 优先级混合
        let pal_index = if bg_pat == 0 && spr_pat == 0 {
            0
        } else if spr_pat != 0 && (bg_pat == 0 || !spr_behind) {
            0x10 | spr_pal << 2 | spr_pat
        } else {
            bg_pal << 2 | bg_pat
        };
        let color = self.ppu.palette_read(0x3F00 | pal_index as u16);
        self.write_fb(sl, px, color);
    }

    fn output_pixel_blank(&mut self, sl: u16, dot: u16) {
        let px = (dot - 1) as usize;
        // 渲染关闭:输出 $3F00,若 v 指向调色板则输出该表项(背景调色板 hack)
        let color = if self.ppu.v & 0x3F00 == 0x3F00 {
            self.ppu.palette_read(self.ppu.v)
        } else {
            self.ppu.palette_read(0x3F00)
        };
        self.write_fb(sl, px, color);
    }

    fn write_fb(&mut self, sl: u16, px: usize, color: u8) {
        let grey = if self.ppu.mask & 1 != 0 { 0x30 } else { 0x3F };
        let emph = (self.ppu.mask >> 5) as u16;
        self.ppu.fb[sl as usize * W + px] = emph << 6 | (color & grey) as u16;
    }
}
