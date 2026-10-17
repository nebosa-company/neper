// Storage, DOMParser / XMLSerializer, <template>, structuredClone, channels, observers and other small platform objects.

// --- Storage

function Storage() { throw new TypeError('Illegal constructor'); }
iface('Storage', Storage, null);
function stSlot(o) { const s = slotOf(o); if (!s || !s.isStorage) illegal(); return s; }
function makeStorage(areaName) {
  const state = { isStorage: true, map: new Map(), area: areaName };
  const sto = legacyObject(Storage.prototype, {
    length: () => state.map.size,
    item: i => null,
    named: name => (state.map.has(name) ? state.map.get(name) : undefined),
    names: () => Array.from(state.map.keys()),
    namedSetter: (name, value) => storageSet(sto, name, toDOMString(value)),
    deleter: name => storageRemove(sto, name),
    enumerableNamed: true
  }, state);
  state.self = sto;
  return sto;
}
function storageSet(st, key, value) {
  const s = slotOf(st);
  const old = s.map.has(key) ? s.map.get(key) : null;
  if (old === value) return;
  if (storageQuota(s, key, value) > 5 * 1024 * 1024) throw domError('QuotaExceededError', 'The quota has been exceeded.');
  s.map.set(key, value);
  fireStorageEvent(s, key, old, value);
}
function storageQuota(s, key, value) {
  let total = key.length + value.length;
  for (const [k, v] of s.map) if (k !== key) total += k.length + v.length;
  return total * 2;
}
function storageRemove(st, key) {
  const s = slotOf(st);
  if (!s.map.has(key)) return;
  const old = s.map.get(key);
  s.map.delete(key);
  fireStorageEvent(s, key, old, null);
}
function fireStorageEvent(s, key, oldValue, newValue) { /* other windows of the origin would hear this; there are none */ }
operations(Storage.prototype, {
  key(index) { const s = stSlot(this); required(arguments, 1, 'key'); const keys = Array.from(s.map.keys()); const i = toUnsignedLong(index); return i < keys.length ? keys[i] : null; },
  getItem(key) { const s = stSlot(this); required(arguments, 1, 'getItem'); const k = toDOMString(key); return s.map.has(k) ? s.map.get(k) : null; },
  setItem(key, value) { stSlot(this); required(arguments, 2, 'setItem'); storageSet(this, toDOMString(key), toDOMString(value)); },
  removeItem(key) { stSlot(this); required(arguments, 1, 'removeItem'); storageRemove(this, toDOMString(key)); },
  clear() { const s = stSlot(this); if (s.map.size === 0) return; s.map.clear(); fireStorageEvent(s, null, null, null); }
});
attributes(Storage.prototype, { length: { get() { return stSlot(this).map.size; } } });
const localStorageObject = makeStorage('local'), sessionStorageObject = makeStorage('session');
defineProperty(global, 'localStorage', { get() { return localStorageObject; }, enumerable: true, configurable: true });
defineProperty(global, 'sessionStorage', { get() { return sessionStorageObject; }, enumerable: true, configurable: true });

// --- XML parsing (a namespace-aware XML 1.0 reader building DOM nodes)

