// Elements and attributes (DOM Standard 4.9, 4.10), live collections, DOMTokenList, NamedNodeMap.

// --- legacy platform objects: array-like and named access through a Proxy over a prototype-carrying target

function canonicalIndex(key) {
  if (typeof key !== 'string') return -1;
  const n = +key;
  if (n >= 0 && n < 4294967295 && n === Math.trunc(n) && String(n) === key) return n;
  return -1;
}
// `spec`: { length(): number, item(i), named(name) -> value|undefined (optional), names() -> string[] (optional), setter, deleter }
function legacyObject(proto, spec, slotState) {
  const target = create(proto);
  setSlot(target, slotState);
  const handler = {
    get(t, key, receiver) {
      const idx = canonicalIndex(key);
      if (idx >= 0) { const v = spec.item(idx); return v === null ? undefined : v; }
      if (typeof key === 'string' && spec.named && !(key in t)) {
        const v = spec.named(key);
        if (v !== undefined) return v;
      }
      return Reflect.get(t, key, receiver);
    },
    set(t, key, value, receiver) {
      const idx = canonicalIndex(key);
      if (idx >= 0) {
        if (spec.indexedSetter) { spec.indexedSetter(idx, value); return true; }
        return false;
      }
      if (typeof key === 'string' && spec.named && spec.namedSetter && receiver === proxy) {
        const hasNamed = spec.named(key) !== undefined;
        if (hasNamed || !(key in t)) { spec.namedSetter(key, value); return true; }
      }
      return Reflect.set(t, key, value, receiver);
    },
    has(t, key) {
      const idx = canonicalIndex(key);
      if (idx >= 0) return spec.item(idx) !== null;
      if (typeof key === 'string' && spec.named && spec.named(key) !== undefined) return true;
      return key in t;
    },
    getOwnPropertyDescriptor(t, key) {
      const idx = canonicalIndex(key);
      if (idx >= 0) {
        const v = spec.item(idx);
        if (v === null) return undefined;
        return { value: v, writable: !!spec.indexedSetter, enumerable: true, configurable: true };
      }
      const own = Reflect.getOwnPropertyDescriptor(t, key);
      if (own !== undefined) return own;
      if (typeof key === 'string' && spec.named) {
        const v = spec.named(key);
        if (v !== undefined && !spec.unenumerableNamed) return { value: v, writable: !!spec.namedSetter, enumerable: !!spec.enumerableNamed, configurable: true };
      }
      return undefined;
    },
    defineProperty(t, key, desc) {
      const idx = canonicalIndex(key);
      if (idx >= 0) {
        if (!spec.indexedSetter) return false;
        if ('get' in desc || 'set' in desc) return false;
        if (desc.configurable === false || desc.enumerable === false || desc.writable === false) return false;
        spec.indexedSetter(idx, desc.value);
        return true;
      }
      if (typeof key === 'string' && spec.named && spec.named(key) !== undefined && !(Reflect.getOwnPropertyDescriptor(t, key))) {
        if (!spec.namedSetter) return false;
        if ('get' in desc || 'set' in desc) return false;
        if (desc.configurable === false || desc.enumerable === false || desc.writable === false) return false;
        spec.namedSetter(key, desc.value);
        return true;
      }
      return Reflect.defineProperty(t, key, desc);
    },
    deleteProperty(t, key) {
      const idx = canonicalIndex(key);
      if (idx >= 0) return spec.item(idx) === null;
      if (typeof key === 'string' && spec.named && spec.named(key) !== undefined && !Reflect.getOwnPropertyDescriptor(t, key)) {
        if (spec.deleter) { spec.deleter(key); return true; }
        return false;
      }
      return Reflect.deleteProperty(t, key);
    },
    ownKeys(t) {
      const keys = [];
      const n = spec.length();
      for (let i = 0; i < n; i++) apply(arrayPush, keys, [String(i)]);
      if (spec.names) for (const name of spec.names()) if (!(keys.indexOf(name) >= 0) && !Reflect.getOwnPropertyDescriptor(t, name)) apply(arrayPush, keys, [name]);
      for (const k of Reflect.ownKeys(t)) apply(arrayPush, keys, [k]);
      return keys;
    },
    preventExtensions(t) { return false; }
  };
  const proxy = new Proxy(target, handler);
  setSlot(proxy, slotState);
  return proxy;
}
function lgSlot(o, flag) { const s = slotOf(o); if (!s || !s[flag]) illegal(); return s; }

// --- NodeList

