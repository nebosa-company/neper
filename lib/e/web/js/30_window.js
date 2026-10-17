// The window: document extras, location, history, navigator, performance, URL, encoding, script execution.

// --- Document extras

const documentAttrs = {
  title: {
    get() {
      const s = docSlot(this);
      let title = null;
      if (s.docType === 'html') {
        for (const d of descendantsOf(this)) if (nodeType(d) === ELEMENT_NODE && slotOf(d).localName === 'title' && slotOf(d).namespaceURI === HTML_NS) { title = d; break; }
      } else {
        const de = documentElementOf(this);
        if (de !== null && slotOf(de).namespaceURI === SVG_NS && slotOf(de).localName === 'svg') {
          for (const c of childrenOf(de)) if (nodeType(c) === ELEMENT_NODE && slotOf(c).localName === 'title' && slotOf(c).namespaceURI === SVG_NS) { title = c; break; }
        } else if (de !== null) {
          for (const d of descendantsOf(this)) if (nodeType(d) === ELEMENT_NODE && slotOf(d).localName === 'title' && slotOf(d).namespaceURI === HTML_NS) { title = d; break; }
        }
      }
      return title === null ? '' : stripAndCollapse(descendantTextContent(title));
    },
    set(v) {
      const s = docSlot(this);
      const value = toDOMString(v);
      let title = null;
      const de = documentElementOf(this);
      if (de !== null && slotOf(de).namespaceURI === SVG_NS && slotOf(de).localName === 'svg') {
        for (const c of childrenOf(de)) if (nodeType(c) === ELEMENT_NODE && slotOf(c).localName === 'title' && slotOf(c).namespaceURI === SVG_NS) { title = c; break; }
        if (title === null) { title = createElementInternal(this, 'title', SVG_NS, null, null, false); preInsert(title, de, firstChild(de)); }
        replaceAllWith(title, value === '' ? null : createTextNode(this, value));
        return;
      }
      if (de !== null && slotOf(de).namespaceURI === HTML_NS) {
        for (const d of descendantsOf(this)) if (nodeType(d) === ELEMENT_NODE && slotOf(d).localName === 'title' && slotOf(d).namespaceURI === HTML_NS) { title = d; break; }
        if (title === null) {
          const head = headOf(this);
          if (head === null) return;
          title = createElementInternal(this, 'title', HTML_NS, null, null, false);
          preInsert(title, head, null);
        }
        replaceAllWith(title, value === '' ? null : createTextNode(this, value));
      }
    }
  },
  head: { get() { docSlot(this); return headOf(this); } },
  body: {
    get() { docSlot(this); return bodyOf(this); },
    set(v) {
      docSlot(this);
      if (v === null || !isObject(v) || !slotOf(v) || slotOf(v).nodeType !== ELEMENT_NODE || slotOf(v).namespaceURI !== HTML_NS || (slotOf(v).localName !== 'body' && slotOf(v).localName !== 'frameset')) throw domError('HierarchyRequestError', 'The new body must be a body or frameset element');
      const old = bodyOf(this);
      if (old === v) return;
      if (old !== null) { replaceChild(v, old, parentNode(old)); return; }
      const de = documentElementOf(this);
      if (de === null) throw domError('HierarchyRequestError', 'The document has no document element');
      preInsert(v, de, null);
    }
  },
  forms: { get() { docSlot(this); return htmlCollectionOf(this, 'forms', d => slotOf(d).localName === 'form'); } },
  images: { get() { docSlot(this); return htmlCollectionOf(this, 'images', d => slotOf(d).localName === 'img'); } },
  links: { get() { docSlot(this); return htmlCollectionOf(this, 'links', d => (slotOf(d).localName === 'a' || slotOf(d).localName === 'area') && getAttributeValue(d, 'href') !== null); } },
  anchors: { get() { docSlot(this); return htmlCollectionOf(this, 'anchors', d => slotOf(d).localName === 'a' && getAttributeValue(d, 'name') !== null); } },
  scripts: { get() { docSlot(this); return htmlCollectionOf(this, 'scripts', d => slotOf(d).localName === 'script'); } },
  embeds: { get() { docSlot(this); return htmlCollectionOf(this, 'embeds', d => slotOf(d).localName === 'embed'); } },
  plugins: { get() { docSlot(this); return htmlCollectionOf(this, 'embeds', d => slotOf(d).localName === 'embed'); } },
  applets: { get() { docSlot(this); return htmlCollectionOf(this, 'applets', d => false); } },
  all: { get() { docSlot(this); return htmlCollectionOf(this, 'all', d => true); } },
  cookie: { get() { return docSlot(this).cookie; }, set(v) { const s = docSlot(this); const c = toDOMString(v); const semi = c.indexOf(';'); const pair = semi >= 0 ? c.slice(0, semi) : c; const eq = pair.indexOf('='); const name = eq >= 0 ? pair.slice(0, eq).trim() : ''; const value = eq >= 0 ? pair.slice(eq + 1).trim() : pair.trim();
    const jar = s.jar || (s.jar = []); for (let i = 0; i < jar.length; i++) if (jar[i][0] === name) jar.splice(i--, 1); if (!/max-age=0|expires=.*1970/i.test(c)) jar.push([name, value]); s.cookie = jar.map(p => p[0] === '' ? p[1] : p[0] + '=' + p[1]).join('; '); } },
  referrer: { get() { return docSlot(this).referrer || ''; } },
  domain: { get() { const s = docSlot(this); try { return new URL(s.url).hostname; } catch (_) { return ''; } }, set(v) {} },
  lastModified: { get() { return '01/01/1970 00:00:00'; } },
  readyState: { get() { return docSlot(this).readyState; } },
  location: { get() { const s = docSlot(this); return s.browsingContext ? global.location : null; }, set(v) { const s = docSlot(this); if (s.browsingContext) global.location.href = v; } },
  defaultView: { get() { return docSlot(this).browsingContext ? global : null; } },
  designMode: { get() { return docSlot(this).designMode || 'off'; }, set(v) { const l = asciiLowercase(toDOMString(v)); if (l === 'on' || l === 'off') docSlot(this).designMode = l; } },
  dir: { get() { const de = documentElementOf(this); if (de === null) return ''; const v = getAttributeValue(de, 'dir'); return v !== null && ['ltr', 'rtl', 'auto'].indexOf(asciiLowercase(v)) >= 0 ? asciiLowercase(v) : ''; }, set(v) { const de = documentElementOf(this); if (de !== null) setAttributeValue(de, 'dir', toDOMString(v)); } },
  activeElement: { get() { const s = docSlot(this); return s.focused !== null && isConnected(s.focused) ? s.focused : bodyOf(this) || documentElementOf(this); } },
  hidden: { get() { return false; } },
  visibilityState: { get() { return 'visible'; } },
  currentScript: { get() { return docSlot(this).currentScript; } },
  fullscreenEnabled: { get() { return false; } },
  fullscreenElement: { get() { return null; } },
  scrollingElement: { get() { return docSlot(this).mode === 'quirks' ? bodyOf(this) : documentElementOf(this); } },
  styleSheets: { get() { return styleSheetsOf(this); } },
  adoptedStyleSheets: { get() { const s = docSlot(this); if (!s.adopted) s.adopted = []; return s.adopted; }, set(v) { docSlot(this).adopted = Array.from(v); } },
  fonts: { get() { return fontsOf(this); } },
  characterSet: { get() { return docSlot(this).encoding; } },
  lastElementChildCache: { get() { return null; } }
};
delete documentAttrs.lastElementChildCache;
attributes(Document.prototype, documentAttrs);
defineHandlerAttrs(Document.prototype, eventHandlerNames);
attributes(Document.prototype, {
  onreadystatechange: eventHandlerAttribute('readystatechange'),
  onvisibilitychange: eventHandlerAttribute('visibilitychange'),
  onselectionchange: eventHandlerAttribute('selectionchange')
});
function headOf(doc) {
  const de = documentElementOf(doc);
  if (de === null) return null;
  for (const c of childrenOf(de)) if (nodeType(c) === ELEMENT_NODE && slotOf(c).localName === 'head' && slotOf(c).namespaceURI === HTML_NS) return c;
  return null;
}
function bodyOf(doc) {
  const de = documentElementOf(doc);
  if (de === null || slotOf(de).localName !== 'html' || slotOf(de).namespaceURI !== HTML_NS) return null;
  for (const c of childrenOf(de)) if (nodeType(c) === ELEMENT_NODE && slotOf(c).namespaceURI === HTML_NS && (slotOf(c).localName === 'body' || slotOf(c).localName === 'frameset')) return c;
  return null;
}
function htmlCollectionOf(doc, name, pred) {
  const s = slotOf(doc);
  if (!s.collections) s.collections = {};
  if (!s.collections[name]) s.collections[name] = makeCollection(() => { const out = []; for (const d of descendantsOf(doc)) if (nodeType(d) === ELEMENT_NODE && pred(d)) apply(arrayPush, out, [d]); return out; });
  return s.collections[name];
}
let styleSheetsOf = doc => [];
let fontsOf = doc => null;
operations(HTMLDocument.prototype, {});
operations(Document.prototype, {
  getElementsByName(elementName) {
    docSlot(this);
    required(arguments, 1, 'getElementsByName');
    const name = toDOMString(elementName);
    return makeCollection(() => { const out = []; for (const d of descendantsOf(this)) if (nodeType(d) === ELEMENT_NODE && slotOf(d).namespaceURI === HTML_NS && getAttributeValue(d, 'name') === name) apply(arrayPush, out, [d]); return out; });
  },
  open() { const s = docSlot(this); return this; },
  close() { docSlot(this); },
  write(...text) { docSlot(this); documentWrite(this, text.join('')); },
  writeln(...text) { docSlot(this); documentWrite(this, text.join('') + '\n'); },
  execCommand() { return false; },
  queryCommandSupported() { return false; },
  queryCommandEnabled() { return false; },
  elementFromPoint(x, y) { return null; },
  elementsFromPoint(x, y) { return []; },
  caretPositionFromPoint() { return null; },
  exitFullscreen() { return Promise.resolve(); },
  requestStorageAccess() { return Promise.resolve(); },
  hasStorageAccess() { return Promise.resolve(true); }
});
function documentWrite(doc, markup) {
  // A write after parsing has finished replaces nothing in this model: the markup is appended to the body.
  const body = bodyOf(doc);
  const target = body === null ? documentElementOf(doc) : body;
  if (target === null) return;
  const frag = parseFragment(target, markup);
  preInsert(frag, target, null);
}

