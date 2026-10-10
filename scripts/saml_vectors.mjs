// Vectors for `x.identity.xml` and `x.identity.saml` (L045): Appdor's own src/identity/{xml,saml}.js over random XML
// documents and over SAML responses really signed with node:crypto (RSA-SHA256 over the exclusively canonicalised SignedInfo
// the reference itself produces), then tampered, wrapped, expired, replayed and re-keyed, written as the link fixture
// tests/selfhost/fixtures/link/x_identity_saml. Usage: node scripts/saml_vectors.mjs (APPDOR_DIR defaults to D:/repos/appdor)
import crypto from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (f) => import(pathToFileURL(resolve(appdor, f)).href);
const xml = await load('src/identity/xml.js');
const saml = await load('src/identity/saml.js');

let seed = 0x7ab3;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const norm = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');

const keys = [];
for (let i = 0; i < 2; i++) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 1024 + 1024 * i });
  const jwk = publicKey.export({ format: 'jwk' });
  keys.push({ privateKey, jwk: { kty: 'RSA', n: jwk.n, e: jwk.e }, der: publicKey.export({ format: 'der', type: 'spki' }) });
}

const cases = [];
const add = (c) => cases.push(c);

// ---------------------------------------------------------------- xml.js
function treeJson(n) {
  return {
    name: n.name, prefix: n.prefix, local: n.local, attributes: n.attributes, attributeOrder: n.attributeOrder, namespaces: n.namespaces, text: n.text,
    nodes: n.nodes.map((e) => (e.type === 'text' ? { type: 'text', value: e.value } : { type: 'element', node: treeJson(e.node) })),
  };
}
function preorder(n, out = []) { out.push(n); for (const c of n.children) preorder(c, out); return out; }

