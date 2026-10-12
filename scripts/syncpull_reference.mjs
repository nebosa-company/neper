// Reference vectors for `e.algo.syncpull` (L037): run appdor's own src/connectors/connector-type-map.js and the pagination,
// record-envelope and base-URL half of src/sync/synced-table.js over random operations -- native types and proposed
// mappings, a column's configuration and badge, base-URL placeholders, the pull request, the pagination an entity's
// action declares, the next-page cursor and the request it makes, envelope unwrapping, and whole page loops against a
// recorded server -- and write the link fixture tests/selfhost/fixtures/link/algo_syncpull. APPDOR_DIR defaults to
// D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, canon, clone, emit, rng } from './ref_common.mjs';

const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const st = await load('src/sync/synced-table.js');
const tm = await load('src/connectors/connector-type-map.js');
const { int, pick, chance } = rng(0x7c05);

const CONNECTORS = ['postgresql', 'google-sheets', 'mysql', 'sqlserver', 'sap-s4hana', 'business-central', 'epicor-kinetic', 'microsoft-graph', 'dynamics-365', 'microsoft-excel',
  'sharepoint', 'aveva-pi', 'kepware', 'salesforce', 'airtable', 'nope'];
const NATIVES = ['integer', 'text', 'jsonb', 'bytea', 'timestamp with time zone', 'uuid', 'string', 'formula', 'datetime', 'varchar', 'enum', 'blob', 'Edm.String', 'Edm.Duration',
  'Edm.Int64', 'Lookup', 'Picklist', 'Memo', 'Note', 'Choice', 'User', 'Float32', 'Blob', 'Guid', 'Boolean', 'picklist', 'anyType', 'weird_type', '', 'nvarchar(max)', 'rowversion', 'mediumtext'];
const LC8 = ['number', 'text', 'checkbox', 'date', 'dateTime', 'longText', 'singleSelect', 'multiSelect', 'email', 'phone', 'url', 'nope'];

const genColumns = () => Array.from({ length: 1 + int(5) }, (_, i) => ({ name: 'c' + i, nativeType: pick(NATIVES) }));

const genItems = (n, offset = 0) => Array.from({ length: n }, (_, i) => ({ id: offset + i + 1, name: 'n' + (offset + i + 1) }));

// A recorded server: answers a request URL by the style's rules and logs every (url, page) pair.
function makeServer(kind, opts) {
  const total = opts.total;
  const size = opts.size;
  const log = {};
  const items = genItems(total);
  const answer = (url) => {
    const u = new URL(url);
    const q = u.searchParams;
    if (opts.failAt !== undefined && (u.searchParams.get(opts.param) === String(opts.failAt) || (opts.failAt === 0 && !q.has(opts.param)))) {
      return opts.failWith;
    }
    let from = 0;
    let page;
    switch (kind) {
      case 'cursor': {
        const c = q.get(opts.param || 'cursor');
        from = c ? Number(c) : 0;
        const slice = items.slice(from, from + size);
        const next = from + size < total ? from + size : null;
        const body = { data: slice };
        if (opts.nested) body.meta = { next: next === null ? null : opts.absolute ? opts.origin + opts.basePath + u.pathname.slice(opts.basePath.length) + '?' + (opts.param || 'cursor') + '=' + next : String(next) };
        else if (next !== null) body.next_cursor = opts.absolute ? opts.origin + opts.basePath + u.pathname.slice(opts.basePath.length) + '?' + (opts.param || 'cursor') + '=' + next : (opts.stuck ? '0' : String(next));
        page = { ok: true, body };
        break;
      }
      case 'link': {
        const p = Number(q.get('page') || 1);
        const slice = items.slice((p - 1) * size, p * size);
        const headers = {};
        if (p * size < total) headers[opts.upper ? 'Link' : 'link'] = `<${opts.origin}${opts.basePath}${u.pathname.slice(opts.basePath.length)}?page=${p + 1}>; rel="next"`;
        page = { ok: true, body: opts.wrapped ? { records: slice } : slice, headers };
        break;
      }
      case 'offset': {
        from = Number(q.get(opts.param || 'offset') || 0);
        page = { ok: true, body: { items: items.slice(from, from + size) } };
        break;
      }
      case 'page': {
        const p = Number(q.get(opts.param || 'page') || 1);
        page = { ok: true, body: items.slice((p - 1) * size, p * size) };
        break;
      }
      default: throw new Error(kind);
    }
    return page;
  };
  return { log, fetchPage: async (request) => { const r = answer(request.url); log[request.url] = r; return clone(r); } };
}

