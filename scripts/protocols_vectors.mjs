// Vectors for `x.net.webhook`, `x.net.authscheme`, `x.mcp.protocol` and `x.api.openapi` (L049): Appdor's own
// src/webhooks/sign.js, src/auth-schemes/index.js, src/mcp/protocol.js and src/api/openapi-builder.js over random inputs,
// with `Date.now` pinned, written as the link fixture tests/selfhost/fixtures/link/x_api_protocols.
// Usage: node scripts/protocols_vectors.mjs   (APPDOR_DIR defaults to D:/repos/appdor)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (f) => import(pathToFileURL(resolve(appdor, 'src', f)).href);
const NOW = 1_800_000_000_000;
Date.now = () => NOW;
const sign = await load('webhooks/sign.js');
const auth = await load('auth-schemes/index.js');
const mcp = await load('mcp/protocol.js');
const api = await load('api/openapi-builder.js');

let seed = 0x6a2d;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const norm = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const cases = [];
const add = (c) => cases.push(c);

// ---- webhooks
const BODIES = ['', '{"a":1}', 'hello world', 'ünï', '{"event":"x","n":[1,2,3]}', 'x'.repeat(200)];
const SECRETS = ['secret', 'k', 'a very long secret key '.repeat(4), 'ünï', 's3cr3t!'];
for (let i = 0; i < 20; i++) {
  const body = pick(BODIES), secret = pick(SECRETS), ts = pick([1_800_000_000, 1_700_000_000, 1_800_000_000.7, 0]);
  add({ op: 'hmac', key: secret, message: body, e: sign.hmacSha256(secret, body) });
  add({ op: 'signBody', body, secret, e: sign.signBody(body, secret) });
  add({ op: 'signV1', body, secret, ts, e: sign.signBodyV1(body, secret, ts) });
  add({ op: 'headers', body, secret, ts, e: sign.signatureHeaders(body, secret, ts) });
}
const nowSec = NOW / 1000;
for (let i = 0; i < 40; i++) {
  const body = pick(BODIES), secret = pick(SECRETS);
  const t = nowSec + pick([0, -10, 100, -299, 301, -400, 5000]);
  const good = sign.hmacSha256(secret, `${t}.${body}`);
  const sigs = [`v1=${good}`, good, `V1=${good.toUpperCase()}`, `  v1=${good}  `, `v1=${good.slice(0, -1)}0`, '', 'v1=', `v2=${good}`];
  const sig = pick(sigs);
  const stamp = pick([String(t), t, ` ${t} `, 'abc', '', '0x10', String(t) + 'x', '1e3']);
  const tol = chance(0.3) ? pick([10, 600, 0]) : undefined;
  const sec = chance(0.1) ? '' : secret;
  const r = tol === undefined ? sign.verifySignatureHeaders(body, sec, sig, stamp) : sign.verifySignatureHeaders(body, sec, sig, stamp, tol);
  add({ op: 'verifyHeaders', body, secret: sec, signature: sig, timestamp: String(stamp), tol: tol === undefined ? null : tol, e: norm(r) });
  const header = pick([`t=${t},v1=${good}`, `T=${t},V1=${good.toUpperCase()}`, `t=${t},v1=${good.slice(0, -2)}ff`, `t=,v1=${good}`, `t=${t}`, ` t=${t},v1=${good} `, `t=${t},v1=zz`, '', `t=0${t},v1=${good}`]);
  const r2 = tol === undefined ? sign.verifyV1(body, sec, header) : sign.verifyV1(body, sec, header, tol);
  add({ op: 'verifyV1', body, secret: sec, header, tol: tol === undefined ? null : tol, e: norm(r2) });
}
for (let i = 0; i < 12; i++) {
  const body = pick(BODIES);
  const secrets = pick([['a', 'b'], ['b', 'a'], ['x', 'y'], [], ['a']]);
  const header = sign.signBodyV1(body, 'a', nowSec + pick([0, -50, 1000]));
  add({ op: 'rotated', body, secrets, header, e: norm(sign.verifyV1Rotated(body, secrets, header)) });
}

