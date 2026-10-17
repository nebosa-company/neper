// Document, XMLDocument, DOMImplementation and the document-level collections.

function Document() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Document': Please use the 'new' operator");
  const id = N.mkFragment();
  const s = setSlot(this, newNodeSlot(id, DOCUMENT_NODE, null));
  initDocumentSlot(s, false);
  register(this, id);
}
iface('Document', Document, Node);
function initDocumentSlot(s, html) {
  s.docType = html ? 'html' : 'xml';
  s.contentType = html ? 'text/html' : 'application/xml';
  s.url = 'about:blank';
  s.origin = 'null';
  s.mode = 'no-quirks';
  s.encoding = 'UTF-8';
  s.readyState = 'complete';
  s.implementation = null;
  s.cookie = '';
  s.currentScript = null;
  s.browsingContext = false;
  s.focused = null;
}
function docSlot(o) { const s = slotOf(o); if (!s || s.nodeType !== DOCUMENT_NODE) illegal(); return s; }
function XMLDocument() { throw new TypeError('Illegal constructor'); }
iface('XMLDocument', XMLDocument, Document);
function HTMLDocument() { throw new TypeError('Illegal constructor'); }
iface('HTMLDocument', HTMLDocument, Document);

// A new document owned by itself: an HTML document when `html`, else an XML document.
newDocument = function (xmlFlag) {
  const id = N.mkFragment();
  const w = create(xmlFlag === true ? XMLDocument.prototype : HTMLDocument.prototype);
  const s = setSlot(w, newNodeSlot(id, DOCUMENT_NODE, null));
  initDocumentSlot(s, xmlFlag !== true);
  register(w, id);
  return w;
};
isHTMLDocument = function (doc) { return doc === null ? true : slotOf(doc).docType === 'html'; };

// The main document wraps the native root.
(function () {
  const id = N.root();
  const w = create(HTMLDocument.prototype);
  const s = setSlot(w, newNodeSlot(id, DOCUMENT_NODE, null));
  initDocumentSlot(s, true);
  s.url = N.base();
  s.browsingContext = true;
  s.readyState = 'loading';
  register(w, id);
  mainDocument = w;
})();
let mainDocumentRef = mainDocument;

documentBaseURL = function (doc) {
  const s = slotOf(doc);
  return s.url;
};

function doctypeOf(doc) { for (const k of childrenOf(doc)) if (nodeType(k) === DOCUMENT_TYPE_NODE) return k; return null; }
function validateName(name) {
  if (!isValidName(name)) throw domError('InvalidCharacterError', "'" + name + "' is not a valid name");
}
function isXHTMLDocument(doc) { return slotOf(doc).contentType === 'application/xhtml+xml'; }

function createElementFor(doc, localName, namespace, prefix, isValue, sync) {
  return createElementInternal(doc, localName, namespace, prefix, isValue, sync);
}

