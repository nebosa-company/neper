/*---
description: toPrecision rounds the exact value of a large number, not its shortest decimal
---*/
assert.sameValue((1.2345e27).toPrecision(4), "1.234e+27");
assert.sameValue((1e21).toPrecision(3), "1.00e+21");
assert.sameValue((123456789012345680000).toPrecision(3), "1.23e+20");
