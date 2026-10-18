/*---
description: decorator application
features: [decorators]
flags: [onlyStrict]
---*/
var log = [];
function trace(tag) { return function (v, ctx) { log.push(tag + ":" + ctx.kind + ":" + String(ctx.name) + ":" + ctx.static + ":" + ctx.private); }; }

// method replace + kind/name/static
function wrap(fn, ctx) { return function () { return "w(" + fn.apply(this, arguments) + ")"; }; }
class A {
  @wrap m() { return "m"; }
  @wrap static s() { return "s"; }
  @wrap get g() { return "g"; }
  @wrap #p() { return "p"; }
  callP() { return this.#p(); }
}
var a = new A();
assert.sameValue(a.m(), "w(m)");
assert.sameValue(A.s(), "w(s)");
assert.sameValue(a.g, "w(g)");
assert.sameValue(a.callP(), "w(p)");

// order: last decorator applied first
var order = [];
function d(n) { return function (v, c) { order.push(n); }; }
class B { @d(1) @d(2) @d(3) x() {} }
assert.compareArray(order, [3, 2, 1]);

// field decorator
function plusOne(v, ctx) { return function (init) { return init + 1; }; }
class C { @plusOne f = 1; @plusOne static sf = 10; }
assert.sameValue(new C().f, 2);
assert.sameValue(C.sf, 11);

// accessor decorator
function dbl(value, ctx) {
  return { get() { return value.get.call(this) * 2; }, set(v) { value.set.call(this, v + 1); }, init(v) { return v + 100; } };
}
class D { @dbl accessor x = 1; }
var dd = new D();
assert.sameValue(dd.x, 202);
dd.x = 5;
assert.sameValue(dd.x, 12);

// class decorator replacement and addInitializer
var seen = [];
function cls(Base, ctx) {
  ctx.addInitializer(function () { seen.push("class-init:" + (this === E2)); });
  return class extends Base { extra() { return 1; } };
}
@cls class E { }
var E2 = E;
assert.sameValue(new E().extra(), 1);
assert.sameValue(seen.length, 1);

// instance addInitializer runs per construction
var n = 0;
function counter(fn, ctx) { ctx.addInitializer(function () { n++; }); }
class F { @counter m() {} }
new F(); new F();
assert.sameValue(n, 2);

// access
var acc;
function grab(v, ctx) { acc = ctx.access; }
class G { @grab h = 7; }
assert.sameValue(acc.get(new G()), 7);
acc.set(new G(), 3);
assert.sameValue(acc.has(new G()), true);

// addInitializer after decoration throws
var late;
function keep(fn, ctx) { late = ctx.addInitializer; }
class H { @keep m() {} }
assert.throws(TypeError, function () { late(function () {}); });
