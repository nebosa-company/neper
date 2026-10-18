// Core of the page's JavaScript environment: WebIDL helpers, DOMException, events, abort signals, timers, console.
// Everything in lib/e/web/js/*.js is concatenated into one function by scripts/gen_web_js.py (generated into dom_js.e), so
// the files share their top-level names. `N` is the table of native primitives from e.web.script.

const N = global.__native;
delete global.__native;

const hasOwn = Object.prototype.hasOwnProperty;
const defineProperty = Object.defineProperty;
const getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
const getPrototypeOf = Object.getPrototypeOf;
const setPrototypeOf = Object.setPrototypeOf;
const create = Object.create;
const apply = Reflect.apply;
const arrayPush = Array.prototype.push;
const arraySlice = Array.prototype.slice;
const arrayIndexOf = Array.prototype.indexOf;
const arraySplice = Array.prototype.splice;
const stringCharCodeAt = String.prototype.charCodeAt;
const symIterator = Symbol.iterator;
const symToStringTag = Symbol.toStringTag;
const construct = Reflect.construct;
const allInterfaces = [];

// --- WebIDL helpers

const slots = new WeakMap();
const slotGet = WeakMap.prototype.get;
const slotSet = WeakMap.prototype.set;
// The intrinsics are own properties of the (unreachable) map, so a call needs no argument array and page code cannot change it.
defineProperty(slots, 'get', { value: slotGet });
defineProperty(slots, 'set', { value: slotSet });
function slotOf(o) { return slots.get(o); }
function setSlot(o, s) { slots.set(o, s); return s; }

function isObject(v) { return (typeof v === 'object' && v !== null) || typeof v === 'function'; }
function illegal() { throw new TypeError('Illegal invocation'); }
function toDOMString(v) {
  if (typeof v === 'symbol') throw new TypeError('Cannot convert a Symbol value to a string');
  return '' + v;
}
function toUSVString(v) {
  const s = toDOMString(v);
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = apply(stringCharCodeAt, s, [i]);
    if (c >= 0xD800 && c <= 0xDBFF) {
      const d = i + 1 < s.length ? apply(stringCharCodeAt, s, [i + 1]) : 0;
      if (d >= 0xDC00 && d <= 0xDFFF) { out += s[i] + s[i + 1]; i++; } else out += '�';
    } else if (c >= 0xDC00 && c <= 0xDFFF) out += '�';
    else out += s[i];
  }
  return out;
}
function toNullableDOMString(v) { return v === null || v === undefined ? null : toDOMString(v); }
function toUnsignedLong(v) {
  let n = +v;
  if (n !== n || n === Infinity || n === -Infinity) return 0;
  n = Math.trunc(n);
  n = ((n % 4294967296) + 4294967296) % 4294967296;
  return n;
}
function toLong(v) {
  const n = toUnsignedLong(v);
  return n >= 2147483648 ? n - 4294967296 : n;
}
function toUnsignedShort(v) {
  let n = +v;
  if (n !== n || n === Infinity || n === -Infinity) return 0;
  n = Math.trunc(n);
  return ((n % 65536) + 65536) % 65536;
}
function toDouble(v) {
  const n = +v;
  if (n !== n || n === Infinity || n === -Infinity) throw new TypeError('The provided value is non-finite');
  return n;
}
function required(args, n, what) {
  if (args.length < n) throw new TypeError(n + ' argument' + (n === 1 ? '' : 's') + ' required, but only ' + args.length + ' present (' + what + ')');
}

// Defines the operations in `ops` (an object literal of methods) as WebIDL operations of `proto`.
function operations(proto, ops) {
  for (const name of Reflect.ownKeys(ops)) {
    const d = getOwnPropertyDescriptor(ops, name);
    defineProperty(proto, name, { value: d.value, writable: true, enumerable: true, configurable: true });
  }
}
// Defines attributes from `{ name: { get, set } }`.
function attributes(proto, attrs) {
  for (const name of Reflect.ownKeys(attrs)) {
    const a = attrs[name];
    const desc = { get: a.get, enumerable: true, configurable: true };
    if (a.set) desc.set = a.set;
    if (a.get) defineProperty(a.get, 'name', { value: 'get ' + String(name), configurable: true });
    if (a.set) defineProperty(a.set, 'name', { value: 'set ' + String(name), configurable: true });
    defineProperty(proto, name, desc);
  }
}
function constants(ctor, consts) {
  for (const name of Object.keys(consts)) {
    defineProperty(ctor, name, { value: consts[name], writable: false, enumerable: true, configurable: false });
    defineProperty(ctor.prototype, name, { value: consts[name], writable: false, enumerable: true, configurable: false });
  }
}
// Registers `ctor` as the interface object `name` on the global object, with its prototype and @@toStringTag.
function iface(name, ctor, parent) {
  defineProperty(ctor, 'name', { value: name, configurable: true });
  defineProperty(ctor, 'prototype', { value: ctor.prototype, writable: false, enumerable: false, configurable: false });
  defineProperty(ctor.prototype, 'constructor', { value: ctor, writable: true, enumerable: false, configurable: true });
  if (parent) { setPrototypeOf(ctor, parent); setPrototypeOf(ctor.prototype, parent.prototype); }
  defineProperty(ctor.prototype, symToStringTag, { value: name, writable: false, enumerable: false, configurable: true });
  defineProperty(global, name, { value: ctor, writable: true, enumerable: false, configurable: true });
  apply(arrayPush, allInterfaces, [ctor]);
  return ctor;
}
// A fresh interface constructor function that throws unless it is being called as `new` from the environment.
function makeIllegal(name) {
  const f = { [name]: function () { throw new TypeError('Illegal constructor'); } }[name];
  return f;
}
function legacyConstants(ctor, consts) { constants(ctor, consts); }

