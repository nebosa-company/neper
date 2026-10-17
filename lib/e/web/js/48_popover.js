// The popover API, dialog and details behaviour (HTML Standard 6.12, 4.11).

const ToggleEvent = defineEventClass('ToggleEvent', Event, [['oldState', '', asString], ['newState', '', asString], ['source', null, asAny]]);

// --- popover attribute and state

function popoverStateOf(el) {
  const v = getAttributeValue(el, 'popover');
  if (v === null) return null;
  const l = asciiLowercase(v);
  if (l === '' || l === 'auto') return 'auto';
  if (l === 'hint') return 'hint';
  return 'manual';
}
attributes(HTMLElement.prototype, {
  popover: {
    get() { elSlot(this); return popoverStateOf(this); },
    set(v) { elSlot(this); if (v === null) removeAttributeByName(this, 'popover'); else setAttributeValue(this, 'popover', toDOMString(v)); }
  }
});
const popoverStack = [];       // showing auto popovers, oldest first
const hintStack = [];          // showing hint popovers
function popoverData(el) { const s = slotOf(el); if (!s.popover) s.popover = { showing: false, invoker: null, toggleTask: null, previousFocus: null, opener: null }; return s.popover; }
function isShowingPopover(el) { return popoverStateOf(el) !== null && popoverData(el).showing; }

