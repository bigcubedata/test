//! 测试 ROM 回归套件。
//!
//! 判定协议:blargg $6000 状态字节(新式)或 nametable 文本/结果码(2005 系)。
//! 已知未过项见 `#[ignore]` 标注(微时序长尾,详见 README 精度矩阵)。

use nes_core::Nes;
use std::path::PathBuf;

fn rom_path(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../test-roms")
        .join(rel)
}

fn load(rel: &str) -> Nes {
    let rom = std::fs::read(rom_path(rel)).unwrap_or_else(|e| panic!("读 {rel}: {e}"));
    Nes::insert(&rom).unwrap_or_else(|e| panic!("加载 {rel}: {e}"))
}

fn nametable_text(nes: &Nes) -> String {
    let mut out = String::new();
    for row in 0..30 {
        for col in 0..32 {
            let b = nes.peek_nametable(row * 32 + col);
            out.push(if (0x20..0x7F).contains(&b) { b as char } else { ' ' });
        }
        out.push('\n');
    }
    out
}

/// 运行 blargg 类测试 ROM 至通过/失败/超时。
fn run_blargg(rel: &str, max_frames: u64) {
    let mut nes = load(rel);
    let mut started = false;
    for frame in 0..max_frames {
        if !started && frame % 60 == 30 {
            let text = nametable_text(&nes);
            if text.contains("PASSED") || text.contains("Passed") {
                return;
            }
            if text.contains("FAILED") || text.contains("Failed") {
                panic!("{rel} 屏幕失败:\n{text}");
            }
            let t = text.trim();
            if t.len() == 3 && t.starts_with('$') {
                assert_eq!(t, "$01", "{rel} 结果码 {t}");
                return;
            }
        }
        nes.run_frame();
        let magic = [nes.peek(0x6001), nes.peek(0x6002), nes.peek(0x6003)];
        if magic == [0xDE, 0xB0, 0x61] {
            let status = nes.peek(0x6000);
            match status {
                0x80 => started = true,
                0x81 => {
                    for _ in 0..8 {
                        nes.run_frame();
                    }
                    nes.reset();
                }
                _ if started || status < 0x80 => {
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
                    assert_eq!(status, 0, "{rel} 失败(状态 {status:#04X}):\n{msg}");
                    return;
                }
                _ => {}
            }
        }
    }
    panic!("{rel} 超时({max_frames} 帧内未完成)");
}

// ---------------- CPU ----------------

#[test]
fn nestest_golden_log() {
    let mut nes = load("nestest/nestest.nes");
    let log = std::fs::read_to_string(rom_path("nestest/nestest.log")).unwrap();
    nes.set_pc(0xC000);
    for (i, line) in log.lines().filter(|l| l.len() > 10).enumerate() {
        let t = nes.trace();
        let pc = u16::from_str_radix(&line[0..4], 16).unwrap();
        let get = |key: &str| {
            let p = line.find(key).unwrap();
            u8::from_str_radix(&line[p + key.len()..p + key.len() + 2], 16).unwrap()
        };
        let cyc: u64 = line[line.find("CYC:").unwrap() + 4..].trim().parse().unwrap();
        assert!(
            t.pc == pc
                && t.a == get("A:")
                && t.x == get("X:")
                && t.y == get("Y:")
                && t.p == get("P:")
                && t.sp == get("SP:")
                && t.cycles == cyc,
            "第 {} 行分歧\n金标: {line}\n实际: {t:04X?}",
            i + 1
        );
        nes.step();
    }
    assert_eq!(nes.peek(0x0002), 0, "nestest 官方指令结果字节");
    assert_eq!(nes.peek(0x0003), 0, "nestest 非官方指令结果字节");
}

#[test]
fn instr_test_v5_official() {
    run_blargg("instr_test-v5/official_only.nes", 60 * 120);
}

#[test]
fn instr_timing() {
    run_blargg("instr_timing/instr_timing.nes", 60 * 60);
}

#[test]
fn instr_misc() {
    run_blargg("instr_misc/instr_misc.nes", 60 * 60);
}

#[test]
fn cpu_dummy_reads() {
    run_blargg("cpu_dummy_reads/cpu_dummy_reads.nes", 60 * 30);
}

#[test]
fn cpu_dummy_writes() {
    run_blargg("cpu_dummy_writes/cpu_dummy_writes_oam.nes", 60 * 60);
    run_blargg("cpu_dummy_writes/cpu_dummy_writes_ppumem.nes", 60 * 60);
}

#[test]
fn cpu_timing_test6() {
    run_blargg("cpu_timing_test6/cpu_timing_test.nes", 60 * 60);
}

#[test]
fn branch_timing() {
    run_blargg("branch_timing_tests/1.Branch_Basics.nes", 60 * 20);
    run_blargg("branch_timing_tests/2.Backward_Branch.nes", 60 * 20);
    run_blargg("branch_timing_tests/3.Forward_Branch.nes", 60 * 20);
}

#[test]
fn cpu_interrupts_cli_latency_and_nmi_brk() {
    run_blargg("cpu_interrupts_v2/rom_singles/1-cli_latency.nes", 60 * 60);
    run_blargg("cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes", 60 * 60);
}

