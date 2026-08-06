# 君子之盾 · A Junzi's Shield

以儒家君子之德重铸骑士精神的中世纪游侠骑士游戏。3D 版（Three.js 实时渲染：日光投影、雾气、程序化地形与可动关节骑士）。

> 天下失序之时，一个人的操守还算数吗。

## 玩法

- **第三人称行游**：骑马穿过裂而未崩的王国。沙溪村、黑桦林、苇渡口——路上遇事，皆由你断。
- **竞技场决斗**：上/中/下三段架势相克。对手与你架势相同即被格挡；出剑途中换势即是虚招。
- **降伏抉择**：打掉对手气势，他会弃剑请降。杀与不杀、收不收赎金，永远是你的一念。
- **德行即机制**：仁、义、礼、智、信与"慎独"全程暗中记账，从不显示数值。终幕时，你的盾面便是你的一生。

## 运行

浏览器直接打开 `index.html` 即可——构建产物是零依赖单文件（Three.js 已内联）。

## 开发

源码在 `src/game.js`（游戏逻辑与 3D 场景）与 `template.html`（外壳与 UI 样式）：

```bash
npm install
node build.mjs   # 打包生成 index.html
```

角色为真实骨骼动画模型（glTF），构建时以 base64 内嵌（`src/assets/models.js`，由
`tools/models.mjs` 从 [KayKit Character Pack: Adventurers](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0)
裁剪生成——只保留用到的 16 个动画并量化压缩）。该资源包为 CC0 授权（无需署名，此处致谢作者 Kay Lousberg）。
`src/assets/models.js` 已入库，日常构建无需重新运行模型管线。

## 操作

| 场景 | 按键 |
|------|------|
| 行游 | 方向键 / WASD 骑行 |
| 决斗 | A/D 或 ←→ 移动 · W/S 或 ↑↓ 换势 · J/空格 出剑 · K 撞盾 · 开赛前按 K 行礼 |

触屏设备自动显示虚拟按键。

## 设计

概念设计书见 [`docs/game-concept.md`](docs/game-concept.md)。核心命题：**把德行做成持续运转的玩法系统，而不是对话选项**——德行有代价（君子固穷），也有回响（世界记得）。
