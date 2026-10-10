// Vectors for `x.identity.jose` and `x.identity.oidc` (L045): Appdor's own src/identity/{jose,oidc}.js over random tokens
// (real RS256 signatures from node:crypto, tampered and unsigned ones), discovery documents, authorization and token
// requests, callbacks, claims and link decisions, written as the link fixture tests/selfhost/fixtures/link/x_identity_oidc.
// Usage: node scripts/oidc_vectors.mjs   (APPDOR_DIR defaults to D:/repos/appdor)
import crypto from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (f) => import(pathToFileURL(resolve(appdor, f)).href);
const jose = await load('src/identity/jose.js');
const oidc = await load('src/identity/oidc.js');

let seed = 0x4d1e;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const norm = (v) => JSON.parse(JSON.stringify(v === undefined ? null : v));
const b64u = (buf) => Buffer.from(buf).toString('base64url');
const randBytes = (n) => Array.from({ length: n }, () => int(256));

const keys = [];
for (let i = 0; i < 2; i++) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 1024 + 1024 * i });
  const jwk = publicKey.export({ format: 'jwk' });
  keys.push({ privateKey, jwk: { ...jwk, kid: `key-${i}`, alg: 'RS256', use: 'sig' } });
}
const NOW = 1_800_000_000;

function sign(header, payload, key, tamper) {
  const h = b64u(JSON.stringify(header));
  let p = b64u(JSON.stringify(payload));
  const input = `${h}.${p}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(input), key.privateKey);
  if (tamper === 'payload') p = b64u(JSON.stringify({ ...payload, sub: 'mallory' }));
  let s = b64u(sig);
  if (tamper === 'sig') s = s.slice(0, -4) + (s.endsWith('AAAA') ? 'BBBB' : 'AAAA');
  if (tamper === 'short') s = s.slice(0, 20);
  return `${h}.${p}.${s}`;
}

const cases = [];
const add = (c) => cases.push(c);

// ---- base64url and decode
for (let i = 0; i < 30; i++) {
  const bytes = randBytes(int(40));
  const s = b64u(bytes);
  add({ op: 'b64', text: s, e: { bytes: bytes.map(String), roundtrip: jose.bytesToBase64Url(bytes) } });
}
for (const t of ['aGk=', 'aGk', 'a+b/c', '!!!', '', 'YQ==', '__8', 'a b']) add({ op: 'b64', text: t, e: { bytes: jose.base64UrlToBytes(t).map(String), roundtrip: jose.bytesToBase64Url(jose.base64UrlToBytes(t)) } });

const unsignedHeader = (alg) => b64u(JSON.stringify({ alg, typ: 'JWT' }));
function decodeCase(token) {
  const d = jose.decodeJwt(token);
  const e = d.ok ? { ok: true, header: d.header, payload: d.payload, signature: d.signature, signingInput: d.signingInput } : { ok: false, error: d.error.startsWith('malformed JWT') ? 'malformed JWT' : d.error };
  add({ op: 'decode', token, e: norm(e) });
}
for (let i = 0; i < 20; i++) decodeCase(`${b64u(JSON.stringify({ alg: 'RS256', kid: `k${i}` }))}.${b64u(JSON.stringify({ sub: `u${i}`, n: i, ok: chance(0.5), list: [1, 'a'] }))}.${b64u(randBytes(10))}`);
for (const t of ['', 'a.b', 'a.b.c.d', '...', 'e30.e30.', `${b64u('not json')}.${b64u('{}')}.x`, `${b64u('{}')}.${b64u('[1,2]')}.x`, `${b64u('null')}.${b64u('null')}.x`, `${b64u('{"é":"日本"}')}.${b64u('{}')}.s`]) decodeCase(t);

// ---- verify
const algs = ['RS256', 'RS256', 'RS256', 'none', 'None', 'HS256', 'PS256', 'ES256', 'RS512', ''];
for (let i = 0; i < 70; i++) {
  const key = pick(keys);
  const alg = pick(algs);
  const header = chance(0.1) ? { typ: 'JWT' } : { alg, typ: 'JWT', kid: key.jwk.kid };
  const token = sign(header, { sub: `u${i}`, iss: 'https://idp' }, key, pick([undefined, undefined, 'payload', 'sig', 'short']));
  let jwk = chance(0.75) ? key.jwk : pick([pick(keys).jwk, { kty: 'EC', crv: 'P-256' }, { kty: 'RSA' }, null, { ...key.jwk, n: '' }]);
  add({ op: 'verify', token, jwk, e: norm(jose.verifyJwtSignature(token, jwk)) });
}
add({ op: 'verify', token: 'junk', jwk: keys[0].jwk, e: norm(jose.verifyJwtSignature('junk', keys[0].jwk)) });
add({ op: 'verify', token: `${unsignedHeader('RS256')}.${b64u('{}')}.${b64u(randBytes(128))}`, jwk: keys[0].jwk, e: norm(jose.verifyJwtSignature(`${unsignedHeader('RS256')}.${b64u('{}')}.${b64u(randBytes(128))}`, keys[0].jwk)) });

// ---- select
for (let i = 0; i < 30; i++) {
  const set = [];
  const n = int(4);
  for (let k = 0; k < n; k++) set.push(chance(0.2) ? { kty: 'EC', kid: `e${k}` } : { ...pick(keys).jwk, kid: chance(0.2) ? undefined : `key-${k}` });
  const jwks = chance(0.1) ? {} : { keys: set };
  const header = pick([{ kid: 'key-1' }, { kid: 'nope' }, {}, { kid: '' }]);
  add({ op: 'select', jwks: norm(jwks), header, e: norm(jose.selectJwk(norm(jwks), header)) });
}

// ---- discovery and PKCE
const issuers = ['https://idp.example.com', 'https://idp.example.com/', 'https://idp.example.com///', 'idp', ''];
for (const iss of issuers) add({ op: 'discovery_url', issuer: iss, e: oidc.discoveryUrl(iss) });
for (let i = 0; i < 24; i++) {
  const doc = { issuer: 'https://idp', authorization_endpoint: 'https://idp/auth', token_endpoint: 'https://idp/token', jwks_uri: 'https://idp/jwks' };
  for (const k of Object.keys(doc)) if (chance(0.15)) delete doc[k];
  if (chance(0.5)) doc.userinfo_endpoint = 'https://idp/userinfo';
  if (chance(0.4)) doc.end_session_endpoint = 'https://idp/logout';
  if (chance(0.3)) doc.scopes_supported = ['openid', 'email'];
  if (chance(0.3)) doc.response_types_supported = ['code', 'id_token'];
  if (chance(0.3)) doc.id_token_signing_alg_values_supported = ['RS256', 'ES256'];
  if (chance(0.3)) doc.code_challenge_methods_supported = ['S256'];
  const r = oidc.parseDiscovery(doc);
  add({ op: 'discovery', doc, e: norm(r) });
}
add({ op: 'discovery', doc: null, e: norm(oidc.parseDiscovery(null)) });
for (let i = 0; i < 20; i++) {
  const verifier = chance(0.5) ? b64u(randBytes(32)) : pick(['', 'abc', 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk', 'é']);
  const challenge = oidc.pkceChallenge(verifier);
  add({ op: 'pkce', verifier, challenge, wrong: chance(0.3) ? 'x' + challenge : challenge, e: { challenge, verified: oidc.verifyPkce(verifier, chance(0) ? '' : challenge) } });
}
for (let i = 0; i < 6; i++) {
  const bytes = randBytes(32);
  const p = oidc.createPkcePair(() => bytes);
  add({ op: 'pair', bytes: bytes.map(String), e: p });
}

// ---- authorization url, callback, token request
const config = oidc.parseDiscovery({ issuer: 'https://idp', authorization_endpoint: 'https://idp/auth', token_endpoint: 'https://idp/token', jwks_uri: 'https://idp/jwks', end_session_endpoint: 'https://idp/logout' }).config;
const WORDS = ['abc', 'a b', 'ä~ö', 'x&y=z', 'https://app/cb?x=1', '日本', 'a+b', '*-._', "it's", '100%'];
for (let i = 0; i < 40; i++) {
  const o = {};
  if (chance(0.9)) o.clientId = pick(WORDS);
  if (chance(0.9)) o.redirectUri = pick(WORDS);
  if (chance(0.5)) o.scope = pick(WORDS);
  if (chance(0.9)) o.state = pick(WORDS);
  if (chance(0.9)) o.nonce = pick(WORDS);
  if (chance(0.9)) o.codeChallenge = pick(WORDS);
  if (chance(0.3)) o.prompt = 'consent';
  if (chance(0.3)) o.loginHint = 'a@b.c';
  if (chance(0.4)) { o.extra = {}; for (let k = 0; k < 1 + int(3); k++) o.extra[pick(['acr_values', 'state', 'ui_locales', 'max_age', 'client_id'])] = pick(WORDS); }
  add({ op: 'authurl', p: o, e: norm(oidc.buildAuthorizationUrl(config, o)) });
}
for (let i = 0; i < 30; i++) {
  const q = {};
  if (chance(0.15)) q.error = pick(['access_denied', 'login_required']);
  if (chance(0.1) && q.error) q.error_description = 'user said no';
  if (chance(0.9)) q.state = pick(['s1', 's2', '']);
  if (chance(0.8)) q.code = pick(['c1', 'c2']);
  const expected = pick(['s1', 's2', 'nope', '']);
  add({ op: 'callback', q, expected, e: norm(oidc.parseCallback(q, expected)) });
}
const ASCII = ['abc', 'a b', 'x&y=z', 'https://app/cb?x=1', 'a+b', '*-._', "it's", '100%'];
for (let i = 0; i < 30; i++) {
  const o = {};
  if (chance(0.9)) o.clientId = pick(ASCII);
  if (chance(0.5)) o.clientSecret = pick(ASCII);
  if (chance(0.9)) o.code = pick(WORDS);
  if (chance(0.9)) o.redirectUri = pick(WORDS);
  if (chance(0.9)) o.codeVerifier = pick(WORDS);
  add({ op: 'tokenreq', p: o, e: norm(oidc.buildTokenRequest(config, o)) });
}
for (let i = 0; i < 12; i++) {
  const o = {};
  if (chance(0.7)) o.idTokenHint = pick(WORDS);
  if (chance(0.7)) o.postLogoutRedirectUri = pick(WORDS);
  if (chance(0.5)) o.state = pick(WORDS);
  const cfg = chance(0.8) ? config : { ...config, endSessionEndpoint: null };
  add({ op: 'logout', p: o, noEnd: cfg.endSessionEndpoint === null, e: norm(oidc.buildLogoutUrl(cfg, o)) });
}

// ---- ID tokens
const jwks = { keys: keys.map((k) => k.jwk) };
for (let i = 0; i < 110; i++) {
  const key = pick(keys);
  const claims = { sub: `u${i}`, iss: 'https://idp', aud: 'client-1', exp: NOW + 600, iat: NOW - 10, nonce: 'n-1', email: 'a@acme.com', email_verified: true };
  const mut = int(18);
  if (mut === 1) claims.iss = 'https://evil';
  if (mut === 2) claims.aud = 'other';
  if (mut === 3) claims.aud = ['client-1', 'client-2'];
  if (mut === 4) { claims.aud = ['client-1', 'client-2']; claims.azp = 'client-2'; }
  if (mut === 5) claims.exp = NOW - 120;
  if (mut === 6) claims.exp = NOW - 30;
  if (mut === 7) delete claims.exp;
  if (mut === 8) claims.nbf = NOW + 600;
  if (mut === 9) claims.iat = NOW + 600;
  if (mut === 10) claims.nonce = 'wrong';
  if (mut === 11) delete claims.nonce;
  if (mut === 12) claims.auth_time = NOW - 5000;
  if (mut === 13) claims.exp = 'soon';
  if (mut === 14) delete claims.iss;
  if (mut === 15) delete claims.aud;
  const token = sign({ alg: 'RS256', kid: chance(0.9) ? key.jwk.kid : 'ghost', typ: 'JWT' }, claims, key, chance(0.1) ? 'sig' : undefined);
  const ex = { issuer: 'https://idp', clientId: 'client-1', nonce: chance(0.85) ? 'n-1' : undefined, jwks, now: NOW * 1000 + int(900) };
  if (chance(0.2)) ex.maxAgeSeconds = pick([60, 3600, 100000]);
  if (chance(0.2)) ex.skewSeconds = pick([0, 5, 300]);
  if (chance(0.05)) ex.jwks = { keys: [] };
  add({ op: 'validate', token, ex, e: norm(oidc.validateIdToken(token, ex)) });
}
add({ op: 'validate', token: 'garbage', ex: { issuer: 'https://idp', clientId: 'c', jwks, now: NOW * 1000 }, e: norm(oidc.validateIdToken('garbage', { issuer: 'https://idp', clientId: 'c', jwks, now: NOW * 1000 })) });

// ---- profile and link policy
for (let i = 0; i < 40; i++) {
  const claims = {};
  if (chance(0.9)) claims.sub = `u${i}`;
  if (chance(0.8)) claims.email = pick(['a@acme.com', 'B@ACME.com', 'c@other.org', 'x@y@z.com', '']);
  if (chance(0.7)) claims.email_verified = pick([true, false, 'true']);
  if (chance(0.5)) claims.name = pick(['Ann', '']);
  if (chance(0.4)) claims.preferred_username = 'ann42';
  if (chance(0.3)) claims.given_name = 'Ann';
  if (chance(0.3)) claims.family_name = 'Lee';
  if (chance(0.5)) claims.groups = pick([['eng', 'ops'], 'solo', [], '']);
  if (chance(0.3)) claims.roles = pick([['admin'], 'viewer']);
  if (chance(0.3)) claims.mail = 'mapped@acme.com';
  if (chance(0.2)) claims.grp = ['mapped'];
  if (chance(0.7)) claims.iss = 'https://idp';
  const mapping = chance(0.4) ? { email: 'mail', groups: 'grp' } : {};
  add({ op: 'profile', claims, mapping, e: norm(oidc.profileFromClaims(claims, mapping)) });
}
const PROFILES = [
  { email: 'a@acme.com', emailVerified: true }, { email: 'a@acme.com', emailVerified: false },
  { email: 'a@other.org', emailVerified: true }, { email: null, emailVerified: true }, { email: 'A@ACME.COM', emailVerified: true },
  { email: 'x@y@acme.com', emailVerified: true },
];
for (let i = 0; i < 48; i++) {
  const profile = PROFILES[i % PROFILES.length];
  const opts = { verifiedDomains: pick([[], ['acme.com'], ['ACME.com', 'x.io']]), existingAccount: chance(0.5) ? { id: 1 } : null, allowUnverifiedEmailLink: chance(0.3) };
  add({ op: 'link', profile, opts, e: norm(oidc.linkPolicy(profile, opts)) });
}

const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
const size = 10;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'oidc_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_identity_oidc/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_identity_oidc`);
