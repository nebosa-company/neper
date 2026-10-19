/*---
description: full upper-case mappings and the final sigma rule
---*/
assert.sameValue("ﬀ".toUpperCase(), "FF");
assert.sameValue("ß".toUpperCase(), "SS");
assert.sameValue("ὐ".toUpperCase(), "Υ̓");
assert.sameValue("AΣ".toLowerCase(), "aς");
assert.sameValue("AΣB".toLowerCase(), "aσb");
assert.sameValue("A᠎Σ᠎".toLowerCase(), "a᠎ς᠎");
assert.sameValue("ͅΣ".toLowerCase(), "ͅσ");
