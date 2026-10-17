// The DOM Standard's node tree over the native node table: Node, Element, Attr, CharacterData, DocumentType, DocumentFragment,
// with the pre-insertion checks, insertion, removal, adoption, cloning, normalisation and comparison algorithms.

const HTML_NS = 'http://www.w3.org/1999/xhtml';
const SVG_NS = 'http://www.w3.org/2000/svg';
const MATHML_NS = 'http://www.w3.org/1998/Math/MathML';
const XML_NS = 'http://www.w3.org/XML/1998/namespace';
const XMLNS_NS = 'http://www.w3.org/2000/xmlns/';
const XLINK_NS = 'http://www.w3.org/1999/xlink';
const codeToNS = [HTML_NS, SVG_NS, MATHML_NS, XLINK_NS, XML_NS, XMLNS_NS];
function nsToCode(ns) {
  if (ns === HTML_NS) return 0;
  if (ns === SVG_NS) return 1;
  if (ns === MATHML_NS) return 2;
  if (ns === XLINK_NS) return 3;
  if (ns === XMLNS_NS) return 5;
  return 4;
}

// --- wrappers: one platform object per native node id

const nParent = id => id < 0 ? -1 : N.parent(id);
const nFirst = id => id < 0 ? -1 : N.first(id);
const nLast = id => id < 0 ? -1 : N.last(id);
const nNext = id => id < 0 ? -1 : N.next(id);
const nPrev = id => id < 0 ? -1 : N.prev(id);
const wrappers = new Map();
const mapGet = Map.prototype.get;
const mapSet = Map.prototype.set;
const mapDelete = Map.prototype.delete;

const ELEMENT_NODE = 1, ATTRIBUTE_NODE = 2, TEXT_NODE = 3, CDATA_SECTION_NODE = 4, PROCESSING_INSTRUCTION_NODE = 7,
  COMMENT_NODE = 8, DOCUMENT_NODE = 9, DOCUMENT_TYPE_NODE = 10, DOCUMENT_FRAGMENT_NODE = 11;

function newNodeSlot(id, nodeType, doc) {
  return { isNode: true, isTarget: true, listeners: [], id, nodeType, doc, getTheParent: nodeGetTheParent, registrations: null };
}
function nodeGetTheParent(event) {
  if (isSlotable(this)) { const sl = assignedSlotOf(this); if (sl) return sl; }
  const p = parentNode(this);
  if (p !== null) return p;
  if (isShadowRoot(this)) {
    const path = slotOf(event).path;
    if (slotOf(event).composed || (path.length && rootNode(path[0].invocationTarget) !== this)) return shadowHost(this);
    return null;
  }
  if (nodeType(this) === DOCUMENT_NODE && slotOf(event).type !== 'load' && slotOf(this).browsingContext) return global;
  return null;
}
function register(wrapper, id) { apply(mapSet, wrappers, [id, wrapper]); return wrapper; }

// The wrapper of native node `id`, made on first use for nodes the parser or serializer produced.
function wrap(id) {
  if (id < 0) return null;
  let w = apply(mapGet, wrappers, [id]);
  if (w !== undefined) return w;
  const kind = N.kind(id);
  let top = id, p = nParent(top);
  while (p >= 0) { top = p; p = nParent(top); }
  let doc = null;
  const topWrapper = apply(mapGet, wrappers, [top]);
  if (topWrapper !== undefined) {
    const ts = slotOf(topWrapper);
    doc = ts.nodeType === DOCUMENT_NODE ? topWrapper : ts.doc;
  }
  if (doc === null) doc = mainDocument;
  if (kind === 2) w = createElementWrapper(id, doc);
  else if (kind === 3) { w = create(Text.prototype); setSlot(w, newNodeSlot(id, TEXT_NODE, doc)); }
  else if (kind === 4) { w = create(Comment.prototype); setSlot(w, newNodeSlot(id, COMMENT_NODE, doc)); }
  else if (kind === 1) {
    w = create(DocumentType.prototype);
    const s = setSlot(w, newNodeSlot(id, DOCUMENT_TYPE_NODE, doc));
    s.publicId = ''; s.systemId = '';
  } else if (kind === 5) { w = create(DocumentFragment.prototype); setSlot(w, newNodeSlot(id, DOCUMENT_FRAGMENT_NODE, doc)); }
  else throw new TypeError('unexpected node kind ' + kind);
  return register(w, id);
}
function idOf(node) { return slotOf(node).id; }
function nodeSlot(o) { const s = slotOf(o); if (!s || !s.isNode) illegal(); return s; }
function isNode(o) { if (!isObject(o)) return false; const s = slotOf(o); return !!(s && s.isNode); }
function nodeType(o) { return slotOf(o).nodeType; }
function ownerDoc(o) { const s = slotOf(o); return s.nodeType === DOCUMENT_NODE ? null : s.doc; }

isNodeObject = o => isObject(o) && o !== global && isNode(o);

// --- tree reads

function parentNode(o) { return wrap(nParent(idOf(o))); }
function parentElement(o) { const p = parentNode(o); return p !== null && nodeType(p) === ELEMENT_NODE ? p : null; }
function firstChild(o) { return wrap(nFirst(idOf(o))); }
function lastChild(o) { return wrap(nLast(idOf(o))); }
function nextSibling(o) { return wrap(nNext(idOf(o))); }
function previousSibling(o) { return wrap(nPrev(idOf(o))); }
function childrenOf(o) {
  const out = [];
  let id = nFirst(idOf(o));
  while (id >= 0) { apply(arrayPush, out, [wrap(id)]); id = nNext(id); }
  return out;
}
function childCount(o) { let n = 0, id = nFirst(idOf(o)); while (id >= 0) { n++; id = nNext(id); } return n; }
function indexOfChild(o) { let n = 0, id = nPrev(idOf(o)); while (id >= 0) { n++; id = nPrev(id); } return n; }
function isDescendantNative(ancestorId, id) {
  while (id >= 0) { if (id === ancestorId) return true; id = nParent(id); }
  return false;
}
function rootNode(o) {
  let id = idOf(o), p = nParent(id);
  while (p >= 0) { id = p; p = nParent(id); }
  return wrap(id);
}
function inclusiveAncestors(o) {
  const out = [];
  let id = idOf(o);
  while (id >= 0) { apply(arrayPush, out, [wrap(id)]); id = nParent(id); }
  return out;
}
function isConnected(o) { return rootNode(o) === slotOf(o).doc || nodeType(rootNode(o)) === DOCUMENT_NODE; }
function isInclusiveAncestor(a, b) { return isDescendantNative(idOf(a), idOf(b)); }

rootOf = o => rootNode(o);

