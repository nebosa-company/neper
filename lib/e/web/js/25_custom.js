// Custom elements: the registry, upgrades, lifecycle reactions and ElementInternals.

const ceDefinitions = new Map();      // name -> definition
const ceByConstructor = new Map();    // constructor -> definition
const ceWhenDefined = new Map();      // name -> { promise, resolve }
let ceDefining = false;

// --- reactions: every WebIDL operation runs on a reaction stack; reactions queued meanwhile run when it returns

const ceStack = [];
const ceBackup = [];
let ceBackupQueued = false;
function ceEnqueueElement(el) {
  const s = slotOf(el);
  if (ceStack.length === 0) {
    apply(arrayPush, ceBackup, [el]);
    if (!ceBackupQueued) { ceBackupQueued = true; Promise.resolve().then(ceProcessBackup); }
  } else {
    const top = ceStack[ceStack.length - 1];
    if (top.indexOf(el) < 0) apply(arrayPush, top, [el]);
  }
}
function ceProcessBackup() {
  ceBackupQueued = false;
  const q = ceBackup.splice(0, ceBackup.length);
  ceProcessQueue(q);
}
function ceProcessQueue(q) {
  for (const el of q) {
    const s = slotOf(el);
    const reactions = s.ceReactions;
    while (reactions && reactions.length) {
      const r = apply(arrayShift, reactions, []);
      if (r.kind === 'upgrade') { try { upgradeElement(el, r.definition); } catch (e) { reportException(e); } }
      else { try { apply(r.fn, el, r.args); } catch (e) { reportException(e); } }
    }
  }
}
const arrayShift = Array.prototype.shift;
function ceWrap(f) {
  const name = f.name;
  const w = { [name](...args) {
    ceStack.push([]);
    try { return apply(f, this, args); } finally { ceProcessQueue(ceStack.pop()); }
  } }[name];
  defineProperty(w, 'length', { value: f.length, configurable: true });
  return w;
}
function ceWrapPrototype(proto) {
  for (const key of Reflect.ownKeys(proto)) {
    const d = getOwnPropertyDescriptor(proto, key);
    if (!d || !d.configurable) continue;
    if (typeof d.value === 'function' && key !== 'constructor' && !('prototype' in d.value)) { d.value = ceWrap(d.value); defineProperty(proto, key, d); }
    else if (d.set) { const nm = d.set.name; d.set = ceWrap(d.set); defineProperty(d.set, 'name', { value: nm, configurable: true }); defineProperty(proto, key, d); }
  }
}

// --- lookup, creation and upgrade

