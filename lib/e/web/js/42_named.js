// Named access on the Window: elements of the main document with an id (or a name, for a few tags) are properties of the global.

const namedDefined = new Set();
const namedByName = ['embed', 'form', 'iframe', 'img', 'object'];
function firstNamed(name) {
  const byId = apply(documentGetElementById, mainDocument, [name]);
  if (byId !== null) return byId;
  for (const d of descendantsOf(mainDocument)) {
    if (nodeType(d) !== ELEMENT_NODE) continue;
    const s = slotOf(d);
    if (s.namespaceURI === HTML_NS && namedByName.indexOf(s.localName) >= 0 && getAttributeValue(d, 'name') === name) return s.localName === 'iframe' && frameWindowOf(d) !== null ? frameWindowOf(d) : d;
  }
  return null;
}
const documentGetElementById = Document.prototype.getElementById;
function refreshNamed(name) {
  if (typeof name !== 'string' || name === '') return;
  const found = firstNamed(name);
  if (found === null) {
    if (namedDefined.has(name)) { delete global[name]; namedDefined.delete(name); }
    return;
  }
  if (namedDefined.has(name) || hasOwn.call(global, name)) return;
  defineProperty(global, name, {
    get() { return firstNamed(name); },
    set(v) { delete global[name]; namedDefined.delete(name); defineProperty(global, name, { value: v, writable: true, enumerable: true, configurable: true }); },
    enumerable: false, configurable: true
  });
  namedDefined.add(name);
}
function refreshNamedFor(el) {
  if (nodeType(el) !== ELEMENT_NODE) return;
  refreshNamed(getAttributeValue(el, 'id'));
  if (namedByName.indexOf(slotOf(el).localName) >= 0) refreshNamed(getAttributeValue(el, 'name'));
}
const prevInserted = elementInserted;
elementInserted = function (el) {
  prevInserted(el);
  if (shadowIncludingRoot(el) === mainDocument) refreshNamedFor(el);
};
const prevRemoved = elementRemoved;
elementRemoved = function (el, parent) {
  prevRemoved(el, parent);
  refreshNamedFor(el);
};
const prevAttrChanged = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrChanged(el, name, oldValue, value);
  if ((name === 'id' || name === 'name') && shadowIncludingRoot(el) === mainDocument) { refreshNamed(oldValue); refreshNamed(value); }
};
for (const d of descendantsOf(mainDocument)) refreshNamedFor(d);
