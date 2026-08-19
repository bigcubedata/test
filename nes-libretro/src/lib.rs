//! libretro 核心:手写 FFI(API v1 子集),RetroArch 可加载。
//! 提供:XRGB8888 视频、48kHz 立体声、手柄双人、存档(serialize)、
//! 电池 RAM(SAVE_RAM 内存接口)、软复位、NTSC/PAL 时序上报。

use nes_core::{Buttons, Nes, Port, FRAME_H, FRAME_W};
use std::ffi::{c_char, c_uint, c_void};
use std::sync::Mutex;

const RETRO_API_VERSION: c_uint = 1;
const RETRO_DEVICE_JOYPAD: c_uint = 1;
const RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: c_uint = 10;
const RETRO_PIXEL_FORMAT_XRGB8888: c_uint = 1;
const RETRO_MEMORY_SAVE_RAM: c_uint = 0;
// joypad id
const ID_B: c_uint = 0;
const ID_Y: c_uint = 1;
const ID_SELECT: c_uint = 2;
const ID_START: c_uint = 3;
const ID_UP: c_uint = 4;
const ID_DOWN: c_uint = 5;
const ID_LEFT: c_uint = 6;
const ID_RIGHT: c_uint = 7;
const ID_A: c_uint = 8;

#[repr(C)]
pub struct RetroSystemInfo {
    library_name: *const c_char,
    library_version: *const c_char,
    valid_extensions: *const c_char,
    need_fullpath: bool,
    block_extract: bool,
}

#[repr(C)]
pub struct RetroGameGeometry {
    base_width: c_uint,
    base_height: c_uint,
    max_width: c_uint,
    max_height: c_uint,
    aspect_ratio: f32,
}

#[repr(C)]
pub struct RetroSystemTiming {
    fps: f64,
    sample_rate: f64,
}

#[repr(C)]
pub struct RetroSystemAvInfo {
    geometry: RetroGameGeometry,
    timing: RetroSystemTiming,
}

#[repr(C)]
pub struct RetroGameInfo {
    path: *const c_char,
    data: *const c_void,
    size: usize,
    meta: *const c_char,
}

type EnvironmentFn = unsafe extern "C" fn(c_uint, *mut c_void) -> bool;
type VideoRefreshFn = unsafe extern "C" fn(*const c_void, c_uint, c_uint, usize);
type AudioSampleFn = unsafe extern "C" fn(i16, i16);
type AudioSampleBatchFn = unsafe extern "C" fn(*const i16, usize) -> usize;
type InputPollFn = unsafe extern "C" fn();
type InputStateFn = unsafe extern "C" fn(c_uint, c_uint, c_uint, c_uint) -> i16;

struct Callbacks {
    env: Option<EnvironmentFn>,
    video: Option<VideoRefreshFn>,
    audio_batch: Option<AudioSampleBatchFn>,
    input_poll: Option<InputPollFn>,
    input_state: Option<InputStateFn>,
}

unsafe impl Send for Callbacks {}

static CBS: Mutex<Callbacks> = Mutex::new(Callbacks {
    env: None,
    video: None,
    audio_batch: None,
    input_poll: None,
    input_state: None,
});
static EMU: Mutex<Option<Nes>> = Mutex::new(None);
static VIDEO_BUF: Mutex<Vec<u32>> = Mutex::new(Vec::new());
static AUDIO_BUF: Mutex<Vec<i16>> = Mutex::new(Vec::new());
static SCRATCH: Mutex<Vec<i16>> = Mutex::new(Vec::new());

#[no_mangle]
pub extern "C" fn retro_api_version() -> c_uint {
    RETRO_API_VERSION
}

#[no_mangle]
pub extern "C" fn retro_set_environment(cb: EnvironmentFn) {
    CBS.lock().unwrap().env = Some(cb);
}
#[no_mangle]
pub extern "C" fn retro_set_video_refresh(cb: VideoRefreshFn) {
    CBS.lock().unwrap().video = Some(cb);
}
#[no_mangle]
pub extern "C" fn retro_set_audio_sample(_cb: AudioSampleFn) {}
#[no_mangle]
pub extern "C" fn retro_set_audio_sample_batch(cb: AudioSampleBatchFn) {
    CBS.lock().unwrap().audio_batch = Some(cb);
}
#[no_mangle]
pub extern "C" fn retro_set_input_poll(cb: InputPollFn) {
    CBS.lock().unwrap().input_poll = Some(cb);
}
#[no_mangle]
pub extern "C" fn retro_set_input_state(cb: InputStateFn) {
    CBS.lock().unwrap().input_state = Some(cb);
}