// --- DOMException

const exceptionCodes = {
  IndexSizeError: 1, HierarchyRequestError: 3, WrongDocumentError: 4, InvalidCharacterError: 5, NoModificationAllowedError: 7,
  NotFoundError: 8, NotSupportedError: 9, InUseAttributeError: 10, InvalidStateError: 11, SyntaxError: 12,
  InvalidModificationError: 13, NamespaceError: 14, InvalidAccessError: 15, TypeMismatchError: 17, SecurityError: 18,
  NetworkError: 19, AbortError: 20, URLMismatchError: 21, QuotaExceededError: 22, TimeoutError: 23, InvalidNodeTypeError: 24,
  DataCloneError: 25
};
const exceptionConsts = {
  INDEX_SIZE_ERR: 1, DOMSTRING_SIZE_ERR: 2, HIERARCHY_REQUEST_ERR: 3, WRONG_DOCUMENT_ERR: 4, INVALID_CHARACTER_ERR: 5,
  NO_DATA_ALLOWED_ERR: 6, NO_MODIFICATION_ALLOWED_ERR: 7, NOT_FOUND_ERR: 8, NOT_SUPPORTED_ERR: 9, INUSE_ATTRIBUTE_ERR: 10,
  INVALID_STATE_ERR: 11, SYNTAX_ERR: 12, INVALID_MODIFICATION_ERR: 13, NAMESPACE_ERR: 14, INVALID_ACCESS_ERR: 15,
  VALIDATION_ERR: 16, TYPE_MISMATCH_ERR: 17, SECURITY_ERR: 18, NETWORK_ERR: 19, ABORT_ERR: 20, URL_MISMATCH_ERR: 21,
  QUOTA_EXCEEDED_ERR: 22, TIMEOUT_ERR: 23, INVALID_NODE_TYPE_ERR: 24, DATA_CLONE_ERR: 25
};

function DOMException(message = undefined, name = 'Error') {
  if (new.target === undefined) throw new TypeError("Class constructor DOMException cannot be invoked without 'new'");
  setSlot(this, { message: message === undefined ? '' : toDOMString(message), name: toDOMString(name) });
}
setPrototypeOf(DOMException.prototype, Error.prototype);
attributes(DOMException.prototype, {
  name: { get() { const s = slotOf(this); if (!s) illegal(); return s.name; } },
  message: { get() { const s = slotOf(this); if (!s) illegal(); return s.message; } },
  code: { get() { const s = slotOf(this); if (!s) illegal(); return hasOwn.call(exceptionCodes, s.name) ? exceptionCodes[s.name] : 0; } }
});
iface('DOMException', DOMException, null);
setPrototypeOf(DOMException.prototype, Error.prototype);
setPrototypeOf(DOMException, Function.prototype);
constants(DOMException, exceptionConsts);

function domError(name, message) { return new DOMException(message === undefined ? '' : message, name); }

// --- events

const NONE = 0, CAPTURING_PHASE = 1, AT_TARGET = 2, BUBBLING_PHASE = 3;

function currentTime() { return N.now(); }

function Event(type, eventInitDict = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Event': Please use the 'new' operator");
  required(arguments, 1, 'Event');
  const s = initEvent(this, toDOMString(type), eventInitDict);
}
function initEvent(ev, type, init) {
  if (init !== undefined && init !== null && !isObject(init)) throw new TypeError('The provided value is not of type EventInit');
  const s = setSlot(ev, {
    type, target: null, currentTarget: null, phase: NONE, stopProp: false, stopImmediate: false, canceled: false,
    inPassive: false, composed: false, bubbles: false, cancelable: false, dispatch: false, initialized: true, path: [],
    isTrusted: false, timeStamp: currentTime(), relatedTarget: null, touchTargets: []
  });
  if (init) {
    s.bubbles = !!init.bubbles;
    s.cancelable = !!init.cancelable;
    s.composed = !!init.composed;
  }
  defineProperty(ev, 'isTrusted', { get: isTrustedGetter, enumerable: true, configurable: false });
  return s;
}
function isTrustedGetter() { const s = slotOf(this); if (!s || s.type === undefined) illegal(); return s.isTrusted; }
defineProperty(isTrustedGetter, 'name', { value: 'isTrusted', configurable: true });
function evSlot(o) { const s = slotOf(o); if (!s || s.type === undefined) illegal(); return s; }
function setCanceled(s) { if (s.cancelable && !s.inPassive) s.canceled = true; }

