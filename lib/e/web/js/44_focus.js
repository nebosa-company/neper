// Focus: focusable areas, element.focus() / blur(), the focus events and document.activeElement.

isDisabledFormControl = el => isDisabledControl(el);
function hasHref(el) { return getAttributeValue(el, 'href') !== null; }
function focusableByDefault(el) {
  const n = htmlLocal(el);
  if (n === null) return false;
  if (n === 'a' || n === 'area') return hasHref(el);
  if (n === 'input') return inputTypeOf(el) !== 'hidden' && !isDisabledControl(el);
  if (n === 'button' || n === 'select' || n === 'textarea') return !isDisabledControl(el);
  if (n === 'iframe' || n === 'summary' && isSummaryOfDetails(el)) return true;
  if (n === 'audio' || n === 'video') return getAttributeValue(el, 'controls') !== null;
  if (n === 'object' || n === 'embed') return false;
  const ce = getAttributeValue(el, 'contenteditable');
  if (ce !== null) { const l = asciiLowercase(ce); if (l === '' || l === 'true' || l === 'plaintext-only') return true; }
  return false;
}
function isSummaryOfDetails(el) {
  const p = parentNode(el);
  if (p === null || htmlLocal(p) !== 'details') return false;
  for (const c of childrenOf(p)) if (htmlLocal(c) === 'summary') return c === el;
  return false;
}
defaultTabIndex = el => (focusableByDefault(el) ? 0 : -1);
function isFocusableArea(el) {
  if (!el || slotOf(el).nodeType !== ELEMENT_NODE || !isConnected(el)) return false;
  if (isDisabledControl(el)) return false;
  if (htmlLocal(el) === 'input' && inputTypeOf(el) === 'hidden') return false;
  if (parseInteger(getAttributeValue(el, 'tabindex')) !== null) return true;
  return focusableByDefault(el);
}
function fireFocusEvent(type, target, related, bubbles) {
  const ev = new FocusEvent(type, { bubbles, cancelable: false, composed: true, relatedTarget: related, view: global });
  slotOf(ev).isTrusted = true;
  dispatch(ev, target);
}
function focusFlags(el, on) {
  setNodeFlags(el, F_FOCUS, on);
  for (let p = el; p !== null; p = parentNode(p) || (isShadowRoot(p) ? shadowHost(p) : null)) if (nodeType(p) === ELEMENT_NODE) setNodeFlags(p, F_FOCUS_WITHIN, on);
}
function updateFocus(doc, old, nw) {
  const ds = slotOf(doc);
  if (old !== null) focusFlags(old, false);
  if (nw !== null) focusFlags(nw, true);
  if (old !== null) {
    ds.focused = null;
    fireFocusEvent('blur', old, nw, false);
    fireFocusEvent('focusout', old, nw, true);
  }
  if (nw !== null) {
    ds.focused = nw;
    fireFocusEvent('focus', nw, old, false);
    fireFocusEvent('focusin', nw, old, true);
  }
}
focusElement = function (el) {
  if (!isFocusableArea(el)) return;
  const doc = slotOf(el).doc, ds = slotOf(doc);
  const old = ds.focused !== null && isConnected(ds.focused) ? ds.focused : null;
  if (old === el) return;
  updateFocus(doc, old, el);
};
blurElement = function (el) {
  const doc = slotOf(el).doc, ds = slotOf(doc);
  if (ds.focused === el) updateFocus(doc, el, null);
};