async function genPages(force) {
  const kind = force ? 'cursor' : pick(['cursor', 'cursor', 'link', 'offset', 'page']);
  const basePath = pick(['/v1', '/v1/', '', '/api/v2']);
  const origin = 'https://api.example.com';
  const connection = { baseUrl: origin + basePath, ...(chance(0.3) ? { auth: { type: 'bearer', token: 't' } } : {}) };
  const basePathClean = basePath.replace(/\/+$/, '');
  const size = force ? 1 : pick([2, 3, 5]);
  const total = force ? force : pick([0, 1, size, size * 2, size * 3 + 1, 7]);
  const opts = { total, size, origin, basePath: basePathClean };
  let pagination;
  if (kind === 'cursor') {
    opts.nested = chance(0.3);
    opts.absolute = chance(0.3);
    opts.stuck = chance(0.1);
    if (chance(0.3)) { opts.param = 'after'; }
    pagination = { style: 'cursor', ...(opts.nested ? { cursorPath: 'meta.next' } : {}), ...(opts.param ? { cursorParam: 'after' } : {}) };
    if (opts.absolute && chance(0.3)) opts.origin = 'https://other.example.com';
  } else if (kind === 'link') {
    opts.upper = chance(0.4);
    opts.wrapped = chance(0.3);
    pagination = { style: 'link-header' };
  } else if (kind === 'offset') {
    if (chance(0.3)) opts.param = 'skip';
    pagination = { style: 'offset', itemsPath: 'items', limit: size, ...(opts.param ? { offsetParam: 'skip' } : {}) };
  } else {
    if (chance(0.3)) opts.param = 'p';
    pagination = { style: 'page', limit: size, ...(opts.param ? { pageParam: 'p' } : {}) };
  }
  if (kind === 'offset' && pagination.itemsPath === undefined) delete pagination.itemsPath;
  if (chance(0.15)) { opts.failAt = pick([0, size]); opts.failWith = pick([{ ok: false, reason: 'http-500', status: 500 }, { ok: false }, { ok: true, body: 'not a list' }, null]); opts.param = opts.param || (kind === 'cursor' ? 'cursor' : kind === 'offset' ? 'offset' : 'page'); }
  if (kind === 'cursor' && opts.nested) {
    // items live under `data`
  }
  if (chance(0.1)) pagination = { style: 'none' };
  const srv = makeServer(kind, opts);
  const limit = chance(0.35) ? pick([0, 1, size, size + 1, 4]) : undefined;
  const shape = chance(0.15) ? null : null;
  const entity = pick(['orders', '/orders', 'orders/list']);
  const shapes = { fieldsPath: 'fields', keep: ['id'] };
  const useShape = chance(0.2) ? shapes : undefined;
  const result = await st.pullPages({ connection: clone(connection), entity, pagination: clone(pagination), recordShape: useShape, limit, fetchPage: srv.fetchPage });
  return { op: { op: 'pages', connection, entity, pagination, shape: useShape ?? null, limit, pages: srv.log }, result };
}

