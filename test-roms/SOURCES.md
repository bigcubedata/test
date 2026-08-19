# 测试 ROM 来源与授权

本目录内容拷贝自社区测试 ROM 合集 [christopherpow/nes-test-roms](https://github.com/christopherpow/nes-test-roms),
仅保留本项目 CI 所需的子集(二进制 .nes、金标日志与说明文件,不含源码)。

这些测试 ROM 由各自作者(kevtris、blargg/Shay Green、bisqwit 等)以可自由再分发的形式发布,
是 NES 模拟器社区的标准精度测试集,不包含任何商业游戏内容。

| 子目录 | 作者 | 用途 |
|---|---|---|
| `nestest/` | kevtris | CPU 全指令金标日志比对(nestest.log) |
| `instr_test-v5/`、`instr_timing/`、`instr_misc/` | blargg | 指令行为/时序 |
| `cpu_dummy_reads/`、`cpu_dummy_writes/` | blargg | 冗余总线访问 |
| `cpu_interrupts_v2/`、`branch_timing_tests/`、`cpu_timing_test6/`、`cpu_reset/` | blargg | 中断与整机时序 |
| `ppu_vbl_nmi/`、`vbl_nmi_timing/` | blargg | VBlank/NMI 时序 |
| `sprite_hit_tests_2005.10.05/`、`sprite_overflow_tests/` | blargg | sprite 0 hit / overflow |
| `oam_read/`、`oam_stress/`、`ppu_open_bus/`、`blargg_ppu_tests_2005.09.15b/` | blargg | OAM 与 PPU 寄存器行为 |
| `apu_test/`、`apu_reset/` | blargg | APU 行为与时序 |
| `mmc3_test/` | blargg | MMC3 IRQ(A12)时序 |

商业游戏 ROM 一律不入库。
