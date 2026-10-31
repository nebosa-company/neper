/*---
description: decorators before and after export
flags: [module]
features: [decorators]
---*/
var seen = [];
function mark(name) { return function (cls, ctx) { seen.push(name + ':' + ctx.kind + ':' + ctx.name); }; }

@mark('a') export class A {}
export @mark('b') class B {}
export default @mark('c') class {}

assert.compareArray(seen, ['a:class:A', 'b:class:B', 'c:class:default']);