#[test]
#[ignore = "已知未过:NMI 劫持 IRQ 向量 / DMA 交叠 / 分支延迟的 dot 级细节(M4)"]
fn cpu_interrupts_rest() {
    run_blargg("cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes", 60 * 60);
    run_blargg("cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes", 60 * 60);
    run_blargg("cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes", 60 * 60);
}

// ---------------- PPU ----------------

#[test]
fn ppu_vbl_nmi_suite() {
    for t in [
        "01-vbl_basics",
        "02-vbl_set_time",
        "03-vbl_clear_time",
        "04-nmi_control",
        "05-nmi_timing",
        "06-suppression",
        "07-nmi_on_timing",
        "08-nmi_off_timing",
        "09-even_odd_frames",
    ] {
        run_blargg(&format!("ppu_vbl_nmi/rom_singles/{t}.nes"), 60 * 90);
    }
}

#[test]
#[ignore = "已知未过:奇帧跳 dot 相对 $2001 写入的 1-dot 判定窗口(M4)"]
fn ppu_even_odd_timing() {
    run_blargg("ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes", 60 * 90);
}

#[test]
fn vbl_nmi_timing_2005_suite() {
    for t in [
        "1.frame_basics",
        "2.vbl_timing",
        "3.even_odd_frames",
        "4.vbl_clear_timing",
        "5.nmi_suppression",
        "6.nmi_disable",
        "7.nmi_timing",
    ] {
        run_blargg(&format!("vbl_nmi_timing/{t}.nes"), 60 * 90);
    }
}

#[test]
fn sprite_hit_suite() {
    for t in [
        "01.basics",
        "02.alignment",
        "03.corners",
        "04.flip",
        "05.left_clip",
        "06.right_edge",
        "07.screen_bottom",
        "08.double_height",
        "09.timing_basics",
        "10.timing_order",
        "11.edge_timing",
    ] {
        run_blargg(&format!("sprite_hit_tests_2005.10.05/{t}.nes"), 60 * 30);
    }
}

#[test]
fn sprite_overflow_suite() {
    for t in ["1.Basics", "2.Details", "3.Timing", "4.Obscure", "5.Emulator"] {
        run_blargg(&format!("sprite_overflow_tests/{t}.nes"), 60 * 30);
    }
}

#[test]
fn oam_and_open_bus() {
    run_blargg("oam_read/oam_read.nes", 60 * 60);
    run_blargg("oam_stress/oam_stress.nes", 60 * 120);
    run_blargg("ppu_open_bus/ppu_open_bus.nes", 60 * 90);
}

#[test]
fn blargg_ppu_tests_2005() {
    for t in [
        "palette_ram",
        "power_up_palette",
        "sprite_ram",
        "vbl_clear_time",
        "vram_access",
    ] {
        run_blargg(&format!("blargg_ppu_tests_2005.09.15b/{t}.nes"), 60 * 20);
    }
}

// ---------------- APU ----------------

#[test]
fn apu_test_suite() {
    for t in [
        "1-len_ctr",
        "2-len_table",
        "3-irq_flag",
        "4-jitter",
        "5-len_timing",
        "6-irq_flag_timing",
        "7-dmc_basics",
        "8-dmc_rates",
    ] {
        run_blargg(&format!("apu_test/rom_singles/{t}.nes"), 60 * 90);
    }
}

#[test]
#[ignore = "已知未过:软复位后 $4017 重写/长度计数器复位语义(M4)"]
fn apu_reset_suite() {
    for t in [
        "4017_timing",
        "4017_written",
        "irq_flag_cleared",
        "len_ctrs_enabled",
        "works_immediately",
    ] {
        run_blargg(&format!("apu_reset/{t}.nes"), 60 * 90);
    }
}

// ---------------- Mapper ----------------

#[test]
fn mmc3_suite() {
    for t in ["1-clocking", "2-details", "3-A12_clocking", "5-MMC3"] {
        run_blargg(&format!("mmc3_test/{t}.nes"), 60 * 60);
    }
}

#[test]
#[ignore = "已知未过:A12 两 dot 高电平波形与 MMC6 变体(M4)"]
fn mmc3_rest() {
    run_blargg("mmc3_test/4-scanline_timing.nes", 60 * 60);
    run_blargg("mmc3_test/6-MMC6.nes", 60 * 60);
}

// ---------------- 存档与确定性 ----------------

#[test]
fn savestate_roundtrip_deterministic() {
    let mut a = load("nestest/nestest.nes");
    for _ in 0..30 {
        a.run_frame();
    }
    let snap = a.save_state();
    // 继续跑 30 帧,记录参照
    for _ in 0..30 {
        a.run_frame();
    }
    let want: Vec<u16> = a.framebuffer().to_vec();
    let want_trace = a.trace();
    // 回档重放,必须逐位一致
    a.load_state(&snap).expect("读档");
    for _ in 0..30 {
        a.run_frame();
    }
    assert_eq!(a.framebuffer(), &want[..], "回放帧不一致");
    assert_eq!(a.trace(), want_trace, "回放 CPU 状态不一致");
}

