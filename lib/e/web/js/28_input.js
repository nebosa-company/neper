// The input element (HTML Standard 4.10.5): type states, value modes and sanitization, date/number parsing, stepping, validity,
// the selection API and activation behaviour.

const inputTypeNames = ['hidden', 'text', 'search', 'tel', 'url', 'email', 'password', 'date', 'month', 'week', 'time', 'datetime-local', 'number', 'range', 'color', 'checkbox', 'radio', 'file', 'submit', 'image', 'reset', 'button'];
function inputTypeOf(el) {
  const v = getAttributeValue(el, 'type');
  if (v === null) return 'text';
  const l = asciiLowercase(v);
  return inputTypeNames.indexOf(l) >= 0 ? l : 'text';
}
function inputState(el) {
  const s = slotOf(el);
  if (!s.input) s.input = { value: '', dirty: false, checked: false, dirtyChecked: false, indeterminate: false, selStart: 0, selEnd: 0, selDir: 'none', files: null, selected: false };
  return s.input;
}
function valueModeOf(t) {
  if (['hidden', 'submit', 'image', 'reset', 'button'].indexOf(t) >= 0) return 'default';
  if (t === 'checkbox' || t === 'radio') return 'default/on';
  if (t === 'file') return 'filename';
  return 'value';
}
const textLike = ['text', 'search', 'tel', 'url', 'email', 'password'];
function selectionApplies(t) { return ['text', 'search', 'tel', 'url', 'password'].indexOf(t) >= 0; }

// --- microsyntaxes

function isLeapYear(y) { return y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0); }
function daysInMonth(y, m) { return [31, isLeapYear(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]; }
function utcMs(y, m, d, h, mi, s, ms) {
  const dt = new Date(0);
  dt.setUTCFullYear(y, m - 1, d);
  dt.setUTCHours(h || 0, mi || 0, s || 0, ms || 0);
  return dt.getTime();
}
function weeksInYear(y) {
  const jan1 = new Date(0); jan1.setUTCFullYear(y, 0, 1);
  const dow = jan1.getUTCDay();
  return dow === 4 || (isLeapYear(y) && dow === 3) ? 53 : 52;
}
function parseDateString(s) {
  const m = /^(\d{4,})-(\d\d)-(\d\d)$/.exec(s);
  if (!m) return null;
  const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  if (y < 1 || mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null;
  return { y, mo, d };
}
function parseMonthString(s) {
  const m = /^(\d{4,})-(\d\d)$/.exec(s);
  if (!m) return null;
  const y = Number(m[1]), mo = Number(m[2]);
  if (y < 1 || mo < 1 || mo > 12) return null;
  return { y, mo };
}
function parseWeekString(s) {
  const m = /^(\d{4,})-W(\d\d)$/.exec(s);
  if (!m) return null;
  const y = Number(m[1]), w = Number(m[2]);
  if (y < 1 || w < 1 || w > weeksInYear(y)) return null;
  return { y, w };
}
function parseTimeString(s) {
  const m = /^(\d\d):(\d\d)(?::(\d\d)(?:\.(\d{1,3}))?)?$/.exec(s);
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]), sec = m[3] === undefined ? 0 : Number(m[3]);
  if (h > 23 || mi > 59 || sec > 59) return null;
  const ms = m[4] === undefined ? 0 : Number((m[4] + '00').slice(0, 3));
  return { h, mi, s: sec, ms };
}
function parseLocalDateTimeString(s) {
  const m = /^(.*?)[T ](.*)$/.exec(s);
  if (!m) return null;
  const d = parseDateString(m[1]), t = parseTimeString(m[2]);
  return d && t ? { d, t } : null;
}
function pad(n, w) { let s = String(n); while (s.length < w) s = '0' + s; return s; }
function timeToString(ms) {
  const h = Math.floor(ms / 3600000) % 24, mi = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60, f = ms % 1000;
  let out = pad(h, 2) + ':' + pad(mi, 2);
  if (s !== 0 || f !== 0) { out += ':' + pad(s, 2); if (f !== 0) out += '.' + pad(f, 3).replace(/0+$/, ''); }
  return out;
}
function dateToString(ms) { const d = new Date(ms); return pad(d.getUTCFullYear(), 4) + '-' + pad(d.getUTCMonth() + 1, 2) + '-' + pad(d.getUTCDate(), 2); }
function mondayOfWeek(y, w) {
  const jan4 = utcMs(y, 1, 4, 0, 0, 0, 0);
  const dow = (new Date(jan4).getUTCDay() + 6) % 7;
  return jan4 - dow * 86400000 + (w - 1) * 7 * 86400000;
}
function weekToString(ms) {
  const d = new Date(ms);
  const thursday = ms + (3 - ((d.getUTCDay() + 6) % 7)) * 86400000;
  const y = new Date(thursday).getUTCFullYear();
  const w = Math.floor((thursday - utcMs(y, 1, 1, 0, 0, 0, 0)) / 86400000 / 7) + 1;
  return pad(y, 4) + '-W' + pad(w, 2);
}
// "Convert a string to a number" for the types that have one; NaN when the string is not valid.
function stringToNumber(t, s) {
  switch (t) {
    case 'date': { const d = parseDateString(s); return d ? utcMs(d.y, d.mo, d.d, 0, 0, 0, 0) : NaN; }
    case 'month': { const m = parseMonthString(s); return m ? (m.y - 1970) * 12 + (m.mo - 1) : NaN; }
    case 'week': { const w = parseWeekString(s); return w ? mondayOfWeek(w.y, w.w) : NaN; }
    case 'time': { const x = parseTimeString(s); return x ? ((x.h * 60 + x.mi) * 60 + x.s) * 1000 + x.ms : NaN; }
    case 'datetime-local': { const x = parseLocalDateTimeString(s); return x ? utcMs(x.d.y, x.d.mo, x.d.d, x.t.h, x.t.mi, x.t.s, x.t.ms) : NaN; }
    case 'number': case 'range': { const v = parseValidFloat(s); return isFinite(v) ? v : NaN; }
  }
  return NaN;
}
function numberToString(t, n) {
  switch (t) {
    case 'date': return dateToString(n);
    case 'month': { const y = 1970 + Math.floor(n / 12), m = ((n % 12) + 12) % 12 + 1; return pad(y, 4) + '-' + pad(m, 2); }
    case 'week': return weekToString(n);
    case 'time': return timeToString(((n % 86400000) + 86400000) % 86400000);
    case 'datetime-local': { const ms = ((n % 86400000) + 86400000) % 86400000; return dateToString(n) + 'T' + timeToString(ms); }
    case 'number': case 'range': return String(n);
  }
  return '';
}
const numericTypes = ['date', 'month', 'week', 'time', 'datetime-local', 'number', 'range'];
const dateTypes = ['date', 'month', 'week', 'time'];
function stepScale(t) { return t === 'date' ? 86400000 : t === 'week' ? 604800000 : t === 'time' || t === 'datetime-local' ? 1000 : 1; }
function defaultStep(t) { return t === 'time' || t === 'datetime-local' ? 60 : 1; }