// --- Window

function Window() { throw new TypeError('Illegal constructor'); }
iface('Window', Window, EventTarget);
setPrototypeOf(global, Window.prototype);
function WindowProperties() {}
setSlot(global, { listeners: [], isTarget: true });
for (const name of ['window', 'self', 'globalThis', 'top', 'parent', 'frames']) {
  defineProperty(global, name, { get() { return name === 'top' ? N.topWindow() : name === 'parent' ? N.parentWindow() : global; }, set(v) { defineProperty(global, name, { value: v, writable: true, enumerable: true, configurable: true }); }, enumerable: true, configurable: true });
}
defineProperty(global, 'globalThis', { value: global, writable: true, enumerable: false, configurable: true });
defineProperty(global, 'document', { get() { return mainDocument; }, enumerable: true, configurable: true });
Object.defineProperty(global, 'name', { value: '', writable: true, enumerable: true, configurable: true });
for (const [name, fn] of Object.entries(windowMethods)) defineProperty(global, name, { value: fn, writable: true, enumerable: true, configurable: true });
defineHandlerAttrs(Window.prototype, eventHandlerNames.concat(['beforeunload', 'hashchange', 'languagechange', 'message', 'messageerror', 'offline', 'online', 'pagehide', 'pageshow', 'popstate', 'rejectionhandled', 'storage', 'unhandledrejection', 'unload']));
operations(global, {
  alert() {}, confirm() { return false; }, prompt() { return null; }, print() {}, stop() {}, focus() {}, blur() {}, close() {},
  open() { return null; },
  getComputedStyle(elt, pseudoElt = undefined) { return computedStyleOf(elt, pseudoElt); },
  matchMedia(query) { return makeMediaQueryList(toDOMString(query)); },
  scrollTo() {}, scrollBy() {}, scroll() {},
  getSelection() { return null; },
  postMessage(message, targetOrigin = undefined, transfer = undefined) {
    required(arguments, 1, 'postMessage');
    let target = '*';
    if (isObject(targetOrigin) && !(typeof targetOrigin === 'string')) { target = targetOrigin.targetOrigin === undefined ? '/' : String(targetOrigin.targetOrigin); }
    else if (targetOrigin !== undefined) target = toDOMString(targetOrigin);
    const caller = N.callerWindow();
    const origin = caller.origin;
    const mine = slotOf(mainDocument).origin;
    if (target !== '*' && target !== '/' && target !== mine) {
      if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(target)) throw domError('SyntaxError', "Invalid target origin '" + target + "' in a call to 'postMessage'.");
      return;
    }
    const data = structuredCloneImpl(message);
    scheduleTimer(() => { const ev = new MessageEvent('message', { data, origin: origin, source: caller }); slotOf(ev).isTrusted = true; dispatch(ev, global); }, 0, false, []);
  },
  structuredClone(value) { return structuredCloneImpl(value); },
  reportError(e) { reportException(e); },
  btoa(data) {
    required(arguments, 1, 'btoa');
    const s = toDOMString(data);
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out = '';
    for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) > 255) throw domError('InvalidCharacterError', 'The string to be encoded contains characters outside of the Latin1 range.');
    for (let i = 0; i < s.length; i += 3) {
      const a = s.charCodeAt(i), b = i + 1 < s.length ? s.charCodeAt(i + 1) : NaN, c = i + 2 < s.length ? s.charCodeAt(i + 2) : NaN;
      out += chars[a >> 2] + chars[((a & 3) << 4) | ((b !== b ? 0 : b) >> 4)] + (b !== b ? '=' : chars[((b & 15) << 2) | ((c !== c ? 0 : c) >> 6)]) + (c !== c ? '=' : chars[c & 63]);
    }
    return out;
  },
  atob(data) {
    required(arguments, 1, 'atob');
    let s = toDOMString(data).replace(/[\t\n\f\r ]/g, '');
    if (s.length % 4 === 0) s = s.replace(/==?$/, '');
    if (s.length % 4 === 1 || /[^A-Za-z0-9+/]/.test(s)) throw domError('InvalidCharacterError', 'The string to be decoded is not correctly encoded.');
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out = '', bits = 0, acc = 0;
    for (let i = 0; i < s.length; i++) {
      acc = (acc << 6) | chars.indexOf(s[i]);
      bits += 6;
      if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 255); }
    }
    return out;
  }
});
let makeMediaQueryList = q => ({ media: q, matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return true; } });
let structuredCloneImpl = v => v;
const windowAttrs = {
  location: { get() { return locationObject; }, set(v) { locationObject.href = v; } },
  history: { get() { return historyObject; } },
  navigator: { get() { return navigatorObject; } },
  performance: { get() { return performanceObject; } },
  devicePixelRatio: { get() { return 1; } },
  screenX: { get() { return 0; } }, screenY: { get() { return 0; } }, screenLeft: { get() { return 0; } }, screenTop: { get() { return 0; } },
  screen: { get() { return screenObject; } },
  origin: { get() { return slotOf(mainDocument).origin; } },
  isSecureContext: { get() { return false; } },
  closed: { get() { return false; } },
  length: { get() { return N.frameCount(); } },
  opener: { get() { return null; }, set(v) {} },
  frameElement: { get() { return hasOwn.call(global, '__frameElement') ? global.__frameElement : null; } },
  status: { get() { return ''; }, set(v) {} },
  crossOriginIsolated: { get() { return false; } }
};
let viewportWidth = 800, viewportHeight = 600;
for (const key of Object.keys(windowAttrs)) {
  const a = windowAttrs[key];
  defineProperty(global, key, { get: a.get, set: a.set || function (v) { defineProperty(global, key, { value: v, writable: true, enumerable: true, configurable: true }); }, enumerable: true, configurable: true });
}

