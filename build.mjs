import { build } from 'esbuild';
import fs from 'node:fs';

const r = await build({
  entryPoints: ['src/game.js'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'es2020',
  write: false,
  logLevel: 'warning',
});
let js = r.outputFiles[0].text.replace(/<\/script>/gi, '<\\/script>');
let html = fs.readFileSync('template.html', 'utf8');
html = html.replace('<!--GAME_JS-->', () => '<script>\n' + js + '</script>');
fs.writeFileSync('index.html', html);

// Artifact 版本：去掉文档外壳（发布环境会自行包裹）
const art = html
  .replace(/^[\s\S]*?<meta name="viewport"[^>]*>\n/, '')
  .replace(/<\/body>\s*<\/html>\s*$/, '');
const artOut = process.env.ART_OUT;
if (artOut) fs.writeFileSync(artOut, art);
console.log('index.html:', (html.length / 1024).toFixed(0) + ' KB');