function NodeList() { throw new TypeError('Illegal constructor'); }
iface('NodeList', NodeList, null);
operations(NodeList.prototype, {
  item(index) { const s = lgSlot(this, 'isNodeList'); required(arguments, 1, 'item'); return s.at(toUnsignedLong(index)); },
  forEach(callback, thisArg = undefined) {
    const s = lgSlot(this, 'isNodeList');
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError("Failed to execute 'forEach' on 'NodeList': parameter 1 is not of type 'Function'.");
    for (let i = 0; i < s.size(); i++) apply(callback, thisArg, [s.at(i), i, this]);
  },
  keys() { const s = lgSlot(this, 'isNodeList'); return arrayIteratorOf(this, 'key'); },
  values() { const s = lgSlot(this, 'isNodeList'); return arrayIteratorOf(this, 'value'); },
  entries() { const s = lgSlot(this, 'isNodeList'); return arrayIteratorOf(this, 'key+value'); }
});
attributes(NodeList.prototype, { length: { get() { return lgSlot(this, 'isNodeList').size(); } } });
defineProperty(NodeList.prototype, symIterator, { value: NodeList.prototype.values, writable: true, enumerable: false, configurable: true });
// Array iterators over array-likes use %ArrayIteratorPrototype% through Array.prototype's methods.
function arrayIteratorOf(obj, kind) {
  if (kind === 'key') return Array.prototype.keys.call(obj);
  if (kind === 'value') return Array.prototype.values.call(obj);
  return Array.prototype.entries.call(obj);
}
function makeNodeList(size, at) {
  const state = { isNodeList: true, size, at };
  return legacyObject(NodeList.prototype, { length: size, item: at }, state);
}
staticNodeList = arr => makeNodeList(() => arr.length, i => i < arr.length ? arr[i] : null);
childNodesOf = function (parent) {
  const s = slotOf(parent);
  if (s.childNodesList) return s.childNodesList;
  let cache = null, cacheVersion = -1;
  const refresh = () => {
    const v = N.version();
    if (cache === null || cacheVersion !== v) { cache = childrenOf(parent); cacheVersion = v; }
    return cache;
  };
  s.childNodesList = makeNodeList(() => refresh().length, i => { const c = refresh(); return i < c.length ? c[i] : null; });
  return s.childNodesList;
};

// --- HTMLCollection

function HTMLCollection() { throw new TypeError('Illegal constructor'); }
iface('HTMLCollection', HTMLCollection, null);
function collectionItems(s) {
  const v = N.version();
  if (s.cache === null || s.cacheVersion !== v) { s.cache = s.collect(); s.cacheVersion = v; }
  return s.cache;
}
function namedLookup(s, name) {
  if (name === '') return undefined;
  for (const el of collectionItems(s)) {
    if (getAttributeValue(el, 'id') === name) return el;
    if (slotOf(el).namespaceURI === HTML_NS && getAttributeValue(el, 'name') === name) return el;
  }
  return undefined;
}
function namedKeys(s) {
  const keys = [];
  for (const el of collectionItems(s)) {
    const id = getAttributeValue(el, 'id');
    if (id !== null && id !== '' && keys.indexOf(id) < 0) apply(arrayPush, keys, [id]);
    if (slotOf(el).namespaceURI === HTML_NS) {
      const name = getAttributeValue(el, 'name');
      if (name !== null && name !== '' && keys.indexOf(name) < 0) apply(arrayPush, keys, [name]);
    }
  }
  return keys;
}
function makeCollection(collect) {
  const state = { isCollection: true, collect, cache: null, cacheVersion: -1 };
  return legacyObject(HTMLCollection.prototype, {
    length: () => collectionItems(state).length,
    item: i => { const c = collectionItems(state); return i < c.length ? c[i] : null; },
    named: name => namedLookup(state, name),
    names: () => namedKeys(state)
  }, state);
}
operations(HTMLCollection.prototype, {
  item(index) { const s = lgSlot(this, 'isCollection'); required(arguments, 1, 'item'); const c = collectionItems(s); const i = toUnsignedLong(index); return i < c.length ? c[i] : null; },
  namedItem(name) { const s = lgSlot(this, 'isCollection'); required(arguments, 1, 'namedItem'); const v = namedLookup(s, toDOMString(name)); return v === undefined ? null : v; }
});
attributes(HTMLCollection.prototype, { length: { get() { return collectionItems(lgSlot(this, 'isCollection')).length; } } });
defineProperty(HTMLCollection.prototype, symIterator, { value: Array.prototype.values, writable: true, enumerable: false, configurable: true });
childrenCollection = function (parent) {
  const s = slotOf(parent);
  if (!s.childrenList) s.childrenList = makeCollection(() => elementChildren(parent));
  return s.childrenList;
};

// --- names