function lookupDefinition(doc, ns, localName, is) {
  if (ns !== HTML_NS || !slotOf(doc).browsingContext) return null;
  if (is !== null && is !== undefined) {
    const d = ceDefinitions.get(is);
    if (d && d.localName === localName) return d;
  }
  const d = ceDefinitions.get(localName);
  if (d && d.localName === localName && d.name === localName) return d;
  return null;
}
customElementState = el => slotOf(el).customState;
enqueueCallbackReaction = function (el, name, args) {
  const s = slotOf(el);
  const def = s.customDefinition;
  if (!def) return;
  if (name === 'attributeChangedCallback' && def.observed.indexOf(args[0]) < 0) return;
  const fn = def.callbacks[name];
  if (!fn) return;
  if (!s.ceReactions) s.ceReactions = [];
  apply(arrayPush, s.ceReactions, [{ kind: 'callback', fn, args }]);
  ceEnqueueElement(el);
};
enqueueAdoptedCallback = function (el, oldDoc, newDoc) { enqueueCallbackReaction(el, 'adoptedCallback', [oldDoc, newDoc]); };
function enqueueUpgrade(el, def) {
  const s = slotOf(el);
  if (!s.ceReactions) s.ceReactions = [];
  apply(arrayPush, s.ceReactions, [{ kind: 'upgrade', definition: def }]);
  ceEnqueueElement(el);
}
tryUpgrade = function (el) {
  const s = slotOf(el);
  if (s.customState !== 'undefined' && s.customState !== 'uncustomized') return;
  const is = s.isValue !== null && s.isValue !== undefined ? s.isValue : getAttributeValue(el, 'is');
  const def = lookupDefinition(s.doc, s.namespaceURI, s.localName, is);
  if (def) enqueueUpgrade(el, def);
};
function upgradeElement(el, def) {
  const s = slotOf(el);
  if (s.customState !== 'undefined' && s.customState !== 'uncustomized') return;
  s.customDefinition = def;
  s.customState = 'failed';
  for (const a of attrsOf(el)) { const as = slotOf(a); enqueueCallbackReaction(el, 'attributeChangedCallback', [as.localName, null, as.value, as.namespaceURI]); }
  if (isConnected(el)) enqueueCallbackReaction(el, 'connectedCallback', []);
  apply(arrayPush, def.constructionStack, [el]);
  let result;
  try { result = construct(def.ctor, [], def.ctor); }
  catch (e) {
    s.customState = 'failed'; s.customDefinition = null; s.ceReactions = [];
    def.constructionStack.pop();
    throw e;
  }
  def.constructionStack.pop();
  if (result !== el) { s.customState = 'failed'; s.customDefinition = null; s.ceReactions = []; throw new TypeError('The custom element constructor did not produce the element being upgraded.'); }
  s.customState = 'custom';
  setNodeFlags(el, F_DEFINED, true);
}
const ceAlreadyConstructed = { alreadyConstructed: true };
constructCustomElement = function (newTarget, base) {
  const def = ceByConstructor.get(newTarget);
  if (!def) throw new TypeError('Illegal constructor');
  if (def.localName === def.name) { if (base !== HTMLElement) throw new TypeError('Illegal constructor'); }
  else if (interfaceFor(def.localName, HTML_NS).constructor !== base) throw new TypeError('Illegal constructor');
  const stack = def.constructionStack;
  let proto = newTarget.prototype;
  if (!isObject(proto)) proto = interfaceFor(def.localName, HTML_NS);
  if (stack.length === 0) {
    const el = createElementInternal(mainDocument, def.localName, HTML_NS, null, null, false);
    const s = slotOf(el);
    s.customState = 'custom'; s.customDefinition = def;
    setNodeFlags(el, F_DEFINED, true);
    setPrototypeOf(el, proto);
    return el;
  }
  const el = stack[stack.length - 1];
  if (el === ceAlreadyConstructed) throw domError('InvalidStateError', 'This instance is already constructed');
  setPrototypeOf(el, proto);
  stack[stack.length - 1] = ceAlreadyConstructed;
  return el;
};
createElementWithDefinition = function (doc, localName, ns, prefix, is, sync) {
  const def = lookupDefinition(doc, ns, localName, is);
  if (def !== null && def.name !== def.localName) {
    const el = createElementInternal(doc, localName, ns, prefix, is, false);
    slotOf(el).customState = 'undefined';
    enqueueUpgrade(el, def);
    return el;
  }
  if (def !== null) {
    if (sync) {
      let result;
      try {
        result = construct(def.ctor, [], def.ctor);
        const rs = slotOf(result);
        if (!rs || rs.nodeType !== ELEMENT_NODE || rs.namespaceURI !== HTML_NS || !(result instanceof HTMLElement)) throw new TypeError('The result must implement HTMLElement');
        if (attrsOf(result).length) throw domError('NotSupportedError', 'The result must not have attributes');
        if (nFirst(idOf(result)) >= 0) throw domError('NotSupportedError', 'The result must not have children');
        if (parentNode(result) !== null) throw domError('NotSupportedError', 'The result must not have a parent');
        if (rs.doc !== doc) throw domError('NotSupportedError', 'The result must belong to the document');
        if (rs.localName !== localName) throw domError('NotSupportedError', 'The result must have the same local name');
        rs.prefix = prefix;
        rs.isValue = null;
      } catch (e) {
        reportException(e);
        result = createElementInternal(doc, localName, HTML_NS, null, null, false);
        setPrototypeOf(result, HTMLUnknownElement.prototype);
        slotOf(result).customState = 'failed';
      }
      return result;
    }
    const el = createElementInternal(doc, localName, ns, prefix, null, false);
    slotOf(el).customState = 'undefined';
    enqueueUpgrade(el, def);
    return el;
  }
  const el = createElementInternal(doc, localName, ns, prefix, is, false);
  if (ns === HTML_NS && (isValidCustomElementName(localName) || is !== null && is !== undefined)) slotOf(el).customState = 'undefined';
  return el;
};

// --- the registry

