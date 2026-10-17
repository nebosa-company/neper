// CSSOM and CSSOM View: CSSStyleDeclaration (inline and computed), geometry of elements, DOMRect.

const cssPropertyNames = (
  'align-content align-items align-self all animation animation-delay animation-direction animation-duration animation-fill-mode ' +
  'animation-iteration-count animation-name animation-play-state animation-timing-function appearance aspect-ratio backdrop-filter ' +
  'backface-visibility background background-attachment background-blend-mode background-clip background-color background-image ' +
  'background-origin background-position background-position-x background-position-y background-repeat background-size block-size ' +
  'border border-block border-block-end border-block-start border-bottom border-bottom-color border-bottom-left-radius ' +
  'border-bottom-right-radius border-bottom-style border-bottom-width border-collapse border-color border-image border-inline ' +
  'border-inline-end border-inline-start border-left border-left-color border-left-style border-left-width border-radius border-right ' +
  'border-right-color border-right-style border-right-width border-spacing border-style border-top border-top-color ' +
  'border-top-left-radius border-top-right-radius border-top-style border-top-width border-width bottom box-shadow box-sizing ' +
  'break-after break-before break-inside caption-side caret-color clear clip clip-path color color-scheme column-count column-fill ' +
  'column-gap column-rule column-rule-color column-rule-style column-rule-width column-span column-width columns contain content ' +
  'counter-increment counter-reset cursor direction display empty-cells filter flex flex-basis flex-direction flex-flow flex-grow ' +
  'flex-shrink flex-wrap float font font-family font-feature-settings font-kerning font-size font-size-adjust font-stretch font-style ' +
  'font-variant font-variant-caps font-variant-ligatures font-variant-numeric font-variation-settings font-weight gap grid ' +
  'grid-area grid-auto-columns grid-auto-flow grid-auto-rows grid-column grid-column-end grid-column-gap grid-column-start grid-gap ' +
  'grid-row grid-row-end grid-row-gap grid-row-start grid-template grid-template-areas grid-template-columns grid-template-rows ' +
  'height hyphens image-rendering inline-size inset inset-block inset-inline isolation justify-content justify-items justify-self left ' +
  'letter-spacing line-break line-height list-style list-style-image list-style-position list-style-type margin margin-block ' +
  'margin-bottom margin-inline margin-left margin-right margin-top mask max-block-size max-height max-inline-size max-width ' +
  'min-block-size min-height min-inline-size min-width mix-blend-mode object-fit object-position offset opacity order orphans outline ' +
  'outline-color outline-offset outline-style outline-width overflow overflow-anchor overflow-wrap overflow-x overflow-y ' +
  'overscroll-behavior padding padding-block padding-bottom padding-inline padding-left padding-right padding-top page-break-after ' +
  'page-break-before page-break-inside perspective perspective-origin place-content place-items place-self pointer-events position ' +
  'quotes resize right rotate row-gap scale scroll-behavior scroll-margin scroll-padding scroll-snap-align scroll-snap-type ' +
  'scrollbar-color scrollbar-width shape-outside table-layout tab-size text-align text-align-last text-decoration text-decoration-color ' +
  'text-decoration-line text-decoration-style text-decoration-thickness text-indent text-justify text-overflow text-rendering ' +
  'text-shadow text-transform text-underline-offset top touch-action transform transform-box transform-origin transform-style ' +
  'transition transition-delay transition-duration transition-property transition-timing-function translate unicode-bidi user-select ' +
  'vertical-align visibility white-space widows width will-change word-break word-spacing word-wrap writing-mode z-index zoom ' +
  '-webkit-appearance -webkit-line-clamp -webkit-text-stroke -webkit-text-fill-color -webkit-box-orient -webkit-tap-highlight-color ' +
  '-webkit-font-smoothing -moz-osx-font-smoothing -webkit-text-size-adjust -webkit-user-select -webkit-box-shadow -webkit-transition ' +
  '-webkit-transform -webkit-animation -webkit-filter -webkit-mask-image').split(' ');
