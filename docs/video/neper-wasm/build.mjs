// Renders scenes.html frame by frame and muxes the narration: node build.mjs [--test]
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/gaddl/AppData/Roaming/npm/node_modules/playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const FFMPEG = process.env.FFMPEG || 'C:/Users/gaddl/AppData/Roaming/ffmpeg/ffmpeg.exe';
const out = process.env.OUT || path.join(here, 'neper-wasm.mp4');
const frames = path.join(process.env.FRAMES || path.join(here, 'frames'));
const FPS = 30, LEAD = 0.6, TAIL = 1.1;

const cfg = JSON.parse(fs.readFileSync(path.join(here, 'narration.json'), 'utf8'));
const wavSeconds = (file) => {
  const b = fs.readFileSync(file);
  let p = 12, rate = 0, align = 0, bytes = 0;
  while (p + 8 <= b.length) {
    const id = b.toString('ascii', p, p + 4), n = b.readUInt32LE(p + 4);
    if (id === 'fmt ') { rate = b.readUInt32LE(p + 12); align = b.readUInt16LE(p + 20); }
    if (id === 'data') { bytes = Math.min(n, b.length - p - 8); break; }
    p += 8 + n;
  }
  return bytes / align / rate;
};
let at = 0;
const scenes = cfg.scenes.map((s) => {
  const wav = path.join(here, 'audio', s.id + '.wav');
  const len = wavSeconds(wav);
  const sc = { id: s.id, caption: s.caption, wav, start: at, dur: LEAD + len + TAIL, audioAt: at + LEAD, speed: s.cueSeconds ? (s.cueSeconds + LEAD + TAIL) / (len + LEAD + TAIL) : 1 };
  at += sc.dur; return sc;
});
const total = at;
console.log('scenes', scenes.map((s) => `${s.id}@${s.start.toFixed(1)}+${s.dur.toFixed(1)}`).join(' '), 'total', total.toFixed(1));

fs.rmSync(frames, { recursive: true, force: true }); fs.mkdirSync(frames, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto(pathToFileURL(path.join(here, 'scenes.html')).href);
await page.evaluate(() => document.fonts.ready);
const n = process.argv.includes('--test') ? 0 : Math.ceil(total * FPS);
const marks = process.argv.includes('--test') ? scenes.map((s) => s.start + s.dur / 2) : null;
const count = marks ? marks.length : n;
for (let i = 0; i < count; i++) {
  const t = marks ? marks[i] : i / FPS;
  await page.evaluate(([t, s]) => render(t, s), [t, scenes]);
  await page.screenshot({ path: path.join(frames, String(i).padStart(5, '0') + '.jpg'), type: 'jpeg', quality: 92 });
  if (!marks && i % 300 === 0) console.log('frame', i, '/', n);
}
await browser.close();
if (marks) { console.log('test frames in', frames); process.exit(0); }

const inputs = scenes.flatMap((s) => ['-i', s.wav]);
const delays = scenes.map((s, i) => `[${i + 1}:a]adelay=${Math.round(s.audioAt * 1000)}|${Math.round(s.audioAt * 1000)}[a${i}]`).join(';');
const mix = scenes.map((_, i) => `[a${i}]`).join('') + `amix=inputs=${scenes.length}:normalize=0[aout]`;
const r = spawnSync(FFMPEG, ['-y', '-framerate', String(FPS), '-i', path.join(frames, '%05d.jpg'), ...inputs,
  '-filter_complex', `${delays};${mix}`, '-map', '0:v', '-map', '[aout]', '-c:v', 'libx264', '-preset', 'medium', '-crf', '20',
  '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k', '-t', total.toFixed(2), '-movflags', '+faststart', out], { stdio: 'inherit' });
if (r.status !== 0) process.exit(r.status);
console.log('wrote', out);
