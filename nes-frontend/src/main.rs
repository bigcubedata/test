//! NES 桌面前端:winit 窗口 + pixels(wgpu) 整数缩放 + cpal 音频 + gilrs 手柄。
//!
//! 音画同步:以音频为主时钟——监视环形缓冲水位,微调核心重采样比(±1% 内),
//! 视频侧按 NTSC 场率的时间累加器决定每次重绘跑几帧(上限 3 帧防螺旋)。
//!
//! 键位:方向键;Z=B X=A;回车=Start 右Shift=Select;
//! R 复位,P 暂停,Tab 快进,1-8 选存档槽,F2 存档,F4 读档,Esc 退出。

#[cfg(feature = "dualsense")]
mod dualsense;
#[cfg(feature = "gamepad")]
mod pads;

use nes_core::{Buttons, Nes, Port, Region, FRAME_H, FRAME_W};
use pixels::{Pixels, SurfaceTexture};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::{ElementState, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{Window, WindowId};

type AudioRing = Arc<Mutex<std::collections::VecDeque<i16>>>;

struct App {
    nes: Nes,
    rom_path: PathBuf,
    scale: u32,
    window: Option<Arc<Window>>,
    pixels: Option<Pixels<'static>>,
    buttons: Buttons,
    paused: bool,
    fast_forward: bool,
    state_slot: u8,
    last_frame: Instant,
    time_debt: f64,
    last_battery_flush: Instant,
    audio_ring: Option<AudioRing>,
    audio_rate: f64,
    #[cfg(feature = "audio")]
    _audio_stream: Option<cpal::Stream>,
    #[cfg(feature = "gamepad")]
    pads: pads::GilrsPads,
    #[cfg(feature = "dualsense")]
    ds: dualsense::DualSense,
    audio_scratch: Vec<i16>,
}

impl App {
    fn state_path(&self) -> PathBuf {
        self.rom_path.with_extension(format!("state{}", self.state_slot))
    }

    fn sav_path(&self) -> PathBuf {
        self.rom_path.with_extension("sav")
    }

    fn flush_battery(&mut self) {
        if self.nes.take_battery_dirty() {
            if let Some(ram) = self.nes.battery_ram() {
                if let Err(e) = std::fs::write(self.sav_path(), ram) {
                    eprintln!("电池档写入失败: {e}");
                }
            }
        }
    }

    fn run_emulation(&mut self) {
        if self.paused {
            return;
        }
        // 时间累加器:按 NTSC 场率决定本次重绘应跑的帧数(防螺旋上限 3)
        let fps = self.nes.region.fps();
        let now = Instant::now();
        let dt = now.duration_since(self.last_frame).as_secs_f64();
        self.last_frame = now;
        self.time_debt = (self.time_debt + dt).min(3.0 / fps);
        let mut frames = 0;
        while self.time_debt >= 1.0 / fps && frames < 3 {
            self.time_debt -= 1.0 / fps;
            frames += 1;
        }
        if self.fast_forward {
            frames = 4;
            self.time_debt = 0.0;
        }
        for _ in 0..frames {
            let (p1, p2) = self.gather_input();
            self.nes.set_input(Port::P1, p1);
            self.nes.set_input(Port::P2, p2);
            self.nes.run_frame();
            self.pump_audio();
        }
        if self.last_battery_flush.elapsed() > Duration::from_secs(5) {
            self.last_battery_flush = Instant::now();
            self.flush_battery();
        }
    }

    fn pump_audio(&mut self) {
        self.audio_scratch.clear();
        let mut scratch = std::mem::take(&mut self.audio_scratch);
        self.nes.drain_audio(&mut scratch);
        if let Some(ring) = &self.audio_ring {
            let mut q = ring.lock().unwrap();
            // 动态速率控制:水位偏离目标(40ms)时微调重采样比
            let target = (self.audio_rate * 0.040) as isize;
            let fill = q.len() as isize;
            let error = (fill - target) as f64 / target.max(1) as f64;
            self.nes.set_rate_adjust(1.0 + 0.005 * error.clamp(-1.0, 1.0));
            let cap = target as usize * 4;
            for s in &scratch {
                if q.len() >= cap {
                    break; // 快进等场景直接丢弃冗余样本
                }
                q.push_back(*s);
            }
        }
        scratch.clear();
        self.audio_scratch = scratch;
    }

    fn render(&mut self) {
        if let Some(pixels) = &mut self.pixels {
            self.nes.render_rgba(pixels.frame_mut());
            if let Err(e) = pixels.render() {
                eprintln!("渲染失败: {e}");
            }
        }
    }

    fn handle_key(&mut self, code: KeyCode, pressed: bool) {
        let map = |b: Buttons, on: bool, all: &mut Buttons| all.set(b, on);
        match code {
            KeyCode::ArrowUp => map(Buttons::UP, pressed, &mut self.buttons),
            KeyCode::ArrowDown => map(Buttons::DOWN, pressed, &mut self.buttons),
            KeyCode::ArrowLeft => map(Buttons::LEFT, pressed, &mut self.buttons),
            KeyCode::ArrowRight => map(Buttons::RIGHT, pressed, &mut self.buttons),
            KeyCode::KeyZ => map(Buttons::B, pressed, &mut self.buttons),
            KeyCode::KeyX => map(Buttons::A, pressed, &mut self.buttons),
            KeyCode::Enter => map(Buttons::START, pressed, &mut self.buttons),
            KeyCode::ShiftRight => map(Buttons::SELECT, pressed, &mut self.buttons),
            KeyCode::F9 => {
                #[cfg(feature = "gamepad")]
                if pressed {
                    self.pads.learn_key();
                }
            }
            KeyCode::Tab => self.fast_forward = pressed,
            _ if !pressed => {}
            KeyCode::KeyP => self.paused = !self.paused,
            KeyCode::KeyR => self.nes.reset(),
            KeyCode::Digit1
            | KeyCode::Digit2
            | KeyCode::Digit3
            | KeyCode::Digit4
            | KeyCode::Digit5
            | KeyCode::Digit6
            | KeyCode::Digit7
            | KeyCode::Digit8 => {
                self.state_slot = match code {
                    KeyCode::Digit1 => 1,
                    KeyCode::Digit2 => 2,
                    KeyCode::Digit3 => 3,
                    KeyCode::Digit4 => 4,
                    KeyCode::Digit5 => 5,
                    KeyCode::Digit6 => 6,
                    KeyCode::Digit7 => 7,
                    _ => 8,
                };
                println!("存档槽 {}", self.state_slot);
            }
            KeyCode::F2 => {
                let path = self.state_path();
                match std::fs::write(&path, self.nes.save_state()) {
                    Ok(()) => println!("已存档到 {}", path.display()),
                    Err(e) => eprintln!("存档失败: {e}"),
                }
            }
            KeyCode::F4 => {
                let path = self.state_path();
                match std::fs::read(&path) {
                    Ok(data) => match self.nes.load_state(&data) {
                        Ok(()) => println!("已读档 {}", path.display()),
                        Err(e) => eprintln!("读档失败: {e}"),
                    },
                    Err(e) => eprintln!("读取 {} 失败: {e}", path.display()),
                }
            }
            _ => {}
        }
    }

    /// 键盘 | 通用手柄槽 | DualSense 槽 → P1/P2。
    #[allow(unused_mut)] // 两个手柄 feature 都关时 p1/p2 无需可变
    fn gather_input(&mut self) -> (Buttons, Buttons) {
        let mut p1 = self.buttons.0;
        let mut p2 = 0u8;
        #[cfg(feature = "gamepad")]
        {
            p1 |= self.pads.player(0).0;
            p2 |= self.pads.player(1).0;
        }
        #[cfg(feature = "dualsense")]
        {
            p1 |= self.ds.player(0).0;
            p2 |= self.ds.player(1).0;
        }
        (Buttons(p1), Buttons(p2))
    }

    fn poll_pads(&mut self) {
        #[cfg(feature = "gamepad")]
        {
            self.pads.poll();
            if self.pads.take_status_dirty() {
                if let Some(w) = &self.window {
                    match self.pads.learn_status() {
                        Some(s) => w.set_title(&s),
                        None => w.set_title(&self.base_title()),
                    }
                }
            }
        }
    }

    fn base_title(&self) -> String {
        format!(
            "nes — {}",
            self.rom_path.file_name().unwrap_or_default().to_string_lossy()
        )
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        let size = LogicalSize::new(
            (FRAME_W as u32 * self.scale) as f64,
            (FRAME_H as u32 * self.scale) as f64,
        );
        let attrs = Window::default_attributes()
            .with_title(format!(
                "nes — {}",
                self.rom_path.file_name().unwrap_or_default().to_string_lossy()
            ))
            .with_inner_size(size)
            .with_min_inner_size(LogicalSize::new(FRAME_W as f64, FRAME_H as f64));
        let window = Arc::new(event_loop.create_window(attrs).expect("创建窗口失败"));
        let inner = window.inner_size();
        let surface = SurfaceTexture::new(inner.width, inner.height, window.clone());
        let pixels = Pixels::new(FRAME_W as u32, FRAME_H as u32, surface).expect("初始化 wgpu 失败");
        self.window = Some(window);
        self.pixels = Some(pixels);
        self.last_frame = Instant::now();
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                self.flush_battery();
                event_loop.exit();
            }
            WindowEvent::Resized(size) => {
                if let Some(p) = &mut self.pixels {
                    let _ = p.resize_surface(size.width, size.height);
                }
            }
            WindowEvent::KeyboardInput { event, .. } => {
                if let PhysicalKey::Code(code) = event.physical_key {
                    if code == KeyCode::Escape {
                        self.flush_battery();
                        event_loop.exit();
                        return;
                    }
                    self.handle_key(code, event.state == ElementState::Pressed);
                }
            }
            WindowEvent::RedrawRequested => {
                self.poll_pads();
                self.run_emulation();
                self.render();
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, _event_loop: &ActiveEventLoop) {
        if let Some(w) = &self.window {
            w.request_redraw();
        }
    }
}

#[cfg(feature = "audio")]
fn start_audio(ring: AudioRing) -> Option<(cpal::Stream, f64)> {
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    let host = cpal::default_host();
    let device = host.default_output_device()?;
    let config = device.default_output_config().ok()?;
    let sample_rate = config.sample_rate() as f64;
    let channels = config.channels() as usize;
    let err_fn = |e| eprintln!("音频流错误: {e}");
    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => device
            .build_output_stream(
                config.config(),
                move |data: &mut [f32], _| {
                    let mut q = ring.lock().unwrap();
                    for frame in data.chunks_mut(channels) {
                        let s = q.pop_front().unwrap_or(0) as f32 / 32768.0;
                        for out in frame.iter_mut() {
                            *out = s;
                        }
                    }
                },
                err_fn,
                None,
            )
            .ok()?,
        cpal::SampleFormat::I16 => device
            .build_output_stream(
                config.config(),
                move |data: &mut [i16], _| {
                    let mut q = ring.lock().unwrap();
                    for frame in data.chunks_mut(channels) {
                        let s = q.pop_front().unwrap_or(0);
                        for out in frame.iter_mut() {
                            *out = s;
                        }
                    }
                },
                err_fn,
                None,
            )
            .ok()?,
        _ => return None,
    };
    stream.play().ok()?;
    Some((stream, sample_rate))
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut rom_path: Option<PathBuf> = None;
    let mut scale = 3u32;
    let mut region: Option<Region> = None;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--region" => {
                region = match args.next().as_deref() {
                    Some("pal") => Some(Region::Pal),
                    Some("dendy") => Some(Region::Dendy),
                    Some("ntsc") => Some(Region::Ntsc),
                    _ => {
                        eprintln!("--region 取 ntsc|pal|dendy");
                        std::process::exit(2);
                    }
                };
            }
            "--scale" => {
                scale = args
                    .next()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or_else(|| {
                        eprintln!("--scale 需要数字参数");
                        std::process::exit(2);
                    });
            }
            "--help" | "-h" => {
                println!("用法: nes <rom.nes> [--scale N] [--region ntsc|pal|dendy]");
                return;
            }
            _ => rom_path = Some(PathBuf::from(a)),
        }
    }
    let Some(rom_path) = rom_path else {
        eprintln!("用法: nes <rom.nes> [--scale N]");
        std::process::exit(2);
    };
    let rom = std::fs::read(&rom_path).unwrap_or_else(|e| {
        eprintln!("读取 {} 失败: {e}", rom_path.display());
        std::process::exit(2);
    });
    let mut nes = Nes::insert_with_region(&rom, region).unwrap_or_else(|e| {
        eprintln!("加载 ROM 失败: {e}");
        std::process::exit(2);
    });
    println!(
        "mapper {}{},PRG {}KB,CHR {}KB{}",
        nes.cart.info.mapper,
        if nes.cart.info.submapper != 0 {
            format!(".{}", nes.cart.info.submapper)
        } else {
            String::new()
        },
        nes.cart.info.prg_rom_len / 1024,
        if nes.cart.info.chr_rom_len > 0 {
            nes.cart.info.chr_rom_len / 1024
        } else {
            nes.cart.info.chr_ram_len / 1024
        },
        if nes.cart.info.battery { ",电池" } else { "" }
    );
    // 电池档
    let sav = rom_path.with_extension("sav");
    if let Ok(data) = std::fs::read(&sav) {
        nes.load_battery_ram(&data);
        println!("已载入电池档 {}", sav.display());
    }

    // 音频
    #[allow(unused_mut)] // audio feature 关闭时不再赋值
    let mut audio_ring = None;
    #[allow(unused_mut)]
    let mut audio_rate = 48000.0;
    #[cfg(feature = "audio")]
    let audio_stream;
    #[cfg(feature = "audio")]
    {
        let ring: AudioRing = Arc::new(Mutex::new(std::collections::VecDeque::new()));
        match start_audio(ring.clone()) {
            Some((stream, rate)) => {
                audio_rate = rate;
                nes.set_audio_rate(rate);
                audio_ring = Some(ring);
                audio_stream = Some(stream);
            }
            None => {
                eprintln!("音频初始化失败,静音运行");
                audio_stream = None;
            }
        }
    }

    #[cfg(feature = "gamepad")]
    let pads = pads::GilrsPads::new();
    #[cfg(feature = "dualsense")]
    let ds = dualsense::DualSense::start();

    let event_loop = EventLoop::new().expect("创建事件循环失败");
    event_loop.set_control_flow(ControlFlow::Poll);
    let mut app = App {
        nes,
        rom_path,
        scale,
        window: None,
        pixels: None,
        buttons: Buttons::default(),
        paused: false,
        fast_forward: false,
        state_slot: 1,
        last_frame: Instant::now(),
        time_debt: 0.0,
        last_battery_flush: Instant::now(),
        audio_ring,
        audio_rate,
        #[cfg(feature = "audio")]
        _audio_stream: audio_stream,
        #[cfg(feature = "gamepad")]
        pads,
        #[cfg(feature = "dualsense")]
        ds,
        audio_scratch: Vec::new(),
    };
    if let Err(e) = event_loop.run_app(&mut app) {
        eprintln!("事件循环错误: {e}");
    }
    app.flush_battery();
}
