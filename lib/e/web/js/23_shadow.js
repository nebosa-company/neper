// Shadow trees and slots (DOM Standard: shadow roots, slots, slottables, slotchange).

function ShadowRoot() { throw new TypeError('Illegal constructor'); }
iface('ShadowRoot', ShadowRoot, DocumentFragment);
defineHandlerAttrs(ShadowRoot.prototype, ['slotchange']);
function srSlot(o) { const s = slotOf(o); if (!s || s.isShadowRoot !== true) illegal(); return s; }
isShadowRoot = o => { if (!isObject(o) || o === global) return false; const s = slotOf(o); return !!s && s.isShadowRoot === true; };
shadowMode = o => slotOf(o).mode;
shadowHost = o => slotOf(o).host;
isShadowIncludingInclusiveAncestor = (a, b) => hostIncludingInclusiveAncestor(a, b);
sameShadowIncludingRoot = (a, b) => shadowIncludingRoot(a) === shadowIncludingRoot(b);
function shadowIncludingRoot(n) { let r = rootNode(n); while (isShadowRoot(r)) r = rootNode(shadowHost(r)); return r; }
isConnected = function (o) { return nodeType(shadowIncludingRoot(o)) === DOCUMENT_NODE; };
shadowIncludingInclusiveDescendants = function (n) {
  const out = [];
  (function walk(x) {
    apply(arrayPush, out, [x]);
    const s = slotOf(x);
    if (s.shadowRoot) walk(s.shadowRoot);
    for (const k of childrenOf(x)) walk(k);
  })(n);
  return out;
};

const shadowHostNames = ['article', 'aside', 'blockquote', 'body', 'div', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'main', 'nav', 'p', 'section', 'span'];
function attachShadowRoot(el, mode, delegatesFocus, slotAssignment, clonable, serializable) {
  const es = slotOf(el);
  const id = N.mkFragment();
  const w = create(ShadowRoot.prototype);
  const s = setSlot(w, newNodeSlot(id, DOCUMENT_FRAGMENT_NODE, es.doc));
  s.isShadowRoot = true; s.mode = mode; s.host = el; s.delegatesFocus = delegatesFocus; s.slotAssignment = slotAssignment;
  s.clonable = clonable; s.serializable = serializable;
  register(w, id);
  es.shadowRoot = w;
  return w;
}
operations(Element.prototype, {
  attachShadow(init) {
    const es = elSlot(this);
    required(arguments, 1, 'attachShadow');
    if (!isObject(init)) throw new TypeError("Failed to execute 'attachShadow' on 'Element': The provided value is not of type 'ShadowRootInit'.");
    const mode = init.mode === undefined ? undefined : String(init.mode);
    if (mode !== 'open' && mode !== 'closed') throw new TypeError("Failed to execute 'attachShadow' on 'Element': The provided value '" + mode + "' is not a valid enum value of type ShadowRootMode.");
    const sa = init.slotAssignment === undefined ? 'named' : String(init.slotAssignment);
    if (sa !== 'named' && sa !== 'manual') throw new TypeError("Failed to execute 'attachShadow' on 'Element': The provided value '" + sa + "' is not a valid enum value of type SlotAssignmentMode.");
    if (es.namespaceURI !== HTML_NS || !(shadowHostNames.indexOf(es.localName) >= 0 || isValidCustomElementName(es.localName))) throw domError('NotSupportedError', 'This element does not support attachShadow');
    if (es.customDefinition && es.customDefinition.disableShadow) throw domError('NotSupportedError', 'Shadow roots are disabled for this custom element');
    if (es.shadowRoot) throw domError('NotSupportedError', 'Shadow root cannot be created on a host which already hosts a shadow tree.');
    return attachShadowRoot(this, mode, !!init.delegatesFocus, sa, !!init.clonable, !!init.serializable);
  }
});
attributes(Element.prototype, {
  shadowRoot: { get() { const es = elSlot(this); return es.shadowRoot && slotOf(es.shadowRoot).mode === 'open' ? es.shadowRoot : null; } }
});
attributes(ShadowRoot.prototype, {
  mode: { get() { return srSlot(this).mode; } },
  host: { get() { return srSlot(this).host; } },
  delegatesFocus: { get() { return srSlot(this).delegatesFocus; } },
  slotAssignment: { get() { return srSlot(this).slotAssignment; } },
  clonable: { get() { return srSlot(this).clonable; } },
  serializable: { get() { return srSlot(this).serializable; } },
  innerHTML: {
    get() { const s = srSlot(this); return N.innerGet(s.id); },
    set(v) { const s = srSlot(this); setInnerHTML(this, v === null ? '' : toDOMString(v), s.host); }
  },
  activeElement: { get() { srSlot(this); return null; } }
});

// --- slots

