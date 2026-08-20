# Rust 红白机(NES/FC)模拟器 — 技术方案

> 目标:用 Rust 实现一个周期级精度的 NES/Famicom 模拟器,完整模拟 UA6527/UA6528(即 Ricoh 2A03 CPU+APU 与 2C02 PPU 的 UMC 克隆),含卷轴 PPU 全管线、APU 与扩展音源、可插拔 mapper 体系;《超级马里奥兄弟》《魂斗罗》等经典游戏完美可玩。

## 0. 目标与术语校准

- **UA6527 / UA6528** 是联华电子(UMC)为兼容机生产的克隆芯片,分别对应 Ricoh **RP2A03**(CPU:去掉 BCD 的 6502 内核 + APU + DMA)和 **RP2C02**(PPU);PAL 版对应 UA6527P/UA6538。模拟基准取原版 Ricoh NTSC 行为,PAL(2A07)与 Dendy 时序作为可配置变体。
- **验收目标**:通过 nestest 与 blargg 全套测试 ROM(周期级精度);《超级马里奥兄弟》(mapper 0)与《魂斗罗》(美版 mapper 2 UNROM、日版 Konami VRC 系)画面、分屏、声音全部正确;支持即时存档与电池存档。
- **关于"全部 345 个 mapper"**(详见 §5):架构上一次到位——任意编号可插拔、NES 2.0 submapper 全解析;实现上分梯队推进,第一批覆盖商业游戏库 ~90%+,长尾按出现频率与文档完整度滚动补齐。编号空间里大量是盗版/多合一卡专用且文档残缺,一次性交付全部编号不现实(成熟参考模拟器也是多年滚动补齐的结果),这里不夸口,给的是能演进到全覆盖的架构和明确的推进路径。

## 1. 总体架构

- Cargo workspace,三个 crate:
  - **`nes-core`** — 纯模拟逻辑,零 I/O 依赖(不碰窗口/声卡/文件),可单测、可 wasm。
  - **`nes`** — 桌面前端:`winit` 窗口 + `pixels`(wgpu) 帧缓冲 + `cpal` 音频 + `gilrs` 手柄。
  - **`nes-headless`** — 无头运行器:跑测试 ROM、比对 golden log / 帧哈希,接入 CI。
- **时序模型**:主时钟 21.477272 MHz(NTSC),CPU = ÷12,PPU = ÷4,即每个 CPU 周期步进 PPU 3 dots、APU 1 步。采用**逐周期互锁(cycle-stepped)**而非"整条指令执行完再让 PPU 追赶":中扫描线写 $2005/$2006、sprite 0 hit、MMC3 A12 IRQ 等效果都要求 CPU/PPU 在周期粒度上正确交错,追赶式架构在这些点上会积累特例,不如从一开始就逐周期。
- **所有权设计**:不搞 `Rc<RefCell>` 引用网。顶层 `Nes` 结构体扁平持有 cpu/ppu/apu/cartridge/controllers,总线读写通过 `&mut Nes` 集中分派,mapper 为 `Box<dyn Mapper>`。全机状态可 serde 序列化 → 即时存档、确定性回放、CI 断言。

## 2. CPU(2A03 的 6502 内核)

- **全部 256 个操作码**:151 条官方指令 + 全部非官方指令(LAX/SAX/DCP/ISB/SLO/RLA/SRE/RRA/ANC/ALR/ARR/AXS/SHX/SHY/LAS 等)+ 12 个 JAM。不少游戏和测试依赖非官方指令。
- **微操作级周期精确**:每条指令按真实总线访问序列逐周期执行——RMW 指令的 dummy write、跨页 dummy read、`(zp,X)` 的多次取址等。这些"冗余访问"会触发 mapper/PPU 副作用(如 $2007 双读),不能省略。
- **中断**:NMI 边沿检测与 IRQ 电平采样的精确时点、分支指令的中断轮询特例、中断劫持(NMI 劫持 BRK/IRQ)、CLI/SEI/PLP 延迟一条指令生效。
- **2A03 特性**:D 标志可置位但 ADC/SBC 无十进制模式。
- **DMA**:OAM DMA 513/514 周期(奇偶对齐),DMC DMA 抢总线 stall,以及两种 DMA 冲突时的时序。
- **验收**:nestest.log 全量逐行对齐(PC/寄存器/周期数);blargg `instr_test-v5`、`instr_timing`、`instr_misc`、`cpu_interrupts_v2`。

## 3. PPU(2C02)— 卷轴与渲染