// --- URL

function parseURLComponents(input, base) {
  return N.urlParse(input, base === undefined ? null : base);
}
parseURLAgainst = function (input, base) {
  const c = N.urlParse(input, base === undefined || base === '' ? null : base);
  return c === null ? null : { href: c[0] };
};
const urlSlots = new WeakMap();
function URL(url, base = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'URL': Please use the 'new' operator, this DOM object constructor cannot be called as a function.");
  required(arguments, 1, 'URL');
  const u = toUSVString(url);
  const b = base === undefined ? null : toUSVString(base);
  let baseHref = null;
  if (b !== null) {
    const bc = N.urlParse(b, null);
    if (bc === null) throw new TypeError("Failed to construct 'URL': Invalid base URL");
    baseHref = bc[0];
  }
  const c = N.urlParse(u, baseHref);
  if (c === null) throw new TypeError("Failed to construct 'URL': Invalid URL");
  setSlot(this, { isURL: true, c, searchParams: null });
}
iface('URL', URL, null);
function urlSlot(o) { const s = slotOf(o); if (!s || !s.isURL) illegal(); return s; }
function urlSetter(component) {
  return function (v) {
    const s = urlSlot(this);
    const c = N.urlSet(s.c[0], component, toUSVString(v));
    if (c !== null) {
      s.c = c;
      if (component === 'search' && s.searchParams !== null) updateSearchParamsFromURL(this);
    }
  };
}
attributes(URL.prototype, {
  href: { get() { return urlSlot(this).c[0]; }, set(v) { const s = urlSlot(this); const c = N.urlParse(toUSVString(v), null); if (c === null) throw new TypeError("Failed to set the 'href' property on 'URL': Invalid URL"); s.c = c; if (s.searchParams !== null) updateSearchParamsFromURL(this); } },
  origin: { get() { return urlSlot(this).c[10]; } },
  protocol: { get() { return urlSlot(this).c[1]; }, set: urlSetter('protocol') },
  username: { get() { return urlSlot(this).c[2]; }, set: urlSetter('username') },
  password: { get() { return urlSlot(this).c[3]; }, set: urlSetter('password') },
  host: { get() { return urlSlot(this).c[4]; }, set: urlSetter('host') },
  hostname: { get() { return urlSlot(this).c[5]; }, set: urlSetter('hostname') },
  port: { get() { return urlSlot(this).c[6]; }, set: urlSetter('port') },
  pathname: { get() { return urlSlot(this).c[7]; }, set: urlSetter('pathname') },
  search: { get() { return urlSlot(this).c[8]; }, set: urlSetter('search') },
  searchParams: { get() { const s = urlSlot(this); if (s.searchParams === null) { s.searchParams = newSearchParams(this); updateSearchParamsFromURL(this); } return s.searchParams; } },
  hash: { get() { return urlSlot(this).c[9]; }, set: urlSetter('hash') }
});
operations(URL.prototype, {
  toString() { return urlSlot(this).c[0]; },
  toJSON() { return urlSlot(this).c[0]; }
});
operations(URL, {
  canParse(url, base = undefined) {
    required(arguments, 1, 'canParse');
    let baseHref = null;
    if (base !== undefined) { const bc = N.urlParse(toUSVString(base), null); if (bc === null) return false; baseHref = bc[0]; }
    return N.urlParse(toUSVString(url), baseHref) !== null;
  },
  parse(url, base = undefined) {
    required(arguments, 1, 'parse');
    try { return new URL(url, base); } catch (_) { return null; }
  }
});
defineProperty(URL, 'createObjectURL', { value: function createObjectURL(obj) { return 'blob:' + slotOf(mainDocument).origin + '/' + (++blobCounter); }, writable: true, enumerable: true, configurable: true });
defineProperty(URL, 'revokeObjectURL', { value: function revokeObjectURL(url) {}, writable: true, enumerable: true, configurable: true });
let blobCounter = 0;

