// Event handler content attributes (<button onclick="...">): compiled into the handler of the element (or, for <body> and
// <frameset>, of the window) with the element, its form owner and the document in scope.

const FunctionConstructor = Function;
const windowReflectedHandlers = ['afterprint', 'beforeprint', 'beforeunload', 'blur', 'error', 'focus', 'hashchange', 'languagechange', 'load', 'message', 'messageerror', 'offline', 'online', 'pagehide', 'pageshow', 'popstate', 'rejectionhandled', 'resize', 'scroll', 'storage', 'unhandledrejection', 'unload'];
function isBodyOrFrameset(el) { const n = htmlLocal(el); return n === 'body' || n === 'frameset'; }
function compileHandler(el, type, code, forWindow) {
  const form = isListed(el) ? formOwnerOf(el) : null;
  const params = type === 'error' && forWindow ? 'event, source, lineno, colno, error' : 'event';
  const factory = FunctionConstructor('__doc', '__form', '__el', 'with (__doc) with (__form) with (__el) { return function on' + type + '(' + params + ') {\n' + code + '\n}; }');
  return factory(slotOf(el).doc, form || {}, el);
}
function handlerContentAttribute(el, name, value) {
  const s = slotOf(el);
  if (s.namespaceURI !== HTML_NS && s.namespaceURI !== SVG_NS && s.namespaceURI !== MATHML_NS) return;
  const type = name.slice(2);
  const windowTarget = isBodyOrFrameset(el) && windowReflectedHandlers.indexOf(type) >= 0;
  if (!windowTarget && eventHandlerNames.indexOf(type) < 0) return;
  const target = windowTarget ? global : el;
  const setter = eventHandlerAttribute(type).set;
  if (value === null) { apply(setter, target, [null]); return; }
  let fn = null;
  try { fn = compileHandler(el, type, value, windowTarget); } catch (e) { reportException(e); }
  apply(setter, target, [fn]);
}
const prevAttrHandlers = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrHandlers(el, name, oldValue, value);
  if (name.length > 2 && name.charCodeAt(0) === 111 && name.charCodeAt(1) === 110) handlerContentAttribute(el, name, value);
};
function scanHandlerAttributes() {
  for (const d of descendantsOf(mainDocument)) {
    if (nodeType(d) !== ELEMENT_NODE) continue;
    for (const a of attrsOf(d)) { const as = slotOf(a); if (as.namespaceURI === null && as.localName.length > 2 && as.localName.charCodeAt(0) === 111 && as.localName.charCodeAt(1) === 110) handlerContentAttribute(d, as.localName, as.value); }
  }
}