const cssPropertySet = new Set(cssPropertyNames);
function camelToDashed(name) {
  if (name === 'cssFloat') return 'float';
  let out = '';
  for (let i = 0; i < name.length; i++) {
    const c = name[i];
    if (c >= 'A' && c <= 'Z') out += '-' + String.fromCharCode(c.charCodeAt(0) + 32);
    else out += c;
  }
  if (out.startsWith('webkit-') || out.startsWith('moz-')) out = '-' + out;
  return out;
}
function dashedToCamel(name) {
  let out = '', up = false;
  for (let i = 0; i < name.length; i++) {
    const c = name[i];
    if (c === '-') { if (i > 0) up = true; continue; }
    out += up ? c.toUpperCase() : c;
    up = false;
  }
  return out;
}
function isKnownProperty(name) {
  if (name === 'cssFloat') return true;
  if (cssPropertySet.has(name)) return true;
  if (name.indexOf('-') < 0 && /[A-Z]/.test(name)) return cssPropertySet.has(camelToDashed(name));
  if (name.startsWith('webkit') && /[A-Z]/.test(name)) return cssPropertySet.has(camelToDashed(name));
  return false;
}
function parseDeclarations(text) {
  const out = [];
  let depth = 0, quote = '', start = 0;
  const parts = [];
  for (let i = 0; i <= text.length; i++) {
    const c = text[i];
    if (quote) { if (c === '\\') i++; else if (c === quote) quote = ''; continue; }
    if (c === '"' || c === "'") { quote = c; continue; }
    if (c === '(') depth++;
    else if (c === ')') { if (depth > 0) depth--; }
    else if ((c === ';' && depth === 0) || i === text.length) { parts.push(text.slice(start, i)); start = i + 1; }
  }
  for (const part of parts) {
    const colon = part.indexOf(':');
    if (colon < 0) continue;
    const name = part.slice(0, colon).trim();
    let value = part.slice(colon + 1).trim();
    if (name === '' || value === '') continue;
    let important = false;
    const m = /!\s*important\s*$/i.exec(value);
    if (m) { important = true; value = value.slice(0, m.index).trim(); }
    if (value === '') continue;
    const lname = name.startsWith('--') ? name : asciiLowercase(name);
    if (!name.startsWith('--') && !cssPropertySet.has(lname)) continue;
    const existing = out.findIndex(d => d.name === lname);
    if (existing >= 0) out.splice(existing, 1);
    out.push({ name: lname, value, important });
  }
  return out;
}
function serializeDeclarations(list) {
  return list.map(d => d.name + ': ' + d.value + (d.important ? ' !important' : '') + ';').join(' ');
}

