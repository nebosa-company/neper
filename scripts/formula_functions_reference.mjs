// Reference and fixture generator for the formula function library (L027).
//
//   node scripts/formula_functions_reference.mjs <group> [<group> ...]      (APPDOR_DIR as for formula_reference.mjs)
//
// For each function of the named groups in appdor's own default registry it generates calls over a vocabulary of
// argument expressions (numbers, text, dates, arrays, blanks, errors, field references), at each arity the function
// accepts, evaluates them with appdor's engine and writes the outcomes, rendered canonically, into the group's
// fixture under tests/selfhost/fixtures/link/. The fixture evaluates the same source with the Neper library and
// compares. Groups and their Neper modules are the table below.
// The reference evaluates legacy date strings in the host's zone; the port is UTC throughout.
process.env.TZ = 'UTC';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, 'src/formula', p)).href);
const index = await load('index.js');
const { isError } = await load('errors.js');

const GROUPS = {
  basic: { categories: ['logical', 'information', 'lookup', 'finance'], modules: ['basic'], fixture: 'algo_formula_basic', ok: 'algo formula basic ok' },
  convert: { categories: ['convertion'], modules: ['basic', 'datetime', 'convert'], fixture: 'algo_formula_convert', ok: 'algo formula convert ok' },
  math: { categories: ['math'], modules: ['basic', 'math'], fixture: 'algo_formula_math', ok: 'algo formula math ok' },
  text: { categories: ['text'], modules: ['basic', 'text'], fixture: 'algo_formula_text', ok: 'algo formula text ok' },
  datetime: { categories: ['datetime'], modules: ['basic', 'datetime'], fixture: 'algo_formula_datetime', ok: 'algo formula datetime ok' },
  misc: { categories: ['random-hash-encode', 'array', 'reference', 'extraction'], modules: ['basic', 'misc'], fixture: 'algo_formula_misc', ok: 'algo formula misc ok' },
};

const FIELDS = {
  Price: 10, Qty: 3, Name: 'Ada Lovelace', Empty: '', Nothing: null, Flag: true, NumText: '42', Neg: -7, Float: 1.5, Zero: 0,
  DateText: '2026-01-15', Stamp: '2026-01-15T23:30:00', List: [1, 2, 3], Words: ['pear', 'apple', 'fig'], Mixed: [1, 'a', null, true],
  Padded: '  padded  ', Csv: 'a,b,c', Email: 'ada@example.com', Url: 'https://example.com/a b?q=1&r=2', Json: '{"a":{"b":[1,2,3]},"c":"x"}',
};
const DATES = { When: '2026-03-01T12:30:45.250Z', Earlier: '2024-02-29T00:00:00.000Z' };
const NOW = '2026-06-15T09:30:00.000Z';

const VOCAB = [
  '0', '1', '-1', '2', '3', '7', '10', '0.5', '-2.5', '100', '1e6', '255', '1000.456',
  '""', '"abc"', '"Hello World"', '"  pad  "', '"5"', '"-3.7"', '"abc,def,ghi"', '"2026-01-15"', '"2026-01-15T10:30:45Z"', '"a-b_c d"',
  'true', 'false', 'null', '[1, 2, 3]', '[3, 1, 2, 3]', '["b", "a", "c"]', '[1, "a", null, true]', '[]', '[[1, 2], [3]]',
  '{Price}', '{Name}', '{Nothing}', '{When}', '{Earlier}', '{List}', '{Words}', '{DateText}', '{Neg}', '{Padded}', '{Csv}', '{Email}', '{Url}', '{Json}',
  'BLANK()', '1/0', '"abc" + 1',
];

let seed = 0x1357;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];

