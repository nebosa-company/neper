// Reference vectors for `e.algo.writeback` (L037): run appdor's own src/sync/writeback.js, src/connectors/writeback-outbox.js,
// src/connectors/sync-engine.js and src/connectors/index.js (buildRequest) over random single operations -- the outbox
// lifecycle, the host's judgements, the echo set, the field mapping, the three-way merge and the SSRF-checked request
// builder -- and write the link fixture tests/selfhost/fixtures/link/algo_writeback. The clock and the entry id are fixed
// (Date is replaced; the id is overwritten). APPDOR_DIR defaults to D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, canon, clone, emit, rng } from './ref_common.mjs';

const FIXED = '2026-05-01T08:30:00.000Z';
const RealDate = Date;
let tick = FIXED;
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(tick); else super(...args); }
  static now() { return new RealDate(tick).getTime(); }
};
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const wb = await load('src/sync/writeback.js');
const ob = await load('src/connectors/writeback-outbox.js');
const eng = await load('src/connectors/sync-engine.js');
const conn = await load('src/connectors/index.js');

const { int, pick, chance } = rng(0x57a1);

const FIELDS = ['status', 'qty', 'note', 'name'];
const VALUES = ['a', 'b', 1, 2, 2.5, true, false, null, '', 'x y'];
const val = () => pick(VALUES);
const instant = () => new RealDate(RealDate.UTC(2026, 3, 30, int(24), int(60), int(60))).toISOString();
const genPayload = () => { const o = {}; for (const f of FIELDS) if (chance(0.5)) o[f] = val(); return o; };
const genConfirmed = () => { const o = {}; for (const f of FIELDS) if (chance(0.55)) o[f] = val(); return o; };
const STATUSES = ['pending', 'failed', 'delivered', 'dead_lettered', 'reverted', 'weird'];

function genEntry(status) {
  const maxAttempts = pick([1, 2, 3, 5]);
  const attempts = int(maxAttempts + 1);
  const errors = Array.from({ length: Math.min(attempts, 3) }, (_, i) => pick(['boom', 'E_X: no', '409: conflict', 'timeout']) + i);
  return {
    id: 'wb_' + int(1000), connectionId: pick(['c1', 'c2', '']), tableId: pick(['t1', 't2']), recordKey: pick(['r1', 'r2', 'r 3', 'ü/5', '7']),
    payload: genPayload(), status: status || pick(STATUSES), attempts, maxAttempts, errors,
    lastConfirmedValue: chance(0.85) ? genConfirmed() : null,
    createdAt: instant(), lastAttemptAt: chance(0.5) ? instant() : null, deliveredAt: chance(0.2) ? instant() : null, deadLetteredAt: chance(0.2) ? instant() : null,
  };
}
const genResult = () => pick([
  { ok: true }, { ok: false, error: 'boom' }, { ok: false }, { ok: false, sourceError: { code: 'E_RO', message: 'read only' } },
  { ok: false, sourceError: { message: 'nope' } }, { ok: false, sourceError: { code: '422' }, error: 'bad' }, { ok: false, sourceError: {} }, {},
  { ok: 1 }, { ok: false, error: 'x', sourceError: null }, { ok: false, error: 42 },
]);

const genMapping = () => FIELDS.filter(() => chance(0.8)).map((name) => ({
  name,
  ...(chance(0.5) ? { direction: pick(['both', 'push', 'pull', 'other']) } : {}),
  ...(chance(0.2) ? { missingInSource: pick([true, false, 'yes']) } : {}),
  ...(chance(0.25) ? { sourceName: 'src_' + name } : {}),
}));
const genEngineMapping = () => FIELDS.filter(() => chance(0.8)).map((name) => ({ remote: 'r_' + name, local: name, direction: pick(['both', 'pull', 'push']) }));

const KEYS = [1, 2, 3, 'k4', 'k5', 6];
function genRow(key) {
  const r = { id: key };
  for (const f of ['a', 'b', 'c']) if (chance(0.7)) r[f] = pick([1, 2, 'x', 'y', null, true]);
  return r;
}
function genRows(keys, p) { return keys.filter(() => chance(p)).map(genRow); }
function evolve(rows) {
  return rows.filter(() => chance(0.88)).map((r) => (chance(0.4) ? { ...r, [pick(['a', 'b', 'c'])]: pick([1, 2, 'x', 'z', null]) } : { ...r }));
}

const BASES = ['https://api.example.com/v1', 'https://api.example.com/v1/', 'http://localhost:3000', 'https://10.0.0.5/api', 'https://192.168.1.1', 'https://172.20.0.1',
  'https://172.32.0.1/x', 'https://172.16.0.1', 'https://172.31.255.1', 'https://172.15.9.9', 'https://192.169.0.1', 'https://11.0.0.1', 'https://metadata.google.internal', 'https://intranet', 'ftp://files.example.com', 'https://[::1]/x', 'https://[fe80::1]/x',
  'https://[2001:db8::1]/x', 'https://169.254.169.254', 'https://x.localhost', 'https://127.0.0.1', 'https://0.0.0.0', 'https://8.8.8.8/dns', '', 'not a url',
  'https://Example.COM/api', 'https://example.com:8443/base', 'https://user:pw@example.com/z', 'http://127.1/x', 'https://[::ffff:127.0.0.1]/x'];
