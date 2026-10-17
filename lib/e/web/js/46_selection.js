// Selection API: the one range of the document and its direction.

function Selection() { throw new TypeError('Illegal constructor'); }
iface('Selection', Selection, null);
const selectionObject = create(Selection.prototype);
setSlot(selectionObject, { isSelection: true, range: null, forwards: true, directionless: true });
function selectionSlot(o) { const s = slotOf(o); if (!s || !s.isSelection) illegal(); return s; }
function inSelectableTree(node) { return rootNode(node) === mainDocument; }
function selectionNodeArg(node, method, n) {
  if (!isNode(node)) throw new TypeError("Failed to execute '" + method + "' on 'Selection': parameter " + n + " is not of type 'Node'.");
  return node;
}
function checkOffset(node, offset) {
  if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node provided is a doctype');
  if (offset > nodeLength(node)) throw domError('IndexSizeError', 'The offset ' + offset + ' is larger than the node\'s length (' + nodeLength(node) + ').');
}
function newSelectionRange(startNode, startOffset, endNode, endOffset) {
  const r = new Range();
  const rs = slotOf(r);
  rs.startNode = startNode; rs.startOffset = startOffset; rs.endNode = endNode; rs.endOffset = endOffset;
  return r;
}
function setSelectionRange(sel, range, forwards) {
  const s = slotOf(sel);
  if (s.range !== null) slotOf(s.range).selection = null;
  s.range = range;
  if (range !== null) slotOf(range).selection = sel;
  s.forwards = forwards;
  s.directionless = range === null ? true : false;
}
function selectionAnchor(s) { if (s.range === null) return null; const r = slotOf(s.range); return s.forwards ? [r.startNode, r.startOffset] : [r.endNode, r.endOffset]; }
function selectionFocus(s) { if (s.range === null) return null; const r = slotOf(s.range); return s.forwards ? [r.endNode, r.endOffset] : [r.startNode, r.startOffset]; }
attributes(Selection.prototype, {
  anchorNode: { get() { const a = selectionAnchor(selectionSlot(this)); return a === null ? null : a[0]; } },
  anchorOffset: { get() { const a = selectionAnchor(selectionSlot(this)); return a === null ? 0 : a[1]; } },
  focusNode: { get() { const a = selectionFocus(selectionSlot(this)); return a === null ? null : a[0]; } },
  focusOffset: { get() { const a = selectionFocus(selectionSlot(this)); return a === null ? 0 : a[1]; } },
  isCollapsed: { get() { const s = selectionSlot(this); if (s.range === null) return true; const r = slotOf(s.range); return r.startNode === r.endNode && r.startOffset === r.endOffset; } },
  rangeCount: { get() { return selectionSlot(this).range === null ? 0 : 1; } },
  type: { get() { const s = selectionSlot(this); if (s.range === null) return 'None'; const r = slotOf(s.range); return r.startNode === r.endNode && r.startOffset === r.endOffset ? 'Caret' : 'Range'; } },
  direction: { get() { const s = selectionSlot(this); return s.range === null || s.directionless ? 'none' : s.forwards ? 'forward' : 'backward'; } }
});
operations(Selection.prototype, {
  getRangeAt(index) {
    const s = selectionSlot(this);
    required(arguments, 1, 'getRangeAt');
    if (toUnsignedLong(index) !== 0 || s.range === null) throw domError('IndexSizeError', 'The index is out of range');
    return s.range;
  },
  addRange(range) {
    const s = selectionSlot(this);
    required(arguments, 1, 'addRange');
    if (!isObject(range) || !slotOf(range) || !slotOf(range).isRange) throw new TypeError("Failed to execute 'addRange' on 'Selection': parameter 1 is not of type 'Range'.");
    if (!inSelectableTree(slotOf(range).startNode)) return;
    if (s.range !== null) return;
    setSelectionRange(this, range, true);
  },
  removeRange(range) {
    const s = selectionSlot(this);
    required(arguments, 1, 'removeRange');
    if (!isObject(range) || !slotOf(range) || !slotOf(range).isRange) throw new TypeError("Failed to execute 'removeRange' on 'Selection': parameter 1 is not of type 'Range'.");
    if (s.range !== range) throw domError('NotFoundError', 'The range is not in the selection');
    setSelectionRange(this, null, true);
  },
  removeAllRanges() { selectionSlot(this); setSelectionRange(this, null, true); },
  empty() { selectionSlot(this); setSelectionRange(this, null, true); },
  collapse(node, offset = 0) {
    selectionSlot(this);
    required(arguments, 1, 'collapse');
    if (node === null) { setSelectionRange(this, null, true); return; }
    selectionNodeArg(node, 'collapse', 1);
    const o = toUnsignedLong(offset);
    checkOffset(node, o);
    if (!inSelectableTree(node)) return;
    setSelectionRange(this, newSelectionRange(node, o, node, o), true);
  },
  setPosition(node, offset = 0) { this.collapse(node, offset); },
  collapseToStart() {
    const s = selectionSlot(this);
    if (s.range === null) throw domError('InvalidStateError', 'There is no selection to collapse');
    const r = slotOf(s.range);
    setSelectionRange(this, newSelectionRange(r.startNode, r.startOffset, r.startNode, r.startOffset), true);
  },
  collapseToEnd() {
    const s = selectionSlot(this);
    if (s.range === null) throw domError('InvalidStateError', 'There is no selection to collapse');
    const r = slotOf(s.range);
    setSelectionRange(this, newSelectionRange(r.endNode, r.endOffset, r.endNode, r.endOffset), true);
  },
  extend(node, offset = 0) {
    const s = selectionSlot(this);
    required(arguments, 1, 'extend');
    selectionNodeArg(node, 'extend', 1);
    const o = toUnsignedLong(offset);
    if (!inSelectableTree(node)) return;
    if (s.range === null) throw domError('InvalidStateError', 'This Selection object doesn\'t have any Ranges.');
    checkOffset(node, o);
    const anchor = selectionAnchor(s);
    let r, fwd = true;
    if (rootNode(anchor[0]) !== rootNode(node)) r = newSelectionRange(node, o, node, o);
    else if (comparePoints(anchor[0], anchor[1], node, o) <= 0) r = newSelectionRange(anchor[0], anchor[1], node, o);
    else { r = newSelectionRange(node, o, anchor[0], anchor[1]); fwd = false; }
    setSelectionRange(this, r, fwd);
  },
  setBaseAndExtent(anchorNode, anchorOffset, focusNode, focusOffset) {
    selectionSlot(this);
    required(arguments, 4, 'setBaseAndExtent');
    selectionNodeArg(anchorNode, 'setBaseAndExtent', 1);
    selectionNodeArg(focusNode, 'setBaseAndExtent', 3);
    const ao = toUnsignedLong(anchorOffset), fo = toUnsignedLong(focusOffset);
    checkOffset(anchorNode, ao);
    checkOffset(focusNode, fo);
    if (!inSelectableTree(anchorNode) || !inSelectableTree(focusNode)) return;
    if (comparePoints(anchorNode, ao, focusNode, fo) <= 0) setSelectionRange(this, newSelectionRange(anchorNode, ao, focusNode, fo), true);
    else setSelectionRange(this, newSelectionRange(focusNode, fo, anchorNode, ao), false);
  },
  selectAllChildren(node) {
    selectionSlot(this);
    required(arguments, 1, 'selectAllChildren');
    selectionNodeArg(node, 'selectAllChildren', 1);
    if (nodeType(node) === DOCUMENT_TYPE_NODE) throw domError('InvalidNodeTypeError', 'The node provided is a doctype');
    if (!inSelectableTree(node)) return;
    setSelectionRange(this, newSelectionRange(node, 0, node, nodeLength(node)), true);
  },
  deleteFromDocument() { const s = selectionSlot(this); if (s.range !== null) s.range.deleteContents(); },
  containsNode(node, allowPartialContainment = false) {
    const s = selectionSlot(this);
    required(arguments, 1, 'containsNode');
    selectionNodeArg(node, 'containsNode', 1);
    if (s.range === null) return false;
    const r = slotOf(s.range);
    if (rootNode(node) !== rootNode(r.startNode)) return false;
    const parent = parentNode(node);
    if (parent === null) return true;
    const index = indexOfChild(node);
    const startsBeforeEnd = comparePoints(r.startNode, r.startOffset, parent, index + 1) < 0;
    const endsAfterStart = comparePoints(r.endNode, r.endOffset, parent, index) > 0;
    if (allowPartialContainment) return startsBeforeEnd && endsAfterStart;
    return comparePoints(r.startNode, r.startOffset, parent, index) <= 0 && comparePoints(r.endNode, r.endOffset, parent, index + 1) >= 0;
  },
  getComposedRanges() { selectionSlot(this); const s = slotOf(this); return s.range === null ? [] : [new StaticRange({ startContainer: slotOf(s.range).startNode, startOffset: slotOf(s.range).startOffset, endContainer: slotOf(s.range).endNode, endOffset: slotOf(s.range).endOffset })]; },
  modify() { selectionSlot(this); },
  toString() { const s = selectionSlot(this); return s.range === null ? '' : s.range.toString(); }
});
defineProperty(global, 'getSelection', { value: function getSelection() { return selectionObject; }, writable: true, enumerable: true, configurable: true });
Document.prototype.getSelection = function getSelection() { docSlot(this); return slotOf(this).browsingContext ? selectionObject : null; };
defineProperty(Document.prototype, 'getSelection', { enumerable: true });
