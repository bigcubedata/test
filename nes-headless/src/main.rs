//! 无头运行器,供 CI 与调试:
//!   nes-headless nestest <rom> <log>       —— nestest 金标逐行比对
//!   nes-headless blargg <rom> [秒数上限]    —— blargg $6000 状态协议
//!   nes-headless run <rom> --frames N      —— 跑 N 帧输出帧哈希
//!   nes-headless ppm <rom> <out.ppm> [N]   —— 跑 N 帧后导出画面

use nes_core::Nes;
use std::process::ExitCode;

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
        Some("text") if args.len() >= 3 => {
            let frames: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(300);
            let mut nes = load(&args[2]);
            for _ in 0..frames {
                nes.run_frame();
            }
            print!("{}", nametable_text(&nes));
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
    Nes::insert(&rom).unwrap_or_else(|e| {
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
    let mut out = String::new();
    for row in 0..30 {
        let mut line = String::new();
        for col in 0..32 {
            let b = nes.peek_nametable(row * 32 + col);
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
    for _ in 0..frames {
        nes.run_frame();
    }
    let h = fnv(nes.framebuffer().iter().flat_map(|p| p.to_le_bytes()));
    println!("{frames} 帧后帧哈希: {h:016x}");
    ExitCode::SUCCESS
}

fn ppm(rom_path: &str, out_path: &str, frames: u64) -> ExitCode {
    let mut nes = load(rom_path);
    for _ in 0..frames {
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