#[no_mangle]
pub extern "C" fn retro_init() {
    *VIDEO_BUF.lock().unwrap() = vec![0u32; FRAME_W * FRAME_H];
}
#[no_mangle]
pub extern "C" fn retro_deinit() {}

/// # Safety
/// `info` 由前端提供,须指向有效结构。
#[no_mangle]
pub unsafe extern "C" fn retro_get_system_info(info: *mut RetroSystemInfo) {
    (*info).library_name = b"rnes\0".as_ptr() as *const c_char;
    (*info).library_version = b"0.1.0\0".as_ptr() as *const c_char;
    (*info).valid_extensions = b"nes\0".as_ptr() as *const c_char;
    (*info).need_fullpath = false;
    (*info).block_extract = false;
}

/// # Safety
/// 同上。
#[no_mangle]
pub unsafe extern "C" fn retro_get_system_av_info(info: *mut RetroSystemAvInfo) {
    let fps = EMU
        .lock()
        .unwrap()
        .as_ref()
        .map(|n| n.region.fps())
        .unwrap_or(60.0988);
    (*info).geometry = RetroGameGeometry {
        base_width: FRAME_W as c_uint,
        base_height: FRAME_H as c_uint,
        max_width: FRAME_W as c_uint,
        max_height: FRAME_H as c_uint,
        aspect_ratio: 4.0 / 3.0,
    };
    (*info).timing = RetroSystemTiming {
        fps,
        sample_rate: 48000.0,
    };
}

#[no_mangle]
pub extern "C" fn retro_set_controller_port_device(_port: c_uint, _device: c_uint) {}

#[no_mangle]
pub extern "C" fn retro_reset() {
    if let Some(nes) = EMU.lock().unwrap().as_mut() {
        nes.reset();
    }
}

/// # Safety
/// `game.data` 指向 `game.size` 字节的 ROM。
#[no_mangle]
pub unsafe extern "C" fn retro_load_game(game: *const RetroGameInfo) -> bool {
    if game.is_null() {
        return false;
    }
    let data = std::slice::from_raw_parts((*game).data as *const u8, (*game).size);
    let Ok(mut nes) = Nes::insert(data) else {
        return false;
    };
    nes.set_audio_rate(48000.0);
    // XRGB8888
    if let Some(env) = CBS.lock().unwrap().env {
        let mut fmt: c_uint = RETRO_PIXEL_FORMAT_XRGB8888;
        env(
            RETRO_ENVIRONMENT_SET_PIXEL_FORMAT,
            &mut fmt as *mut c_uint as *mut c_void,
        );
    }
    *EMU.lock().unwrap() = Some(nes);
    true
}

#[no_mangle]
pub extern "C" fn retro_load_game_special(
    _type: c_uint,
    _info: *const RetroGameInfo,
    _num: usize,
) -> bool {
    false
}

#[no_mangle]
pub extern "C" fn retro_unload_game() {
    *EMU.lock().unwrap() = None;
}

#[no_mangle]
pub extern "C" fn retro_get_region() -> c_uint {
    let pal = EMU
        .lock()
        .unwrap()
        .as_ref()
        .map(|n| n.region != nes_core::Region::Ntsc)
        .unwrap_or(false);
    pal as c_uint
}

fn read_pad(input: InputStateFn, port: c_uint) -> Buttons {
    let mut b = Buttons::default();
    let get = |id: c_uint| unsafe { input(port, RETRO_DEVICE_JOYPAD, 0, id) != 0 };
    b.set(Buttons::A, get(ID_A));
    b.set(Buttons::B, get(ID_B) || get(ID_Y));
    b.set(Buttons::SELECT, get(ID_SELECT));
    b.set(Buttons::START, get(ID_START));
    b.set(Buttons::UP, get(ID_UP));
    b.set(Buttons::DOWN, get(ID_DOWN));
    b.set(Buttons::LEFT, get(ID_LEFT));
    b.set(Buttons::RIGHT, get(ID_RIGHT));
    b
}

