// Forms (HTML Standard 4.10): form association, the form element, constraint validation, labels and the small form controls.

const resetAlgorithms = {};
const listedNames = ['button', 'fieldset', 'input', 'object', 'output', 'select', 'textarea'];
function htmlLocal(el) { const s = slotOf(el); return s && s.nodeType === ELEMENT_NODE && s.namespaceURI === HTML_NS ? s.localName : null; }
function isFormElement(el) { return htmlLocal(el) === 'form'; }
function formAssociatedCustom(el) { const s = slotOf(el); return !!(s && s.customDefinition && s.customDefinition.formAssociated); }
function isListed(el) { const n = htmlLocal(el); return n !== null && (listedNames.indexOf(n) >= 0 || formAssociatedCustom(el)); }
function isLabelable(el) {
  const n = htmlLocal(el);
  if (n === null) return false;
  if (n === 'input') return inputTypeOf(el) !== 'hidden';
  return ['button', 'meter', 'output', 'progress', 'select', 'textarea'].indexOf(n) >= 0 || formAssociatedCustom(el);
}
function isSubmittable(el) { const n = htmlLocal(el); return n !== null && (['button', 'input', 'select', 'textarea'].indexOf(n) >= 0 || formAssociatedCustom(el)); }
function isResettable(el) { const n = htmlLocal(el); return n !== null && (['input', 'output', 'select', 'textarea'].indexOf(n) >= 0 || formAssociatedCustom(el)); }

function findByIdInTree(root, id) {
  for (const d of descendantsOf(root)) if (nodeType(d) === ELEMENT_NODE && getAttributeValue(d, 'id') === id) return d;
  return null;
}
function formOwnerOf(el) {
  const attr = getAttributeValue(el, 'form');
  if (attr !== null) {
    if (!isConnected(el) && false) return null;
    const found = findByIdInTree(rootNode(el), attr);
    return found !== null && isFormElement(found) ? found : null;
  }
  for (let p = parentNode(el); p !== null; p = parentNode(p)) if (isFormElement(p)) return p;
  return null;
}
function formElementsOf(form) {
  const out = [];
  const root = rootNode(form);
  for (const d of descendantsOf(root)) {
    if (nodeType(d) !== ELEMENT_NODE || !isListed(d)) continue;
    if (htmlLocal(d) === 'input' && inputTypeOf(d) === 'image') continue;
    if (formOwnerOf(d) === form) apply(arrayPush, out, [d]);
  }
  return out;
}
function submittableElementsOf(form) {
  const out = [];
  for (const d of descendantsOf(rootNode(form))) if (nodeType(d) === ELEMENT_NODE && isSubmittable(d) && formOwnerOf(d) === form) apply(arrayPush, out, [d]);
  return out;
}

// --- disabled

function isDisabledControl(el) {
  const n = htmlLocal(el);
  if (n === 'button' || n === 'input' || n === 'select' || n === 'textarea' || n === 'fieldset') {
    if (getAttributeValue(el, 'disabled') !== null) return true;
  } else if (formAssociatedCustom(el)) {
    if (getAttributeValue(el, 'disabled') !== null) return true;
  } else return false;
  return inDisabledFieldset(el);
}
function inDisabledFieldset(el) {
  let child = el;
  for (let p = parentNode(el); p !== null; child = p, p = parentNode(p)) {
    if (htmlLocal(p) === 'fieldset' && getAttributeValue(p, 'disabled') !== null) {
      let firstLegend = null;
      for (const k of childrenOf(p)) if (htmlLocal(k) === 'legend') { firstLegend = k; break; }
      if (firstLegend === null || !isInclusiveAncestor(firstLegend, el)) return true;
    }
  }
  return false;
}
function isActuallyDisabled(el) {
  const n = htmlLocal(el);
  if (n === 'option') {
    if (getAttributeValue(el, 'disabled') !== null) return true;
    const p = parentNode(el);
    return p !== null && htmlLocal(p) === 'optgroup' && getAttributeValue(p, 'disabled') !== null;
  }
  if (n === 'optgroup') return getAttributeValue(el, 'disabled') !== null;
  return isDisabledControl(el);
}