function genConnection() {
  const c = {};
  if (chance(0.95)) c.baseUrl = pick(BASES);
  const auth = pick([null, { type: 'bearer', token: 'tok' }, { type: 'bearer' }, { type: 'basic', username: 'u', password: 'p w' }, { type: 'apiKey', key: 'k1' },
    { type: 'apiKey', in: 'query', key: 'k2' }, { type: 'apiKey', in: 'query', param: 'tok', key: 'k3', }, { type: 'apiKey', header: 'X-Key', key: 'k4' },
    { type: 'customHeader', header: 'X-Custom', value: 'v' }, { type: 'customHeader', header: 'X-Only' }, { type: 'oauth' }, {}]);
  if (auth) c.auth = auth;
  if (chance(0.3)) c.headers = pick([{ 'X-Extra': '1' }, { 'Content-Type': 'text/plain' }, { Authorization: 'Custom' }]);
  return c;
}
function genReq() {
  const r = {};
  if (chance(0.95)) r.path = pick(['/orders', '/orders/1', '/a b', '/x?y=1', '', '/é']);
  if (chance(0.5)) r.query = pick([{}, { a: '1' }, { q: 'x y', page: 2 }, { s: 'é&=' }, { tok: 'dup' }, { api_key: 'mine' }, { a: [1, 2] }, { n: null }]);
  if (chance(0.5)) r.method = pick(['get', 'POST', 'patch', 'Delete']);
  if (chance(0.5)) r.body = pick(['raw text', { a: 1, b: [1, 2], c: { d: null } }, [1], 'x"y']);
  return r;
}

function genOp() {
  const now = instant();
  switch (int(22)) {
    case 0: return { op: 'create', opts: pick([{}, undefined, { connectionId: 'c', tableId: 't', recordKey: 'r', payload: genPayload(), lastConfirmedValue: genConfirmed(), maxAttempts: pick([1, 3, 0, undefined]) }, { recordKey: 0, payload: null }]), id: 'wb_fixed', now };
    case 1: case 2: case 3: return { op: 'deliver', entry: genEntry(pick(['pending', 'failed'])), result: genResult(), now };
    case 4: case 5: return { op: 'settle', entry: genEntry(pick(['pending', 'failed'])), result: genResult(), now };
    case 6: return { op: 'reversion', entry: genEntry() };
    case 7: return { op: 'mark', entry: genEntry(), fields: genConfirmed(), now };
    case 8: return { op: 'summary', entries: Array.from({ length: int(7) }, () => genEntry()) };
    case 9: return { op: 'twoWay', mapping: pick([genMapping(), genMapping(), null, 'x', [null, { name: '' }, { name: 'z', direction: 'both' }]]) };
    case 10: return { op: 'mapping', mapping: pick([genMapping(), genMapping(), undefined, [{}, { name: 'n', sourceName: '' }]]) };
    case 11: return { op: 'row', row: pick([{}, { id: 'row1', connection_id: 'c', table_id: 't', record_key: 'r', fields: genPayload(), last_confirmed: genConfirmed(), status: 'failed', attempts: 2, errors: ['e1'], max_attempts: 3, created_at: instant(), last_attempt_at: instant() },
      { id: '', status: '', attempts: '3', errors: 'nope', max_attempts: 0, fields: null }, { attempts: 'x', delivered_at: instant() }]), id: 'wb_fixed', now };
    case 12: return { op: 'patch', entry: pick([genEntry(), { status: 'pending' }, {}, { ...genEntry(), _revertedAt: instant() }]) };
    case 13: case 14: {
      const entry = genEntry('dead_lettered');
      return { op: 'revert', entry, reversion: ob.planReversion(clone(entry)), now };
    }
    case 15: return { op: 'finish', entry: genEntry('dead_lettered'), patch: pick([{ data: genConfirmed() }, {}, undefined]), now };
    case 16: {
      const fields = FIELDS.filter(() => chance(0.6));
      return { op: 'echoSet', delivered: Array.from({ length: int(5) }, () => pick([{ record_key: pick(['r1', 'r2', 'r1']), fields: genPayload() }, { fields: genPayload() }, { record_key: 'r9' }, null])).filter((x) => x !== null || chance(0.3)), fields };
    }
    case 17: {
      const fields = FIELDS.slice(0, 1 + int(3));
      const recs = Array.from({ length: 5 }, (_, i) => ({ id: 'k' + (i % 3), ...genPayload() }));
      const echoRecs = recs.filter(() => chance(0.5));
      const echo = [...eng.recordEcho(new Set(), 'k0', echoRecs[0] || {}, fields), ...echoRecs.map((r) => [...eng.recordEcho(new Set(), r.id, r, fields)][0])];
      const updates = recs.map((r) => pick([{ key: r.id, local: {}, remote: r }, { remote: r }, { key: undefined, remote: r }]));
      return { op: 'suppress', plan: pick([{ inserts: [], updates, deletes: [], bulkLoad: false }, undefined, { updates: [] }]), echo: pick([echo, [], echo]), syncKey: 'id', fields };
    }
    case 18: return { op: 'line', entries: Array.from({ length: int(6) }, () => genEntry()).filter(() => chance(0.9)) };
    case 19: {
      const mapping = genEngineMapping();
      const record = pick([{ ...Object.fromEntries(FIELDS.map((f) => [f, val()])) }, Object.fromEntries(mapping.map((m) => [chance(0.5) ? m.remote : m.local, val()])), {}]);
      return { op: pick(['toLocal', 'toRemote']), record, mapping };
    }
    case 20: {
      const keys = KEYS.slice(0, 3 + int(4));
      const base = genRows(keys, 0.8);
      const local = chance(0.7) ? evolve(base).concat(genRows([pick(KEYS)], 0.3)) : genRows(keys, 0.7);
      const remote = chance(0.7) ? evolve(base).concat(genRows([pick(KEYS)], 0.3)) : genRows(keys, 0.7);
      const fields = ['a', 'b', 'c'].filter(() => chance(0.75));
      if (!fields.length) fields.push('a');
      const echo = remote.filter(() => chance(0.2)).map((r) => [...eng.recordEcho(new Set(), r.id, r, fields)][0]);
      return { op: 'twoWayPlan', local, remote, base, key: 'id', fields, policy: pick(['manual', 'source-wins', 'local-wins', 'manual']), echo };
    }
    default: {
      if (chance(0.5)) return { op: 'request', connection: genConnection(), req: genReq() };
      return { op: 'push', connection: genConnection(), entity: pick(['orders', '/orders', '/items/x']), entry: { recordKey: pick(['r1', 'a/b c', 'é', 5, null, '']), payload: genPayload() }, mapping: pick([genMapping(), genMapping(), []]) };
    }
  }
}