// Next node in tree order after `o` within `root` (or the whole tree), skipping descendants if `skip`.
function nextInTree(o, root, skipChildren) {
  let id = idOf(o);
  if (!skipChildren) { const f = nFirst(id); if (f >= 0) return wrap(f); }
  const rootId = root ? idOf(root) : -1;
  while (id >= 0 && id !== rootId) {
    const n = nNext(id);
    if (n >= 0) return wrap(n);
    id = nParent(id);
  }
  return null;
}
function descendantsOf(o) {
  const out = [];
  let n = nextInTree(o, o, false);
  while (n !== null) { apply(arrayPush, out, [n]); n = nextInTree(n, o, false); }
  return out;
}

// --- text content helpers

function descendantTextContent(o) {
  let out = '';
  let n = nextInTree(o, o, false);
  while (n !== null) {
    if (nodeType(n) === TEXT_NODE || nodeType(n) === CDATA_SECTION_NODE) out += N.value(idOf(n));
    n = nextInTree(n, o, false);
  }
  return out;
}

// --- Node

function Node() { throw new TypeError('Illegal constructor'); }
iface('Node', Node, EventTarget);
constants(Node, {
  ELEMENT_NODE: 1, ATTRIBUTE_NODE: 2, TEXT_NODE: 3, CDATA_SECTION_NODE: 4, ENTITY_REFERENCE_NODE: 5, ENTITY_NODE: 6,
  PROCESSING_INSTRUCTION_NODE: 7, COMMENT_NODE: 8, DOCUMENT_NODE: 9, DOCUMENT_TYPE_NODE: 10, DOCUMENT_FRAGMENT_NODE: 11,
  NOTATION_NODE: 12, DOCUMENT_POSITION_DISCONNECTED: 1, DOCUMENT_POSITION_PRECEDING: 2, DOCUMENT_POSITION_FOLLOWING: 4,
  DOCUMENT_POSITION_CONTAINS: 8, DOCUMENT_POSITION_CONTAINED_BY: 16, DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: 32
});

function nodeName(o) {
  const s = slotOf(o);
  switch (s.nodeType) {
    case ELEMENT_NODE: return elementTagName(o);
    case ATTRIBUTE_NODE: return s.prefix === null ? s.localName : s.prefix + ':' + s.localName;
    case TEXT_NODE: return '#text';
    case CDATA_SECTION_NODE: return '#cdata-section';
    case PROCESSING_INSTRUCTION_NODE: return s.target;
    case COMMENT_NODE: return '#comment';
    case DOCUMENT_NODE: return '#document';
    case DOCUMENT_TYPE_NODE: return s.name;
    default: return '#document-fragment';
  }
}
function nodeValueOf(o) {
  const s = slotOf(o);
  switch (s.nodeType) {
    case ATTRIBUTE_NODE: return s.value;
    case TEXT_NODE: case CDATA_SECTION_NODE: case COMMENT_NODE: return N.value(s.id);
    case PROCESSING_INSTRUCTION_NODE: return N.value(s.id);
    default: return null;
  }
}
function textContentOf(o) {
  const s = slotOf(o);
  switch (s.nodeType) {
    case DOCUMENT_NODE: case DOCUMENT_TYPE_NODE: return null;
    case DOCUMENT_FRAGMENT_NODE: case ELEMENT_NODE: return descendantTextContent(o);
    case ATTRIBUTE_NODE: return s.value;
    default: return N.value(s.id);
  }
}
function setCharacterData(o, data) {
  const s = slotOf(o);
  N.setValue(s.id, data);
}

function replaceAllWith(parent, node) {
  const removed = childrenOf(parent);
  let added = [];
  if (node !== null) added = nodeType(node) === DOCUMENT_FRAGMENT_NODE ? childrenOf(node) : [node];
  if (node !== null) adopt(node, ownerDocOrSelf(parent));
  for (const c of removed) removeNode(c, true);
  if (node !== null) insertNode(node, parent, null, true);
  queueMutationRecord('childList', parent, null, null, null, added, removed, null, null);
}

