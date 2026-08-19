# rnes — 周期级 NES/Famicom 模拟器(Rust)

模拟 Ricoh 2A03(6502 内核 + APU)与 2C02 PPU——即 UA6527/UA6528 兼容机芯片的原型。
纯 Rust,零 C 依赖;核心 `nes-core` 无任何 I/O,可嵌入、可测试、可移植 wasm。

## 状态(精度测试矩阵)

| 套件 | 结果 |
|---|---|
| nestest 金标日志(8991 行,含全部非官方指令) | ✅ 全对齐 |
| blargg instr_test-v5(16 项) | ✅ 16/16 |
| instr_timing / instr_misc / cpu_timing_test6 | ✅ 全过 |
| cpu_dummy_reads / cpu_dummy_writes | ✅ 全过 |
| branch_timing_tests | ✅ 3/3 |
| cpu_interrupts_v2 | ⚠️ 2/5(NMI 劫持向量/DMA 交叠微时序,见路线图) |
| ppu_vbl_nmi(新版) | ✅ 9/10(even_odd_timing 差 1-dot 判定窗) |
| vbl_nmi_timing(2005 版,7 项) | ✅ 7/7 |
| sprite_hit_tests(11 项,含 edge timing) | ✅ 11/11 |
| sprite_overflow_tests(含硬件 bug 模拟) | ✅ 5/5 |
| oam_read / oam_stress / ppu_open_bus(含衰减) | ✅ 全过 |
| blargg_ppu_tests_2005(5 项) | ✅ 5/5 |
| apu_test(8 项,含 jitter 与 IRQ 时序) | ✅ 8/8 |
| apu_reset | ⚠️ 1/6(软复位边角) |
| mmc3_test | ⚠️ 4/6(A12 双 dot 波形与 MMC6) |

全部断言固化在 `cargo test`(19 过 / 0 败 / 4 项已知未过标注 `#[ignore]`)。

## 支持的 Mapper(第一梯队)

0 NROM / 1 MMC1(SxROM 全变体含 SUROM 512K)/ 2 UxROM / 3 CNROM /
4 MMC3(真实 A12 上升沿滤波 IRQ)/ 7 AxROM / 11 Color Dreams / 66 GxROM /
71 Camerica / 180(Crazy Climber)。总线冲突按板型模拟。

覆盖《超级马里奥兄弟》《魂斗罗》(美/日版所需的 NROM/UNROM 均在)及绝大多数
欧美日商业库。第二梯队(MMC5/VRC/N163/FME-7 + 扩展音源)见 PLAN.md 路线图。

## 构建与运行

```sh
# Linux 桌面前端依赖(音频/手柄):
sudo apt install libasound2-dev libudev-dev

cargo build --release
target/release/nes 你的游戏.nes [--scale 4]

# 无声/无手柄的最小构建(CI、无头环境):
cargo build -p nes-frontend --no-default-features
```

ROM 请自备,仓库不含任何商业游戏(`test-roms/` 是社区自由分发的测试 ROM,
来源见其中 SOURCES.md)。电池存档自动写在 ROM 旁(`.sav`)。

### 键位

| 键 | 功能 |
|---|---|
| 方向键 / Z / X / 回车 / 右Shift | 十字键 / B / A / Start / Select |
| F2 / F4 / 1-8 | 存档 / 读档 / 选槽 |
| R / P / Tab / Esc | 复位 / 暂停 / 快进 / 退出 |

手柄(gilrs):东=A 南/西=B,DPad 与左摇杆均可。

## 测试与无头工具

```sh
cargo test                       # 全量回归(约半分钟)
cargo run -p nes-headless -- nestest test-roms/nestest/nestest.nes test-roms/nestest/nestest.log
cargo run -p nes-headless -- blargg <rom> [秒]   # blargg $6000 协议 / 屏幕文本判定
cargo run -p nes-headless -- run <rom> [帧数]     # 帧哈希(确定性回归)
cargo run -p nes-headless -- ppm <rom> <out.ppm> [帧数]  # 截图
```

## 架构一瞥

- **时序模型**:CPU 每周期恰一次总线访问;访问落在该周期第 2/3 个 PPU dot 之间
  (blargg 套件校准),读 $2002 清标志后"周期末采样不到 NMI 边沿"等硬件行为自然涌现。
- **PPU**:逐 dot 管线,loopy v/t/x/w 全模型,精灵评估状态机(含 overflow 硬件 bug),
  渲染取数走真实 PPU 总线(mapper 可见 A12,MMC3 IRQ 由此驱动)。
- **APU**:每周期出样 → 分数步长抽取到声卡采样率;前端以缓冲水位反馈微调重采样比
  (音频主时钟的动态速率控制),无爆音无漂移。
- **确定性**:核内无系统时间/随机数,同输入逐位同输出;即时存档 = serde 全状态,
  跨 ROM 读档校验哈希拒绝。

完整设计文档与里程碑见 [PLAN.md](PLAN.md)。

## 已知未完成(路线图节选)

- cpu_interrupts 3/4/5、MMC3 scanline_timing/MMC6、apu_reset 边角、
  ppu even_odd_timing 的 1-dot 窗口 —— M4 精度冲刺项。
- 第二梯队 mapper 与扩展音源(VRC6/FDS/N163/MMC5/5B/VRC7)、PAL/Dendy —— M4。
- 表驱动 mapper 铺量、UNIF/FDS、CRT 滤镜、wasm、libretro 核心 —— M5。
