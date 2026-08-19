//! 顶层 `Nes`:所有部件的扁平所有者,总线分派与时钟互锁的枢纽。

use crate::apu::Apu;
use crate::cartridge::{Cartridge, RomError};
use crate::controller::{Buttons, Controller};
use crate::cpu::Cpu;
use crate::palette;
use crate::ppu::{Ppu, H, W};
use serde::{Deserialize, Serialize};

pub const FRAME_W: usize = W;
pub const FRAME_H: usize = H;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Region {
    Ntsc,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Port {
    P1,
    P2,
}

#[derive(Debug)]
pub enum StateError {
    BadHeader,
    RomMismatch,
    Decode(String),
}

impl std::fmt::Display for StateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StateError::BadHeader => write!(f, "存档头无效"),
            StateError::RomMismatch => write!(f, "存档与当前 ROM 不匹配"),
            StateError::Decode(e) => write!(f, "存档解码失败: {e}"),
        }
    }
}

impl std::error::Error for StateError {}

/// nestest 金标比对用的 CPU 快照。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CpuTrace {
    pub pc: u16,
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub p: u8,
    pub sp: u8,
    pub cycles: u64,
    pub ppu_scanline: u16,
    pub ppu_dot: u16,
}

#[derive(Serialize, Deserialize)]
pub struct Nes {
    pub cpu: Cpu,
    pub ppu: Ppu,
    pub apu: Apu,
    pub cart: Cartridge,
    pub controllers: [Controller; 2],
    ram: Vec<u8>,
    pub(crate) ciram: Vec<u8>,
    open_bus: u8,
    pub cycles: u64,
    pub region: Region,
}

impl Nes {
    pub fn insert(rom: &[u8]) -> Result<Nes, RomError> {
        let cart = Cartridge::parse(rom)?;
        let mut nes = Nes {
            cpu: Cpu::default(),
            ppu: Ppu::default(),
            apu: Apu::default(),
            cart,
            controllers: [Controller::default(), Controller::default()],
            ram: vec![0; 0x800],
            ciram: vec![0; 0x800],
            open_bus: 0,
            cycles: 0,
            region: Region::Ntsc,
        };
        nes.cpu_reset();
        Ok(nes)
    }

    /// 软复位(Reset 键)。
    pub fn reset(&mut self) {
        self.ppu.soft_reset();
        self.apu.write(0x4015, 0, self.cycles);
        self.cpu_reset();
    }

    // ---------------- 时钟互锁 ----------------

    /// CPU 周期前半:总线访问发生在第 2 个 PPU dot 之后(实测对齐 blargg 套件)。
    fn tick_begin(&mut self) {
        self.cycles += 1;
        // 轮询历史:保存本周期开始前的线状态(倒数第二周期语义)
        self.cpu.prev_nmi_pending = self.cpu.nmi_pending;
        self.cpu.prev_irq_line = self.cpu.irq_line;
        self.ppu_step();
        self.ppu_step();
    }

    /// 中断线采样点 = 总线访问之后(φ2 末)。第 3 个 dot 里的边沿要到
    /// 下一周期才被看见;$2002 读清 vblank 后同周期采不到边沿——
    /// 硬件的 NMI 抑制行为由此自然产生,无需特判。
    fn sample_interrupt_lines(&mut self) {
        let line = self.ppu.nmi_line();
        if line && !self.cpu.nmi_line {
            self.cpu.nmi_pending = true;
        }
        self.cpu.nmi_line = line;
        self.cpu.irq_line = self.apu.irq_asserted() || self.cart.mapper.irq_asserted();
    }

    /// CPU 周期后半:第 3 个 dot、APU、mapper,周期末采样中断线。
    fn tick_end(&mut self) {
        self.ppu_step();
        let expansion = self.cart.mapper.audio();
        self.apu.step(expansion);
        self.cart.mapper.cpu_tick();
        self.sample_interrupt_lines();
    }

    /// 无总线访问语义的整周期(内部周期用)。
    pub(crate) fn tick(&mut self) {
        self.tick_begin();
        self.tick_end();
    }

    pub(crate) fn read(&mut self, addr: u16) -> u8 {
        self.tick_begin();
        let v = self.bus_read(addr);
        self.open_bus = v;
        self.tick_end();
        v
    }

    pub(crate) fn write(&mut self, addr: u16, val: u8) {
        self.tick_begin();
        self.open_bus = val;
        self.bus_write(addr, val);
        self.tick_end();
    }

    // ---------------- CPU 总线 ----------------

    fn bus_read(&mut self, addr: u16) -> u8 {
        match addr {
            0x0000..=0x1FFF => self.ram[addr as usize & 0x7FF],
            0x2000..=0x3FFF => self.ppu_reg_read(addr & 7),
            0x4015 => {
                let ob = self.open_bus;
                self.apu.read_status(ob)
            }
            0x4016 => 0x40 | self.controllers[0].read_bit(),
            0x4017 => 0x40 | self.controllers[1].read_bit(),
            0x4000..=0x401F => self.open_bus,
            _ => self.cart.cpu_read(addr).unwrap_or(self.open_bus),
        }
    }

    fn bus_write(&mut self, addr: u16, val: u8) {
        match addr {
            0x0000..=0x1FFF => self.ram[addr as usize & 0x7FF] = val,
            0x2000..=0x3FFF => self.ppu_reg_write(addr & 7, val),
            0x4014 => self.oam_dma(val),
            0x4016 => {
                self.controllers[0].write_strobe(val & 1 != 0);
                self.controllers[1].write_strobe(val & 1 != 0);
            }
            0x4000..=0x4013 | 0x4015 | 0x4017 => {
                let c = self.cycles;
                self.apu.write(addr, val, c);
            }
            0x4018..=0x401F => {}
            _ => self.cart.cpu_write(addr, val),
        }
    }

