// NodeIterator, TreeWalker and NodeFilter (DOM Standard 6).

function NodeFilter() { throw new TypeError('Illegal constructor'); }
iface('NodeFilter', NodeFilter, null);
const FILTER_ACCEPT = 1, FILTER_REJECT = 2, FILTER_SKIP = 3;
defineProperty(global, 'NodeFilter', { value: NodeFilter, writable: true, enumerable: false, configurable: true });
for (const [k, v] of Object.entries({
  FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3, SHOW_ALL: 0xFFFFFFFF, SHOW_ELEMENT: 0x1, SHOW_ATTRIBUTE: 0x2, SHOW_TEXT: 0x4,
  SHOW_CDATA_SECTION: 0x8, SHOW_ENTITY_REFERENCE: 0x10, SHOW_ENTITY: 0x20, SHOW_PROCESSING_INSTRUCTION: 0x40, SHOW_COMMENT: 0x80,
  SHOW_DOCUMENT: 0x100, SHOW_DOCUMENT_TYPE: 0x200, SHOW_DOCUMENT_FRAGMENT: 0x400, SHOW_NOTATION: 0x800
})) {
  defineProperty(NodeFilter, k, { value: v, writable: false, enumerable: true, configurable: false });
}
delete NodeFilter.prototype.constructor;
defineProperty(NodeFilter.prototype, 'constructor', { value: NodeFilter, writable: true, enumerable: false, configurable: true });

function filterNode(traverser, node) {
  const s = slotOf(traverser);
  if (s.active) throw domError('InvalidStateError', 'The filter is already running');
  const n = nodeType(node) - 1;
  if (((s.whatToShow >>> n) & 1) === 0) return FILTER_SKIP;
  const f = s.filter;
  if (f === null) return FILTER_ACCEPT;
  s.active = true;
  let result;
  try {
    if (typeof f === 'function') result = apply(f, undefined, [node]);
    else {
      const accept = f.acceptNode;
      if (typeof accept !== 'function') throw new TypeError('acceptNode is not a function');
      result = apply(accept, f, [node]);
    }
  } finally {
    s.active = false;
  }
  return toUnsignedShort(result);
}
function toFilter(filter) {
  if (filter === null || filter === undefined) return null;
  if (!isObject(filter)) throw new TypeError('The provided callback is not an object');
  return filter;
}

// --- NodeIterator

function NodeIterator() { throw new TypeError('Illegal constructor'); }
iface('NodeIterator', NodeIterator, null);
function niSlot(o) { const s = slotOf(o); if (!s || !s.isNodeIterator) illegal(); return s; }
function createNodeIterator(root, whatToShow, filter) {
  const it = create(NodeIterator.prototype);
  setSlot(it, { isNodeIterator: true, root, reference: root, pointerBefore: true, whatToShow, filter, active: false });
  apply(arrayPush, liveIterators, [it]);
  return it;
}
function followingInRoot(node, root) {
  // the first node following `node` in tree order inside `root`
  const f = firstChild(node);
  if (f !== null) return f;
  let n = node;
  while (n !== null && n !== root) {
    const sib = nextSibling(n);
    if (sib !== null) return sib;
    n = parentNode(n);
  }
  return null;
}
function precedingInRoot(node, root) {
  if (node === root) return null;
  const sib = previousSibling(node);
  if (sib === null) return parentNode(node);
  let n = sib;
  while (lastChild(n) !== null) n = lastChild(n);
  return n;
}
function iterate(iterator, next) {
  const s = niSlot(iterator);
  let node = s.reference, before = s.pointerBefore;
  while (true) {
    if (next) {
      if (!before) { node = followingInRoot(node, s.root); if (node === null) return null; } else before = false;
    } else {
      if (before) { node = precedingInRoot(node, s.root); if (node === null) return null; } else before = true;
    }
    const result = filterNode(iterator, node);
    if (result === FILTER_ACCEPT) break;
  }
  s.reference = node;
  s.pointerBefore = before;
  return node;
}
iteratorRemoveAdjust = function (iterator, toBeRemoved) {
  const s = slotOf(iterator);
  if (!isInclusiveAncestor(toBeRemoved, s.reference) || toBeRemoved === s.root) return;
  if (s.pointerBefore) {
    // first node following toBeRemoved that is not its descendant, inside the root
    let n = toBeRemoved, next = null;
    while (n !== null && n !== s.root) {
      const sib = nextSibling(n);
      if (sib !== null) { next = sib; break; }
      n = parentNode(n);
    }
    if (next !== null && isInclusiveAncestor(s.root, next)) { s.reference = next; return; }
    s.pointerBefore = false;
  }
  const prev = previousSibling(toBeRemoved);
  if (prev === null) s.reference = parentNode(toBeRemoved);
  else { let n = prev; while (lastChild(n) !== null) n = lastChild(n); s.reference = n; }
};
operations(NodeIterator.prototype, {
  nextNode() { niSlot(this); return iterate(this, true); },
  previousNode() { niSlot(this); return iterate(this, false); },
  detach() { niSlot(this); }
});
attributes(NodeIterator.prototype, {
  root: { get() { return niSlot(this).root; } },
  referenceNode: { get() { return niSlot(this).reference; } },
  pointerBeforeReferenceNode: { get() { return niSlot(this).pointerBefore; } },
  whatToShow: { get() { return niSlot(this).whatToShow; } },
  filter: { get() { return niSlot(this).filter; } }
});

