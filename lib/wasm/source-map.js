// Source lines for an engine error's WebAssembly frames (C196, D5683): `addLines(stack, mapText)` appends
// `[path:line]` to each `wasm-function[N]:0xOFFSET)` frame, the offset looked up in the map the compiler's
// `--source-map` wrote (Source Map v3, one generated line whose columns are byte offsets in the module).
const DIGITS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function decode(mappings) {
  const entries = []
  const state = [0, 0, 0, 0]
  for (const segment of mappings.split(',')) {
    let at = 0
    for (let field = 0; field < 4 && segment; field++) {
      let value = 0
      let shift = 0
      let digit
      do {
        digit = DIGITS.indexOf(segment[at++])
        value += (digit & 31) * 2 ** shift
        shift += 5
      } while (digit & 32)
      state[field] += value % 2 ? -(value - 1) / 2 : value / 2
    }
    if (segment) entries.push([state[0], state[1], state[2]])
  }
  return entries
}

export function addLines(stack, mapText) {
  const map = JSON.parse(mapText)
  const entries = decode(map.mappings)
  return stack.replace(/wasm-function\[\d+\]:0x([0-9a-f]+)\)/g, (frame, hex) => {
    const offset = parseInt(hex, 16)
    let low = 0
    let high = entries.length
    while (low < high) {
      const middle = (low + high) >> 1
      if (entries[middle][0] <= offset) low = middle + 1
      else high = middle
    }
    if (low === 0) return frame
    const [, source, line] = entries[low - 1]
    return `${frame} [${map.sources[source]}:${line + 1}]`
  })
}