/// 全部已支持 mapper 编号:合成 ROM 构造 + 跑 3 帧不崩。
#[test]
fn mapper_matrix_constructs() {
    let numbers: &[u16] = &[
        0, 1, 2, 3, 4, 5, 7, 9, 10, 11, 18, 19, 21, 22, 23, 24, 25, 26, 32, 33, 34, 38, 48, 65,
        66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 78, 79, 80, 85, 86, 87, 88, 89, 92, 93, 94,
        95, 97, 107, 112, 113, 118, 119, 133, 140, 145, 146, 148, 149, 152, 154, 163, 180, 184,
        185, 189, 206, 210,
    ];
    for &n in numbers {
        let mut rom = vec![0u8; 16];
        rom[0..4].copy_from_slice(b"NES\x1a");
        rom[4] = 2; // 32K PRG
        rom[5] = 1; // 8K CHR
        rom[6] = ((n & 0x0F) as u8) << 4;
        rom[7] = (n & 0xF0) as u8;
        let mut prg = vec![0xEAu8; 32 * 1024]; // NOP 海
        // 复位向量 $8000,IRQ/NMI 向量 $8000
        prg[0x7FFC] = 0x00;
        prg[0x7FFD] = 0x80;
        prg[0x7FFA] = 0x00;
        prg[0x7FFB] = 0x80;
        prg[0x7FFE] = 0x00;
        prg[0x7FFF] = 0x80;
        rom.extend_from_slice(&prg);
        rom.extend_from_slice(&vec![0u8; 8 * 1024]);
        let mut nes = Nes::insert(&rom).unwrap_or_else(|e| panic!("mapper {n}: {e}"));
        for _ in 0..3 {
            nes.run_frame();
        }
        // 存档往返也不崩
        let s = nes.save_state();
        nes.load_state(&s).unwrap_or_else(|e| panic!("mapper {n} 存档: {e}"));
    }
}

/// 构造 128K UNROM 合成 ROM:各 bank 首字节为 bank 号,固定 bank 里的代码
/// 把 `bank_val` 写到 $8000(该处 ROM 字节 = 0x00,与写入值不匹配),
/// 再把切换后 $8000 的标记字节存到 $0000。
fn build_unrom(nes2_submapper: Option<u8>, bank_val: u8) -> Vec<u8> {
    let mut rom = vec![0u8; 16];
    rom[0..4].copy_from_slice(b"NES\x1a");
    rom[4] = 8; // 128K PRG
    rom[5] = 0; // CHR RAM
    rom[6] = 2 << 4;
    if let Some(sub) = nes2_submapper {
        rom[7] = 0x08; // NES 2.0
        rom[8] = sub << 4;
    }
    let mut prg = vec![0u8; 128 * 1024];
    for bank in 0..8 {
        prg[bank * 0x4000] = bank as u8; // 标记
    }
    // 固定 bank(第 7 个,映射 $C000)偏移 0 处放代码
    let fixed = 7 * 0x4000;
    let code = [
        0xA9, bank_val, // LDA #bank_val
        0x8D, 0x00, 0x80, // STA $8000(切 bank;ROM 字节 = 0x00)
        0xAD, 0x00, 0x80, // LDA $8000(读标记)
        0x85, 0x00, // STA $00
        0x4C, 0x0A, 0xC0, // JMP $C00A(自旋)
    ];
    prg[fixed..fixed + code.len()].copy_from_slice(&code);
    // 向量 → $C000
    prg[fixed + 0x3FFC] = 0x00;
    prg[fixed + 0x3FFD] = 0xC0;
    prg[fixed + 0x3FFA] = 0x00;
    prg[fixed + 0x3FFB] = 0xC0;
    prg[fixed + 0x3FFE] = 0x00;
    prg[fixed + 0x3FFF] = 0xC0;
    rom.extend_from_slice(&prg);
    rom
}

/// Konami 无冲突板(Top Gun/魂斗罗):默认不得做 AND。
#[test]
fn uxrom_no_bus_conflicts_by_default() {
    let mut nes = Nes::insert(&build_unrom(None, 5)).unwrap();
    nes.run_frame();
    assert_eq!(nes.peek(0x0000), 5, "写入 5 应切到 bank 5(无 AND)");
}

/// NES 2.0 submapper 2 显式声明才模拟总线冲突。
#[test]
fn uxrom_bus_conflicts_with_submapper2() {
    let mut nes = Nes::insert(&build_unrom(Some(2), 5)).unwrap();
    nes.run_frame();
    // 5 & 0x00(ROM 字节)= 0 → 停在 bank 0
    assert_eq!(nes.peek(0x0000), 0, "submapper 2 应做 AND:5 & 0 = 0");
}

#[test]
fn savestate_rejects_wrong_rom() {
    let a = load("nestest/nestest.nes");
    let snap = a.save_state();
    let mut b = load("instr_timing/instr_timing.nes");
    assert!(b.load_state(&snap).is_err(), "跨 ROM 读档应被拒绝");
}