const nameStartChar = 'A-Z_a-z\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02FF\\u0370-\\u037D\\u037F-\\u1FFF\\u200C-\\u200D\\u2070-\\u218F\\u2C00-\\u2FEF\\u3001-\\uD7FF\\uF900-\\uFDCF\\uFDF0-\\uFFFD';
const nameChar = nameStartChar + '\\-.0-9\\u00B7\\u0300-\\u036F\\u203F-\\u2040';
const nameRe = new RegExp('^[:' + nameStartChar + '][:' + nameChar + ']*$', 'u');
const ncNameRe = new RegExp('^[' + nameStartChar + '][' + nameChar + ']*$', 'u');
const nameReAstral = new RegExp('^(?:[:' + nameStartChar + ']|[\\u{10000}-\\u{EFFFF}])(?:[:' + nameChar + ']|[\\u{10000}-\\u{EFFFF}])*$', 'u');
const ncNameReAstral = new RegExp('^(?:[' + nameStartChar + ']|[\\u{10000}-\\u{EFFFF}])(?:[' + nameChar + ']|[\\u{10000}-\\u{EFFFF}])*$', 'u');
function isValidName(s) { return s.length > 0 && nameReAstral.test(s); }
function isValidNCName(s) { return s.length > 0 && ncNameReAstral.test(s); }
function validateAndExtract(namespace, qualifiedName) {
  const ns = namespace === null || namespace === undefined || namespace === '' ? null : toDOMString(namespace);
  const q = toDOMString(qualifiedName);
  if (!isValidName(q)) throw domError('InvalidCharacterError', "'" + q + "' is not a valid qualified name");
  const colon = q.indexOf(':');
  let prefix = null, localName = q;
  if (colon >= 0) {
    prefix = q.slice(0, colon);
    localName = q.slice(colon + 1);
    if (!isValidNCName(prefix) || !isValidNCName(localName)) throw domError('InvalidCharacterError', "'" + q + "' is not a valid qualified name");
  } else if (!isValidNCName(q) && q.indexOf(':') < 0) {
    throw domError('InvalidCharacterError', "'" + q + "' is not a valid qualified name");
  }
  if (prefix !== null && ns === null) throw domError('NamespaceError', 'A prefix requires a namespace');
  if (prefix === 'xml' && ns !== XML_NS) throw domError('NamespaceError', 'The xml prefix requires the XML namespace');
  if ((prefix === 'xmlns' || (prefix === null && q === 'xmlns')) && ns !== XMLNS_NS) throw domError('NamespaceError', 'The xmlns prefix requires the XMLNS namespace');
  if (ns === XMLNS_NS && prefix !== 'xmlns' && !(prefix === null && q === 'xmlns')) throw domError('NamespaceError', 'The XMLNS namespace requires the xmlns prefix');
  return { namespace: ns, prefix, localName };
}

// --- Attr

function Attr() { throw new TypeError('Illegal constructor'); }
iface('Attr', Attr, Node);
function attrSlot(o) { const s = slotOf(o); if (!s || s.nodeType !== ATTRIBUTE_NODE) illegal(); return s; }
function newAttr(doc, localName, namespaceURI, prefix, value) {
  const a = create(Attr.prototype);
  const s = setSlot(a, newNodeSlot(-1, ATTRIBUTE_NODE, doc));
  s.localName = localName; s.namespaceURI = namespaceURI; s.prefix = prefix; s.value = value; s.element = null;
  return a;
}
attributes(Attr.prototype, {
  namespaceURI: { get() { return attrSlot(this).namespaceURI; } },
  prefix: { get() { return attrSlot(this).prefix; } },
  localName: { get() { return attrSlot(this).localName; } },
  name: { get() { const s = attrSlot(this); return s.prefix === null ? s.localName : s.prefix + ':' + s.localName; } },
  value: { get() { return attrSlot(this).value; }, set(v) { attrSlot(this); setAttrValue(this, toDOMString(v)); } },
  ownerElement: { get() { return attrSlot(this).element; } },
  specified: { get() { attrSlot(this); return true; } }
});
function qualifiedName(attr) { const s = slotOf(attr); return s.prefix === null ? s.localName : s.prefix + ':' + s.localName; }