operations(Event.prototype, {
  composedPath() {
    const s = evSlot(this);
    const out = [];
    const path = s.path;
    if (path.length === 0) return out;
    const currentTarget = s.currentTarget;
    out.push(currentTarget);
    let currentTargetIndex = 0, currentTargetHiddenSubtreeLevel = 0;
    for (let index = path.length - 1; index >= 0; index--) {
      if (path[index].rootOfClosedTree) currentTargetHiddenSubtreeLevel++;
      if (path[index].invocationTarget === currentTarget) { currentTargetIndex = index; break; }
      if (path[index].slotInClosedTree) currentTargetHiddenSubtreeLevel--;
    }
    let currentHiddenLevel = currentTargetHiddenSubtreeLevel, maxHiddenLevel = currentTargetHiddenSubtreeLevel;
    for (let index = currentTargetIndex - 1; index >= 0; index--) {
      if (path[index].rootOfClosedTree) currentHiddenLevel++;
      if (currentHiddenLevel <= maxHiddenLevel) out.unshift(path[index].invocationTarget);
      if (path[index].slotInClosedTree) { currentHiddenLevel--; if (currentHiddenLevel < maxHiddenLevel) maxHiddenLevel = currentHiddenLevel; }
    }
    currentHiddenLevel = currentTargetHiddenSubtreeLevel;
    maxHiddenLevel = currentTargetHiddenSubtreeLevel;
    for (let index = currentTargetIndex + 1; index < path.length; index++) {
      if (path[index].slotInClosedTree) currentHiddenLevel++;
      if (currentHiddenLevel <= maxHiddenLevel) out.push(path[index].invocationTarget);
      if (path[index].rootOfClosedTree) { currentHiddenLevel--; if (currentHiddenLevel < maxHiddenLevel) maxHiddenLevel = currentHiddenLevel; }
    }
    return out;
  },
  stopPropagation() { evSlot(this).stopProp = true; },
  stopImmediatePropagation() { const s = evSlot(this); s.stopProp = true; s.stopImmediate = true; },
  preventDefault() { setCanceled(evSlot(this)); },
  initEvent(type, bubbles = false, cancelable = false) {
    const s = evSlot(this);
    required(arguments, 1, 'initEvent');
    if (s.dispatch) return;
    s.stopProp = false; s.stopImmediate = false; s.canceled = false; s.isTrusted = false; s.target = null;
    s.type = toDOMString(type); s.bubbles = !!bubbles; s.cancelable = !!cancelable; s.initialized = true;
  }
});
attributes(Event.prototype, {
  type: { get() { return evSlot(this).type; } },
  target: { get() { return evSlot(this).target; } },
  srcElement: { get() { return evSlot(this).target; } },
  currentTarget: { get() { return evSlot(this).currentTarget; } },
  eventPhase: { get() { return evSlot(this).phase; } },
  cancelBubble: { get() { return evSlot(this).stopProp; }, set(v) { const s = evSlot(this); if (v) s.stopProp = true; } },
  bubbles: { get() { return evSlot(this).bubbles; } },
  cancelable: { get() { return evSlot(this).cancelable; } },
  returnValue: { get() { return !evSlot(this).canceled; }, set(v) { const s = evSlot(this); if (!v) setCanceled(s); } },
  defaultPrevented: { get() { return evSlot(this).canceled; } },
  composed: { get() { return evSlot(this).composed; } },
  timeStamp: { get() { return evSlot(this).timeStamp; } }
});
iface('Event', Event, null);
constants(Event, { NONE, CAPTURING_PHASE, AT_TARGET, BUBBLING_PHASE });

// Subclasses that only add init-dictionary members (read in the constructor from `fields`, a list of [name, default, convert]).
const eventClassFields = new Map();
function defineEventClass(name, parent, ownFields, extra) {
  const fields = (eventClassFields.get(parent) || []).concat(ownFields);
  const C = {
    [name]: function (type, eventInitDict = undefined) {
      if (new.target === undefined) throw new TypeError("Failed to construct '" + name + "': Please use the 'new' operator");
      required(arguments, 1, name);
      const s = initEvent(this, toDOMString(type), eventInitDict);
      const state = {};
      for (const f of fields) {
        let v = eventInitDict !== undefined && eventInitDict !== null ? eventInitDict[f[0]] : undefined;
        v = v === undefined ? f[1] : f[2](v);
        state[f[0]] = v;
      }
      s.extra = state;
      if (extra) extra(this, s, eventInitDict);
    }
  }[name];
  const attrs = {};
  for (const f of ownFields) {
    const key = f[0];
    attrs[key] = { get() { const s = evSlot(this); if (!s.extra) illegal(); return s.extra[key]; } };
  }
  attributes(C.prototype, attrs);
  iface(name, C, parent);
  eventClassFields.set(C, fields);
  return C;
}
const asBool = v => !!v;
const asString = v => toDOMString(v);
const asAny = v => v;
const asUL = v => toUnsignedLong(v);
const asDouble = v => toDouble(v);

