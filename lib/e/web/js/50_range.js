// Range (DOM Standard 5): boundary points that follow tree mutations, plus StaticRange.

function AbstractRange() { throw new TypeError('Illegal constructor'); }
iface('AbstractRange', AbstractRange, null);
function Range() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Range': Please use the 'new' operator");
  const s = setSlot(this, { isRange: true, startNode: mainDocument, startOffset: 0, endNode: mainDocument, endOffset: 0 });
  apply(arrayPush, liveRanges, [this]);
}
iface('Range', Range, AbstractRange);
constants(Range, { START_TO_START: 0, START_TO_END: 1, END_TO_END: 2, END_TO_START: 3 });
function rangeSlot(o) { const s = slotOf(o); if (!s || !s.isRange) illegal(); return s; }

function nodeLength(node) {
  const t = nodeType(node);
  if (t === DOCUMENT_TYPE_NODE) return 0;
  if (isCharacterData(t)) return N.value(idOf(node)).length;
  return childCount(node);
}
// Position of boundary point A relative to B: -1 before, 0 equal, 1 after (both in the same tree).
function comparePoints(nodeA, offsetA, nodeB, offsetB) {
  if (nodeA === nodeB) return offsetA === offsetB ? 0 : offsetA < offsetB ? -1 : 1;
  if (isFollowing(nodeA, nodeB)) {
    const r = comparePoints(nodeB, offsetB, nodeA, offsetA);
    return r === -1 ? 1 : r === 1 ? -1 : 0;
  }
  if (isInclusiveAncestor(nodeA, nodeB)) {
    let child = nodeB;
    while (parentNode(child) !== nodeA) child = parentNode(child);
    if (indexOfChild(child) < offsetA) return 1;
  }
  return -1;
}
// Whether `a` follows `b` in tree order (same tree).
function isFollowing(a, b) { return a !== b && !precedes(a, b); }

function setBoundary(range, isStart, node, offset) {
  const s = slotOf(range);
  if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node provided is a doctype');
  if (offset > nodeLength(node)) throw domError('IndexSizeError', 'The offset ' + offset + ' is larger than the node\'s length (' + nodeLength(node) + ').');
  if (isStart) {
    if (rootNode(node) !== rootNode(s.endNode) || comparePoints(node, offset, s.endNode, s.endOffset) === 1) { s.endNode = node; s.endOffset = offset; }
    s.startNode = node; s.startOffset = offset;
  } else {
    if (rootNode(node) !== rootNode(s.startNode) || comparePoints(node, offset, s.startNode, s.startOffset) === -1) { s.startNode = node; s.startOffset = offset; }
    s.endNode = node; s.endOffset = offset;
  }
}
function toNodeArg(node, method) {
  if (!isNode(node)) throw new TypeError("Failed to execute '" + method + "' on 'Range': parameter 1 is not of type 'Node'.");
  return node;
}
function commonAncestor(a, b) {
  const pa = inclusiveAncestors(a);
  let n = b;
  while (n !== null) { if (pa.indexOf(n) >= 0) return n; n = parentNode(n); }
  return null;
}
function contained(node, range) {
  const s = slotOf(range);
  return rootNode(node) === rootNode(s.startNode) && comparePoints(node, 0, s.startNode, s.startOffset) === 1 && comparePoints(node, nodeLength(node), s.endNode, s.endOffset) === -1;
}
function partiallyContained(node, range) {
  const s = slotOf(range);
  const a = isInclusiveAncestor(node, s.startNode), b = isInclusiveAncestor(node, s.endNode);
  return (a && !b) || (!a && b);
}

