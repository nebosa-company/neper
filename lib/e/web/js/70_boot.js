// Work that needs every earlier file defined: declarative shadow roots in the parsed document.

// Every WebIDL operation and setter of the node interfaces runs on the custom element reaction stack.
// Nothing queues a reaction until a custom element is defined, so the wrappers (about 2 KB each, a few thousand of them) are
// installed by the first customElements.define.
const ceNodeLike = c => c === Node || c.prototype instanceof Node || c === DOMTokenList || c === NamedNodeMap || c === Range || c === DOMImplementation;
let ceWrapped = false;
function ensureCeWrapped() {
  if (ceWrapped) return;
  ceWrapped = true;
  for (const w of frameWindowsAll) { try { w.__realm.ensureCeWrapped(); } catch (e) { /* a dropped frame */ } }
  for (const c of allInterfaces) if (typeof c === 'function' && ceNodeLike(c)) ceWrapPrototype(c.prototype);
}
convertDeclarative(mainDocument);
scanHandlerAttributes();
// Frames the markup parser made get their contexts now.
for (const d of descendantsOf(mainDocument)) if (isIFrame(d)) frameInserted(d);
