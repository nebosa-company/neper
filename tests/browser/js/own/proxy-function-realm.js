/*---
description: the realm of a proxy is its target's, for the prototype taken when new.target has no object prototype
---*/
var realm1 = $262.createRealm().global;
var realm2 = $262.createRealm().global;
var realm3 = $262.createRealm().global;
var newTarget = new realm1.Function();
newTarget.prototype = false;
var proxy = new realm2.Proxy(newTarget, {});
var array = Reflect.construct(realm3.Array, [], proxy);
assert.sameValue(Object.getPrototypeOf(array), realm1.Array.prototype);