const CustomEvent = defineEventClass('CustomEvent', Event, [['detail', null, asAny]]);
operations(CustomEvent.prototype, {
  initCustomEvent(type, bubbles = false, cancelable = false, detail = null) {
    const s = evSlot(this);
    required(arguments, 1, 'initCustomEvent');
    if (s.dispatch) return;
    s.stopProp = false; s.stopImmediate = false; s.canceled = false; s.isTrusted = false; s.target = null;
    s.type = toDOMString(type); s.bubbles = !!bubbles; s.cancelable = !!cancelable;
    s.extra.detail = detail;
  }
});
const ErrorEvent = defineEventClass('ErrorEvent', Event, [['message', '', asString], ['filename', '', asString], ['lineno', 0, asUL], ['colno', 0, asUL], ['error', undefined, asAny]]);
const ProgressEvent = defineEventClass('ProgressEvent', Event, [['lengthComputable', false, asBool], ['loaded', 0, asDouble], ['total', 0, asDouble]]);
const MessageEvent = defineEventClass('MessageEvent', Event, [['data', null, asAny], ['origin', '', asString], ['lastEventId', '', asString], ['source', null, asAny], ['ports', [], asAny]]);
const CloseEvent = defineEventClass('CloseEvent', Event, [['wasClean', false, asBool], ['code', 0, toUnsignedShort], ['reason', '', asString]]);
const PromiseRejectionEvent = defineEventClass('PromiseRejectionEvent', Event, [['promise', undefined, asAny], ['reason', undefined, asAny]]);
const HashChangeEvent = defineEventClass('HashChangeEvent', Event, [['oldURL', '', asString], ['newURL', '', asString]]);
const PopStateEvent = defineEventClass('PopStateEvent', Event, [['state', null, asAny]]);
const PageTransitionEvent = defineEventClass('PageTransitionEvent', Event, [['persisted', false, asBool]]);
const StorageEvent = defineEventClass('StorageEvent', Event, [['key', null, v => v === null ? null : toDOMString(v)], ['oldValue', null, v => v === null ? null : toDOMString(v)], ['newValue', null, v => v === null ? null : toDOMString(v)], ['url', '', asString], ['storageArea', null, asAny]]);
const UIEvent = defineEventClass('UIEvent', Event, [['view', null, asAny], ['detail', 0, toLong], ['which', 0, asUL]]);
const FocusEvent = defineEventClass('FocusEvent', UIEvent, [['relatedTarget', null, asAny]]);
const InputEvent = defineEventClass('InputEvent', UIEvent, [['data', null, v => v === null ? null : toDOMString(v)], ['isComposing', false, asBool], ['inputType', '', asString]]);
const CompositionEvent = defineEventClass('CompositionEvent', UIEvent, [['data', '', asString]]);
const MouseEvent = defineEventClass('MouseEvent', UIEvent, [
  ['screenX', 0, toLong], ['screenY', 0, toLong], ['clientX', 0, toLong], ['clientY', 0, toLong],
  ['ctrlKey', false, asBool], ['shiftKey', false, asBool], ['altKey', false, asBool], ['metaKey', false, asBool],
  ['button', 0, toLong], ['buttons', 0, toUnsignedShort], ['relatedTarget', null, asAny]
]);
const WheelEvent = defineEventClass('WheelEvent', MouseEvent, [['deltaX', 0, asDouble], ['deltaY', 0, asDouble], ['deltaZ', 0, asDouble], ['deltaMode', 0, asUL]]);
const KeyboardEvent = defineEventClass('KeyboardEvent', UIEvent, [
  ['key', '', asString], ['code', '', asString], ['location', 0, asUL], ['ctrlKey', false, asBool], ['shiftKey', false, asBool],
  ['altKey', false, asBool], ['metaKey', false, asBool], ['repeat', false, asBool], ['isComposing', false, asBool], ['charCode', 0, asUL], ['keyCode', 0, asUL]
]);
const PointerEvent = defineEventClass('PointerEvent', MouseEvent, [['pointerId', 0, toLong], ['width', 1, asDouble], ['height', 1, asDouble], ['pressure', 0, asDouble], ['pointerType', '', asString], ['isPrimary', false, asBool]]);
const TransitionEvent = defineEventClass('TransitionEvent', Event, [['propertyName', '', asString], ['elapsedTime', 0, asDouble], ['pseudoElement', '', asString]]);
const AnimationEvent = defineEventClass('AnimationEvent', Event, [['animationName', '', asString], ['elapsedTime', 0, asDouble], ['pseudoElement', '', asString]]);
const BeforeUnloadEvent = defineEventClass('BeforeUnloadEvent', Event, []);
constants(MouseEvent, {});
constants(WheelEvent, { DOM_DELTA_PIXEL: 0, DOM_DELTA_LINE: 1, DOM_DELTA_PAGE: 2 });
constants(KeyboardEvent, { DOM_KEY_LOCATION_STANDARD: 0, DOM_KEY_LOCATION_LEFT: 1, DOM_KEY_LOCATION_RIGHT: 2, DOM_KEY_LOCATION_NUMPAD: 3 });

// --- EventTarget

function EventTarget() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'EventTarget': Please use the 'new' operator");
  setSlot(this, { listeners: [], isTarget: true });
}
function targetSlot(o) {
  if (o === undefined || o === null) o = global;
  let s = slotOf(o);
  if (!s || !s.isTarget) {
    if (o === global && !s) s = setSlot(o, { listeners: [], isTarget: true });
    else illegal();
  }
  return s;
}
function flattenOptions(options) {
  if (typeof options === 'boolean') return { capture: options };
  if (options === undefined || options === null) return { capture: false };
  if (!isObject(options)) return { capture: !!options };
  return { capture: !!options.capture };
}
function flattenMoreOptions(options) {
  const out = { capture: false, once: false, passive: undefined, signal: undefined };
  if (typeof options === 'boolean') { out.capture = options; return out; }
  if (options === undefined || options === null) return out;
  if (!isObject(options)) { out.capture = !!options; return out; }
  out.capture = !!options.capture;
  out.once = !!options.once;
  if (options.passive !== undefined) out.passive = !!options.passive;
  if (options.signal !== undefined) {
    if (!isObject(options.signal) || !isAbortSignal(options.signal)) throw new TypeError("Failed to execute 'addEventListener': member signal is not of type AbortSignal.");
    out.signal = options.signal;
  }
  return out;
}
function addListener(target, listener) {
  const s = targetSlot(target);
  if (listener.signal && slotOf(listener.signal).aborted) return;
  if (listener.callback === null) return;
  for (const l of s.listeners) {
    if (l.type === listener.type && l.callback === listener.callback && l.capture === listener.capture) return;
  }
  if (listener.passive === undefined) {
    listener.passive = (listener.type === 'touchstart' || listener.type === 'touchmove' || listener.type === 'wheel' || listener.type === 'mousewheel') &&
      (target === global || (target.nodeType === 9) || target === (global.document && global.document.documentElement) || target === (global.document && global.document.body));
  }
  apply(arrayPush, s.listeners, [listener]);
  if (listener.signal) {
    const sig = slotOf(listener.signal);
    apply(arrayPush, sig.algorithms, [() => removeListener(target, listener)]);
  }
}
function removeListener(target, listener) {
  const s = targetSlot(target);
  listener.removed = true;
  const i = apply(arrayIndexOf, s.listeners, [listener]);
  if (i >= 0) apply(arraySplice, s.listeners, [i, 1]);
}
function callbackOf(c) {
  if (c === null || c === undefined) return null;
  if (!isObject(c)) throw new TypeError('parameter 2 is not of type EventListener');
  return c;
}

