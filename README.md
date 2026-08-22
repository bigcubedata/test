# rnes — 周期级 NES/Famicom 模拟器(Rust)

模拟 Ricoh 2A03(6502 内核 + APU)与 2C02 PPU——即 UA6527/UA6528 兼容机芯片的原型。
纯 Rust,核心 `nes-core` 无任何 I/O,同一份核驱动四个外壳:**桌面**(winit+wgpu+cpal)、
**浏览器**(wasm,零 JS 依赖)、**libretro 核心**(RetroArch)、**无头测试器**(CI)。

## 状态(精度测试矩阵)

| 套件 | 结果 |
|---|---|
| nestest 金标日志(8991 行,含全部非官方指令) | ✅ 全对齐 |
| blargg instr_test-v5(16 项)/ instr_timing / instr_misc / cpu_timing_test6 | ✅ 全过 |
| cpu_dummy_reads / cpu_dummy_writes / branch_timing(3) | ✅ 全过 |
| cpu_interrupts_v2 | ⚠️ 2/5(NMI 劫持向量/DMA 交叠微时序) |
| ppu_vbl_nmi(新版 10 项) | ✅ 9/10 |
| vbl_nmi_timing(2005 版 7 项) | ✅ 7/7 |
| sprite_hit(11)/ sprite_overflow(5)/ oam_read / oam_stress | ✅ 全过 |
| ppu_open_bus(含按位衰减)/ blargg_ppu_tests(5) | ✅ 全过 |
| apu_test(8 项,含 jitter 与 IRQ 时序) | ✅ 8/8 |
| pal_apu_tests(PAL 帧计数器/表) | ✅ 6/10(halt/reload 写时序细项待攻) |
| apu_reset | ✅ 4/6(4017_timing 含 ~10 周期复位延迟) |
| mmc3_test | ⚠️ 4/6(scanline_timing 差 1 dot、MMC6 需 ROM DB) |
| mmc5(CHR bank/ExRAM 可执行,视觉测试) | ✅ 画面正确 |
| m22chrbankingtest(VRC2 CHR) | ✅ 分行正确 |

全部断言固化在 `cargo test`(20 过 / 0 败 / 4 项已知未过标注 `#[ignore]`)。

## Mapper 覆盖(68 个编号)

**大型芯片**:1 MMC1(SxROM/SUROM)· 4 MMC3(+118 TxSROM/119 TQROM/74 国产 CHR-RAM 混合/189)
· 5 **MMC5**(PRG 四模式、CHR A/B 组、ExRAM 四模式含 ExAttr、扫描线 IRQ、乘法器)
· 9/10 MMC2/MMC4 · 21/22/23/25 VRC2/VRC4 · 24/26 **VRC6** · 85 **VRC7** · 19 **N163**
· 69 **FME-7/5B** · 67/68 Sunsoft-3/4 · 32/65 Irem · 33/48/80 Taito · 18 Jaleco SS88006
· 73/75 VRC3/VRC1 · 112 Asder · **163 南晶**(国产原创游戏)

**discrete/简单板**:0/2/3/7/11/34/38/66/70/71/72/76/78/79/86/87/88/89/92/93/94/95/97/
107/113/133/140/145/146/148/149/152/154/180/184/185(CNROM 保护)/206/210,总线冲突按板型。

**扩展音源**(混入 APU 输出):VRC6(双方波+锯齿)· VRC7(OPLL 子集 FM:6ch 2-op、
ADSR、内置音色)· N163(波表 1-8 通道)· MMC5(双方波+PCM)· Sunsoft 5B(AY 子集含包络)。

**区制**:NTSC / PAL(312 行、16:5 分频、PAL APU 表)/ Dendy(291 行 vblank)。

## 构建与运行

```sh
# Linux 桌面依赖(音频/手柄):
sudo apt install libasound2-dev libudev-dev

cargo build --release
target/release/nes 游戏.nes [--scale 4] [--region ntsc|pal|dendy]

# 浏览器版(wasm):
rustup target add wasm32-unknown-unknown
./web/build.sh && python3 -m http.server -d web 8080

# RetroArch 核心:
cargo build --release -p nes-libretro
retroarch -L target/release/librnes_libretro.so 游戏.nes

# 无头/CI 最小构建:
cargo build -p nes-frontend --no-default-features
```

ROM 请自备,仓库不含任何商业游戏(`test-roms/` 为社区自由分发的测试 ROM,见 SOURCES.md)。

### 键位(桌面/网页)

| 键 | 功能 |
|---|---|
| 方向键 / Z / X / 回车 / 右Shift | 十字键 / B / A / Start / Select |
| F2 / F4 / 1-8(桌面) | 存档 / 读档 / 选槽 |
| R / P / Tab / Esc(桌面) | 复位 / 暂停 / 快进 / 退出 |

### 手柄(USB 通用 + PS5 DualSense 蓝牙)

即插即用,热插拔,第 1/2 只手柄 → P1/P2(键盘始终并入 P1)。
映射:右侧面键(○/East)= A,下/左面键(✕/□)= B,Create/Share = Select,
Options = Start,十字键与左摇杆等效。