operations(Range.prototype, {
  setStart(node, offset) { rangeSlot(this); required(arguments, 2, 'setStart'); setBoundary(this, true, toNodeArg(node, 'setStart'), toUnsignedLong(offset)); },
  setEnd(node, offset) { rangeSlot(this); required(arguments, 2, 'setEnd'); setBoundary(this, false, toNodeArg(node, 'setEnd'), toUnsignedLong(offset)); },
  setStartBefore(node) { rangeSlot(this); required(arguments, 1, 'setStartBefore'); const p = parentNode(toNodeArg(node, 'setStartBefore')); if (p === null) throw domError('InvalidNodeTypeError', 'The node has no parent'); setBoundary(this, true, p, indexOfChild(node)); },
  setStartAfter(node) { rangeSlot(this); required(arguments, 1, 'setStartAfter'); const p = parentNode(toNodeArg(node, 'setStartAfter')); if (p === null) throw domError('InvalidNodeTypeError', 'The node has no parent'); setBoundary(this, true, p, indexOfChild(node) + 1); },
  setEndBefore(node) { rangeSlot(this); required(arguments, 1, 'setEndBefore'); const p = parentNode(toNodeArg(node, 'setEndBefore')); if (p === null) throw domError('InvalidNodeTypeError', 'The node has no parent'); setBoundary(this, false, p, indexOfChild(node)); },
  setEndAfter(node) { rangeSlot(this); required(arguments, 1, 'setEndAfter'); const p = parentNode(toNodeArg(node, 'setEndAfter')); if (p === null) throw domError('InvalidNodeTypeError', 'The node has no parent'); setBoundary(this, false, p, indexOfChild(node) + 1); },
  collapse(toStart = false) {
    const s = rangeSlot(this);
    if (toStart) { s.endNode = s.startNode; s.endOffset = s.startOffset; } else { s.startNode = s.endNode; s.startOffset = s.endOffset; }
  },
  selectNode(node) {
    const s = rangeSlot(this);
    required(arguments, 1, 'selectNode');
    toNodeArg(node, 'selectNode');
    const p = parentNode(node);
    if (p === null) throw domError('InvalidNodeTypeError', 'The node has no parent');
    const index = indexOfChild(node);
    s.startNode = p; s.startOffset = index; s.endNode = p; s.endOffset = index + 1;
  },
  selectNodeContents(node) {
    const s = rangeSlot(this);
    required(arguments, 1, 'selectNodeContents');
    toNodeArg(node, 'selectNodeContents');
    if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node is a doctype');
    s.startNode = node; s.startOffset = 0; s.endNode = node; s.endOffset = nodeLength(node);
  },
  compareBoundaryPoints(how, sourceRange) {
    const s = rangeSlot(this);
    required(arguments, 2, 'compareBoundaryPoints');
    const h = toUnsignedShort(how);
    if (!isObject(sourceRange) || !slotOf(sourceRange) || !slotOf(sourceRange).isRange) throw new TypeError("Failed to execute 'compareBoundaryPoints' on 'Range': parameter 2 is not of type 'Range'.");
    if (h > 3) throw domError('NotSupportedError', 'The comparison method provided must be one of START_TO_START, START_TO_END, END_TO_END, or END_TO_START.');
    const o = slotOf(sourceRange);
    if (rootNode(s.startNode) !== rootNode(o.startNode)) throw domError('WrongDocumentError', 'The two Ranges are not in the same tree.');
    let thisNode, thisOffset, otherNode, otherOffset;
    switch (h) {
      case 0: thisNode = s.startNode; thisOffset = s.startOffset; otherNode = o.startNode; otherOffset = o.startOffset; break;
      case 1: thisNode = s.endNode; thisOffset = s.endOffset; otherNode = o.startNode; otherOffset = o.startOffset; break;
      case 2: thisNode = s.endNode; thisOffset = s.endOffset; otherNode = o.endNode; otherOffset = o.endOffset; break;
      default: thisNode = s.startNode; thisOffset = s.startOffset; otherNode = o.endNode; otherOffset = o.endOffset;
    }
    return comparePoints(thisNode, thisOffset, otherNode, otherOffset);
  },
  deleteContents() { const s = rangeSlot(this); deleteRangeContents(this); },
  extractContents() { rangeSlot(this); return extractRange(this); },
  cloneContents() { rangeSlot(this); return cloneRangeContents(this); },
  insertNode(node) {
    const s = rangeSlot(this);
    required(arguments, 1, 'insertNode');
    toNodeArg(node, 'insertNode');
    const sn = s.startNode;
    const t = nodeType(sn);
    if (t === PROCESSING_INSTRUCTION_NODE || t === COMMENT_NODE || (t === TEXT_NODE && parentNode(sn) === null) || node === sn) throw domError('HierarchyRequestError', 'The range start is not a valid insertion point');
    let referenceNode = null;
    if (t === TEXT_NODE) referenceNode = sn;
    else referenceNode = childrenOf(sn)[s.startOffset] || null;
    const parent = referenceNode === null ? sn : parentNode(referenceNode);
    ensurePreInsertionValidity(node, parent, referenceNode);
    if (t === TEXT_NODE) referenceNode = splitText(sn, s.startOffset);
    if (node === referenceNode) referenceNode = nextSibling(referenceNode);
    const oldParent = parentNode(node);
    if (oldParent !== null) removeNode(node, false);
    let newOffset = referenceNode === null ? nodeLength(parent) : indexOfChild(referenceNode);
    newOffset += nodeType(node) === DOCUMENT_FRAGMENT_NODE ? nodeLength(node) : 1;
    preInsert(node, parent, referenceNode);
    if (s.startNode === s.endNode && s.startOffset === s.endOffset) { s.endNode = parent; s.endOffset = newOffset; }
  },
  surroundContents(newParent) {
    const s = rangeSlot(this);
    required(arguments, 1, 'surroundContents');
    toNodeArg(newParent, 'surroundContents');
    const ca = commonAncestor(s.startNode, s.endNode);
    for (const n of descendantsOf(ca)) {
      if (nodeType(n) !== TEXT_NODE && nodeType(n) !== CDATA_SECTION_NODE && partiallyContained(n, this)) throw domError('InvalidStateError', 'The range partially selects a non-Text node');
    }
    const t = nodeType(newParent);
    if (t === DOCUMENT_NODE || t === DOCUMENT_TYPE_NODE || t === DOCUMENT_FRAGMENT_NODE) throw domError('InvalidNodeTypeError', 'The new parent has an invalid type');
    const fragment = extractRange(this);
    if (firstChild(newParent) !== null) replaceAllWith(newParent, null);
    Range.prototype.insertNode.call(this, newParent);
    preInsert(fragment, newParent, null);
    Range.prototype.selectNode.call(this, newParent);
  },
  cloneRange() {
    const s = rangeSlot(this);
    const r = new Range();
    const rs = slotOf(r);
    rs.startNode = s.startNode; rs.startOffset = s.startOffset; rs.endNode = s.endNode; rs.endOffset = s.endOffset;
    return r;
  },
  detach() { rangeSlot(this); },
  isPointInRange(node, offset) {
    const s = rangeSlot(this);
    required(arguments, 2, 'isPointInRange');
    toNodeArg(node, 'isPointInRange');
    const off = toUnsignedLong(offset);
    if (rootNode(node) !== rootNode(s.startNode)) return false;
    if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node is a doctype');
    if (off > nodeLength(node)) throw domError('IndexSizeError', 'The offset is larger than the node length');
    return !(comparePoints(node, off, s.startNode, s.startOffset) === -1 || comparePoints(node, off, s.endNode, s.endOffset) === 1);
  },
  comparePoint(node, offset) {
    const s = rangeSlot(this);
    required(arguments, 2, 'comparePoint');
    toNodeArg(node, 'comparePoint');
    const off = toUnsignedLong(offset);
    if (rootNode(node) !== rootNode(s.startNode)) throw domError('WrongDocumentError', 'The node is not in the same tree as the range');
    if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node is a doctype');
    if (off > nodeLength(node)) throw domError('IndexSizeError', 'The offset is larger than the node length');
    if (comparePoints(node, off, s.startNode, s.startOffset) === -1) return -1;
    if (comparePoints(node, off, s.endNode, s.endOffset) === 1) return 1;
    return 0;
  },
  intersectsNode(node) {
    const s = rangeSlot(this);
    required(arguments, 1, 'intersectsNode');
    toNodeArg(node, 'intersectsNode');
    if (rootNode(node) !== rootNode(s.startNode)) return false;
    const p = parentNode(node);
    if (p === null) return true;
    const offset = indexOfChild(node);
    return comparePoints(p, offset, s.endNode, s.endOffset) === -1 && comparePoints(p, offset + 1, s.startNode, s.startOffset) === 1;
  },
  toString() {
    const s = rangeSlot(this);
    let out = '';
    if (s.startNode === s.endNode && nodeType(s.startNode) === TEXT_NODE) return N.value(idOf(s.startNode)).slice(s.startOffset, s.endOffset);
    if (nodeType(s.startNode) === TEXT_NODE) out += N.value(idOf(s.startNode)).slice(s.startOffset);
    const ca = commonAncestor(s.startNode, s.endNode);
    for (const d of descendantsOf(ca)) {
      if (nodeType(d) === TEXT_NODE && contained(d, this)) out += N.value(idOf(d));
    }
    if (nodeType(s.endNode) === TEXT_NODE) out += N.value(idOf(s.endNode)).slice(0, s.endOffset);
    return out;
  },
  createContextualFragment(fragment) {
    const s = rangeSlot(this);
    required(arguments, 1, 'createContextualFragment');
    const markup = toDOMString(fragment);
    let node = s.startNode;
    const t = nodeType(node);
    let element = null;
    if (t === DOCUMENT_NODE || t === DOCUMENT_FRAGMENT_NODE) element = null;
    else if (t === ELEMENT_NODE) element = node;
    else element = parentElement(node);
    if (element === null || (slotOf(element).localName === 'html' && slotOf(element).namespaceURI === HTML_NS && isHTMLDocument(slotOf(element).doc))) element = createElementInternal(ownerDocOrSelf(node), 'body', HTML_NS, null, null, false);
    return parseFragment(element, markup);
  },
  getBoundingClientRect() { rangeSlot(this); return makeDOMRect(0, 0, 0, 0); },
  getClientRects() { rangeSlot(this); return []; }
});
attributes(Range.prototype, {
  commonAncestorContainer: { get() { const s = rangeSlot(this); return commonAncestor(s.startNode, s.endNode); } }
});
attributes(AbstractRange.prototype, {
  startContainer: { get() { const s = slotOf(this); if (!s || (!s.isRange && !s.isStaticRange)) illegal(); return s.startNode; } },
  startOffset: { get() { const s = slotOf(this); if (!s || (!s.isRange && !s.isStaticRange)) illegal(); return s.startOffset; } },
  endContainer: { get() { const s = slotOf(this); if (!s || (!s.isRange && !s.isStaticRange)) illegal(); return s.endNode; } },
  endOffset: { get() { const s = slotOf(this); if (!s || (!s.isRange && !s.isStaticRange)) illegal(); return s.endOffset; } },
  collapsed: { get() { const s = slotOf(this); if (!s || (!s.isRange && !s.isStaticRange)) illegal(); return s.startNode === s.endNode && s.startOffset === s.endOffset; } }
});
let makeDOMRect = (x, y, w, h) => ({ x, y, width: w, height: h, top: y, left: x, right: x + w, bottom: y + h });

