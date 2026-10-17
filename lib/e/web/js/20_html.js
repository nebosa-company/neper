// HTML elements: HTMLElement and the interfaces for each tag, with content-attribute reflection and the common behaviours.

// --- reflection helpers (HTML Standard 2.6.1)

function reflectString(proto, idl, content) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() { elSlot(this); const v = getAttributeValue(this, c); return v === null ? '' : v; },
    set(v) { elSlot(this); setAttributeValue(this, c, toDOMString(v)); }
  } });
}
function reflectNullableString(proto, idl, content) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() { elSlot(this); return getAttributeValue(this, c); },
    set(v) { elSlot(this); if (v === null) removeAttributeByName(this, c); else setAttributeValue(this, c, toDOMString(v)); }
  } });
}
function reflectBool(proto, idl, content) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() { elSlot(this); return getAttributeValue(this, c) !== null; },
    set(v) { elSlot(this); if (v) setAttributeValue(this, c, ''); else removeAttributeByName(this, c); }
  } });
}
function parseNonNegativeInteger(v) {
  if (v === null) return null;
  const m = /^[\t\n\f\r ]*([+-]?[0-9]+)/.exec(v);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  if (n < 0 || n !== n) return null;
  return n;
}
function parseInteger(v) {
  if (v === null) return null;
  const m = /^[\t\n\f\r ]*([+-]?[0-9]+)/.exec(v);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return n !== n ? null : n;
}
function reflectLong(proto, idl, content, def) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() { elSlot(this); const n = parseInteger(getAttributeValue(this, c)); return n === null || n > 2147483647 || n < -2147483648 ? (def === undefined ? 0 : def) : n; },
    set(v) { elSlot(this); setAttributeValue(this, c, String(toLong(v))); }
  } });
}
function reflectUnsignedLong(proto, idl, content, def, limited) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() {
      elSlot(this);
      const n = parseNonNegativeInteger(getAttributeValue(this, c));
      if (n === null || n > 2147483647 || (limited && n === 0)) return def === undefined ? 0 : def;
      return n;
    },
    set(v) {
      elSlot(this);
      const n = toUnsignedLong(v);
      if (limited && n === 0) throw domError('IndexSizeError', 'The value provided is 0, which is an invalid size');
      setAttributeValue(this, c, String(n > 2147483647 ? (def === undefined ? 0 : def) : n));
    }
  } });
}
function reflectDouble(proto, idl, content, def) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() { elSlot(this); const v = getAttributeValue(this, c); const n = v === null ? NaN : parseFloat(v); return n === n ? n : (def === undefined ? 0 : def); },
    set(v) { elSlot(this); setAttributeValue(this, c, String(toDouble(v))); }
  } });
}
function reflectEnum(proto, idl, content, values, missing, invalid, nullable) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() {
      elSlot(this);
      const v = getAttributeValue(this, c);
      if (v === null) return missing;
      const l = asciiLowercase(v);
      if (values.indexOf(l) >= 0) return l;
      return invalid === undefined ? (missing) : invalid;
    },
    set(v) { elSlot(this); setAttributeValue(this, c, toDOMString(v)); }
  } });
}
function reflectURL(proto, idl, content) {
  const c = content || asciiLowercase(idl);
  attributes(proto, { [idl]: {
    get() {
      elSlot(this);
      const v = getAttributeValue(this, c);
      if (v === null) return '';
      const abs = parseURLAgainst(v, documentBaseURL(slotOf(this).doc));
      return abs === null ? v : abs.href;
    },
    set(v) { elSlot(this); setAttributeValue(this, c, toUSVString(v)); }
  } });
}
function removeAttributeByName(el, name) { const a = getAttributeByName(el, name); if (a !== null) removeAttribute(a); }
let parseURLAgainst = (input, base) => null;

// --- HTMLElement

function HTMLElement() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'HTMLElement': Please use the 'new' operator");
  return constructCustomElement(new.target, HTMLElement);
}
iface('HTMLElement', HTMLElement, Element);
let constructCustomElement = (newTarget, base) => { throw new TypeError('Illegal constructor'); };