function CSSStyleDeclaration() { throw new TypeError('Illegal constructor'); }
iface('CSSStyleDeclaration', CSSStyleDeclaration, null);
function csSlot(o) { const s = slotOf(o); if (!s || !s.isStyleDecl) illegal(); return s; }
function declList(s) {
  if (s.computedFor !== undefined) return null;
  const el = s.element;
  const attr = getAttributeValue(el, 'style');
  if (attr === null) return [];
  if (s.cacheText !== attr) { s.cache = parseDeclarations(attr); s.cacheText = attr; }
  return s.cache;
}
function writeDecls(s, list) {
  const text = serializeDeclarations(list);
  s.cache = list; s.cacheText = text;
  if (list.length === 0 && getAttributeValue(s.element, 'style') === null) return;
  setAttributeValue(s.element, 'style', text);
}
function getDeclValue(s, prop) {
  if (s.computedFor !== undefined) {
    const v = N.computed(idOf(s.computedFor), prop);
    return v === undefined ? '' : v;
  }
  for (const d of declList(s)) if (d.name === prop) return d.value;
  return '';
}
function setDeclValue(s, prop, value, priority) {
  if (s.computedFor !== undefined || s.readonly) throw domError('NoModificationAllowedError', 'These styles are computed, and therefore the ' + prop + ' property is read-only.');
  const list = declList(s).slice();
  const i = list.findIndex(d => d.name === prop);
  if (value === '') { if (i >= 0) list.splice(i, 1); writeDecls(s, list); return; }
  const entry = { name: prop, value: value.trim(), important: priority === 'important' };
  if (i >= 0) list.splice(i, 1);
  list.push(entry);
  writeDecls(s, list);
}
function makeStyleDecl(element, computedFor) {
  const state = { isStyleDecl: true, element, computedFor, cache: [], cacheText: null };
  const decl = legacyObject(CSSStyleDeclaration.prototype, {
    length: () => styleNames(state).length,
    item: i => { const n = styleNames(state); return i < n.length ? n[i] : null; },
    named: name => (isKnownProperty(name) ? getDeclValue(state, name === 'cssFloat' ? 'float' : camelToDashed(name.indexOf('-') >= 0 ? dashedToCamel(name) : name)) : undefined),
    namedSetter: (name, value) => setDeclValue(state, name === 'cssFloat' ? 'float' : camelToDashed(name.indexOf('-') >= 0 ? dashedToCamel(name) : name), value === null ? '' : toDOMString(value), ''),
    enumerableNamed: true
  }, state);
  return decl;
}
function styleNames(s) {
  if (s.computedFor !== undefined) return cssPropertyNames.filter(n => N.computed(idOf(s.computedFor), n) !== undefined);
  return declList(s).map(d => d.name);
}
operations(CSSStyleDeclaration.prototype, {
  item(index) { const s = csSlot(this); required(arguments, 1, 'item'); const n = styleNames(s); const i = toUnsignedLong(index); return i < n.length ? n[i] : ''; },
  getPropertyValue(property) { const s = csSlot(this); required(arguments, 1, 'getPropertyValue'); const p = toDOMString(property); return getDeclValue(s, p.startsWith('--') ? p : asciiLowercase(p)); },
  getPropertyPriority(property) { const s = csSlot(this); required(arguments, 1, 'getPropertyPriority'); if (s.computedFor !== undefined) return ''; const p = asciiLowercase(toDOMString(property)); for (const d of declList(s)) if (d.name === p) return d.important ? 'important' : ''; return ''; },
  setProperty(property, value, priority = '') {
    const s = csSlot(this);
    required(arguments, 2, 'setProperty');
    const p = toDOMString(property);
    const name = p.startsWith('--') ? p : asciiLowercase(p);
    const v = value === null ? '' : toDOMString(value);
    const pr = asciiLowercase(toDOMString(priority));
    if (pr !== '' && pr !== 'important') return;
    if (s.computedFor !== undefined) throw domError('NoModificationAllowedError', 'read-only');
    if (!name.startsWith('--') && !cssPropertySet.has(name)) return;
    setDeclValue(s, name, v, pr);
  },
  removeProperty(property) {
    const s = csSlot(this);
    required(arguments, 1, 'removeProperty');
    const p = toDOMString(property);
    const name = p.startsWith('--') ? p : asciiLowercase(p);
    if (s.computedFor !== undefined) throw domError('NoModificationAllowedError', 'read-only');
    const old = getDeclValue(s, name);
    setDeclValue(s, name, '', '');
    return old;
  }
});
attributes(CSSStyleDeclaration.prototype, {
  cssText: {
    get() { const s = csSlot(this); if (s.computedFor !== undefined) return ''; return serializeDeclarations(declList(s)); },
    set(v) {
      const s = csSlot(this);
      if (s.computedFor !== undefined) throw domError('NoModificationAllowedError', 'read-only');
      const text = toDOMString(v);
      const list = parseDeclarations(text);
      s.cache = list; s.cacheText = null;
      setAttributeValue(s.element, 'style', text.trim() === '' ? '' : serializeDeclarations(list));
    }
  },
  length: { get() { return styleNames(csSlot(this)).length; } },
  parentRule: { get() { csSlot(this); return null; } },
  cssFloat: { get() { return getDeclValue(csSlot(this), 'float'); }, set(v) { setDeclValue(csSlot(this), 'float', toDOMString(v), ''); } }
});
defineProperty(CSSStyleDeclaration.prototype, symIterator, { value: Array.prototype.values, writable: true, enumerable: false, configurable: true });
styleOf = function (el) {
  const s = slotOf(el);
  if (!s.styleDecl) s.styleDecl = makeStyleDecl(el, undefined);
  return s.styleDecl;
};
function computedStyleOf(elt, pseudo) {
  if (!isObject(elt) || !slotOf(elt) || slotOf(elt).nodeType !== ELEMENT_NODE) throw new TypeError("Failed to execute 'getComputedStyle' on 'Window': parameter 1 is not of type 'Element'.");
  const decl = makeStyleDecl(elt, elt);
  return decl;
}
operations(HTMLElement.prototype, {});
// SVG and MathML elements carry `style` too.
attributes(Element.prototype, {
  style: { get() { return styleOf(this); }, set(v) { this.style.cssText = v; } }
});