operations(EventTarget.prototype, {
  addEventListener(type, callback, options = undefined) {
    targetSlot(this);
    required(arguments, 2, 'addEventListener');
    const t = toDOMString(type);
    const cb = callbackOf(callback);
    const o = flattenMoreOptions(options);
    addListener(this === undefined || this === null ? global : this, { type: t, callback: cb, capture: o.capture, passive: o.passive, once: o.once, signal: o.signal, removed: false });
  },
  removeEventListener(type, callback, options = undefined) {
    const s = targetSlot(this);
    required(arguments, 2, 'removeEventListener');
    const t = toDOMString(type);
    const cb = callbackOf(callback);
    const capture = flattenOptions(options).capture;
    for (const l of s.listeners) {
      if (l.type === t && l.callback === cb && l.capture === capture) { removeListener(this === undefined || this === null ? global : this, l); break; }
    }
  },
  dispatchEvent(event) {
    targetSlot(this);
    const self = this === undefined || this === null ? global : this;
    required(arguments, 1, 'dispatchEvent');
    if (!isObject(event) || !slotOf(event) || slotOf(event).type === undefined) throw new TypeError("Failed to execute 'dispatchEvent' on 'EventTarget': parameter 1 is not of type 'Event'.");
    const s = slotOf(event);
    if (s.dispatch || !s.initialized) throw domError('InvalidStateError', 'The event is already being dispatched');
    s.isTrusted = false;
    return dispatch(event, self);
  }
});
iface('EventTarget', EventTarget, null);

let inEventDispatch = 0;
function getTheParent(target, event) {
  if (target === global) return null;
  const s = slotOf(target);
  if (s && s.getTheParent) return apply(s.getTheParent, target, [event]);
  return null;
}