// --- URLSearchParams

function URLSearchParams(init = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'URLSearchParams': Please use the 'new' operator.");
  const s = setSlot(this, { isParams: true, list: [], url: null });
  if (init === undefined || init === null && false) return;
  if (isObject(init)) {
    if (typeof init[symIterator] === 'function') {
      for (const pair of init) {
        const items = Array.from(pair);
        if (items.length !== 2) throw new TypeError("Failed to construct 'URLSearchParams': Sequence initializer must only contain pair elements");
        s.list.push([toUSVString(items[0]), toUSVString(items[1])]);
      }
    } else {
      for (const key of Reflect.ownKeys(init)) {
        if (typeof key !== 'string') continue;
        const d = getOwnPropertyDescriptor(init, key);
        if (d !== undefined && d.enumerable) s.list.push([toUSVString(key), toUSVString(init[key])]);
      }
    }
  } else {
    let str = toUSVString(init);
    if (str[0] === '?') str = str.slice(1);
    s.list = parseUrlEncoded(str);
  }
}
iface('URLSearchParams', URLSearchParams, null);
function paramsSlot(o) { const s = slotOf(o); if (!s || !s.isParams) illegal(); return s; }
function percentDecode(s) {
  const bytes = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 37 && i + 2 < s.length + 0 && /^[0-9a-fA-F]{2}$/.test(s.slice(i + 1, i + 3))) { bytes.push(parseInt(s.slice(i + 1, i + 3), 16)); i += 2; }
    else if (c < 128) bytes.push(c);
    else { const enc = encodeUTF8(s[i] + (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length ? s[++i] : '')); for (const b of enc) bytes.push(b); }
  }
  return decodeUTF8(bytes);
}
function parseUrlEncoded(input) {
  const out = [];
  for (const seq of input.split('&')) {
    if (seq === '') continue;
    const eq = seq.indexOf('=');
    const name = eq >= 0 ? seq.slice(0, eq) : seq;
    const value = eq >= 0 ? seq.slice(eq + 1) : '';
    out.push([percentDecode(name.replace(/\+/g, ' ')), percentDecode(value.replace(/\+/g, ' '))]);
  }
  return out;
}
function serializeUrlEncoded(list) {
  let out = '';
  for (const [n, v] of list) {
    if (out !== '') out += '&';
    out += urlEncodeComponent(n) + '=' + urlEncodeComponent(v);
  }
  return out;
}
function urlEncodeComponent(s) {
  let out = '';
  const bytes = encodeUTF8(s);
  for (const b of bytes) {
    if (b === 32) out += '+';
    else if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b === 42 || b === 45 || b === 46 || b === 95) out += String.fromCharCode(b);
    else out += '%' + (b < 16 ? '0' : '') + b.toString(16).toUpperCase();
  }
  return out;
}
function encodeUTF8(s) {
  const out = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.codePointAt(i);
    if (c > 0xFFFF) i++;
    if (c >= 0xD800 && c <= 0xDFFF) c = 0xFFFD;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xC0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return out;
}
function decodeUTF8(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length;) {
    const b = bytes[i];
    let cp = 0xFFFD, n = 1;
    if (b < 0x80) { cp = b; }
    else if (b >= 0xC2 && b <= 0xDF && i + 1 < bytes.length && (bytes[i + 1] & 0xC0) === 0x80) { cp = ((b & 31) << 6) | (bytes[i + 1] & 63); n = 2; }
    else if (b >= 0xE0 && b <= 0xEF && i + 2 < bytes.length && (bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80) {
      const c = ((b & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63);
      if (c >= 0x800 && (c < 0xD800 || c > 0xDFFF)) { cp = c; n = 3; }
    } else if (b >= 0xF0 && b <= 0xF4 && i + 3 < bytes.length && (bytes[i + 1] & 0xC0) === 0x80 && (bytes[i + 2] & 0xC0) === 0x80 && (bytes[i + 3] & 0xC0) === 0x80) {
      const c = ((b & 7) << 18) | ((bytes[i + 1] & 63) << 12) | ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63);
      if (c >= 0x10000 && c <= 0x10FFFF) { cp = c; n = 4; }
    }
    out += String.fromCodePoint(cp);
    i += n;
  }
  return out;
}
function newSearchParams(url) {
  const p = create(URLSearchParams.prototype);
  setSlot(p, { isParams: true, list: [], url });
  return p;
}
function updateSearchParamsFromURL(url) {
  const us = urlSlot(url);
  const q = us.c[8];
  slotOf(us.searchParams).list = parseUrlEncoded(q[0] === '?' ? q.slice(1) : q);
}
function updateURLFromParams(params) {
  const s = slotOf(params);
  if (s.url === null) return;
  const us = urlSlot(s.url);
  const serialized = serializeUrlEncoded(s.list);
  const c = N.urlSet(us.c[0], 'searchRaw', serialized);
  if (c !== null) us.c = c;
}
operations(URLSearchParams.prototype, {
  append(name, value) { const s = paramsSlot(this); required(arguments, 2, 'append'); s.list.push([toUSVString(name), toUSVString(value)]); updateURLFromParams(this); },
  delete(name, value = undefined) {
    const s = paramsSlot(this);
    required(arguments, 1, 'delete');
    const n = toUSVString(name);
    const v = value === undefined ? undefined : toUSVString(value);
    s.list = s.list.filter(p => !(p[0] === n && (v === undefined || p[1] === v)));
    updateURLFromParams(this);
  },
  get(name) { const s = paramsSlot(this); required(arguments, 1, 'get'); const n = toUSVString(name); for (const p of s.list) if (p[0] === n) return p[1]; return null; },
  getAll(name) { const s = paramsSlot(this); required(arguments, 1, 'getAll'); const n = toUSVString(name); return s.list.filter(p => p[0] === n).map(p => p[1]); },
  has(name, value = undefined) {
    const s = paramsSlot(this);
    required(arguments, 1, 'has');
    const n = toUSVString(name);
    const v = value === undefined ? undefined : toUSVString(value);
    for (const p of s.list) if (p[0] === n && (v === undefined || p[1] === v)) return true;
    return false;
  },
  set(name, value) {
    const s = paramsSlot(this);
    required(arguments, 2, 'set');
    const n = toUSVString(name), v = toUSVString(value);
    let found = false;
    const out = [];
    for (const p of s.list) {
      if (p[0] === n) { if (!found) { found = true; out.push([n, v]); } } else out.push(p);
    }
    if (!found) out.push([n, v]);
    s.list = out;
    updateURLFromParams(this);
  },
  sort() {
    const s = paramsSlot(this);
    const idx = s.list.map((p, i) => [p, i]);
    idx.sort((a, b) => { const x = a[0][0], y = b[0][0]; if (x === y) return a[1] - b[1]; const n = Math.min(x.length, y.length); for (let i = 0; i < n; i++) { const d = x.charCodeAt(i) - y.charCodeAt(i); if (d !== 0) return d; } return x.length - y.length || a[1] - b[1]; });
    s.list = idx.map(e => e[0]);
    updateURLFromParams(this);
  },
  toString() { return serializeUrlEncoded(paramsSlot(this).list); },
  forEach(callback, thisArg = undefined) {
    const s = paramsSlot(this);
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError("Failed to execute 'forEach' on 'URLSearchParams': parameter 1 is not of type 'Function'.");
    for (let i = 0; i < s.list.length; i++) apply(callback, thisArg, [s.list[i][1], s.list[i][0], this]);
  },
  keys() { paramsSlot(this); return makeParamsIterator(this, 'key'); },
  values() { paramsSlot(this); return makeParamsIterator(this, 'value'); },
  entries() { paramsSlot(this); return makeParamsIterator(this, 'key+value'); }
});
attributes(URLSearchParams.prototype, { size: { get() { return paramsSlot(this).list.length; } } });
defineProperty(URLSearchParams.prototype, symIterator, { value: URLSearchParams.prototype.entries, writable: true, enumerable: false, configurable: true });
const IteratorProto = getPrototypeOf(getPrototypeOf([][symIterator]()));
const ParamsIteratorProto = create(IteratorProto);
defineProperty(ParamsIteratorProto, symToStringTag, { value: 'URLSearchParams Iterator', configurable: true });
operations(ParamsIteratorProto, {
  next() {
    const s = slotOf(this);
    if (!s || !s.isParamsIterator) illegal();
    const list = slotOf(s.target).list;
    if (s.index >= list.length) return { value: undefined, done: true };
    const p = list[s.index++];
    return { value: s.kind === 'key' ? p[0] : s.kind === 'value' ? p[1] : [p[0], p[1]], done: false };
  }
});
defineProperty(ParamsIteratorProto, 'next', { enumerable: true });
function makeParamsIterator(target, kind) {
  const it = create(ParamsIteratorProto);
  setSlot(it, { isParamsIterator: true, target, kind, index: 0 });
  return it;
}