operations(Node.prototype, {
  getRootNode(options = undefined) {
    nodeSlot(this);
    const composed = options !== undefined && options !== null && !!options.composed;
    let root = rootNode(this);
    if (composed) { while (isShadowRoot(root)) root = shadowHost(root).getRootNode ? rootNode(shadowHost(root)) : root; }
    return root;
  },
  hasChildNodes() { nodeSlot(this); return nFirst(idOf(this)) >= 0; },
  normalize() {
    nodeSlot(this);
    const textNodes = [];
    for (const d of descendantsOf(this)) if (nodeType(d) === TEXT_NODE) apply(arrayPush, textNodes, [d]);
    for (const node of textNodes) {
      if (!isInclusiveAncestor(this, node)) continue;
      let length = N.value(idOf(node)).length;
      if (length === 0) { removeNode(node, false); continue; }
      let data = '';
      const contiguous = [];
      let sib = nextSibling(node);
      while (sib !== null && nodeType(sib) === TEXT_NODE) { apply(arrayPush, contiguous, [sib]); data += N.value(idOf(sib)); sib = nextSibling(sib); }
      if (contiguous.length === 0) continue;
      replaceData(node, length, 0, data);
      for (const cur of contiguous) {
        adjustRangesForMerge(cur, node, length);
        length += N.value(idOf(cur)).length;
      }
      for (const cur of contiguous) removeNode(cur, false);
    }
  },
  cloneNode(subtree = false) {
    nodeSlot(this);
    if (isShadowRoot(this)) throw domError('NotSupportedError', 'ShadowRoot nodes are not clonable');
    return cloneNode(this, undefined, !!subtree);
  },
  isEqualNode(other = null) {
    nodeSlot(this);
    if (other !== null && !isNode(other)) throw new TypeError("Failed to execute 'isEqualNode' on 'Node': parameter 1 is not of type 'Node'.");
    return other !== null && equalNodes(this, other);
  },
  isSameNode(other = null) { nodeSlot(this); return this === other; },
  compareDocumentPosition(other) {
    nodeSlot(this);
    required(arguments, 1, 'compareDocumentPosition');
    if (!isNode(other)) throw new TypeError("Failed to execute 'compareDocumentPosition' on 'Node': parameter 1 is not of type 'Node'.");
    return comparePosition(this, other);
  },
  contains(other = null) {
    nodeSlot(this);
    if (other !== null && !isNode(other)) throw new TypeError("Failed to execute 'contains' on 'Node': parameter 1 is not of type 'Node'.");
    return other !== null && isInclusiveAncestorGeneric(this, other);
  },
  lookupPrefix(namespace) {
    nodeSlot(this);
    const ns = namespace === null || namespace === undefined || namespace === '' ? null : toDOMString(namespace);
    if (ns === null) return null;
    const s = slotOf(this);
    let el = null;
    if (s.nodeType === ELEMENT_NODE) el = this;
    else if (s.nodeType === DOCUMENT_NODE) el = documentElementOf(this);
    else if (s.nodeType === DOCUMENT_TYPE_NODE || s.nodeType === DOCUMENT_FRAGMENT_NODE) el = null;
    else if (s.nodeType === ATTRIBUTE_NODE) el = s.element;
    else el = parentElement(this);
    return el === null ? null : locatePrefix(el, ns);
  },
  lookupNamespaceURI(prefix) {
    nodeSlot(this);
    const p = prefix === null || prefix === undefined || prefix === '' ? null : toDOMString(prefix);
    return locateNamespace(this, p);
  },
  isDefaultNamespace(namespace) {
    nodeSlot(this);
    const ns = namespace === null || namespace === undefined || namespace === '' ? null : toDOMString(namespace);
    return locateNamespace(this, null) === ns;
  },
  insertBefore(node, child) {
    nodeSlot(this);
    required(arguments, 2, 'insertBefore');
    if (!acceptNode(node, ownerDocOrSelf(this))) throw new TypeError("Failed to execute 'insertBefore' on 'Node': parameter 1 is not of type 'Node'.");
    if (child !== null && !isNode(child)) throw new TypeError("Failed to execute 'insertBefore' on 'Node': parameter 2 is not of type 'Node'.");
    return preInsert(node, this, child);
  },
  appendChild(node) {
    nodeSlot(this);
    required(arguments, 1, 'appendChild');
    if (!acceptNode(node, ownerDocOrSelf(this))) throw new TypeError("Failed to execute 'appendChild' on 'Node': parameter 1 is not of type 'Node'.");
    return preInsert(node, this, null);
  },
  replaceChild(node, child) {
    nodeSlot(this);
    required(arguments, 2, 'replaceChild');
    if (!acceptNode(node, ownerDocOrSelf(this))) throw new TypeError("Failed to execute 'replaceChild' on 'Node': parameter 1 is not of type 'Node'.");
    if (!isNode(child)) throw new TypeError("Failed to execute 'replaceChild' on 'Node': parameter 2 is not of type 'Node'.");
    return replaceChild(node, child, this);
  },
  removeChild(child) {
    nodeSlot(this);
    required(arguments, 1, 'removeChild');
    if (!isNode(child)) throw new TypeError("Failed to execute 'removeChild' on 'Node': parameter 1 is not of type 'Node'.");
    return preRemove(child, this);
  }
});
attributes(Node.prototype, {
  nodeType: { get() { return nodeSlot(this).nodeType; } },
  nodeName: { get() { nodeSlot(this); return nodeName(this); } },
  baseURI: { get() { nodeSlot(this); return documentBaseURL(ownerDocOrSelf(this)); } },
  isConnected: { get() { nodeSlot(this); return isConnected(this); } },
  ownerDocument: { get() { return nodeSlot(this).nodeType === DOCUMENT_NODE ? null : nodeSlot(this).doc; } },
  parentNode: { get() { nodeSlot(this); return parentNode(this); } },
  parentElement: { get() { nodeSlot(this); return parentElement(this); } },
  childNodes: { get() { nodeSlot(this); return childNodesOf(this); } },
  firstChild: { get() { nodeSlot(this); return firstChild(this); } },
  lastChild: { get() { nodeSlot(this); return lastChild(this); } },
  previousSibling: { get() { nodeSlot(this); return previousSibling(this); } },
  nextSibling: { get() { nodeSlot(this); return nextSibling(this); } },
  nodeValue: {
    get() { nodeSlot(this); return nodeValueOf(this); },
    set(v) {
      nodeSlot(this);
      const value = v === null || v === undefined ? '' : toDOMString(v);
      const t = nodeType(this);
      if (t === ATTRIBUTE_NODE) setAttrValue(this, value);
      else if (t === TEXT_NODE || t === CDATA_SECTION_NODE || t === COMMENT_NODE || t === PROCESSING_INSTRUCTION_NODE) replaceData(this, 0, N.value(idOf(this)).length, value);
    }
  },
  textContent: {
    get() { nodeSlot(this); return textContentOf(this); },
    set(v) {
      nodeSlot(this);
      const value = v === null || v === undefined ? null : toDOMString(v);
      const t = nodeType(this);
      if (t === ELEMENT_NODE || t === DOCUMENT_FRAGMENT_NODE) {
        let node = null;
        if (value !== null && value !== '') node = createTextNode(ownerDocOrSelf(this), value);
        replaceAllWith(this, node);
      } else if (t === ATTRIBUTE_NODE) setAttrValue(this, value === null ? '' : value);
      else if (t === TEXT_NODE || t === CDATA_SECTION_NODE || t === COMMENT_NODE || t === PROCESSING_INSTRUCTION_NODE) replaceData(this, 0, N.value(idOf(this)).length, value === null ? '' : value);
    }
  }
});

function ownerDocOrSelf(o) { const s = slotOf(o); return s.nodeType === DOCUMENT_NODE ? o : s.doc; }
function isInclusiveAncestorGeneric(a, b) {
  const as = slotOf(a), bs = slotOf(b);
  if (as.nodeType === ATTRIBUTE_NODE || bs.nodeType === ATTRIBUTE_NODE) return a === b;
  return isInclusiveAncestor(a, b);
}

// --- namespace lookup

function locatePrefix(el, ns) {
  const s = slotOf(el);
  if (s.namespaceURI === ns && s.prefix !== null) return s.prefix;
  for (const a of attrsOf(el)) {
    const as = slotOf(a);
    if (as.prefix === 'xmlns' && as.value === ns) return as.localName;
  }
  const p = parentElement(el);
  return p === null ? null : locatePrefix(p, ns);
}
function locateNamespace(o, prefix) {
  const s = slotOf(o);
  switch (s.nodeType) {
    case ELEMENT_NODE: {
      if (s.namespaceURI !== null && s.prefix === prefix) return s.namespaceURI;
      for (const a of attrsOf(o)) {
        const as = slotOf(a);
        if (as.namespaceURI === XMLNS_NS && ((as.prefix === 'xmlns' && as.localName === prefix) || (prefix === null && as.prefix === null && as.localName === 'xmlns'))) {
          return as.value === '' ? null : as.value;
        }
      }
      if (prefix === 'xml') return XML_NS;
      if (prefix === 'xmlns') return XMLNS_NS;
      const p = parentElement(o);
      return p === null ? null : locateNamespace(p, prefix);
    }
    case DOCUMENT_NODE: {
      const de = documentElementOf(o);
      return de === null ? null : locateNamespace(de, prefix);
    }
    case DOCUMENT_TYPE_NODE: case DOCUMENT_FRAGMENT_NODE: return null;
    case ATTRIBUTE_NODE: return s.element === null ? null : locateNamespace(s.element, prefix);
    default: {
      const p = parentElement(o);
      return p === null ? null : locateNamespace(p, prefix);
    }
  }
}