// --- TreeWalker

function TreeWalker() { throw new TypeError('Illegal constructor'); }
iface('TreeWalker', TreeWalker, null);
function twSlot(o) { const s = slotOf(o); if (!s || !s.isTreeWalker) illegal(); return s; }
function createTreeWalker(root, whatToShow, filter) {
  const w = create(TreeWalker.prototype);
  setSlot(w, { isTreeWalker: true, root, current: root, whatToShow, filter, active: false });
  return w;
}
function traverseChildren(walker, first) {
  const s = twSlot(walker);
  let node = first ? firstChild(s.current) : lastChild(s.current);
  while (node !== null) {
    const result = filterNode(walker, node);
    if (result === FILTER_ACCEPT) { s.current = node; return node; }
    if (result === FILTER_SKIP) {
      const child = first ? firstChild(node) : lastChild(node);
      if (child !== null) { node = child; continue; }
    }
    while (node !== null) {
      const sibling = first ? nextSibling(node) : previousSibling(node);
      if (sibling !== null) { node = sibling; break; }
      const parent = parentNode(node);
      if (parent === null || parent === s.root || parent === s.current) return null;
      node = parent;
    }
  }
  return null;
}
function traverseSiblings(walker, next) {
  const s = twSlot(walker);
  let node = s.current;
  if (node === s.root) return null;
  while (true) {
    let sibling = next ? nextSibling(node) : previousSibling(node);
    while (sibling !== null) {
      node = sibling;
      const result = filterNode(walker, node);
      if (result === FILTER_ACCEPT) { s.current = node; return node; }
      sibling = next ? firstChild(node) : lastChild(node);
      if (result === FILTER_REJECT || sibling === null) sibling = next ? nextSibling(node) : previousSibling(node);
    }
    node = parentNode(node);
    if (node === null || node === s.root) return null;
    if (filterNode(walker, node) === FILTER_ACCEPT) return null;
  }
}
operations(TreeWalker.prototype, {
  parentNode() {
    const s = twSlot(this);
    let node = s.current;
    while (node !== null && node !== s.root) {
      node = parentNode(node);
      if (node !== null && filterNode(this, node) === FILTER_ACCEPT) { s.current = node; return node; }
    }
    return null;
  },
  firstChild() { twSlot(this); return traverseChildren(this, true); },
  lastChild() { twSlot(this); return traverseChildren(this, false); },
  previousSibling() { twSlot(this); return traverseSiblings(this, false); },
  nextSibling() { twSlot(this); return traverseSiblings(this, true); },
  previousNode() {
    const s = twSlot(this);
    let node = s.current;
    while (node !== s.root) {
      let sibling = previousSibling(node);
      while (sibling !== null) {
        node = sibling;
        let result = filterNode(this, node);
        while (result !== FILTER_REJECT && lastChild(node) !== null) { node = lastChild(node); result = filterNode(this, node); }
        if (result === FILTER_ACCEPT) { s.current = node; return node; }
        sibling = previousSibling(node);
      }
      if (node === s.root || parentNode(node) === null) return null;
      node = parentNode(node);
      if (filterNode(this, node) === FILTER_ACCEPT) { s.current = node; return node; }
    }
    return null;
  },
  nextNode() {
    const s = twSlot(this);
    let node = s.current;
    let result = FILTER_ACCEPT;
    while (true) {
      while (result !== FILTER_REJECT && firstChild(node) !== null) {
        node = firstChild(node);
        result = filterNode(this, node);
        if (result === FILTER_ACCEPT) { s.current = node; return node; }
      }
      let sibling = null, temporary = node;
      while (temporary !== null) {
        if (temporary === s.root) return null;
        sibling = nextSibling(temporary);
        if (sibling !== null) { node = sibling; break; }
        temporary = parentNode(temporary);
      }
      if (temporary === null || sibling === null) return null;
      result = filterNode(this, node);
      if (result === FILTER_ACCEPT) { s.current = node; return node; }
    }
  }
});
attributes(TreeWalker.prototype, {
  root: { get() { return twSlot(this).root; } },
  whatToShow: { get() { return twSlot(this).whatToShow; } },
  filter: { get() { return twSlot(this).filter; } },
  currentNode: {
    get() { return twSlot(this).current; },
    set(v) { const s = twSlot(this); if (!isNode(v)) throw new TypeError("Failed to set the 'currentNode' property on 'TreeWalker': The provided value is not of type 'Node'."); s.current = v; }
  }
});

operations(Document.prototype, {
  createNodeIterator(root, whatToShow = 0xFFFFFFFF, filter = null) {
    docSlot(this);
    required(arguments, 1, 'createNodeIterator');
    if (!isNode(root)) throw new TypeError("Failed to execute 'createNodeIterator' on 'Document': parameter 1 is not of type 'Node'.");
    return createNodeIterator(root, whatToShow === undefined ? 0xFFFFFFFF : toUnsignedLong(whatToShow), toFilter(filter));
  },
  createTreeWalker(root, whatToShow = 0xFFFFFFFF, filter = null) {
    docSlot(this);
    required(arguments, 1, 'createTreeWalker');
    if (!isNode(root)) throw new TypeError("Failed to execute 'createTreeWalker' on 'Document': parameter 1 is not of type 'Node'.");
    return createTreeWalker(root, whatToShow === undefined ? 0xFFFFFFFF : toUnsignedLong(whatToShow), toFilter(filter));
  }
});
