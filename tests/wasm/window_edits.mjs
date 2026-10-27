// What lib/wasm/window.js makes of a keyboard's edit to the text field (D5890): Android's keyboard corrects a word with
// ONE delete event for the whole word and then the replacement, so only the field's value before and after counts the
// characters (the phone_probe.html report: "outdige" -> delete -> "side " left "outside ").
//   node --no-warnings tests/wasm/window_edits.mjs
import assert from 'node:assert/strict'
import { edits } from '../../lib/wasm/window.js'

assert.deepEqual(edits('outdige', 'out'), { deleted: 4, inserted: [] })
assert.deepEqual(edits('outdige', 'outside '), { deleted: 4, inserted: ['s', 'i', 'd', 'e', ' '] })
assert.deepEqual(edits('hel', 'hell'), { deleted: 0, inserted: ['l'] })
assert.deepEqual(edits('hel Бу', 'hel Бургас '), { deleted: 0, inserted: ['р', 'г', 'а', 'с', ' '] })
assert.deepEqual(edits('a😀', 'a'), { deleted: 1, inserted: [] })
assert.deepEqual(edits('abc', 'abc'), { deleted: 0, inserted: [] })
console.log('window edits ok')