// --- deleteContents / extractContents / cloneContents

function deleteRangeContents(range) {
  const s = slotOf(range);
  if (s.startNode === s.endNode && s.startOffset === s.endOffset) return;
  const originalStartNode = s.startNode, originalStartOffset = s.startOffset, originalEndNode = s.endNode, originalEndOffset = s.endOffset;
  if (originalStartNode === originalEndNode && isCharacterData(nodeType(originalStartNode))) {
    replaceData(originalStartNode, originalStartOffset, originalEndOffset - originalStartOffset, '');
    return;
  }
  const nodesToRemove = [];
  const ca = commonAncestor(originalStartNode, originalEndNode);
  for (const d of descendantsOf(ca)) if (contained(d, range) && !contained(parentNode(d), range)) apply(arrayPush, nodesToRemove, [d]);
  let newNode, newOffset;
  if (isInclusiveAncestor(originalStartNode, originalEndNode)) { newNode = originalStartNode; newOffset = originalStartOffset; }
  else {
    let referenceNode = originalStartNode;
    while (parentNode(referenceNode) !== null && !isInclusiveAncestor(parentNode(referenceNode), originalEndNode)) referenceNode = parentNode(referenceNode);
    newNode = parentNode(referenceNode);
    newOffset = indexOfChild(referenceNode) + 1;
  }
  if (isCharacterData(nodeType(originalStartNode))) replaceData(originalStartNode, originalStartOffset, nodeLength(originalStartNode) - originalStartOffset, '');
  for (const n of nodesToRemove) removeNode(n, false);
  if (isCharacterData(nodeType(originalEndNode))) replaceData(originalEndNode, 0, originalEndOffset, '');
  s.startNode = newNode; s.startOffset = newOffset; s.endNode = newNode; s.endOffset = newOffset;
}
function extractRange(range) {
  const s = slotOf(range);
  const fragment = createFragmentNode(ownerDocOrSelf(s.startNode));
  if (s.startNode === s.endNode && s.startOffset === s.endOffset) return fragment;
  const originalStartNode = s.startNode, originalStartOffset = s.startOffset, originalEndNode = s.endNode, originalEndOffset = s.endOffset;
  if (originalStartNode === originalEndNode && isCharacterData(nodeType(originalStartNode))) {
    const clone = cloneNode(originalStartNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalStartNode, originalStartOffset, originalEndOffset - originalStartOffset));
    appendNodeSimple(fragment, clone);
    replaceData(originalStartNode, originalStartOffset, originalEndOffset - originalStartOffset, '');
    return fragment;
  }
  const ca = commonAncestor(originalStartNode, originalEndNode);
  let firstPartiallyContainedChild = null, lastPartiallyContainedChild = null;
  if (!isInclusiveAncestor(originalStartNode, originalEndNode)) for (const c of childrenOf(ca)) if (partiallyContained(c, range)) { firstPartiallyContainedChild = c; break; }
  if (!isInclusiveAncestor(originalEndNode, originalStartNode)) { const kids = childrenOf(ca); for (let i = kids.length - 1; i >= 0; i--) if (partiallyContained(kids[i], range)) { lastPartiallyContainedChild = kids[i]; break; } }
  const containedChildren = childrenOf(ca).filter(c => contained(c, range));
  for (const c of containedChildren) if (nodeType(c) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'The range contains a doctype');
  let newNode, newOffset;
  if (isInclusiveAncestor(originalStartNode, originalEndNode)) { newNode = originalStartNode; newOffset = originalStartOffset; }
  else {
    let referenceNode = originalStartNode;
    while (parentNode(referenceNode) !== null && !isInclusiveAncestor(parentNode(referenceNode), originalEndNode)) referenceNode = parentNode(referenceNode);
    newNode = parentNode(referenceNode);
    newOffset = indexOfChild(referenceNode) + 1;
  }
  if (firstPartiallyContainedChild !== null && isCharacterData(nodeType(firstPartiallyContainedChild))) {
    const clone = cloneNode(originalStartNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalStartNode, originalStartOffset, nodeLength(originalStartNode) - originalStartOffset));
    appendNodeSimple(fragment, clone);
    replaceData(originalStartNode, originalStartOffset, nodeLength(originalStartNode) - originalStartOffset, '');
  } else if (firstPartiallyContainedChild !== null) {
    const clone = cloneNode(firstPartiallyContainedChild, undefined, false);
    appendNodeSimple(fragment, clone);
    const subrange = new Range();
    const ss = slotOf(subrange);
    ss.startNode = originalStartNode; ss.startOffset = originalStartOffset; ss.endNode = firstPartiallyContainedChild; ss.endOffset = nodeLength(firstPartiallyContainedChild);
    const subfragment = extractRange(subrange);
    preInsert(subfragment, clone, null);
  }
  for (const c of containedChildren) preInsert(c, fragment, null);
  if (lastPartiallyContainedChild !== null && isCharacterData(nodeType(lastPartiallyContainedChild))) {
    const clone = cloneNode(originalEndNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalEndNode, 0, originalEndOffset));
    appendNodeSimple(fragment, clone);
    replaceData(originalEndNode, 0, originalEndOffset, '');
  } else if (lastPartiallyContainedChild !== null) {
    const clone = cloneNode(lastPartiallyContainedChild, undefined, false);
    appendNodeSimple(fragment, clone);
    const subrange = new Range();
    const ss = slotOf(subrange);
    ss.startNode = lastPartiallyContainedChild; ss.startOffset = 0; ss.endNode = originalEndNode; ss.endOffset = originalEndOffset;
    const subfragment = extractRange(subrange);
    preInsert(subfragment, clone, null);
  }
  s.startNode = newNode; s.startOffset = newOffset; s.endNode = newNode; s.endOffset = newOffset;
  return fragment;
}
function cloneRangeContents(range) {
  const s = slotOf(range);
  const fragment = createFragmentNode(ownerDocOrSelf(s.startNode));
  if (s.startNode === s.endNode && s.startOffset === s.endOffset) return fragment;
  const originalStartNode = s.startNode, originalStartOffset = s.startOffset, originalEndNode = s.endNode, originalEndOffset = s.endOffset;
  if (originalStartNode === originalEndNode && isCharacterData(nodeType(originalStartNode))) {
    const clone = cloneNode(originalStartNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalStartNode, originalStartOffset, originalEndOffset - originalStartOffset));
    appendNodeSimple(fragment, clone);
    return fragment;
  }
  const ca = commonAncestor(originalStartNode, originalEndNode);
  let firstPartiallyContainedChild = null, lastPartiallyContainedChild = null;
  if (!isInclusiveAncestor(originalStartNode, originalEndNode)) for (const c of childrenOf(ca)) if (partiallyContained(c, range)) { firstPartiallyContainedChild = c; break; }
  if (!isInclusiveAncestor(originalEndNode, originalStartNode)) { const kids = childrenOf(ca); for (let i = kids.length - 1; i >= 0; i--) if (partiallyContained(kids[i], range)) { lastPartiallyContainedChild = kids[i]; break; } }
  const containedChildren = childrenOf(ca).filter(c => contained(c, range));
  for (const c of containedChildren) if (nodeType(c) === DOCUMENT_TYPE_NODE) throw domError('HierarchyRequestError', 'The range contains a doctype');
  if (firstPartiallyContainedChild !== null && isCharacterData(nodeType(firstPartiallyContainedChild))) {
    const clone = cloneNode(originalStartNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalStartNode, originalStartOffset, nodeLength(originalStartNode) - originalStartOffset));
    appendNodeSimple(fragment, clone);
  } else if (firstPartiallyContainedChild !== null) {
    const clone = cloneNode(firstPartiallyContainedChild, undefined, false);
    appendNodeSimple(fragment, clone);
    const subrange = new Range();
    const ss = slotOf(subrange);
    ss.startNode = originalStartNode; ss.startOffset = originalStartOffset; ss.endNode = firstPartiallyContainedChild; ss.endOffset = nodeLength(firstPartiallyContainedChild);
    preInsert(cloneRangeContents(subrange), clone, null);
  }
  for (const c of containedChildren) appendNodeSimple(fragment, cloneNode(c, undefined, true));
  if (lastPartiallyContainedChild !== null && isCharacterData(nodeType(lastPartiallyContainedChild))) {
    const clone = cloneNode(originalEndNode, undefined, false);
    N.setValue(idOf(clone), substringData(originalEndNode, 0, originalEndOffset));
    appendNodeSimple(fragment, clone);
  } else if (lastPartiallyContainedChild !== null) {
    const clone = cloneNode(lastPartiallyContainedChild, undefined, false);
    appendNodeSimple(fragment, clone);
    const subrange = new Range();
    const ss = slotOf(subrange);
    ss.startNode = lastPartiallyContainedChild; ss.startOffset = 0; ss.endNode = originalEndNode; ss.endOffset = originalEndOffset;
    preInsert(cloneRangeContents(subrange), clone, null);
  }
  return fragment;
}