// Element attribute storage: `attrObjs` (Attr objects, authoritative) mirrored into the native table by index.
attrsOf = function (el) {
  const s = slotOf(el);
  if (s.attrObjs !== null) return s.attrObjs;
  const list = [];
  const n = N.attrCount(s.id);
  for (let i = 0; i < n; i++) {
    const name = N.attrName(s.id, i);
    const value = N.attrValue(s.id, i);
    const code = N.attrNs(s.id, i);
    let prefix = null, localName = name, namespaceURI = null;
    const colon = name.indexOf(':');
    if (code !== 0) {
      namespaceURI = codeToNS[code];
      if (colon > 0) { prefix = name.slice(0, colon); localName = name.slice(colon + 1); }
    }
    const a = newAttr(s.doc, localName, namespaceURI, prefix, value);
    slotOf(a).element = el;
    apply(arrayPush, list, [a]);
  }
  s.attrObjs = list;
  return list;
};
function nativeAttrName(a) { return qualifiedName(a); }
function appendAttr(attr, el) {
  const s = slotOf(el), as = slotOf(attr);
  const list = attrsOf(el);
  apply(arrayPush, list, [attr]);
  as.element = el;
  as.doc = s.doc;
  N.attrPut(s.id, nativeAttrName(attr), as.value, as.namespaceURI === null ? 0 : nsToCode(as.namespaceURI));
}
function attributeChangedSteps(el, localName, oldValue, value, namespace) {
  queueMutationRecord('attributes', el, localName, namespace, oldValue, [], [], null, null);
  const s = slotOf(el);
  if (s.customState === 'custom') enqueueCallbackReaction(el, 'attributeChangedCallback', [localName, oldValue, value, namespace]);
  if (namespace === null) elementAttributeChanged(el, localName, oldValue, value);
}
let elementAttributeChanged = (el, name, oldValue, value) => {};
function changeAttribute(attr, value) {
  const as = slotOf(attr);
  const el = as.element;
  const old = as.value;
  if (el !== null) attributeChangedSteps(el, as.localName, old, value, as.namespaceURI);
  as.value = value;
  if (el !== null) {
    const idx = attrsOf(el).indexOf(attr);
    N.attrSetAt(slotOf(el).id, idx, value);
  }
}
setAttrValue = function (attr, value) { changeAttribute(attr, value); };
function appendAttribute(attr, el) {
  attributeChangedSteps(el, slotOf(attr).localName, null, slotOf(attr).value, slotOf(attr).namespaceURI);
  appendAttr(attr, el);
}
function removeAttribute(attr) {
  const as = slotOf(attr);
  const el = as.element;
  const list = attrsOf(el);
  const idx = list.indexOf(attr);
  attributeChangedSteps(el, as.localName, as.value, null, as.namespaceURI);
  apply(arraySplice, list, [idx, 1]);
  as.element = null;
  N.attrDelAt(slotOf(el).id, idx);
}
function replaceAttribute(oldAttr, newAttr_) {
  const os = slotOf(oldAttr), ns_ = slotOf(newAttr_);
  const el = os.element;
  const list = attrsOf(el);
  const idx = list.indexOf(oldAttr);
  attributeChangedSteps(el, os.localName, os.value, ns_.value, os.namespaceURI);
  list[idx] = newAttr_;
  os.element = null;
  ns_.element = el;
  ns_.doc = slotOf(el).doc;
  // rewrite the native slot in place: delete then put keeps indices consistent
  N.attrDelAt(slotOf(el).id, idx);
  const code = ns_.namespaceURI === null ? 0 : nsToCode(ns_.namespaceURI);
  N.attrPut(slotOf(el).id, nativeAttrName(newAttr_), ns_.value, code);
  // attrPut appends; move the entry back to index `idx` by rebuilding the tail
  const total = list.length;
  for (let i = idx + 1; i < total; i++) {
    const a = list[i];
    N.attrDelAt(slotOf(el).id, idx + 1);
    N.attrPut(slotOf(el).id, nativeAttrName(a), slotOf(a).value, slotOf(a).namespaceURI === null ? 0 : nsToCode(slotOf(a).namespaceURI));
  }
}
function getAttributeByName(el, qname) {
  const s = slotOf(el);
  let name = qname;
  if (s.namespaceURI === HTML_NS && isHTMLDocument(s.doc)) name = asciiLowercase(name);
  const list = attrsOf(el);
  for (const a of list) if (qualifiedName(a) === name) return a;
  return null;
}
function getAttributeByNS(el, namespace, localName) {
  const ns = namespace === '' ? null : namespace;
  for (const a of attrsOf(el)) { const as = slotOf(a); if (as.namespaceURI === ns && as.localName === localName) return a; }
  return null;
}
function getAttributeValue_(el, name) {
  const s = slotOf(el);
  if (s.attrObjs === null) { const v = N.attrGet(s.id, name); return v === undefined ? null : v; }
  const a = getAttributeByName(el, name);
  return a === null ? null : slotOf(a).value;
}
getAttributeValue = getAttributeValue_;
function setAttributeValue(el, localName, value, prefix = null, namespace = null) {
  const a = getAttributeByNS(el, namespace === null ? '' : namespace, localName);
  if (a === null) {
    const attr = newAttr(slotOf(el).doc, localName, namespace, prefix, value);
    appendAttribute(attr, el);
  } else changeAttribute(a, value);
}
function asciiLowercase(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) { const c = s[i]; out += c >= 'A' && c <= 'Z' ? String.fromCharCode(c.charCodeAt(0) + 32) : c; }
  return out;
}
function asciiUppercase(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) { const c = s[i]; out += c >= 'a' && c <= 'z' ? String.fromCharCode(c.charCodeAt(0) - 32) : c; }
  return out;
}

// --- Element