// --- Location

function Location() { throw new TypeError('Illegal constructor'); }
iface('Location', Location, null);
const locationObject = create(Location.prototype);
setSlot(locationObject, { isLocation: true });
function curURL() { return N.urlParse(slotOf(mainDocument).url, null) || ['about:blank', 'about:', '', '', '', '', '', 'blank', '', '', 'null']; }
function navigateTo(href) {
  const c = N.urlParse(href, slotOf(mainDocument).url);
  if (c === null) throw domError('SyntaxError', 'Invalid URL');
  const old = slotOf(mainDocument).url;
  const sameDocFragment = c[0].split('#')[0] === old.split('#')[0] && c[9] !== '' || (c[0].split('#')[0] === old.split('#')[0] && c[0].indexOf('#') >= 0);
  if (sameDocFragment) {
    slotOf(mainDocument).url = c[0];
    scheduleTimer(() => { const ev = new HashChangeEvent('hashchange', { oldURL: old, newURL: c[0] }); slotOf(ev).isTrusted = true; dispatch(ev, global); }, 0, false, []);
  } else N.navigate(c[0]);
}
function locAttr(i, setterName) {
  return { get() { if (this !== locationObject) illegal(); return curURL()[i]; }, set(v) { if (this !== locationObject) illegal(); const u = curURL(); const c = N.urlSet(u[0], setterName, toUSVString(v)); if (c !== null) navigateTo(c[0]); } };
}
attributes(Location.prototype, {
  href: { get() { if (this !== locationObject) illegal(); return slotOf(mainDocument).url; }, set(v) { if (this !== locationObject) illegal(); navigateTo(toUSVString(v)); } },
  origin: { get() { if (this !== locationObject) illegal(); return curURL()[10]; } },
  protocol: locAttr(1, 'protocol'), host: locAttr(4, 'host'), hostname: locAttr(5, 'hostname'), port: locAttr(6, 'port'),
  pathname: locAttr(7, 'pathname'), search: locAttr(8, 'search'), hash: locAttr(9, 'hash')
});
operations(Location.prototype, {
  assign(url) { if (this !== locationObject) illegal(); required(arguments, 1, 'assign'); navigateTo(toUSVString(url)); },
  replace(url) { if (this !== locationObject) illegal(); required(arguments, 1, 'replace'); navigateTo(toUSVString(url)); },
  reload() { if (this !== locationObject) illegal(); },
  toString() { if (this !== locationObject) illegal(); return slotOf(mainDocument).url; }
});
defineProperty(Location.prototype, 'ancestorOrigins', { get() { return []; }, enumerable: true, configurable: true });

