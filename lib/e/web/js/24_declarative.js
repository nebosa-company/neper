// Declarative shadow DOM: <template shadowrootmode> in parsed markup, setHTMLUnsafe, parseHTMLUnsafe and getHTML.

function attachDeclarativeShadow(tpl, host) {
  const mode = getAttributeValue(tpl, 'shadowrootmode');
  if (mode !== 'open' && mode !== 'closed') return false;
  const hs = slotOf(host);
  if (hs.shadowRoot || hs.namespaceURI !== HTML_NS || !(shadowHostNames.indexOf(hs.localName) >= 0 || isValidCustomElementName(hs.localName))) return false;
  const sr = attachShadowRoot(host, mode, getAttributeValue(tpl, 'shadowrootdelegatesfocus') !== null,
    getAttributeValue(tpl, 'shadowrootslotassignment') === 'manual' ? 'manual' : 'named',
    getAttributeValue(tpl, 'shadowrootclonable') !== null, getAttributeValue(tpl, 'shadowrootserializable') !== null);
  slotOf(sr).declarative = true;
  for (const c of childrenOf(tpl)) { removeNode(c, true); appendNodeSimple(sr, c); }
  removeNode(tpl, true);
  return sr;
}
function convertDeclarative(root) {
  for (const c of childrenOf(root)) {
    if (nodeType(c) !== ELEMENT_NODE) continue;
    const cs = slotOf(c);
    if (cs.localName === 'template' && cs.namespaceURI === HTML_NS && nodeType(root) === ELEMENT_NODE) {
      const sr = attachDeclarativeShadow(c, root);
      if (sr) { convertDeclarative(sr); continue; }
    }
    convertDeclarative(c);
  }
}
function parseUnsafe(context, markup) {
  const frag = parseFragment(context, markup);
  const holder = createElementInternal(slotOf(context).doc, slotOf(context).localName, slotOf(context).namespaceURI, null, null, false);
  for (const k of childrenOf(frag)) appendNodeSimple(holder, k);
  convertDeclarative(holder);
  for (const k of childrenOf(holder)) appendNodeSimple(frag, k);
  return frag;
}
operations(Element.prototype, {
  setHTMLUnsafe(html) {
    elSlot(this);
    required(arguments, 1, 'setHTMLUnsafe');
    const s = toDOMString(html);
    replaceAllWith(this, parseUnsafe(this, s));
  },
  getHTML(options = undefined) {
    elSlot(this);
    return serializeHTMLChildren(this, options || {});
  }
});
operations(ShadowRoot.prototype, {
  setHTMLUnsafe(html) {
    const s = srSlot(this);
    required(arguments, 1, 'setHTMLUnsafe');
    replaceAllWith(this, parseUnsafe(s.host, toDOMString(html)));
  },
  getHTML(options = undefined) { srSlot(this); return serializeHTMLChildren(this, options || {}); }
});
operations(Document, {
  parseHTMLUnsafe(html) {
    required(arguments, 1, 'parseHTMLUnsafe');
    const doc = newDocument(false);
    setPrototypeOf(doc, Document.prototype);
    slotOf(doc).url = slotOf(mainDocument).url;
    parseHTMLDocument(doc, toDOMString(html));
    convertDeclarative(doc);
    return doc;
  }
});

const htmlVoid = ['area', 'base', 'basefont', 'bgsound', 'br', 'col', 'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr'];
const htmlRawText = ['style', 'script', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext', 'noscript'];
function escapeHTMLText(s) { return s.replace(/&/g, '&amp;').replace(/ /g, '&nbsp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function escapeHTMLAttr(s) { return s.replace(/&/g, '&amp;').replace(/ /g, '&nbsp;').replace(/"/g, '&quot;'); }
function serializeHTMLChildren(node, opts) {
  let out = '';
  const ns = slotOf(node);
  const host = ns.nodeType === ELEMENT_NODE ? node : null;
  if (host && ns.shadowRoot && (opts.serializableShadowRoots && slotOf(ns.shadowRoot).serializable || (opts.shadowRoots || []).indexOf(ns.shadowRoot) >= 0)) {
    const sr = slotOf(ns.shadowRoot);
    out += '<template shadowrootmode="' + sr.mode + '"' + (sr.delegatesFocus ? ' shadowrootdelegatesfocus=""' : '') + (sr.clonable ? ' shadowrootclonable=""' : '') + (sr.serializable ? ' shadowrootserializable=""' : '') + (sr.slotAssignment === 'manual' ? ' shadowrootslotassignment="manual"' : '') + '>' + serializeHTMLChildren(ns.shadowRoot, opts) + '</template>';
  }
  const kids = ns.nodeType === ELEMENT_NODE && ns.localName === 'template' && ns.namespaceURI === HTML_NS ? childrenOf(templateContent(node)) : childrenOf(node);
  for (const c of kids) out += serializeHTMLNode(c, opts, node);
  return out;
}
function serializeHTMLNode(n, opts, parent) {
  const s = slotOf(n);
  switch (s.nodeType) {
    case ELEMENT_NODE: {
      const tag = s.namespaceURI === HTML_NS || s.namespaceURI === SVG_NS || s.namespaceURI === MATHML_NS ? s.localName : qualifiedName(n);
      let out = '<' + tag;
      for (const a of attrsOf(n)) {
        const as = slotOf(a);
        let name = as.localName;
        if (as.namespaceURI === XMLNS_NS) name = as.prefix === null ? 'xmlns' : 'xmlns:' + as.localName;
        else if (as.namespaceURI === XML_NS) name = 'xml:' + as.localName;
        else if (as.namespaceURI === XLINK_NS) name = 'xlink:' + as.localName;
        else if (as.prefix !== null) name = as.prefix + ':' + as.localName;
        out += ' ' + name + '="' + escapeHTMLAttr(as.value) + '"';
      }
      out += '>';
      if (s.namespaceURI === HTML_NS && htmlVoid.indexOf(s.localName) >= 0) return out;
      out += serializeHTMLChildren(n, opts);
      return out + '</' + tag + '>';
    }
    case TEXT_NODE: {
      const v = N.value(s.id);
      const ps = parent && slotOf(parent);
      if (ps && ps.nodeType === ELEMENT_NODE && ps.namespaceURI === HTML_NS && htmlRawText.indexOf(ps.localName) >= 0) return v;
      return escapeHTMLText(v);
    }
    case COMMENT_NODE: return '<!--' + N.value(s.id) + '-->';
    case PROCESSING_INSTRUCTION_NODE: return '<?' + s.target + ' ' + N.value(s.id) + '>';
    case DOCUMENT_TYPE_NODE: return '<!DOCTYPE ' + s.name + '>';
  }
  return '';
}