// --- sanitization

function sanitizeValue(t, v, el) {
  switch (t) {
    case 'text': case 'search': case 'tel': case 'password': return v.replace(/[\r\n]/g, '');
    case 'url': return v.replace(/[\r\n]/g, '').replace(/^[ \t\n\f\r]+|[ \t\n\f\r]+$/g, '');
    case 'email': {
      v = v.replace(/[\r\n]/g, '');
      if (el && getAttributeValue(el, 'multiple') !== null) return v.split(',').map(x => x.replace(/^[ \t\n\f\r]+|[ \t\n\f\r]+$/g, '')).join(',');
      return v.replace(/^[ \t\n\f\r]+|[ \t\n\f\r]+$/g, '');
    }
    case 'date': return parseDateString(v) ? v : '';
    case 'month': return parseMonthString(v) ? v : '';
    case 'week': return parseWeekString(v) ? v : '';
    case 'time': return parseTimeString(v) ? v : '';
    case 'datetime-local': { const x = parseLocalDateTimeString(v); return x ? dateToString(utcMs(x.d.y, x.d.mo, x.d.d)) + 'T' + timeToString(((x.t.h * 60 + x.t.mi) * 60 + x.t.s) * 1000 + x.t.ms) : ''; }
    case 'number': return isFinite(parseValidFloat(v)) ? v : '';
    case 'range': return sanitizeRange(el, v);
    case 'color': { if (/^#[0-9a-fA-F]{6}$/.test(v)) return v.toLowerCase(); const c = N.parseColor(v); return c === null ? '#000000' : c; }
  }
  return v;
}
function rangeParams(el) {
  const num = name => { const raw = getAttributeValue(el, name); if (raw === null) return NaN; const x = parseValidFloat(raw); return isFinite(x) ? x : NaN; };
  let min = num('min'); if (isNaN(min)) min = 0;
  let max = num('max'); if (isNaN(max)) max = 100;
  if (max < min) max = min;
  return { min, max };
}
function sanitizeRange(el, v) {
  const { min, max } = rangeParams(el);
  let n = parseValidFloat(v);
  const rawMax = (() => { const x = parseValidFloat(getAttributeValue(el, 'max') || ''); return isFinite(x) ? x : 100; })();
  if (!isFinite(n)) n = rawMax < min ? min : min + (max - min) / 2;
  if (n < min) n = min;
  if (n > max) n = max;
  const step = allowedStep(el, 'range');
  if (step !== null) {
    const base = min;
    if ((n - base) % step !== 0) {
      let r = base + step * Math.round((n - base) / step);
      if (r > max) r = base + step * Math.floor((max - base) / step);
      if (r < min) r = base + step * Math.ceil((min - base) / step);
      n = r;
    }
  }
  return String(n);
}
function allowedStep(el, t) {
  const raw = getAttributeValue(el, 'step');
  let step = defaultStep(t);
  if (raw !== null) {
    if (asciiLowercase(raw) === 'any') return null;
    const v = parseValidFloat(raw);
    if (isFinite(v) && v > 0) step = v;
  }
  return step * stepScale(t);
}
function stepBaseOf(el, t) {
  const min = getAttributeValue(el, 'min');
  if (min !== null) { const n = stringToNumber(t, min); if (!isNaN(n)) return n; }
  const dv = getAttributeValue(el, 'value');
  if (dv !== null) { const n = stringToNumber(t, dv); if (!isNaN(n)) return n; }
  return t === 'week' ? -259200000 : 0;
}
function minOf(el, t) {
  const raw = getAttributeValue(el, 'min');
  if (raw === null) return t === 'range' ? rangeParams(el).min : NaN;
  const n = stringToNumber(t, raw);
  return isNaN(n) ? (t === 'range' ? rangeParams(el).min : NaN) : n;
}
function maxOf(el, t) {
  const raw = getAttributeValue(el, 'max');
  if (raw === null) return t === 'range' ? rangeParams(el).max : NaN;
  const n = stringToNumber(t, raw);
  return isNaN(n) ? (t === 'range' ? rangeParams(el).max : NaN) : n;
}

// --- the value

function inputValue(el) {
  const t = inputTypeOf(el), st = inputState(el);
  switch (valueModeOf(t)) {
    case 'value':
      if (t === 'range') return sanitizeRange(el, st.dirty ? st.value : (getAttributeValue(el, 'value') || ''));
      return st.dirty ? st.value : sanitizeValue(t, getAttributeValue(el, 'value') || '', el);
    case 'default': { const v = getAttributeValue(el, 'value'); return v === null ? '' : v; }
    case 'default/on': { const v = getAttributeValue(el, 'value'); return v === null ? 'on' : v; }
    default: {
      const f = st.files;
      return f && f.length ? 'C:\\fakepath\\' + f[0].name : '';
    }
  }
}
function setInputValue(el, v) {
  const t = inputTypeOf(el), st = inputState(el), mode = valueModeOf(t);
  if (mode === 'value') {
    const old = inputValue(el);
    st.value = sanitizeValue(t, v, el);
    st.dirty = true;
    if (inputValue(el) !== old) { st.selStart = st.selEnd = st.value.length; st.selDir = 'none'; }
  } else if (mode === 'filename') {
    if (v === '') st.files = null; else throw domError('InvalidStateError', 'This input element accepts a filename, which may only be programmatically set to the empty string.');
  } else setAttributeValue(el, 'value', v);
}
attributes(P('HTMLInputElement'), {
  type: { get() { elSlot(this); return inputTypeOf(this); }, set(v) { elSlot(this); setAttributeValue(this, 'type', toDOMString(v)); } },
  value: {
    get() { elSlot(this); return inputValue(this); },
    set(v) { elSlot(this); setInputValue(this, v === null ? '' : toDOMString(v)); }
  },
  checked: {
    get() { elSlot(this); return isCheckedInput(this); },
    set(v) { elSlot(this); setCheckedInput(this, !!v); }
  },
  indeterminate: { get() { elSlot(this); return inputState(this).indeterminate; }, set(v) { elSlot(this); inputState(this).indeterminate = !!v; } },
  valueAsNumber: {
    get() { elSlot(this); const t = inputTypeOf(this); return numericTypes.indexOf(t) >= 0 ? stringToNumber(t, inputValue(this)) : NaN; },
    set(v) {
      elSlot(this);
      const t = inputTypeOf(this);
      const n = Number(v);
      if (numericTypes.indexOf(t) < 0) throw domError('InvalidStateError', 'The input type does not support valueAsNumber.');
      if (typeof v === 'symbol') throw new TypeError('Cannot convert a Symbol value to a number');
      if (n === Infinity || n === -Infinity) throw new TypeError("Failed to set the 'valueAsNumber' property on 'HTMLInputElement': The provided double value is non-finite.");
      setInputValue(this, isNaN(n) ? '' : numberToString(t, n));
    }
  },
  valueAsDate: {
    get() {
      elSlot(this);
      const t = inputTypeOf(this);
      if (dateTypes.indexOf(t) < 0) return null;
      const n = stringToNumber(t, inputValue(this));
      if (isNaN(n)) return null;
      return new Date(t === 'month' ? utcMs(1970 + Math.floor(n / 12), (n % 12 + 12) % 12 + 1, 1, 0, 0, 0, 0) : n);
    },
    set(v) {
      elSlot(this);
      const t = inputTypeOf(this);
      if (dateTypes.indexOf(t) < 0) throw domError('InvalidStateError', 'The input type does not support valueAsDate.');
      if (v !== null && !(v instanceof Date)) throw new TypeError("Failed to set the 'valueAsDate' property on 'HTMLInputElement': The provided value is not a Date.");
      if (v === null || isNaN(v.getTime())) { setInputValue(this, ''); return; }
      const ms = v.getTime();
      let n = ms;
      if (t === 'month') n = (v.getUTCFullYear() - 1970) * 12 + v.getUTCMonth();
      else if (t === 'time') n = ((ms % 86400000) + 86400000) % 86400000;
      setInputValue(this, numberToString(t, n));
    }
  },
  list: { get() { elSlot(this); const id = getAttributeValue(this, 'list'); if (id === null || ['hidden', 'password', 'checkbox', 'radio', 'file', 'submit', 'image', 'reset', 'button'].indexOf(inputTypeOf(this)) >= 0) return null; const f = findByIdInTree(rootNode(this), id); return f !== null && htmlLocal(f) === 'datalist' ? f : null; } },
  files: {
    get() { elSlot(this); if (inputTypeOf(this) !== 'file') return null; const st = inputState(this); if (!st.fileList) st.fileList = makeFileListObject(this); return st.fileList; },
    set(v) {
      elSlot(this);
      if (inputTypeOf(this) !== 'file') return;
      if (v === null || !(isObject(v) && slotOf(v) && slotOf(v).isFileList)) throw new TypeError("Failed to set the 'files' property on 'HTMLInputElement': The provided value is not of type 'FileList'.");
      inputState(this).files = slotOf(v).files.slice();
      delete inputState(this).fileList;
    }
  },
  formEnctype: { get() { elSlot(this); const v = getAttributeValue(this, 'formenctype'); const l = v === null ? '' : asciiLowercase(v); return ['application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain'].indexOf(l) >= 0 ? l : ''; }, set(v) { elSlot(this); setAttributeValue(this, 'formenctype', toDOMString(v)); } },
  formMethod: { get() { elSlot(this); const v = getAttributeValue(this, 'formmethod'); const l = v === null ? '' : asciiLowercase(v); return ['get', 'post', 'dialog'].indexOf(l) >= 0 ? l : ''; }, set(v) { elSlot(this); setAttributeValue(this, 'formmethod', toDOMString(v)); } }
});
reflectURL(P('HTMLInputElement'), 'formAction', 'formaction');
reflectBool(P('HTMLInputElement'), 'formNoValidate', 'formnovalidate');
reflectString(P('HTMLInputElement'), 'formTarget', 'formtarget');
function makeFileListObject(input) {
  const st = inputState(input);
  const files = () => st.files || [];
  return makeFileListFrom(files);
}
operations(P('HTMLInputElement'), {
  stepUp(n = 1) { elSlot(this); stepInput(this, toInt32(n), true); },
  stepDown(n = 1) { elSlot(this); stepInput(this, toInt32(n), false); },
  showPicker() {
    elSlot(this);
    if (getAttributeValue(this, 'disabled') !== null || (readOnlyApplies(inputTypeOf(this)) && getAttributeValue(this, 'readonly') !== null)) throw domError('InvalidStateError', 'The input element is not mutable.');
    const t = inputTypeOf(this);
    if (['date', 'month', 'week', 'time', 'datetime-local', 'color', 'file'].indexOf(t) < 0 && !(getAttributeValue(this, 'list') !== null && list_ok(this))) throw domError('NotSupportedError', 'showPicker() is not supported for this input type.');
    throw domError('NotAllowedError', 'showPicker() requires a user gesture.');
  }
});
function list_ok(el) { return el.list !== null; }
function toInt32(v) { return v | 0; }

// stepUp / stepDown (4.10.5.4)
function stepInput(el, n, up) {
  const t = inputTypeOf(el);
  if (numericTypes.indexOf(t) < 0) throw domError('InvalidStateError', 'This form element is not steppable.');
  const step = allowedStep(el, t);
  if (step === null) throw domError('InvalidStateError', 'This form element does not have an allowed value step.');
  const base = stepBaseOf(el, t);
  const min = minOf(el, t), max = maxOf(el, t);
  if (!isNaN(min) && !isNaN(max) && min > max) return;
  if (!isNaN(min) && !isNaN(max)) {
    const firstValid = base + step * Math.ceil((min - base) / step);
    if (firstValid > max) return;
  }
  let value = stringToNumber(t, inputValue(el));
  if (isNaN(value)) value = 0;
  const before = value;
  const off = (value - base) / step;
  if (off !== Math.round(off) && Math.abs(off - Math.round(off)) > 1e-9 * Math.max(1, Math.abs(off))) {
    value = up ? base + step * Math.ceil(off) : base + step * Math.floor(off);
    if (up ? n < 1 && false : false) {}
    if (n > 1 || n < -1) { const extra = Math.abs(n) - 1; value += (up ? 1 : -1) * extra * step; }
    else if (n < 0) { value += (up ? -1 : 1) * 0; }
  } else {
    value += (up ? 1 : -1) * n * step;
  }
  if (!isNaN(min) && value < min) value = base + step * Math.ceil((min - base) / step);
  if (!isNaN(max) && value > max) value = base + step * Math.floor((max - base) / step);
  if ((!up && value > before) || (up && value < before)) return;
  setInputValue(el, numberToString(t, value));
}

// --- checkedness and radio groups

function isCheckedInput(el) {
  const st = inputState(el);
  return st.dirtyChecked ? st.checked : getAttributeValue(el, 'checked') !== null;
}
function radioGroupOf(el) {
  const name = getAttributeValue(el, 'name');
  if (name === null || name === '') return [el];
  const form = formOwnerOf(el);
  const root = rootNode(el);
  const out = [];
  for (const d of descendantsOf(root)) {
    if (nodeType(d) !== ELEMENT_NODE || htmlLocal(d) !== 'input' || inputTypeOf(d) !== 'radio') continue;
    if (getAttributeValue(d, 'name') !== name) continue;
    if (formOwnerOf(d) !== form) continue;
    apply(arrayPush, out, [d]);
  }
  return out;
}
function setCheckedInput(el, v) {
  const st = inputState(el);
  st.checked = v;
  st.dirtyChecked = true;
  if (v && inputTypeOf(el) === 'radio') uncheckGroupMembers(el);
}
function uncheckGroupMembers(el) {
  for (const o of radioGroupOf(el)) if (o !== el && isCheckedInput(o)) { const s = inputState(o); s.checked = false; s.dirtyChecked = true; }
}

// --- reset and cloning

resetAlgorithms.input = function (el) {
  const st = inputState(el);
  st.dirty = false; st.value = ''; st.dirtyChecked = false; st.checked = false; st.files = null; delete st.fileList;
  st.indeterminate = st.indeterminate;
  const t = inputTypeOf(el);
  if (valueModeOf(t) === 'value') { st.selStart = st.selEnd = inputValue(el).length; st.selDir = 'none'; }
  if (t === 'radio' && isCheckedInput(el)) uncheckGroupMembers(el);
};
function cloneFormState(node, copy) {
  const s = slotOf(node);
  if (s.nodeType !== ELEMENT_NODE || s.namespaceURI !== HTML_NS) return;
  if (s.localName === 'input' && s.input) {
    const a = s.input, b = inputState(copy);
    b.value = a.value; b.dirty = a.dirty; b.checked = a.checked; b.dirtyChecked = a.dirtyChecked; b.indeterminate = a.indeterminate;
    b.selStart = a.selStart; b.selEnd = a.selEnd; b.selDir = a.selDir; b.files = a.files ? a.files.slice() : null;
  } else if (s.localName === 'textarea' && s.textarea) {
    const a = s.textarea, b = textareaState(copy);
    b.value = a.value; b.dirty = a.dirty; b.selStart = a.selStart; b.selEnd = a.selEnd; b.selDir = a.selDir;
  } else if (s.localName === 'option' && s.optionState) {
    const b = optionState(copy);
    b.selected = s.optionState.selected; b.dirty = s.optionState.dirty;
  }
}

// --- attribute changes

const prevAttrInput = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrInput(el, name, oldValue, value);
  if (htmlLocal(el) === 'input') {
    const st = inputState(el);
    if (name === 'type') {
      const oldType = oldValue === null ? 'text' : (inputTypeNames.indexOf(asciiLowercase(oldValue)) >= 0 ? asciiLowercase(oldValue) : 'text');
      const newType = inputTypeOf(el);
      if (oldType !== newType) inputTypeChanged(el, oldType, newType);
    } else if (name === 'value') {
      if (!st.dirty && valueModeOf(inputTypeOf(el)) === 'value') { st.selStart = st.selEnd = inputValue(el).length; }
    } else if (name === 'checked') {
      if (!st.dirtyChecked && value !== null && inputTypeOf(el) === 'radio') uncheckGroupMembers(el);
    }
  } else if (htmlLocal(el) === 'textarea' && name === 'maxlength') { /* limits only matter for user edits */ }
};
function inputTypeChanged(el, oldType, newType) {
  const st = inputState(el);
  const oldMode = valueModeOf(oldType), newMode = valueModeOf(newType);
  if (oldMode === 'value' && (newMode === 'default' || newMode === 'default/on')) {
    const cur = st.dirty ? sanitizeValue(oldType, st.value, el) : sanitizeValue(oldType, getAttributeValue(el, 'value') || '', el);
    if (cur !== '') setAttributeValue(el, 'value', cur);
    st.dirty = false;
  } else if ((oldMode === 'default' || oldMode === 'default/on') && newMode === 'value') {
    st.value = getAttributeValue(el, 'value') || '';
    st.dirty = false;
  } else if (oldMode === 'filename' && newMode !== 'filename') {
    st.value = ''; st.files = null; delete st.fileList; st.dirty = false;
  } else if (oldMode !== 'filename' && newMode === 'filename') {
    st.value = ''; st.dirty = false;
  } else if (oldMode === 'value' && newMode === 'value' && st.dirty) {
    st.value = sanitizeValue(newType, st.value, el);
  }
  if (newType === 'radio' && isCheckedInput(el)) uncheckGroupMembers(el);
  if (selectionApplies(newType) && !selectionApplies(oldType)) { const l = inputValue(el).length; st.selStart = st.selEnd = l; }
}
const prevInsertedInput = elementInserted;
elementInserted = function (el) {
  prevInsertedInput(el);
  if (htmlLocal(el) === 'input' && inputTypeOf(el) === 'radio' && isCheckedInput(el)) uncheckGroupMembers(el);
};

// --- validity

function emailValid(v) { return /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(v); }
function patternRegExp(p) {
  try { return new RegExp('^(?:' + p + ')$', 'v'); } catch (e) {}
  try { return new RegExp('^(?:' + p + ')$', 'u'); } catch (e) {}
  return null;
}
controlValidators.input = function (el, out) {
  const t = inputTypeOf(el);
  const value = inputValue(el);
  const required = getAttributeValue(el, 'required') !== null;
  const mutable = getAttributeValue(el, 'disabled') === null && !(readOnlyApplies(t) && getAttributeValue(el, 'readonly') !== null);
  if (required) {
    if (t === 'checkbox') { if (!isCheckedInput(el)) out.valueMissing = true; }
    else if (t === 'radio') { if (!radioGroupOf(el).some(isCheckedInput)) out.valueMissing = true; }
    else if (t === 'file') { const f = inputState(el).files; if (!f || f.length === 0) out.valueMissing = true; }
    else if (['text', 'search', 'url', 'tel', 'email', 'password', 'date', 'month', 'week', 'time', 'datetime-local', 'number'].indexOf(t) >= 0 && mutable && value === '') out.valueMissing = true;
  }
  if (value !== '') {
    if (t === 'email') {
      const parts = getAttributeValue(el, 'multiple') !== null ? value.split(',').map(x => x.trim()) : [value];
      if (parts.some(p => !emailValid(p))) out.typeMismatch = true;
    } else if (t === 'url') {
      const u = N.urlParse(value, '');
      if (u === null || !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) out.typeMismatch = true;
    }
    const pattern = getAttributeValue(el, 'pattern');
    if (pattern !== null && ['text', 'search', 'tel', 'url', 'email', 'password'].indexOf(t) >= 0) {
      const re = patternRegExp(pattern);
      if (re !== null) {
        if (t === 'email' && getAttributeValue(el, 'multiple') !== null) { if (value.split(',').some(p => !re.test(p.trim()))) out.patternMismatch = true; }
        else if (!re.test(value)) out.patternMismatch = true;
      }
    }
    if (numericTypes.indexOf(t) >= 0) {
      const n = stringToNumber(t, value);
      if (!isNaN(n)) {
        const min = minOf(el, t), max = maxOf(el, t);
        if (t === 'time' && !isNaN(min) && !isNaN(max) && min > max) {
          if (n < min && n > max) { out.rangeUnderflow = true; out.rangeOverflow = true; }
        } else {
          if (!isNaN(min) && n < min) out.rangeUnderflow = true;
          if (!isNaN(max) && n > max) out.rangeOverflow = true;
        }
        const step = allowedStep(el, t);
        if (step !== null) {
          const off = (n - stepBaseOf(el, t)) / step;
          if (Math.abs(off - Math.round(off)) > 1e-9 * Math.max(1, Math.abs(off))) out.stepMismatch = true;
        }
      }
    }
  }
};

// --- activation

function fireInputAndChange(el) {
  const i = new Event('input', { bubbles: true, composed: true });
  slotOf(i).isTrusted = true;
  dispatch(i, el);
  const c = new Event('change', { bubbles: true });
  slotOf(c).isTrusted = true;
  dispatch(c, el);
}
defineProperty(P('HTMLInputElement'), 'legacyPreActivationBehavior', {
  value: function (event) {
    const t = inputTypeOf(this), st = inputState(this);
    if (t === 'checkbox') { st.preChecked = isCheckedInput(this); st.preIndeterminate = st.indeterminate; setCheckedInput(this, !st.preChecked); st.indeterminate = false; }
    else if (t === 'radio') {
      st.preChecked = isCheckedInput(this);
      st.preGroup = radioGroupOf(this).filter(o => o !== this && isCheckedInput(o));
      setCheckedInput(this, true);
    }
  }, writable: true, enumerable: false, configurable: true
});
defineProperty(P('HTMLInputElement'), 'legacyCanceledActivationBehavior', {
  value: function () {
    const t = inputTypeOf(this), st = inputState(this);
    if (t === 'checkbox') { setCheckedInput(this, st.preChecked); st.indeterminate = st.preIndeterminate; }
    else if (t === 'radio') {
      if (st.preChecked === false) { const s = inputState(this); s.checked = false; s.dirtyChecked = true; }
      for (const o of st.preGroup || []) setCheckedInput(o, true);
    }
  }, writable: true, enumerable: false, configurable: true
});
defineProperty(P('HTMLInputElement'), 'activationBehavior', {
  value: function (event) {
    if (isDisabledControl(this)) return;
    const t = inputTypeOf(this);
    if (t === 'checkbox' || t === 'radio') { if (isConnected(this)) fireInputAndChange(this); }
    else if (t === 'submit' || t === 'image') { const f = formOwnerOf(this); if (f !== null) submitFormFrom(f, this); }
    else if (t === 'reset') { const f = formOwnerOf(this); if (f !== null) resetFormFrom(f); }
  }, writable: true, enumerable: false, configurable: true
});

// --- the selection API

function selectionTarget(el) { return htmlLocal(el) === 'textarea' ? textareaState(el) : inputState(el); }
function selectionValue(el) { return htmlLocal(el) === 'textarea' ? textareaAPIValue(el) : inputValue(el); }
function selectionAvailable(el) { return htmlLocal(el) === 'textarea' || selectionApplies(inputTypeOf(el)); }
function clampSel(el) {
  const st = selectionTarget(el), len = selectionValue(el).length;
  if (st.selStart > len) st.selStart = len;
  if (st.selEnd > len) st.selEnd = len;
}
function queueSelectEvent(el) {
  scheduleTimer(() => { const ev = new Event('select', { bubbles: true }); slotOf(ev).isTrusted = true; dispatch(ev, el); }, 0, false, []);
}
function setSelectionRangeOf(el, start, end, dir, quiet) {
  const st = selectionTarget(el), len = selectionValue(el).length;
  if (end > len) end = len;
  if (start > end) start = end;
  const changed = st.selStart !== start || st.selEnd !== end || st.selDir !== dir;
  st.selStart = start; st.selEnd = end; st.selDir = dir;
  if (changed && !quiet) queueSelectEvent(el);
}
function ulong(v) { const n = Number(v); if (!isFinite(n)) return 0; const t = Math.trunc(n); return t < 0 ? t + 4294967296 : t % 4294967296; }
function selectionAttrs(name) {
  return {
    selectionStart: {
      get() { elSlot(this); if (!selectionAvailable(this)) return null; clampSel(this); return selectionTarget(this).selStart; },
      set(v) { elSlot(this); if (!selectionAvailable(this)) throw domError('InvalidStateError', 'The input element\'s type does not support selection.'); clampSel(this); const st = selectionTarget(this); setSelectionRangeOf(this, v === null ? 0 : ulong(v), Math.max(v === null ? 0 : ulong(v), st.selEnd), st.selDir); }
    },
    selectionEnd: {
      get() { elSlot(this); if (!selectionAvailable(this)) return null; clampSel(this); return selectionTarget(this).selEnd; },
      set(v) { elSlot(this); if (!selectionAvailable(this)) throw domError('InvalidStateError', 'The input element\'s type does not support selection.'); clampSel(this); setSelectionRangeOf(this, selectionTarget(this).selStart, v === null ? 0 : ulong(v), selectionTarget(this).selDir); }
    },
    selectionDirection: {
      get() { elSlot(this); if (!selectionAvailable(this)) return null; return selectionTarget(this).selDir; },
      set(v) { elSlot(this); if (!selectionAvailable(this)) throw domError('InvalidStateError', 'The input element\'s type does not support selection.'); clampSel(this); const st = selectionTarget(this); const d = v === null ? 'none' : String(v); setSelectionRangeOf(this, st.selStart, st.selEnd, d === 'forward' || d === 'backward' ? d : 'none'); }
    }
  };
}
const selectionOps = {
  select() {
    elSlot(this);
    if (htmlLocal(this) === 'input' && !selectionApplies(inputTypeOf(this)) && !(inputTypeOf(this) === 'email' || inputTypeOf(this) === 'number')) return;
    if (htmlLocal(this) === 'input' && !selectionAvailable(this)) return;
    const len = selectionValue(this).length;
    setSelectionRangeOf(this, 0, len, 'none');
  },
  setSelectionRange(start, end, direction = undefined) {
    elSlot(this);
    required(arguments, 2, 'setSelectionRange');
    if (!selectionAvailable(this)) throw domError('InvalidStateError', 'The input element\'s type does not support selection.');
    const d = direction === undefined ? 'none' : String(direction);
    setSelectionRangeOf(this, ulong(start), ulong(end), d === 'forward' || d === 'backward' ? d : 'none');
  },
  setRangeText(replacement, start = undefined, end = undefined, selectionMode = 'preserve') {
    elSlot(this);
    required(arguments, 1, 'setRangeText');
    if (!selectionAvailable(this)) throw domError('InvalidStateError', 'The input element\'s type does not support selection.');
    const rep = toDOMString(replacement);
    const st = selectionTarget(this);
    clampSel(this);
    let s, e;
    if (start === undefined) { s = st.selStart; e = st.selEnd; } else { s = ulong(start); e = ulong(end); if (s > e) throw domError('IndexSizeError', 'The start is greater than the end.'); }
    const mode = String(selectionMode);
    if (['select', 'start', 'end', 'preserve'].indexOf(mode) < 0) throw new TypeError("Failed to execute 'setRangeText' on 'HTMLInputElement': The provided value '" + mode + "' is not a valid enum value of type SelectionMode.");
    const cur = selectionValue(this);
    if (s > cur.length) s = cur.length;
    if (e > cur.length) e = cur.length;
    const oldStart = st.selStart, oldEnd = st.selEnd;
    const next = cur.slice(0, s) + rep + cur.slice(e);
    if (htmlLocal(this) === 'textarea') { st.value = next; st.dirty = true; } else { st.value = sanitizeValue(inputTypeOf(this), next, this); st.dirty = true; }
    const newEnd = s + rep.length;
    const delta = rep.length - (e - s);
    let ns = st.selStart, ne = st.selEnd;
    if (mode === 'select') { ns = s; ne = newEnd; }
    else if (mode === 'start') { ns = ne = s; }
    else if (mode === 'end') { ns = ne = newEnd; }
    else {
      const adjust = x => (x > e ? x + delta : x > s ? s : x);
      ns = adjust(oldStart);
      ne = adjust(oldEnd);
      if (oldStart > s && oldStart <= e) ns = newEnd;
      if (oldEnd > s && oldEnd <= e) ne = newEnd;
    }
    st.selStart = ns; st.selEnd = ne;
    clampSel(this);
  }
};
attributes(P('HTMLInputElement'), selectionAttrs());
operations(P('HTMLInputElement'), selectionOps);