function CustomElementRegistry() { throw new TypeError('Illegal constructor'); }
iface('CustomElementRegistry', CustomElementRegistry, null);
function isConstructorFunction(f) {
  if (typeof f !== 'function') return false;
  try { new (new Proxy(f, { construct() { return {}; } }))(); return true; } catch (e) { return false; }
}
function ceCallback(proto, name) {
  const v = proto[name];
  if (v === undefined || v === null) return null;
  if (typeof v !== 'function') throw new TypeError("The '" + name + "' value is not a function.");
  return v;
}
function ceSequence(v) {
  if (v === undefined) return [];
  if (!isObject(v) || typeof v[symIterator] !== 'function') throw new TypeError('The value is not iterable.');
  const out = [];
  for (const x of v) apply(arrayPush, out, [toDOMString(x)]);
  return out;
}
operations(CustomElementRegistry.prototype, {
  define(name, constructor, options = undefined) {
    if (!slotOf(this) || !slotOf(this).isRegistry) illegal();
    required(arguments, 2, 'define');
    const n = toDOMString(name);
    if (typeof constructor !== 'function') throw new TypeError("Failed to execute 'define' on 'CustomElementRegistry': parameter 2 is not of type 'Function'.");
    if (options !== undefined && options !== null && !isObject(options)) throw new TypeError("Failed to execute 'define' on 'CustomElementRegistry': parameter 3 is not of type 'ElementDefinitionOptions'.");
    const ext = options !== undefined && options !== null && options.extends !== undefined ? toDOMString(options.extends) : null;
    if (!isConstructorFunction(constructor)) throw new TypeError("Failed to execute 'define' on 'CustomElementRegistry': The provided callback is not a constructor.");
    if (!isValidCustomElementName(n)) throw domError('SyntaxError', "Failed to execute 'define' on 'CustomElementRegistry': \"" + n + '" is not a valid custom element name');
    if (ceDefinitions.has(n)) throw domError('NotSupportedError', "Failed to execute 'define' on 'CustomElementRegistry': the name \"" + n + '" has already been used with this registry');
    if (ceByConstructor.has(constructor)) throw domError('NotSupportedError', "Failed to execute 'define' on 'CustomElementRegistry': this constructor has already been used with this registry");
    let localName = n;
    if (ext !== null) {
      if (isValidCustomElementName(ext)) throw domError('NotSupportedError', 'The element being extended is a custom element');
      if (interfaceFor(ext, HTML_NS) === HTMLUnknownElement.prototype) throw domError('NotSupportedError', 'The element being extended is not a valid HTML element');
      localName = ext;
    }
    if (ceDefining) throw domError('NotSupportedError', 'Another definition is in progress');
    ceDefining = true;
    let def;
    try {
      const proto = constructor.prototype;
      if (!isObject(proto)) throw new TypeError("The constructor's prototype is not an object.");
      const callbacks = {
        connectedCallback: ceCallback(proto, 'connectedCallback'),
        disconnectedCallback: ceCallback(proto, 'disconnectedCallback'),
        adoptedCallback: ceCallback(proto, 'adoptedCallback'),
        attributeChangedCallback: ceCallback(proto, 'attributeChangedCallback')
      };
      const observed = callbacks.attributeChangedCallback ? ceSequence(constructor.observedAttributes) : [];
      const disabled = ceSequence(constructor.disabledFeatures);
      const formAssociated = !!constructor.formAssociated;
      if (formAssociated) {
        callbacks.formAssociatedCallback = ceCallback(proto, 'formAssociatedCallback');
        callbacks.formResetCallback = ceCallback(proto, 'formResetCallback');
        callbacks.formDisabledCallback = ceCallback(proto, 'formDisabledCallback');
        callbacks.formStateRestoreCallback = ceCallback(proto, 'formStateRestoreCallback');
      }
      def = { name: n, localName, ctor: constructor, callbacks, observed, disableInternals: disabled.indexOf('internals') >= 0, disableShadow: disabled.indexOf('shadow') >= 0, formAssociated, constructionStack: [] };
    } finally { ceDefining = false; }
    ceDefinitions.set(n, def);
    ceByConstructor.set(constructor, def);
    for (const d of shadowIncludingInclusiveDescendants(mainDocument)) {
      if (nodeType(d) !== ELEMENT_NODE) continue;
      const ds = slotOf(d);
      if (ds.namespaceURI !== HTML_NS || ds.localName !== localName) continue;
      const is = ds.isValue !== null && ds.isValue !== undefined ? ds.isValue : getAttributeValue(d, 'is');
      if (ext === null ? true : is === n) { if (ds.customState === 'undefined' || ds.customState === 'uncustomized') enqueueUpgrade(d, def); }
    }
    const wd = ceWhenDefined.get(n);
    if (wd) { wd.resolve(constructor); ceWhenDefined.delete(n); }
  },
  get(name) {
    if (!slotOf(this) || !slotOf(this).isRegistry) illegal();
    required(arguments, 1, 'get');
    const d = ceDefinitions.get(toDOMString(name));
    return d ? d.ctor : undefined;
  },
  getName(constructor) {
    if (!slotOf(this) || !slotOf(this).isRegistry) illegal();
    required(arguments, 1, 'getName');
    if (!isConstructorFunction(constructor)) throw new TypeError("Failed to execute 'getName' on 'CustomElementRegistry': parameter 1 is not a constructor.");
    const d = ceByConstructor.get(constructor);
    return d ? d.name : null;
  },
  whenDefined(name) {
    if (!slotOf(this) || !slotOf(this).isRegistry) return Promise.reject(new TypeError('Illegal invocation'));
    required(arguments, 1, 'whenDefined');
    const n = toDOMString(name);
    if (!isValidCustomElementName(n)) return Promise.reject(domError('SyntaxError', "'" + n + "' is not a valid custom element name"));
    const d = ceDefinitions.get(n);
    if (d) return Promise.resolve(d.ctor);
    let w = ceWhenDefined.get(n);
    if (!w) { w = {}; w.promise = new Promise(r => { w.resolve = r; }); ceWhenDefined.set(n, w); }
    return w.promise;
  },
  upgrade(root) {
    if (!slotOf(this) || !slotOf(this).isRegistry) illegal();
    required(arguments, 1, 'upgrade');
    if (!isNode(root)) throw new TypeError("Failed to execute 'upgrade' on 'CustomElementRegistry': parameter 1 is not of type 'Node'.");
    for (const d of shadowIncludingInclusiveDescendants(root)) if (nodeType(d) === ELEMENT_NODE) tryUpgrade(d);
  }
});
const customElementsObject = create(CustomElementRegistry.prototype);
setSlot(customElementsObject, { isRegistry: true });
defineProperty(global, 'customElements', { get() { return customElementsObject; }, enumerable: true, configurable: true });