| 平台 | 通用 USB 手柄 | PS5 DualSense(USB/蓝牙) |
|---|---|---|
| Linux 桌面 | gilrs(evdev + SDL 映射库) | 内核 hid-playstation 驱动 + gilrs(USB/蓝牙同路径) |
| Windows 桌面 | gilrs(XInput,Xbox 类) | 内置 HID 驱动直连(hidapi,USB/蓝牙三种报文) |
| macOS 桌面 | gilrs(IOKit) | 内置 HID 驱动直连 |
| 浏览器 | Gamepad API 标准映射 | Gamepad API(Chrome/Edge/Firefox 蓝牙直连) |

- 自定义映射:桌面端支持 `SDL_GAMECONTROLLERCONFIG` 环境变量(SDL 映射串)。
- Linux 老内核(<5.12 无 hid-playstation)可 `NES_DUALSENSE_HID=1` 启用内置驱动;
  若 hidraw 权限不足,添加 udev 规则:
  `SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", MODE="0660", TAG+="uaccess"`。
- 蓝牙配对:长按 DualSense 的 PS + Create 键至灯条闪烁,系统蓝牙里配对即可。

## 附带游戏:《比武大会》骑士长枪比武

`game/tourney/` 是第二个**从零 6502 汇编原创 NES 游戏**(NROM,`tourney.nes`
已入库):中世纪马上长枪比武,《Punch-Out!!》式读招对决——B 持盾 A 固枪,
上/中/下三线,贴身固枪才有完美一击,出枪太早会被高手看破换盾。
**骑士精神写进规则**:致意、饶过断盾者、扶起坠马对手挣荣誉;低刺失德、
击马犯规当场判负;荣誉决定平局裁决、决赛再战权与三种结局。战役七将各有
性情(早枪/高盾/假盾/看破早枪/低刺者),另有 2P 同屏对战与 AI 演示循环。
细节见 [game/tourney/README.md](game/tourney/README.md)。

```sh
cargo run --release -p nes-frontend -- game/tourney/tourney.nes --scale 4
```

## 附带游戏:《C172S 五边飞行》

`game/c172s/` 是一个**从零用 6502 汇编写的原创 NES 游戏**(NROM,构建好的
`c172s.nes` 已入库)——Godot 版 C172S Simulator 的红白机原生移植:
**座舱内第一人称视角**(全景地平线随真实航向卷动、透视跑道随侧偏歪斜、
PAPI、sprite-0 分屏六联仪表盘:空速表彩弧/姿态仪天地面/精灵指针)+
**真实空气动力学**(升力/诱导阻力/功率曲线/失速迎角/地效由真实公式生成
查找表,整数管线过 POH 校验:失速 48-41、Vy 74、极速 123、坡度失速 +7%、
地效飘飞;另有定常风+阵风、侧风偏流与侧载评分、P-factor 左偏与地面转向、
定距桨真实转速、电动襟翼渐变、接地弹跳/海豚跳、失速掉翼),塔台电台 +
随机复飞令,失速抖振/接地冲击全机身震动,地面调色板行进 + 低空扑面,
完好落地可续飞**黄昏/夜航圈**(红光仪表照明),讲评页画出真实航迹图。
POH 目标 + 起落航线逐段 A-E 教官评分,标题自动驾驶整圈演示循环播放,
细节见 [game/c172s/README.md](game/c172s/README.md)。

```sh
cargo run --release -p nes-frontend -- game/c172s/c172s.nes --scale 4
```

## 测试与无头工具

```sh
cargo test                # 全量回归(约 1 分钟)
cargo run -p nes-headless -- nestest <rom> <log>   # 金标比对
cargo run -p nes-headless -- blargg <rom> [秒]      # $6000 协议/屏幕文本判定
cargo run -p nes-headless -- run <rom> [帧]         # 帧哈希
cargo run -p nes-headless -- ppm <rom> <out> [帧]   # 截图
NES_REGION=pal cargo run -p nes-headless -- ...     # 区制覆盖
```

## 架构一瞥

- **时序**:CPU 每周期恰一次总线访问,落在第 2/3 个 PPU dot 之间(blargg 校准);
  NMI 抑制等行为从"读清标志→周期末采样"自然涌现。PAL 用 16:5 分频。
- **PPU**:逐 dot 管线、loopy 全模型、精灵评估状态机(含 overflow bug);
  地址总线按 dot 保持并汇报给 mapper(MMC3 的 A12 波形滤波直接观测)。
- **Mapper 层**:CPU/PPU/nametable 三条翻译通道 + 每周期/每 dot 钩子 + 音频钩子;
  nametable 可指向 CIRAM/ExRAM/CHR/填充值(MMC5、N163、Sunsoft-4 之必需)。
- **确定性**:无系统时间/随机数,同输入逐位同输出;存档 = serde 全状态,
  存档回放确定性有 cargo test 断言把守。

设计文档与里程碑:[PLAN.md](PLAN.md)。

## 已知未完成

- cpu_interrupts 3/4/5、mmc3 scanline_timing(±1 dot)与 MMC6 自动识别(需 ROM DB)、
  apu_reset 2 项、pal_apu 4 项、ppu even_odd_timing —— dot 级长尾。
- FDS(需 BIOS+磁碟子系统)与 UNIF 容器、MMC5 垂直分屏、CRT/NTSC 滤镜、
  逐 dot 循环批处理优化 —— 后续迭代。
- VRC7 FM 为结构等价的简化实现(非逐位精确)。