// ---- auth schemes
const TOKEN = (exp) => `${Buffer.from('{"alg":"HS256"}').toString('base64url')}.${Buffer.from(JSON.stringify(exp === undefined ? {} : { exp })).toString('base64url')}.sig`;
const CONNS = [
  () => ({ type: 'none' }), () => ({}), () => ({ type: 'basic', username: 'u', password: pick(['p', '', undefined, 'ü']) }), () => ({ type: 'basic' }),
  () => ({ type: 'bearer', token: 't1', prefix: pick([undefined, 'Token', '']) }), () => ({ type: 'bearer' }),
  () => ({ type: 'apiKey', key: 'k', in: pick(['header', 'query', undefined]), name: pick([undefined, 'X-Key', 'bad name', 'key']), template: pick([undefined, 'Key {key}', 'a\r\nb']) }),
  () => ({ type: 'custom', headers: pick([{ 'X-A': '1' }, { 'bad name': 'v' }, { 'X-B': 'a\nb' }, undefined]), query: pick([{ q: 1 }, undefined]) }),
  () => ({ type: 'jwt', token: pick([TOKEN(NOW / 1000 + 600), TOKEN(NOW / 1000 - 600), TOKEN(), 'junk']), header: pick([undefined, 'X-Token']), prefix: pick([undefined, 'JWT']) }),
  () => ({ type: 'oauth2', accessToken: pick(['at', undefined]), tokenType: pick([undefined, 'MAC']), expiresAt: pick([undefined, NOW + 10_000, NOW + 600_000, NOW - 1]), refreshToken: pick([undefined, 'rt']), clientId: 'cid', clientSecret: pick([undefined, 'cs']), tokenUrl: pick(['https://idp/token', undefined]), scope: pick([undefined, 'a b']), grant: pick([undefined, 'client_credentials', 'password', 'authorization_code', 'device_code']), clientAuth: pick([undefined, 'body']), username: 'u', password: 'p w', code: 'c', redirectUri: 'https://app/cb', codeVerifier: 'v', deviceCode: 'd' }),
  () => ({ type: 'oidc', accessToken: pick(['at', undefined]), tokenUrl: 'https://idp/token', clientId: 'cid', refreshToken: pick([undefined, 'rt']), scope: pick([undefined, 'x']) }),
  () => ({ type: 'saml-bearer', accessToken: pick(['at', undefined]), tokenUrl: pick(['https://idp/token', undefined]), assertion: pick(['<a/>', undefined]), clientId: 'c', scope: pick([undefined, 's']), expiresAt: pick([undefined, NOW - 5, NOW + 1e6]) }),
  () => ({ type: 'hmac', secret: pick(['s', undefined]), header: pick([undefined, 'X-Sig']), prefix: pick([undefined, 'sha256=']), canonical: pick([undefined, '{method}.{path}.{timestamp}.{body}', '{body}{body}', '{timestamp}']), timestamp: pick([undefined, 1700000000, '1700000001']), timestampHeader: pick([undefined, false, 'X-Ts']) }),
  () => ({ type: 'webhook', url: pick(['https://hooks/x', undefined]), signingSecret: pick([undefined, 'ss']), header: pick([undefined, 'X-S']), timestampHeader: pick([undefined, 'X-T']), timestamp: pick([undefined, 5]) }),
  () => ({ type: 'awsSigV4', accessKeyId: pick(['AK', undefined]), secretAccessKey: pick(['SK', undefined]), sessionToken: pick([undefined, 'ST']), region: pick([undefined, 'eu-west-1']), service: pick([undefined, 's3']) }),
  () => ({ type: 'mtls', certificate: 'C', privateKey: 'K', ca: pick([undefined, 'CA']) }),
  () => ({ type: 'session', cookie: pick(['sid=1', undefined]), loginUrl: pick(['https://app/login', undefined]), username: 'u', password: 'p', expiresAt: pick([undefined, NOW - 1, NOW + 5]) }),
  () => ({ type: 'nope' }),
];
const REQS = [
  { url: 'https://api.example.com/v1/items?x=1', method: 'post', body: '{"a":1}', headers: { Accept: 'x' } },
  { url: 'https://s3.eu-west-1.amazonaws.com/b', body: { k: [1, 2] } },
  { url: 'not a url', method: undefined },
  { url: 'https://execute-api.us-east-1.amazonaws.com/p', query: { a: '1' } },
  {},
  { url: 'https://dynamodb-2.example.com/', body: undefined, headers: { 'X-Existing': 'v' } },
];
for (let i = 0; i < 90; i++) {
  const connection = JSON.parse(JSON.stringify(pick(CONNS)()));
  const request = JSON.parse(JSON.stringify(pick(REQS)));
  add({ op: 'apply', connection, request, e: norm(auth.applyAuth(connection, request)) });
}
for (let i = 0; i < 60; i++) {
  const connection = JSON.parse(JSON.stringify(pick(CONNS)()));
  add({ op: 'needsRefresh', connection, now: NOW, e: auth.needsRefresh(connection, NOW) });
  let r;
  try {
    const built = auth.buildRefresh(connection);
    r = built === null ? { none: true } : { request: built.request };
  } catch (e) { r = { threw: e.message }; }
  add({ op: 'buildRefresh', connection, e: norm(r) });
  add({ op: 'redact', connection, e: norm(auth.redactConnection(connection)) });
}
for (let i = 0; i < 24; i++) {
  const response = pick([{ access_token: 'a', token_type: 'bearer', expires_in: 3600, refresh_token: 'r', scope: 's' }, { access_token: 'a' }, { error: 'invalid_grant', error_description: 'bad' }, { error: 'x' }, {}, null, 'str',
    { access_token: 'a', expires_in: '60' }, { access_token: 'a', expires_in: 0 }, { access_token: 'a', id_token: TOKEN(5) }, { access_token: 'a', id_token: 'junk' }]);
  const connection = pick([{}, { scope: 'cs' }]);
  const oidc = chance(0.4);
  let r;
  try {
    r = { value: oidc ? auth.getScheme('oidc').refresh({ ...connection, tokenUrl: 'u', clientId: 'c' }).parse(response, NOW) : auth.parseTokenResponse(response, connection, NOW) };
  } catch (e) { r = { threw: e.message }; }
  add({ op: 'token', response, connection, oidc, e: norm(r) });
}
for (let i = 0; i < 30; i++) {
  const connection = { type: pick(['hmac', 'hmac', 'basic']), secret: pick(['s', undefined]), header: pick([undefined, 'X-Sig']), prefix: pick([undefined, 'sha256=']), toleranceSec: pick([undefined, 300, 10]), timestampHeader: pick([undefined, 'X-Ts']), canonical: pick([undefined, '{timestamp}|{body}']) };
  const ts = pick([NOW / 1000, NOW / 1000 - 1000, 'abc']);
  const body = pick(['{"a":1}', { a: 1 }, '']);
  const bodyText = typeof body === 'string' ? body : JSON.stringify(body);
  const canonical = (connection.canonical || '{timestamp}.{body}').replace('{timestamp}', String(ts)).replace('{body}', bodyText);
  const sig = sign.hmacSha256('s', canonical);
  const presented = pick([sig, (connection.prefix || '') + sig, sig.slice(0, -1), '']);
  const headers = { [pick(['X-Sig', 'x-sig', 'X-SIG'])]: presented, [pick(['X-Timestamp', 'x-timestamp', 'X-Ts'])]: String(ts) };
  add({ op: 'inbound', connection, headers, body, now: NOW, e: norm(auth.verifyInbound(connection, { headers, body, now: NOW })) });
}
for (let i = 0; i < 14; i++) {
  const connection = { type: 'oauth2', authorizeUrl: pick(['https://idp.example.com/authorize', 'HTTPS://IDP.example.com:443/a?x=1&scope=old', 'https://idp/auth?state=s0#frag', 'idp/auth', 'https://user@idp:8443/a b']), clientId: pick(['cid', undefined]), redirectUri: pick([undefined, 'https://app/cb']), scope: pick([undefined, 'read write']), accessType: pick([undefined, 'offline']) };
  const options = { redirectUri: pick([undefined, 'https://other/cb']), scope: pick([undefined, 'a']), state: pick([undefined, 'st ate', 's']), codeChallenge: pick([undefined, 'CH']), prompt: pick([undefined, 'consent']) };
  let r;
  try { r = { value: auth.buildAuthorizeUrl(connection, options) }; } catch (e) { r = { threw: true }; }
  add({ op: 'authorize', connection, options, e: norm(r) });
}