operations(Document.prototype, {
  createElement(localName, options = undefined) {
    const s = docSlot(this);
    required(arguments, 1, 'createElement');
    let name = toDOMString(localName);
    validateName(name);
    if (s.docType === 'html') name = asciiLowercase(name);
    const ns = s.docType === 'html' || isXHTMLDocument(this) ? HTML_NS : null;
    let is = null;
    if (options !== undefined && options !== null) {
      if (typeof options === 'string') is = options;
      else if (isObject(options) && options.is !== undefined) is = toDOMString(options.is);
    }
    return createElementWithDefinition(this, name, ns, null, is, true);
  },
  createElementNS(namespace, qualifiedName_, options = undefined) {
    docSlot(this);
    required(arguments, 2, 'createElementNS');
    const ex = validateAndExtract(namespace, qualifiedName_);
    let is = null;
    if (options !== undefined && options !== null) {
      if (typeof options === 'string') is = options;
      else if (isObject(options) && options.is !== undefined) is = toDOMString(options.is);
    }
    return createElementWithDefinition(this, ex.localName, ex.namespace, ex.prefix, is, true);
  },
  createDocumentFragment() { docSlot(this); return createFragmentNode(this); },
  createTextNode(data) { docSlot(this); required(arguments, 1, 'createTextNode'); return createTextNode(this, toDOMString(data)); },
  createCDATASection(data) {
    const s = docSlot(this);
    required(arguments, 1, 'createCDATASection');
    if (s.docType === 'html') throw domError('NotSupportedError', 'This operation is not supported for HTML documents');
    const d = toDOMString(data);
    if (d.indexOf(']]>') >= 0) throw domError('InvalidCharacterError', 'String contains ]]>');
    return createCDATA(this, d);
  },
  createComment(data) { docSlot(this); required(arguments, 1, 'createComment'); return createCommentNode(this, toDOMString(data)); },
  createProcessingInstruction(target, data) {
    docSlot(this);
    required(arguments, 2, 'createProcessingInstruction');
    const t = toDOMString(target), d = toDOMString(data);
    if (!isValidName(t) || t.indexOf(':') >= 0 && false) throw domError('InvalidCharacterError', 'Invalid target');
    if (d.indexOf('?>') >= 0) throw domError('InvalidCharacterError', 'Data contains ?>');
    return createPI(this, t, d);
  },
  importNode(node, subtree = false) {
    docSlot(this);
    required(arguments, 1, 'importNode');
    if (isForeignNode(node)) { const copy = node.cloneNode(!!subtree); importForeign(copy, this); return copy; }
    if (!isNode(node)) throw new TypeError("Failed to execute 'importNode' on 'Document': parameter 1 is not of type 'Node'.");
    if (nodeType(node) === DOCUMENT_NODE || isShadowRoot(node)) throw domError('NotSupportedError', 'The node provided is a document or shadow root');
    return cloneNode(node, this, !!subtree);
  },
  adoptNode(node) {
    docSlot(this);
    required(arguments, 1, 'adoptNode');
    if (!acceptNode(node, this)) throw new TypeError("Failed to execute 'adoptNode' on 'Document': parameter 1 is not of type 'Node'.");
    if (nodeType(node) === DOCUMENT_NODE) throw domError('NotSupportedError', 'The node provided is a document');
    if (isShadowRoot(node)) throw domError('HierarchyRequestError', 'The node provided is a shadow root');
    if (nodeType(node) === DOCUMENT_FRAGMENT_NODE && shadowHost(node) !== null) return node;
    adopt(node, this);
    return node;
  },
  createAttribute(localName) {
    const s = docSlot(this);
    required(arguments, 1, 'createAttribute');
    let name = toDOMString(localName);
    validateName(name);
    if (s.docType === 'html') name = asciiLowercase(name);
    return newAttr(this, name, null, null, '');
  },
  createAttributeNS(namespace, qualifiedName_) {
    docSlot(this);
    required(arguments, 2, 'createAttributeNS');
    const ex = validateAndExtract(namespace, qualifiedName_);
    return newAttr(this, ex.localName, ex.namespace, ex.prefix, '');
  },
  createEvent(interface_) {
    docSlot(this);
    required(arguments, 1, 'createEvent');
    const name = asciiLowercase(toDOMString(interface_));
    let ctor = null;
    switch (name) {
      case 'beforeunloadevent': ctor = BeforeUnloadEvent; break;
      case 'compositionevent': ctor = CompositionEvent; break;
      case 'customevent': ctor = CustomEvent; break;
      case 'devicemotionevent': case 'deviceorientationevent': ctor = Event; break;
      case 'dragevent': ctor = MouseEvent; break;
      case 'event': case 'events': case 'htmlevents': case 'svgevents': ctor = Event; break;
      case 'focusevent': ctor = FocusEvent; break;
      case 'hashchangeevent': ctor = HashChangeEvent; break;
      case 'keyboardevent': ctor = KeyboardEvent; break;
      case 'messageevent': ctor = MessageEvent; break;
      case 'mouseevent': case 'mouseevents': ctor = MouseEvent; break;
      case 'storageevent': ctor = StorageEvent; break;
      case 'textevent': ctor = CompositionEvent; break;
      case 'touchevent': ctor = UIEvent; break;
      case 'uievent': case 'uievents': ctor = UIEvent; break;
      default: throw domError('NotSupportedError', 'The provided event type (\'' + interface_ + '\') is invalid.');
    }
    const ev = new ctor('');
    const s = slotOf(ev);
    s.initialized = false;
    s.type = '';
    s.timeStamp = currentTime();
    return ev;
  },
  getElementById(elementId) {
    docSlot(this);
    required(arguments, 1, 'getElementById');
    const id = toDOMString(elementId);
    if (id === '') return null;
    return findById(this, id);
  },
  getElementsByTagName(qualifiedName_) { docSlot(this); required(arguments, 1, 'getElementsByTagName'); return collectionByTagName(this, toDOMString(qualifiedName_)); },
  getElementsByTagNameNS(namespace, localName) {
    docSlot(this);
    required(arguments, 2, 'getElementsByTagNameNS');
    return collectionByTagNameNS(this, namespace === null || namespace === undefined ? '' : toDOMString(namespace), toDOMString(localName));
  },
  getElementsByClassName(classNames) { docSlot(this); required(arguments, 1, 'getElementsByClassName'); return collectionByClassName(this, toDOMString(classNames)); },
  hasFocus() { docSlot(this); return true; },
  getSelection() { docSlot(this); return null; }
});
installParentNode(Document.prototype);
function findById(root, id) {
  const rid = idOf(root);
  let n = nFirst(rid);
  // preorder walk over native ids
  let cur = n;
  while (cur >= 0) {
    if (N.kind(cur) === 2) {
      const v = N.attrGet(cur, 'id');
      if (v === id && (!hasAttrObjs(cur) || getAttributeValue(wrap(cur), 'id') === id)) return wrap(cur);
    }
    const f = nFirst(cur);
    if (f >= 0) { cur = f; continue; }
    while (cur >= 0 && cur !== rid) {
      const nx = nNext(cur);
      if (nx >= 0) { cur = nx; break; }
      cur = nParent(cur);
      if (cur === rid) { cur = -1; break; }
    }
  }
  return null;
}
function hasAttrObjs(nid_) { const w = apply(mapGet, wrappers, [nid_]); return w !== undefined && slotOf(w).attrObjs !== null; }