const NAMES = ['a', 'b:item', 'ns:x', 'saml:Assertion', 'p:q', 'row'];
const TEXTS = ['', 'text', ' spaced ', 'a &amp; b', '&lt;tag&gt;', '&quot;q&quot; &apos;', '&#65;&#x42;', 'caf\u00e9', '日本', 'x\ty', 'a\r\nb', '&unknown;', '&#4a;', '\n  '];
function elem(depth, ns) {
  const prefix = chance(0.4) ? pick(['p', 'q', 'ds', 'saml']) : '';
  const name = (prefix ? `${prefix}:` : '') + pick(['Item', 'Node', 'Value', 'Assertion', 'Signature']);
  const attrs = [];
  const used = new Set();
  for (let i = 0; i < int(4); i++) {
    const an = pick(['id', 'ID', 'Id', 'type', 'xsi:type', 'p:attr', 'z', 'lang', 'xml:lang', 'b']);
    if (used.has(an)) continue;
    used.add(an);
    const quote = chance(0.8) ? '"' : "'";
    let v = pick(['v', 'a&amp;b', 'a<b', 'q"x', 'saml:NameIDType', 'p:Other', '', 'tab\there', '1', 'x y']);
    if (quote === "'") v = v.replace(/'/g, '&apos;');
    else v = v.replace(/"/g, '&quot;');
    attrs.push(` ${an}=${quote}${v}${quote}`);
  }
  const decls = [];
  if (chance(0.3) || depth === 0) {
    for (const p of ['p', 'q', 'ds', 'saml', 'xsi']) if (chance(0.4) || depth === 0) decls.push(` xmlns:${p}="urn:${p}${chance(0.2) ? ':2' : ''}"`);
    if (chance(0.3)) decls.push(` xmlns="${pick(['urn:default', 'urn:other', ''])}"`);
  }
  let body = '';
  if (depth < 3) {
    for (let i = 0; i < int(4); i++) {
      const r = int(8);
      if (r < 3) body += pick(TEXTS);
      else if (r === 3) body += '<!-- note -->';
      else if (r === 4) body += '<![CDATA[<raw & text>]]>';
      else body += elem(depth + 1, ns);
    }
  } else body = pick(TEXTS);
  if (!body && chance(0.4)) return `<${name}${decls.join('')}${attrs.join('')}/>`;
  return `<${name}${decls.join('')}${attrs.join('')}>${body}</${name}>`;
}
const BROKEN_XML = ['', '<a>', '<a></b>', '</a>', '<a><b></a></b>', '<a x=1/>', '<a x="1/>', '<a x/>', '<1a/>', '<a/><b/>', 'text', '<!-- x', '<![CDATA[ x', '<?pi', '<a', '<a></a', '<!DOCTYPE x [<!ENTITY e "v">]><a>&e;</a>', '<a b="1" b="2"/>', '<a>é</b>'];
for (let i = 0; i < 60; i++) {
  const src = chance(0.2) ? pick(BROKEN_XML) : (chance(0.5) ? '<?xml version="1.0"?>\n' : '') + elem(0, {});
  const r = xml.parseXml(src);
  add({ op: 'xml', src, e: norm(r.ok ? { ok: true, tree: treeJson(r.root) } : { ok: false, error: r.error }) });
}
for (const src of BROKEN_XML) {
  const r = xml.parseXml(src);
  add({ op: 'xml', src, e: norm(r.ok ? { ok: true, tree: treeJson(r.root) } : { ok: false, error: r.error }) });
}
for (let i = 0; i < 60; i++) {
  const src = elem(0, {});
  const r = xml.parseXml(src);
  if (!r.ok) continue;
  const all = preorder(r.root);
  const at = int(all.length);
  const inclusive = chance(0.3) ? pick([['p'], ['saml', 'ds'], ['zz'], ['']]) : [];
  const c = xml.canonicalize(all[at], { inclusivePrefixes: inclusive });
  add({ op: 'c14n', src, at, inclusive, e: c.xml });
}
for (const t of ['a &amp; b', '&#65;', '&#x41;', '&#X41;', '&lt;&gt;&quot;&apos;', '&bogus;', '&#4a;', '&#;', '&;', 'a&b', '&amp', '&#x;', '&#12', '&&amp;', '&#128512;', '&#0;']) {
  add({ op: 'entities', text: t, e: xml.decodeEntities(t) });
}
for (let i = 0; i < 30; i++) {
  const src = elem(0, {});
  const r = xml.parseXml(src);
  if (!r.ok) continue;
  const all = preorder(r.root);
  const ns = pick(['', 'urn:p', 'urn:q', 'urn:saml', 'urn:ds', 'urn:default', 'nope']);
  const local = pick(['Item', 'Node', 'Value', 'Assertion', 'Signature']);
  const found = xml.findElements(r.root, ns, local).map((n) => all.indexOf(n));
  const id = pick(['v', '1', 'nope', '']);
  const byId = xml.findById(r.root, id);
  add({ op: 'find', src, ns, local, id, e: { found, byId: byId ? all.indexOf(byId) : -1 } });
}

// ---------------------------------------------------------------- saml.js
const NS_P = 'urn:oasis:names:tc:SAML:2.0:protocol';
const NS_A = 'urn:oasis:names:tc:SAML:2.0:assertion';
const NS_D = 'http://www.w3.org/2000/09/xmldsig#';
const EXC = 'http://www.w3.org/2001/10/xml-exc-c14n#';
const NOW = Date.UTC(2026, 5, 1, 12, 0, 0);
const iso = (ms) => new Date(ms).toISOString().replace('.000Z', 'Z');

function sigXml(refId, o) {
  const alg = o.sigAlg || 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
  const dig = o.digAlg || 'http://www.w3.org/2001/04/xmlenc#sha256';
  const incl = o.prefixList ? `<ec:InclusiveNamespaces xmlns:ec="${EXC}" PrefixList="${o.prefixList}"/>` : '';
  const uri = o.refUri === undefined ? `#${refId}` : o.refUri;
  return `<ds:Signature xmlns:ds="${NS_D}"><ds:SignedInfo><ds:CanonicalizationMethod Algorithm="${EXC}"/>`
    + `<ds:SignatureMethod Algorithm="${alg}"/><ds:Reference URI="${uri}"><ds:Transforms>`
    + `<ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/><ds:Transform Algorithm="${EXC}">${incl}</ds:Transform>`
    + `</ds:Transforms><ds:DigestMethod Algorithm="${dig}"/><ds:DigestValue>@@DIGEST@@</ds:DigestValue></ds:Reference></ds:SignedInfo>`
    + `<ds:SignatureValue>@@SIGVALUE@@</ds:SignatureValue></ds:Signature>`;
}

function responseXml(o, sigs) {
  const nl = o.pretty ? '\n  ' : '';
  const asn = (id, sig) => `<saml:Assertion xmlns:saml="${NS_A}" ID="${id}" Version="2.0" IssueInstant="${iso(NOW - 1000)}">${nl}`
    + `<saml:Issuer>${o.issuer}</saml:Issuer>${nl}${sig}`
    + `<saml:Subject>${nl}<saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">${o.nameId}</saml:NameID>`
    + `<saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer"><saml:SubjectConfirmationData${o.recipient ? ` Recipient="${o.recipient}"` : ''}${o.confNotOnOrAfter ? ` NotOnOrAfter="${o.confNotOnOrAfter}"` : ''}${o.inResponseTo ? ` InResponseTo="${o.inResponseTo}"` : ''}/></saml:SubjectConfirmation>${nl}</saml:Subject>${nl}`
    + `<saml:Conditions${o.notBefore ? ` NotBefore="${o.notBefore}"` : ''}${o.notOnOrAfter ? ` NotOnOrAfter="${o.notOnOrAfter}"` : ''}>${o.audience ? `<saml:AudienceRestriction><saml:Audience>${o.audience}</saml:Audience></saml:AudienceRestriction>` : ''}</saml:Conditions>${nl}`
    + `<saml:AuthnStatement AuthnInstant="${iso(NOW - 2000)}" SessionIndex="_s1"/>${nl}`
    + `<saml:AttributeStatement><saml:Attribute Name="groups"><saml:AttributeValue xsi:type="xs:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xs="http://www.w3.org/2001/XMLSchema">eng</saml:AttributeValue><saml:AttributeValue>ops &amp; dev</saml:AttributeValue></saml:Attribute>`
    + `<saml:Attribute FriendlyName="mail"><saml:AttributeValue>${o.nameId}</saml:AttributeValue></saml:Attribute></saml:AttributeStatement>${nl}</saml:Assertion>`;
  let body = `<samlp:Response xmlns:samlp="${NS_P}" ID="_r1" Version="2.0" IssueInstant="${iso(NOW - 1000)}"${o.destination ? ` Destination="${o.destination}"` : ''}${o.respInResponseTo ? ` InResponseTo="${o.respInResponseTo}"` : ''}>${nl}`
    + `<saml:Issuer xmlns:saml="${NS_A}">${o.issuer}</saml:Issuer>${nl}${sigs.response}`
    + `<samlp:Status><samlp:StatusCode Value="${o.status}"/>${o.statusMessage ? `<samlp:StatusMessage>${o.statusMessage}</samlp:StatusMessage>` : ''}</samlp:Status>${nl}`
    + asn('_a1', sigs.assertion);
  if (o.second) body += asn('_a2', '');
  return `${body}${nl}</samlp:Response>`;
}

// Signs `target` ('_r1' or '_a1') into the signature slot, using the reference's own canonicalizer.
function signResponse(o, where, key, refId) {
  const sigTemplate = sigXml(refId, o);
  const build = (resp, asn) => responseXml(o, { response: resp, assertion: asn });
  const withoutSig = build('', '');
  const slot = (s) => (where === 'response' ? build(s, '') : build('', s));
  // digest over the referenced element without its Signature
  const doc0 = xml.parseXml(withoutSig).root;
  const target0 = xml.findById(doc0, refId);
  const canon = xml.canonicalize(target0, { inclusivePrefixes: o.prefixList ? o.prefixList.split(' ') : [] });
  const digest = crypto.createHash('sha256').update(canon.xml).digest('base64');
  let withSig = slot(sigTemplate.replace('@@DIGEST@@', digest));
  const doc1 = xml.parseXml(withSig.replace('@@SIGVALUE@@', 'X')).root;
  const signedInfo = xml.findElement(doc1, NS_D, 'SignedInfo');
  const canonInfo = xml.canonicalize(signedInfo, { inclusivePrefixes: [] });
  const sigValue = crypto.sign('RSA-SHA256', Buffer.from(canonInfo.xml), key.privateKey).toString('base64');
  return { xml: withSig.replace('@@SIGVALUE@@', sigValue), digest, sigValue };
}

function sample() {
  const o = {
    issuer: 'https://idp.example.com', nameId: 'alice@acme.com', audience: 'https://sp.example.com', status: saml.STATUS_SUCCESS,
    recipient: 'https://sp.example.com/acs', destination: 'https://sp.example.com/acs', inResponseTo: '_req1', respInResponseTo: '_req1',
    notBefore: iso(NOW - 60000), notOnOrAfter: iso(NOW + 300000), confNotOnOrAfter: iso(NOW + 300000), pretty: chance(0.5), statusMessage: '',
  };
  return o;
}

const SAMPLE_CFG = (key) => ({ issuer: 'https://idp.example.com', audience: 'https://sp.example.com', acsUrl: 'https://sp.example.com/acs', jwk: key.jwk, expectedInResponseTo: '_req1', now: NOW, skewMs: 60000 });

for (let i = 0; i < 110; i++) {
  const key = pick(keys);
  const o = sample();
  let where = pick(['assertion', 'assertion', 'response']);
  const refId = where === 'response' ? '_r1' : '_a1';
  const mutation = int(24);
  const cfg = SAMPLE_CFG(key);
  if (chance(0.3)) o.prefixList = pick(['saml', 'samlp saml', 'xs xsi']);
  if (mutation === 1) o.issuer = 'https://evil.example.com';
  if (mutation === 2) o.audience = 'https://other.example.com';
  if (mutation === 3) o.notOnOrAfter = iso(NOW - 120000);
  if (mutation === 4) o.notBefore = iso(NOW + 600000);
  if (mutation === 5) o.status = 'urn:oasis:names:tc:SAML:2.0:status:Responder';
  if (mutation === 6) o.statusMessage = 'denied';
  if (mutation === 7) o.recipient = 'https://sp.example.com/other';
  if (mutation === 8) o.inResponseTo = '_zzz';
  if (mutation === 9) o.destination = 'https://sp.example.com/else';
  if (mutation === 10) o.audience = '';
  if (mutation === 11) o.confNotOnOrAfter = iso(NOW - 120000);
  if (mutation === 12) o.sigAlg = 'http://www.w3.org/2000/09/xmldsig#rsa-sha1';
  if (mutation === 13) o.digAlg = 'http://www.w3.org/2000/09/xmldsig#sha1';
  if (mutation === 14) o.refUri = '#nope';
  if (mutation === 15) o.refUri = '';
  if (mutation === 16) o.second = true;
  const signed = signResponse(o, where, key, refId);
  let docXml = signed.xml;
  if (mutation === 17) docXml = docXml.replace(o.nameId, 'mallory@acme.com');
  if (mutation === 18) docXml = docXml.replace(signed.sigValue, signed.sigValue.slice(0, -8) + 'AAAAAAAA');
  if (mutation === 19) docXml = docXml.replace(/<ds:Signature[\s\S]*<\/ds:Signature>/, '');
  if (mutation === 20) cfg.jwk = keys[1 - keys.indexOf(key)].jwk;
  if (mutation === 21) cfg.seenAssertionIds = ['_a1'];
  if (mutation === 22) delete cfg.jwk;
  if (mutation === 23) { cfg.now = NOW + 90000; cfg.skewMs = pick([0, 1000000]); }
  const encoded = chance(0.6) ? b64(docXml) : docXml;
  const parsedExpected = saml.parseSamlResponse(encoded);
  const cfgForJs = { ...cfg, seenAssertionIds: cfg.seenAssertionIds ? new Set(cfg.seenAssertionIds) : undefined };
  add({ op: 'validate', response: encoded, config: cfg, e: norm(saml.validateSamlResponse(encoded, cfgForJs)) });
  if (i % 3 === 0) {
    const p = parsedExpected;
    add({ op: 'parse', response: encoded, e: norm(p.ok ? { ok: true, id: p.id, inResponseTo: p.inResponseTo, destination: p.destination, issueInstant: p.issueInstant, issuer: p.issuer, statusCode: p.statusCode, statusMessage: p.statusMessage, assertion: p.assertion } : { ok: false, error: p.error }) });
  }
}
for (const bad of ['', 'not xml at all ###', b64('<a/>'), b64('<samlp:Response xmlns:samlp="x"'), '<Other/>']) {
  const r = saml.parseSamlResponse(bad);
  add({ op: 'parse', response: bad, e: norm(r.ok ? { ok: true, id: r.id, inResponseTo: r.inResponseTo, destination: r.destination, issueInstant: r.issueInstant, issuer: r.issuer, statusCode: r.statusCode, statusMessage: r.statusMessage, assertion: r.assertion } : { ok: false, error: r.error }) });
}

// ---- requests, base64, ids, metadata, certificates, replay
for (let i = 0; i < 30; i++) {
  const o = {};
  if (chance(0.9)) o.id = pick(['_id1', 'abc']);
  if (chance(0.9)) o.issueInstant = '2026-06-01T12:00:00Z';
  if (chance(0.9)) o.destination = pick(['https://idp/sso', 'https://idp/sso?tenant=1', 'https://idp/a&b']);
  if (chance(0.9)) o.issuer = pick(['https://sp', 'sp & co']);
  if (chance(0.9)) o.acsUrl = pick(['https://sp/acs', 'https://sp/acs?a=1&b=2']);
  if (chance(0.5)) o.nameIdFormat = saml.NAMEID_EMAIL;
  if (chance(0.3)) o.forceAuthn = true;
  if (chance(0.5)) o.relayState = pick(['/dashboard', 'a b&c', 'x?y=z']);
  if (chance(0.4)) o.binding = saml.BINDING_POST;
  add({ op: 'authn', p: o, e: norm(saml.buildAuthnRequest(o)) });
}
add({ op: 'authn', p: {}, e: norm(saml.buildAuthnRequest({})) });
for (const t of ['', 'a', 'ab', 'abc', 'hello world', 'ünï', '\u0000\u00ff']) {
  const bytes = [...Buffer.from(t, 'utf8')];
  add({ op: 'b64', text: t, e: { std: saml.toBase64(bytes), stored: saml.deflateRawStored(bytes).map(String), id: saml.samlId(t) } });
}
{
  const big = Array.from({ length: 70000 }, (_, i) => (i * 7) & 255);
  const stored = saml.deflateRawStored(big);
  add({ op: 'stored', length: 70000, e: { total: String(stored.length), head: stored.slice(0, 8).map(String), second: stored.slice(5 + 65535, 5 + 65535 + 5).map(String) } });
}
for (let i = 0; i < 10; i++) {
  const o = { entityId: pick(['https://sp.example.com', 'sp & <x>']), acsUrl: pick(['https://sp/acs', 'https://sp/acs?a=1&b=2']) };
  if (chance(0.5)) o.sloUrl = 'https://sp/slo';
  if (chance(0.3)) o.nameIdFormat = 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent';
  if (chance(0.3)) o.wantAssertionsSigned = false;
  add({ op: 'metadata', p: o, e: norm(saml.buildSpMetadata(o)) });
}
add({ op: 'metadata', p: { entityId: 'x' }, e: norm(saml.buildSpMetadata({ entityId: 'x' })) });
{
  const md = (extra) => `<md:EntityDescriptor xmlns:md="${saml.NS.metadata}" xmlns:ds="${NS_D}" entityID="https://idp"><md:IDPSSODescriptor>`
    + `<md:KeyDescriptor><ds:KeyInfo><ds:X509Data><ds:X509Certificate>\n MIIB\n abc= \n</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor>${extra}</md:IDPSSODescriptor></md:EntityDescriptor>`;
  for (const extra of [
    `<md:SingleSignOnService Binding="${saml.BINDING_POST}" Location="https://idp/post"/><md:SingleSignOnService Binding="${saml.BINDING_REDIRECT}" Location="https://idp/redir"/>`,
    `<md:SingleSignOnService Binding="${saml.BINDING_POST}" Location="https://idp/post"/>`,
    '', `<md:SingleSignOnService Binding="other" Location="https://idp/x"/>`,
  ]) add({ op: 'idp', xml: md(extra), e: norm(saml.parseIdpMetadata(md(extra))) });
  add({ op: 'idp', xml: '<a/>', e: norm(saml.parseIdpMetadata('<a/>')) });
  add({ op: 'idp', xml: '<a', e: norm(saml.parseIdpMetadata('<a')) });
}
function lenBytes(n) { return n < 128 ? [n] : n < 256 ? [0x81, n] : [0x82, n >> 8, n & 255]; }
function derKey(modLen, lead00, expBytes) {
  const modulus = [...(lead00 ? [0] : []), ...Array.from({ length: modLen }, (_, i) => 0x80 | ((i * 37) & 0x7f))];
  const m = [0x02, ...lenBytes(modulus.length), ...modulus];
  const e = [0x02, ...lenBytes(expBytes.length), ...expBytes];
  const seq = [0x30, ...lenBytes(m.length + e.length), ...m, ...e];
  const bit = [0x03, ...lenBytes(seq.length + 1), 0x00, ...seq];
  return [0x30, 0x82, 0x01, 0x00, 0x02, 0x01, 0x01, 0x04, 0x03, 0x01, 0x02, 0x03, ...bit, 0x05, 0x00];
}
for (let i = 0; i < 14; i++) {
  const modLen = pick([128, 256, 64, 63, 32, 129]);
  const der = derKey(modLen, chance(0.5), pick([[1, 0, 1], [3], [1, 0, 1, 0]]));
  const b = Buffer.from(der).toString('base64');
  const pem = chance(0.5) ? `-----BEGIN CERTIFICATE-----\n${b.match(/.{1,64}/g).join('\n')}\n-----END CERTIFICATE-----\n` : b;
  add({ op: 'cert', cert: pem, e: norm(saml.certificateToJwk(pem)) });
}
add({ op: 'cert', cert: 'AAAA', e: norm(saml.certificateToJwk('AAAA')) });
for (const k of keys) {
  const b = k.der.toString('base64');
  add({ op: 'cert', cert: b, e: norm(saml.certificateToJwk(b)) });
}
for (let i = 0; i < 6; i++) {
  let t = NOW;
  const cache = saml.createReplayCache({ now: () => t });
  const steps = [];
  const results = [];
  for (let k = 0; k < 8; k++) {
    t += int(5) * 120000;
    const kind = pick(['has', 'remember', 'size']);
    const id = pick(['_a', '_b', '_c']);
    const expires = chance(0.3) ? undefined : t + pick([60000, 300000, 900000]);
    steps.push({ t, kind, id, expires: expires === undefined ? 0 : expires });
    if (kind === 'has') results.push(String(cache.has(id)));
    else if (kind === 'size') results.push(String(cache.size));
    else { cache.remember(id, expires); results.push('-'); }
  }
  add({ op: 'replay', steps, e: results });
}

const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
const size = 4;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'saml_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_identity_saml/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
const tally = {};
for (const c of cases) if (c.op === 'validate') { const k = c.e.ok ? 'ok' : c.e.error.split(':')[0]; tally[k] = (tally[k] || 0) + 1; }
console.log(tally);
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_identity_saml`);