function xmlError(msg, line) { const e = new Error(msg); e.xmlLine = line; return e; }
const xmlEntities = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };
function parseXML(doc, text, entities0) {
  let pos = 0, line = 1;
  const n = text.length;
  const nsStack = [{ xml: XML_NS, xmlns: XMLNS_NS }];
  let defaultNS = [null];
  const customEntities = Object.assign(Object.create(null), entities0 || {});
  function fail(msg) { throw xmlError(msg, line); }
  function isSpace(c) { return c === ' ' || c === '\t' || c === '\n' || c === '\r'; }
  function skipSpace() { while (pos < n && isSpace(text[pos])) { if (text[pos] === '\n') line++; pos++; } }
  function readName() {
    const start = pos;
    while (pos < n && !isSpace(text[pos]) && '>/=<?!&"\''.indexOf(text[pos]) < 0) pos++;
    if (pos === start) fail('expected a name');
    const name = text.slice(start, pos);
    if (!isValidName(name)) fail('invalid name ' + name);
    return name;
  }
  function decodeRefs(s, inAttr) {
    if (s.indexOf('&') < 0) return s;
    return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[^;&\s]*);/g, (m, body) => {
      if (body[0] === '#') {
        const cp = body[1] === 'x' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
        if (!(cp === 9 || cp === 10 || cp === 13 || (cp >= 0x20 && cp <= 0xD7FF) || (cp >= 0xE000 && cp <= 0xFFFD) || (cp >= 0x10000 && cp <= 0x10FFFF))) fail('invalid character reference');
        return String.fromCodePoint(cp);
      }
      if (hasOwn.call(xmlEntities, body)) return xmlEntities[body];
      if (body in customEntities) return customEntities[body];
      fail('unknown entity &' + body + ';');
    });
  }
  function lookupNS(prefix) {
    for (let i = nsStack.length - 1; i >= 0; i--) if (prefix in nsStack[i]) return nsStack[i][prefix];
    return undefined;
  }
  if (text.charCodeAt(0) === 0xFEFF) pos = 1;
  let root = null;
  let parent = doc;
  const open = [];
  if (text.startsWith('<?xml', pos) && /\s/.test(text[pos + 5] || '')) {
    const end = text.indexOf('?>', pos);
    if (end < 0) fail('unterminated XML declaration');
    pos = end + 2;
  }
  while (pos < n) {
    const c = text[pos];
    if (c === '<') {
      if (text.startsWith('<!--', pos)) {
        const end = text.indexOf('-->', pos + 4);
        if (end < 0) fail('unterminated comment');
        const body = text.slice(pos + 4, end);
        if (body.indexOf('--') >= 0 || body.endsWith('-')) fail('-- is not allowed in a comment');
        appendNodeSimple(parent, createCommentNode(doc, body));
        for (const ch of body) if (ch === '\n') line++;
        pos = end + 3;
      } else if (text.startsWith('<![CDATA[', pos)) {
        if (parent === doc) fail('CDATA outside the root element');
        const end = text.indexOf(']]>', pos);
        if (end < 0) fail('unterminated CDATA section');
        appendNodeSimple(parent, createCDATA(doc, text.slice(pos + 9, end)));
        for (const ch of text.slice(pos, end)) if (ch === '\n') line++;
        pos = end + 3;
      } else if (text.startsWith('<!DOCTYPE', pos)) {
        if (root !== null || doctypeOf(doc) !== null) fail('misplaced DOCTYPE');
        pos += 9;
        skipSpace();
        const name = readName();
        skipSpace();
        let publicId = '', systemId = '';
        const readLiteral = () => { const q = text[pos]; if (q !== '"' && q !== "'") fail('expected a quoted literal'); const end = text.indexOf(q, pos + 1); if (end < 0) fail('unterminated literal'); const v = text.slice(pos + 1, end); pos = end + 1; return v; };
        if (text.startsWith('PUBLIC', pos)) { pos += 6; skipSpace(); publicId = readLiteral(); skipSpace(); systemId = readLiteral(); skipSpace(); }
        else if (text.startsWith('SYSTEM', pos)) { pos += 6; skipSpace(); systemId = readLiteral(); skipSpace(); }
        if (text[pos] === '[') {
          const end = text.indexOf(']', pos);
          if (end < 0) fail('unterminated internal subset');
          const subset = text.slice(pos + 1, end);
          for (const m of subset.matchAll(/<!ENTITY\s+([^\s%]+)\s+(?:"([^"]*)"|'([^']*)')\s*>/g)) customEntities[m[1]] = m[2] !== undefined ? m[2] : m[3];
          pos = end + 1;
          skipSpace();
        }
        if (text[pos] !== '>') fail('expected > at the end of the DOCTYPE');
        pos++;
        appendNodeSimple(doc, createDoctypeNode(doc, name, publicId, systemId));
      } else if (text.startsWith('<?', pos)) {
        const end = text.indexOf('?>', pos);
        if (end < 0) fail('unterminated processing instruction');
        const body = text.slice(pos + 2, end);
        const m = /^([^\s?]+)(?:\s+([\s\S]*))?$/.exec(body);
        if (!m || !isValidName(m[1]) || asciiLowercase(m[1]) === 'xml') fail('invalid processing instruction');
        appendNodeSimple(parent, createPI(doc, m[1], m[2] || ''));
        for (const ch of body) if (ch === '\n') line++;
        pos = end + 2;
      } else if (text[pos + 1] === '/') {
        pos += 2;
        const name = readName();
        skipSpace();
        if (text[pos] !== '>') fail('malformed end tag');
        pos++;
        const top = open.pop();
        if (!top || top.name !== name) fail('mismatched end tag </' + name + '>');
        nsStack.pop(); defaultNS.pop();
        parent = parentNode(parent) || doc;
        if (open.length === 0) parent = doc;
      } else {
        pos++;
        const name = readName();
        const attrs = [];
        while (true) {
          skipSpace();
          if (text[pos] === '>' || text[pos] === '/' || pos >= n) break;
          const an = readName();
          skipSpace();
          if (text[pos] !== '=') fail('expected = after attribute ' + an);
          pos++;
          skipSpace();
          const q = text[pos];
          if (q !== '"' && q !== "'") fail('expected a quoted attribute value');
          const end = text.indexOf(q, pos + 1);
          if (end < 0) fail('unterminated attribute value');
          const raw = text.slice(pos + 1, end);
          if (raw.indexOf('<') >= 0) fail('< in an attribute value');
          for (const ch of raw) if (ch === '\n') line++;
          attrs.push([an, decodeRefs(raw.replace(/[\t\n\r]/g, ' '), true)]);
          pos = end + 1;
          if (attrs.filter(a => a[0] === an).length > 1) fail('duplicate attribute ' + an);
        }
        let selfClosing = false;
        if (text[pos] === '/') { selfClosing = true; pos++; }
        if (text[pos] !== '>') fail('malformed start tag');
        pos++;
        const nsDecl = {};
        let defNS = defaultNS[defaultNS.length - 1];
        for (const [an, av] of attrs) {
          if (an === 'xmlns') defNS = av === '' ? null : av;
          else if (an.startsWith('xmlns:')) nsDecl[an.slice(6)] = av === '' ? null : av;
        }
        nsStack.push(nsDecl); defaultNS.push(defNS);
        const colon = name.indexOf(':');
        const prefix = colon > 0 ? name.slice(0, colon) : null, local = colon > 0 ? name.slice(colon + 1) : name;
        let ns = prefix === null ? defNS : (lookupNS(prefix) === undefined ? fail('unbound prefix ' + prefix) : lookupNS(prefix));
        if (parent === doc && root !== null) fail('more than one root element');
        const el = createElementWithDefinition(doc, local, ns === undefined ? null : ns, prefix, null, false);
        for (const [an, av] of attrs) {
          const ac = an.indexOf(':');
          let ap = null, al = an, ans = null;
          if (an === 'xmlns') { ans = XMLNS_NS; }
          else if (ac > 0) {
            ap = an.slice(0, ac); al = an.slice(ac + 1);
            ans = ap === 'xmlns' ? XMLNS_NS : (lookupNS(ap) === undefined ? fail('unbound prefix ' + ap) : lookupNS(ap));
          }
          appendAttr(newAttr(doc, al, ans === undefined ? null : ans, ap, av), el);
        }
        appendNodeSimple(parent, el);
        if (root === null) root = el;
        if (selfClosing) { nsStack.pop(); defaultNS.pop(); }
        else { open.push({ name }); parent = el; }
      }
    } else {
      const end = text.indexOf('<', pos);
      const raw = text.slice(pos, end < 0 ? n : end);
      if (parent === doc) {
        if (raw.trim() !== '') fail('text outside the root element');
      } else {
        if (raw.indexOf(']]>') >= 0) fail(']]> in character data');
        appendNodeSimple(parent, createTextNode(doc, decodeRefs(raw.replace(/\r\n?/g, '\n'), false)));
      }
      for (const ch of raw) if (ch === '\n') line++;
      pos = end < 0 ? n : end;
    }
  }
  if (open.length) fail('unclosed element ' + open[open.length - 1].name);
  if (root === null) fail('no root element');
}

