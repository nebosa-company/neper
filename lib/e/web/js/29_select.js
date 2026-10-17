// select, option, textarea, FileList and the Option / Image constructors.

// --- FileList

function FileList() { throw new TypeError('Illegal constructor'); }
iface('FileList', FileList, null);
function makeFileListFrom(getFiles) {
  const state = { isFileList: true };
  Object.defineProperty(state, 'files', { get: getFiles });
  return legacyObject(FileList.prototype, { length: () => getFiles().length, item: i => { const f = getFiles(); return i < f.length ? f[i] : null; } }, state);
}
operations(FileList.prototype, {
  item(index) { const s = slotOf(this); if (!s || !s.isFileList) illegal(); required(arguments, 1, 'item'); const f = s.files, i = toUnsignedLong(index); return i < f.length ? f[i] : null; }
});
attributes(FileList.prototype, { length: { get() { const s = slotOf(this); if (!s || !s.isFileList) illegal(); return s.files.length; } } });
defineProperty(FileList.prototype, symIterator, { value: Array.prototype.values, writable: true, enumerable: false, configurable: true });

// --- option

function optionState(o) {
  const s = slotOf(o);
  if (!s.optionState) s.optionState = { selected: getAttributeValue(o, 'selected') !== null, dirty: false };
  return s.optionState;
}
function optionSelectedness(o) { return optionState(o).selected; }
function optionValue(o) { const v = getAttributeValue(o, 'value'); return v !== null ? v : stripAndCollapse(optionDescendantText(o)); }
function optionDescendantText(o) {
  let out = '';
  (function walk(n) {
    for (const c of childrenOf(n)) {
      const t = nodeType(c);
      if (t === TEXT_NODE) out += N.value(idOf(c));
      else if (t === ELEMENT_NODE && !(htmlLocal(c) === 'script' || (slotOf(c).namespaceURI === SVG_NS && slotOf(c).localName === 'script'))) walk(c);
    }
  })(o);
  return out;
}
function selectOf(o) {
  const p = parentNode(o);
  if (p === null) return null;
  if (htmlLocal(p) === 'select') return p;
  if (htmlLocal(p) === 'optgroup') { const g = parentNode(p); return g !== null && htmlLocal(g) === 'select' ? g : null; }
  return null;
}
function selectOptions(sel) {
  const out = [];
  for (const c of childrenOf(sel)) {
    const n = htmlLocal(c);
    if (n === 'option') apply(arrayPush, out, [c]);
    else if (n === 'optgroup') for (const g of childrenOf(c)) if (htmlLocal(g) === 'option') apply(arrayPush, out, [g]);
  }
  return out;
}
function selectIsMultiple(sel) { return getAttributeValue(sel, 'multiple') !== null; }
function displaySize(sel) {
  const raw = getAttributeValue(sel, 'size');
  if (raw !== null) { const m = /^[ \t\n\f\r]*([+-]?\d+)/.exec(raw); if (m) { const n = parseInt(m[1], 10); if (n > 0) return n; } }
  return selectIsMultiple(sel) ? 4 : 1;
}
function askForReset(sel) {
  if (selectIsMultiple(sel) || displaySize(sel) !== 1) return;
  const options = selectOptions(sel);
  const selected = options.filter(optionSelectedness);
  if (selected.length === 0) {
    for (const o of options) if (!isActuallyDisabled(o)) { optionState(o).selected = true; break; }
  } else if (selected.length > 1) {
    for (let i = 0; i < selected.length - 1; i++) optionState(selected[i]).selected = false;
  }
}
function setOptionSelectedness(o, v, dirty) {
  const st = optionState(o);
  st.selected = v;
  if (dirty) st.dirty = true;
  const sel = selectOf(o);
  if (sel !== null) {
    if (v && !selectIsMultiple(sel)) for (const other of selectOptions(sel)) if (other !== o) optionState(other).selected = false;
    askForReset(sel);
  }
}
attributes(P('HTMLOptionElement'), {
  selected: { get() { elSlot(this); const sel = selectOf(this); return optionSelectedness(this); }, set(v) { elSlot(this); setOptionSelectedness(this, !!v, true); } },
  value: { get() { elSlot(this); return optionValue(this); }, set(v) { elSlot(this); setAttributeValue(this, 'value', toDOMString(v)); } },
  label: { get() { elSlot(this); const v = getAttributeValue(this, 'label'); return v !== null && v !== '' ? v : stripAndCollapse(optionDescendantText(this)); }, set(v) { elSlot(this); setAttributeValue(this, 'label', toDOMString(v)); } },
  index: { get() { elSlot(this); const sel = selectOf(this); return sel === null ? 0 : selectOptions(sel).indexOf(this); } },
  form: { get() { elSlot(this); const sel = selectOf(this); return sel === null ? null : formOwnerOf(sel); } }
});
attributes(P('HTMLOptionElement'), { text: { get() { return stripAndCollapse(optionDescendantText(this)); }, set(v) { replaceAllWith(this, v === '' ? null : createTextNode(slotOf(this).doc, toDOMString(v))); } } });
resetAlgorithms.option = function (o) {};
resetAlgorithms.select = function (sel) {
  for (const o of selectOptions(sel)) { const st = optionState(o); st.selected = getAttributeValue(o, 'selected') !== null; st.dirty = false; }
  askForReset(sel);
};
function OptionConstructor(text = '', value = undefined, defaultSelected = false, selected = false) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Option': Please use the 'new' operator");
  const el = createElementInternal(mainDocument, 'option', HTML_NS, null, null, false);
  if (new.target !== OptionConstructor) setPrototypeOf(el, new.target.prototype);
  const t = toDOMString(text);
  if (t !== '') appendNodeSimple(el, createTextNode(mainDocument, t));
  if (value !== undefined) setAttributeValue(el, 'value', toDOMString(value));
  if (defaultSelected) setAttributeValue(el, 'selected', '');
  optionState(el).selected = !!selected || !!defaultSelected;
  if (selected !== undefined && !selected && !defaultSelected) optionState(el).selected = false;
  return el;
}
defineProperty(OptionConstructor, 'name', { value: 'Option', configurable: true });
defineProperty(OptionConstructor, 'length', { value: 0, configurable: true });
defineProperty(OptionConstructor, 'prototype', { value: P('HTMLOptionElement'), writable: false, enumerable: false, configurable: false });
defineProperty(global, 'Option', { value: OptionConstructor, writable: true, enumerable: false, configurable: true });
function ImageConstructor(width = undefined, height = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Image': Please use the 'new' operator");
  const el = createElementInternal(mainDocument, 'img', HTML_NS, null, null, false);
  if (new.target !== ImageConstructor) setPrototypeOf(el, new.target.prototype);
  if (width !== undefined) setAttributeValue(el, 'width', String(width >>> 0));
  if (height !== undefined) setAttributeValue(el, 'height', String(height >>> 0));
  return el;
}
defineProperty(ImageConstructor, 'name', { value: 'Image', configurable: true });
defineProperty(ImageConstructor, 'length', { value: 0, configurable: true });
defineProperty(ImageConstructor, 'prototype', { value: P('HTMLImageElement'), writable: false, enumerable: false, configurable: false });
defineProperty(global, 'Image', { value: ImageConstructor, writable: true, enumerable: false, configurable: true });