reflectString(HTMLElement.prototype, 'title');
reflectString(HTMLElement.prototype, 'lang');
reflectString(HTMLElement.prototype, 'accessKey', 'accesskey');
reflectBool(HTMLElement.prototype, 'hidden');
reflectBool(HTMLElement.prototype, 'inert');
reflectString(HTMLElement.prototype, 'nonce');
reflectBool(HTMLElement.prototype, 'autofocus');
reflectEnum(HTMLElement.prototype, 'dir', 'dir', ['ltr', 'rtl', 'auto'], '', '');
reflectEnum(HTMLElement.prototype, 'autocapitalize', 'autocapitalize', ['none', 'off', 'on', 'sentences', 'words', 'characters'], '', '');
attributes(HTMLElement.prototype, {
  draggable: {
    get() { const v = getAttributeValue(this, 'draggable'); return v === 'true' ? true : v === 'false' ? false : (this instanceof HTMLImageElement || (this instanceof HTMLAnchorElement && getAttributeValue(this, 'href') !== null)); },
    set(v) { setAttributeValue(this, 'draggable', v ? 'true' : 'false'); }
  },
  spellcheck: {
    get() { const v = getAttributeValue(this, 'spellcheck'); return v === 'false' ? false : true; },
    set(v) { setAttributeValue(this, 'spellcheck', v ? 'true' : 'false'); }
  },
  translate: {
    get() { const v = getAttributeValue(this, 'translate'); return v === 'no' ? false : true; },
    set(v) { setAttributeValue(this, 'translate', v ? 'yes' : 'no'); }
  },
  contentEditable: {
    get() { const v = getAttributeValue(this, 'contenteditable'); if (v === null) return 'inherit'; const l = asciiLowercase(v); return l === '' || l === 'true' ? 'true' : l === 'false' ? 'false' : l === 'plaintext-only' ? 'plaintext-only' : 'inherit'; },
    set(v) {
      const s = asciiLowercase(toDOMString(v));
      if (s === 'inherit') removeAttributeByName(this, 'contenteditable');
      else if (s === 'true' || s === 'false' || s === 'plaintext-only') setAttributeValue(this, 'contenteditable', s);
      else throw domError('SyntaxError', 'The value provided is not one of true, false, plaintext-only or inherit');
    }
  },
  isContentEditable: { get() { for (const e of inclusiveAncestors(this)) { if (nodeType(e) !== ELEMENT_NODE) continue; const v = getAttributeValue(e, 'contenteditable'); if (v !== null) { const l = asciiLowercase(v); if (l === '' || l === 'true' || l === 'plaintext-only') return true; if (l === 'false') return false; } } return false; } },
  tabIndex: {
    get() { const n = parseInteger(getAttributeValue(this, 'tabindex')); if (n !== null) return n; return defaultTabIndex(this); },
    set(v) { setAttributeValue(this, 'tabindex', String(toLong(v))); }
  },
  innerText: {
    get() { return renderedText(this); },
    set(v) {
      const text = v === null ? '' : toDOMString(v);
      const frag = createFragmentNode(slotOf(this).doc);
      let start = 0;
      for (let i = 0; i <= text.length; i++) {
        if (i === text.length || text[i] === '\n' || text[i] === '\r') {
          if (i > start) preInsert(createTextNode(slotOf(this).doc, text.slice(start, i)), frag, null);
          if (i < text.length) {
            preInsert(createElementInternal(slotOf(this).doc, 'br', HTML_NS, null, null, false), frag, null);
            if (text[i] === '\r' && text[i + 1] === '\n') i++;
          }
          start = i + 1;
        }
      }
      replaceAllWith(this, frag);
    }
  },
  outerText: {
    get() { return renderedText(this); },
    set(v) { const p = parentNode(this); if (p === null) throw domError('NoModificationAllowedError', 'The element has no parent'); const prev = previousSibling(this), next = nextSibling(this); const text = v === null ? '' : toDOMString(v); replaceChild(createTextNode(slotOf(this).doc, text), this, p); }
  },
  dataset: { get() { return datasetOf(this); } },
  style: { get() { return styleOf(this); }, set(v) { this.style.cssText = v; } },
  offsetParent: { get() { return null; } },
  offsetTop: { get() { return 0; } },
  offsetLeft: { get() { return 0; } },
  offsetWidth: { get() { return 0; } },
  offsetHeight: { get() { return 0; } }
});
operations(HTMLElement.prototype, {
  click() {
    elSlot(this);
    if (isDisabledFormControl(this)) return;
    const ev = new MouseEvent('click', { bubbles: true, cancelable: true, composed: true, view: global });
    const s = slotOf(ev);
    s.isTrusted = false;
    s.isMouseClick = true;
    dispatch(ev, this);
  },
  focus(options = undefined) { elSlot(this); focusElement(this); },
  blur() { elSlot(this); blurElement(this); },
  attachInternals() { throw domError('NotSupportedError', 'attachInternals is not supported'); }
});
defineHandlerAttrs(HTMLElement.prototype, eventHandlerNames);
let defaultTabIndex = el => -1;
let renderedText = el => textContentOf(el);
let datasetOf = el => null;
let styleOf = el => null;
let isDisabledFormControl = el => false;
let focusElement = el => {};
let blurElement = el => {};