function execute(op) {
  tick = op.now || FIXED;
  const e = clone(op.entry);
  switch (op.op) {
    case 'create': { const r = ob.createWritebackEntry(clone(op.opts) || undefined); r.id = op.id; return r; }
    case 'deliver': return ob.recordDelivery(e, clone(op.result));
    case 'settle': return wb.settleDelivery(e, clone(op.result));
    case 'reversion': return ob.planReversion(e);
    case 'mark': return ob.markReverted(e, clone(op.fields));
    case 'summary': return ob.summarizeOutbox(clone(op.entries));
    case 'twoWay': return wb.twoWayFields(clone(op.mapping));
    case 'mapping': return wb.writebackMapping(clone(op.mapping));
    case 'row': { const row = clone(op.row); const r = wb.entryFromRow(row); r.id = row.id || op.id; return r; }
    case 'patch': return wb.entryPatch(e);
    case 'revert': return wb.revertPatch(e, clone(op.reversion), op.now);
    case 'finish': return wb.finishReversion(e, clone(op.patch));
    case 'echoSet': return [...wb.echoSet(clone(op.delivered), op.fields)];
    case 'suppress': return wb.suppressEchoes(clone(op.plan), new Set(op.echo), op.syncKey, op.fields);
    case 'line': {
      const r = wb.outboxLine(clone(op.entries));
      return r;
    }
    case 'toLocal': return eng.mapRemoteToLocal(clone(op.record), clone(op.mapping));
    case 'toRemote': return eng.mapLocalToRemote(clone(op.record), clone(op.mapping));
    case 'twoWayPlan': {
      const plan = eng.planTwoWaySync({ local: clone(op.local), remote: clone(op.remote), base: clone(op.base) }, { key: op.key, fields: op.fields, policy: op.policy, echo: new Set(op.echo) });
      return plan;
    }
    case 'request': return conn.buildRequest(clone(op.connection), clone(op.req));
    case 'push': return wb.buildPushRequest(clone(op.connection), op.entity, clone(op.entry), clone(op.mapping));
    default: throw new Error(op.op);
  }
}

const cases = [];
const kinds = {};
for (let i = 0; i < 900; i++) {
  const op = genOp();
  kinds[op.op] = (kinds[op.op] || 0) + 1;
  cases.push({ op, e: canon(execute(op)) });
}
const chunks = emit('algo_writeback', 'writeback_fixture_template.e', cases, 'algo writeback ok');
console.log(`${cases.length} cases in ${chunks} chunks -> algo_writeback`, kinds);