// --- live range maintenance

rangeInsertAdjust = function (r, parent, child, count) {
  const s = slotOf(r);
  const index = indexOfChild(child);
  if (s.startNode === parent && s.startOffset > index) s.startOffset += count;
  if (s.endNode === parent && s.endOffset > index) s.endOffset += count;
};
rangeRemoveAdjust = function (r, node, parent, index) {
  const s = slotOf(r);
  if (isInclusiveAncestor(node, s.startNode)) { s.startNode = parent; s.startOffset = index; }
  if (isInclusiveAncestor(node, s.endNode)) { s.endNode = parent; s.endOffset = index; }
  if (s.startNode === parent && s.startOffset > index) s.startOffset--;
  if (s.endNode === parent && s.endOffset > index) s.endOffset--;
};
rangeReplaceDataAdjust = function (r, node, offset, count, dataLength) {
  const s = slotOf(r);
  if (s.startNode === node && s.startOffset > offset && s.startOffset <= offset + count) s.startOffset = offset;
  if (s.endNode === node && s.endOffset > offset && s.endOffset <= offset + count) s.endOffset = offset;
  if (s.startNode === node && s.startOffset > offset + count) s.startOffset += dataLength - count;
  if (s.endNode === node && s.endOffset > offset + count) s.endOffset += dataLength - count;
};
rangeSplitAdjust = function (r, node, newNode, offset, parent) {
  const s = slotOf(r);
  if (s.startNode === node && s.startOffset > offset) { s.startNode = newNode; s.startOffset -= offset; }
  if (s.endNode === node && s.endOffset > offset) { s.endNode = newNode; s.endOffset -= offset; }
  const index = indexOfChild(node);
  if (s.startNode === parent && s.startOffset === index + 1) s.startOffset++;
  if (s.endNode === parent && s.endOffset === index + 1) s.endOffset++;
};
adjustRangesForMerge = function (cur, node, length) {
  const parent = parentNode(cur);
  const index = indexOfChild(cur);
  for (const r of liveRanges) {
    const s = slotOf(r);
    if (s.startNode === cur) { s.startNode = node; s.startOffset += length; }
    if (s.endNode === cur) { s.endNode = node; s.endOffset += length; }
    if (s.startNode === parent && s.startOffset === index) { s.startNode = node; s.startOffset = length; }
    if (s.endNode === parent && s.endOffset === index) { s.endNode = node; s.endOffset = length; }
  }
};

