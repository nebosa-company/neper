// Work that needs every earlier file defined: declarative shadow roots in the parsed document.

// Every WebIDL operation and setter of the node interfaces runs on the custom element reaction stack.
const ceNodeLike = c => c === Node || c.prototype instanceof Node || c === DOMTokenList || c === NamedNodeMap || c === Range || c === DOMImplementation;
for (const c of allInterfaces) if (typeof c === 'function' && ceNodeLike(c)) ceWrapPrototype(c.prototype);
convertDeclarative(mainDocument);