- **逐 dot 渲染**:341 dots × 262 扫描线(NTSC);渲染开启时奇数帧跳过 pre-render 行的一个 dot;VBlank 标志于 (241,1) 置位;NMI 与 $2002 读的竞态(同点读导致抑制)按硬件行为处理。
- **背景管线**:标准 8-dot NT/AT/PT 取数节奏、16-bit 移位寄存器 + fine-x 选择;完整 **loopy v/t/x/w 寄存器模型**($2000/2002/2005/2006/2007 的写切换,dot 256 Y 递增、dot 257 水平拷贝、pre-render 280–304 垂直拷贝)。这是"卷轴 PPU"的全部机制,天然支持任意中屏分割滚动(SMB 状态栏、忍者龙剑传、塞尔达等)。
- **精灵**:dots 65–256 的次级 OAM 评估状态机、每行 8 个上限、sprite overflow 硬件 bug(诊断地址错误递增)照实模拟、**sprite 0 hit 精确到 dot**(SMB 分屏依赖它)、8×16 模式、优先级与翻转、OAMADDR 怪癖。
- **寄存器行为**:$2007 读缓冲、调色板镜像($3F10/$3F14/…)、灰度位、三路强调位、PPU open bus。NTSC 调色板内置,支持外部 .pal 替换。
- **验收**:blargg `ppu_vbl_nmi`、`sprite_hit_tests`、`sprite_overflow_tests`、`oam_read`/`oam_stress`、`ppu_open_bus`、scanline 时序测试。

## 4. APU 与扩展音源

- **基础 5 通道**:Pulse×2(两个 sweep 单元取负时一补/二补的差异)、Triangle(线性计数器)、Noise(15-bit LFSR,长短两模式)、DMC(增量采样、DMA、IRQ、$4011 直写)。
- **帧计数器**:4-step/5-step 模式、帧 IRQ、$4017 写入后 3–4 周期延迟复位。
- **混音与输出**:nesdev 非线性 DAC 查表公式,一阶高通×2 + 低通滤波;每 CPU 周期产样,band-limited 增量合成(blip 风格,纯 Rust 实现)重采样到 48 kHz。**音频驱动同步**:按声卡实际消耗速率微调重采样比,不爆音、不漂移。
- **扩展音源**通过 mapper 音频钩子混入,按优先级:
  1. **VRC6**(2 方波 + 锯齿;悪魔城伝説)
  2. **FDS** 波表(磁碟机音源)
  3. **Namco 163**(波表 1–8 通道)
  4. **MMC5**(2 方波 + PCM)
  5. **Sunsoft 5B**(AY-3-8910 子集;Gimmick!)
  6. **VRC7**(YM2413 亚种 FM;Lagrange Point)— FM 合成工作量最大,单列二期。
- **验收**:blargg `apu_test`、`apu_mixer`、DMC 系列;与成熟模拟器录音对拍抽查。

## 5. 卡带与 Mapper 体系

- **加载**:iNES(含脏头启发式修复)与 **NES 2.0**(submapper、PRG-RAM/NVRAM 精确大小、地区、四屏标志);电池存档 `.sav` 自动读写;UNIF 与 FDS 磁碟镜像列二期。
- **`trait Mapper` 能力面**:
  - CPU $4020–$FFFF 全空间读写(PRG bank、寄存器、PRG-RAM);
  - PPU 地址空间读写与镜像控制(H/V/单屏/四屏/MMC5 ExRAM nametable);
  - 每周期 tick;**真实 A12 上升沿信号(带低电平滤波)**驱动 MMC3 类扫描线 IRQ(不用"每行回调一次"的近似);CPU 周期计数 IRQ(VRC/FME-7);
  - MMC5 所需的取指/渲染阶段监听;
  - 扩展音频输出;状态序列化。
  - **总线冲突**(UNROM/CNROM 写入与 ROM 值相与)按板型/submapper 模拟——美版魂斗罗正确性相关。
- **编号覆盖策略**(对"345 个"的坦诚回答——NES 2.0 编号空间 0–4095,已分配三百余个):
  - **第一梯队(M2–M3,覆盖商业库 ~90%+)**:0 NROM、1 MMC1(SxROM 全变体)、2 UxROM、3 CNROM、4 MMC3/MMC6、7 AxROM、9/10 MMC2/MMC4、11 ColorDreams、66 GxROM、71 Camerica、206 Namco 118。SMB 和美版魂斗罗落在此层。
  - **第二梯队(M4)**:5 MMC5、19 N163、21/22/23/25 VRC2/VRC4(日版魂斗罗在此)、24/26 VRC6、69 FME-7/Sunsoft 5B、85 VRC7、34/38/68/70/75/76/79/87/88/95/118/119/140/152/154/180/185/189/210 等常见号。
  - **第三梯队(M5,滚动推进)**:做一个**表驱动 discrete mapper 框架**(一个 bank 映射描述结构 = 一个编号),把大量简单逻辑类 mapper 快速铺量;再按 NesCartDB 出现频率与 nesdev 文档补多合一/盗版长尾。目标先到 200+ 编号,之后按需求推进;每个编号至少带一个样本 ROM 回归。

## 6. 前端与体验(已定稿)