// --- DOMRect

function DOMRectReadOnly(x = 0, y = 0, width = 0, height = 0) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DOMRectReadOnly': Please use the 'new' operator");
  setSlot(this, { isRect: true, x: +x, y: +y, width: +width, height: +height, readonly: true });
}
iface('DOMRectReadOnly', DOMRectReadOnly, null);
function rectSlot(o) { const s = slotOf(o); if (!s || !s.isRect) illegal(); return s; }
function rectAttrs(writable) {
  const a = {};
  for (const k of ['x', 'y', 'width', 'height']) a[k] = { get() { return rectSlot(this)[k]; }, set: writable ? function (v) { rectSlot(this)[k] = +v; } : undefined };
  a.top = { get() { const s = rectSlot(this); return Math.min(s.y, s.y + s.height); } };
  a.right = { get() { const s = rectSlot(this); return Math.max(s.x, s.x + s.width); } };
  a.bottom = { get() { const s = rectSlot(this); return Math.max(s.y, s.y + s.height); } };
  a.left = { get() { const s = rectSlot(this); return Math.min(s.x, s.x + s.width); } };
  return a;
}
attributes(DOMRectReadOnly.prototype, rectAttrs(false));
operations(DOMRectReadOnly.prototype, {
  toJSON() { const s = rectSlot(this); return { x: s.x, y: s.y, width: s.width, height: s.height, top: this.top, right: this.right, bottom: this.bottom, left: this.left }; }
});
operations(DOMRectReadOnly, { fromRect(other = {}) { return new DOMRectReadOnly(other.x, other.y, other.width, other.height); } });
function DOMRect(x = 0, y = 0, width = 0, height = 0) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DOMRect': Please use the 'new' operator");
  setSlot(this, { isRect: true, x: +x, y: +y, width: +width, height: +height });
}
iface('DOMRect', DOMRect, DOMRectReadOnly);
attributes(DOMRect.prototype, rectAttrs(true));
operations(DOMRect, { fromRect(other = {}) { return new DOMRect(other.x, other.y, other.width, other.height); } });
function makeDOMRect(x, y, w, h) { return new DOMRect(x, y, w, h); }

function DOMPointReadOnly(x = 0, y = 0, z = 0, w = 1) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DOMPointReadOnly': Please use the 'new' operator");
  setSlot(this, { isPoint: true, x: +x, y: +y, z: +z, w: +w });
}
iface('DOMPointReadOnly', DOMPointReadOnly, null);
function pointSlot(o) { const s = slotOf(o); if (!s || !s.isPoint) illegal(); return s; }
const pointAttrs = writable => { const a = {}; for (const k of ['x', 'y', 'z', 'w']) a[k] = { get() { return pointSlot(this)[k]; }, set: writable ? function (v) { pointSlot(this)[k] = +v; } : undefined }; return a; };
attributes(DOMPointReadOnly.prototype, pointAttrs(false));
operations(DOMPointReadOnly, { fromPoint(p = {}) { return new DOMPointReadOnly(p.x, p.y, p.z, p.w === undefined ? 1 : p.w); } });
function DOMPoint(x = 0, y = 0, z = 0, w = 1) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DOMPoint': Please use the 'new' operator");
  setSlot(this, { isPoint: true, x: +x, y: +y, z: +z, w: +w });
}
iface('DOMPoint', DOMPoint, DOMPointReadOnly);
attributes(DOMPoint.prototype, pointAttrs(true));

