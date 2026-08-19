//! 浏览器核心:零依赖 C-ABI 导出(不用 wasm-bindgen,JS 直接实例化 .wasm)。
//!
//! 约定:JS 先 `wasm_alloc` 拿缓冲写入 ROM 字节,再 `load_rom`;
//! 每帧 `set_buttons` + `run_frame`,然后从 `frame_ptr()` 读 RGBA、
//! 从 `audio_ptr()/audio_take()` 取 f32 单声道样本。

use nes_core::{Buttons, Nes, Port, FRAME_H, FRAME_W};
use std::sync::Mutex;

static EMU: Mutex<Option<Nes>> = Mutex::new(None);
static FRAME: Mutex<Vec<u8>> = Mutex::new(Vec::new());
static AUDIO: Mutex<Vec<f32>> = Mutex::new(Vec::new());
static SCRATCH: Mutex<Vec<i16>> = Mutex::new(Vec::new());

/// 分配一块由 JS 填充的缓冲(泄漏语义:load_rom 时回收使用)。
#[no_mangle]
pub extern "C" fn wasm_alloc(size: usize) -> *mut u8 {
    let mut v = vec![0u8; size];
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

/// # Safety
/// `ptr` 必须来自 `wasm_alloc(len)`。
#[no_mangle]
pub unsafe extern "C" fn load_rom(ptr: *mut u8, len: usize) -> i32 {
    let rom = Vec::from_raw_parts(ptr, len, len);
    match Nes::insert(&rom) {
        Ok(nes) => {
            *FRAME.lock().unwrap() = vec![0; FRAME_W * FRAME_H * 4];
            *EMU.lock().unwrap() = Some(nes);
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn set_sample_rate(rate: f32) {
    if let Some(nes) = EMU.lock().unwrap().as_mut() {
        nes.set_audio_rate(rate as f64);
    }
}

#[no_mangle]
pub extern "C" fn set_rate_adjust(adjust: f32) {
    if let Some(nes) = EMU.lock().unwrap().as_mut() {
        nes.set_rate_adjust(adjust as f64);
    }
}

#[no_mangle]
pub extern "C" fn set_buttons(p1: u32, p2: u32) {
    if let Some(nes) = EMU.lock().unwrap().as_mut() {
        nes.set_input(Port::P1, Buttons(p1 as u8));
        nes.set_input(Port::P2, Buttons(p2 as u8));
    }
}

#[no_mangle]
pub extern "C" fn run_frame() {
    let mut emu = EMU.lock().unwrap();
    if let Some(nes) = emu.as_mut() {
        nes.run_frame();
        nes.render_rgba(&mut FRAME.lock().unwrap()[..]);
        let mut scratch = SCRATCH.lock().unwrap();
        scratch.clear();
        nes.drain_audio(&mut scratch);
        let mut audio = AUDIO.lock().unwrap();
        for s in scratch.iter() {
            audio.push(*s as f32 / 32768.0);
        }
        // 上限 ~0.5s,防积压
        let len = audio.len();
        if len > 24000 {
            audio.drain(0..len - 24000);
        }
    }
}

#[no_mangle]
pub extern "C" fn reset() {
    if let Some(nes) = EMU.lock().unwrap().as_mut() {
        nes.reset();
    }
}

#[no_mangle]
pub extern "C" fn frame_ptr() -> *const u8 {
    FRAME.lock().unwrap().as_ptr()
}

#[no_mangle]
pub extern "C" fn frame_len() -> usize {
    FRAME.lock().unwrap().len()
}

/// 把最多 `max` 个样本拷到 `out`(由 wasm_alloc 分配),返回实际数量。
/// # Safety
/// `out` 至少能容纳 `max` 个 f32。
#[no_mangle]
pub unsafe extern "C" fn audio_take(out: *mut f32, max: usize) -> usize {
    let mut audio = AUDIO.lock().unwrap();
    let n = audio.len().min(max);
    for (i, s) in audio.drain(0..n).enumerate() {
        *out.add(i) = s;
    }
    n
}

#[no_mangle]
pub extern "C" fn audio_pending() -> usize {
    AUDIO.lock().unwrap().len()
}