function isSlotElement(n) { const s = slotOf(n); return s.nodeType === ELEMENT_NODE && s.localName === 'slot' && s.namespaceURI === HTML_NS; }
function slotsIn(sr) { return descendantsOf(sr).filter(isSlotElement); }
function slotNameOf(slot) { const v = getAttributeValue(slot, 'name'); return v === null ? '' : v; }
function slottableNameOf(n) { if (nodeType(n) !== ELEMENT_NODE) return ''; const v = getAttributeValue(n, 'slot'); return v === null ? '' : v; }
isSlotable = o => { if (!isObject(o) || o === global) return false; const s = slotOf(o); return !!s && s.isNode === true && (s.nodeType === ELEMENT_NODE || s.nodeType === TEXT_NODE); };
function findSlot(node, open, slots) {
  const p = parentNode(node);
  if (p === null || nodeType(p) !== ELEMENT_NODE) return null;
  const sr = slotOf(p).shadowRoot;
  if (!sr) return null;
  if (open && slotOf(sr).mode !== 'open') return null;
  const list = slots || slotsIn(sr);
  if (slotOf(sr).slotAssignment === 'manual') {
    for (const sl of list) { const m = slotOf(sl).manual; if (m && m.indexOf(node) >= 0) return sl; }
    return null;
  }
  const name = slottableNameOf(node);
  for (const sl of list) if (slotNameOf(sl) === name) return sl;
  return null;
}
assignedSlotOf = o => findSlot(o, false);
assignedSlotOfNode = o => { nodeSlot(o); return findSlot(o, true); };
const signalSlots = [];
function signalSlotChange(slot) {
  if (signalSlots.indexOf(slot) < 0) apply(arrayPush, signalSlots, [slot]);
  queueMicrotaskForObservers();
}
function fireSlotChanges() {
  const list = signalSlots.splice(0, signalSlots.length);
  for (const sl of list) fireSimple(sl, 'slotchange', true);
}
function assignSlotsOfShadow(sr) {
  const host = slotOf(sr).host;
  const slots = slotsIn(sr);
  const lists = new Map();
  for (const sl of slots) lists.set(sl, []);
  for (const c of childrenOf(host)) {
    if (!isSlotable(c)) continue;
    const sl = findSlot(c, false, slots);
    if (sl !== null) apply(arrayPush, lists.get(sl), [c]);
  }
  for (const sl of slots) {
    const s = slotOf(sl), now = lists.get(sl), old = s.assigned || [];
    s.assigned = now;
    if (now.length !== old.length || now.some((x, i) => x !== old[i])) signalSlotChange(sl);
  }
}
isShadowHostWithSlots = o => nodeType(o) === ELEMENT_NODE && !!slotOf(o).shadowRoot;
assignSlotablesForTree = host => assignSlotsOfShadow(slotOf(host).shadowRoot);
childrenChanged = function (parent) {
  const root = rootNode(parent);
  if (isShadowRoot(root)) {
    if (nodeType(parent) === ELEMENT_NODE && isSlotElement(parent) && assignedOf(parent).length === 0) signalSlotChange(parent);
    assignSlotsOfShadow(root);
  }
  const ps = slotOf(parent);
  if (ps.nodeType === ELEMENT_NODE && ps.shadowRoot) assignSlotsOfShadow(ps.shadowRoot);
};
elementAttributeChanged = function (el, name, oldValue, value) {
  if (name === 'name' && isSlotElement(el)) {
    const root = rootNode(el);
    if (isShadowRoot(root)) assignSlotsOfShadow(root);
  } else if (name === 'slot') {
    const p = parentNode(el);
    if (p !== null && nodeType(p) === ELEMENT_NODE && slotOf(p).shadowRoot) assignSlotsOfShadow(slotOf(p).shadowRoot);
  }
};
function assignedOf(slot) {
  const root = rootNode(slot);
  if (!isShadowRoot(root)) return [];
  const host = slotOf(root).host;
  const slots = slotsIn(root);
  return childrenOf(host).filter(c => isSlotable(c) && findSlot(c, false, slots) === slot);
}
function flattenSlottables(slot, out) {
  const assigned = assignedOf(slot);
  const items = assigned.length ? assigned : childrenOf(slot).filter(isSlotable);
  for (const n of items) {
    if (nodeType(n) === ELEMENT_NODE && isSlotElement(n) && isShadowRoot(rootNode(n))) flattenSlottables(n, out);
    else apply(arrayPush, out, [n]);
  }
}
function slotElementSlot(o) { const s = slotOf(o); if (!s || s.localName !== 'slot' || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
operations(P('HTMLSlotElement'), {
  assignedNodes(options = undefined) {
    const s = slotElementSlot(this);
    if (options && options.flatten) { const out = []; flattenSlottables(this, out); return out; }
    return assignedOf(this);
  },
  assignedElements(options = undefined) {
    const s = slotElementSlot(this);
    let list;
    if (options && options.flatten) { list = []; flattenSlottables(this, list); } else list = assignedOf(this);
    return list.filter(n => nodeType(n) === ELEMENT_NODE);
  },
  assign(...nodes) {
    const s = slotElementSlot(this);
    for (const n of nodes) if (!isNode(n) || (nodeType(n) !== ELEMENT_NODE && nodeType(n) !== TEXT_NODE)) throw new TypeError("Failed to execute 'assign' on 'HTMLSlotElement': parameter is not of type 'Element or Text'.");
    const root = rootNode(this);
    s.manual = [];
    for (const n of nodes) {
      for (const sl of isShadowRoot(root) ? slotsIn(root) : []) {
        const m = slotOf(sl).manual;
        if (m && sl !== this) { const i = m.indexOf(n); if (i >= 0) m.splice(i, 1); }
      }
      if (s.manual.indexOf(n) < 0) apply(arrayPush, s.manual, [n]);
    }
    if (isShadowRoot(root)) assignSlotsOfShadow(root);
  }
});

// --- shadow trees cloned with their host

function cloneShadow(node, copy) {
  const s = slotOf(node);
  if (s.nodeType !== ELEMENT_NODE || !s.shadowRoot || !slotOf(s.shadowRoot).clonable) return;
  const ss = slotOf(s.shadowRoot);
  const sr = attachShadowRoot(copy, ss.mode, ss.delegatesFocus, ss.slotAssignment, true, ss.serializable);
  for (const c of childrenOf(s.shadowRoot)) appendNodeSimple(sr, cloneNode(c, slotOf(copy).doc, true));
  assignSlotsOfShadow(sr);
}
attributes(Element.prototype, { assignedSlot: { get() { elSlot(this); return findSlot(this, true); } } });