// --- element geometry (from the page's layout; zeros when there is none)

function boxOf(el, what) { return N.geom(idOf(el), what); }
const geometryAttrs = {
  clientWidth: { get() { elSlot(this); const g = boxOf(this, 2); if (g === null) return 0; if (this === documentElementOf(slotOf(this).doc)) return Math.round(N.geom(N.root(), 4)[0]); return Math.round(g[2]); } },
  clientHeight: { get() { elSlot(this); const g = boxOf(this, 2); if (g === null) return 0; if (this === documentElementOf(slotOf(this).doc)) return Math.round(N.geom(N.root(), 4)[1]); return Math.round(g[3]); } },
  clientLeft: { get() { elSlot(this); const g = boxOf(this, 2); return g === null ? 0 : Math.round(g[0]); } },
  clientTop: { get() { elSlot(this); const g = boxOf(this, 2); return g === null ? 0 : Math.round(g[1]); } },
  scrollWidth: { get() { elSlot(this); const g = boxOf(this, 3); return g === null ? 0 : Math.round(g[0]); } },
  scrollHeight: { get() { elSlot(this); const g = boxOf(this, 3); return g === null ? 0 : Math.round(g[1]); } },
  scrollTop: { get() { elSlot(this); return slotOf(this).scrollTop || 0; }, set(v) { elSlot(this); slotOf(this).scrollTop = Math.max(0, +v || 0); } },
  scrollLeft: { get() { elSlot(this); return slotOf(this).scrollLeft || 0; }, set(v) { elSlot(this); slotOf(this).scrollLeft = Math.max(0, +v || 0); } }
};
attributes(Element.prototype, geometryAttrs);
operations(Element.prototype, {
  getBoundingClientRect() {
    elSlot(this);
    const g = boxOf(this, 0);
    return g === null ? new DOMRect(0, 0, 0, 0) : new DOMRect(g[0], g[1], g[2], g[3]);
  },
  getClientRects() {
    elSlot(this);
    const g = boxOf(this, 0);
    return g === null ? [] : [new DOMRect(g[0], g[1], g[2], g[3])];
  },
  scrollIntoView() {}, scrollTo() {}, scrollBy() {}, scroll() {},
  checkVisibility() { elSlot(this); return boxOf(this, 0) !== null; }
});
attributes(HTMLElement.prototype, {
  offsetParent: { get() { elSlot(this); const g = boxOf(this, 1); if (g === null || g[4] < 0) return null; return wrap(g[4]); } },
  offsetTop: { get() { elSlot(this); const g = boxOf(this, 1); return g === null ? 0 : Math.round(g[1]); } },
  offsetLeft: { get() { elSlot(this); const g = boxOf(this, 1); return g === null ? 0 : Math.round(g[0]); } },
  offsetWidth: { get() { elSlot(this); const g = boxOf(this, 1); return g === null ? 0 : Math.round(g[2]); } },
  offsetHeight: { get() { elSlot(this); const g = boxOf(this, 1); return g === null ? 0 : Math.round(g[3]); } }
});
for (const [name, index] of [['innerWidth', 0], ['innerHeight', 1], ['outerWidth', 0], ['outerHeight', 1]]) {
  defineProperty(global, name, { get() { const g = N.geom(N.root(), 4); return g === null ? (index === 0 ? 800 : 600) : g[index]; }, set(v) { defineProperty(global, name, { value: v, writable: true, enumerable: true, configurable: true }); }, enumerable: true, configurable: true });
}
for (const [name, index] of [['scrollX', 2], ['scrollY', 3], ['pageXOffset', 2], ['pageYOffset', 3]]) {
  defineProperty(global, name, { get() { const g = N.geom(N.root(), 4); return g === null ? 0 : g[index]; }, set(v) {}, enumerable: true, configurable: true });
}