// --- DOMParser and XMLSerializer

function DOMParser() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DOMParser': Please use the 'new' operator");
  setSlot(this, { isDOMParser: true });
}
iface('DOMParser', DOMParser, null);
// ponytail: markup goes into <body> only (no head/doctype detection); add a native document parse when a test needs it.
function parseHTMLDocument(doc, markup) {
  const mk = name => createElementWithDefinition(doc, name, HTML_NS, null, null, false);
  const html = mk('html'), head = mk('head'), body = mk('body');
  appendNodeSimple(doc, html); appendNodeSimple(html, head); appendNodeSimple(html, body);
  body.innerHTML = markup;
}
operations(DOMParser.prototype, {
  parseFromString(string, type) {
    const s = slotOf(this);
    if (!s || !s.isDOMParser) illegal();
    required(arguments, 2, 'parseFromString');
    const text = toDOMString(string);
    const t = toDOMString(type);
    if (['text/html', 'text/xml', 'application/xml', 'application/xhtml+xml', 'image/svg+xml'].indexOf(t) < 0) throw new TypeError("Failed to execute 'parseFromString' on 'DOMParser': The provided value '" + t + "' is not a valid enum value of type SupportedType.");
    if (t === 'text/html') {
      const doc = newDocument(false);
      slotOf(doc).url = slotOf(mainDocument).url;
      slotOf(doc).browsingContext = false;
      parseHTMLDocument(doc, text);
      return doc;
    }
    const doc = newDocument(true);
    slotOf(doc).contentType = t;
    slotOf(doc).url = slotOf(mainDocument).url;
    try { parseXML(doc, text); } catch (e) {
      if (!e.xmlLine) throw e;
      for (const k of childrenOf(doc)) removeNode(k, true);
      const err = createElementWithDefinition(doc, 'parsererror', 'http://www.mozilla.org/newlayout/xml/parsererror.xml', null, null, false);
      appendNodeSimple(err, createTextNode(doc, e.message));
      appendNodeSimple(doc, err);
    }
    return doc;
  }
});

