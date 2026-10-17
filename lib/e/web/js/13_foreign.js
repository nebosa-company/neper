// Nodes of other realms. Every frame owns its own node table, so a node handed over from another window is re-homed into this
// one: its native subtree is rebuilt here and the wrapper object keeps its identity (as adoptNode promises).

const realmInfo = {
  global,
  slotOf: o => apply(slotGet, slots, [o]),
  // Source side: detach `root` and describe its subtree (wrappers in tree order); the wrappers leave this realm.
  exportSubtree(root) {
    removeNode(root, false);
    const list = [], parents = [];
    const index = new Map();
    (function walk(n, parent) {
      index.set(n, list.length);
      apply(arrayPush, list, [n]);
      apply(arrayPush, parents, [parent]);
      const me = list.length - 1;
      const s = slotOf(n);
      if (s.nodeType === ELEMENT_NODE && s.shadowRoot) walk(s.shadowRoot, -2 - me);
      for (const k of childrenOf(n)) walk(k, me);
    })(root, -1);
    const out = [];
    for (let i = 0; i < list.length; i++) {
      const n = list[i], s = slotOf(n), t = s.nodeType;
      const d = { w: n, slot: s, parent: parents[i], type: t, local: s.localName, ns: s.namespaceURI, value: null, attrs: null, name: s.name, pub: s.publicId, sys: s.systemId };
      if (t === TEXT_NODE || t === CDATA_SECTION_NODE || t === COMMENT_NODE || t === PROCESSING_INSTRUCTION_NODE) d.value = N.value(s.id);
      if (t === ELEMENT_NODE) d.attrs = attrsOf(n).map(a => [qualifiedName(a), slotOf(a).value, slotOf(a).namespaceURI === null ? 0 : nsToCode(slotOf(a).namespaceURI)]);
      apply(arrayPush, out, [d]);
    }
    for (const n of list) { apply(mapDelete, wrappers, [slotOf(n).id]); apply(WeakMap.prototype.delete, slots, [n]); }
    return out;
  }
};
defineProperty(global, '__realm', { value: realmInfo, writable: true, enumerable: false, configurable: true });

function foreignRealmOf(o) { return isObject(o) && o !== global ? N.realmOf(o) : undefined; }
function isForeignNode(o) {
  const g = foreignRealmOf(o);
  if (g === undefined) return false;
  const s = g.__realm.slotOf(o);
  return !!s && s.isNode === true;
}
// The local prototype for a wrapper that arrives from another realm.
function localPrototypeFor(s) {
  switch (s.nodeType) {
    case ELEMENT_NODE: return interfaceFor(s.localName, s.namespaceURI);
    case TEXT_NODE: return Text.prototype;
    case CDATA_SECTION_NODE: return CDATASection.prototype;
    case COMMENT_NODE: return Comment.prototype;
    case PROCESSING_INSTRUCTION_NODE: return ProcessingInstruction.prototype;
    case DOCUMENT_TYPE_NODE: return DocumentType.prototype;
    default: return s.isShadowRoot ? ShadowRoot.prototype : DocumentFragment.prototype;
  }
}
// Re-homes the foreign node into `doc` (detached) and answers it.
function importForeign(node, doc) {
  const g = N.realmOf(node);
  const list = g.__realm.exportSubtree(node);
  const ids = [];
  for (let i = 0; i < list.length; i++) {
    const d = list[i], w = d.w;
    const t = d.type;
    let id;
    if (t === ELEMENT_NODE) id = N.mkElement(d.local, d.ns === null ? 4 : nsToCode(d.ns));
    else if (t === TEXT_NODE || t === CDATA_SECTION_NODE) id = N.mkText(d.value);
    else if (t === COMMENT_NODE || t === PROCESSING_INSTRUCTION_NODE) id = N.mkComment(d.value);
    else if (t === DOCUMENT_TYPE_NODE) id = N.mkDoctype(d.name);
    else id = N.mkFragment();
    apply(arrayPush, ids, [id]);
    const s = d.slot;
    s.id = id;
    s.doc = doc;
    setSlot(w, s);
    register(w, id);
    setPrototypeOf(w, localPrototypeFor(s));
    if (t === ELEMENT_NODE) {
      for (const a of d.attrs) N.attrPut(id, a[0], a[1], a[2]);
      for (const a of attrsOf(w)) slotOf(a).doc = doc;
    }
  }
  for (let i = 0; i < list.length; i++) {
    const p = list[i].parent;
    if (p >= 0) N.insert(ids[p], ids[i], -1);
  }
  return node;
}
// A node argument that may come from another window: answers whether it is a node and re-homes it into `doc` when it is foreign.
function acceptNode(o, doc) {
  if (isNode(o)) return true;
  if (!isForeignNode(o)) return false;
  importForeign(o, doc);
  return true;
}