// ---- mcp
const MESSAGES = [
  { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', clientInfo: { name: 'c' } } },
  { jsonrpc: '2.0', id: 'a', method: 'initialize', params: { protocolVersion: 'bogus' } },
  { jsonrpc: '2.0', id: 2, method: 'ping' },
  { jsonrpc: '2.0', method: 'notifications/initialized' },
  { jsonrpc: '2.0', method: 'notifications/other' },
  { jsonrpc: '2.0', id: 3, method: 'prompts/list' },
  { jsonrpc: '2.0', id: 4, method: 'prompts/get', params: { name: 'explore_base' } },
  { jsonrpc: '2.0', id: 5, method: 'prompts/get', params: { name: 'find_records', arguments: { table: 'T', criteria: 'x' } } },
  { jsonrpc: '2.0', id: 6, method: 'prompts/get', params: { name: 'find_records', arguments: { table: 'T' } } },
  { jsonrpc: '2.0', id: 7, method: 'prompts/get', params: { name: 'summarize_table', arguments: {} } },
  { jsonrpc: '2.0', id: 8, method: 'prompts/get', params: { name: 'nope' } },
  { jsonrpc: '2.0', id: 9, method: 'resources/read', params: { uri: 'appdor://table/t1/schema' } },
  { jsonrpc: '2.0', id: 10, method: 'resources/read', params: { uri: 'http://x' } },
  { jsonrpc: '2.0', id: 11, method: 'tools/call', params: {} },
  { jsonrpc: '2.0', id: 12, method: 'tools/call', params: { name: 5 } },
  { jsonrpc: '2.0', id: 13, method: 'weird/method' },
  { jsonrpc: '1.0', id: 14, method: 'ping' },
  { jsonrpc: '2.0', id: 15 },
  { jsonrpc: '2.0', id: { x: 1 }, method: 'ping' },
  { jsonrpc: '2.0', id: null, method: 'ping' },
  [1, 2], 'str', null, 5,
];
for (let i = 0; i < 40; i++) {
  const seq = Array.from({ length: 2 + int(5) }, () => pick(MESSAGES));
  const instructions = chance(0.3) ? 'Be careful.' : '';
  const server = mcp.createMcpServer({}, instructions ? { instructions } : {});
  const out = [];
  for (const m of seq) {
    const isDelegated = m && m.method && ['tools/list', 'resources/list'].includes(m.method);
    if (isDelegated) { out.push('delegate'); continue; }
    if (m && m.method === 'resources/read' && m.params && m.params.uri === 'appdor://table/t1/schema' && server.initialized) { out.push('delegate'); continue; }
    if (m && m.method === 'tools/call' && m.params && typeof m.params.name === 'string' && server.initialized) { out.push('delegate'); continue; }
    let r;
    try { r = await server.handle(m); } catch (e) { r = { threw: true }; }
    out.push(r === null ? null : norm(r));
  }
  add({ op: 'server', messages: seq, instructions, e: out });
}
for (const m of MESSAGES) {
  const c = mcp.classifyMessage(m);
  add({ op: 'classify', message: m, e: norm(c) });
}
for (const v of ['2025-06-18', '2025-03-26', '2024-11-05', '2023-01-01', '', 'x']) add({ op: 'negotiate', version: v, e: mcp.negotiateVersion(v) });
for (const o of [{}, { resources: false }, { prompts: false }, { toolListChanged: true }, { resources: false, prompts: false, toolListChanged: true }]) add({ op: 'capabilities', opts: o, e: norm(mcp.serverCapabilities(o)) });
for (const name of ['explore_base', 'find_records', 'summarize_table', 'nope']) {
  for (const args of [{}, { table: 'T' }, { table: 'T', criteria: 'c' }, { table: '', criteria: 'c' }]) add({ op: 'prompt', name, args, e: norm(mcp.renderPrompt(name, args)) });
}
for (const uri of ['appdor://table/t1/schema', 'appdor://table/t1/records', 'appdor://table//schema', 'appdor://table/a/b/schema', 'appdor://table/t1/other', 'x', '', 'appdor://table/t1/schema/']) add({ op: 'uri', uri, e: norm(mcp.parseResourceUri(uri)) });
add({ op: 'tableUri', id: 't9', e: mcp.tableResourceUri('t9') });
for (let i = 0; i < 10; i++) {
  const m = pick(MESSAGES);
  add({ op: 'encode', message: m, e: mcp.encodeStdioMessage(m) });
}
for (const buf of ['{"a":1}\n{"b":2}\npartial', '\n\n   \n{"a":1}\nnot json\n', '', '{"a":1}\n', 'x\ny', '{"a":\n1}\n']) add({ op: 'decode', buffer: buf, e: norm(mcp.decodeStdioChunk(buf)) });
add({ op: 'notification', e: mcp.toolListChangedNotification() });
for (const [id, code, message, data] of [[1, -32601, 'm', undefined], [undefined, -32600, 'x', undefined], ['s', -32602, 'bad', { a: 1 }]]) {
  add({ op: 'rpcError', id: id === undefined ? null : id, code, message, e: norm(mcp.rpcError(id, code, message)) });
}

// ---- openapi
for (let i = 0; i < 12; i++) {
  const info = {};
  if (chance(0.8)) info.title = pick(['T', '']);
  if (chance(0.7)) info.version = pick(['2.0', '']);
  if (chance(0.4)) info.description = 'd';
  if (chance(0.3)) info.securitySchemes = { b: { type: 'http', scheme: 'bearer' } };
  if (chance(0.3)) info.servers = [{ url: 'https://x' }];
  if (chance(0.3)) info.tags = [{ name: 't' }];
  let spec = api.createSpec(info);
  const steps = [];
  for (let k = 0; k < 1 + int(4); k++) {
    if (chance(0.6)) {
      const step = { k: 'path', path: pick(['/a', '/b/{id}', '/a']), method: pick(['GET', 'post', 'Patch']), operation: { summary: pick(['s', 't']), responses: { 200: { description: 'ok' } } } };
      steps.push(step);
      api.addPath(spec, step.path, step.method, step.operation);
    } else {
      const step = { k: 'schema', name: pick(['Task', 'User', 'Task']), schema: { type: 'object', properties: { id: { type: 'string' } } } };
      steps.push(step);
      api.addSchema(spec, step.name, step.schema);
    }
  }
  add({ op: 'openapi', info, steps, e: { spec: norm(api.toJSON(spec)), validation: norm(api.validateSpec(spec)) } });
}
for (const spec of [null, 'x', {}, { openapi: '2.0' }, { openapi: '3.1.0', info: { title: 'a' }, paths: {} }, { openapi: '3.0.3', info: { title: 'a', version: '1' }, paths: [], components: { schemas: {} } }, { openapi: 3, info: {}, paths: null }]) {
  add({ op: 'validate', spec, e: norm(api.validateSpec(spec)) });
}

const bs = String.fromCharCode(92);
const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
for (let i = 0; i < lines.length; i += 8) {
  chunks.push('"' + lines.slice(i, i + 8).map((l) => l.split(bs).join(bs + bs).split('"').join(bs + '"')).join(bs + 'n') + bs + 'n"');
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'protocols_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_api_protocols/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_api_protocols`);
