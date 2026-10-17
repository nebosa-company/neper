// Streams Standard: shared helpers (queues with sizes, strategies, promise plumbing).

const promiseThen = Promise.prototype.then;
const promiseResolve = Promise.resolve.bind(Promise);
const promiseReject = Promise.reject.bind(Promise);
function noop() {}
function isNonNegativeNumber(v) { return typeof v === 'number' && v === v && v >= 0; }
function promiseResolvedWith(v) { return promiseResolve(v); }
function promiseRejectedWith(e) { return promiseReject(e); }
function newPromiseCapability() {
  const cap = { promise: undefined, resolve: undefined, reject: undefined, settled: false };
  cap.promise = new Promise((res, rej) => {
    cap.resolve = v => { cap.settled = true; res(v); };
    cap.reject = e => { cap.settled = true; rej(e); };
  });
  return cap;
}
function settledCapability(promise) { return { promise, resolve: noop, reject: noop, settled: true }; }
function setPromiseIsHandled(p) { apply(promiseThen, p, [undefined, noop]); }
function uponPromise(p, onFulfilled, onRejected) { return apply(promiseThen, p, [onFulfilled, onRejected]); }
function uponFulfillment(p, onFulfilled) { return apply(promiseThen, p, [onFulfilled, undefined]); }
function uponRejection(p, onRejected) { return apply(promiseThen, p, [undefined, onRejected]); }
function transformPromiseWith(p, onFulfilled, onRejected) { return apply(promiseThen, p, [onFulfilled, onRejected]); }
function queueMicrotaskStreams(fn) { Promise.resolve().then(fn); }

function enqueueValueWithSize(container, value, size) {
  if (!isNonNegativeNumber(size) || size === Infinity) throw new RangeError('The return value of a queuing strategy\'s size function must be a finite, non-NaN, non-negative number');
  apply(arrayPush, container.queue, [{ value, size }]);
  container.queueTotalSize += size;
}
function dequeueValue(container) {
  const pair = container.queue.shift();
  container.queueTotalSize -= pair.size;
  if (container.queueTotalSize < 0) container.queueTotalSize = 0;
  return pair.value;
}
function peekQueueValue(container) { return container.queue[0].value; }
function resetQueue(container) { container.queue = []; container.queueTotalSize = 0; }

function extractHighWaterMark(strategy, defaultHWM) {
  const hwm = strategy.highWaterMark;
  if (hwm === undefined) return defaultHWM;
  const n = Number(hwm);
  if (n !== n || n < 0) throw new RangeError('Invalid highWaterMark');
  return n;
}
function extractSizeAlgorithm(strategy) {
  const size = strategy.size;
  if (size === undefined) return () => 1;
  return chunk => apply(size, undefined, [chunk]);
}
// QueuingStrategy dictionary conversion (members in lexicographic order).
function convertQueuingStrategy(strategy, context) {
  if (strategy === undefined || strategy === null) return {};
  if (!isObject(strategy)) throw new TypeError(context + ' is not an object.');
  const out = {};
  const hwm = strategy.highWaterMark;
  if (hwm !== undefined) out.highWaterMark = Number(hwm);
  const size = strategy.size;
  if (size !== undefined) {
    if (typeof size !== 'function') throw new TypeError(context + '.size is not a function.');
    out.size = size;
  }
  return out;
}
function validateAndNormalizeHighWaterMark(hwm) {
  const n = Number(hwm);
  if (n !== n || n < 0) throw new RangeError('Invalid highWaterMark');
  return n;
}
function callOrUndefined(fn, thisArg, args) { return fn === undefined ? undefined : apply(fn, thisArg, args); }
function promiseCall(fn, thisArg, args) {
  try { return promiseResolve(apply(fn, thisArg, args)); } catch (e) { return promiseReject(e); }
}
function isReadableStreamLike(o) { return isObject(o) && slotOf(o) && slotOf(o).isReadableStream === true; }

// Detached buffers: ArrayBuffer.prototype.detached / transfer are the platform's way to move a buffer.
const abDetachedGetter = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'detached').get;
const abTransfer = ArrayBuffer.prototype.transfer;
const abByteLengthGetter = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
function isDetachedBuffer(b) { return apply(abDetachedGetter, b, []); }
function transferArrayBuffer(b) { return apply(abTransfer, b, []); }
function canTransferArrayBuffer(b) { return !isDetachedBuffer(b); }
function isArrayBufferObject(o) { try { apply(abByteLengthGetter, o, []); return true; } catch (e) { return false; } }
const taBufferGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Int8Array.prototype), 'buffer').get;
const taByteOffsetGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Int8Array.prototype), 'byteOffset').get;
const taByteLengthGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Int8Array.prototype), 'byteLength').get;
const taTagGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Int8Array.prototype), Symbol.toStringTag).get;
const dvBufferGetter = Object.getOwnPropertyDescriptor(DataView.prototype, 'buffer').get;
const dvByteOffsetGetter = Object.getOwnPropertyDescriptor(DataView.prototype, 'byteOffset').get;
const dvByteLengthGetter = Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get;
function viewKind(v) {
  if (!isObject(v)) return null;
  const t = apply(taTagGetter, v, []);
  if (t !== undefined) return t;
  try { apply(dvBufferGetter, v, []); return 'DataView'; } catch (e) { return null; }
}
function viewBuffer(v) { return viewKind(v) === 'DataView' ? apply(dvBufferGetter, v, []) : apply(taBufferGetter, v, []); }
function viewByteOffset(v) { return viewKind(v) === 'DataView' ? apply(dvByteOffsetGetter, v, []) : apply(taByteOffsetGetter, v, []); }
function viewByteLength(v) { return viewKind(v) === 'DataView' ? apply(dvByteLengthGetter, v, []) : apply(taByteLengthGetter, v, []); }
const viewElementSizes = { Int8Array: 1, Uint8Array: 1, Uint8ClampedArray: 1, Int16Array: 2, Uint16Array: 2, Int32Array: 4, Uint32Array: 4, Float32Array: 4, Float64Array: 8, BigInt64Array: 8, BigUint64Array: 8, DataView: 1 };
const viewConstructors = { Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array, Float64Array, BigInt64Array, BigUint64Array, DataView };