// --- comparison

function equalNodes(a, b) {
  const sa = slotOf(a), sb = slotOf(b);
  if (sa.nodeType !== sb.nodeType) return false;
  switch (sa.nodeType) {
    case DOCUMENT_TYPE_NODE:
      if (sa.name !== sb.name || sa.publicId !== sb.publicId || sa.systemId !== sb.systemId) return false;
      break;
    case ELEMENT_NODE: {
      if (sa.namespaceURI !== sb.namespaceURI || sa.prefix !== sb.prefix || sa.localName !== sb.localName) return false;
      const aa = attrsOf(a), ab = attrsOf(b);
      if (aa.length !== ab.length) return false;
      for (const x of aa) {
        const xs = slotOf(x);
        let found = false;
        for (const y of ab) { const ys = slotOf(y); if (ys.namespaceURI === xs.namespaceURI && ys.localName === xs.localName && ys.value === xs.value) { found = true; break; } }
        if (!found) return false;
      }
      break;
    }
    case ATTRIBUTE_NODE:
      if (sa.namespaceURI !== sb.namespaceURI || sa.localName !== sb.localName || sa.value !== sb.value) return false;
      break;
    case PROCESSING_INSTRUCTION_NODE:
      if (sa.target !== sb.target || N.value(sa.id) !== N.value(sb.id)) return false;
      break;
    case TEXT_NODE: case COMMENT_NODE: case CDATA_SECTION_NODE:
      if (N.value(sa.id) !== N.value(sb.id)) return false;
      break;
  }
  if (sa.nodeType === ATTRIBUTE_NODE) return true;
  const ca = childrenOf(a), cb = childrenOf(b);
  if (ca.length !== cb.length) return false;
  for (let i = 0; i < ca.length; i++) if (!equalNodes(ca[i], cb[i])) return false;
  return true;
}
function comparePosition(a, b) {
  if (a === b) return 0;
  let node1 = b, node2 = a, attr1 = null, attr2 = null;
  if (nodeType(node1) === ATTRIBUTE_NODE) { attr1 = node1; node1 = slotOf(attr1).element; }
  if (nodeType(node2) === ATTRIBUTE_NODE) {
    attr2 = node2; node2 = slotOf(attr2).element;
    if (attr1 !== null && node1 !== null && node2 === node1) {
      for (const at of attrsOf(node2)) {
        if (at === attr1) return 32 | 2;
        if (at === attr2) return 32 | 4;
      }
    }
  }
  if (node1 === null || node2 === null || rootNode(node1) !== rootNode(node2)) return 1 | 32 | (uniqueOrder(b, a) ? 2 : 4);
  if ((node1 !== node2 && isInclusiveAncestor(node1, node2) && attr1 === null) || (node1 === node2 && attr2 !== null)) return 8 | 2;
  if ((node1 !== node2 && isInclusiveAncestor(node2, node1) && attr2 === null) || (node1 === node2 && attr1 !== null)) return 16 | 4;
  return precedes(node1, node2) ? 2 : 4;
}
let orderCounter = 0;
const orderIds = new WeakMap();
function uniqueOrder(x, y) {
  let ox = apply(slotGet, orderIds, [x]); if (ox === undefined) { ox = ++orderCounter; apply(slotSet, orderIds, [x, ox]); }
  let oy = apply(slotGet, orderIds, [y]); if (oy === undefined) { oy = ++orderCounter; apply(slotSet, orderIds, [y, oy]); }
  return ox < oy;
}
// Whether x precedes y in tree order (both in the same tree).
function precedes(x, y) {
  const px = inclusiveAncestors(x).reverse(), py = inclusiveAncestors(y).reverse();
  let i = 0;
  while (i < px.length && i < py.length && px[i] === py[i]) i++;
  if (i === px.length) return true;
  if (i === py.length) return false;
  let n = px[i];
  while (n !== null) { if (n === py[i]) return true; n = nextSibling(n); }
  return false;
}

// --- pre-insertion validity and mutation

function hostIncludingInclusiveAncestor(a, b) {
  let n = b;
  while (n !== null) {
    if (n === a) return true;
    const p = parentNode(n);
    if (p !== null) n = p;
    else n = isShadowRoot(n) ? shadowHost(n) : null;
  }
  return false;
}
function isElementNode(o) { return nodeType(o) === ELEMENT_NODE; }
function isCharacterData(t) { return t === TEXT_NODE || t === CDATA_SECTION_NODE || t === PROCESSING_INSTRUCTION_NODE || t === COMMENT_NODE; }