// --- ValidityState and the constraint validation API

function ValidityState() { throw new TypeError('Illegal constructor'); }
iface('ValidityState', ValidityState, null);
function vsSlot(o) { const s = slotOf(o); if (!s || !s.isValidity) illegal(); return s; }
const validityFlags = ['valueMissing', 'typeMismatch', 'patternMismatch', 'tooLong', 'tooShort', 'rangeUnderflow', 'rangeOverflow', 'stepMismatch', 'badInput', 'customError'];
for (const f of validityFlags) defineProperty(ValidityState.prototype, f, { get() { const s = vsSlot(this); return !!computeValidity(s.element)[f]; }, enumerable: true, configurable: true });
defineProperty(ValidityState.prototype, 'valid', { get() { const s = vsSlot(this); const v = computeValidity(s.element); for (const f of validityFlags) if (v[f]) return false; return true; }, enumerable: true, configurable: true });
function validityOf(el) {
  const s = slotOf(el);
  if (!s.validityObject) { const o = create(ValidityState.prototype); setSlot(o, { isValidity: true, element: el }); s.validityObject = o; }
  return s.validityObject;
}
// A control's validity flags; the element kinds provide their own `validate` through `controlValidators`.
const controlValidators = {};
function computeValidity(el) {
  const out = {};
  for (const f of validityFlags) out[f] = false;
  const v = controlValidators[htmlLocal(el)];
  if (v) v(el, out);
  const s = slotOf(el);
  if (s.customValidity) out.customError = true;
  return out;
}
function noCustomOnBarred(el, out) {
  // customError applies even to barred elements (validity.customError mirrors the message), but they never "invalidate".
  return out;
}
const neverValidated = ['fieldset', 'object', 'output'];
function isCandidateForValidation(el) {
  const n = htmlLocal(el);
  if (n === null) return false;
  if (neverValidated.indexOf(n) >= 0) return false;
  if (!isSubmittable(el) && !formAssociatedCustom(el)) return false;
  if (isDisabledControl(el)) return false;
  for (let p = parentNode(el); p !== null; p = parentNode(p)) if (htmlLocal(p) === 'datalist') return false;
  if (n === 'button') return buttonTypeOf(el) === 'submit';
  if (n === 'input') {
    const t = inputTypeOf(el);
    if (t === 'hidden' || t === 'reset' || t === 'button') return false;
    if (readOnlyApplies(t) && getAttributeValue(el, 'readonly') !== null) return false;
    return true;
  }
  if (n === 'textarea') return getAttributeValue(el, 'readonly') === null;
  return true;
}
function readOnlyApplies(t) { return ['text', 'search', 'url', 'tel', 'email', 'password', 'date', 'month', 'week', 'time', 'datetime-local', 'number'].indexOf(t) >= 0; }
function isValidControl(el) { const v = computeValidity(el); for (const f of validityFlags) if (v[f]) return false; return true; }
function validationMessageOf(el) {
  if (!isCandidateForValidation(el) && !(slotOf(el).customValidity && false)) return '';
  const s = slotOf(el);
  if (s.customValidity) return s.customValidity;
  if (!isValidControl(el)) return 'Please fill out this field.';
  return '';
}
function fireInvalid(el) {
  const ev = new Event('invalid', { bubbles: false, cancelable: true });
  slotOf(ev).isTrusted = true;
  return dispatch(ev, el);
}
function checkValidityOf(el) {
  if (!isCandidateForValidation(el)) return true;
  if (isValidControl(el)) return true;
  fireInvalid(el);
  return false;
}
function reportValidityOf(el) {
  if (!isCandidateForValidation(el)) return true;
  if (isValidControl(el)) return true;
  fireInvalid(el);
  return false;
}
const constraintAttributes = {
  willValidate: { get() { elSlot(this); return isCandidateForValidation(this); } },
  validity: { get() { elSlot(this); return validityOf(this); } },
  validationMessage: { get() { elSlot(this); return validationMessageOf(this); } }
};
const constraintOperations = {
  checkValidity() { elSlot(this); return checkValidityOf(this); },
  reportValidity() { elSlot(this); return reportValidityOf(this); },
  setCustomValidity(error) { elSlot(this); required(arguments, 1, 'setCustomValidity'); slotOf(this).customValidity = toDOMString(error); }
};
for (const name of ['HTMLButtonElement', 'HTMLFieldSetElement', 'HTMLInputElement', 'HTMLObjectElement', 'HTMLOutputElement', 'HTMLSelectElement', 'HTMLTextAreaElement']) {
  attributes(P(name), constraintAttributes);
  operations(P(name), constraintOperations);
}

