// MutationObserver (DOM Standard 4.3): registered observers on nodes, transient registrations for removed subtrees, and records
// delivered from a microtask.

function MutationRecord() { throw new TypeError('Illegal constructor'); }
iface('MutationRecord', MutationRecord, null);
function mrSlot(o) { const s = slotOf(o); if (!s || !s.isMutationRecord) illegal(); return s; }
for (const key of ['type', 'target', 'addedNodes', 'removedNodes', 'previousSibling', 'nextSibling', 'attributeName', 'attributeNamespace', 'oldValue']) {
  attributes(MutationRecord.prototype, { [key]: { get() { return mrSlot(this)[key]; } } });
}

const observerNotifyList = [];
let mutationObserverMicrotaskQueued = false;

function MutationObserver(callback) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'MutationObserver': Please use the 'new' operator");
  required(arguments, 1, 'MutationObserver');
  if (typeof callback !== 'function') throw new TypeError("Failed to construct 'MutationObserver': The callback provided as parameter 1 is not a function.");
  setSlot(this, { isObserver: true, callback, nodes: [], records: [] });
}
iface('MutationObserver', MutationObserver, null);
function moSlot(o) { const s = slotOf(o); if (!s || !s.isObserver) illegal(); return s; }

function registrationsOf(node, create_) {
  const s = slotOf(node);
  if (s.registrations === null || s.registrations === undefined) { if (!create_) return null; s.registrations = []; }
  return s.registrations;
}

operations(MutationObserver.prototype, {
  observe(target, options = {}) {
    const s = moSlot(this);
    required(arguments, 1, 'observe');
    if (!isNode(target)) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': parameter 1 is not of type 'Node'.");
    if (options !== undefined && options !== null && !isObject(options)) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The provided value is not of type 'MutationObserverInit'.");
    const o = options === undefined || options === null ? {} : options;
    const opts = {
      childList: !!o.childList, subtree: !!o.subtree,
      attributes: o.attributes === undefined ? undefined : !!o.attributes,
      attributeOldValue: o.attributeOldValue === undefined ? undefined : !!o.attributeOldValue,
      characterData: o.characterData === undefined ? undefined : !!o.characterData,
      characterDataOldValue: o.characterDataOldValue === undefined ? undefined : !!o.characterDataOldValue,
      attributeFilter: undefined
    };
    if (o.attributeFilter !== undefined) opts.attributeFilter = Array.from(o.attributeFilter, toDOMString);
    if ((opts.attributeOldValue !== undefined || opts.attributeFilter !== undefined) && opts.attributes === undefined) opts.attributes = true;
    if (opts.characterDataOldValue !== undefined && opts.characterData === undefined) opts.characterData = true;
    if (!opts.childList && !opts.attributes && !opts.characterData) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The options object must set at least one of 'attributes', 'characterData', or 'childList' to true.");
    if (opts.attributeOldValue && !opts.attributes) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The options object may only set 'attributeOldValue' to true when 'attributes' is true or not present.");
    if (opts.attributeFilter !== undefined && !opts.attributes) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The options object may only set 'attributeFilter' when 'attributes' is true or not present.");
    if (opts.characterDataOldValue && !opts.characterData) throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The options object may only set 'characterDataOldValue' to true when 'characterData' is true or not present.");
    const regs = registrationsOf(target, true);
    let found = false;
    for (const r of regs.slice()) {
      if (r.observer === this) {
        found = true;
        for (const n of s.nodes) { const nr = registrationsOf(n, false); if (nr) for (let i = nr.length - 1; i >= 0; i--) if (nr[i].source === r) nr.splice(i, 1); }
        r.options = opts;
      }
    }
    if (!found) {
      apply(arrayPush, regs, [{ observer: this, options: opts, source: null }]);
      apply(arrayPush, s.nodes, [target]);
    }
  },
  disconnect() {
    const s = moSlot(this);
    for (const node of s.nodes) {
      const regs = registrationsOf(node, false);
      if (regs) for (let i = regs.length - 1; i >= 0; i--) if (regs[i].observer === this) regs.splice(i, 1);
    }
    s.nodes = [];
    s.records = [];
  },
  takeRecords() {
    const s = moSlot(this);
    const r = s.records;
    s.records = [];
    return r;
  }
});

function queueMicrotaskForObservers() {
  if (mutationObserverMicrotaskQueued) return;
  mutationObserverMicrotaskQueued = true;
  Promise.resolve().then(notifyMutationObservers);
}
function notifyMutationObservers() {
  mutationObserverMicrotaskQueued = false;
  const signals = signalSlots.length > 0;
  const notify = observerNotifyList.splice(0, observerNotifyList.length);
  for (const mo of notify) {
    const s = slotOf(mo);
    const records = s.records;
    s.records = [];
    for (const node of s.nodes) {
      const regs = registrationsOf(node, false);
      if (regs) for (let i = regs.length - 1; i >= 0; i--) if (regs[i].observer === mo && regs[i].source !== null) regs.splice(i, 1);
    }
    if (records.length > 0) {
      try { apply(s.callback, mo, [records, mo]); } catch (e) { reportException(e); }
    }
  }
  if (signals) fireSlotChanges();
}

queueMutationRecord = function (type, target, name, namespace, oldValue, added, removed, previousSibling_, nextSibling_) {
  const interested = [];
  let n = target;
  const chain = [];
  while (n !== null) { apply(arrayPush, chain, [n]); n = parentNode(n); }
  for (const node of chain) {
    const regs = registrationsOf(node, false);
    if (!regs) continue;
    for (const r of regs) {
      const o = r.options;
      if (node !== target && !o.subtree) continue;
      if (type === 'attributes' && !o.attributes) continue;
      if (type === 'attributes' && o.attributeFilter !== undefined && (namespace !== null || o.attributeFilter.indexOf(name) < 0)) continue;
      if (type === 'characterData' && !o.characterData) continue;
      if (type === 'childList' && !o.childList) continue;
      let entry = null;
      for (const e of interested) if (e.observer === r.observer) { entry = e; break; }
      if (entry === null) { entry = { observer: r.observer, oldValue: null }; apply(arrayPush, interested, [entry]); }
      if ((type === 'attributes' && o.attributeOldValue) || (type === 'characterData' && o.characterDataOldValue)) entry.oldValue = oldValue;
    }
  }
  for (const e of interested) {
    const record = create(MutationRecord.prototype);
    setSlot(record, {
      isMutationRecord: true, type, target,
      addedNodes: staticNodeList(added), removedNodes: staticNodeList(removed),
      previousSibling: previousSibling_ === undefined ? null : previousSibling_, nextSibling: nextSibling_ === undefined ? null : nextSibling_,
      attributeName: type === 'attributes' ? name : null, attributeNamespace: type === 'attributes' ? namespace : null,
      oldValue: e.oldValue
    });
    const mo = slotOf(e.observer);
    apply(arrayPush, mo.records, [record]);
    if (observerNotifyList.indexOf(e.observer) < 0) apply(arrayPush, observerNotifyList, [e.observer]);
    queueMicrotaskForObservers();
  }
};
addTransientRegistrations = function (node, parent) {
  let n = parent;
  while (n !== null) {
    const regs = registrationsOf(n, false);
    if (regs) {
      for (const r of regs.slice()) {
        if (r.options.subtree) {
          const t = registrationsOf(node, true);
          apply(arrayPush, t, [{ observer: r.observer, options: r.options, source: r }]);
          apply(arrayPush, slotOf(r.observer).nodes, [node]);
        }
      }
    }
    n = parentNode(n);
  }
};
