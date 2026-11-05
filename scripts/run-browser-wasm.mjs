// Runs the browser app's wasm32-wasi build under `lib/wasm/neper-host.js`, so the third target of the app can be
// checked without a display: the module loads, WASI runs, the app finds its fonts in the seeded file system, and it
// then exits cleanly because this host has no windows (the message on stdout). Without the fonts the app exits 4
// (`added == 0` in examples/browser/main.e) before it gets that far, which is the signal used here.
//
//   node scripts/run-browser-wasm.mjs [build/app-wasi.wasm]
//
// The app asks for Windows, Debian and bundled (`/jost-*.ttf`) faces; a wasm deployment supplies the bundled ones, so
// this seeds those with the real Jost files and stands the test font in for the rest. The point is the startup path,
// not the glyph shapes.
import fs from 'node:fs'
import { run } from '../lib/wasm/neper-host.js'

const modulePath = process.argv[2] || 'build/app-wasi.wasm'
const bundled = {
  '/jost-regular.ttf': fs.readFileSync('neperos/assets/fonts/jost-regular.ttf'),
  '/jost-bold.ttf': fs.readFileSync('neperos/assets/fonts/jost-bold.ttf'),
}
const fallback = fs.readFileSync('tests/browser/assets/ahem.ttf')
const systemFaces = [
  'C:/Windows/Fonts/segoeui.ttf', 'C:/Windows/Fonts/segoeuib.ttf', 'C:/Windows/Fonts/arial.ttf',
  'C:/Windows/Fonts/arialbd.ttf', 'C:/Windows/Fonts/ariali.ttf', 'C:/Windows/Fonts/times.ttf',
  'C:/Windows/Fonts/timesbd.ttf', 'C:/Windows/Fonts/timesi.ttf', 'C:/Windows/Fonts/cour.ttf',
  'C:/Windows/Fonts/verdana.ttf', 'C:/Windows/Fonts/calibri.ttf', 'C:/Windows/Fonts/segoeuisl.ttf',
]
const files = { ...bundled }
for (const f of systemFaces) files[f] = fallback

const result = await run(fs.readFileSync(modulePath), {
  args: ['browser', 'about:blank'],
  files,
  stdout: (t) => process.stdout.write(t),
  stderr: (t) => process.stderr.write(t),
})
if (result.exitCode !== 0) {
  console.error(`wasm32-wasi browser exited ${result.exitCode} (4 means it found no fonts)`)
  process.exit(1)
}
console.log(`wasm32-wasi browser ran: exit 0, ${Object.keys(result.files || {}).length} files left in its file system`)