DocumentFragment.prototype.getElementById = function getElementById(elementId) {
  const s = slotOf(this);
  if (!s || s.nodeType !== DOCUMENT_FRAGMENT_NODE) illegal();
  required(arguments, 1, 'getElementById');
  const id = toDOMString(elementId);
  if (id === '') return null;
  return findById(this, id);
};
defineProperty(DocumentFragment.prototype, 'getElementById', { enumerable: true });

// Custom element hooks (replaced by the custom elements implementation).
let createElementWithDefinition = function (doc, localName, ns, prefix, is, sync) {
  return createElementInternal(doc, localName, ns, prefix, is, sync);
};

attributes(Document.prototype, {
  implementation: { get() { const s = docSlot(this); if (s.implementation === null) s.implementation = makeImplementation(this); return s.implementation; } },
  URL: { get() { return docSlot(this).url; } },
  documentURI: { get() { return docSlot(this).url; } },
  compatMode: { get() { return docSlot(this).mode === 'quirks' ? 'BackCompat' : 'CSS1Compat'; } },
  characterSet: { get() { return docSlot(this).encoding; } },
  charset: { get() { return docSlot(this).encoding; } },
  inputEncoding: { get() { return docSlot(this).encoding; } },
  contentType: { get() { return docSlot(this).contentType; } },
  doctype: { get() { docSlot(this); return doctypeOf(this); } },
  documentElement: { get() { docSlot(this); return documentElementOf(this); } },
  origin: { get() { return docSlot(this).origin; } }
});

// --- DOMImplementation

