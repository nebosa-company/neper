/*---
description: A backslash that does not start a unicode escape ends the source with a SyntaxError instead of hanging the lexer
---*/
assert.throws(SyntaxError, function() { Function("x\\"); });
assert.throws(SyntaxError, function() { Function("for(var w in \\"); });
assert.sameValue(new Function("return typeof anonymous")(), "undefined");
assert.throws(SyntaxError, function() { new Function("/*", "*/) {"); });
assert.throws(SyntaxError, function() { eval("function class() {}"); });
assert.sameValue(typeof (0, eval)?.("1"), "number");
function C() {}
var tagged = function() { return C; };
assert(new tagged`x` instanceof C);
var oc = { x: 1 };
assert.sameValue(delete oc?.x, true);
assert.sameValue(oc.x, undefined);
assert.throws(SyntaxError, function() { eval("new Object?.()"); });
assert.throws(SyntaxError, function() { eval("class A {} class B extends A { constructor() { super?.(); } }"); });
assert.throws(SyntaxError, function() { eval("({ __proto__: null, __proto__, __proto__: null })"); });
assert.sameValue(new Date("1997-3-8 1:1:1.01").getTime(), new Date("1997-03-08T01:01:01.01").getTime());
var pif = [];
for (let v = (pif.push(function() { return v; }), 0); v < 2; v++) { v += 0; }
assert.sameValue(pif[0](), 0);