function fireToggleEvent(type, el, oldState, newState, cancelable, source) {
  const ev = new ToggleEvent(type, { bubbles: false, cancelable, oldState, newState, source: source === undefined ? null : source });
  slotOf(ev).isTrusted = true;
  return dispatch(ev, el);
}
function checkPopoverValidity(el, expectedToBeShowing, throwExceptions, source) {
  const state = popoverStateOf(el);
  if (state === null) { if (throwExceptions) throw domError('NotSupportedError', 'Not supported on elements that do not have a valid value for the "popover" attribute.'); return false; }
  const data = popoverData(el);
  if (expectedToBeShowing && !data.showing) return false;
  if (!expectedToBeShowing && data.showing) return false;
  if (!isConnected(el)) { if (throwExceptions) throw domError('InvalidStateError', 'Invalid on disconnected popover elements.'); return false; }
  if (htmlLocal(el) === 'dialog' && (getAttributeValue(el, 'open') !== null)) { if (throwExceptions) throw domError('InvalidStateError', 'The dialog is open and cannot be a popover.'); return false; }
  if (!expectedToBeShowing && htmlLocal(el) === 'dialog' && nodeFlag(el, F_MODAL)) { if (throwExceptions) throw domError('InvalidStateError', 'The dialog is modal.'); return false; }
  return true;
}
function topmostPopoverAncestor(el, invoker, stack) {
  const chain = [];
  for (let n = el; n !== null; n = parentNode(n) || (isShadowRoot(n) ? shadowHost(n) : null)) apply(arrayPush, chain, [n]);
  if (invoker) for (let n = invoker; n !== null; n = parentNode(n) || (isShadowRoot(n) ? shadowHost(n) : null)) apply(arrayPush, chain, [n]);
  let best = null;
  for (const p of stack) if (p !== el && chain.indexOf(p) >= 0) best = p;
  return best;
}
function hideAllPopoversUntil(ancestor, focusPrevious, fireEvents, stack) {
  while (stack.length > 0 && stack[stack.length - 1] !== ancestor) {
    const top = stack[stack.length - 1];
    hidePopoverInternal(top, focusPrevious, fireEvents);
    if (stack[stack.length - 1] === top) stack.pop();
  }
}
function showPopoverInternal(el, invoker) {
  const state = popoverStateOf(el), data = popoverData(el);
  let shouldRestoreFocus = false;
  let ancestor = null;
  if (state === 'auto' || state === 'hint') ancestor = topmostPopoverAncestor(el, invoker, state === 'hint' ? popoverStack.concat(hintStack) : popoverStack);
  if (!fireToggleEvent('beforetoggle', el, 'closed', 'open', true, invoker)) return;
  if (!checkPopoverValidity(el, false, false, invoker)) return;
  if (state === 'auto') {
    // The popovers above the new one's ancestor close.
    hideAllPopoversUntil(ancestor, false, true, popoverStack);
    if (!checkPopoverValidity(el, false, false, invoker) ) return;
  } else if (state === 'hint') {
    hideAllPopoversUntil(ancestor && hintStack.indexOf(ancestor) >= 0 ? ancestor : null, false, true, hintStack);
    if (!checkPopoverValidity(el, false, false, invoker)) return;
  }
  data.previousFocus = slotOf(slotOf(el).doc).focused || null;
  data.invoker = invoker || null;
  data.showing = true;
  if (state === 'auto') apply(arrayPush, popoverStack, [el]);
  else if (state === 'hint') apply(arrayPush, hintStack, [el]);
  setNodeFlags(el, F_POPOVER_OPEN, true);
  // popover focusing steps
  const target = autofocusDelegate(el);
  if (target) { try { target.focus(); } catch (e) {} }
  queuePopoverToggle(el, 'closed', 'open');
}
function autofocusDelegate(el) {
  if (getAttributeValue(el, 'autofocus') !== null && isFocusableArea(el)) return el;
  for (const d of descendantsOf(el)) if (nodeType(d) === ELEMENT_NODE && getAttributeValue(d, 'autofocus') !== null && isFocusableArea(d)) return d;
  return null;
}
function queuePopoverToggle(el, oldState, newState) {
  const data = popoverData(el);
  if (data.toggleTask !== null) { oldState = data.toggleTask.oldState; data.toggleTask.cancelled = true; data.toggleTask = null; }
  const task = { oldState, cancelled: false };
  data.toggleTask = task;
  scheduleTimer(() => {
    if (task.cancelled) return;
    data.toggleTask = null;
    fireToggleEvent('toggle', el, oldState, newState, false, undefined);
  }, 0, false, []);
}
function hidePopoverInternal(el, focusPrevious, fireEvents) {
  const state = popoverStateOf(el), data = popoverData(el);
  if (!data.showing) return;
  if (state === 'auto') {
    // Popovers shown after this one close first.
    const idx = popoverStack.indexOf(el);
    while (popoverStack.length - 1 > idx && idx >= 0) {
      const top = popoverStack[popoverStack.length - 1];
      hidePopoverInternal(top, false, fireEvents);
      if (popoverStack[popoverStack.length - 1] === top) popoverStack.pop();
    }
  }
  if (fireEvents) fireToggleEvent('beforetoggle', el, 'open', 'closed', false, undefined);
  if (!data.showing) return;
  data.showing = false;
  const si = popoverStack.indexOf(el); if (si >= 0) popoverStack.splice(si, 1);
  const hi = hintStack.indexOf(el); if (hi >= 0) hintStack.splice(hi, 1);
  setNodeFlags(el, F_POPOVER_OPEN, false);
  data.invoker = null;
  if (fireEvents) queuePopoverToggle(el, 'open', 'closed');
  if (focusPrevious && data.previousFocus !== null && data.previousFocus.isConnected) { try { data.previousFocus.focus(); } catch (e) {} }
  data.previousFocus = null;
}
operations(HTMLElement.prototype, {
  showPopover(options = undefined) {
    elSlot(this);
    let source = null;
    if (options !== undefined && options !== null) {
      if (!isObject(options)) throw new TypeError("Failed to execute 'showPopover' on 'HTMLElement': parameter 1 is not of type 'ShowPopoverOptions'.");
      if (options.source !== undefined && options.source !== null) {
        if (!isNode(options.source) || nodeType(options.source) !== ELEMENT_NODE || !(options.source instanceof HTMLElement)) throw new TypeError("Failed to execute 'showPopover' on 'HTMLElement': Failed to read the 'source' property: the provided value is not of type 'HTMLElement'.");
        source = options.source;
      }
    }
    if (!checkPopoverValidity(this, false, true, source)) return;
    showPopoverInternal(this, source);
  },
  hidePopover() {
    elSlot(this);
    if (!checkPopoverValidity(this, true, true, null)) return;
    hidePopoverInternal(this, true, true);
  },
  togglePopover(options = undefined) {
    elSlot(this);
    let force;
    let source = null;
    if (typeof options === 'boolean') force = options;
    else if (isObject(options)) {
      if (options.force !== undefined) force = !!options.force;
      if (options.source !== undefined && options.source !== null) {
        if (!isNode(options.source) || nodeType(options.source) !== ELEMENT_NODE) throw new TypeError("Failed to execute 'togglePopover' on 'HTMLElement': Failed to read the 'source' property: the provided value is not of type 'HTMLElement'.");
        source = options.source;
      }
    } else if (options !== undefined && options !== null) force = !!options;
    const showing = isShowingPopover(this);
    if (showing && (force === undefined || force === false)) {
      if (checkPopoverValidity(this, true, true, null)) hidePopoverInternal(this, true, true);
    } else if (force === undefined || force === true) {
      if (!showing) { if (checkPopoverValidity(this, false, true, source)) showPopoverInternal(this, source); }
      else checkPopoverValidity(this, true, true, null);
    } else checkPopoverValidity(this, showing, true, null);
    return isShowingPopover(this);
  }
});
// invokers
function sameOrAncestorTree(el, t) {
  let r = rootNode(el);
  for (let i = 0; i < 64; i++) {
    if (rootNode(t) === r) return true;
    if (isShadowRoot(r)) r = rootNode(shadowHost(r)); else return false;
  }
  return false;
}
function popoverTargetOf(el) {
  const s = slotOf(el);
  if (s.popoverTargetExplicit !== undefined && s.popoverTargetExplicit !== null) return sameOrAncestorTree(el, s.popoverTargetExplicit) ? s.popoverTargetExplicit : null;
  const id = getAttributeValue(el, 'popovertarget');
  if (id === null) return null;
  return findByIdInTree(rootNode(el), id);
}
for (const name of ['HTMLButtonElement', 'HTMLInputElement']) {
  attributes(P(name), {
    popoverTargetElement: {
      get() { elSlot(this); return popoverTargetOf(this); },
      set(v) {
        const s = elSlot(this);
        if (v !== null && !(isNode(v) && nodeType(v) === ELEMENT_NODE)) throw new TypeError("Failed to set the 'popoverTargetElement' property: The provided value is not an Element.");
        s.popoverTargetExplicit = v;
        if (v === null) removeAttributeByName(this, 'popovertarget'); else setAttributeValue(this, 'popovertarget', '');
      }
    },
    popoverTargetAction: {
      get() { elSlot(this); const v = getAttributeValue(this, 'popovertargetaction'); if (v === null) return 'toggle'; const l = asciiLowercase(v); return l === 'show' || l === 'hide' ? l : 'toggle'; },
      set(v) { elSlot(this); setAttributeValue(this, 'popovertargetaction', toDOMString(v)); }
    }
  });
}
function isRetargetable(a, b) { return true; }
function popoverInvokerBehavior(el) {
  const target = popoverTargetOf(el);
  if (target === null || popoverStateOf(target) === null) return;
  const l = getAttributeValue(el, 'popovertargetaction');
  const action = l === null ? 'toggle' : (asciiLowercase(l) === 'show' ? 'show' : asciiLowercase(l) === 'hide' ? 'hide' : 'toggle');
  const showing = isShowingPopover(target);
  if (showing && (action === 'hide' || action === 'toggle')) { if (checkPopoverValidity(target, true, false, null)) hidePopoverInternal(target, true, true); }
  else if (!showing && (action === 'show' || action === 'toggle')) { if (checkPopoverValidity(target, false, false, el)) showPopoverInternal(target, el); }
}