// keep the selectedness invariants as options come and go
const prevChildrenChangedSelect = childrenChanged;
childrenChanged = function (parent) {
  prevChildrenChangedSelect(parent);
  const n = htmlLocal(parent);
  let sel = null;
  if (n === 'select') sel = parent;
  else if (n === 'optgroup') { const g = parentNode(parent); if (g !== null && htmlLocal(g) === 'select') sel = g; }
  if (sel !== null) {
    const options = selectOptions(sel);
    if (!selectIsMultiple(sel)) {
      const sel2 = options.filter(optionSelectedness);
      // an option that arrives selected wins over the others
      for (const o of options) {
        const st = optionState(o);
        if (st.fresh === undefined) { st.fresh = false; if (st.selected && sel2.length > 1) { for (const other of options) if (other !== o) optionState(other).selected = false; } }
      }
    }
    askForReset(sel);
  }
};
const prevAttrSelect = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrSelect(el, name, oldValue, value);
  const n = htmlLocal(el);
  if (n === 'option') {
    if (name === 'selected') {
      const st = optionState(el);
      if (!st.dirty) { setOptionSelectedness(el, value !== null, false); }
    } else if (name === 'disabled') { const sel = selectOf(el); if (sel !== null) askForReset(sel); }
  } else if (n === 'select' && (name === 'multiple' || name === 'size')) askForReset(el);
};

// --- select