function Element() { throw new TypeError('Illegal constructor'); }
iface('Element', Element, Node);
function elSlot(o) { const s = slotOf(o); if (!s || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
elementTagName = function (el) {
  const s = slotOf(el);
  const q = s.prefix === null ? s.localName : s.prefix + ':' + s.localName;
  return s.namespaceURI === HTML_NS && isHTMLDocument(s.doc) ? asciiUppercase(q) : q;
};

// Which interface object an element of this name and namespace gets; filled in by the HTML/SVG definitions.
let interfaceFor = (localName, ns) => Element.prototype;
function createElementWrapper(id, doc) {
  const name = N.name(id);
  const ns = codeToNS[N.ns(id)];
  const w = create(interfaceFor(name, ns));
  const s = setSlot(w, newNodeSlot(id, ELEMENT_NODE, doc));
  s.localName = name; s.namespaceURI = ns; s.prefix = null; s.attrObjs = null; s.isValue = null; s.customState = ns === HTML_NS && isValidCustomElementName(name) ? 'undefined' : 'uncustomized';
  s.shadowRoot = null; s.classList = null;
  return register(w, id);
}
createElementInternal = function (doc, localName, namespace, prefix, isValue, sync) {
  const id = N.mkElement(localName, namespace === null ? 4 : nsToCode(namespace));
  const w = create(interfaceFor(localName, namespace));
  const s = setSlot(w, newNodeSlot(id, ELEMENT_NODE, doc));
  s.localName = localName; s.namespaceURI = namespace; s.prefix = prefix; s.attrObjs = []; s.isValue = isValue; s.customState = 'uncustomized';
  s.shadowRoot = null; s.classList = null;
  register(w, id);
  return w;
};

operations(Element.prototype, {
  hasAttributes() { elSlot(this); return attrsOf(this).length > 0; },
  getAttributeNames() { elSlot(this); return attrsOf(this).map(qualifiedName); },
  getAttribute(qualifiedName_) {
    elSlot(this);
    required(arguments, 1, 'getAttribute');
    const a = getAttributeByName(this, toDOMString(qualifiedName_));
    return a === null ? null : slotOf(a).value;
  },
  getAttributeNS(namespace, localName) {
    elSlot(this);
    required(arguments, 2, 'getAttributeNS');
    const ns = namespace === null || namespace === undefined ? '' : toDOMString(namespace);
    const a = getAttributeByNS(this, ns, toDOMString(localName));
    return a === null ? null : slotOf(a).value;
  },
  setAttribute(qualifiedName_, value) {
    const s = elSlot(this);
    required(arguments, 2, 'setAttribute');
    let name = toDOMString(qualifiedName_);
    const v = toDOMString(value);
    if (!isValidName(name)) throw domError('InvalidCharacterError', "'" + name + "' is not a valid attribute name");
    if (s.namespaceURI === HTML_NS && isHTMLDocument(s.doc)) name = asciiLowercase(name);
    const attr = getAttributeByName(this, name);
    if (attr === null) {
      appendAttribute(newAttr(s.doc, name, null, null, v), this);
      return;
    }
    changeAttribute(attr, v);
  },
  setAttributeNS(namespace, qualifiedName_, value) {
    const s = elSlot(this);
    required(arguments, 3, 'setAttributeNS');
    const ex = validateAndExtract(namespace, qualifiedName_);
    const v = toDOMString(value);
    const attr = getAttributeByNS(this, ex.namespace === null ? '' : ex.namespace, ex.localName);
    if (attr === null) { appendAttribute(newAttr(s.doc, ex.localName, ex.namespace, ex.prefix, v), this); return; }
    const as = slotOf(attr);
    as.prefix = ex.prefix;
    changeAttribute(attr, v);
  },
  removeAttribute(qualifiedName_) {
    elSlot(this);
    required(arguments, 1, 'removeAttribute');
    const a = getAttributeByName(this, toDOMString(qualifiedName_));
    if (a !== null) removeAttribute(a);
  },
  removeAttributeNS(namespace, localName) {
    elSlot(this);
    required(arguments, 2, 'removeAttributeNS');
    const a = getAttributeByNS(this, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName));
    if (a !== null) removeAttribute(a);
  },
  hasAttribute(qualifiedName_) {
    elSlot(this);
    required(arguments, 1, 'hasAttribute');
    return getAttributeByName(this, toDOMString(qualifiedName_)) !== null;
  },
  hasAttributeNS(namespace, localName) {
    elSlot(this);
    required(arguments, 2, 'hasAttributeNS');
    return getAttributeByNS(this, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName)) !== null;
  },
  toggleAttribute(qualifiedName_, force = undefined) {
    const s = elSlot(this);
    required(arguments, 1, 'toggleAttribute');
    let name = toDOMString(qualifiedName_);
    if (!isValidName(name)) throw domError('InvalidCharacterError', "'" + name + "' is not a valid attribute name");
    if (s.namespaceURI === HTML_NS && isHTMLDocument(s.doc)) name = asciiLowercase(name);
    const attr = getAttributeByName(this, name);
    if (attr === null) {
      if (force === undefined || force) { appendAttribute(newAttr(s.doc, name, null, null, ''), this); return true; }
      return false;
    }
    if (force === undefined || !force) { removeAttribute(attr); return false; }
    return true;
  },
  getAttributeNode(qualifiedName_) { elSlot(this); required(arguments, 1, 'getAttributeNode'); return getAttributeByName(this, toDOMString(qualifiedName_)); },
  getAttributeNodeNS(namespace, localName) {
    elSlot(this);
    required(arguments, 2, 'getAttributeNodeNS');
    return getAttributeByNS(this, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName));
  },
  setAttributeNode(attr) { elSlot(this); required(arguments, 1, 'setAttributeNode'); return setAttributeNodeImpl(this, attr, false); },
  setAttributeNodeNS(attr) { elSlot(this); required(arguments, 1, 'setAttributeNodeNS'); return setAttributeNodeImpl(this, attr, true); },
  removeAttributeNode(attr) {
    elSlot(this);
    required(arguments, 1, 'removeAttributeNode');
    if (!isObject(attr) || !slotOf(attr) || slotOf(attr).nodeType !== ATTRIBUTE_NODE) throw new TypeError("Failed to execute 'removeAttributeNode' on 'Element': parameter 1 is not of type 'Attr'.");
    if (slotOf(attr).element !== this) throw domError('NotFoundError', 'The attribute is not an attribute of this element');
    removeAttribute(attr);
    return attr;
  },
  closest(selectors) {
    elSlot(this);
    required(arguments, 1, 'closest');
    const r = N.closest(idOf(this), toDOMString(selectors));
    if (r === -2) throw domError('SyntaxError', "'" + selectors + "' is not a valid selector");
    return wrap(r);
  },
  matches(selectors) {
    elSlot(this);
    required(arguments, 1, 'matches');
    const r = N.matches(idOf(this), toDOMString(selectors));
    if (r === null) throw domError('SyntaxError', "'" + selectors + "' is not a valid selector");
    return r;
  },
  webkitMatchesSelector(selectors) { return Element.prototype.matches.call(this, selectors); },
  getElementsByTagName(qualifiedName_) {
    elSlot(this);
    required(arguments, 1, 'getElementsByTagName');
    return collectionByTagName(this, toDOMString(qualifiedName_));
  },
  getElementsByTagNameNS(namespace, localName) {
    elSlot(this);
    required(arguments, 2, 'getElementsByTagNameNS');
    return collectionByTagNameNS(this, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName));
  },
  getElementsByClassName(classNames) {
    elSlot(this);
    required(arguments, 1, 'getElementsByClassName');
    return collectionByClassName(this, toDOMString(classNames));
  },
  insertAdjacentElement(where, element) {
    elSlot(this);
    required(arguments, 2, 'insertAdjacentElement');
    if (!isObject(element) || !slotOf(element) || slotOf(element).nodeType !== ELEMENT_NODE) throw new TypeError("Failed to execute 'insertAdjacentElement' on 'Element': parameter 2 is not of type 'Element'.");
    return insertAdjacent(this, toDOMString(where), element);
  },
  insertAdjacentText(where, data) {
    elSlot(this);
    required(arguments, 2, 'insertAdjacentText');
    const text = createTextNode(slotOf(this).doc, toDOMString(data));
    insertAdjacent(this, toDOMString(where), text);
  }
});
function insertAdjacent(el, where, node) {
  switch (asciiLowercase(where)) {
    case 'beforebegin': { const p = parentNode(el); if (p === null) return null; preInsert(node, p, el); return node; }
    case 'afterbegin': preInsert(node, el, firstChild(el)); return node;
    case 'beforeend': preInsert(node, el, null); return node;
    case 'afterend': { const p = parentNode(el); if (p === null) return null; preInsert(node, p, nextSibling(el)); return node; }
    default: throw domError('SyntaxError', "The value provided ('" + where + "') is not one of 'beforebegin', 'afterbegin', 'beforeend', or 'afterend'.");
  }
}
function setAttributeNodeImpl(el, attr, ns) {
  if (!isObject(attr) || !slotOf(attr) || slotOf(attr).nodeType !== ATTRIBUTE_NODE) throw new TypeError("Failed to execute 'setAttributeNode' on 'Element': parameter 1 is not of type 'Attr'.");
  const as = slotOf(attr);
  if (as.element !== null && as.element !== el) throw domError('InUseAttributeError', 'The attribute is already in use');
  const old = ns ? getAttributeByNS(el, as.namespaceURI === null ? '' : as.namespaceURI, as.localName) : getAttributeByName(el, qualifiedName(attr));
  if (old === attr) return attr;
  if (old !== null) replaceAttribute(old, attr);
  else appendAttribute(attr, el);
  return old;
}
installChildNode(Element.prototype);
installNonDocumentTypeChildNode(Element.prototype);
installParentNode(Element.prototype);