// Removing the attribute or the element closes the popover (no events); an element that stops being a popover too.
const prevAttrPopover = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrPopover(el, name, oldValue, value);
  if (name === 'popover' && htmlLocal(el) !== null) {
    const s = slotOf(el);
    if (s.popover && s.popover.showing && (popoverStateOf(el) === null || (oldValue !== null && popoverStateOf(el) !== normalizePopover(oldValue)))) hidePopoverInternal(el, false, false);
  } else if (name === 'open' && htmlLocal(el) === 'details') detailsToggled(el, oldValue, value);
  else if (name === 'open' && htmlLocal(el) === 'dialog') dialogOpenChanged(el, oldValue, value);
};
function normalizePopover(v) { const l = asciiLowercase(v); return l === '' || l === 'auto' ? 'auto' : l === 'hint' ? 'hint' : 'manual'; }
const prevRemovedPopover = elementRemoved;
elementRemoved = function (el, parent) {
  prevRemovedPopover(el, parent);
  const s = slotOf(el);
  if (s.popover && s.popover.showing) hidePopoverInternal(el, false, false);
  if (htmlLocal(el) === 'dialog' && nodeFlag(el, F_MODAL)) { setNodeFlags(el, F_MODAL, false); slotOf(el).dialog = undefined; }
};
// light dismiss
document_addDismiss();
function document_addDismiss() {
  mainDocument.addEventListener('click', event => {
    if (popoverStack.length === 0) return;
    const target = event.target;
    if (!isNodeObject(target)) return;
    let ancestor = null;
    for (const p of popoverStack) { let n = target; while (n !== null) { if (n === p) { ancestor = p; break; } n = parentNode(n) || (isShadowRoot(n) ? shadowHost(n) : null); } }
    // clicking an invoker of a showing popover is handled by the invoker
    for (const p of popoverStack) { const inv = popoverData(p).invoker; if (inv && (inv === target || isInclusiveAncestor(inv, target))) ancestor = p; }
    // a click on a control that names a showing popover is that control's business
    for (let n = target; n !== null; n = parentNode(n)) {
      if (nodeType(n) === ELEMENT_NODE && (htmlLocal(n) === 'button' || htmlLocal(n) === 'input')) { const t = popoverTargetOf(n); if (t !== null && popoverStack.indexOf(t) >= 0) ancestor = t; }
    }
    hideAllPopoversUntil(ancestor, false, true, popoverStack);
  }, true);
  mainDocument.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    if (popoverStack.length > 0) { const top = popoverStack[popoverStack.length - 1]; hidePopoverInternal(top, true, true); }
  });
}