function XMLSerializer() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'XMLSerializer': Please use the 'new' operator");
  setSlot(this, { isSerializer: true });
}
iface('XMLSerializer', XMLSerializer, null);
function escapeXMLText(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function escapeXMLAttr(s) { return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\t/g, '&#9;').replace(/\n/g, '&#10;').replace(/\r/g, '&#13;'); }
const voidHTML = ['area', 'base', 'basefont', 'bgsound', 'br', 'col', 'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'menuitem', 'meta', 'param', 'source', 'track', 'wbr'];
function serializeXML(node, requireWellFormed, inheritedNS, prefixMap, counter) {
  const s = slotOf(node);
  switch (s.nodeType) {
    case ELEMENT_NODE: {
      const ns = s.namespaceURI;
      let out = '<';
      let map = Object.assign(Object.create(null), prefixMap);
      let ignoreNS = false;
      let nsDecls = [];
      let localDefault = inheritedNS;
      let prefix = s.prefix;
      const attrList = attrsOf(node);
      // namespace declarations that already exist on the element
      let locallyDeclared = Object.create(null);
      for (const a of attrList) { const as = slotOf(a); if (as.namespaceURI === XMLNS_NS) { if (as.prefix === null) { localDefault = as.value; } else locallyDeclared[as.localName] = as.value; } }
      let qualified;
      if (ns === inheritedNS) {
        qualified = s.prefix === null ? s.localName : s.prefix + ':' + s.localName;
        if (s.prefix === null && ns !== null) ignoreNS = true;
      } else if (ns === null) {
        qualified = s.localName;
        nsDecls.push(['', '']);
        localDefault = null;
      } else {
        const found = Object.keys(map).find(p => map[p] === ns && p !== '' && !(p in locallyDeclared && locallyDeclared[p] !== ns));
        if (found !== undefined && s.prefix !== null && found === s.prefix) qualified = s.prefix + ':' + s.localName;
        else if (found !== undefined) qualified = found + ':' + s.localName;
        else if (s.prefix !== null && !(s.prefix in map && map[s.prefix] !== ns)) { qualified = s.prefix + ':' + s.localName; nsDecls.push([s.prefix, ns]); map[s.prefix] = ns; }
        else if (s.prefix === null || s.prefix in map) { qualified = s.localName; nsDecls.push(['', ns]); localDefault = ns; }
        else { qualified = s.prefix + ':' + s.localName; nsDecls.push([s.prefix, ns]); map[s.prefix] = ns; }
        if (found === undefined && s.prefix === null) localDefault = ns;
      }
      out += qualified;
      let attrsOut = '';
      for (const a of attrList) {
        const as = slotOf(a);
        if (as.namespaceURI === XMLNS_NS) {
          if (as.prefix === null) { if (ignoreNS || (as.value === localDefault && false)) continue; attrsOut += ' xmlns="' + escapeXMLAttr(as.value) + '"'; if (as.value !== inheritedNS) localDefault = as.value; }
          else { attrsOut += ' xmlns:' + as.localName + '="' + escapeXMLAttr(as.value) + '"'; map[as.localName] = as.value; }
          continue;
        }
        let aq = as.localName;
        if (as.namespaceURI !== null) {
          let ap = Object.keys(map).find(p => map[p] === as.namespaceURI && p !== '');
          if (ap === undefined) {
            ap = as.prefix !== null && !(as.prefix in map) ? as.prefix : 'ns' + (++counter.n);
            nsDecls.push([ap, as.namespaceURI]); map[ap] = as.namespaceURI;
          }
          aq = ap + ':' + as.localName;
        }
        attrsOut += ' ' + aq + '="' + escapeXMLAttr(as.value) + '"';
      }
      for (const [p, v] of nsDecls) {
        if (p === '') out += ' xmlns="' + escapeXMLAttr(v) + '"';
        else out += ' xmlns:' + p + '="' + escapeXMLAttr(v) + '"';
      }
      out += attrsOut;
      const kids = childrenOf(node);
      if (ns === HTML_NS && kids.length === 0 && voidHTML.indexOf(s.localName) >= 0) return out + ' />';
      if (kids.length === 0 && !(ns === HTML_NS)) return out + '/>';
      out += '>';
      for (const k of kids) out += serializeXML(k, requireWellFormed, ns === inheritedNS && !nsDecls.length ? inheritedNS : localDefault, map, counter);
      return out + '</' + qualified + '>';
    }
    case DOCUMENT_NODE: case DOCUMENT_FRAGMENT_NODE: {
      let out = '';
      for (const k of childrenOf(node)) out += serializeXML(k, requireWellFormed, inheritedNS, prefixMap, counter);
      return out;
    }
    case DOCUMENT_TYPE_NODE: return '<!DOCTYPE ' + s.name + (s.publicId !== '' ? ' PUBLIC "' + s.publicId + '"' + (s.systemId !== '' ? ' "' + s.systemId + '"' : '') : (s.systemId !== '' ? ' SYSTEM "' + s.systemId + '"' : '')) + '>';
    case TEXT_NODE: return escapeXMLText(N.value(s.id));
    case CDATA_SECTION_NODE: return '<![CDATA[' + N.value(s.id) + ']]>';
    case COMMENT_NODE: { const v = N.value(s.id); if (requireWellFormed && (v.indexOf('--') >= 0 || v.endsWith('-'))) throw domError('InvalidStateError', 'The comment is not well-formed'); return '<!--' + v + '-->'; }
    case PROCESSING_INSTRUCTION_NODE: return '<?' + s.target + (N.value(s.id) !== '' ? ' ' + N.value(s.id) : '') + '?>';
    case ATTRIBUTE_NODE: return s.value;
  }
  return '';
}
operations(XMLSerializer.prototype, {
  serializeToString(root) {
    const s = slotOf(this);
    if (!s || !s.isSerializer) illegal();
    required(arguments, 1, 'serializeToString');
    if (!isNode(root)) throw new TypeError("Failed to execute 'serializeToString' on 'XMLSerializer': parameter 1 is not of type 'Node'.");
    return serializeXML(root, false, null, Object.assign(Object.create(null), { xml: XML_NS }), { n: 0 });
  }
});

// --- template contents

const templateContents = new WeakMap();
function templateContent(tpl) {
  let frag = apply(slotGet, templateContents, [tpl]);
  if (frag === undefined) {
    const doc = slotOf(tpl).doc;
    const ds = slotOf(doc);
    if (!ds.templateDoc) { ds.templateDoc = newDocument(false); slotOf(ds.templateDoc).browsingContext = false; slotOf(ds.templateDoc).templateOwner = true; }
    frag = createFragmentNode(ds.templateDoc);
    // Children the parser put under the element become the content.
    for (const c of childrenOf(tpl)) { N.remove(idOf(c)); slotOf(c).doc = ds.templateDoc; appendNodeSimple(frag, c); }
    apply(slotSet, templateContents, [tpl, frag]);
  }
  return frag;
}
attributes(HTMLTemplateElement.prototype, {
  content: { get() { elSlot(this); return templateContent(this); } }
});
cloningSteps = function (node, copy, document, cloneChildren) {
  const s = slotOf(node);
  if (s.nodeType === ELEMENT_NODE && s.localName === 'template' && s.namespaceURI === HTML_NS && cloneChildren) {
    const src = templateContent(node), dst = templateContent(copy);
    for (const c of childrenOf(src)) appendNodeSimple(dst, cloneNode(c, slotOf(dst).doc, true));
  }
};

// --- structuredClone

structuredCloneImpl = function (value, options) {
  const memory = new Map();
  function clone(v) {
    if (typeof v === 'symbol') throw domError('DataCloneError', 'Symbol() could not be cloned.');
    if (typeof v === 'function') throw domError('DataCloneError', 'function could not be cloned.');
    if (!isObject(v)) return v;
    if (memory.has(v)) return memory.get(v);
    let out;
    if (v instanceof Boolean) out = new Boolean(v.valueOf());
    else if (v instanceof Number) out = new Number(v.valueOf());
    else if (v instanceof String) out = new String(v.valueOf());
    else if (v instanceof Date) out = new Date(v.getTime());
    else if (v instanceof RegExp) out = new RegExp(v.source, v.flags);
    else if (v instanceof ArrayBuffer) { out = v.slice(0); }
    else if (ArrayBuffer.isView(v)) { const buf = clone(v.buffer); out = v instanceof DataView ? new DataView(buf, v.byteOffset, v.byteLength) : new v.constructor(buf, v.byteOffset, v.length); }
    else if (v instanceof Map) { out = new Map(); memory.set(v, out); for (const [k, x] of v) out.set(clone(k), clone(x)); return out; }
    else if (v instanceof Set) { out = new Set(); memory.set(v, out); for (const x of v) out.add(clone(x)); return out; }
    else if (v instanceof Error) {
      out = new (hasOwn.call(global, v.name) && typeof global[v.name] === 'function' ? global[v.name] : Error)(v.message);
      memory.set(v, out);
      if ('cause' in v) out.cause = clone(v.cause);
      return out;
    } else if (isObject(v) && slotOf(v) && (slotOf(v).isNode || slotOf(v).isTarget || slotOf(v).isBlob === undefined && slotOf(v).isPlatform)) {
      if (slotOf(v).isBlob) { out = v; }
      else throw domError('DataCloneError', 'An object could not be cloned.');
    } else if (slotOf(v) && slotOf(v).isBlob) out = v;
    else if (Array.isArray(v)) { out = new Array(v.length); memory.set(v, out); for (const k of Object.keys(v)) out[k] = clone(v[k]); return out; }
    else {
      if (slotOf(v)) throw domError('DataCloneError', 'An object could not be cloned.');
      out = {};
      memory.set(v, out);
      for (const k of Object.keys(v)) out[k] = clone(v[k]);
      return out;
    }
    memory.set(v, out);
    return out;
  }
  return clone(value);
};

// --- channels

function MessagePort() { throw new TypeError('Illegal constructor'); }
iface('MessagePort', MessagePort, EventTarget);
defineHandlerAttrs(MessagePort.prototype, ['message', 'messageerror']);
function portSlot(o) { const s = slotOf(o); if (!s || !s.isPort) illegal(); return s; }
operations(MessagePort.prototype, {
  postMessage(message, transfer = undefined) {
    const s = portSlot(this);
    required(arguments, 1, 'postMessage');
    const data = structuredCloneImpl(message);
    const peer = s.peer;
    if (peer === null || s.closed) return;
    scheduleTimer(() => {
      const ps = slotOf(peer);
      if (!ps.started && !ps.enabled) { ps.queue.push(data); return; }
      const ev = new MessageEvent('message', { data, origin: '' });
      slotOf(ev).isTrusted = true;
      dispatch(ev, peer);
    }, 0, false, []);
  },
  start() { const s = portSlot(this); s.started = true; const q = s.queue.splice(0); for (const d of q) { const ev = new MessageEvent('message', { data: d }); slotOf(ev).isTrusted = true; dispatch(ev, this); } },
  close() { const s = portSlot(this); s.closed = true; if (s.peer) slotOf(s.peer).closed = true; }
});
function newPort() { const p = create(MessagePort.prototype); setSlot(p, { listeners: [], isTarget: true, isPort: true, peer: null, queue: [], started: false, enabled: false, closed: false }); return p; }
const portOnMessage = eventHandlerAttribute('message');
defineProperty(MessagePort.prototype, 'onmessage', { get: portOnMessage.get, set(v) { portOnMessage.set.call(this, v); const s = portSlot(this); s.enabled = true; this.start(); }, enumerable: true, configurable: true });
function MessageChannel() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'MessageChannel': Please use the 'new' operator");
  const a = newPort(), b = newPort();
  slotOf(a).peer = b; slotOf(b).peer = a;
  setSlot(this, { isChannel: true, port1: a, port2: b });
}
iface('MessageChannel', MessageChannel, null);
attributes(MessageChannel.prototype, {
  port1: { get() { const s = slotOf(this); if (!s || !s.isChannel) illegal(); return s.port1; } },
  port2: { get() { const s = slotOf(this); if (!s || !s.isChannel) illegal(); return s.port2; } }
});
const broadcastChannels = new Map();
function BroadcastChannel(name) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'BroadcastChannel': Please use the 'new' operator");
  required(arguments, 1, 'BroadcastChannel');
  const n = toDOMString(name);
  setSlot(this, { listeners: [], isTarget: true, isBC: true, name: n, closed: false });
  if (!broadcastChannels.has(n)) broadcastChannels.set(n, []);
  broadcastChannels.get(n).push(this);
}
iface('BroadcastChannel', BroadcastChannel, EventTarget);
defineHandlerAttrs(BroadcastChannel.prototype, ['message', 'messageerror']);
attributes(BroadcastChannel.prototype, { name: { get() { const s = slotOf(this); if (!s || !s.isBC) illegal(); return s.name; } } });
operations(BroadcastChannel.prototype, {
  postMessage(message) {
    const s = slotOf(this);
    if (!s || !s.isBC) illegal();
    required(arguments, 1, 'postMessage');
    if (s.closed) throw domError('InvalidStateError', 'The channel is closed');
    const data = structuredCloneImpl(message);
    for (const other of broadcastChannels.get(s.name)) {
      if (other === this || slotOf(other).closed) continue;
      scheduleTimer(() => { const ev = new MessageEvent('message', { data }); slotOf(ev).isTrusted = true; dispatch(ev, other); }, 0, false, []);
    }
  },
  close() { const s = slotOf(this); if (!s || !s.isBC) illegal(); s.closed = true; }
});

