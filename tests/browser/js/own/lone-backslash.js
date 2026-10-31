/*---
description: A backslash that does not start a unicode escape ends the source with a SyntaxError instead of hanging the lexer
---*/
assert.throws(SyntaxError, function() { Function("x\\"); });
assert.throws(SyntaxError, function() { Function("for(var w in \\"); });
assert.sameValue(new Function("return typeof anonymous")(), "undefined");
assert.throws(SyntaxError, function() { new Function("/*", "*/) {"); });