// --- dialog

function dialogData(el) { const s = slotOf(el); if (!s.dialog) s.dialog = { modal: false, previousFocus: null, returnValue: '' }; return s.dialog; }
attributes(P('HTMLDialogElement'), {
  returnValue: { get() { elSlot(this); return dialogData(this).returnValue; }, set(v) { elSlot(this); dialogData(this).returnValue = toDOMString(v); } },
  closedBy: { get() { elSlot(this); const v = getAttributeValue(this, 'closedby'); const l = v === null ? '' : asciiLowercase(v); return l === 'any' || l === 'closerequest' || l === 'none' ? l : 'auto'; }, set(v) { elSlot(this); setAttributeValue(this, 'closedby', toDOMString(v)); } }
});
function dialogOpenChanged(el, oldValue, value) {
  if (value === null && oldValue !== null) {
    const d = dialogData(el);
    if (d.modal) { d.modal = false; setNodeFlags(el, F_MODAL, false); }
  }
}
function setDialogFocus(el) {
  const target = autofocusDelegate(el);
  if (target) { try { target.focus(); } catch (e) {} return; }
  for (const d of descendantsOf(el)) if (nodeType(d) === ELEMENT_NODE && isFocusableArea(d)) { try { d.focus(); } catch (e) {} return; }
}
operations(P('HTMLDialogElement'), {
  show() {
    elSlot(this);
    if (getAttributeValue(this, 'open') !== null) { if (dialogData(this).modal) throw domError('InvalidStateError', 'The dialog is already open as a modal dialog, and therefore cannot be opened as a non-modal dialog.'); return; }
    if (popoverStateOf(this) !== null && popoverData(this).showing) throw domError('InvalidStateError', 'The dialog is already open as a popover, and therefore cannot be opened as a non-modal dialog.');
    if (!fireToggleEvent('beforetoggle', this, 'closed', 'open', true, undefined)) return;
    if (getAttributeValue(this, 'open') !== null) return;
    if (popoverStateOf(this) !== null && popoverData(this).showing) return;
    setAttributeValue(this, 'open', '');
    dialogData(this).previousFocus = slotOf(slotOf(this).doc).focused || null;
    setDialogFocus(this);
  },
  showModal() {
    elSlot(this);
    if (getAttributeValue(this, 'open') !== null) { if (dialogData(this).modal) return; throw domError('InvalidStateError', 'The dialog is already open as a non-modal dialog, and therefore cannot be opened as a modal dialog.'); }
    if (!isConnected(this)) throw domError('InvalidStateError', 'The element is not in a Document.');
    if (popoverStateOf(this) !== null && popoverData(this).showing) throw domError('InvalidStateError', 'The dialog is already open as a popover, and therefore cannot be opened as a modal dialog.');
    if (!fireToggleEvent('beforetoggle', this, 'closed', 'open', true, undefined)) return;
    if (getAttributeValue(this, 'open') !== null) return;
    if (!isConnected(this)) return;
    if (popoverStateOf(this) !== null && popoverData(this).showing) return;
    setAttributeValue(this, 'open', '');
    const d = dialogData(this);
    d.modal = true;
    setNodeFlags(this, F_MODAL, true);
    d.previousFocus = slotOf(slotOf(this).doc).focused || null;
    // popovers close when a modal dialog opens
    hideAllPopoversUntil(null, false, true, popoverStack);
    setDialogFocus(this);
  },
  close(returnValue = undefined) {
    elSlot(this);
    if (getAttributeValue(this, 'open') === null) return;
    closeDialog(this, returnValue === undefined ? undefined : toDOMString(returnValue));
  },
  requestClose(returnValue = undefined) {
    elSlot(this);
    if (getAttributeValue(this, 'open') === null) return;
    const rv = returnValue === undefined ? undefined : toDOMString(returnValue);
    const ev = new Event('cancel', { bubbles: false, cancelable: true });
    slotOf(ev).isTrusted = true;
    if (dispatch(ev, this)) closeDialog(this, rv);
  }
});
function closeDialog(el, result) {
  const d = dialogData(el);
  const wasModal = d.modal;
  removeAttributeByName(el, 'open');
  d.modal = false;
  setNodeFlags(el, F_MODAL, false);
  if (result !== undefined) d.returnValue = result;
  fireToggleEvent('toggle', el, 'open', 'closed', false, undefined);
  const prev = d.previousFocus;
  d.previousFocus = null;
  scheduleTimer(() => { const ev = new Event('close', { bubbles: false, cancelable: false }); slotOf(ev).isTrusted = true; dispatch(ev, el); }, 0, false, []);
  if (prev !== null && prev.isConnected) { try { prev.focus(); } catch (e) {} }
}
// Escape on a modal dialog fires cancel then closes
mainDocument.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  for (const d of descendantsOf(mainDocument)) {
    if (nodeType(d) === ELEMENT_NODE && htmlLocal(d) === 'dialog' && slotOf(d).dialog && slotOf(d).dialog.modal) {
      const ev = new Event('cancel', { bubbles: false, cancelable: true });
      slotOf(ev).isTrusted = true;
      if (dispatch(ev, d)) closeDialog(d, undefined);
      return;
    }
  }
});