const genCursorBody = () => pick([
  { next_cursor: 'abc' }, { next_cursor: 5 }, { next_cursor: '' }, { next_cursor: null }, {}, { meta: { next: 'zz' } }, { 'meta.next': 'whole' }, { next_cursor: { a: 1 } },
  { next_cursor: [1, 2] }, { next_cursor: 0 }, { next_cursor: true }, 'text', null, [1, 2, 3], { items: [1, 2, 3] }, { items: [1, 2] }, { data: { items: [1, 2, 3, 4] } },
]);
const genHeaders = () => pick([{}, { link: '<https://x.test/a?page=2>; rel="next"' }, { Link: '<https://x.test/a?page=3>;rel="next"' }, { link: '<https://x.test/a>; rel="prev"' },
  { link: '<https://x.test/p?page=1>; rel="prev", <https://x.test/p?page=2>; rel="next"' }, { link: '<>; rel="next"' }, { link: '<a<b>; rel="next"' }, { link: '' }, { link: 7 },
  { link: '<https://x.test/a?page=2>;   rel="next"' }, { link: '<https://x.test/a?page=2> ; rel="next"' }]);
const genPagination = () => pick([null, undefined, { style: 'none' }, { style: 'cursor' }, { style: 'cursor', cursorPath: 'meta.next', cursorParam: 'after' }, { style: 'link-header' },
  { style: 'offset', limit: 3 }, { style: 'offset' }, { style: 'page', limit: 2, itemsPath: 'items' }, { style: 'page', pageParam: 'p' }, { style: 'weird' }, { style: 'offset', offsetParam: 'skip', limit: 2 }]);
const BASEURLS = ['https://api.example.com/v1', 'https://api.example.com/v1/', 'https://api.example.com', 'https://api.example.com:443/v1', 'http://api.example.com:80/v1', 'https://API.example.com/v1',
  'https://api.example.com:8443/v1', '', 'not a url'];
const CURSORS = [{ style: 'cursor', value: 'abc' }, { style: 'cursor', value: 'https://api.example.com/v1/orders?cursor=9&x=1' }, { style: 'cursor', value: 'HTTPS://api.example.com/v1/orders?cursor=9' },
  { style: 'cursor', value: 'https://evil.example.com/v1/orders?cursor=9' }, { style: 'link-header', value: 'https://api.example.com/v1/orders?page=2' }, { style: 'link-header', value: 'https://api.example.com/other?a=1&a=2&b=%20x+y' },
  { style: 'link-header', value: 'https://api.example.com:443/v1/orders/../items/./x?z=1#frag' }, { style: 'link-header', value: 'orders?page=2' }, { style: 'link-header', value: 'https://api.example.com' },
  { style: 'link-header', value: 'https://api.example.com/v1' }, { style: 'link-header', value: 'https://api.example.com/v1/' }, { style: 'link-header', value: 'https://api.example.com/v10/orders' },
  { style: 'offset', value: 3 }, { style: 'page', value: 1 }, { style: 'weird', value: 1 }, null, undefined, { style: 'link-header', value: 'https://api.example.com/a b/ü?q=é' },
  { style: 'link-header', value: 'https://api.example.com/v1/a%20b?x' }, { style: 'link-header', value: 'https://api.example.com/v1/a\\b' }];
const genQuery = () => pick([{}, { page: '2' }, { offset: '10' }, { cursor: 'old', other: 'x' }, { skip: '4' }, { p: '3' }, { page: 'abc' }, { offset: '' }]);