// --- observers that need layout

function ResizeObserver(callback) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'ResizeObserver': Please use the 'new' operator");
  required(arguments, 1, 'ResizeObserver');
  if (typeof callback !== 'function') throw new TypeError("Failed to construct 'ResizeObserver': The callback provided as parameter 1 is not a function.");
  setSlot(this, { isRO: true, callback, targets: new Map() });
}
iface('ResizeObserver', ResizeObserver, null);
operations(ResizeObserver.prototype, {
  observe(target) {
    const s = slotOf(this);
    if (!s || !s.isRO) illegal();
    required(arguments, 1, 'observe');
    if (!isNode(target) || nodeType(target) !== ELEMENT_NODE) throw new TypeError("Failed to execute 'observe' on 'ResizeObserver': parameter 1 is not of type 'Element'.");
    if (s.targets.has(target)) return;
    s.targets.set(target, null);
    scheduleTimer(() => runResizeObserver(this), 0, false, []);
  },
  unobserve(target) { const s = slotOf(this); if (!s || !s.isRO) illegal(); s.targets.delete(target); },
  disconnect() { const s = slotOf(this); if (!s || !s.isRO) illegal(); s.targets.clear(); }
});
function runResizeObserver(ro) {
  const s = slotOf(ro);
  const entries = [];
  for (const [t, last] of s.targets) {
    const g = N.geom(idOf(t), 2);
    const size = g === null ? [0, 0] : [g[2], g[3]];
    if (last === null || last[0] !== size[0] || last[1] !== size[1]) {
      s.targets.set(t, size);
      const rect = new DOMRect(0, 0, size[0], size[1]);
      entries.push({ target: t, contentRect: rect, contentBoxSize: [{ inlineSize: size[0], blockSize: size[1] }], borderBoxSize: [{ inlineSize: size[0], blockSize: size[1] }], devicePixelContentBoxSize: [{ inlineSize: size[0], blockSize: size[1] }] });
    }
  }
  if (entries.length) { try { s.callback.call(ro, entries, ro); } catch (e) { reportException(e); } }
}
function IntersectionObserver(callback, options = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'IntersectionObserver': Please use the 'new' operator");
  required(arguments, 1, 'IntersectionObserver');
  if (typeof callback !== 'function') throw new TypeError("Failed to construct 'IntersectionObserver': The callback provided as parameter 1 is not a function.");
  const o = options || {};
  setSlot(this, { isIO: true, callback, targets: new Map(), root: o.root === undefined ? null : o.root, rootMargin: o.rootMargin === undefined ? '0px' : String(o.rootMargin), thresholds: o.threshold === undefined ? [0] : [].concat(o.threshold).map(Number).sort((a, b) => a - b), pending: [] });
}
iface('IntersectionObserver', IntersectionObserver, null);
attributes(IntersectionObserver.prototype, {
  root: { get() { const s = slotOf(this); if (!s || !s.isIO) illegal(); return s.root; } },
  rootMargin: { get() { const s = slotOf(this); if (!s || !s.isIO) illegal(); return s.rootMargin; } },
  thresholds: { get() { const s = slotOf(this); if (!s || !s.isIO) illegal(); return s.thresholds; } }
});
function intersectionEntry(io, target) {
  const s = slotOf(io);
  const g = N.geom(idOf(target), 0), vp = N.geom(N.root(), 4);
  const rect = g === null ? new DOMRect(0, 0, 0, 0) : new DOMRect(g[0], g[1], g[2], g[3]);
  let root = new DOMRect(0, 0, vp ? vp[0] : 800, vp ? vp[1] : 600);
  if (s.root !== null) { const rg = N.geom(idOf(s.root), 0); if (rg) root = new DOMRect(rg[0], rg[1], rg[2], rg[3]); }
  const x1 = Math.max(rect.left, root.left), y1 = Math.max(rect.top, root.top), x2 = Math.min(rect.right, root.right), y2 = Math.min(rect.bottom, root.bottom);
  const w = Math.max(0, x2 - x1), h = Math.max(0, y2 - y1);
  const area = rect.width * rect.height;
  const ratio = g === null ? 0 : (area === 0 ? (x2 >= x1 && y2 >= y1 ? 1 : 0) : (w * h) / area);
  return { time: N.now(), rootBounds: root, boundingClientRect: rect, intersectionRect: new DOMRect(x1, y1, w, h), isIntersecting: g !== null && x2 >= x1 && y2 >= y1 && (w > 0 || h > 0 || area === 0), intersectionRatio: ratio, target };
}
function runIntersectionObserver(io) {
  const s = slotOf(io);
  const entries = [];
  for (const [t, last] of s.targets) {
    const e = intersectionEntry(io, t);
    let idx = 0;
    for (let i = 0; i < s.thresholds.length; i++) if (e.intersectionRatio >= s.thresholds[i] && (e.isIntersecting || s.thresholds[i] === 0 && false)) idx = i + 1;
    if (!e.isIntersecting) idx = 0;
    const state = e.isIntersecting ? idx : -1;
    if (last === undefined || last !== state) { s.targets.set(t, state); entries.push(e); }
  }
  if (entries.length) { try { s.callback.call(io, entries, io); } catch (er) { reportException(er); } }
}
operations(IntersectionObserver.prototype, {
  observe(target) {
    const s = slotOf(this);
    if (!s || !s.isIO) illegal();
    required(arguments, 1, 'observe');
    if (!isNode(target) || nodeType(target) !== ELEMENT_NODE) throw new TypeError("Failed to execute 'observe' on 'IntersectionObserver': parameter 1 is not of type 'Element'.");
    if (s.targets.has(target)) return;
    s.targets.set(target, undefined);
    scheduleTimer(() => runIntersectionObserver(this), 0, false, []);
  },
  unobserve(target) { const s = slotOf(this); if (!s || !s.isIO) illegal(); s.targets.delete(target); },
  disconnect() { const s = slotOf(this); if (!s || !s.isIO) illegal(); s.targets.clear(); },
  takeRecords() { const s = slotOf(this); if (!s || !s.isIO) illegal(); return []; }
});
function PerformanceObserver(callback) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'PerformanceObserver': Please use the 'new' operator");
  required(arguments, 1, 'PerformanceObserver');
  if (typeof callback !== 'function') throw new TypeError("Failed to construct 'PerformanceObserver': The callback provided as parameter 1 is not a function.");
  setSlot(this, { isPO: true, callback });
}
iface('PerformanceObserver', PerformanceObserver, null);
operations(PerformanceObserver.prototype, { observe() {}, disconnect() {}, takeRecords() { return []; } });
defineProperty(PerformanceObserver, 'supportedEntryTypes', { value: [], enumerable: true, configurable: true });
defineProperty(global, 'requestIdleCallback', { value: function requestIdleCallback(callback, options = undefined) { required(arguments, 1, 'requestIdleCallback'); const id = ++timerSeq; insertTimer({ id, fn: () => callback({ didTimeout: false, timeRemaining() { return 50; } }), due: N.now() + 1, delay: 0, repeat: false, args: [], seq: id }); return id; }, writable: true, enumerable: true, configurable: true });
defineProperty(global, 'cancelIdleCallback', { value: function cancelIdleCallback(id) { clearTimer(id); }, writable: true, enumerable: true, configurable: true });