function dispatch(event, target, legacyTargetOverride, legacyOutput) {
  const s = slotOf(event);
  s.dispatch = true;
  let targetOverride = legacyTargetOverride ? legacyTargetOverride : target;
  let activationTarget = null;
  let relatedTarget = retarget(s.relatedTarget, target);
  s.path = [];
  let clearTargets = false;
  if (target !== relatedTarget || target === s.relatedTarget) {
    const touchTargets = [];
    appendToPath(s, target, targetOverride, relatedTarget, touchTargets, false);
    const isActivationEvent = s.isMouseClick === true || (event instanceof MouseEvent && s.type === 'click');
    if (isActivationEvent && hasActivationBehavior(target)) activationTarget = target;
    let slotable = isSlotable(target) && assignedSlotOf(target) ? target : null;
    let slotInClosedTree = false;
    let parent = getTheParent(target, event);
    while (parent !== null) {
      if (slotable !== null) {
        slotable = null;
        if (isShadowRoot(parent) && shadowMode(parent) === 'closed') slotInClosedTree = true;
      }
      if (isSlotable(parent) && assignedSlotOf(parent)) slotable = parent;
      relatedTarget = retarget(s.relatedTarget, parent);
      const touch = [];
      if (isWindowLike(parent) || (isNodeObject(parent) && isNodeObject(targetOverride) && isShadowIncludingInclusiveAncestor(rootOf(targetOverride), parent))) {
        if (isActivationEvent && s.bubbles && activationTarget === null && hasActivationBehavior(parent)) activationTarget = parent;
        appendToPath(s, parent, null, relatedTarget, touch, slotInClosedTree);
      } else if (parent === relatedTarget) {
        parent = null;
      } else {
        targetOverride = parent;
        if (isActivationEvent && activationTarget === null && hasActivationBehavior(parent)) activationTarget = parent;
        appendToPath(s, parent, targetOverride, relatedTarget, touch, slotInClosedTree);
      }
      if (parent !== null) parent = getTheParent(parent, event);
      slotInClosedTree = false;
    }
    let clearTargetsStructIndex = -1;
    for (let i = s.path.length - 1; i >= 0; i--) {
      if (s.path[i].shadowAdjustedTarget !== null) { clearTargetsStructIndex = i; break; }
    }
    const cts = s.path[clearTargetsStructIndex];
    clearTargets = (isNodeObject(cts.shadowAdjustedTarget) && isShadowRoot(rootOf(cts.shadowAdjustedTarget))) ||
      (isNodeObject(cts.relatedTarget) && isShadowRoot(rootOf(cts.relatedTarget)));
    if (activationTarget !== null && activationTarget.legacyPreActivationBehavior) activationTarget.legacyPreActivationBehavior(event);
    for (let i = s.path.length - 1; i >= 0; i--) {
      const st = s.path[i];
      s.phase = st.shadowAdjustedTarget !== null ? AT_TARGET : CAPTURING_PHASE;
      invoke(st, event, 'capturing', legacyOutput);
    }
    for (let i = 0; i < s.path.length; i++) {
      const st = s.path[i];
      if (st.shadowAdjustedTarget !== null) s.phase = AT_TARGET;
      else { if (!s.bubbles) continue; s.phase = BUBBLING_PHASE; }
      invoke(st, event, 'bubbling', legacyOutput);
    }
  }
  s.phase = NONE;
  s.currentTarget = null;
  s.path = [];
  s.dispatch = false;
  s.stopProp = false;
  s.stopImmediate = false;
  if (clearTargets) { s.target = null; s.relatedTarget = null; s.touchTargets = []; }
  if (activationTarget !== null) {
    if (!s.canceled) { if (activationTarget.activationBehavior) activationTarget.activationBehavior(event); }
    else if (activationTarget.legacyCanceledActivationBehavior) activationTarget.legacyCanceledActivationBehavior();
  }
  return !s.canceled;
}
function appendToPath(s, invocationTarget, shadowAdjustedTarget, relatedTarget, touchTargets, slotInClosedTree) {
  let invocationTargetInShadowTree = false, rootOfClosedTree = false;
  if (isNodeObject(invocationTarget)) {
    if (isShadowRoot(rootOf(invocationTarget))) invocationTargetInShadowTree = true;
    if (isShadowRoot(invocationTarget) && shadowMode(invocationTarget) === 'closed') rootOfClosedTree = true;
  }
  apply(arrayPush, s.path, [{ invocationTarget, invocationTargetInShadowTree, shadowAdjustedTarget, relatedTarget, touchTargets, rootOfClosedTree, slotInClosedTree }]);
}
function invoke(struct, event, phase, legacyOutput) {
  const s = slotOf(event);
  let idx = s.path.indexOf(struct);
  let i = idx;
  for (; i >= 0; i--) { if (s.path[i].shadowAdjustedTarget !== null) { s.target = s.path[i].shadowAdjustedTarget; break; } }
  s.relatedTarget = struct.relatedTarget;
  s.touchTargets = struct.touchTargets;
  if (s.stopProp) return;
  s.currentTarget = struct.invocationTarget;
  const ts = struct.invocationTarget === global ? targetSlot(global) : slotOf(struct.invocationTarget);
  const listeners = apply(arraySlice, ts.listeners, []);
  const found = innerInvoke(event, listeners, phase, struct.invocationTargetInShadowTree, legacyOutput);
  if (!found && event.isTrusted && s.type === 'animationend') { /* legacy type aliases are not modelled */ }
}
// The event a listener is being called for (`window.event`).
let currentWindowEvent;
function innerInvoke(event, listeners, phase, invocationTargetInShadowTree, legacyOutput) {
  const s = slotOf(event);
  let found = false;
  for (const listener of listeners) {
    if (listener.removed) continue;
    if (listener.type !== s.type) continue;
    found = true;
    if (phase === 'capturing' && !listener.capture) continue;
    if (phase === 'bubbling' && listener.capture) continue;
    if (listener.once) removeListener(s.currentTarget, listener);
    if (listener.passive) s.inPassive = true;
    const cb = listener.callback;
    const previousEvent = currentWindowEvent;
    if (!invocationTargetInShadowTree) currentWindowEvent = event;
    try {
      if (typeof cb === 'function') apply(cb, s.currentTarget, [event]);
      else if (isObject(cb)) {
        const handle = cb.handleEvent;
        if (typeof handle !== 'function') throw new TypeError('handleEvent is not a function');
        apply(handle, cb, [event]);
      }
    } catch (e) {
      if (legacyOutput) legacyOutput.threw = true;
      reportException(e);
    }
    currentWindowEvent = previousEvent;
    s.inPassive = false;
    if (s.stopImmediate) return found;
  }
  return found;
}
function retarget(a, b) {
  while (true) {
    if (!isNodeObject(a)) return a;
    const r = rootOf(a);
    if (!isShadowRoot(r)) return a;
    if (isNodeObject(b) && isShadowIncludingInclusiveAncestor(r, b)) return a;
    a = shadowHost(r);
  }
}

// Hooks that the node layer replaces once it exists (shadow trees, slots, activation behaviour).
let isNodeObject = o => false;
let rootOf = o => o;
let isShadowRoot = o => false;
let shadowMode = o => 'open';
let shadowHost = o => null;
let isShadowIncludingInclusiveAncestor = (a, b) => false;
let sameShadowIncludingRoot = (a, b) => false;
let isSlotable = o => false;
let assignedSlotOf = o => null;
let hasActivationBehavior = o => !!(o && o.activationBehavior);
let isWindowLike = o => o === global;

// --- abort signals