function DOMImplementation() { throw new TypeError('Illegal constructor'); }
iface('DOMImplementation', DOMImplementation, null);
function makeImplementation(doc) {
  const o = create(DOMImplementation.prototype);
  setSlot(o, { isImplementation: true, doc });
  return o;
}
function implSlot(o) { const s = slotOf(o); if (!s || !s.isImplementation) illegal(); return s; }
operations(DOMImplementation.prototype, {
  createDocumentType(qualifiedName_, publicId, systemId) {
    const s = implSlot(this);
    required(arguments, 3, 'createDocumentType');
    const q = toDOMString(qualifiedName_);
    if (!isValidName(q)) throw domError('InvalidCharacterError', "'" + q + "' is not a valid doctype name");
    const colon = q.indexOf(':');
    if (colon >= 0) {
      const prefix = q.slice(0, colon), local = q.slice(colon + 1);
      if (!isValidNCName(prefix) || !isValidNCName(local)) throw domError('InvalidCharacterError', "'" + q + "' is not a valid doctype name");
    }
    return createDoctypeNode(s.doc, q, toDOMString(publicId), toDOMString(systemId));
  },
  createDocument(namespace, qualifiedName_, doctype = null) {
    implSlot(this);
    required(arguments, 2, 'createDocument');
    if (doctype !== null && doctype !== undefined && (!isObject(doctype) || !slotOf(doctype) || slotOf(doctype).nodeType !== DOCUMENT_TYPE_NODE)) throw new TypeError("Failed to execute 'createDocument' on 'DOMImplementation': parameter 3 is not of type 'DocumentType'.");
    const doc = newDocument(true);
    const ds = slotOf(doc);
    let element = null;
    const q = qualifiedName_ === null || qualifiedName_ === undefined ? '' : toDOMString(qualifiedName_);
    if (q !== '') element = createElementWithDefinition(doc, ...(function () { const ex = validateAndExtract(namespace, q); return [ex.localName, ex.namespace, ex.prefix, null, true]; })());
    if (doctype) preInsert(doctype, doc, null);
    if (element !== null) preInsert(element, doc, null);
    const ns = namespace === null || namespace === undefined || namespace === '' ? null : toDOMString(namespace);
    if (ns === HTML_NS) ds.contentType = 'application/xhtml+xml';
    else if (ns === SVG_NS) ds.contentType = 'image/svg+xml';
    else ds.contentType = 'application/xml';
    return doc;
  },
  createHTMLDocument(title = undefined) {
    const s = implSlot(this);
    const doc = newDocument(false);
    const ds = slotOf(doc);
    preInsert(createDoctypeNode(doc, 'html', '', ''), doc, null);
    const html = createElementInternal(doc, 'html', HTML_NS, null, null, false);
    preInsert(html, doc, null);
    const head = createElementInternal(doc, 'head', HTML_NS, null, null, false);
    preInsert(head, html, null);
    if (title !== undefined) {
      const t = createElementInternal(doc, 'title', HTML_NS, null, null, false);
      preInsert(t, head, null);
      preInsert(createTextNode(doc, toDOMString(title)), t, null);
    }
    preInsert(createElementInternal(doc, 'body', HTML_NS, null, null, false), html, null);
    ds.url = 'about:blank';
    ds.origin = slotOf(s.doc).origin;
    return doc;
  },
  hasFeature() { implSlot(this); return true; }
});

// --- element collections by name

function matchesTagName(el, qualifiedName_, htmlDoc) {
  const s = slotOf(el);
  if (qualifiedName_ === '*') return true;
  const q = s.prefix === null ? s.localName : s.prefix + ':' + s.localName;
  if (htmlDoc) {
    if (s.namespaceURI === HTML_NS) return q === asciiLowercase(qualifiedName_);
    return q === qualifiedName_;
  }
  return q === qualifiedName_;
}
collectionByTagName = function (root, qualifiedName_) {
  const doc = ownerDocOrSelf(root);
  return makeCollection(() => {
    const htmlDoc = isHTMLDocument(doc);
    const out = [];
    for (const d of descendantsOf(root)) if (nodeType(d) === ELEMENT_NODE && matchesTagName(d, qualifiedName_, htmlDoc)) apply(arrayPush, out, [d]);
    return out;
  });
};
collectionByTagNameNS = function (root, namespace, localName) {
  const ns = namespace === '' ? null : namespace;
  return makeCollection(() => {
    const out = [];
    for (const d of descendantsOf(root)) {
      if (nodeType(d) !== ELEMENT_NODE) continue;
      const s = slotOf(d);
      if ((namespace === '*' || s.namespaceURI === ns) && (localName === '*' || s.localName === localName)) apply(arrayPush, out, [d]);
    }
    return out;
  });
};
collectionByClassName = function (root, classNames) {
  const doc = ownerDocOrSelf(root);
  const wanted = parseTokens(classNames);
  return makeCollection(() => {
    const out = [];
    if (wanted.length === 0) return out;
    const quirks = slotOf(doc).mode === 'quirks';
    for (const d of descendantsOf(root)) {
      if (nodeType(d) !== ELEMENT_NODE) continue;
      const cls = getAttributeValue(d, 'class');
      if (cls === null) continue;
      const have = parseTokens(quirks ? asciiLowercase(cls) : cls);
      let all = true;
      for (const w of wanted) if (have.indexOf(quirks ? asciiLowercase(w) : w) < 0) { all = false; break; }
      if (all) apply(arrayPush, out, [d]);
    }
    return out;
  });
};