attributes(Element.prototype, {
  namespaceURI: { get() { return elSlot(this).namespaceURI; } },
  prefix: { get() { return elSlot(this).prefix; } },
  localName: { get() { return elSlot(this).localName; } },
  tagName: { get() { elSlot(this); return elementTagName(this); } },
  id: { get() { elSlot(this); const v = getAttributeValue(this, 'id'); return v === null ? '' : v; }, set(v) { elSlot(this); setAttributeValue(this, 'id', toDOMString(v)); } },
  className: { get() { elSlot(this); const v = getAttributeValue(this, 'class'); return v === null ? '' : v; }, set(v) { elSlot(this); setAttributeValue(this, 'class', toDOMString(v)); } },
  classList: { get() { return classListOf(this); }, set(v) { elSlot(this); this.classList.value = v; } },
  slot: { get() { elSlot(this); const v = getAttributeValue(this, 'slot'); return v === null ? '' : v; }, set(v) { elSlot(this); setAttributeValue(this, 'slot', toDOMString(v)); } },
  attributes: { get() { return namedNodeMapOf(this); } },
  innerHTML: {
    get() { elSlot(this); return N.innerGet(idOf(this)); },
    set(v) { elSlot(this); setInnerHTML(this, v === null ? '' : toDOMString(v)); }
  },
  outerHTML: {
    get() { elSlot(this); return N.outerGet(idOf(this)); },
    set(v) {
      elSlot(this);
      const parent = parentNode(this);
      if (parent === null) return;
      if (nodeType(parent) === DOCUMENT_NODE) throw domError('NoModificationAllowedError', 'Modifications are not allowed for this document');
      let ctx = parent;
      if (nodeType(ctx) === DOCUMENT_FRAGMENT_NODE) ctx = createElementInternal(slotOf(this).doc, 'body', HTML_NS, null, null, false);
      const frag = parseFragment(ctx, toDOMString(v));
      replaceChild(frag, this, parent);
    }
  }
});
let classListOf = el => null;
let namedNodeMapOf = el => null;
let collectionByTagName = () => null;
let collectionByTagNameNS = () => null;
let collectionByClassName = () => null;
let isHTMLDocument = doc => true;