    /// 第一张 nametable 的字节(测试文本抽取用)。
    pub fn peek_nametable(&self, index: usize) -> u8 {
        self.ciram[index & 0x3FF]
    }

    /// 无副作用读(调试/测试;IO 区返回 0)。
    pub fn peek(&self, addr: u16) -> u8 {
        match addr {
            0x0000..=0x1FFF => self.ram[addr as usize & 0x7FF],
            0x2000..=0x401F => 0,
            _ => self.cart.cpu_peek(addr).unwrap_or(0),
        }
    }

    // ---------------- DMA ----------------

    fn oam_dma(&mut self, page: u8) {
        // 写周期已计;halt 1 周期,奇数周期再补 1,而后 256×(读+写)
        self.tick();
        if self.cycles & 1 != 0 {
            self.tick();
        }
        let base = (page as u16) << 8;
        for i in 0..256 {
            let v = self.read(base + i);
            self.write(0x2004, v);
        }
    }

    /// DMC 取样 DMA(指令边界近似:3 周期 stall + 1 周期读)。
    fn dmc_dma(&mut self) {
        self.apu.dmc.fetch_pending = false;
        if self.apu.dmc.bytes_remaining == 0 {
            return; // 挂起后被 $4015 禁用等竞争:不再取样
        }
        self.tick();
        self.tick();
        self.tick();
        let addr = self.apu.dmc.addr_cur;
        let v = self.read(addr);
        self.apu.dmc.dma_finished(v);
    }

    // ---------------- 运行 ----------------

    /// 执行一条指令(含挂起的 DMA 服务)。
    pub fn step(&mut self) {
        if self.apu.dmc.fetch_pending {
            self.dmc_dma();
        }
        self.step_instruction();
    }

    /// 跑到下一帧就绪(VBlank 开始,(241,1))。
    pub fn run_frame(&mut self) {
        self.ppu.frame_ready = false;
        while !self.ppu.frame_ready {
            self.step();
        }
    }

    // ---------------- 对外 API ----------------

    pub fn set_input(&mut self, port: Port, buttons: Buttons) {
        let i = match port {
            Port::P1 => 0,
            Port::P2 => 1,
        };
        self.controllers[i].buttons = buttons;
    }

    /// 帧缓冲:每像素 = 强调位<<6 | 调色板值(0-63)。
    pub fn framebuffer(&self) -> &[u16] {
        &self.ppu.fb
    }

    /// 转 RGBA8(len = 256*240*4)。
    pub fn render_rgba(&self, out: &mut [u8]) {
        for (i, &px) in self.ppu.fb.iter().enumerate() {
            let [r, g, b] = palette::rgb_for(px);
            out[i * 4] = r;
            out[i * 4 + 1] = g;
            out[i * 4 + 2] = b;
            out[i * 4 + 3] = 0xFF;
        }
    }

    pub fn set_audio_rate(&mut self, rate: f64) {
        self.apu.set_sample_rate(rate);
    }

    /// 动态速率控制(音频主时钟):1.0 标称。
    pub fn set_rate_adjust(&mut self, adjust: f64) {
        self.apu.set_rate_adjust(adjust);
    }

    pub fn drain_audio(&mut self, out: &mut Vec<i16>) {
        out.append(&mut self.apu.out);
    }

    pub fn battery_ram(&self) -> Option<&[u8]> {
        if self.cart.info.battery {
            Some(&self.cart.prg_ram)
        } else {
            None
        }
    }

    pub fn load_battery_ram(&mut self, data: &[u8]) {
        let n = data.len().min(self.cart.prg_ram.len());
        self.cart.prg_ram[..n].copy_from_slice(&data[..n]);
    }

    /// 电池档自上次调用以来是否变脏(取走即清)。
    pub fn take_battery_dirty(&mut self) -> bool {
        std::mem::take(&mut self.cart.prg_ram_dirty)
    }

    // ---------------- trace / 测试钩子 ----------------

    pub fn trace(&self) -> CpuTrace {
        CpuTrace {
            pc: self.cpu.pc,
            a: self.cpu.a,
            x: self.cpu.x,
            y: self.cpu.y,
            p: self.cpu.p,
            sp: self.cpu.sp,
            cycles: self.cycles,
            ppu_scanline: self.ppu.scanline,
            ppu_dot: self.ppu.dot,
        }
    }

    pub fn set_pc(&mut self, pc: u16) {
        self.cpu.pc = pc;
    }

    // ---------------- 即时存档 ----------------

    pub fn save_state(&self) -> Vec<u8> {
        let mut out = b"NESS\x01".to_vec();
        bincode::serialize_into(&mut out, self).expect("状态序列化不应失败");
        out
    }

    pub fn load_state(&mut self, data: &[u8]) -> Result<(), StateError> {
        if data.len() < 5 || &data[0..4] != b"NESS" || data[4] != 1 {
            return Err(StateError::BadHeader);
        }
        let mut new: Nes =
            bincode::deserialize(&data[5..]).map_err(|e| StateError::Decode(e.to_string()))?;
        if new.cart.rom_hash != self.cart.rom_hash {
            return Err(StateError::RomMismatch);
        }
        // ROM 大块与瞬态缓冲不入档,从当前实例回填
        new.cart.prg_rom = std::mem::take(&mut self.cart.prg_rom);
        new.cart.chr_rom = std::mem::take(&mut self.cart.chr_rom);
        new.ppu.fb = std::mem::replace(&mut self.ppu.fb, Vec::new());
        if new.ppu.fb.len() != W * H {
            new.ppu.fb = vec![0; W * H];
        }
        new.apu.out = Vec::new();
        *self = new;
        Ok(())
    }
}
