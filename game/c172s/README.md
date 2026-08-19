# 《C172S 五边飞行》(C172S Pattern Flight)

一个**从零用 6502 汇编写的原创 NES 游戏**(NROM,mapper 0,32KB PRG + 8KB CHR),
是 [C172S Simulator](https://github.com/bigcubedata/test/tree/claude/goal-setting-sjhs9v)
(Godot 版塞斯纳 172S 训练模拟器)的红白机原生 demake:
**理念照搬——POH 目标数字 + 起落航线逐段打分的"教官"玩法;
表现形式全部换成 1985 年的做法**——侧视卷轴、sprite-0 分屏仪表板、
表驱动物理、APU 合成音效、吸引模式自动驾驶演示。

仓库直接附带构建好的 `c172s.nes`,可在本模拟器(或任何 NES 模拟器/实机)运行:

```sh
cargo run --release -p nes-frontend -- game/c172s/c172s.nes --scale 4
```

## 玩法

从跑道起飞,沿左起落航线(五边)飞一整圈落回原跑道。每一段有 POH 目标:

| 航段 | 目标 |
|---|---|
| 起飞滑跑 | 全油门,55 KIAS 抬前轮 |
| 一边 UPWIND | Vy **74** KIAS 爬升 |
| 二边 XWIND | 继续爬到 **1000** ft 场高 |
| 三边 DOWNWIND | 平飞 1000 ft,**90** KT;中点收油放襟翼 10° |
| 四边 BASE | 襟翼 20°,**73** KT 下降 |
| 五边 FINAL | 襟翼 30°,**65** KT,PAPI 保持两白两红 |
| 拉平 FLARE | 收油带杆,靠掉速轻轻接地 |

到转弯点仪表板会闪"TURN LEFT NOW!",按 ← 完成转弯(转弯在世界观上被抽象为
提示-响应;错过教官会代打并扣分——"INSTRUCTOR : MY CONTROLS")。
每段按空速/高度采样打 A-E 档;接地按下沉率打分(**掉速飘落是唯一的软着陆方法**:
保持平飘等空速掉到 ~52 KT 时接地即是 A);
落完看 FLIGHT LOG 讲评与总评级(CHECKRIDE PASSED / READY FOR SOLO / …)。

标题画面等 13 秒不按键,自动驾驶(PatternPilot 传承)会自己飞整圈演示。

## 键位

| 键 | 功能 |
|---|---|
| A / B | 油门 +/-(按住连发) |
| ↑ / ↓ | 俯仰配平(5 档) |
| ← | 应答转弯提示 |
| SELECT | 襟翼 0/10/20/30° |
| START | 开始 / 暂停 |
| B(地面) | 刹车 |

失速(<49-40 KIAS 按襟翼)会响喇叭、掉机头;引擎音调随转速,接地有闷响。

## 构建

```sh
sudo apt install cc65
./build.sh        # gen_chr.py 生成 CHR → ca65 → ld65 → c172s.nes
```

- `tools/gen_chr.py` — 程序化生成全部图块:ASCII 对齐字库(瓦片号=ASCII,
  便于 `nes-headless text` 直读 HUD 做自动化测试)、地形、标题大字、
  「五边飞行」16×16 汉字、8 变体塞斯纳精灵(4 姿态 × 2 桨相位)。
- `src/c172s.s` — 全部游戏逻辑(~2000 行 ca65):SMB 式全 NMI 主循环、
  sprite-0 分屏、列流式卷轴(世界周长 9216px = 512 的倍数,保证 NT 相位连续)、
  表驱动飞行模型、航段状态机 + 采样评分、自动驾驶、APU 引擎/喇叭/啁啾/接地音。

回归:`cargo test -p nes-core c172s`(标题 + 演示开局冒烟)。