// --- History, Navigator, Performance, Screen

function History() { throw new TypeError('Illegal constructor'); }
iface('History', History, null);
const historyObject = create(History.prototype);
setSlot(historyObject, { isHistory: true, entries: [{ url: null, state: null }], index: 0, scrollRestoration: 'auto' });
function histSlot(o) { const s = slotOf(o); if (!s || !s.isHistory) illegal(); return s; }
attributes(History.prototype, {
  length: { get() { return histSlot(this).entries.length; } },
  state: { get() { const s = histSlot(this); return s.entries[s.index].state; } },
  scrollRestoration: { get() { return histSlot(this).scrollRestoration; }, set(v) { const s = histSlot(this); const x = toDOMString(v); if (x === 'auto' || x === 'manual') s.scrollRestoration = x; } }
});
operations(History.prototype, {
  pushState(data, unused, url = undefined) { const s = histSlot(this); if (url !== undefined && url !== null) setDocumentURL(url); s.entries.splice(s.index + 1); s.entries.push({ url: slotOf(mainDocument).url, state: data }); s.index++; },
  replaceState(data, unused, url = undefined) { const s = histSlot(this); if (url !== undefined && url !== null) setDocumentURL(url); s.entries[s.index] = { url: slotOf(mainDocument).url, state: data }; },
  go(delta = 0) { const s = histSlot(this); const n = s.index + (+delta || 0); if (n < 0 || n >= s.entries.length) return; s.index = n; const e = s.entries[n]; scheduleTimer(() => { const ev = new PopStateEvent('popstate', { state: e.state }); slotOf(ev).isTrusted = true; dispatch(ev, global); }, 0, false, []); },
  back() { this.go(-1); },
  forward() { this.go(1); }
});
function setDocumentURL(url) {
  const c = N.urlParse(toUSVString(url), slotOf(mainDocument).url);
  if (c === null) throw domError('SecurityError', 'Invalid URL');
  const cur = curURL();
  if (c[10] !== cur[10]) throw domError('SecurityError', 'A history state object with URL cannot be created in a document with a different origin');
  slotOf(mainDocument).url = c[0];
}

