//! nes-core — 周期级 NES/Famicom 模拟核心。
//!
//! 零 I/O:不开窗口、不出声、不读文件;外壳通过 [`Nes`] 的小 API 驱动。
//! 时序模型:CPU 每个周期恰好一次总线访问,访问内部先推进 PPU×3 dot 与 APU×1,
//! 因此 dummy read/write、中扫描线寄存器写、A12 边沿等副作用天然落在正确的周期上。

mod apu;
mod cartridge;
mod controller;
mod cpu;
mod nes;
mod palette;
mod ppu;

pub use cartridge::{Cartridge, Mirroring, RomError, RomInfo};
pub use controller::Buttons;
pub use nes::{Nes, Port, Region, StateError, FRAME_H, FRAME_W};
pub use palette::rgb_for;