function AbortSignal() { throw new TypeError('Illegal constructor'); }
function isAbortSignal(o) { const s = slotOf(o); return !!(s && s.isAbortSignal); }
function newSignal() {
  const sig = create(AbortSignal.prototype);
  setSlot(sig, { listeners: [], isTarget: true, isAbortSignal: true, aborted: false, reason: undefined, algorithms: [], dependents: [], sources: [] });
  return sig;
}
function signalAbort(sig, reason) {
  const s = slotOf(sig);
  if (s.aborted) return;
  s.aborted = true;
  s.reason = reason === undefined ? domError('AbortError', 'signal is aborted without reason') : reason;
  const algs = s.algorithms;
  s.algorithms = [];
  for (const a of algs) a();
  const ev = new Event('abort');
  slotOf(ev).isTrusted = true;
  dispatch(ev, sig);
  for (const d of s.dependents) signalAbort(d, s.reason);
}
operations(AbortSignal.prototype, {
  throwIfAborted() { const s = slotOf(this); if (!s || !s.isAbortSignal) illegal(); if (s.aborted) throw s.reason; }
});
attributes(AbortSignal.prototype, {
  aborted: { get() { const s = slotOf(this); if (!s || !s.isAbortSignal) illegal(); return s.aborted; } },
  reason: { get() { const s = slotOf(this); if (!s || !s.isAbortSignal) illegal(); return s.reason; } },
  onabort: eventHandlerAttribute('abort')
});
iface('AbortSignal', AbortSignal, EventTarget);
operations(AbortSignal, {
  abort(reason = undefined) { const sig = newSignal(); signalAbort(sig, reason); return sig; },
  timeout(milliseconds) {
    required(arguments, 1, 'timeout');
    const ms = toUnsignedLong(milliseconds);
    const sig = newSignal();
    scheduleTimer(() => signalAbort(sig, domError('TimeoutError', 'signal timed out')), ms, false, []);
    return sig;
  },
  any(signals) {
    required(arguments, 1, 'any');
    const list = [];
    for (const x of signals) { if (!isObject(x) || !isAbortSignal(x)) throw new TypeError('AbortSignal.any: not an AbortSignal'); apply(arrayPush, list, [x]); }
    const sig = newSignal();
    for (const x of list) { const xs = slotOf(x); if (xs.aborted) { signalAbort(sig, xs.reason); return sig; } }
    for (const x of list) apply(arrayPush, slotOf(x).dependents, [sig]);
    return sig;
  }
});
function AbortController() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'AbortController': Please use the 'new' operator");
  setSlot(this, { signal: newSignal(), isController: true });
}
operations(AbortController.prototype, {
  abort(reason = undefined) { const s = slotOf(this); if (!s || !s.isController) illegal(); signalAbort(s.signal, reason); }
});
attributes(AbortController.prototype, {
  signal: { get() { const s = slotOf(this); if (!s || !s.isController) illegal(); return s.signal; } }
});
iface('AbortController', AbortController, null);

// --- event handler IDL attributes (onclick, onload, ...)

function eventHandlerAttribute(type) {
  return {
    get() {
      const target = this === undefined || this === null ? global : this;
      const s = targetSlot(target);
      const h = s.handlers && s.handlers[type];
      return h ? h.value : null;
    },
    set(v) {
      const target = this === undefined || this === null ? global : this;
      const s = targetSlot(target);
      if (!s.handlers) s.handlers = {};
      let h = s.handlers[type];
      if (!isObject(v)) v = null;
      if (typeof v !== 'function') v = null;
      if (!h) {
        h = s.handlers[type] = { value: null, listener: null };
        const listener = function (event) {
          const cur = h.value;
          if (typeof cur !== 'function') return;
          let result;
          if (type === 'error' && target === global && event instanceof ErrorEvent) {
            result = apply(cur, target, [event.message, event.filename, event.lineno, event.colno, event.error]);
            if (result === true) event.preventDefault();
            return;
          }
          result = apply(cur, event.currentTarget, [event]);
          if (type === 'beforeunload') { if (result !== undefined && result !== null) { event.preventDefault(); } return; }
          if (result === false) event.preventDefault();
        };
        h.listener = listener;
        addListener(target, { type, callback: listener, capture: false, passive: undefined, once: false, signal: undefined, removed: false });
      }
      h.value = v;
    }
  };
}
const eventHandlerNames = [
  'abort', 'auxclick', 'beforeinput', 'beforematch', 'beforetoggle', 'blur', 'cancel', 'canplay', 'canplaythrough', 'change', 'click',
  'close', 'contextlost', 'contextmenu', 'contextrestored', 'copy', 'cuechange', 'cut', 'dblclick', 'drag', 'dragend', 'dragenter',
  'dragleave', 'dragover', 'dragstart', 'drop', 'durationchange', 'emptied', 'ended', 'error', 'focus', 'formdata', 'input', 'invalid',
  'keydown', 'keypress', 'keyup', 'load', 'loadeddata', 'loadedmetadata', 'loadstart', 'mousedown', 'mouseenter', 'mouseleave',
  'mousemove', 'mouseout', 'mouseover', 'mouseup', 'paste', 'pause', 'play', 'playing', 'progress', 'ratechange', 'reset', 'resize',
  'scroll', 'scrollend', 'securitypolicyviolation', 'seeked', 'seeking', 'select', 'slotchange', 'stalled', 'submit', 'suspend',
  'timeupdate', 'toggle', 'volumechange', 'waiting', 'webkitanimationend', 'webkitanimationiteration', 'webkitanimationstart',
  'webkittransitionend', 'wheel', 'pointerdown', 'pointerup', 'pointermove', 'pointercancel', 'pointerover', 'pointerout',
  'pointerenter', 'pointerleave', 'gotpointercapture', 'lostpointercapture', 'touchstart', 'touchend', 'touchmove', 'touchcancel',
  'animationstart', 'animationend', 'animationiteration', 'animationcancel', 'transitionrun', 'transitionstart', 'transitionend',
  'transitioncancel'
];
function defineHandlerAttrs(proto, names) {
  const attrs = {};
  for (const n of names) attrs['on' + n] = eventHandlerAttribute(n);
  attributes(proto, attrs);
}