// --- form owner and labels

function formAttr(name) { return { get() { elSlot(this); return formOwnerOf(this); } }; }
for (const name of ['HTMLButtonElement', 'HTMLFieldSetElement', 'HTMLInputElement', 'HTMLObjectElement', 'HTMLOutputElement', 'HTMLSelectElement', 'HTMLTextAreaElement']) {
  attributes(P(name), { form: formAttr() });
}
function labelControl(label) {
  const id = getAttributeValue(label, 'for');
  if (id !== null) {
    const el = findByIdInTree(rootNode(label), id);
    return el !== null && isLabelable(el) ? el : null;
  }
  for (const d of descendantsOf(label)) if (nodeType(d) === ELEMENT_NODE && isLabelable(d)) return d;
  return null;
}
function labelsOf(el) {
  const s = slotOf(el);
  if (!s.labelsList) {
    let cache = null, version = -1;
    const refresh = () => {
      const v = N.version();
      if (cache === null || version !== v) {
        cache = [];
        for (const d of descendantsOf(rootNode(el))) if (htmlLocal(d) === 'label' && labelControl(d) === el) apply(arrayPush, cache, [d]);
        version = v;
      }
      return cache;
    };
    s.labelsList = makeNodeList(() => refresh().length, i => { const c = refresh(); return i < c.length ? c[i] : null; });
  }
  return s.labelsList;
}
for (const name of ['HTMLButtonElement', 'HTMLInputElement', 'HTMLMeterElement', 'HTMLOutputElement', 'HTMLProgressElement', 'HTMLSelectElement', 'HTMLTextAreaElement']) {
  attributes(P(name), { labels: { get() { elSlot(this); if (name === 'HTMLInputElement' && inputTypeOf(this) === 'hidden') return null; return labelsOf(this); } } });
}
attributes(P('HTMLLabelElement'), {
  control: { get() { elSlot(this); return labelControl(this); } },
  form: { get() { elSlot(this); const c = labelControl(this); return c === null ? null : formOwnerOf(c); } }
});
// Clicking a label activates its control.
function labelActivation(event) {
  const target = slotOf(event).target;
  const c = labelControl(this);
  if (c === null) return;
  for (let p = isNode(target) ? target : null; p !== null && p !== this; p = parentNode(p)) {
    if (isInteractiveContent(p)) return;
  }
  if (!isDisabledControl(c)) simulateClick(c);
}
function isInteractiveContent(el) {
  const n = htmlLocal(el);
  if (n === null) return false;
  if (['a', 'button', 'details', 'embed', 'iframe', 'label', 'select', 'textarea'].indexOf(n) >= 0) return n !== 'a' || getAttributeValue(el, 'href') !== null;
  if (n === 'input') return inputTypeOf(el) !== 'hidden';
  return false;
}
defineProperty(P('HTMLLabelElement'), 'activationBehavior', { value: labelActivation, writable: true, enumerable: false, configurable: true });
function simulateClick(el) {
  const ev = new MouseEvent('click', { bubbles: true, cancelable: true, composed: true, view: global });
  slotOf(ev).isTrusted = false;
  slotOf(ev).isMouseClick = true;
  return dispatch(ev, el);
}