**选型决议**(评估过 pixels 栈 / softbuffer / SDL2 / SDL3 / eframe / macroquad / libretro,详见会话评估记录):

- **主选**:`winit` + `pixels`(wgpu,整数缩放 + 后续 shader 滤镜)+ `cpal` 音频 + `gilrs` 手柄,egui 调试 overlay 走 feature 门控(发行构建整体剔除)。唯一同时满足 shader 滤镜、wasm 路线、原生调试 UI、纯 crates 依赖四项的组合。
- **feature 矩阵**:`audio`(cpal,默认开;Linux 构建需 libasound2-dev)、`gamepad`(gilrs,默认开;需 libudev-dev)、`debugger`(egui overlay,默认关)。无头/CI 环境用 `--no-default-features` 裸构建。
- **降级路径**:softbuffer 渲染 feature(无 GPU 机器/最小构建)。
- **Plan B**:整体换 SDL2/SDL3(前端为独立 crate,替换成本被架构锁定)。
- **M5 附加**:libretro core 目标(手写 FFI),接入 RetroArch 生态。

其余体验项:键盘默认 方向键 + Z/X = B/A + 回车/右Shift = Start/Select。
- **功能**:即时存档 8 槽(F1–F8 类快捷键)、电池存档自动落盘、暂停/逐帧/快进、复位、截图、NTSC/PAL/Dendy 切换;CRT/NTSC 滤镜列二期。
- **`nes-headless`**:加载 ROM 跑 N 帧,输出帧哈希或读取测试 ROM 的 $6000 状态约定,供 CI 断言。

## 7. 测试与验收

- **自动化**:nestest golden log 全对齐;blargg CPU/PPU/APU 全套与社区时序测试 ROM(均可自由分发,随仓库入 CI)。
- **商业游戏 ROM 不入库**(版权原因,需使用者自备)。SMB/魂斗罗的关键路径——sprite 0 分屏、奇帧时序、UNROM 总线冲突、8×16 精灵、DMC 节奏——全部有对应自由测试 ROM 覆盖,保证"拿到 ROM 即可玩"。

## 8. 里程碑(每个里程碑提交并推送到指定分支)

| 里程碑 | 内容 | 验收 | 状态 |
|---|---|---|---|
| **M1** | workspace 骨架、iNES/NES 2.0 解析、CPU 全指令周期精确 | nestest 全对齐(headless) | ✅ 完成(8991 行全对齐) |
| **M2** | PPU 全管线(背景/精灵/滚动)、mapper 0、窗口与输入 | SMB 可玩,分屏/计时正确 | ✅ 完成(sprite_hit 11/11 等,见 README 矩阵) |
| **M3** | APU 5 通道与音频同步、第一梯队 mapper、双档存档 | 魂斗罗可玩带声音,blargg CPU/PPU 套件绿 | ✅ 完成(apu_test 8/8;mapper 0/1/2/3/4/7/11/66/71/180;9/10 待补) |
| **M4** | MMC5/VRC/N163/FME-7、扩展音源、MMC3 A12 波形、PAL/Dendy、apu_reset | blargg APU + IRQ 时序测试绿 | ✅ 完成(A12 双 dot 波形落地;mmc3-4/6、cpu_interrupts 3-5、apu_reset 2 项遗留,见 README) |
| **M5** | mapper 铺量、VRC7 FM、wasm、libretro | 按编号回归清单 | ✅ 主体完成(68 编号 + 合成 ROM 矩阵测试;wasm/libretro 双目标;FDS/UNIF/滤镜/批处理优化遗留) |
| **番外** | 《C172S 五边飞行》原创 NES 游戏(6502 汇编,`game/c172s/`) | 标题/演示冒烟测试 + 自动驾驶整圈落地 | ✅ v3 完成(座舱第一人称视角:全景地平线/透视跑道歪斜/PAPI/六联仪表含空速彩弧+姿态仪面;真实气动:gen_aero.py 真公式→整数表,POH 校验失速 48-41/Vy 74/极速 123/坡度失速+7%/地效;定常风+阵风/侧风偏流侧载评分/P-factor 与地面转向/定距桨转速/电动襟翼/接地弹跳海豚跳/失速掉翼;塔台电台+随机复飞,失速抖振与接地冲击全机身震动,地面调色板行进+低空扑面,黄昏/夜航续圈,讲评页真实航迹图;姿态飞行法自动驾驶抗风整圈演示) |

## 9. 主要风险

- **全 mapper 覆盖是长期工程**:按梯队推进,不影响"经典游戏完美可玩"这条主线(M3 即达成)。
- **VRC7 FM 与 FDS 细节工作量大**:已单列,不阻塞其他部分。
- **性能**:dot 级 PPU + 周期级 CPU 在 release 构建下单核余量很大,60 fps 无压力;nes-core 无锁无堆分配热路径。