// innerHTML / fragment parsing: the markup is parsed natively in the context element, the new nodes are adopted into the document.
function parseFragment(context, markup) {
  const tmp = createFragmentNode(slotOf(context).doc);
  const holder = createElementInternal(slotOf(context).doc, slotOf(context).localName, slotOf(context).namespaceURI, null, null, false);
  N.innerSet(idOf(holder), markup);
  markScriptsStarted(idOf(holder));
  let id = nFirst(idOf(holder));
  const kids = [];
  while (id >= 0) { apply(arrayPush, kids, [id]); id = nNext(id); }
  for (const kid of kids) {
    const w = wrap(kid);
    N.remove(kid);
    slotOf(w).doc = slotOf(context).doc;
    N.insert(idOf(tmp), kid, -1);
  }
  return tmp;
}
function setInnerHTML(el, markup, ctx = el) {
  const frag = parseFragment(ctx, markup);
  replaceAllWith(el, frag);
}

// --- NamedNodeMap

function NamedNodeMap() { throw new TypeError('Illegal constructor'); }
iface('NamedNodeMap', NamedNodeMap, null);
function mapSlot(o) { const s = slotOf(o); if (!s || !s.isNamedNodeMap) illegal(); return s; }
namedNodeMapOf = function (el) {
  const s = slotOf(el);
  if (s.attributesMap) return s.attributesMap;
  const state = { isNamedNodeMap: true, element: el };
  s.attributesMap = legacyObject(NamedNodeMap.prototype, {
    length: () => attrsOf(el).length,
    item: i => { const l = attrsOf(el); return i < l.length ? l[i] : null; },
    named: name => { const a = getAttributeByName(el, name); return a === null ? undefined : a; },
    names: () => attrsOf(el).map(qualifiedName),
    enumerableNamed: false
  }, state);
  return s.attributesMap;
};
operations(NamedNodeMap.prototype, {
  item(index) { const s = mapSlot(this); required(arguments, 1, 'item'); const l = attrsOf(s.element); const i = toUnsignedLong(index); return i < l.length ? l[i] : null; },
  getNamedItem(qualifiedName_) { const s = mapSlot(this); required(arguments, 1, 'getNamedItem'); return getAttributeByName(s.element, toDOMString(qualifiedName_)); },
  getNamedItemNS(namespace, localName) { const s = mapSlot(this); required(arguments, 2, 'getNamedItemNS'); return getAttributeByNS(s.element, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName)); },
  setNamedItem(attr) { const s = mapSlot(this); required(arguments, 1, 'setNamedItem'); return setAttributeNodeImpl(s.element, attr, false); },
  setNamedItemNS(attr) { const s = mapSlot(this); required(arguments, 1, 'setNamedItemNS'); return setAttributeNodeImpl(s.element, attr, true); },
  removeNamedItem(qualifiedName_) {
    const s = mapSlot(this);
    required(arguments, 1, 'removeNamedItem');
    const a = getAttributeByName(s.element, toDOMString(qualifiedName_));
    if (a === null) throw domError('NotFoundError', 'The attribute was not found');
    removeAttribute(a);
    return a;
  },
  removeNamedItemNS(namespace, localName) {
    const s = mapSlot(this);
    required(arguments, 2, 'removeNamedItemNS');
    const a = getAttributeByNS(s.element, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName));
    if (a === null) throw domError('NotFoundError', 'The attribute was not found');
    removeAttribute(a);
    return a;
  }
});
attributes(NamedNodeMap.prototype, { length: { get() { return attrsOf(mapSlot(this).element).length; } } });
defineProperty(NamedNodeMap.prototype, symIterator, { value: Array.prototype.values, writable: true, enumerable: false, configurable: true });

// --- DOMTokenList