// --- fieldset, legend, output, progress, meter, datalist, optgroup

attributes(P('HTMLFieldSetElement'), {
  type: { get() { elSlot(this); return 'fieldset'; } },
  elements: { get() { const s = elSlot(this); if (!s.elementsList) s.elementsList = makeCollection(() => descendantsOf(this).filter(d => nodeType(d) === ELEMENT_NODE && isListed(d) && !(htmlLocal(d) === 'input' && inputTypeOf(d) === 'image'))); return s.elementsList; } }
});
attributes(P('HTMLLegendElement'), {
  form: { get() { elSlot(this); const p = parentNode(this); return p !== null && htmlLocal(p) === 'fieldset' ? formOwnerOf(p) : null; } }
});
reflectString(P('HTMLLegendElement'), 'align');
function outputSlot(el) { const s = elSlot(el); if (s.outputDefault === undefined) { s.outputDefault = null; s.outputValue = null; } return s; }
attributes(P('HTMLOutputElement'), {
  type: { get() { elSlot(this); return 'output'; } },
  defaultValue: {
    get() { const s = outputSlot(this); return s.outputDefault !== null ? s.outputDefault : textContentOf(this); },
    set(v) { const s = outputSlot(this); const str = toDOMString(v); if (s.outputValue === null) { replaceAllWith(this, str === '' ? null : createTextNode(s.doc, str)); } else s.outputDefault = str; if (s.outputValue !== null) s.outputDefault = str; }
  },
  value: {
    get() { const s = outputSlot(this); return textContentOf(this); },
    set(v) { const s = outputSlot(this); const str = toDOMString(v); if (s.outputDefault === null) s.outputDefault = textContentOf(this); s.outputValue = str; replaceAllWith(this, str === '' ? null : createTextNode(s.doc, str)); }
  },
  htmlFor: { get() { const s = outputSlot(this); if (!s.htmlForList) s.htmlForList = makeTokenList(this, 'for'); return s.htmlForList; }, set(v) { this.htmlFor.value = v; } }
});
resetAlgorithms.output = function (el) { const s = outputSlot(el); const dv = s.outputDefault !== null ? s.outputDefault : textContentOf(el); s.outputValue = null; replaceAllWith(el, dv === '' ? null : createTextNode(s.doc, dv)); s.outputDefault = null; };

attributes(P('HTMLDataListElement'), {
  options: { get() { const s = elSlot(this); if (!s.optionsList) s.optionsList = makeCollection(() => descendantsOf(this).filter(d => htmlLocal(d) === 'option')); return s.optionsList; } }
});
reflectBool(P('HTMLOptGroupElement'), 'disabled'); reflectString(P('HTMLOptGroupElement'), 'label');