const genChannel = () => {
  const actions = {};
  const n = 1 + int(4);
  for (let i = 0; i < n; i++) {
    actions['a' + i] = {
      method: pick(['GET', 'GET', 'POST']),
      path: pick(['/orders', '/orders/{id}', '/orders/{id}/items', '/{table}', '/orders?x=1', 'orders', '/items', '/{a}/{b}', '/orders/']),
      ...(chance(0.8) ? { pagination: pick([{ style: 'cursor' }, { style: 'offset', limit: 5 }, { style: 'page' }, { style: 'none' }, {}, { style: 'link-header' }]) } : {}),
    };
  }
  return { id: pick(['x', 'airtable', 'notion']), actions, ...(chance(0.1) ? { recordShape: { fieldsPath: 'data', keep: ['k'] } } : {}) };
};
const genEnvelope = (path) => {
  const rec = { id: 'r1', createdTime: 't', created_time: 'c', last_edited_time: 'e', k: 1 };
  rec[path] = pick([{ Name: 'A', id: 'inner' }, {}, 'text', null, [1], { 'fields.x': 1, x: 2 }, { a: { b: 1 } }]);
  return pick([rec, rec, 'str', null, [rec], { other: 1 }, { ...rec, extra: 1 }]);
};

function genOp() {
  switch (int(22)) {
    case 0: case 1: return { op: 'mapType', connector: pick(CONNECTORS), native: pick([...NATIVES, undefined, null, 5]) };
    case 2: return { op: 'lc8', connector: pick(CONNECTORS), lc8: pick(LC8) };
    case 3: return { op: 'types', connector: pick(CONNECTORS) };
    case 4: return { op: 'schema', connector: pick(CONNECTORS), columns: genColumns() };
    case 5: return { op: 'mapping', connector: pick(CONNECTORS), columns: genColumns() };
    case 6: return { op: 'columnConfig', column: pick([{ nativeType: 'int', direction: 'both' }, { nativeType: 'text', direction: 'push', downgraded: true, diagnostic: 'd' }, { nativeType: 'x', downgraded: true },
      { direction: 'pull', downgraded: false, diagnostic: 'z' }, {}, { nativeType: 'q', direction: 'other', downgraded: 'yes' }]), label: pick(['Postgres', undefined, '', 'Sheets']) };
    case 7: return { op: 'badge', config: pick([undefined, null, {}, { synced: null }, { synced: { source: 'PG', downgraded: true, diagnostic: 'why' } }, { synced: { source: 'PG' } },
      { synced: { downgraded: true } }, { synced: { source: 'S', downgraded: false, diagnostic: 'x' } }]) };
    case 8: case 9: return { op: 'baseUrl', channelBaseUrl: pick([undefined, '', 'https://{tenant}.example.com/v{version}', 'https://x.test', 'https://{a}.{b}.test']),
      config: pick([undefined, null, {}, { tenant: 'acme', version: 2 }, { tenant: 'acme' }, { baseUrl: 'https://custom/{x}', x: 'y' }, { baseUrl: 'https://{t}/x', t: '' }, { baseUrl: 'https://{t}/x', t: null }, { a: 'p', b: 'q' },
        { baseUrl: 'https://{t}/{u}', t: '{u}', u: 'z' }, { baseUrl: 'plain' }, { baseUrl: 'https://{a b}/x' }]) };
    case 10: return { op: 'pullRequest', connection: pick([{ baseUrl: 'https://api.example.com/v1' }, { baseUrl: 'http://localhost/x' }, { baseUrl: 'https://api.example.com', auth: { type: 'bearer', token: 'k' } }, {}, undefined]),
      entity: pick(['orders', '/orders', 'a/b']), query: pick([undefined, {}, { page: 2 }, { q: 'a b' }]) };
    case 11: case 12: return { op: 'pagination', channel: pick([genChannel(), genChannel(), null, {}]), entity: pick(['orders', '/orders', 'orders/5', 'orders/5/items', 'foo', '', 'orders?x=2', '/orders/', 'a/b']) };
    case 13: case 14: return { op: 'cursor', body: genCursorBody(), pagination: genPagination(), headers: genHeaders() };
    case 15: case 16: return { op: 'advance', cursor: pick(CURSORS), pagination: genPagination(), path: pick(['/orders', '/orders/list']), query: genQuery(), baseUrl: pick(BASEURLS) };
    case 17: { const shape = pick([{ fieldsPath: 'fields', keep: ['id', 'createdTime'] }, { fieldsPath: 'properties', keep: ['id', 'created_time', 'last_edited_time'] }, { fieldsPath: 'data.attrs', keep: ['id'] }, null]);
      const path = shape ? shape.fieldsPath : 'fields';
      return { op: 'unwrap', shape, records: Array.from({ length: int(4) }, () => (path.includes('.') ? { id: 1, data: { attrs: pick([{ a: 1, id: 2 }, 'x']) }, 'data.attrs': pick([undefined, { z: 1 }]) } : genEnvelope(path))) }; }
    case 18: return { op: 'shape', channel: pick([{ id: 'airtable' }, { id: 'notion' }, { id: 'x' }, {}, null, { id: 'x', recordShape: { fieldsPath: 'fields', keep: ['id'] } }]),
      connector: pick([undefined, 'airtable', 'notion', 'other', '']), stored: pick([undefined, [], [{ name: 'fields', structured: true }], [{ name: 'fields', structured: true }, { name: 'id' }], [{ name: 'fields', structured: true }, { name: 'extra' }],
        [{ name: 'properties', structured: true }, { name: 'created_time' }], [{ name: 'fields', structured: false }], [{ name: 'a' }], [null], [{ name: 'fields', structured: true }, null], [{ name: 'fields', structured: true }, { name: 'createdTime' }]]) };
    default: return null;
  }
}