// --- matchMedia: width/height features only (ponytail: no full media query grammar; route to the style engine's matcher if needed)
function mediaMatches(query, w, h) {
  return query.split(',').some(q => {
    q = q.trim().toLowerCase();
    if (q === '' ) return true;
    if (/^not\b/.test(q)) return false;
    const type = /^(?:only\s+)?(\w+)/.exec(q);
    if (type && ['screen', 'print', 'speech'].indexOf(type[1]) >= 0 && type[1] !== 'screen') return false;
    for (const m of q.matchAll(/\(\s*(min-|max-)?(width|height)\s*:\s*([\d.]+)(px|em|rem)?\s*\)/g)) {
      const v = parseFloat(m[3]) * (m[4] === 'em' || m[4] === 'rem' ? 16 : 1), d = m[2] === 'width' ? w : h;
      if (m[1] === 'min-' ? d < v : m[1] === 'max-' ? d > v : d !== v) return false;
    }
    return true;
  });
}

function MediaQueryList() { throw new TypeError('Illegal constructor'); }
iface('MediaQueryList', MediaQueryList, EventTarget);
makeMediaQueryList = function (query) {
  const mql = create(MediaQueryList.prototype);
  setSlot(mql, { listeners: [], isTarget: true, isMQL: true, media: query });
  return mql;
};
attributes(MediaQueryList.prototype, {
  media: { get() { const s = slotOf(this); if (!s || !s.isMQL) illegal(); return s.media; } },
  matches: { get() { const s = slotOf(this); if (!s || !s.isMQL) illegal(); const g = N.geom(N.root(), 4); return mediaMatches(s.media, g ? g[0] : 800, g ? g[1] : 600); } },
  onchange: eventHandlerAttribute('change')
});
operations(MediaQueryList.prototype, {
  addListener(callback) { this.addEventListener('change', callback); },
  removeListener(callback) { this.removeEventListener('change', callback); }
});