// --- ElementInternals

function ElementInternals() { throw new TypeError('Illegal constructor'); }
iface('ElementInternals', ElementInternals, null);
function CustomStateSet() { throw new TypeError('Illegal constructor'); }
iface('CustomStateSet', CustomStateSet, Set);
function eiSlot(o) { const s = slotOf(o); if (!s || !s.isInternals) illegal(); return s; }
operations(HTMLElement.prototype, {
  attachInternals() {
    const es = elSlot(this);
    if (es.customState !== 'custom' && es.customState !== 'undefined' || !es.customDefinition && es.customState === 'custom') throw domError('NotSupportedError', 'The element is not a custom element');
    if (es.customState === 'undefined' || !es.customDefinition) throw domError('NotSupportedError', 'The element is not a custom element');
    if (es.customDefinition.disableInternals) throw domError('NotSupportedError', 'ElementInternals is disabled for this element');
    if (es.internals) throw domError('NotSupportedError', 'ElementInternals already attached');
    const o = create(ElementInternals.prototype);
    const states = new Set();
    setPrototypeOf(states, CustomStateSet.prototype);
    setSlot(o, { isInternals: true, target: this, states, value: null, validity: {}, message: '' });
    es.internals = o;
    return o;
  }
});
attributes(ElementInternals.prototype, {
  shadowRoot: { get() { const s = eiSlot(this); return slotOf(s.target).shadowRoot || null; } },
  states: { get() { return eiSlot(this).states; } },
  form: { get() { const s = eiSlot(this); if (!s.target || !slotOf(s.target).customDefinition || !slotOf(s.target).customDefinition.formAssociated) throw domError('NotSupportedError', 'The element is not form-associated'); return null; } },
  labels: { get() { eiSlot(this); return staticNodeList([]); } },
  willValidate: { get() { eiSlot(this); return false; } },
  validity: { get() { eiSlot(this); return undefined; } },
  validationMessage: { get() { return eiSlot(this).message; } }
});
operations(ElementInternals.prototype, {
  setFormValue(value, state = undefined) { const s = eiSlot(this); s.value = value; },
  setValidity(flags, message = undefined, anchor = undefined) { const s = eiSlot(this); s.validity = flags; s.message = message === undefined ? '' : String(message); },
  checkValidity() { eiSlot(this); return true; },
  reportValidity() { eiSlot(this); return true; }
});
for (const aria of ['ariaAtomic', 'ariaAutoComplete', 'ariaBusy', 'ariaChecked', 'ariaColCount', 'ariaColIndex', 'ariaColSpan', 'ariaCurrent', 'ariaDescription', 'ariaDisabled', 'ariaExpanded', 'ariaHasPopup', 'ariaHidden', 'ariaInvalid', 'ariaKeyShortcuts', 'ariaLabel', 'ariaLevel', 'ariaLive', 'ariaModal', 'ariaMultiLine', 'ariaMultiSelectable', 'ariaOrientation', 'ariaPlaceholder', 'ariaPosInSet', 'ariaPressed', 'ariaReadOnly', 'ariaRelevant', 'ariaRequired', 'ariaRoleDescription', 'ariaRowCount', 'ariaRowIndex', 'ariaRowSpan', 'ariaSelected', 'ariaSetSize', 'ariaSort', 'ariaValueMax', 'ariaValueMin', 'ariaValueNow', 'ariaValueText', 'role']) {
  defineProperty(ElementInternals.prototype, aria, {
    get() { const s = eiSlot(this); const v = s['_' + aria]; return v === undefined ? null : v; },
    set(v) { const s = eiSlot(this); s['_' + aria] = v === null ? null : String(v); },
    enumerable: true, configurable: true
  });
}