async function execute(op) {
  switch (op.op) {
    case 'mapType': return tm.mapExternalType(op.connector, op.native);
    case 'lc8': return { native: tm.mapLc8ToNative(op.connector, op.lc8) };
    case 'types': return tm.listNativeTypes(op.connector);
    case 'schema': return tm.proposeSchema(op.connector, clone(op.columns));
    case 'mapping': return st.proposeMapping({ connector: op.connector, columns: clone(op.columns) });
    case 'columnConfig': return st.syncedColumnConfig(clone(op.column), op.label);
    case 'badge': return st.syncedColumnBadge(clone(op.config));
    case 'baseUrl': return st.resolveBaseUrl({ channelBaseUrl: op.channelBaseUrl, config: clone(op.config) });
    case 'pullRequest': return st.buildPullRequest(clone(op.connection), op.entity, clone(op.query));
    case 'pagination': return { pagination: st.pullPagination(clone(op.channel), op.entity) };
    case 'cursor': return { cursor: st.pullCursor(clone(op.body), clone(op.pagination), clone(op.headers)) };
    case 'advance': return st.advancePull({ cursor: clone(op.cursor), pagination: clone(op.pagination), path: op.path, query: clone(op.query), baseUrl: op.baseUrl });
    case 'unwrap': return st.unwrapRecords(clone(op.shape), clone(op.records));
    case 'shape': return { shape: st.pullRecordShape(clone(op.channel), op.connector, clone(op.stored)) };
    default: throw new Error(op.op);
  }
}

const cases = [];
const kinds = {};
let guard = 0;
for (const total of [230, 90]) {
  const forced = await genPages(total);
  cases.push({ op: forced.op, e: canon(forced.result) });
}
while (cases.length < 700 && guard++ < 5000) {
  const op = genOp();
  if (op === null) {
    const scenario = await genPages();
    kinds.pages = (kinds.pages || 0) + 1;
    cases.push({ op: scenario.op, e: canon(scenario.result) });
    continue;
  }
  kinds[op.op] = (kinds[op.op] || 0) + 1;
  let expected;
  try { expected = canon(await execute(op)); } catch (e) { kinds.skipped = (kinds.skipped || 0) + 1; continue; }
  cases.push({ op, e: expected });
}
const chunks = emit('algo_syncpull', 'syncpull_fixture_template.e', cases, 'algo syncpull ok');
console.log(`${cases.length} cases in ${chunks} chunks -> algo_syncpull`, kinds);