const hex = (s) => (s === '' ? '_' : Buffer.from(s, 'utf8').toString('hex'));
function render(v) {
  if (isError(v)) return `E|${v.code}|${hex(typeof v.message === 'string' ? v.message : String(v.message))}`;
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N|${String(v)}`;
  if (typeof v === 'string') return `T|${hex(v)}`;
  if (typeof v === 'boolean') return `B|${v ? 1 : 0}`;
  if (v instanceof Date) return `D|${Number.isNaN(v.getTime()) ? 'invalid' : v.toISOString()}`;
  if (Array.isArray(v)) return `[${v.map(render).join(',')}]`;
  return `?|${String(v)}`;
}

function evaluate(src) {
  if (process.env.FN_DEBUG === "2") console.error("eval", src);
  const fields = { ...FIELDS };
  for (const [k, v] of Object.entries(DATES)) fields[k] = new Date(v);
  let counter = 0;
  const ctx = {
    fields,
    now: new Date(NOW),
    // deterministic randomness for RANDOM, UUID and friends
    rng: () => { counter += 1; return ((counter * 7919) % 1000) / 1000; },
    randomSeed: 42,
    rowId: 'row-1', tableId: 'tbl-1', appId: 'app-1', realmId: 'realm-1', userId: 'user-1',
    createdOn: new Date('2026-01-01T00:00:00.000Z'), createdBy: 'ada', updatedOn: new Date('2026-02-02T00:00:00.000Z'), updatedBy: 'bob',
    browserAgent: 'test-agent',
  };
  return index.evaluate(src, ctx);
}

// Date functions are checked over ISO-8601 text and non-dates; text that only V8's legacy date parser reads ("5"
// is 1 May 2001, "-3.7" a January) is outside the port's ISO-only reading and is left out.
const LEGACY_DATE_TEXT = new Set([]);
const VOCAB_DATES = VOCAB.filter((v) => !LEGACY_DATE_TEXT.has(v));

// A second pass for the date groups: mostly valid dates, units and small counts, so the success paths run.
const DATE_VOCAB = [
  '{When}', '{Earlier}', '"2026-01-15"', '"2026-01-31T23:59:59Z"', '"2024-02-29"', '"2025-12-31"', 'DATE(2024, 2, 29)', 'DATE(2026, 1, 31)',
  'NOW()', 'TODAY()', 'DATEVALUE({When})', '"2026-03-01 12:30"', '3', '-1', '30', '0', '1', '2', '7', '12', '-30', '100', '"days"', '"months"',
  '"M"', '"m"', '"years"', '"weeks"', '"Q"', '"hours"', '"minutes"', '"seconds"', '"ms"', '"Y"', '"YM"', '"MD"', '"YD"', '"D"', '"s"', '"h"',
  '"YYYY-MM-DD"', '"dddd, MMMM Do YYYY"', '"MM/DD/YY HH:mm:ss.SSS"', '"[Week] W, Q"', '"L LL LT"', '"hh:mm A"', '"DDDD DDD"', '"Z ZZ"',
  '{DateText}', '{Stamp}', '1700000000', '1700000000000', '[{Earlier}, "2026-01-15"]', '"UTC"', '"+05:30"', '"America/New_York"',
];

// Calls that read like the formulas people write: lambdas over arrays, encodings, documents and positions.
function miscCases() {
  const out = [];
  const arrays = ['[3, 1, 2]', '["b", "a", "c"]', '[1, "a", null, true]', '[]', '{List}', '{Words}', '[[1, 2], [3]]', '[5, 5, 2, 2, 9]', '[10, 9, 100, 1]'];
  const exprs = ['current * 2', 'current + index', 'current > 1', 'index', 'UPPER(current)', 'LEN(current)', 'current', 'accumulator + current',
    'acc & current', '-current', 'IF(current > 1, 1, 0)', '1/0', 'value', 'current & "-" & index', 'ISBLANK(current)', 'current % 2'];
  for (const arr of arrays) {
    for (const e of exprs) {
      out.push(`MAP(${arr}, ${e})`, `FILTER(${arr}, ${e})`, `REDUCE(${arr}, ${e})`, `REDUCE(${arr}, ${e}, 0)`, `REDUCE(${arr}, ${e}, "")`,
        `SORT(${arr}, ${e})`, `SORT(${arr}, ${e}, true)`, `ANY(${arr}, ${e})`, `ALL(${arr}, ${e})`, `SELECT(${arr}, ${e})`);
    }
    out.push(`SORT(${arr})`, `SORT(${arr}, true)`, `SORT(${arr}, false)`, `ANY(${arr})`, `ALL(${arr})`, `SOME(${arr})`, `EVERY(${arr})`,
      `JOIN(${arr})`, `JOIN(${arr}, "; ")`, `ARRAYJOIN(${arr}, "")`, `FLAT(${arr})`, `FLATTEN(${arr}, 7, [8])`, `UNIQUE(${arr})`,
      `ARRAYUNIQUE(${arr})`, `COMPACT(${arr})`, `FIRST(${arr})`, `LAST(${arr})`);
    for (const n of ['0', '1', '-1', '2', '5', '-5', '"2"', 'true', 'null', '1.9', '-1.9', '"x"', '[2]', '[1, 2]']) {
      out.push(`GET(${arr}, ${n})`, `NTH(${arr}, ${n})`, `SLICE(${arr}, ${n})`, `SLICE(${arr}, 1, ${n})`, `SLICE(${arr}, ${n}, 2)`, `ARRAYSLICE(${arr}, ${n}, -1)`);
    }
  }
  // two-way stability and the merge path (64 or more elements), with ties
  const big = `[${Array.from({ length: 70 }, (_, i) => (i * 37) % 11).join(', ')}]`;
  const bigWords = `[${Array.from({ length: 66 }, (_, i) => `"w${(i * 17) % 13}"`).join(', ')}]`;
  out.push(`SORT(${big})`, `SORT(${big}, true)`, `SORT(${big}, current % 3)`, `SORT(${big}, -current)`, `SORT(${bigWords})`, `SORT(${bigWords}, LEN(current), true)`,
    `MAP(${big}, current + 1)`, `FILTER(${big}, current > 5)`, `UNIQUE(${big})`, `REDUCE(${big}, acc + current)`, `JOIN(${big}, "")`);
  out.push('UNIQUE(1, 2, 1, "1", "A", "a")', 'COMPACT(1, null, "", 2)', 'FLAT(1, [2, [3, [4]]])', 'COLLECT([1, 2, 3, 4], [1, 5, 3, 8], ">2")');
  const crit = ['">2"', '"<=3"', '"=3"', '"<>3"', '"!=3"', '">= 3 "', '"abc"', '3', '"> abc"', '"="', '""', 'true', '"<2.5"', '"=1e0"', '"<>"'];
  for (const cr of crit) out.push(`COLLECT([1, 2, 3, 4], [1, 5, 3, 8], ${cr})`, `COLLECT(["a", "b", "c"], ["x", "Y", "x"], ${cr})`, `COLLECT([1, 2, 3], [4], ${cr})`);
  for (const sp of ['("a, b,c")', '("a,b", "")', '("abc", "b")', '("", ",")', '(" a | b ", "|", false)', '("a--b--c", "--")', '("é,ü", ",")', '("😀a", "")',
    '(null, ",")', '(12345, 3)', '("a b  c", " ")', '("a,b", null, false)', '("x", "x")', '(",,", ",")', '("a\tb", "\t", true)', '({Csv})', '({Csv}, ",", false)']) out.push(`SPLIT${sp}`);
  for (const s of ['""', '"Hello"', '"Hello, World"', '"é"', '"😀"', '"a b"', '"abc"', '"1234567"', '{Name}', '12', 'true']) {
    out.push(`MD5(${s})`, `SHA1(${s})`, `SHA256(${s})`, `CRC32(${s})`, `BASE64(${s})`, `BASE64(BASE64(${s}), "decode")`, `BASE64(BASE64(${s}), "DECODE")`, `URLENCODE(${s})`,
      `URLENCODE(URLENCODE(${s}), "decode")`, `ENCODE_URL(${s})`);
  }
  for (const b of ['"SGVsbG8="', '"SGVsbG8"', '"SGVs bG8"', '"A"', '"AB"', '"ABC"', '"ABCD"', '"//8="', '"wqE="', '"4pyT"', '"8J+YgA=="', '"w"', '"/w=="', '"gA=="',
    '"+++="', '"/////w=="', '"!!!"', '""', '"8P//"', '"9////w"', '"7/8="', '"4A=="', '"____"', '"AAAA"', '"zzzz"', '"/+/+/+/+"']) out.push(`BASE64(${b}, "decode")`, `BASE64(${b}, "Decode")`);
  for (const u of ['"%41%20b"', '"%E2%9C%93"', '"%zz"', '"%"', '"%C3"', '"a+b"', '"%F0%9F%98%80"', '"%ED%A0%80"', '"100%"', '"%2"', '"x%20%25"', '""', '"%c3%a9"']) {
    out.push(`URLENCODE(${u}, "decode")`, `URL_ENCODE(${u}, "decode")`);
  }
  for (const u of ['"a b&c=d/e?f"', '"~!*\'()-_."', '"é😀"', '"%"', '";,/?:@&=+$#"']) out.push(`URLENCODE(${u})`);
  const xml = ['"<a><b>1</b><b>2</b><c x=\'5\' y=\\"6\\">t</c></a>"', '"<?xml version=\\"1.0\\"?><!-- c --><r a=\\"1\\" b=\'2\'><i>  text </i><e/><n><m>deep</m></n></r>"',
    '"<a>x<b>y</b>z</a>"', '"abc"', '"<a"', '"<a><b>"', '""', '"<a/>"', '"<a x=\\"1\\"/>"', '"<a><b/><b>q</b></a>"', '"<a><b>1</b></a><c/>"', '"<A><a>1</a></A>"',
    '"<a>&lt;t&gt;</a>"', '"<a><![CDATA[v]]></a>"', '"<a b=c>t</a>"', '"<a\\n b=\\"1\\">t</a>"'];
  const xpaths = ['"/a/b"', '"a/b[1]"', '"/a/c/@x"', '"/a/c"', '"/a/b[5]"', '"/b"', '"/a/@x"', '"a"', '"/"', '""', '"/a/b/@y"', '"/a/c[0]/@x"', '"/r/@a"', '"/r/@b"',
    '"/r/i"', '"/r/e"', '"/r/n/m"', '"/r/n/m/@z"', '"@x"', '"/a/b[0]"', '"/a/b[x]"', '"/a//b"', '"/a/c/@y"', '"/A/a"', '"/a/b[01]"', '"r/n"'];
  for (const x of xml) for (const p of xpaths) out.push(`XMLQUERY(${x}, ${p})`);
  out.push('XML_QUERY("<a>1</a>", "/a")', 'XMLQUERY(null, "/a")', 'XMLQUERY("<a>1</a>", null)', 'XMLQUERY("<a>1</a>", 12)');
  const json = ['"{\\"a\\":{\\"b\\":[1,2,{\\"c\\":\\"x\\"}]},\\"d\\":null,\\"e\\":[],\\"f\\":true,\\"g\\":1.5e2,\\"h\\":\\"\\"}"', '"[10,20,{\\"k\\":1}]"', '"{bad"', '"5"', '"\\"s\\""',
    '"true"', '"null"', '"{\\"a\\":1,\\"a\\":2}"', '"{\\"a b\\":{\\"c\\":[[1],[2,3]]}}"', '"{\\"0\\":\\"zero\\",\\"1\\":[7]}"', '"[]"', '"{}"', '{Json}', '""', '" [1] "'];
  const jpaths = ['"$.a.b[2].c"', '"a.b[0]"', '"$.a[\'b\'][1]"', '"$[\\"a\\"]"', '"d"', '"e"', '"$"', '""', '"a.x"', '"a.b.0"', '"[0]"', '"[2].k"', '"$[0]"', '"f"', '"g"', '"h"',
    '"a"', '"a.b"', '"[1]"', '"$.a b.c[1][1]"', '"0"', '"1[0]"', '"1.0"', '"[0][0]"', '"c"', '"a.b[2]"', '"a..b"', '"$a"', '"$.$"'];
  for (const j of json) for (const p of jpaths) out.push(`JSONQUERY(${j}, ${p})`);
  out.push('JSON_QUERY({Json}, "a.b[1]")', 'JSONQUERY(null, "a")', 'JSONQUERY("{}", null)', 'JSONQUERY("{\\"a\\":1}", 5)');
  out.push('NAME({Price})', 'NAME(Price)', 'NAME(1)', 'NAME("x")', 'NAME({Price} + 1)', 'PROPERTY({Price}, "decimals")', 'PROPERTIES({Price})', 'PROPERTY(1, "x")', 'PROPERTIES(1)',
    'ISNEW()', 'ISCHANGED("Price")', 'ISCHANGED({Price})', 'PRIORVALUE("Price")', 'PRIOR_VALUE("Price")', 'GETRECORDS("t")', 'GETRECORDS("t", "f")', 'GETFIELDVALUES("t", "f")',
    'CHILDREN()', 'CHILDREN(1)', 'ANCESTORS()', 'ANCESTORS(1)', 'ROW()', 'ROWID()', 'RECORD_ID()', 'TABLEID()', 'APPID()', 'REALMID()', 'USERID()', 'CREATEDON()', 'CREATED_TIME()',
    'UPDATEDON()', 'LAST_MODIFIED_TIME()', 'CREATEDBY()', 'UPDATEDBY()', 'MODIFIEDBY()', 'BROWSERAGENT()', 'USERAGENT()', 'CURRENTUSER()', 'USER()', 'USERNAME()', 'ROW() & "-" & TABLEID()');
  return out;
}

const group = process.argv.slice(2);
if (group.length === 0) {
  console.error(`usage: formula_functions_reference.mjs ${Object.keys(GROUPS).join('|')}`);
  process.exit(2);
}
const registry = index.getRegistry();
for (const name of group) {
  const spec = GROUPS[name];
  if (!spec) throw new Error(`unknown group ${name}`);
  const entries = registry.list().filter((e) => spec.categories.includes(e.category));
  const vocab = ['datetime', 'convert'].includes(name) ? VOCAB_DATES : VOCAB;
  const cases = [];
  for (const entry of entries) {
    if (process.env.FN_DEBUG) console.error("fn", entry.name);
    const names = [entry.name, ...(entry.aliases || [])];
    const min = entry.minArgs ?? 0;
    const max = entry.maxArgs === undefined || entry.maxArgs === -1 ? min + 3 : Math.min(entry.maxArgs, min + 3);
    const lazyOrVariadic = true;
    for (let k = 0; k < 28; k += 1) {
      const arity = min + Math.floor(rnd() * (max - min + 1));
      const call = `${pick(names)}(${Array.from({ length: arity }, () => pick(vocab)).join(', ')})`;
      cases.push(call);
    }
    // each alias once with a plain argument list, and the bare name of zero-argument functions
    for (const n of names) {
      const arity = Math.max(min, 1);
      cases.push(`${n}(${Array.from({ length: Math.min(arity, max) }, () => pick(vocab)).join(', ')})`);
      if (min === 0) cases.push(n);
    }
    if (['datetime', 'convert'].includes(name)) {
      for (let k = 0; k < 45; k += 1) {
        const arity = min + Math.floor(rnd() * (max - min + 1));
        cases.push(`${pick(names)}(${Array.from({ length: arity }, () => pick(DATE_VOCAB)).join(', ')})`);
      }
    }
    // arity refusals
    if (min > 0) cases.push(`${entry.name}()`);
    if (entry.maxArgs !== undefined && entry.maxArgs !== -1) cases.push(`${entry.name}(${Array.from({ length: entry.maxArgs + 1 }, () => '1').join(', ')})`);
  }
  if (name === 'misc') cases.push(...miscCases());
  const seen = new Set();
  // Calls whose real evaluation is not a function of the source: a loop that runs for the value of a date
  // (FACT of a timestamp counts to 1.7e12) and the random functions (only their refusals are deterministic).
  const unbounded = /^(FACT|COMBIN|PERMUT)\(.*\{(When|Earlier)\}|^(WORKDAY|WORKDAYADD)\((.*1700000000|[^,]*,\s*(NOW\(\)|TODAY\(\)|DATE\(|DATEVALUE|\{(When|Earlier|Stamp)\}|\[))/;
  const random = /^(RANDBETWEEN|RANDOM|RAND|UUID|GUID|GENERATEPASSWORD|GENERATE_PASSWORD)(\(|$)/i;
  const unique = cases.filter((c) => {
    if (seen.has(c)) return false;
    seen.add(c);
    if (unbounded.test(c)) return false;
    if (random.test(c)) {
      const r = render(evaluate(c));
      return r.startsWith('E|') || r === '_';
    }
    return true;
  });
  const lines = unique.map((src) => JSON.stringify({ src, expect: render(evaluate(src)) }));
  const chunks = [];
  const size = 40;
  for (let i = 0; i < lines.length; i += size) {
    chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
  }
  const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
  const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
  const uses = spec.modules.map((m) => `use e.algo.formula.${m} as ${m}\n`).join('');
  const registers = spec.modules.map((m) => `    if ${m}.register(&reg, a) != ok { os.exit(92i32) }\n`).join('');
  const template = readFileSync(resolve(here, 'formula_fn_fixture_template.e'), 'utf8');
  const out = template
    .replace('//__USES__\n', uses)
    .replace('    //__REGISTERS__\n', registers)
    .replace('//__VECTOR_FUNCTIONS__\n', `${funcs}\n`)
    .replace('    //__VECTOR_CALLS__\n', calls)
    .replace('__OK__', spec.ok)
    .replace('__GROUP__', name);
  const target = resolve(here, '..', 'tests/selfhost/fixtures/link', spec.fixture, 'src/main.e');
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, out, 'utf8');
  const errorCases = unique.filter((src) => render(evaluate(src)).startsWith('E|')).length;
  console.log(`${name}: ${entries.length} functions, ${unique.length} cases (${errorCases} error results) in ${chunks.length} chunks -> ${spec.fixture}`);
}