// progress and meter
function parseValidFloat(s) { return /^-?(?:\d+|\d*\.\d+)(?:[eE][-+]?\d+)?$/.test(s) ? Number(s) : NaN; }
function progressMax(el) { const v = parseValidFloat(getAttributeValue(el, 'max') || ''); return v > 0 ? v : 1; }
function progressValue(el) { const raw = getAttributeValue(el, 'value'); if (raw === null) return null; const v = parseValidFloat(raw); if (!(v >= 0) || !isFinite(v)) return null; return Math.min(v, progressMax(el)); }
attributes(P('HTMLProgressElement'), {
  value: {
    get() { elSlot(this); const v = progressValue(this); return v === null ? 0 : v; },
    set(v) { elSlot(this); const n = toNumberStrict(v); if (n >= 0) setAttributeValue(this, 'value', String(n)); }
  },
  max: {
    get() { elSlot(this); return progressMax(this); },
    set(v) { elSlot(this); const n = toNumberStrict(v); if (n > 0) setAttributeValue(this, 'max', String(n)); }
  },
  position: { get() { elSlot(this); const v = progressValue(this); return v === null ? -1 : v / progressMax(this); } }
});
function toNumberStrict(v) { const n = Number(v); if (!isFinite(n)) throw new TypeError('The provided double value is non-finite.'); return n; }
function meterNumbers(el) {
  const num = (name, def) => { const raw = getAttributeValue(el, name); if (raw === null) return def; const v = parseValidFloat(raw); return isFinite(v) ? v : def; };
  const min = num('min', 0);
  const max = Math.max(num('max', 1), min);
  const value = Math.min(Math.max(num('value', 0), min), max);
  const low = Math.min(Math.max(num('low', min), min), max);
  const high = Math.min(Math.max(num('high', max), low), max);
  const optimum = Math.min(Math.max(num('optimum', (min + max) / 2), min), max);
  return { min, max, value, low, high, optimum };
}
const meterAttr = (name, setName) => ({
  get() { elSlot(this); return meterNumbers(this)[name]; },
  set(v) { elSlot(this); setAttributeValue(this, name, String(toNumberStrict(v))); }
});
attributes(P('HTMLMeterElement'), {
  value: meterAttr('value'), min: meterAttr('min'), max: meterAttr('max'), low: meterAttr('low'), high: meterAttr('high'), optimum: meterAttr('optimum')
});

// --- button

const buttonTypes = ['submit', 'reset', 'button'];
function buttonTypeOf(el) { const v = getAttributeValue(el, 'type'); if (v === null) return 'submit'; const l = asciiLowercase(v); return buttonTypes.indexOf(l) >= 0 ? l : 'submit'; }
attributes(P('HTMLButtonElement'), {
  type: { get() { elSlot(this); return buttonTypeOf(this); }, set(v) { elSlot(this); setAttributeValue(this, 'type', toDOMString(v)); } },
  formEnctype: { get() { elSlot(this); const v = getAttributeValue(this, 'formenctype'); const l = v === null ? '' : asciiLowercase(v); return ['application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain'].indexOf(l) >= 0 ? l : ''; }, set(v) { elSlot(this); setAttributeValue(this, 'formenctype', toDOMString(v)); } },
  formMethod: { get() { elSlot(this); const v = getAttributeValue(this, 'formmethod'); const l = v === null ? '' : asciiLowercase(v); return ['get', 'post', 'dialog'].indexOf(l) >= 0 ? l : ''; }, set(v) { elSlot(this); setAttributeValue(this, 'formmethod', toDOMString(v)); } }
});
function buttonActivation(event) {
  if (isDisabledControl(this)) return;
  const form = formOwnerOf(this);
  const t = buttonTypeOf(this);
  if (form === null) return;
  if (t === 'submit') submitFormFrom(form, this);
  else if (t === 'reset') resetFormFrom(form);
}
defineProperty(P('HTMLButtonElement'), 'activationBehavior', { value: buttonActivation, writable: true, enumerable: false, configurable: true });
controlValidators.button = function (el, out) {};

// --- form element

