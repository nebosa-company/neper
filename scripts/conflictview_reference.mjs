// Reference vectors for `e.algo.conflictview` (L037): build reviews with appdor's own buildConflictReview from random
// offline conflicts (values of every JSON shape, markup characters, a no-break space, long text and 4-byte characters at
// the 120-unit cut) and render them with appdor's own renderConflictReview, then write the link fixture
// tests/selfhost/fixtures/link/algo_conflictview. The translator answers `key|variable`; `escapeHtml` is the DOM's text
// serialisation written out (`&`, `<`, `>` and U+00A0 as named references, then the quotes), because node has no DOM.
// APPDOR_DIR defaults to D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, clone, emit, rng } from './ref_common.mjs';

const cr = await import(pathToFileURL(resolve(appdor, 'src/offline/conflict-review.js')).href);
const { int, pick, chance } = rng(0x9e21);

const escapeHtml = (text) => (text == null ? '' : String(text))
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\u00a0/g, '&nbsp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const t = (key, lang, params) => `${key}|${params ? Object.values(params).join(',') : ''}`;

const FIELDS = ['a', 'b', 'c', 'title<x>', 'q"r', "o'k", 'd&e'];
const LONG = 'abcdefghij'.repeat(13);
const VALS = ['x', 'y', 1, 2.5, null, true, false, '', '<b>&"\'</b>', 'a\u00a0b', LONG, 'é ü', { k: [1, 2], z: 'w' }, [1, 'two', null], {}, [], 'x'.repeat(120), 'x'.repeat(121),
  '\u{1F600}'.repeat(60), '\u{1F600}'.repeat(61), 'é'.repeat(121), '日本語'.repeat(41), 'line\nbreak', 'tab\there'];
const genValues = () => { const p = {}; for (const f of FIELDS) if (chance(0.35)) p[f] = pick(VALS); return p; };
const RIDS = ['r1', 'r<2>', 'r"3"', "r'4", 'r 5'];
const genRaw = () => {
  if (chance(0.05)) return pick([null, {}, { server: { id: 'z' } }]);
  const mutation = {
    ...(chance(0.6) ? { id: pick(['m1', 'm<2>', 3, 0, 'q"4']) } : {}),
    ...(chance(0.9) ? { table: pick(['t1', 't2']) } : {}),
    ...(chance(0.9) ? { recordId: pick(RIDS) } : {}),
    ...(chance(0.9) ? { payload: genValues() } : {}),
    ...(chance(0.6) ? { baseData: genValues() } : {}),
  };
  const server = chance(0.15) ? null : { id: 'r', ...genValues() };
  return { mutation, ...(server ? { server } : {}) };
};

const cases = [];
let withFields = 0;
for (let i = 0; i < 300; i++) {
  const conflicts = Array.from({ length: chance(0.08) ? 0 : 1 + int(3) }, genRaw);
  const review = cr.buildConflictReview(clone(conflicts));
  if (review.items.some((x) => x.fields.length)) withFields += 1;
  cases.push({ op: { op: 'render', review }, e: cr.renderConflictReview({ escapeHtml, t, review: clone(review) }) });
}
const chunks = emit('algo_conflictview', 'conflictview_fixture_template.e', cases, 'algo conflictview ok');
console.log(`${cases.length} cases (${withFields} with field rows) in ${chunks} chunks -> algo_conflictview`);