// --- reporting uncaught exceptions

function reportException(e) {
  let message = '', filename = '', lineno = 0, colno = 0;
  try {
    if (isObject(e) && typeof e.message === 'string') message = (e.name ? e.name + ': ' : '') + e.message;
    else message = 'Uncaught ' + String(e);
  } catch (_) { message = 'Uncaught exception'; }
  const ev = new ErrorEvent('error', { message, filename, lineno, colno, error: e, cancelable: true });
  slotOf(ev).isTrusted = true;
  dispatch(ev, global);
  if (!slotOf(ev).canceled) N.log('error', message);
}
defineProperty(global, '__reportError', { value: function (e, name) { reportException(e); }, writable: true, configurable: true });

// --- timers and the event loop

let timerSeq = 0;
const timerList = [];
function scheduleTimer(fn, delay, repeat, args) {
  const id = ++timerSeq;
  const t = { id, fn, due: N.now() + Math.max(0, delay), delay: Math.max(0, delay), repeat, args, seq: id };
  insertTimer(t);
  return id;
}
function insertTimer(t) {
  let i = timerList.length;
  while (i > 0 && (timerList[i - 1].due > t.due || (timerList[i - 1].due === t.due && timerList[i - 1].seq > t.seq))) i--;
  apply(arraySplice, timerList, [i, 0, t]);
}
function clearTimer(id) {
  const n = +id;
  for (let i = 0; i < timerList.length; i++) if (timerList[i].id === n) { apply(arraySplice, timerList, [i, 1]); return; }
}
let seqCounter = 1000000;
defineProperty(global, '__runTimers', {
  value: function () {
    const now = N.now();
    let guard = 0;
    while (timerList.length && timerList[0].due <= now && guard++ < 100000) {
      const t = timerList[0];
      apply(arraySplice, timerList, [0, 1]);
      if (t.repeat) { t.due = now + Math.max(1, t.delay); t.seq = ++seqCounter; insertTimer(t); }
      try { if (typeof t.fn === 'function') apply(t.fn, global, t.args); else (0, eval)(String(t.fn)); } catch (e) { reportException(e); }
      flushMicrotasks();
    }
    return timerList.length ? timerList[0].due : -1;
  },
  writable: true, configurable: true
});
defineProperty(global, '__nextTimer', { value: function () { return timerList.length ? timerList[0].due : -1; }, writable: true, configurable: true });
function flushMicrotasks() { N.runJobs(); }
function timerDelay(timeout) {
  let n = +timeout;
  if (n !== n || n < 0) n = 0;
  return Math.trunc(n);
}
const windowMethods = {
  setTimeout(handler, timeout = 0, ...args) {
    if (typeof handler !== 'function') handler = toDOMString(handler);
    return scheduleTimer(handler, timerDelay(timeout), false, args);
  },
  setInterval(handler, timeout = 0, ...args) {
    if (typeof handler !== 'function') handler = toDOMString(handler);
    return scheduleTimer(handler, timerDelay(timeout), true, args);
  },
  clearTimeout(id = undefined) { clearTimer(id); },
  clearInterval(id = undefined) { clearTimer(id); },
  queueMicrotask(callback) {
    required(arguments, 1, 'queueMicrotask');
    if (typeof callback !== 'function') throw new TypeError('The provided callback is not a function');
    Promise.resolve().then(() => { try { callback(); } catch (e) { reportException(e); } });
  },
  requestAnimationFrame(callback) {
    required(arguments, 1, 'requestAnimationFrame');
    if (typeof callback !== 'function') throw new TypeError('The provided callback is not a function');
    const now = N.now();
    const due = (Math.floor(now / 16) + 1) * 16;
    const id = ++timerSeq;
    insertTimer({ id, fn: () => callback(due), due, delay: 0, repeat: false, args: [], seq: id });
    return id;
  },
  cancelAnimationFrame(id) { clearTimer(id); }
};

// --- console

function formatArgs(args) {
  const parts = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (typeof a === 'string') parts.push(a);
    else if (typeof a === 'function') parts.push('[Function]');
    else if (isObject(a)) { try { parts.push(JSON.stringify(a)); } catch (_) { parts.push(String(a)); } }
    else parts.push(String(a));
  }
  return parts.join(' ');
}
const consoleObject = {};
for (const level of ['log', 'info', 'warn', 'error', 'debug', 'trace', 'dir', 'dirxml', 'table', 'assert', 'count', 'countReset', 'group', 'groupCollapsed', 'groupEnd', 'time', 'timeLog', 'timeEnd', 'clear']) {
  consoleObject[level] = function (...args) { N.log(level, formatArgs(args)); };
}
defineProperty(consoleObject, symToStringTag, { value: 'console', configurable: true });
defineProperty(global, 'console', { value: consoleObject, writable: true, enumerable: false, configurable: true });