function resetControl(el) { const f = resetAlgorithms[htmlLocal(el)]; if (f) f(el); }
function resetFormFrom(form) {
  const ev = new Event('reset', { bubbles: true, cancelable: true });
  slotOf(ev).isTrusted = true;
  if (!dispatch(ev, form)) return;
  for (const d of descendantsOf(rootNode(form))) if (nodeType(d) === ELEMENT_NODE && isResettable(d) && formOwnerOf(d) === form) resetControl(d);
}
function formSlot(o) { const s = slotOf(o); if (!s || s.localName !== 'form' || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
function statically_validate(form) {
  let ok = true;
  const invalids = [];
  for (const el of submittableElementsOf(form)) {
    if (isCandidateForValidation(el) && !isValidControl(el)) apply(arrayPush, invalids, [el]);
  }
  return invalids;
}
function interactivelyValidate(form) {
  const invalids = statically_validate(form);
  if (invalids.length === 0) return true;
  let first = true;
  for (const el of invalids) fireInvalid(el);
  return false;
}
const SubmitEvent = defineEventClass('SubmitEvent', Event, [['submitter', null, asAny]]);
function submitFormFrom(form, submitter) {
  const s = slotOf(form);
  if (s.constructingEntryList || s.firingSubmit) return;
  if (!isConnected(form)) return;
  if (submitter !== null && submitter !== undefined) {
    const noValidate = getAttributeValue(form, 'novalidate') !== null || (getAttributeValue(submitter, 'formnovalidate') !== null);
    if (!noValidate && !interactivelyValidate(form)) return;
  } else if (getAttributeValue(form, 'novalidate') === null && !interactivelyValidate(form)) return;
  s.firingSubmit = true;
  let proceed = true;
  try {
    const ev = new SubmitEvent('submit', { bubbles: true, cancelable: true, submitter: submitter === undefined ? null : submitter });
    slotOf(ev).isTrusted = true;
    proceed = dispatch(ev, form);
  } finally { s.firingSubmit = false; }
  if (proceed) submitForm(form, submitter);
}
// The entry list of a form (4.10.21.4); `submitter` contributes its own entry.
function buildEntryList(form, submitter) {
  const s = slotOf(form);
  if (s.constructingEntryList) return null;
  s.constructingEntryList = true;
  const entries = [];
  try {
    for (const el of submittableElementsOf(form)) {
      if (isDisabledControl(el)) continue;
      if (htmlLocal(el) === 'button' && el !== submitter) continue;
      if (htmlLocal(el) === 'input') {
        const t = inputTypeOf(el);
        if (['submit', 'image', 'reset', 'button'].indexOf(t) >= 0 && el !== submitter) continue;
        if ((t === 'checkbox' || t === 'radio') && !inputState(el).checked) continue;
      }
      if (htmlLocal(el) === 'object') continue;
      const name = getAttributeValue(el, 'name');
      const n = htmlLocal(el);
      if (n === 'input' && inputTypeOf(el) === 'image') {
        const prefix = name === null || name === '' ? '' : name + '.';
        apply(arrayPush, entries, [[prefix + 'x', '0'], [prefix + 'y', '0']]);
        continue;
      }
      if (name === null || name === '') continue;
      if (n === 'select') {
        for (const o of selectOptions(el)) if (optionSelectedness(o) && !isActuallyDisabled(o)) apply(arrayPush, entries, [[name, optionValue(o)]]);
      } else if (n === 'input' && inputTypeOf(el) === 'file') {
        const files = inputState(el).files || [];
        if (files.length === 0) apply(arrayPush, entries, [[name, new File([], '', { type: 'application/octet-stream' })]]);
        else for (const f of files) apply(arrayPush, entries, [[name, f]]);
      } else if (n === 'input' && (inputTypeOf(el) === 'checkbox' || inputTypeOf(el) === 'radio')) {
        apply(arrayPush, entries, [[name, el.value]]);
      } else {
        const value = n === 'textarea' ? textareaAPIValue(el) : el.value;
        apply(arrayPush, entries, [[name, value]]);
      }
      const dirname = getAttributeValue(el, 'dirname');
      if (dirname !== null && dirname !== '' && (n === 'textarea' || (n === 'input' && ['text', 'search'].indexOf(inputTypeOf(el)) >= 0))) apply(arrayPush, entries, [[dirname, 'ltr']]);
    }
    const fd = new FormData();
    slotOf(fd).entries = entries.map(e => ({ name: e[0], value: e[1] }));
    const evt = new FormDataEvent('formdata', { bubbles: true, cancelable: false, formData: fd });
    slotOf(evt).isTrusted = true;
    dispatch(evt, form);
    return slotOf(fd).entries.map(e => [e.name, e.value]);
  } finally { s.constructingEntryList = false; }
}
const FormDataEvent = defineEventClass('FormDataEvent', Event, [['formData', null, asAny]]);
function urlEncodeEntries(entries) {
  const enc = s => encodeURIComponent(String(s).replace(/\r\n|\r|\n/g, '\r\n')).replace(/%20/g, '+').replace(/[!'()~]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
  return entries.map(e => enc(e[0]) + '=' + enc(typeof e[1] === 'string' ? e[1] : (e[1] && e[1].name) || '')).join('&');
}
function submitForm(form, submitter) {
  const attrOf = (name, formName) => (submitter !== null && submitter !== undefined && getAttributeValue(submitter, formName) !== null) ? getAttributeValue(submitter, formName) : getAttributeValue(form, name);
  let method = asciiLowercase(attrOf('method', 'formmethod') || 'get');
  if (['get', 'post', 'dialog'].indexOf(method) < 0) method = 'get';
  const entries = buildEntryList(form, submitter);
  if (entries === null) return;
  if (method === 'dialog') {
    for (let p = parentNode(form); p !== null; p = parentNode(p)) if (htmlLocal(p) === 'dialog') { if (typeof p.close === 'function') p.close(submitter && submitter.value !== undefined ? submitter.value : undefined); break; }
    return;
  }
  const action = attrOf('action', 'formaction');
  let url = documentBaseURL(mainDocument);
  if (action !== null && action !== '') { const parsed = N.urlParse(action, url); if (parsed === null) return; url = parsed[0]; }
  if (method === 'get') {
    const hash = url.indexOf('#');
    const base = hash >= 0 ? url.slice(0, hash) : url;
    const q = base.indexOf('?');
    const target = (q >= 0 ? base.slice(0, q) : base) + '?' + urlEncodeEntries(entries);
    formNavigate(form, target);
    return;
  }
  formNavigate(form, url, entries, attrOf('enctype', 'formenctype'));
}
function formNavigate(form, url, entries, enctype) {
  const target = getAttributeValue(form, 'target');
  if (target !== null && target !== '' && target !== '_self') {
    for (const d of descendantsOf(mainDocument)) {
      if (isIFrame(d) && getAttributeValue(d, 'name') === target && frameStateOf(d).win !== null) { d.src = url; return; }
    }
  }
  if (entries === undefined) N.navigate(url);
  else N.navigate(url);
}
operations(P('HTMLFormElement'), {
  submit() { const s = formSlot(this); if (!isConnected(this)) return; if (s.firingSubmit || s.constructingEntryList) return; submitForm(this, null); },
  requestSubmit(submitter = undefined) {
    formSlot(this);
    if (submitter !== undefined && submitter !== null) {
      if (!isNode(submitter) || !isSubmitButton(submitter)) throw new TypeError("Failed to execute 'requestSubmit' on 'HTMLFormElement': The specified element is not a submit button.");
      if (formOwnerOf(submitter) !== this) throw domError('NotFoundError', 'The specified element is not owned by this form element.');
    } else submitter = null;
    submitFormFrom(this, submitter);
  },
  reset() { const s = formSlot(this); if (s.resetting) return; s.resetting = true; try { resetFormFrom(this); } finally { s.resetting = false; } },
  checkValidity() { formSlot(this); const inv = statically_validate(this); for (const el of inv) fireInvalid(el); return inv.length === 0; },
  reportValidity() { formSlot(this); return interactivelyValidate(this); }
});
function isSubmitButton(el) {
  const n = htmlLocal(el);
  if (n === 'button') return buttonTypeOf(el) === 'submit';
  if (n === 'input') { const t = inputTypeOf(el); return t === 'submit' || t === 'image'; }
  return false;
}
attributes(P('HTMLFormElement'), {
  elements: { get() { const s = formSlot(this); if (!s.formControls) s.formControls = makeFormControlsCollection(this); return s.formControls; } },
  length: { get() { formSlot(this); return formElementsOf(this).length; } },
  encoding: { get() { return this.enctype; }, set(v) { this.enctype = v; } }
});

// --- HTMLFormControlsCollection and RadioNodeList

function HTMLFormControlsCollection() { throw new TypeError('Illegal constructor'); }
iface('HTMLFormControlsCollection', HTMLFormControlsCollection, HTMLCollection);
function RadioNodeList() { throw new TypeError('Illegal constructor'); }
iface('RadioNodeList', RadioNodeList, NodeList);
function makeFormControlsCollection(form) {
  const state = { isCollection: true, isFormControls: true, collect: () => formElementsOf(form), cache: null, cacheVersion: -1 };
  const named = name => {
    if (name === '') return undefined;
    const matches = collectionItems(state).filter(el => getAttributeValue(el, 'id') === name || getAttributeValue(el, 'name') === name);
    if (matches.length === 0) return undefined;
    if (matches.length === 1) return matches[0];
    return makeRadioNodeList(form, name);
  };
  return legacyObject(HTMLFormControlsCollection.prototype, {
    length: () => collectionItems(state).length,
    item: i => { const c = collectionItems(state); return i < c.length ? c[i] : null; },
    named,
    names: () => {
      const keys = [];
      for (const el of collectionItems(state)) for (const k of [getAttributeValue(el, 'id'), getAttributeValue(el, 'name')]) if (k !== null && k !== '' && keys.indexOf(k) < 0) apply(arrayPush, keys, [k]);
      return keys;
    }
  }, state);
}
operations(HTMLFormControlsCollection.prototype, {
  namedItem(name) {
    const s = slotOf(this);
    if (!s || !s.isFormControls) illegal();
    required(arguments, 1, 'namedItem');
    const n = toDOMString(name);
    if (n === '') return null;
    const matches = collectionItems(s).filter(el => getAttributeValue(el, 'id') === n || getAttributeValue(el, 'name') === n);
    if (matches.length === 0) return null;
    if (matches.length === 1) return matches[0];
    return makeRadioNodeList(null, n, matches);
  }
});
function makeRadioNodeList(form, name, fixed) {
  const collect = () => fixed !== undefined ? fixed.filter(() => true) : formElementsOf(form).filter(el => getAttributeValue(el, 'id') === name || getAttributeValue(el, 'name') === name);
  const state = { isNodeList: true, isRadioList: true, size: () => collect().length, at: i => { const c = collect(); return i < c.length ? c[i] : null; }, collect };
  return legacyObject(RadioNodeList.prototype, { length: state.size, item: state.at }, state);
}
attributes(RadioNodeList.prototype, {
  value: {
    get() {
      const s = slotOf(this);
      if (!s || !s.isRadioList) illegal();
      for (const el of s.collect()) if (htmlLocal(el) === 'input' && inputTypeOf(el) === 'radio' && inputState(el).checked) return getAttributeValue(el, 'value') === null ? 'on' : getAttributeValue(el, 'value');
      return '';
    },
    set(v) {
      const s = slotOf(this);
      if (!s || !s.isRadioList) illegal();
      const str = toDOMString(v);
      for (const el of s.collect()) {
        if (htmlLocal(el) !== 'input' || inputTypeOf(el) !== 'radio') continue;
        const val = getAttributeValue(el, 'value') === null ? 'on' : getAttributeValue(el, 'value');
        if (val === str || (str === 'on' && getAttributeValue(el, 'value') === null)) { el.checked = true; return; }
      }
      if (str === '') for (const el of s.collect()) if (htmlLocal(el) === 'input' && inputTypeOf(el) === 'radio') el.checked = false;
    }
  }
});

// new FormData(form) uses the entry list algorithm.
function constructEntryListImpl(form, submitter) {
  const entries = buildEntryList(form, submitter);
  if (entries === null) throw domError('InvalidStateError', 'The form is already being submitted or its entry list is being constructed');
  return entries.map(e => ({ name: e[0], value: e[1] }));
}