function DOMTokenList() { throw new TypeError('Illegal constructor'); }
iface('DOMTokenList', DOMTokenList, null);
function tlSlot(o) { const s = slotOf(o); if (!s || !s.isTokenList) illegal(); return s; }
function isASCIIWhitespace(c) { return c === ' ' || c === '\t' || c === '\n' || c === '\f' || c === '\r'; }
function parseTokens(value) {
  const tokens = [];
  let i = 0;
  while (i < value.length) {
    while (i < value.length && isASCIIWhitespace(value[i])) i++;
    let start = i;
    while (i < value.length && !isASCIIWhitespace(value[i])) i++;
    if (i > start) { const t = value.slice(start, i); if (tokens.indexOf(t) < 0) apply(arrayPush, tokens, [t]); }
  }
  return tokens;
}
function tokensOf(s) {
  const v = getAttributeValue(s.element, s.attribute);
  return v === null ? [] : parseTokens(v);
}
function updateTokens(s, tokens) {
  const v = getAttributeValue(s.element, s.attribute);
  if (v === null && tokens.length === 0) return;
  setAttributeValue(s.element, s.attribute, tokens.join(' '));
}
function validateToken(t) {
  if (t === '') throw domError('SyntaxError', 'The token provided must not be empty.');
  for (let i = 0; i < t.length; i++) if (isASCIIWhitespace(t[i])) throw domError('InvalidCharacterError', "The token provided ('" + t + "') contains HTML space characters, which are not valid in tokens.");
}
function makeTokenList(el, attribute, supported) {
  const state = { isTokenList: true, element: el, attribute, supported };
  return legacyObject(DOMTokenList.prototype, {
    length: () => tokensOf(state).length,
    item: i => { const t = tokensOf(state); return i < t.length ? t[i] : null; }
  }, state);
}
classListOf = function (el) {
  const s = elSlot(el);
  if (!s.classList) s.classList = makeTokenList(el, 'class', null);
  return s.classList;
};
operations(DOMTokenList.prototype, {
  item(index) { const s = tlSlot(this); required(arguments, 1, 'item'); const t = tokensOf(s); const i = toUnsignedLong(index); return i < t.length ? t[i] : null; },
  contains(token) { const s = tlSlot(this); required(arguments, 1, 'contains'); return tokensOf(s).indexOf(toDOMString(token)) >= 0; },
  add(...tokens) {
    const s = tlSlot(this);
    const ts = tokens.map(toDOMString);
    for (const t of ts) validateToken(t);
    const list = tokensOf(s);
    for (const t of ts) if (list.indexOf(t) < 0) apply(arrayPush, list, [t]);
    updateTokens(s, list);
  },
  remove(...tokens) {
    const s = tlSlot(this);
    const ts = tokens.map(toDOMString);
    for (const t of ts) validateToken(t);
    const list = tokensOf(s).filter(x => ts.indexOf(x) < 0);
    updateTokens(s, list);
  },
  toggle(token, force = undefined) {
    const s = tlSlot(this);
    required(arguments, 1, 'toggle');
    const t = toDOMString(token);
    validateToken(t);
    const list = tokensOf(s);
    if (list.indexOf(t) >= 0) {
      if (force === undefined || !force) { updateTokens(s, list.filter(x => x !== t)); return false; }
      return true;
    }
    if (force === undefined || force) { apply(arrayPush, list, [t]); updateTokens(s, list); return true; }
    return false;
  },
  replace(token, newToken) {
    const s = tlSlot(this);
    required(arguments, 2, 'replace');
    const t = toDOMString(token), n = toDOMString(newToken);
    validateToken(t); validateToken(n);
    const list = tokensOf(s);
    const i = list.indexOf(t);
    if (i < 0) return false;
    const j = list.indexOf(n);
    if (j >= 0 && j !== i) {
      const out = [];
      for (let k = 0; k < list.length; k++) {
        if (k === i) { if (j > i) apply(arrayPush, out, [n]); }
        else if (k === j) { if (j < i) apply(arrayPush, out, [n]); }
        else apply(arrayPush, out, [list[k]]);
      }
      updateTokens(s, out);
      return true;
    }
    list[i] = n;
    updateTokens(s, list);
    return true;
  },
  supports(token) {
    const s = tlSlot(this);
    required(arguments, 1, 'supports');
    if (s.supported === null) throw new TypeError('The associated attribute has no supported tokens defined');
    return s.supported.indexOf(asciiLowercase(toDOMString(token))) >= 0;
  },
  toString() { const s = tlSlot(this); const v = getAttributeValue(s.element, s.attribute); return v === null ? '' : v; },
  forEach(callback, thisArg = undefined) {
    const s = tlSlot(this);
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError("Failed to execute 'forEach' on 'DOMTokenList': parameter 1 is not of type 'Function'.");
    const list = tokensOf(s);
    for (let i = 0; i < list.length; i++) apply(callback, thisArg, [list[i], i, this]);
  },
  keys() { tlSlot(this); return Array.prototype.keys.call(this); },
  values() { tlSlot(this); return Array.prototype.values.call(this); },
  entries() { tlSlot(this); return Array.prototype.entries.call(this); }
});
attributes(DOMTokenList.prototype, {
  length: { get() { return tokensOf(tlSlot(this)).length; } },
  value: {
    get() { const s = tlSlot(this); const v = getAttributeValue(s.element, s.attribute); return v === null ? '' : v; },
    set(v) { const s = tlSlot(this); setAttributeValue(s.element, s.attribute, toDOMString(v)); }
  }
});
defineProperty(DOMTokenList.prototype, symIterator, { value: DOMTokenList.prototype.values, writable: true, enumerable: false, configurable: true });
defineProperty(DOMTokenList.prototype, 'toString', { value: DOMTokenList.prototype.toString, writable: true, enumerable: true, configurable: true });