function selectElSlot(o) { const s = slotOf(o); if (!s || s.localName !== 'select' || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
function HTMLOptionsCollection() { throw new TypeError('Illegal constructor'); }
iface('HTMLOptionsCollection', HTMLOptionsCollection, HTMLCollection);
function makeOptionsCollection(sel) {
  const state = { isCollection: true, isOptions: true, select: sel, collect: () => selectOptions(sel), cache: null, cacheVersion: -1 };
  return legacyObject(HTMLOptionsCollection.prototype, {
    length: () => collectionItems(state).length,
    item: i => { const c = collectionItems(state); return i < c.length ? c[i] : null; },
    named: name => namedLookup(state, name),
    names: () => namedKeys(state),
    indexedSetter: (i, v) => setOptionAt(sel, i, v)
  }, state);
}
function setOptionAt(sel, index, value) {
  const options = selectOptions(sel);
  if (value === null) { if (index < options.length) removeNode(options[index], false); return; }
  if (!isNode(value) || htmlLocal(value) !== 'option') throw new TypeError('The provided value is not an HTMLOptionElement.');
  if (index > 4294967294) return;
  if (index >= options.length) {
    const n = index - options.length;
    for (let i = 0; i < n; i++) appendNodeSimple(sel, createElementInternal(slotOf(sel).doc, 'option', HTML_NS, null, null, false));
    preInsert(value, sel, null);
  } else {
    const before = options[index];
    const parent = parentNode(before);
    replaceChild(value, before, parent);
  }
}
function setOptionsLength(sel, n) {
  const options = selectOptions(sel);
  if (n > 100000) return;
  if (n > options.length) for (let i = options.length; i < n; i++) appendNodeSimple(sel, createElementInternal(slotOf(sel).doc, 'option', HTML_NS, null, null, false));
  else for (let i = options.length - 1; i >= n; i--) removeNode(options[i], false);
}
function addOption(sel, element, before) {
  if (!isNode(element) || (htmlLocal(element) !== 'option' && htmlLocal(element) !== 'optgroup')) throw new TypeError("Failed to execute 'add': parameter 1 is not of type 'HTMLOptionElement or HTMLOptGroupElement'.");
  if (isInclusiveAncestor(element, sel)) throw domError('HierarchyRequestError', 'The new child element contains the parent.');
  let ref = null;
  if (typeof before === 'number' || (before !== undefined && before !== null && !isNode(before))) {
    const options = selectOptions(sel), i = toLong(before);
    ref = i >= 0 && i < options.length ? options[i] : null;
  } else if (before !== undefined && before !== null) {
    ref = before;
    if (!isInclusiveAncestor(sel, ref) || ref === sel) throw domError('NotFoundError', 'The node before which the new node is to be inserted is not a descendant of this element.');
  }
  const parent = ref !== null ? parentNode(ref) : sel;
  preInsert(element, parent, ref);
}
operations(HTMLOptionsCollection.prototype, {
  add(element, before = null) { const s = slotOf(this); if (!s || !s.isOptions) illegal(); required(arguments, 1, 'add'); addOption(s.select, element, before); },
  remove(index) { const s = slotOf(this); if (!s || !s.isOptions) illegal(); required(arguments, 1, 'remove'); const o = selectOptions(s.select), i = toLong(index); if (i >= 0 && i < o.length) removeNode(o[i], false); }
});
attributes(HTMLOptionsCollection.prototype, {
  length: { get() { const s = slotOf(this); if (!s || !s.isOptions) illegal(); return collectionItems(s).length; }, set(v) { const s = slotOf(this); if (!s || !s.isOptions) illegal(); setOptionsLength(s.select, toUnsignedLong(v)); } },
  selectedIndex: { get() { const s = slotOf(this); if (!s || !s.isOptions) illegal(); return selectedIndexOf(s.select); }, set(v) { const s = slotOf(this); if (!s || !s.isOptions) illegal(); setSelectedIndex(s.select, toLong(v)); } }
});
function selectedIndexOf(sel) { const o = selectOptions(sel); for (let i = 0; i < o.length; i++) if (optionSelectedness(o[i])) return i; return -1; }
function setSelectedIndex(sel, idx) {
  const o = selectOptions(sel);
  for (const x of o) { const st = optionState(x); st.selected = false; st.dirty = true; }
  if (idx >= 0 && idx < o.length) optionState(o[idx]).selected = true;
}
attributes(P('HTMLSelectElement'), {
  type: { get() { selectElSlot(this); return selectIsMultiple(this) ? 'select-multiple' : 'select-one'; } },
  options: { get() { const s = selectElSlot(this); if (!s.optionsObject) s.optionsObject = makeOptionsCollection(this); return s.optionsObject; } },
  selectedOptions: { get() { const s = selectElSlot(this); if (!s.selectedList) s.selectedList = makeCollection(() => selectOptions(this).filter(optionSelectedness)); return s.selectedList; } },
  length: { get() { selectElSlot(this); return selectOptions(this).length; }, set(v) { selectElSlot(this); setOptionsLength(this, toUnsignedLong(v)); } },
  selectedIndex: { get() { selectElSlot(this); return selectedIndexOf(this); }, set(v) { selectElSlot(this); setSelectedIndex(this, toLong(v)); } },
  value: {
    get() { selectElSlot(this); for (const o of selectOptions(this)) if (optionSelectedness(o)) return optionValue(o); return ''; },
    set(v) {
      selectElSlot(this);
      const str = toDOMString(v);
      let found = false;
      for (const o of selectOptions(this)) { const st = optionState(o); st.dirty = true; if (!found && optionValue(o) === str) { st.selected = true; found = true; } else st.selected = false; }
    }
  }
});
operations(P('HTMLSelectElement'), {
  item(index) { selectElSlot(this); required(arguments, 1, 'item'); const o = selectOptions(this), i = toUnsignedLong(index); return i < o.length ? o[i] : null; },
  namedItem(name) { selectElSlot(this); required(arguments, 1, 'namedItem'); const n = toDOMString(name); if (n === '') return null; for (const o of selectOptions(this)) if (getAttributeValue(o, 'id') === n || getAttributeValue(o, 'name') === n) return o; return null; },
  add(element, before = null) { selectElSlot(this); required(arguments, 1, 'add'); addOption(this, element, before); },
  remove(index = undefined) {
    selectElSlot(this);
    if (arguments.length === 0) { const p = parentNode(this); if (p !== null) removeNode(this, false); return; }
    const o = selectOptions(this), i = toLong(index);
    if (i >= 0 && i < o.length) removeNode(o[i], false);
  },
  showPicker() { selectElSlot(this); throw domError('NotAllowedError', 'showPicker() requires a user gesture.'); }
});
controlValidators.select = function (el, out) {
  if (getAttributeValue(el, 'required') === null) return;
  if (isDisabledControl(el)) return;
  const options = selectOptions(el);
  const selected = options.filter(optionSelectedness);
  if (selected.length === 0) { out.valueMissing = true; return; }
  if (!selectIsMultiple(el) && displaySize(el) === 1) {
    const first = options[0];
    if (first && selected[0] === first && optionValue(first) === '' && parentNode(first) === el) out.valueMissing = true;
  }
};
const selectLegacyIndexed = null;
// select[i] and select.length through the legacy platform object: the interface prototype answers through the options list.
defineProperty(P('HTMLSelectElement'), symIterator, { value: function () { selectElSlot(this); return selectOptions(this)[symIterator](); }, writable: true, enumerable: false, configurable: true });

// --- textarea

function textareaState(el) {
  const s = slotOf(el);
  if (!s.textarea) s.textarea = { value: '', dirty: false, selStart: 0, selEnd: 0, selDir: 'none' };
  return s.textarea;
}
function textareaChildText(el) { let out = ''; for (const c of childrenOf(el)) if (nodeType(c) === TEXT_NODE) out += N.value(idOf(c)); return out; }
function textareaRaw(el) { const st = textareaState(el); return st.dirty ? st.value : textareaChildText(el); }
function textareaAPIValue(el) { return textareaRaw(el).replace(/\r\n|\r/g, '\n'); }
function taSlot(o) { const s = slotOf(o); if (!s || s.localName !== 'textarea' || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
attributes(P('HTMLTextAreaElement'), {
  type: { get() { taSlot(this); return 'textarea'; } },
  defaultValue: { get() { taSlot(this); return textareaChildText(this); }, set(v) { const s = taSlot(this); const str = toDOMString(v); replaceAllWith(this, str === '' ? null : createTextNode(s.doc, str)); } },
  value: {
    get() { taSlot(this); return textareaAPIValue(this); },
    set(v) {
      taSlot(this);
      const old = textareaAPIValue(this), st = textareaState(this);
      st.value = v === null ? '' : toDOMString(v);
      st.dirty = true;
      if (textareaAPIValue(this) !== old) { const l = textareaAPIValue(this).length; st.selStart = st.selEnd = l; st.selDir = 'none'; }
    }
  },
  textLength: { get() { taSlot(this); return textareaAPIValue(this).length; } }
});
attributes(P('HTMLTextAreaElement'), selectionAttrs());
operations(P('HTMLTextAreaElement'), selectionOps);
resetAlgorithms.textarea = function (el) { const st = textareaState(el); st.dirty = false; st.value = ''; const l = textareaAPIValue(el).length; st.selStart = st.selEnd = l; st.selDir = 'none'; };
controlValidators.textarea = function (el, out) {
  if (getAttributeValue(el, 'required') !== null && textareaAPIValue(el) === '') out.valueMissing = true;
};