function ensurePreInsertionValidity(node, parent, child) {
  const pt = nodeType(parent);
  if (pt !== DOCUMENT_NODE && pt !== DOCUMENT_FRAGMENT_NODE && pt !== ELEMENT_NODE) throw domError('HierarchyRequestError', 'The parent node cannot have children');
  if (hostIncludingInclusiveAncestor(node, parent)) throw domError('HierarchyRequestError', 'The new child is an ancestor of the parent');
  if (child !== null && parentNode(child) !== parent) throw domError('NotFoundError', 'The reference child is not a child of the parent');
  const nt = nodeType(node);
  if (nt !== DOCUMENT_FRAGMENT_NODE && nt !== DOCUMENT_TYPE_NODE && nt !== ELEMENT_NODE && !isCharacterData(nt)) throw domError('HierarchyRequestError', 'The node cannot be inserted');
  if (nt === TEXT_NODE && pt === DOCUMENT_NODE) throw domError('HierarchyRequestError', 'Text cannot be a child of a document');
  if (nt === DOCUMENT_TYPE_NODE && pt !== DOCUMENT_NODE) throw domError('HierarchyRequestError', 'A doctype can only be a child of a document');
  if (pt === DOCUMENT_NODE) {
    if (nt === DOCUMENT_FRAGMENT_NODE) {
      const kids = childrenOf(node);
      let elements = 0;
      for (const k of kids) { if (nodeType(k) === TEXT_NODE) throw domError('HierarchyRequestError', 'Text cannot be a child of a document'); if (isElementNode(k)) elements++; }
      if (elements > 1) throw domError('HierarchyRequestError', 'A document can have only one element child');
      if (elements === 1) {
        for (const k of childrenOf(parent)) if (isElementNode(k)) throw domError('HierarchyRequestError', 'A document can have only one element child');
        if (child !== null && nodeType(child) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype');
        if (child !== null) {
          let n = nextSibling(child);
          while (n !== null) { if (nodeType(n) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype'); n = nextSibling(n); }
        }
      }
    } else if (nt === ELEMENT_NODE) {
      for (const k of childrenOf(parent)) if (isElementNode(k)) throw domError('HierarchyRequestError', 'A document can have only one element child');
      if (child !== null && nodeType(child) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype');
      if (child !== null) {
        let n = nextSibling(child);
        while (n !== null) { if (nodeType(n) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype'); n = nextSibling(n); }
      }
    } else if (nt === DOCUMENT_TYPE_NODE) {
      for (const k of childrenOf(parent)) if (nodeType(k) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'A document can have only one doctype');
      if (child !== null) {
        let n = previousSibling(child);
        while (n !== null) { if (isElementNode(n)) throw domError('HierarchyRequestError', 'A doctype cannot follow the element'); n = previousSibling(n); }
      } else {
        for (const k of childrenOf(parent)) if (isElementNode(k)) throw domError('HierarchyRequestError', 'A doctype cannot follow the element');
      }
    }
  }
}

function preInsert(node, parent, child) {
  ensurePreInsertionValidity(node, parent, child);
  let referenceChild = child;
  if (referenceChild === node) referenceChild = nextSibling(node);
  insertNode(node, parent, referenceChild, false);
  return node;
}

function adopt(node, document) {
  const oldDoc = nodeType(node) === DOCUMENT_NODE ? node : slotOf(node).doc;
  const p = parentNode(node);
  if (p !== null) removeNode(node, false);
  if (oldDoc !== document) {
    const all = [node];
    for (const d of descendantsOf(node)) apply(arrayPush, all, [d]);
    for (const n of all) {
      slotOf(n).doc = document;
      if (nodeType(n) === ELEMENT_NODE) for (const a of attrsOf(n)) slotOf(a).doc = document;
      moveRegistrations(n, oldDoc, document);
    }
    for (const n of all) if (nodeType(n) === ELEMENT_NODE) enqueueAdoptedCallback(n, oldDoc, document);
  }
}

// Whether `node` is inserted while its parent is connected: runs script/iframe/link steps for new elements.
function insertNode(node, parent, child, suppressObservers) {
  const nodes = nodeType(node) === DOCUMENT_FRAGMENT_NODE ? childrenOf(node) : [node];
  const count = nodes.length;
  if (count === 0) return;
  const parentDoc = ownerDocOrSelf(parent);
  if (nodeType(node) === DOCUMENT_FRAGMENT_NODE) {
    for (const n of nodes) removeNode(n, true);
    if (!suppressObservers) queueMutationRecord('childList', node, null, null, null, [], nodes, null, null);
  }
  if (child !== null) {
    for (const r of liveRanges) rangeInsertAdjust(r, parent, child, count);
  }
  const previous = child === null ? lastChild(parent) : previousSibling(child);
  for (const n of nodes) {
    adopt(n, parentDoc);
    const code = N.insert(idOf(parent), idOf(n), child === null ? -1 : idOf(child));
    if (code !== 0) throw domError('HierarchyRequestError', 'The node could not be inserted');
    if (isShadowHostWithSlots(parent)) assignSlotablesForTree(parent);
  }
  if (!suppressObservers) queueMutationRecord('childList', parent, null, null, null, nodes, [], previous, child);
  for (const n of nodes) {
    for (const inc of shadowIncludingInclusiveDescendants(n)) {
      if (isConnected(inc)) {
        if (nodeType(inc) === ELEMENT_NODE) {
          if (customElementState(inc) === 'custom') enqueueCallbackReaction(inc, 'connectedCallback', []);
          else tryUpgrade(inc);
        }
        if (nodeType(inc) === ELEMENT_NODE) elementInserted(inc);
      }
    }
  }
  childrenChanged(parent);
}

function removeNode(node, suppressObservers) {
  const parent = parentNode(node);
  if (parent === null) return;
  const index = indexOfChild(node);
  for (const r of liveRanges) rangeRemoveAdjust(r, node, parent, index);
  for (const it of liveIterators) iteratorRemoveAdjust(it, node);
  const oldPrevious = previousSibling(node), oldNext = nextSibling(node);
  const wasConnected = isConnected(node);
  const removedElements = [];
  if (wasConnected) for (const inc of shadowIncludingInclusiveDescendants(node)) if (nodeType(inc) === ELEMENT_NODE) apply(arrayPush, removedElements, [inc]);
  addTransientRegistrations(node, parent);
  N.remove(idOf(node));
  if (isShadowHostWithSlots(parent)) assignSlotablesForTree(parent);
  if (!suppressObservers) queueMutationRecord('childList', parent, null, null, null, [], [node], oldPrevious, oldNext);
  for (const el of removedElements) {
    if (customElementState(el) === 'custom') enqueueCallbackReaction(el, 'disconnectedCallback', []);
    elementRemoved(el, parent);
  }
  childrenChanged(parent);
}

function replaceChild(node, child, parent) {
  const pt = nodeType(parent);
  if (pt !== DOCUMENT_NODE && pt !== DOCUMENT_FRAGMENT_NODE && pt !== ELEMENT_NODE) throw domError('HierarchyRequestError', 'The parent node cannot have children');
  if (hostIncludingInclusiveAncestor(node, parent)) throw domError('HierarchyRequestError', 'The new child is an ancestor of the parent');
  if (parentNode(child) !== parent) throw domError('NotFoundError', 'The node to be replaced is not a child of this node');
  const nt = nodeType(node);
  if (nt !== DOCUMENT_FRAGMENT_NODE && nt !== DOCUMENT_TYPE_NODE && nt !== ELEMENT_NODE && !isCharacterData(nt)) throw domError('HierarchyRequestError', 'The node cannot be inserted');
  if (nt === TEXT_NODE && pt === DOCUMENT_NODE) throw domError('HierarchyRequestError', 'Text cannot be a child of a document');
  if (nt === DOCUMENT_TYPE_NODE && pt !== DOCUMENT_NODE) throw domError('HierarchyRequestError', 'A doctype can only be a child of a document');
  if (pt === DOCUMENT_NODE) {
    if (nt === DOCUMENT_FRAGMENT_NODE) {
      const kids = childrenOf(node);
      let elements = 0;
      for (const k of kids) { if (nodeType(k) === TEXT_NODE) throw domError('HierarchyRequestError', 'Text cannot be a child of a document'); if (isElementNode(k)) elements++; }
      if (elements > 1) throw domError('HierarchyRequestError', 'A document can have only one element child');
      if (elements === 1) {
        for (const k of childrenOf(parent)) if (isElementNode(k) && k !== child) throw domError('HierarchyRequestError', 'A document can have only one element child');
        let n = nextSibling(child);
        while (n !== null) { if (nodeType(n) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype'); n = nextSibling(n); }
      }
    } else if (nt === ELEMENT_NODE) {
      for (const k of childrenOf(parent)) if (isElementNode(k) && k !== child) throw domError('HierarchyRequestError', 'A document can have only one element child');
      let n = nextSibling(child);
      while (n !== null) { if (nodeType(n) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'An element cannot precede the doctype'); n = nextSibling(n); }
    } else if (nt === DOCUMENT_TYPE_NODE) {
      for (const k of childrenOf(parent)) if (nodeType(k) === DOCUMENT_TYPE_NODE && k !== child) throw domError('HierarchyRequestError', 'A document can have only one doctype');
      let n = previousSibling(child);
      while (n !== null) { if (isElementNode(n)) throw domError('HierarchyRequestError', 'A doctype cannot follow the element'); n = previousSibling(n); }
    }
  }
  let referenceChild = nextSibling(child);
  if (referenceChild === node) referenceChild = nextSibling(node);
  const previous = previousSibling(child);
  adopt(node, ownerDocOrSelf(parent));
  const removedNodes = [];
  if (parentNode(child) !== null) { apply(arrayPush, removedNodes, [child]); removeNode(child, true); }
  const nodes = nt === DOCUMENT_FRAGMENT_NODE ? childrenOf(node) : [node];
  insertNode(node, parent, referenceChild, true);
  queueMutationRecord('childList', parent, null, null, null, nodes, removedNodes, previous, referenceChild);
  return child;
}

function preRemove(child, parent) {
  if (parentNode(child) !== parent) throw domError('NotFoundError', 'The node to be removed is not a child of this node');
  removeNode(child, false);
  return child;
}

// Hooks filled in by later files.
let childrenChanged = p => {};
let elementInserted = el => {};
let elementRemoved = (el, parent) => {};
let customElementState = el => 'undefined';
let enqueueCallbackReaction = (el, name, args) => {};
let enqueueAdoptedCallback = (el, oldDoc, newDoc) => {};
let tryUpgrade = el => {};
let isShadowHostWithSlots = o => false;
let assignSlotablesForTree = o => {};
let shadowIncludingInclusiveDescendants = n => { const out = [n]; for (const d of descendantsOf(n)) apply(arrayPush, out, [d]); return out; };
let queueMutationRecord = (type, target, name, ns, oldValue, added, removed, prev, next) => {};
let addTransientRegistrations = (node, parent) => {};
let moveRegistrations = (n, oldDoc, newDoc) => {};
const liveRanges = [];
const liveIterators = [];
let rangeInsertAdjust = (r, parent, child, count) => {};
let rangeRemoveAdjust = (r, node, parent, index) => {};
let iteratorRemoveAdjust = (it, node) => {};
let adjustRangesForMerge = (cur, node, length) => {};
let documentBaseURL = doc => '';
let documentElementOf = doc => { for (const k of childrenOf(doc)) if (isElementNode(k)) return k; return null; };
let childNodesOf = o => null;

// --- cloning

function cloneNode(node, document, cloneChildren, parent) {
  const s = slotOf(node);
  if (document === undefined) document = s.nodeType === DOCUMENT_NODE ? node : s.doc;
  let copy;
  switch (s.nodeType) {
    case ELEMENT_NODE: {
      copy = createElementInternal(document, s.localName, s.namespaceURI, s.prefix, s.isValue, false);
      for (const a of attrsOf(node)) {
        const as = slotOf(a);
        const na = newAttr(document, as.localName, as.namespaceURI, as.prefix, as.value);
        appendAttribute(na, copy);
      }
      break;
    }
    case TEXT_NODE: copy = createTextNode(document, N.value(s.id)); break;
    case CDATA_SECTION_NODE: copy = createCDATA(document, N.value(s.id)); break;
    case COMMENT_NODE: copy = createCommentNode(document, N.value(s.id)); break;
    case PROCESSING_INSTRUCTION_NODE: copy = createPI(document, s.target, N.value(s.id)); break;
    case DOCUMENT_TYPE_NODE: copy = createDoctypeNode(document, s.name, s.publicId, s.systemId); break;
    case DOCUMENT_FRAGMENT_NODE: copy = createFragmentNode(document); break;
    case DOCUMENT_NODE: {
      copy = newDocument(s.docType === 'xml');
      const cs = slotOf(copy);
      cs.contentType = s.contentType; cs.url = s.url; cs.origin = s.origin; cs.mode = s.mode; cs.encoding = s.encoding;
      document = copy;
      break;
    }
    case ATTRIBUTE_NODE: {
      copy = newAttr(document, s.localName, s.namespaceURI, s.prefix, s.value);
      return copy;
    }
  }
  cloningSteps(node, copy, document, cloneChildren);
  if (cloneChildren) {
    for (const child of childrenOf(node)) {
      const c = cloneNode(child, document, true);
      appendNodeSimple(copy, c);
    }
  }
  return copy;
}
function appendNodeSimple(parent, child) {
  // Appending a fresh clone cannot violate any constraint, so skip validity checks and the mutation-record machinery.
  const code = N.insert(idOf(parent), idOf(child), -1);
  if (code !== 0) throw domError('HierarchyRequestError', 'The node could not be inserted');
}
let cloningSteps = (node, copy, document, cloneChildren) => {};

// --- Text, Comment, CharacterData, ProcessingInstruction, CDATASection

function CharacterData() { throw new TypeError('Illegal constructor'); }
iface('CharacterData', CharacterData, Node);
function cdSlot(o) { const s = slotOf(o); if (!s || !s.isNode || !isCharacterData(s.nodeType)) illegal(); return s; }
function utf16Length(s) { return s.length; }

function replaceData(node, offset, count, data) {
  const s = slotOf(node);
  const current = N.value(s.id);
  const length = current.length;
  if (offset > length) throw domError('IndexSizeError', 'The offset is greater than the node length');
  if (offset + count > length) count = length - offset;
  queueMutationRecord('characterData', node, null, null, current, [], [], null, null);
  const updated = current.slice(0, offset) + data + current.slice(offset + count);
  N.setValue(s.id, updated);
  for (const r of liveRanges) rangeReplaceDataAdjust(r, node, offset, count, data.length);
  characterDataChanged(node);
}
let rangeReplaceDataAdjust = (r, node, offset, count, dataLength) => {};
let characterDataChanged = node => {};

function substringData(node, offset, count) {
  const v = N.value(idOf(node));
  if (offset > v.length) throw domError('IndexSizeError', 'The offset is greater than the node length');
  return v.slice(offset, Math.min(v.length, offset + count));
}

operations(CharacterData.prototype, {
  substringData(offset, count) {
    cdSlot(this);
    required(arguments, 2, 'substringData');
    return substringData(this, toUnsignedLong(offset), toUnsignedLong(count));
  },
  appendData(data) {
    cdSlot(this);
    required(arguments, 1, 'appendData');
    replaceData(this, N.value(idOf(this)).length, 0, toDOMString(data));
  },
  insertData(offset, data) {
    cdSlot(this);
    required(arguments, 2, 'insertData');
    replaceData(this, toUnsignedLong(offset), 0, toDOMString(data));
  },
  deleteData(offset, count) {
    cdSlot(this);
    required(arguments, 2, 'deleteData');
    replaceData(this, toUnsignedLong(offset), toUnsignedLong(count), '');
  },
  replaceData(offset, count, data) {
    cdSlot(this);
    required(arguments, 3, 'replaceData');
    replaceData(this, toUnsignedLong(offset), toUnsignedLong(count), toDOMString(data));
  }
});
attributes(CharacterData.prototype, {
  data: {
    get() { return N.value(cdSlot(this).id); },
    set(v) { cdSlot(this); replaceData(this, 0, N.value(idOf(this)).length, v === null ? '' : toDOMString(v)); }
  },
  length: { get() { return N.value(cdSlot(this).id).length; } }
});

// ChildNode / NonDocumentTypeChildNode mixins
function viableSibling(node, nodes, forward) {
  let sib = forward ? nextSibling(node) : previousSibling(node);
  const set = nodes;
  while (sib !== null && set.indexOf(sib) >= 0) sib = forward ? nextSibling(sib) : previousSibling(sib);
  return sib;
}
function nodesIntoNode(nodes, document) {
  const converted = [];
  for (const n of nodes) {
    if (acceptNode(n, document)) apply(arrayPush, converted, [n]);
    else apply(arrayPush, converted, [createTextNode(document, toDOMString(n))]);
  }
  if (converted.length === 1) return converted[0];
  const frag = createFragmentNode(document);
  for (const n of converted) preInsert(n, frag, null);
  return frag;
}
const childNodeMixin = {
  before(...nodes) {
    nodeSlot(this);
    const parent = parentNode(this);
    if (parent === null) return;
    const viablePrev = viableSibling(this, nodes, false);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    const ref = viablePrev === null ? firstChild(parent) : nextSibling(viablePrev);
    preInsert(node, parent, ref);
  },
  after(...nodes) {
    nodeSlot(this);
    const parent = parentNode(this);
    if (parent === null) return;
    const viableNext = viableSibling(this, nodes, true);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    preInsert(node, parent, viableNext);
  },
  replaceWith(...nodes) {
    nodeSlot(this);
    const parent = parentNode(this);
    if (parent === null) return;
    let viableNext = viableSibling(this, nodes, true);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    if (parentNode(this) === parent) replaceChild(node, this, parent);
    else preInsert(node, parent, viableNext);
  },
  remove() {
    nodeSlot(this);
    if (parentNode(this) === null) return;
    removeNode(this, false);
  }
};
function installChildNode(proto) {
  for (const name of ['before', 'after', 'replaceWith', 'remove']) {
    defineProperty(proto, name, { value: childNodeMixin[name], writable: true, enumerable: true, configurable: true });
    defineProperty(childNodeMixin[name], 'length', { value: name === 'remove' ? 0 : 0, configurable: true });
  }
}
function installNonDocumentTypeChildNode(proto) {
  attributes(proto, {
    previousElementSibling: { get() { nodeSlot(this); let n = previousSibling(this); while (n !== null && !isElementNode(n)) n = previousSibling(n); return n; } },
    nextElementSibling: { get() { nodeSlot(this); let n = nextSibling(this); while (n !== null && !isElementNode(n)) n = nextSibling(n); return n; } }
  });
}
installChildNode(CharacterData.prototype);
installNonDocumentTypeChildNode(CharacterData.prototype);

function Text(data = '') {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Text': Please use the 'new' operator");
  const id = N.mkText(toDOMString(data));
  setSlot(this, newNodeSlot(id, TEXT_NODE, mainDocument));
  register(this, id);
}
iface('Text', Text, CharacterData);
operations(Text.prototype, {
  splitText(offset) {
    const s = slotOf(this);
    if (!s || !s.isNode || (s.nodeType !== TEXT_NODE && s.nodeType !== CDATA_SECTION_NODE)) illegal();
    required(arguments, 1, 'splitText');
    return splitText(this, toUnsignedLong(offset));
  }
});
function splitText(node, offset) {
  const s = slotOf(node);
  const value = N.value(s.id);
  const length = value.length;
  if (offset > length) throw domError('IndexSizeError', 'The offset is greater than the node length');
  const count = length - offset;
  const newData = substringData(node, offset, count);
  const newNode = s.nodeType === CDATA_SECTION_NODE ? createCDATA(s.doc, newData) : createTextNode(s.doc, newData);
  const parent = parentNode(node);
  if (parent !== null) {
    insertNode(newNode, parent, nextSibling(node), false);
    for (const r of liveRanges) rangeSplitAdjust(r, node, newNode, offset, parent);
  }
  replaceData(node, offset, count, '');
  return newNode;
}
let rangeSplitAdjust = (r, node, newNode, offset, parent) => {};
attributes(Text.prototype, {
  wholeText: {
    get() {
      const s = slotOf(this);
      if (!s || !s.isNode || (s.nodeType !== TEXT_NODE && s.nodeType !== CDATA_SECTION_NODE)) illegal();
      let first = this;
      let p = previousSibling(first);
      while (p !== null && (nodeType(p) === TEXT_NODE || nodeType(p) === CDATA_SECTION_NODE)) { first = p; p = previousSibling(first); }
      let out = '';
      let n = first;
      while (n !== null && (nodeType(n) === TEXT_NODE || nodeType(n) === CDATA_SECTION_NODE)) { out += N.value(idOf(n)); n = nextSibling(n); }
      return out;
    }
  },
  assignedSlot: { get() { return assignedSlotOfNode(this); } }
});
let assignedSlotOfNode = o => null;

function CDATASection() { throw new TypeError('Illegal constructor'); }
iface('CDATASection', CDATASection, Text);

function Comment(data = '') {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Comment': Please use the 'new' operator");
  const id = N.mkComment(toDOMString(data));
  setSlot(this, newNodeSlot(id, COMMENT_NODE, mainDocument));
  register(this, id);
}
iface('Comment', Comment, CharacterData);

function ProcessingInstruction() { throw new TypeError('Illegal constructor'); }
iface('ProcessingInstruction', ProcessingInstruction, CharacterData);
attributes(ProcessingInstruction.prototype, {
  target: { get() { const s = slotOf(this); if (!s || s.nodeType !== PROCESSING_INSTRUCTION_NODE) illegal(); return s.target; } }
});

function createTextNode(doc, data) {
  const id = N.mkText(data);
  const w = create(Text.prototype);
  setSlot(w, newNodeSlot(id, TEXT_NODE, doc));
  return register(w, id);
}
function createCDATA(doc, data) {
  const id = N.mkText(data);
  const w = create(CDATASection.prototype);
  setSlot(w, newNodeSlot(id, CDATA_SECTION_NODE, doc));
  return register(w, id);
}
function createCommentNode(doc, data) {
  const id = N.mkComment(data);
  const w = create(Comment.prototype);
  setSlot(w, newNodeSlot(id, COMMENT_NODE, doc));
  return register(w, id);
}
function createPI(doc, target, data) {
  const id = N.mkComment(data);
  const w = create(ProcessingInstruction.prototype);
  const s = setSlot(w, newNodeSlot(id, PROCESSING_INSTRUCTION_NODE, doc));
  s.target = target;
  return register(w, id);
}
function createFragmentNode(doc) {
  const id = N.mkFragment();
  const w = create(DocumentFragment.prototype);
  setSlot(w, newNodeSlot(id, DOCUMENT_FRAGMENT_NODE, doc));
  return register(w, id);
}
function createDoctypeNode(doc, name, publicId, systemId) {
  const id = N.mkDoctype(name);
  const w = create(DocumentType.prototype);
  const s = setSlot(w, newNodeSlot(id, DOCUMENT_TYPE_NODE, doc));
  s.name = name; s.publicId = publicId; s.systemId = systemId;
  return register(w, id);
}

// --- DocumentType and DocumentFragment

function DocumentType() { throw new TypeError('Illegal constructor'); }
iface('DocumentType', DocumentType, Node);
installChildNode(DocumentType.prototype);
function dtSlot(o) { const s = slotOf(o); if (!s || s.nodeType !== DOCUMENT_TYPE_NODE) illegal(); return s; }
attributes(DocumentType.prototype, {
  name: { get() { const s = dtSlot(this); return s.name !== undefined ? s.name : N.name(s.id); } },
  publicId: { get() { return dtSlot(this).publicId; } },
  systemId: { get() { return dtSlot(this).systemId; } }
});

function DocumentFragment() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DocumentFragment': Please use the 'new' operator");
  const id = N.mkFragment();
  setSlot(this, newNodeSlot(id, DOCUMENT_FRAGMENT_NODE, mainDocument));
  register(this, id);
}
iface('DocumentFragment', DocumentFragment, Node);

// ParentNode mixin
function elementChildren(o) { const out = []; let id = nFirst(idOf(o)); while (id >= 0) { if (N.kind(id) === 2) apply(arrayPush, out, [wrap(id)]); id = nNext(id); } return out; }
function parentNodeSlotCheck(o) { const s = slotOf(o); if (!s || !s.isNode || (s.nodeType !== ELEMENT_NODE && s.nodeType !== DOCUMENT_NODE && s.nodeType !== DOCUMENT_FRAGMENT_NODE)) illegal(); return s; }
const parentNodeMixin = {
  prepend(...nodes) {
    parentNodeSlotCheck(this);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    preInsert(node, this, firstChild(this));
  },
  append(...nodes) {
    parentNodeSlotCheck(this);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    preInsert(node, this, null);
  },
  replaceChildren(...nodes) {
    parentNodeSlotCheck(this);
    const node = nodesIntoNode(nodes, ownerDocOrSelf(this));
    ensurePreInsertionValidity(node, this, null);
    replaceAllWith(this, node);
  },
  querySelector(selectors) {
    parentNodeSlotCheck(this);
    required(arguments, 1, 'querySelector');
    const r = N.qs(idOf(this), toDOMString(selectors));
    if (r === -2) throw domError('SyntaxError', "'" + selectors + "' is not a valid selector");
    return wrap(r);
  },
  querySelectorAll(selectors) {
    parentNodeSlotCheck(this);
    required(arguments, 1, 'querySelectorAll');
    const r = N.qsa(idOf(this), toDOMString(selectors));
    if (r === null) throw domError('SyntaxError', "'" + selectors + "' is not a valid selector");
    return staticNodeList(r.map(wrap));
  }
};
const parentNodeAttrs = {
  children: { get() { parentNodeSlotCheck(this); return childrenCollection(this); } },
  firstElementChild: { get() { parentNodeSlotCheck(this); let id = nFirst(idOf(this)); while (id >= 0 && N.kind(id) !== 2) id = nNext(id); return wrap(id); } },
  lastElementChild: { get() { parentNodeSlotCheck(this); let id = nLast(idOf(this)); while (id >= 0 && N.kind(id) !== 2) id = nPrev(id); return wrap(id); } },
  childElementCount: { get() { parentNodeSlotCheck(this); let n = 0, id = nFirst(idOf(this)); while (id >= 0) { if (N.kind(id) === 2) n++; id = nNext(id); } return n; } }
};
function installParentNode(proto) {
  operations(proto, parentNodeMixin);
  attributes(proto, parentNodeAttrs);
  defineProperty(proto.prepend, 'length', { value: 0, configurable: true });
  defineProperty(proto.append, 'length', { value: 0, configurable: true });
  defineProperty(proto.replaceChildren, 'length', { value: 0, configurable: true });
}
installParentNode(DocumentFragment.prototype);
operations(DocumentFragment.prototype, {
  getElementById(elementId) {
    const s = slotOf(this);
    if (!s || s.nodeType !== DOCUMENT_FRAGMENT_NODE) illegal();
    required(arguments, 1, 'getElementById');
    const id = toDOMString(elementId);
    if (id === '') return null;
    for (const d of descendantsOf(this)) if (isElementNode(d) && getAttributeValue(d, 'id') === id) return d;
    return null;
  }
});
let childrenCollection = o => null;
let staticNodeList = arr => arr;
let attrsOf = el => [];
let getAttributeValue = (el, name) => null;
let createElementInternal = () => null;
let newDocument = () => null;
let setAttrValue = () => {};
let elementTagName = el => '';
let mainDocument = null;