// --- Selection (a single range per document, enough for the common script uses)

function Selection() { throw new TypeError('Illegal constructor'); }
iface('Selection', Selection, null);
const selectionObject = create(Selection.prototype);
setSlot(selectionObject, { isSelection: true, range: null });
function selSlot(o) { const s = slotOf(o); if (!s || !s.isSelection) illegal(); return s; }
function selectionCollapsedOrNull(s) { return s.range === null; }
attributes(Selection.prototype, {
  anchorNode: { get() { const s = selSlot(this); return s.range ? slotOf(s.range).startNode : null; } },
  anchorOffset: { get() { const s = selSlot(this); return s.range ? slotOf(s.range).startOffset : 0; } },
  focusNode: { get() { const s = selSlot(this); return s.range ? slotOf(s.range).endNode : null; } },
  focusOffset: { get() { const s = selSlot(this); return s.range ? slotOf(s.range).endOffset : 0; } },
  isCollapsed: { get() { const s = selSlot(this); if (!s.range) return true; const r = slotOf(s.range); return r.startNode === r.endNode && r.startOffset === r.endOffset; } },
  rangeCount: { get() { return selSlot(this).range ? 1 : 0; } },
  type: { get() { const s = selSlot(this); if (!s.range) return 'None'; const r = slotOf(s.range); return r.startNode === r.endNode && r.startOffset === r.endOffset ? 'Caret' : 'Range'; } },
  direction: { get() { selSlot(this); return 'none'; } }
});
operations(Selection.prototype, {
  getRangeAt(index) { const s = selSlot(this); if (toUnsignedLong(index) !== 0 || !s.range) throw domError('IndexSizeError', 'The index is out of range'); return s.range; },
  addRange(range) { const s = selSlot(this); if (s.range === null) s.range = range; },
  removeRange(range) { const s = selSlot(this); if (s.range !== range) throw domError('NotFoundError', 'The range is not in the selection'); s.range = null; },
  removeAllRanges() { selSlot(this).range = null; },
  empty() { selSlot(this).range = null; },
  collapse(node, offset = 0) { const s = selSlot(this); if (node === null) { s.range = null; return; } const r = new Range(); r.setStart(node, offset); r.collapse(true); s.range = r; },
  setPosition(node, offset = 0) { this.collapse(node, offset); },
  collapseToStart() { const s = selSlot(this); if (!s.range) throw domError('InvalidStateError', 'There is no selection'); s.range.collapse(true); },
  collapseToEnd() { const s = selSlot(this); if (!s.range) throw domError('InvalidStateError', 'There is no selection'); s.range.collapse(false); },
  extend(node, offset = 0) { const s = selSlot(this); if (!s.range) throw domError('InvalidStateError', 'There is no selection'); s.range.setEnd(node, offset); },
  setBaseAndExtent(anchorNode, anchorOffset, focusNode, focusOffset) { const s = selSlot(this); const r = new Range(); r.setStart(anchorNode, anchorOffset); r.setEnd(focusNode, focusOffset); s.range = r; },
  selectAllChildren(node) { const s = selSlot(this); const r = new Range(); r.selectNodeContents(node); s.range = r; },
  deleteFromDocument() { const s = selSlot(this); if (s.range) s.range.deleteContents(); },
  containsNode(node, allowPartialContainment = false) { const s = selSlot(this); if (!s.range) return false; const r = s.range; const inter = r.intersectsNode(node); if (!inter) return false; if (allowPartialContainment) return true; return r.comparePoint(node, 0) >= 0 && r.comparePoint(node, nodeLength(node)) <= 0; },
  toString() { const s = selSlot(this); return s.range ? s.range.toString() : ''; }
});
defineProperty(global, 'getSelection', { value: function getSelection() { return selectionObject; }, writable: true, enumerable: true, configurable: true });
Document.prototype.getSelection = function getSelection() { return selectionObject; };
defineProperty(Document.prototype, 'getSelection', { enumerable: true });
