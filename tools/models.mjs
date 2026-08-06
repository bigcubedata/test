/* 模型裁剪管线：删除不用的动画，重采样、去重、量化，输出精简 GLB 并生成 base64 模块 */
import { NodeIO } from '@gltf-transform/core';
import { prune, dedup, resample, quantize } from '@gltf-transform/functions';
import { KHRMeshQuantization } from '@gltf-transform/extensions';
import fs from 'node:fs';
import path from 'node:path';

const SRC = '/workspace/kaykit-game-assets/kaykit-character-pack-adventures-1.0/addons/kaykit_character_pack_adventures/Characters/gltf';
const KEEP = [
  'Idle', 'Walking_A', 'Walking_Backwards',
  '1H_Melee_Attack_Chop', '1H_Melee_Attack_Slice_Horizontal', '1H_Melee_Attack_Stab',
  'Blocking', 'Block_Hit', 'Block_Attack',
  'Hit_A', 'Hit_B',
  'Sit_Floor_Down', 'Sit_Floor_Idle',
  'Cheer', 'Interact', 'Sit_Chair_Idle',
];
const MODELS = [
  ['knight', 'Knight.glb'],
  ['rogue', 'Rogue_Hooded.glb'],
  ['barbarian', 'Barbarian.glb'],
];

const io = new NodeIO().registerExtensions([KHRMeshQuantization]);
const out = {};
for (const [key, file] of MODELS) {
  const doc = await io.read(path.join(SRC, file));
  for (const anim of doc.getRoot().listAnimations()) {
    if (!KEEP.includes(anim.getName())) anim.dispose();
  }
  await doc.transform(resample(), dedup(), prune());
  await doc.transform(quantize());
  const bin = await io.writeBinary(doc);
  out[key] = Buffer.from(bin).toString('base64');
  console.log(key, (bin.byteLength / 1024).toFixed(0) + ' KB ->', (out[key].length / 1024).toFixed(0) + ' KB b64');
}
fs.mkdirSync('src/assets', { recursive: true });
fs.writeFileSync('src/assets/models.js',
  '/* KayKit Character Pack: Adventurers (CC0) — 裁剪后内嵌 */\n' +
  'export const MODELS_B64 = ' + JSON.stringify(out) + ';\n');
console.log('total b64:', (Object.values(out).reduce((a, b) => a + b.length, 0) / 1048576).toFixed(2) + ' MB');