// --- StaticRange

function StaticRange(init) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'StaticRange': Please use the 'new' operator");
  required(arguments, 1, 'StaticRange');
  if (!isObject(init)) throw new TypeError("Failed to construct 'StaticRange': The provided value is not of type 'StaticRangeInit'.");
  for (const key of ['startContainer', 'startOffset', 'endContainer', 'endOffset']) if (init[key] === undefined) throw new TypeError("Failed to construct 'StaticRange': required member " + key + ' is undefined.');
  if (!isNode(init.startContainer) || !isNode(init.endContainer)) throw new TypeError("Failed to construct 'StaticRange': node is not of type 'Node'.");
  if (nodeType(init.startContainer) === DOCUMENT_TYPE_NODE || nodeType(init.startContainer) === ATTRIBUTE_NODE || nodeType(init.endContainer) === DOCUMENT_TYPE_NODE || nodeType(init.endContainer) === ATTRIBUTE_NODE) throw domError('InvalidNodeTypeError', 'The container is a doctype or attribute');
  setSlot(this, { isStaticRange: true, startNode: init.startContainer, startOffset: toUnsignedLong(init.startOffset), endNode: init.endContainer, endOffset: toUnsignedLong(init.endOffset) });
}
iface('StaticRange', StaticRange, AbstractRange);

// --- Document.createRange
operations(Document.prototype, { createRange() { docSlot(this); const r = new Range(); const s = slotOf(r); s.startNode = this; s.endNode = this; return r; } });
// Selection is modelled elsewhere; the range of a fresh document starts at the document.