// --- details

function detailsToggled(el, oldValue, value) {
  const opening = value !== null && oldValue === null;
  const closing = value === null && oldValue !== null;
  if (!opening && !closing) return;
  const data = popoverData(el);
  // coalesce with a pending toggle task
  const oldState = opening ? 'closed' : 'open', newState = opening ? 'open' : 'closed';
  const s = slotOf(el);
  let from = oldState;
  if (s.detailsTask) { from = s.detailsTask.oldState; s.detailsTask.cancelled = true; }
  const task = { oldState: from, cancelled: false };
  s.detailsTask = task;
  scheduleTimer(() => { if (task.cancelled) return; s.detailsTask = undefined; fireToggleEvent('toggle', el, task.oldState, newState, false, undefined); }, 0, false, []);
  if (opening) {
    const name = getAttributeValue(el, 'name');
    if (name !== null && name !== '') {
      for (const d of descendantsOf(rootNode(el))) {
        if (d !== el && nodeType(d) === ELEMENT_NODE && htmlLocal(d) === 'details' && getAttributeValue(d, 'name') === name && getAttributeValue(d, 'open') !== null) removeAttributeByName(d, 'open');
      }
    }
  }
}
// Buttons and inputs that name a popover toggle it when activated.
const prevButtonActivation = Object.getOwnPropertyDescriptor(P('HTMLButtonElement'), 'activationBehavior').value;
defineProperty(P('HTMLButtonElement'), 'activationBehavior', { value: function (event) { if (!isDisabledControl(this)) popoverInvokerBehavior(this); apply(prevButtonActivation, this, [event]); }, writable: true, enumerable: false, configurable: true });
const prevInputActivation = Object.getOwnPropertyDescriptor(P('HTMLInputElement'), 'activationBehavior').value;
defineProperty(P('HTMLInputElement'), 'activationBehavior', { value: function (event) { const t = inputTypeOf(this); if (!isDisabledControl(this) && (t === 'button' || t === 'reset' || t === 'submit' || t === 'image')) popoverInvokerBehavior(this); apply(prevInputActivation, this, [event]); }, writable: true, enumerable: false, configurable: true });
