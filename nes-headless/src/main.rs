//! 无头运行器,供 CI 与调试:
//!   nes-headless nestest <rom> <log>       —— nestest 金标逐行比对
//!   nes-headless blargg <rom> [秒数上限]    —— blargg $6000 状态协议
//!   nes-headless run <rom> --frames N      —— 跑 N 帧输出帧哈希
//!   nes-headless ppm <rom> <out.ppm> [N]   —— 跑 N 帧后导出画面
//!   nes-headless record <rom> <起> <止> <out.wav>
//!       —— [起,止) 帧录像:RGB24 裸帧→stdout(管给 ffmpeg),48kHz 音频→WAV

use nes_core::{Buttons, Nes, Port, Region};
use std::process::ExitCode;

/// NES_INPUT="帧:十六进制掩码,帧:掩码,…" —— 到达指定帧时把 P1 设为该掩码并保持。
/// 位序 A=01 B=02 SEL=04 STA=08 U=10 D=20 L=40 R=80。例:NES_INPUT="120:08,130:00"
struct InputScript {
    events: Vec<(u64, u8)>,
    idx: usize,
    events2: Vec<(u64, u8)>,
    idx2: usize,
}

impl InputScript {
    fn parse(var: &str) -> Vec<(u64, u8)> {
        let mut events: Vec<(u64, u8)> = std::env::var(var)
            .ok()
            .map(|s| {
                s.split(',')
                    .filter_map(|kv| {
                        let (f, m) = kv.trim().split_once(':')?;
                        Some((f.parse().ok()?, u8::from_str_radix(m, 16).ok()?))
                    })
                    .collect()
            })
            .unwrap_or_default();
        events.sort_by_key(|e| e.0);
        events
    }

    fn from_env() -> Self {
        InputScript {
            events: Self::parse("NES_INPUT"),
            idx: 0,
            events2: Self::parse("NES_INPUT2"),
            idx2: 0,
        }
    }