#[no_mangle]
pub extern "C" fn retro_run() {
    let (video, audio_batch, input_poll, input_state) = {
        let cbs = CBS.lock().unwrap();
        (cbs.video, cbs.audio_batch, cbs.input_poll, cbs.input_state)
    };
    let mut emu = EMU.lock().unwrap();
    let Some(nes) = emu.as_mut() else { return };
    if let Some(poll) = input_poll {
        unsafe { poll() };
    }
    if let Some(input) = input_state {
        nes.set_input(Port::P1, read_pad(input, 0));
        nes.set_input(Port::P2, read_pad(input, 1));
    }
    nes.run_frame();

    // 视频:调色板值 → XRGB8888
    let mut vbuf = VIDEO_BUF.lock().unwrap();
    for (dst, &px) in vbuf.iter_mut().zip(nes.framebuffer()) {
        let [r, g, b] = nes_core::rgb_for(px);
        *dst = (r as u32) << 16 | (g as u32) << 8 | b as u32;
    }
    if let Some(video) = video {
        unsafe {
            video(
                vbuf.as_ptr() as *const c_void,
                FRAME_W as c_uint,
                FRAME_H as c_uint,
                FRAME_W * 4,
            )
        };
    }

    // 音频:mono → 立体声交错
    let mut scratch = SCRATCH.lock().unwrap();
    scratch.clear();
    nes.drain_audio(&mut scratch);
    let mut abuf = AUDIO_BUF.lock().unwrap();
    abuf.clear();
    for &s in scratch.iter() {
        abuf.push(s);
        abuf.push(s);
    }
    if let Some(batch) = audio_batch {
        unsafe { batch(abuf.as_ptr(), abuf.len() / 2) };
    }
}

const STATE_SLACK: usize = 65536;

#[no_mangle]
pub extern "C" fn retro_serialize_size() -> usize {
    EMU.lock()
        .unwrap()
        .as_ref()
        .map(|n| n.save_state().len() + STATE_SLACK)
        .unwrap_or(0)
}

/// # Safety
/// `data` 至少 `size` 字节。
#[no_mangle]
pub unsafe extern "C" fn retro_serialize(data: *mut c_void, size: usize) -> bool {
    let Some(state) = EMU.lock().unwrap().as_ref().map(|n| n.save_state()) else {
        return false;
    };
    if state.len() + 8 > size {
        return false;
    }
    let out = std::slice::from_raw_parts_mut(data as *mut u8, size);
    out[0..8].copy_from_slice(&(state.len() as u64).to_le_bytes());
    out[8..8 + state.len()].copy_from_slice(&state);
    true
}

/// # Safety
/// 同上。
#[no_mangle]
pub unsafe extern "C" fn retro_unserialize(data: *const c_void, size: usize) -> bool {
    if size < 8 {
        return false;
    }
    let inp = std::slice::from_raw_parts(data as *const u8, size);
    let len = u64::from_le_bytes(inp[0..8].try_into().unwrap()) as usize;
    if 8 + len > size {
        return false;
    }
    let mut emu = EMU.lock().unwrap();
    match emu.as_mut() {
        Some(nes) => nes.load_state(&inp[8..8 + len]).is_ok(),
        None => false,
    }
}

#[no_mangle]
pub extern "C" fn retro_cheat_reset() {}
#[no_mangle]
pub extern "C" fn retro_cheat_set(_index: c_uint, _enabled: bool, _code: *const c_char) {}

#[no_mangle]
pub extern "C" fn retro_get_memory_data(id: c_uint) -> *mut c_void {
    if id == RETRO_MEMORY_SAVE_RAM {
        if let Some(nes) = EMU.lock().unwrap().as_mut() {
            return nes.cart.prg_ram.as_mut_ptr() as *mut c_void;
        }
    }
    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn retro_get_memory_size(id: c_uint) -> usize {
    if id == RETRO_MEMORY_SAVE_RAM {
        if let Some(nes) = EMU.lock().unwrap().as_ref() {
            return nes.cart.prg_ram.len();
        }
    }
    0
}