function Navigator() { throw new TypeError('Illegal constructor'); }
iface('Navigator', Navigator, null);
const navigatorObject = create(Navigator.prototype);
setSlot(navigatorObject, { isNavigator: true });
attributes(Navigator.prototype, {
  userAgent: { get() { return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Neper/1.0 Safari/537.36'; } },
  appCodeName: { get() { return 'Mozilla'; } }, appName: { get() { return 'Netscape'; } }, appVersion: { get() { return '5.0 (X11)'; } },
  platform: { get() { return 'Linux x86_64'; } }, product: { get() { return 'Gecko'; } }, productSub: { get() { return '20030107'; } },
  vendor: { get() { return ''; } }, vendorSub: { get() { return ''; } },
  language: { get() { return 'en-US'; } }, languages: { get() { return ['en-US', 'en']; } },
  onLine: { get() { return true; } }, cookieEnabled: { get() { return true; } }, webdriver: { get() { return false; } },
  hardwareConcurrency: { get() { return 4; } }, maxTouchPoints: { get() { return 0; } }, pdfViewerEnabled: { get() { return false; } },
  doNotTrack: { get() { return null; } }, deviceMemory: { get() { return 4; } },
  plugins: { get() { return []; } }, mimeTypes: { get() { return []; } }
});
operations(Navigator.prototype, { javaEnabled() { return false; }, sendBeacon() { return false; } });

function Performance() { throw new TypeError('Illegal constructor'); }
iface('Performance', Performance, EventTarget);
const performanceObject = create(Performance.prototype);
setSlot(performanceObject, { listeners: [], isTarget: true, isPerformance: true, marks: [] });
operations(Performance.prototype, {
  now() { return N.now(); },
  toJSON() { return { timeOrigin: 0 }; },
  mark(name) { return undefined; },
  measure() { return undefined; },
  getEntries() { return []; }, getEntriesByName() { return []; }, getEntriesByType() { return []; }, clearMarks() {}, clearMeasures() {}
});
attributes(Performance.prototype, { timeOrigin: { get() { return 0; } } });

function Screen() { throw new TypeError('Illegal constructor'); }
iface('Screen', Screen, null);
const screenObject = create(Screen.prototype);
setSlot(screenObject, { isScreen: true });
attributes(Screen.prototype, {
  width: { get() { return viewportWidth; } }, height: { get() { return viewportHeight; } }, availWidth: { get() { return viewportWidth; } }, availHeight: { get() { return viewportHeight; } },
  colorDepth: { get() { return 24; } }, pixelDepth: { get() { return 24; } }
});

// --- text encoding

function TextEncoder() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'TextEncoder': Please use the 'new' operator");
  setSlot(this, { isEncoder: true });
}
iface('TextEncoder', TextEncoder, null);
attributes(TextEncoder.prototype, { encoding: { get() { return 'utf-8'; } } });
operations(TextEncoder.prototype, {
  encode(input = '') { return new Uint8Array(encodeUTF8(toUSVString(input))); },
  encodeInto(source, destination) {
    const bytes = encodeUTF8(toUSVString(source));
    let read = 0, written = 0;
    const s = toUSVString(source);
    let i = 0;
    for (const ch of s) {
      const b = encodeUTF8(ch);
      if (written + b.length > destination.length) break;
      for (const x of b) destination[written++] = x;
      read += ch.length;
    }
    return { read, written };
  }
});
function TextDecoder(label = 'utf-8', options = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'TextDecoder': Please use the 'new' operator");
  const l = asciiLowercase(toDOMString(label)).trim();
  if (['utf-8', 'utf8', 'unicode-1-1-utf-8'].indexOf(l) < 0) throw new RangeError("The encoding label provided ('" + label + "') is invalid.");
  setSlot(this, { isDecoder: true, fatal: !!(options && options.fatal), ignoreBOM: !!(options && options.ignoreBOM) });
}
iface('TextDecoder', TextDecoder, null);
attributes(TextDecoder.prototype, {
  encoding: { get() { return 'utf-8'; } },
  fatal: { get() { return slotOf(this).fatal; } },
  ignoreBOM: { get() { return slotOf(this).ignoreBOM; } }
});
operations(TextDecoder.prototype, {
  decode(input = undefined, options = undefined) {
    const s = slotOf(this);
    if (!s || !s.isDecoder) illegal();
    if (input === undefined) return '';
    let bytes;
    if (input instanceof ArrayBuffer) bytes = new Uint8Array(input);
    else if (ArrayBuffer.isView(input)) bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    else throw new TypeError("Failed to execute 'decode' on 'TextDecoder': The provided value is not of type '(ArrayBuffer or ArrayBufferView)'");
    let arr = Array.from(bytes);
    if (!s.ignoreBOM && arr[0] === 0xEF && arr[1] === 0xBB && arr[2] === 0xBF) arr = arr.slice(3);
    const out = decodeUTF8(arr);
    if (s.fatal && out.indexOf('�') >= 0) throw new TypeError('The encoded data was not valid for encoding utf-8');
    return out;
  }
});