    fn apply(&mut self, nes: &mut Nes, frame: u64) {
        while let Some(&(f, m)) = self.events.get(self.idx) {
            if f > frame {
                break;
            }
            nes.set_input(Port::P1, Buttons(m));
            self.idx += 1;
        }
        while let Some(&(f, m)) = self.events2.get(self.idx2) {
            if f > frame {
                break;
            }
            nes.set_input(Port::P2, Buttons(m));
            self.idx2 += 1;
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("nestest") if args.len() >= 4 => nestest(&args[2], &args[3]),
        Some("blargg") if args.len() >= 3 => {
            let secs: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(60);
            blargg(&args[2], secs)
        }
        Some("run") if args.len() >= 3 => {
            let frames: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(60);
            run_hash(&args[2], frames)
        }
        Some("record") if args.len() >= 6 => {
            let start: u64 = args[3].parse().unwrap_or(0);
            let end: u64 = args[4].parse().unwrap_or(600);
            record(&args[2], start, end, &args[5])
        }
        Some("text") if args.len() >= 3 => {
            // 帧数可为逗号分隔的多个检查点:一次长跑,途中多次转储
            let spec = args.get(3).cloned().unwrap_or_else(|| "300".into());
            let mut checkpoints: Vec<u64> =
                spec.split(',').filter_map(|s| s.parse().ok()).collect();
            checkpoints.sort_unstable();
            let mut nes = load(&args[2]);
            let mut script = InputScript::from_env();
            let mut f = 0u64;
            for cp in &checkpoints {
                while f < *cp {
                    script.apply(&mut nes, f);
                    nes.run_frame();
                    f += 1;
                }
                if checkpoints.len() > 1 {
                    println!("== 帧 {cp} ==");
                }
                if let Ok(spec) = std::env::var("NES_PEEK") {
                    let vals: Vec<String> = spec
                        .split(',')
                        .filter_map(|s| s.trim().parse::<u16>().ok())
                        .map(|a| format!("[{a}]={:02X}", nes.peek(a)))
                        .collect();
                    println!("PEEK {}", vals.join(" "));
                }
                print!("{}", nametable_text(&nes));
            }
            ExitCode::SUCCESS
        }
        Some("ppm") if args.len() >= 4 => {
            let frames: u64 = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(60);
            ppm(&args[2], &args[3], frames)
        }
        _ => {
            eprintln!("用法: nes-headless <nestest|blargg|run|ppm> ...");
            ExitCode::from(2)
        }
    }
}

fn load(path: &str) -> Nes {
    let rom = std::fs::read(path).unwrap_or_else(|e| {
        eprintln!("读取 {path} 失败: {e}");
        std::process::exit(2);
    });
    // NES_REGION=pal|dendy|ntsc 覆盖(头无区制信息的 PAL 测试 ROM 用)
    let region = match std::env::var("NES_REGION").as_deref() {
        Ok("pal") => Some(Region::Pal),
        Ok("dendy") => Some(Region::Dendy),
        Ok("ntsc") => Some(Region::Ntsc),
        _ => None,
    };
    Nes::insert_with_region(&rom, region).unwrap_or_else(|e| {
        eprintln!("加载 {path} 失败: {e}");
        std::process::exit(2);
    })
}

// ---------------- nestest ----------------

struct GoldenLine {
    pc: u16,
    a: u8,
    x: u8,
    y: u8,
    p: u8,
    sp: u8,
    cyc: u64,
    raw: String,
}

fn parse_golden(log: &str) -> Vec<GoldenLine> {
    log.lines()
        .filter(|l| l.len() > 10)
        .map(|l| {
            let pc = u16::from_str_radix(&l[0..4], 16).expect("PC 列");
            let find = |key: &str| {
                let i = l.find(key).unwrap_or_else(|| panic!("缺 {key}: {l}"));
                u8::from_str_radix(&l[i + key.len()..i + key.len() + 2], 16).unwrap()
            };
            let a = find("A:");
            let x = find("X:");
            let y = find("Y:");
            let p = find("P:");
            let sp = find("SP:");
            let cyc_i = l.find("CYC:").expect("CYC 列");
            let cyc: u64 = l[cyc_i + 4..].trim().parse().unwrap();
            GoldenLine {
                pc,
                a,
                x,
                y,
                p,
                sp,
                cyc,
                raw: l.to_string(),
            }
        })
        .collect()
}

fn nestest(rom_path: &str, log_path: &str) -> ExitCode {
    let mut nes = load(rom_path);
    let log = std::fs::read_to_string(log_path).expect("读取金标日志");
    let golden = parse_golden(&log);
    nes.set_pc(0xC000); // 自动化入口

    for (i, g) in golden.iter().enumerate() {
        let t = nes.trace();
        let mine = format!(
            "{:04X}  A:{:02X} X:{:02X} Y:{:02X} P:{:02X} SP:{:02X} CYC:{}",
            t.pc, t.a, t.x, t.y, t.p, t.sp, t.cycles
        );
        if t.pc != g.pc
            || t.a != g.a
            || t.x != g.x
            || t.y != g.y
            || t.p != g.p
            || t.sp != g.sp
            || t.cycles != g.cyc
        {
            eprintln!("第 {} 行分歧:", i + 1);
            eprintln!("  金标: {}", g.raw);
            eprintln!("  实际: {mine}");
            if i > 0 {
                eprintln!("  上一行: {}", golden[i - 1].raw);
            }
            return ExitCode::FAILURE;
        }
        nes.step();
    }
    let r2 = nes.peek(0x0002);
    let r3 = nes.peek(0x0003);
    println!(
        "nestest 全部 {} 行对齐;结果字节 $02={:02X} $03={:02X}",
        golden.len(),
        r2,
        r3
    );
    if r2 != 0 || r3 != 0 {
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

// ---------------- blargg $6000 协议 ----------------

/// blargg 文字引擎:瓦片号即 ASCII。从 nametable 抽出可读文本。
fn nametable_text(nes: &Nes) -> String {
    // NES_NT=1 → 转储第二张 nametable
    let base: usize = std::env::var("NES_NT")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .map(|n| n * 1024)
        .unwrap_or(0);
    let mut out = String::new();
    for row in 0..30 {
        let mut line = String::new();
        for col in 0..32 {
            let b = nes.peek_nametable(base + row * 32 + col);
            line.push(if (0x20..0x7F).contains(&b) { b as char } else { ' ' });
        }
        let t = line.trim_end();
        if !t.is_empty() {
            out.push_str(t);
            out.push('\n');
        }
    }
    out
}

fn blargg(rom_path: &str, max_secs: u64) -> ExitCode {
    let mut nes = load(rom_path);
    let max_frames = max_secs * 60;
    let mut started = false;
    for frame in 0..max_frames {
        // 老式测试(2005 系)只写屏幕:每秒扫一次 nametable 文本
        if !started && frame % 60 == 30 {
            let text = nametable_text(&nes);
            if text.contains("PASSED") || text.contains("Passed") {
                println!("{text}");
                return ExitCode::SUCCESS;
            }
            if text.contains("FAILED") || text.contains("Failed") {
                println!("{text}");
                return ExitCode::FAILURE;
            }
            // 2005 系结果码:屏幕只显示 $0X,$01 = 通过
            let t = text.trim();
            if t.len() == 3 && t.starts_with('$') {
                println!("{t}");
                return if t == "$01" {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                };
            }
        }
        nes.run_frame();
        let status = nes.peek(0x6000);
        let magic = [nes.peek(0x6001), nes.peek(0x6002), nes.peek(0x6003)];
        if magic == [0xDE, 0xB0, 0x61] {
            if status == 0x80 {
                started = true;
                continue;
            }
            if status == 0x81 {
                // 请求复位:等 ~120ms 后按 reset
                for _ in 0..8 {
                    nes.run_frame();
                }
                nes.reset();
                continue;
            }
            if started || status < 0x80 {
                let mut msg = String::new();
                let mut addr = 0x6004u16;
                loop {
                    let b = nes.peek(addr);
                    if b == 0 || addr == 0x7FFF {
                        break;
                    }
                    msg.push(b as char);
                    addr += 1;
                }
                println!("状态 {status:#04X}");
                println!("{msg}");
                return if status == 0 {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                };
            }
        }
    }
    eprintln!("超时:{max_secs}s 内未完成");
    ExitCode::FAILURE
}

// ---------------- 录像(视频裸帧→stdout,音频→WAV) ----------------

/// [start,end) 帧区间:RGB24 裸帧写 stdout(管给 ffmpeg),48kHz 单声道
/// 16 位 PCM 写 WAV。进度与统计走 stderr。用法:
///   nes-headless record <rom> <start> <end> <out.wav> | ffmpeg -f rawvideo …
fn record(rom_path: &str, start: u64, end: u64, wav_path: &str) -> ExitCode {
    use std::io::Write;
    const RATE: f64 = 48000.0;
    let mut nes = load(rom_path);
    nes.set_audio_rate(RATE);
    let mut script = InputScript::from_env();
    let mut sink: Vec<i16> = Vec::new();
    for f in 0..start {
        script.apply(&mut nes, f);
        nes.run_frame();
        sink.clear();
        nes.drain_audio(&mut sink); // 丢弃起始段音频
    }
    let stdout = std::io::stdout();
    let mut vid = std::io::BufWriter::with_capacity(1 << 20, stdout.lock());
    let mut rgba = vec![0u8; nes_core::FRAME_W * nes_core::FRAME_H * 4];
    let mut rgb = vec![0u8; nes_core::FRAME_W * nes_core::FRAME_H * 3];
    let mut audio: Vec<i16> = Vec::new();
    sink.clear();
    for f in start..end {
        script.apply(&mut nes, f);
        nes.run_frame();
        nes.drain_audio(&mut audio);
        nes.render_rgba(&mut rgba);
        for (d, s) in rgb.chunks_exact_mut(3).zip(rgba.chunks_exact(4)) {
            d.copy_from_slice(&s[..3]);
        }
        if vid.write_all(&rgb).is_err() {
            eprintln!("视频管道中断于帧 {f}");
            return ExitCode::FAILURE;
        }
        if f % 1200 == 0 {
            eprintln!("录制 {f}/{end}");
        }
    }
    drop(vid);
    // WAV(PCM s16le 单声道 48kHz)
    let data_len = (audio.len() * 2) as u32;
    let mut w = Vec::with_capacity(44 + audio.len() * 2);
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&(36 + data_len).to_le_bytes());
    w.extend_from_slice(b"WAVEfmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes()); // PCM
    w.extend_from_slice(&1u16.to_le_bytes()); // 单声道
    w.extend_from_slice(&(RATE as u32).to_le_bytes());
    w.extend_from_slice(&((RATE as u32) * 2).to_le_bytes());
    w.extend_from_slice(&2u16.to_le_bytes());
    w.extend_from_slice(&16u16.to_le_bytes());
    w.extend_from_slice(b"data");
    w.extend_from_slice(&data_len.to_le_bytes());
    for s in &audio {
        w.extend_from_slice(&s.to_le_bytes());
    }
    if std::fs::write(wav_path, w).is_err() {
        eprintln!("写 {wav_path} 失败");
        return ExitCode::FAILURE;
    }
    let frames = end - start;
    let fps = frames as f64 * RATE / audio.len() as f64;
    eprintln!(
        "录制完成:{frames} 帧,{} 音频样本,精确帧率 {fps:.4} fps",
        audio.len()
    );
    ExitCode::SUCCESS
}

// ---------------- 帧哈希 / 截图 ----------------

fn fnv(data: impl Iterator<Item = u8>) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

fn run_hash(rom_path: &str, frames: u64) -> ExitCode {
    let mut nes = load(rom_path);
    let mut script = InputScript::from_env();
    for f in 0..frames {
        script.apply(&mut nes, f);
        nes.run_frame();
    }
    // NES_PEEK="16,17,…":打印零页字节(十进制地址,十六进制值)
    if let Ok(spec) = std::env::var("NES_PEEK") {
        let vals: Vec<String> = spec
            .split(',')
            .filter_map(|s| s.trim().parse::<u16>().ok())
            .map(|a| format!("[{a}]={:02X}", nes.peek(a)))
            .collect();
        println!("PEEK {}", vals.join(" "));
    }
    // NES_TRACE=N:跑完后单步打印 N 条指令踪迹(调试卡死用)
    if let Ok(n) = std::env::var("NES_TRACE").as_deref().map(|s| s.parse::<u32>().unwrap_or(0)) {
        for _ in 0..n {
            let t = nes.trace();
            println!("{:04X} A:{:02X} X:{:02X} Y:{:02X} SP:{:02X}", t.pc, t.a, t.x, t.y, t.sp);
            nes.step();
        }
    }
    let h = fnv(nes.framebuffer().iter().flat_map(|p| p.to_le_bytes()));
    println!("{frames} 帧后帧哈希: {h:016x}");
    ExitCode::SUCCESS
}

fn ppm(rom_path: &str, out_path: &str, frames: u64) -> ExitCode {
    let mut nes = load(rom_path);
    let mut script = InputScript::from_env();
    for f in 0..frames {
        script.apply(&mut nes, f);
        nes.run_frame();
    }
    let mut rgba = vec![0u8; nes_core::FRAME_W * nes_core::FRAME_H * 4];
    nes.render_rgba(&mut rgba);
    let mut out = format!("P6\n{} {}\n255\n", nes_core::FRAME_W, nes_core::FRAME_H).into_bytes();
    for px in rgba.chunks(4) {
        out.extend_from_slice(&px[0..3]);
    }
    std::fs::write(out_path, out).expect("写 PPM");
    println!("已写出 {out_path}");
    ExitCode::SUCCESS
}