// --- the interface table: tag name -> interface name

function HTMLUnknownElement() { throw new TypeError('Illegal constructor'); }
iface('HTMLUnknownElement', HTMLUnknownElement, HTMLElement);

const htmlInterfaces = {};   // interface name -> constructor
const htmlTagInterface = {}; // tag name -> interface name
function defineHTMLInterface(name, tags, setup) {
  const ctor = { [name]: function () {
    if (new.target === undefined) throw new TypeError("Failed to construct '" + name + "': Please use the 'new' operator");
    return constructCustomElement(new.target, ctor);
  } }[name];
  iface(name, ctor, HTMLElement);
  htmlInterfaces[name] = ctor;
  for (const t of tags) htmlTagInterface[t] = name;
  if (setup) setup(ctor.prototype, ctor);
  return ctor;
}
const simple = [
  ['HTMLHtmlElement', ['html']], ['HTMLHeadElement', ['head']], ['HTMLTitleElement', ['title']], ['HTMLBodyElement', ['body']],
  ['HTMLHeadingElement', ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']], ['HTMLParagraphElement', ['p']], ['HTMLDivElement', ['div']],
  ['HTMLSpanElement', ['span']], ['HTMLBRElement', ['br']], ['HTMLHRElement', ['hr']], ['HTMLPreElement', ['pre', 'listing', 'xmp']],
  ['HTMLQuoteElement', ['blockquote', 'q']], ['HTMLUListElement', ['ul']], ['HTMLOListElement', ['ol']], ['HTMLLIElement', ['li']],
  ['HTMLDListElement', ['dl']], ['HTMLModElement', ['ins', 'del']], ['HTMLPictureElement', ['picture']], ['HTMLAreaElement', ['area']],
  ['HTMLTableCaptionElement', ['caption']], ['HTMLTableColElement', ['col', 'colgroup']], ['HTMLTableSectionElement', ['thead', 'tbody', 'tfoot']],
  ['HTMLTableRowElement', ['tr']], ['HTMLTableCellElement', ['td', 'th']], ['HTMLFieldSetElement', ['fieldset']], ['HTMLLegendElement', ['legend']],
  ['HTMLLabelElement', ['label']], ['HTMLOptGroupElement', ['optgroup']], ['HTMLDataElement', ['data']], ['HTMLTimeElement', ['time']],
  ['HTMLMenuElement', ['menu']], ['HTMLDetailsElement', ['details']], ['HTMLDialogElement', ['dialog']], ['HTMLSlotElement', ['slot']],
  ['HTMLMapElement', ['map']], ['HTMLMeterElement', ['meter']], ['HTMLProgressElement', ['progress']], ['HTMLOutputElement', ['output']],
  ['HTMLDataListElement', ['datalist']], ['HTMLSourceElement', ['source']], ['HTMLTrackElement', ['track']], ['HTMLEmbedElement', ['embed']],
  ['HTMLObjectElement', ['object']], ['HTMLParamElement', ['param']], ['HTMLMediaElement', []], ['HTMLVideoElement', ['video']],
  ['HTMLAudioElement', ['audio']], ['HTMLCanvasElement', ['canvas']], ['HTMLIFrameElement', ['iframe']], ['HTMLFrameSetElement', ['frameset']],
  ['HTMLFrameElement', ['frame']], ['HTMLDirectoryElement', ['dir']], ['HTMLFontElement', ['font']], ['HTMLMarqueeElement', ['marquee']],
  ['HTMLBaseElement', ['base']], ['HTMLMetaElement', ['meta']], ['HTMLStyleElement', ['style']], ['HTMLLinkElement', ['link']],
  ['HTMLScriptElement', ['script']], ['HTMLTemplateElement', ['template']], ['HTMLImageElement', ['img']], ['HTMLAnchorElement', ['a']],
  ['HTMLFormElement', ['form']], ['HTMLInputElement', ['input']], ['HTMLButtonElement', ['button']], ['HTMLSelectElement', ['select']],
  ['HTMLOptionElement', ['option']], ['HTMLTextAreaElement', ['textarea']], ['HTMLTableElement', ['table']], ['HTMLTableSectionElement', ['thead', 'tbody', 'tfoot']]
];
for (const [name, tags] of simple) if (!htmlInterfaces[name]) defineHTMLInterface(name, tags);
// Rebind the tags of interfaces that were defined twice in the table above.
for (const t of ['thead', 'tbody', 'tfoot']) htmlTagInterface[t] = 'HTMLTableSectionElement';
setPrototypeOf(htmlInterfaces.HTMLAudioElement, htmlInterfaces.HTMLMediaElement);
setPrototypeOf(htmlInterfaces.HTMLAudioElement.prototype, htmlInterfaces.HTMLMediaElement.prototype);
setPrototypeOf(htmlInterfaces.HTMLVideoElement, htmlInterfaces.HTMLMediaElement);
setPrototypeOf(htmlInterfaces.HTMLVideoElement.prototype, htmlInterfaces.HTMLMediaElement.prototype);
for (const t of ['article', 'section', 'nav', 'aside', 'header', 'footer', 'main', 'address', 'figure', 'figcaption', 'hgroup']) htmlTagInterface[t] = 'HTMLElement';

const HTMLHtmlElement = htmlInterfaces.HTMLHtmlElement, HTMLHeadElement = htmlInterfaces.HTMLHeadElement,
  HTMLBodyElement = htmlInterfaces.HTMLBodyElement, HTMLTitleElement = htmlInterfaces.HTMLTitleElement,
  HTMLAnchorElement = htmlInterfaces.HTMLAnchorElement, HTMLImageElement = htmlInterfaces.HTMLImageElement,
  HTMLScriptElement = htmlInterfaces.HTMLScriptElement, HTMLTemplateElement = htmlInterfaces.HTMLTemplateElement,
  HTMLFormElement = htmlInterfaces.HTMLFormElement, HTMLInputElement = htmlInterfaces.HTMLInputElement,
  HTMLStyleElement = htmlInterfaces.HTMLStyleElement, HTMLLinkElement = htmlInterfaces.HTMLLinkElement,
  HTMLButtonElement = htmlInterfaces.HTMLButtonElement, HTMLSelectElement = htmlInterfaces.HTMLSelectElement,
  HTMLOptionElement = htmlInterfaces.HTMLOptionElement, HTMLTextAreaElement = htmlInterfaces.HTMLTextAreaElement,
  HTMLIFrameElement = htmlInterfaces.HTMLIFrameElement, HTMLBaseElement = htmlInterfaces.HTMLBaseElement,
  HTMLMetaElement = htmlInterfaces.HTMLMetaElement, HTMLCanvasElement = htmlInterfaces.HTMLCanvasElement,
  HTMLTableElement = htmlInterfaces.HTMLTableElement, HTMLLabelElement = htmlInterfaces.HTMLLabelElement;

// Interface selection for new elements.
interfaceFor = function (localName, ns) {
  if (ns === HTML_NS) {
    const name = htmlTagInterface[localName];
    if (name !== undefined && hasOwn.call(htmlTagInterface, localName)) return htmlInterfaces[name] ? htmlInterfaces[name].prototype : HTMLElement.prototype;
    return isValidCustomElementName(localName) ? HTMLElement.prototype : HTMLUnknownElement.prototype;
  }
  if (ns === SVG_NS) return svgInterfaceFor(localName);
  if (ns === MATHML_NS) return MathMLElement.prototype;
  return Element.prototype;
};
let svgInterfaceFor = localName => Element.prototype;
function isValidCustomElementName(name) {
  if (!/^[a-z][-.0-9_a-z·À-ÖØ-öø-ͽͿ-῿‌-‍‿-⁀⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�]*-[-.0-9_a-z·À-ÖØ-öø-ͽͿ-῿‌-‍‿-⁀⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�]*$/.test(name)) return false;
  return ['annotation-xml', 'color-profile', 'font-face', 'font-face-src', 'font-face-uri', 'font-face-format', 'font-face-name', 'missing-glyph'].indexOf(name) < 0;
}

function MathMLElement() { throw new TypeError('Illegal constructor'); }
iface('MathMLElement', MathMLElement, Element);
defineHandlerAttrs(MathMLElement.prototype, eventHandlerNames);

// --- per-interface reflected attributes
const P = n => htmlInterfaces[n].prototype;
reflectString(P('HTMLHtmlElement'), 'version');
reflectString(P('HTMLBodyElement'), 'text'); reflectString(P('HTMLBodyElement'), 'link'); reflectString(P('HTMLBodyElement'), 'vLink', 'vlink');
reflectString(P('HTMLBodyElement'), 'aLink', 'alink'); reflectString(P('HTMLBodyElement'), 'bgColor', 'bgcolor'); reflectString(P('HTMLBodyElement'), 'background');
reflectString(P('HTMLHeadingElement'), 'align'); reflectString(P('HTMLParagraphElement'), 'align'); reflectString(P('HTMLDivElement'), 'align');
reflectString(P('HTMLBRElement'), 'clear');
reflectString(P('HTMLHRElement'), 'align'); reflectString(P('HTMLHRElement'), 'color'); reflectBool(P('HTMLHRElement'), 'noShade', 'noshade');
reflectString(P('HTMLHRElement'), 'size'); reflectString(P('HTMLHRElement'), 'width');
reflectLong(P('HTMLPreElement'), 'width');
reflectURL(P('HTMLQuoteElement'), 'cite');
reflectBool(P('HTMLUListElement'), 'compact'); reflectString(P('HTMLUListElement'), 'type');
reflectBool(P('HTMLOListElement'), 'reversed'); reflectBool(P('HTMLOListElement'), 'compact'); reflectString(P('HTMLOListElement'), 'type'); reflectLong(P('HTMLOListElement'), 'start', 'start', 1);
reflectLong(P('HTMLLIElement'), 'value'); reflectString(P('HTMLLIElement'), 'type');
reflectBool(P('HTMLDListElement'), 'compact');
reflectURL(P('HTMLModElement'), 'cite'); reflectString(P('HTMLModElement'), 'dateTime', 'datetime');
reflectString(P('HTMLDataElement'), 'value'); reflectString(P('HTMLTimeElement'), 'dateTime', 'datetime');
reflectBool(P('HTMLDetailsElement'), 'open'); reflectBool(P('HTMLDialogElement'), 'open');
reflectString(P('HTMLFontElement'), 'color'); reflectString(P('HTMLFontElement'), 'face'); reflectString(P('HTMLFontElement'), 'size');
reflectString(P('HTMLMetaElement'), 'name'); reflectString(P('HTMLMetaElement'), 'content'); reflectString(P('HTMLMetaElement'), 'httpEquiv', 'http-equiv');
reflectString(P('HTMLMetaElement'), 'media'); reflectString(P('HTMLMetaElement'), 'scheme');
reflectURL(P('HTMLBaseElement'), 'href'); reflectString(P('HTMLBaseElement'), 'target');
reflectString(P('HTMLLinkElement'), 'rel'); reflectString(P('HTMLLinkElement'), 'media'); reflectString(P('HTMLLinkElement'), 'hreflang'); reflectString(P('HTMLLinkElement'), 'type');
reflectString(P('HTMLLinkElement'), 'as'); reflectString(P('HTMLLinkElement'), 'charset'); reflectString(P('HTMLLinkElement'), 'rev'); reflectString(P('HTMLLinkElement'), 'target');
reflectNullableString(P('HTMLLinkElement'), 'crossOrigin', 'crossorigin'); reflectURL(P('HTMLLinkElement'), 'href'); reflectBool(P('HTMLLinkElement'), 'disabled');
reflectString(P('HTMLLinkElement'), 'integrity'); reflectString(P('HTMLLinkElement'), 'imageSrcset', 'imagesrcset'); reflectString(P('HTMLLinkElement'), 'imageSizes', 'imagesizes');
reflectString(P('HTMLLinkElement'), 'referrerPolicy', 'referrerpolicy');
reflectString(P('HTMLStyleElement'), 'media'); reflectString(P('HTMLStyleElement'), 'type'); reflectBool(P('HTMLStyleElement'), 'disabled');
reflectURL(P('HTMLScriptElement'), 'src'); reflectString(P('HTMLScriptElement'), 'type'); reflectString(P('HTMLScriptElement'), 'charset');
reflectBool(P('HTMLScriptElement'), 'defer'); reflectNullableString(P('HTMLScriptElement'), 'crossOrigin', 'crossorigin'); reflectBool(P('HTMLScriptElement'), 'noModule', 'nomodule');
reflectString(P('HTMLScriptElement'), 'integrity'); reflectString(P('HTMLScriptElement'), 'event'); reflectString(P('HTMLScriptElement'), 'htmlFor', 'for');
reflectString(P('HTMLScriptElement'), 'referrerPolicy', 'referrerpolicy');
reflectURL(P('HTMLAnchorElement'), 'href'); reflectString(P('HTMLAnchorElement'), 'target'); reflectString(P('HTMLAnchorElement'), 'download'); reflectString(P('HTMLAnchorElement'), 'ping');
reflectString(P('HTMLAnchorElement'), 'rel'); reflectString(P('HTMLAnchorElement'), 'hreflang'); reflectString(P('HTMLAnchorElement'), 'type'); reflectString(P('HTMLAnchorElement'), 'referrerPolicy', 'referrerpolicy');
reflectString(P('HTMLAnchorElement'), 'charset'); reflectString(P('HTMLAnchorElement'), 'coords'); reflectString(P('HTMLAnchorElement'), 'name'); reflectString(P('HTMLAnchorElement'), 'rev'); reflectString(P('HTMLAnchorElement'), 'shape');
reflectString(P('HTMLImageElement'), 'alt'); reflectURL(P('HTMLImageElement'), 'src'); reflectString(P('HTMLImageElement'), 'srcset'); reflectString(P('HTMLImageElement'), 'sizes');
reflectNullableString(P('HTMLImageElement'), 'crossOrigin', 'crossorigin'); reflectString(P('HTMLImageElement'), 'useMap', 'usemap'); reflectBool(P('HTMLImageElement'), 'isMap', 'ismap');
reflectUnsignedLong(P('HTMLImageElement'), 'width'); reflectUnsignedLong(P('HTMLImageElement'), 'height'); reflectString(P('HTMLImageElement'), 'name');
reflectString(P('HTMLImageElement'), 'align'); reflectUnsignedLong(P('HTMLImageElement'), 'hspace'); reflectUnsignedLong(P('HTMLImageElement'), 'vspace'); reflectURL(P('HTMLImageElement'), 'longDesc', 'longdesc');
reflectString(P('HTMLImageElement'), 'border'); reflectString(P('HTMLImageElement'), 'referrerPolicy', 'referrerpolicy');
reflectEnum(P('HTMLImageElement'), 'decoding', 'decoding', ['sync', 'async', 'auto'], 'auto', 'auto');
reflectEnum(P('HTMLImageElement'), 'loading', 'loading', ['lazy', 'eager'], 'eager', 'eager');
reflectUnsignedLong(P('HTMLCanvasElement') || P('HTMLCanvasElement'), 'width', 'width', 300); reflectUnsignedLong(P('HTMLCanvasElement'), 'height', 'height', 150);
reflectString(P('HTMLIFrameElement'), 'name'); reflectURL(P('HTMLIFrameElement'), 'src'); reflectString(P('HTMLIFrameElement'), 'srcdoc'); reflectString(P('HTMLIFrameElement'), 'width');
reflectString(P('HTMLIFrameElement'), 'height'); reflectString(P('HTMLIFrameElement'), 'allow'); reflectBool(P('HTMLIFrameElement'), 'allowFullscreen', 'allowfullscreen');
reflectString(P('HTMLIFrameElement'), 'align'); reflectString(P('HTMLIFrameElement'), 'scrolling'); reflectString(P('HTMLIFrameElement'), 'frameBorder', 'frameborder');
reflectString(P('HTMLIFrameElement'), 'marginHeight', 'marginheight'); reflectString(P('HTMLIFrameElement'), 'marginWidth', 'marginwidth'); reflectString(P('HTMLIFrameElement'), 'referrerPolicy', 'referrerpolicy');
reflectEnum(P('HTMLIFrameElement'), 'loading', 'loading', ['lazy', 'eager'], 'eager', 'eager');
reflectString(P('HTMLFormElement'), 'acceptCharset', 'accept-charset'); reflectURL(P('HTMLFormElement'), 'action'); reflectString(P('HTMLFormElement'), 'name');
reflectString(P('HTMLFormElement'), 'target'); reflectString(P('HTMLFormElement'), 'rel'); reflectBool(P('HTMLFormElement'), 'noValidate', 'novalidate');
reflectEnum(P('HTMLFormElement'), 'autocomplete', 'autocomplete', ['on', 'off'], 'on', 'on');
reflectEnum(P('HTMLFormElement'), 'method', 'method', ['get', 'post', 'dialog'], 'get', 'get');
reflectEnum(P('HTMLFormElement'), 'enctype', 'enctype', ['application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain'], 'application/x-www-form-urlencoded', 'application/x-www-form-urlencoded');
reflectString(P('HTMLLabelElement'), 'htmlFor', 'for');
reflectBool(P('HTMLInputElement'), 'disabled'); reflectString(P('HTMLInputElement'), 'name'); reflectString(P('HTMLInputElement'), 'accept'); reflectString(P('HTMLInputElement'), 'alt');
reflectString(P('HTMLInputElement'), 'autocomplete'); reflectBool(P('HTMLInputElement'), 'defaultChecked', 'checked'); reflectBool(P('HTMLInputElement'), 'multiple'); reflectBool(P('HTMLInputElement'), 'readOnly', 'readonly');
reflectBool(P('HTMLInputElement'), 'required'); reflectString(P('HTMLInputElement'), 'placeholder'); reflectString(P('HTMLInputElement'), 'pattern'); reflectString(P('HTMLInputElement'), 'min');
reflectString(P('HTMLInputElement'), 'max'); reflectString(P('HTMLInputElement'), 'step'); reflectURL(P('HTMLInputElement'), 'src'); reflectString(P('HTMLInputElement'), 'defaultValue', 'value');
reflectString(P('HTMLInputElement'), 'dirName', 'dirname'); reflectUnsignedLong(P('HTMLInputElement'), 'size', 'size', 20, true); reflectLong(P('HTMLInputElement'), 'maxLength', 'maxlength', -1);
reflectLong(P('HTMLInputElement'), 'minLength', 'minlength', -1); reflectString(P('HTMLInputElement'), 'align'); reflectString(P('HTMLInputElement'), 'useMap', 'usemap');
reflectUnsignedLong(P('HTMLInputElement'), 'width'); reflectUnsignedLong(P('HTMLInputElement'), 'height');
reflectBool(P('HTMLButtonElement'), 'disabled'); reflectString(P('HTMLButtonElement'), 'name'); reflectString(P('HTMLButtonElement'), 'value');
reflectBool(P('HTMLButtonElement'), 'formNoValidate', 'formnovalidate'); reflectString(P('HTMLButtonElement'), 'formTarget', 'formtarget'); reflectURL(P('HTMLButtonElement'), 'formAction', 'formaction');
reflectBool(P('HTMLSelectElement'), 'disabled'); reflectBool(P('HTMLSelectElement'), 'multiple'); reflectString(P('HTMLSelectElement'), 'name'); reflectBool(P('HTMLSelectElement'), 'required');
reflectString(P('HTMLSelectElement'), 'autocomplete'); reflectUnsignedLong(P('HTMLSelectElement'), 'size');
reflectBool(P('HTMLOptionElement'), 'disabled'); reflectBool(P('HTMLOptionElement'), 'defaultSelected', 'selected'); reflectString(P('HTMLOptionElement'), 'label');
reflectBool(P('HTMLTextAreaElement'), 'disabled'); reflectString(P('HTMLTextAreaElement'), 'name'); reflectString(P('HTMLTextAreaElement'), 'placeholder'); reflectBool(P('HTMLTextAreaElement'), 'readOnly', 'readonly');
reflectBool(P('HTMLTextAreaElement'), 'required'); reflectUnsignedLong(P('HTMLTextAreaElement'), 'rows', 'rows', 2, true); reflectUnsignedLong(P('HTMLTextAreaElement'), 'cols', 'cols', 20, true);
reflectString(P('HTMLTextAreaElement'), 'autocomplete'); reflectString(P('HTMLTextAreaElement'), 'dirName', 'dirname'); reflectLong(P('HTMLTextAreaElement'), 'maxLength', 'maxlength', -1); reflectLong(P('HTMLTextAreaElement'), 'minLength', 'minlength', -1);
reflectEnum(P('HTMLTextAreaElement'), 'wrap', 'wrap', ['soft', 'hard'], 'soft', 'soft');
reflectBool(P('HTMLFieldSetElement'), 'disabled'); reflectString(P('HTMLFieldSetElement'), 'name');
reflectString(P('HTMLTableElement'), 'align'); reflectString(P('HTMLTableElement'), 'border'); reflectString(P('HTMLTableElement'), 'frame'); reflectString(P('HTMLTableElement'), 'rules');
reflectString(P('HTMLTableElement'), 'summary'); reflectString(P('HTMLTableElement'), 'width'); reflectString(P('HTMLTableElement'), 'bgColor', 'bgcolor');
reflectString(P('HTMLTableElement'), 'cellPadding', 'cellpadding'); reflectString(P('HTMLTableElement'), 'cellSpacing', 'cellspacing');
reflectString(P('HTMLTableRowElement'), 'align'); reflectString(P('HTMLTableRowElement'), 'vAlign', 'valign'); reflectString(P('HTMLTableRowElement'), 'bgColor', 'bgcolor');
reflectString(P('HTMLTableSectionElement'), 'align'); reflectString(P('HTMLTableSectionElement'), 'vAlign', 'valign');
reflectUnsignedLong(P('HTMLTableCellElement'), 'colSpan', 'colspan', 1, true); reflectUnsignedLong(P('HTMLTableCellElement'), 'rowSpan', 'rowspan', 1); reflectString(P('HTMLTableCellElement'), 'headers');
reflectString(P('HTMLTableCellElement'), 'abbr'); reflectString(P('HTMLTableCellElement'), 'scope'); reflectString(P('HTMLTableCellElement'), 'align'); reflectString(P('HTMLTableCellElement'), 'vAlign', 'valign');
reflectString(P('HTMLTableCellElement'), 'bgColor', 'bgcolor'); reflectString(P('HTMLTableCellElement'), 'width'); reflectString(P('HTMLTableCellElement'), 'height');
reflectURL(P('HTMLSourceElement'), 'src'); reflectString(P('HTMLSourceElement'), 'type'); reflectString(P('HTMLSourceElement'), 'srcset'); reflectString(P('HTMLSourceElement'), 'sizes'); reflectString(P('HTMLSourceElement'), 'media');
reflectURL(P('HTMLMediaElement'), 'src'); reflectBool(P('HTMLMediaElement'), 'autoplay'); reflectBool(P('HTMLMediaElement'), 'loop'); reflectBool(P('HTMLMediaElement'), 'controls'); reflectBool(P('HTMLMediaElement'), 'defaultMuted', 'muted');
reflectString(P('HTMLEmbedElement'), 'src'); reflectString(P('HTMLEmbedElement'), 'type'); reflectString(P('HTMLEmbedElement'), 'width'); reflectString(P('HTMLEmbedElement'), 'height');
reflectString(P('HTMLObjectElement'), 'data'); reflectString(P('HTMLObjectElement'), 'type'); reflectString(P('HTMLObjectElement'), 'name'); reflectString(P('HTMLObjectElement'), 'width'); reflectString(P('HTMLObjectElement'), 'height');
reflectString(P('HTMLParamElement'), 'name'); reflectString(P('HTMLParamElement'), 'value');
reflectString(P('HTMLMapElement'), 'name'); reflectString(P('HTMLAreaElement'), 'alt'); reflectString(P('HTMLAreaElement'), 'coords'); reflectString(P('HTMLAreaElement'), 'shape'); reflectURL(P('HTMLAreaElement'), 'href');
reflectString(P('HTMLAreaElement'), 'target'); reflectString(P('HTMLAreaElement'), 'download'); reflectString(P('HTMLAreaElement'), 'rel');
reflectString(P('HTMLSlotElement'), 'name');
reflectString(P('HTMLTrackElement'), 'kind'); reflectURL(P('HTMLTrackElement'), 'src'); reflectString(P('HTMLTrackElement'), 'srclang'); reflectString(P('HTMLTrackElement'), 'label'); reflectBool(P('HTMLTrackElement'), 'default');
reflectDouble(P('HTMLMeterElement'), 'value'); reflectDouble(P('HTMLMeterElement'), 'min', 'min', 0); reflectDouble(P('HTMLMeterElement'), 'max', 'max', 1);
reflectDouble(P('HTMLProgressElement'), 'value'); reflectDouble(P('HTMLProgressElement'), 'max', 'max', 1);
reflectString(P('HTMLOutputElement'), 'name');

// Text-bearing elements.
attributes(P('HTMLTitleElement'), {
  text: { get() { return descendantTextContent(this); }, set(v) { replaceAllWith(this, v === '' ? null : createTextNode(slotOf(this).doc, toDOMString(v))); } }
});
attributes(P('HTMLScriptElement'), {
  text: { get() { return childTextContent(this); }, set(v) { replaceAllWith(this, createTextNode(slotOf(this).doc, toDOMString(v))); } },
  async: {
    get() { return getAttributeValue(this, 'async') !== null || slotOf(this).forceAsync === true; },
    set(v) { slotOf(this).forceAsync = false; if (v) setAttributeValue(this, 'async', ''); else removeAttributeByName(this, 'async'); }
  }
});
attributes(P('HTMLOptionElement'), { text: { get() { return stripAndCollapse(descendantTextContent(this)); }, set(v) { replaceAllWith(this, v === '' ? null : createTextNode(slotOf(this).doc, toDOMString(v))); } } });
attributes(P('HTMLAnchorElement'), { text: { get() { return descendantTextContent(this); }, set(v) { replaceAllWith(this, v === '' ? null : createTextNode(slotOf(this).doc, toDOMString(v))); } } });
function childTextContent(el) {
  let out = '';
  for (const c of childrenOf(el)) if (nodeType(c) === TEXT_NODE) out += N.value(idOf(c));
  return out;
}
function stripAndCollapse(s) {
  let out = '', prevSpace = true;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (isASCIIWhitespace(c)) { if (!prevSpace) out += ' '; prevSpace = true; } else { out += c; prevSpace = false; }
  }
  return out.endsWith(' ') ? out.slice(0, -1) : out;
}

// document-scoped name lookups used by HTMLDocument
operations(HTMLDocument.prototype, {});
