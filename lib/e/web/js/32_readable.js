// Streams Standard: ReadableStream, its default reader and default controller, tee, async iteration and pipeTo.

function ReadableStream(underlyingSource = undefined, strategy = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'ReadableStream': Please use the 'new' operator");
  const strat = convertQueuingStrategy(strategy, 'ReadableStream strategy');
  let src = underlyingSource;
  if (src === undefined) src = null;
  const dict = convertUnderlyingSource(src);
  initializeReadableStream(this);
  if (dict.type === 'bytes') {
    if (strat.size !== undefined) throw new RangeError('The strategy for a byte stream cannot have a size function');
    const hwm = extractHighWaterMark(strat, 0);
    setUpReadableByteStreamControllerFromUnderlyingSource(this, src, dict, hwm);
  } else {
    const sizeAlgorithm = extractSizeAlgorithm(strat);
    const hwm = extractHighWaterMark(strat, 1);
    setUpReadableStreamDefaultControllerFromUnderlyingSource(this, src, dict, hwm, sizeAlgorithm);
  }
}
iface('ReadableStream', ReadableStream, null);
function convertUnderlyingSource(src) {
  const dict = {};
  if (src === null) return dict;
  if (!isObject(src)) throw new TypeError('The underlying source is not an object.');
  const auto = src.autoAllocateChunkSize;
  if (auto !== undefined) {
    const n = Number(auto);
    if (n !== n || n === Infinity || n === -Infinity || Math.trunc(n) < 0 || Math.trunc(n) > 18446744073709551615) throw new TypeError('autoAllocateChunkSize is out of range');
    dict.autoAllocateChunkSize = Math.trunc(n);
  }
  for (const name of ['cancel', 'pull', 'start']) {
    const v = src[name];
    if (v !== undefined) {
      if (typeof v !== 'function') throw new TypeError('The underlying source ' + name + ' is not a function.');
      dict[name] = v;
    }
  }
  const type = src.type;
  if (type !== undefined) {
    const t = String(type);
    if (t !== 'bytes') throw new TypeError("The provided value '" + t + "' is not a valid enum value of type ReadableStreamType.");
    dict.type = t;
  }
  return dict;
}
function rsSlot(o) { const s = slotOf(o); if (!s || s.isReadableStream !== true) throw new TypeError('Illegal invocation'); return s; }
function initializeReadableStream(stream) {
  setSlot(stream, { isReadableStream: true, state: 'readable', reader: undefined, storedError: undefined, disturbed: false, controller: undefined });
}
function isReadableStreamLocked(stream) { return slotOf(stream).reader !== undefined; }

// --- controller

function ReadableStreamDefaultController() { throw new TypeError('Illegal constructor'); }
iface('ReadableStreamDefaultController', ReadableStreamDefaultController, null);
function rdcSlot(o) { const s = slotOf(o); if (!s || s.isDefaultController !== true) throw new TypeError('Illegal invocation'); return s; }
attributes(ReadableStreamDefaultController.prototype, {
  desiredSize: { get() { return readableStreamDefaultControllerGetDesiredSize(this); } }
});
operations(ReadableStreamDefaultController.prototype, {
  close() {
    rdcSlot(this);
    if (!readableStreamDefaultControllerCanCloseOrEnqueue(this)) throw new TypeError('The stream is not in a state that permits close');
    readableStreamDefaultControllerClose(this);
  },
  enqueue(chunk = undefined) {
    rdcSlot(this);
    if (!readableStreamDefaultControllerCanCloseOrEnqueue(this)) throw new TypeError('The stream is not in a state that permits enqueue');
    readableStreamDefaultControllerEnqueue(this, chunk);
  },
  error(e = undefined) { rdcSlot(this); readableStreamDefaultControllerError(this, e); }
});
function readableStreamDefaultControllerCallPullIfNeeded(controller) {
  const c = slotOf(controller);
  if (!readableStreamDefaultControllerShouldCallPull(controller)) return;
  if (c.pulling) { c.pullAgain = true; return; }
  c.pulling = true;
  const pullPromise = c.pullAlgorithm();
  uponPromise(pullPromise, () => {
    c.pulling = false;
    if (c.pullAgain) { c.pullAgain = false; readableStreamDefaultControllerCallPullIfNeeded(controller); }
  }, e => readableStreamDefaultControllerError(controller, e));
}
function readableStreamDefaultControllerShouldCallPull(controller) {
  const c = slotOf(controller), stream = c.stream, ss = slotOf(stream);
  if (!readableStreamDefaultControllerCanCloseOrEnqueue(controller)) return false;
  if (!c.started) return false;
  if (isReadableStreamLocked(stream) && readableStreamGetNumReadRequests(stream) > 0) return true;
  const desiredSize = readableStreamDefaultControllerGetDesiredSize(controller);
  return desiredSize > 0;
}
function readableStreamDefaultControllerClearAlgorithms(controller) {
  const c = slotOf(controller);
  c.pullAlgorithm = undefined; c.cancelAlgorithm = undefined; c.strategySizeAlgorithm = undefined;
}
function readableStreamDefaultControllerClose(controller) {
  const c = slotOf(controller);
  if (!readableStreamDefaultControllerCanCloseOrEnqueue(controller)) return;
  const stream = c.stream;
  c.closeRequested = true;
  if (c.queue.length === 0) { readableStreamDefaultControllerClearAlgorithms(controller); readableStreamClose(stream); }
}
function readableStreamDefaultControllerEnqueue(controller, chunk) {
  const c = slotOf(controller);
  if (!readableStreamDefaultControllerCanCloseOrEnqueue(controller)) return;
  const stream = c.stream;
  if (isReadableStreamLocked(stream) && readableStreamGetNumReadRequests(stream) > 0) {
    readableStreamFulfillReadRequest(stream, chunk, false);
  } else {
    let chunkSize;
    try { chunkSize = c.strategySizeAlgorithm(chunk); } catch (e) { readableStreamDefaultControllerError(controller, e); throw e; }
    try { enqueueValueWithSize(c, chunk, chunkSize); } catch (e) { readableStreamDefaultControllerError(controller, e); throw e; }
  }
  readableStreamDefaultControllerCallPullIfNeeded(controller);
}
function readableStreamDefaultControllerError(controller, e) {
  const c = slotOf(controller), stream = c.stream;
  if (slotOf(stream).state !== 'readable') return;
  resetQueue(c);
  readableStreamDefaultControllerClearAlgorithms(controller);
  readableStreamError(stream, e);
}
function readableStreamDefaultControllerGetDesiredSize(controller) {
  const c = rdcSlot(controller), state = slotOf(c.stream).state;
  if (state === 'errored') return null;
  if (state === 'closed') return 0;
  return c.strategyHWM - c.queueTotalSize;
}
function readableStreamDefaultControllerCanCloseOrEnqueue(controller) {
  const c = slotOf(controller);
  return slotOf(c.stream).state === 'readable' && !c.closeRequested;
}
function readableStreamDefaultControllerHasBackpressure(controller) { return !readableStreamDefaultControllerShouldCallPull(controller); }
function setUpReadableStreamDefaultController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm, sizeAlgorithm) {
  const controller = create(ReadableStreamDefaultController.prototype);
  const c = setSlot(controller, { isDefaultController: true, stream, queue: [], queueTotalSize: 0, started: false, closeRequested: false, pullAgain: false, pulling: false, strategySizeAlgorithm: sizeAlgorithm, strategyHWM: hwm, pullAlgorithm, cancelAlgorithm });
  slotOf(stream).controller = controller;
  const startResult = startAlgorithm(controller);
  uponPromise(promiseResolvedWith(startResult), () => {
    c.started = true;
    readableStreamDefaultControllerCallPullIfNeeded(controller);
  }, r => readableStreamDefaultControllerError(controller, r));
}
function setUpReadableStreamDefaultControllerFromUnderlyingSource(stream, source, dict, hwm, sizeAlgorithm) {
  const startAlgorithm = controller => (dict.start ? apply(dict.start, source, [controller]) : undefined);
  const pullAlgorithm = () => (dict.pull ? promiseCallStreams(dict.pull, source, [slotOf(stream).controller]) : promiseResolvedWith(undefined));
  const cancelAlgorithm = reason => (dict.cancel ? promiseCallStreams(dict.cancel, source, [reason]) : promiseResolvedWith(undefined));
  setUpReadableStreamDefaultController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm, sizeAlgorithm);
}
function promiseCallStreams(fn, thisArg, args) {
  try { return promiseResolvedWith(apply(fn, thisArg, args)); } catch (e) { return promiseRejectedWith(e); }
}
function createReadableStream(startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm = 1, sizeAlgorithm = () => 1) {
  const stream = create(ReadableStream.prototype);
  initializeReadableStream(stream);
  setUpReadableStreamDefaultController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm, sizeAlgorithm);
  return stream;
}
// [[CancelSteps]], [[PullSteps]], [[ReleaseSteps]] of the controllers
function controllerCancelSteps(controller, reason) {
  const c = slotOf(controller);
  if (c.isDefaultController) {
    resetQueue(c);
    const result = c.cancelAlgorithm(reason);
    readableStreamDefaultControllerClearAlgorithms(controller);
    return result;
  }
  return readableByteStreamControllerCancelSteps(controller, reason);
}
function controllerPullSteps(controller, readRequest) {
  const c = slotOf(controller);
  if (c.isDefaultController) {
    const stream = c.stream;
    if (c.queue.length > 0) {
      const chunk = dequeueValue(c);
      if (c.closeRequested && c.queue.length === 0) { readableStreamDefaultControllerClearAlgorithms(controller); readableStreamClose(stream); }
      else readableStreamDefaultControllerCallPullIfNeeded(controller);
      readRequest.chunkSteps(chunk);
    } else {
      readableStreamAddReadRequest(stream, readRequest);
      readableStreamDefaultControllerCallPullIfNeeded(controller);
    }
    return;
  }
  readableByteStreamControllerPullSteps(controller, readRequest);
}
function controllerReleaseSteps(controller) {
  const c = slotOf(controller);
  if (c.isDefaultController) return;
  readableByteStreamControllerReleaseSteps(controller);
}

// --- stream-level abstract operations

function readableStreamAddReadRequest(stream, rr) { apply(arrayPush, slotOf(slotOf(stream).reader).readRequests, [rr]); }
function readableStreamFulfillReadRequest(stream, chunk, done) {
  const reader = slotOf(stream).reader;
  const rr = slotOf(reader).readRequests.shift();
  if (done) rr.closeSteps(); else rr.chunkSteps(chunk);
}
function readableStreamGetNumReadRequests(stream) { return slotOf(slotOf(stream).reader).readRequests.length; }
function readableStreamClose(stream) {
  const s = slotOf(stream);
  s.state = 'closed';
  const reader = s.reader;
  if (reader === undefined) return;
  const r = slotOf(reader);
  r.closedCapability.resolve(undefined);
  if (r.isDefaultReader) {
    const reqs = r.readRequests;
    r.readRequests = [];
    for (const rr of reqs) rr.closeSteps();
  }
}
function readableStreamError(stream, e) {
  const s = slotOf(stream);
  s.state = 'errored';
  s.storedError = e;
  const reader = s.reader;
  if (reader === undefined) return;
  const r = slotOf(reader);
  r.closedCapability.reject(e);
  setPromiseIsHandled(r.closedCapability.promise);
  if (r.isDefaultReader) readableStreamDefaultReaderErrorReadRequests(reader, e);
  else readableStreamBYOBReaderErrorReadIntoRequests(reader, e);
}
function readableStreamCancel(stream, reason) {
  const s = slotOf(stream);
  s.disturbed = true;
  if (s.state === 'closed') return promiseResolvedWith(undefined);
  if (s.state === 'errored') return promiseRejectedWith(s.storedError);
  readableStreamClose(stream);
  const reader = s.reader;
  if (reader !== undefined && slotOf(reader).isBYOBReader) {
    const reqs = slotOf(reader).readIntoRequests;
    slotOf(reader).readIntoRequests = [];
    for (const rr of reqs) rr.closeSteps(undefined);
  }
  const sourceCancelPromise = controllerCancelSteps(s.controller, reason);
  return transformPromiseWith(sourceCancelPromise, () => undefined, undefined);
}

// --- readers

function readerGenericInitialize(reader, stream) {
  const r = slotOf(reader), s = slotOf(stream);
  r.stream = stream;
  s.reader = reader;
  r.closedCapability = newPromiseCapability();
  if (s.state === 'closed') r.closedCapability.resolve(undefined);
  else if (s.state === 'errored') { r.closedCapability.reject(s.storedError); setPromiseIsHandled(r.closedCapability.promise); }
}
function readerGenericRelease(reader) {
  const r = slotOf(reader), stream = r.stream, s = slotOf(stream);
  const e = new TypeError('Reader was released and can no longer be used to monitor the stream\'s closedness');
  if (s.state === 'readable') r.closedCapability.reject(e);
  else r.closedCapability = settledCapability(promiseRejectedWith(e));
  setPromiseIsHandled(r.closedCapability.promise);
  controllerReleaseSteps(s.controller);
  s.reader = undefined;
  r.stream = undefined;
}
function readerGenericCancel(reader, reason) { return readableStreamCancel(slotOf(reader).stream, reason); }

function ReadableStreamDefaultReader(stream) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'ReadableStreamDefaultReader': Please use the 'new' operator");
  required(arguments, 1, 'ReadableStreamDefaultReader');
  if (!isReadableStreamLike(stream)) throw new TypeError("Failed to construct 'ReadableStreamDefaultReader': parameter 1 is not of type 'ReadableStream'.");
  setUpDefaultReader(this, stream);
}
iface('ReadableStreamDefaultReader', ReadableStreamDefaultReader, null);
function setUpDefaultReader(reader, stream) {
  if (isReadableStreamLocked(stream)) throw new TypeError('This stream has already been locked for exclusive reading by another reader');
  setSlot(reader, { isDefaultReader: true, stream: undefined, readRequests: [], closedCapability: undefined });
  readerGenericInitialize(reader, stream);
}
function acquireReadableStreamDefaultReader(stream) {
  const reader = create(ReadableStreamDefaultReader.prototype);
  setUpDefaultReader(reader, stream);
  return reader;
}
function drSlot(o) { const s = slotOf(o); return s && s.isDefaultReader === true ? s : null; }
attributes(ReadableStreamDefaultReader.prototype, {
  closed: { get() { const s = drSlot(this); if (!s) return promiseRejectedWith(new TypeError('Illegal invocation')); return s.closedCapability.promise; } }
});
operations(ReadableStreamDefaultReader.prototype, {
  cancel(reason = undefined) {
    const s = drSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot cancel a stream using a released reader'));
    return readerGenericCancel(this, reason);
  },
  read() {
    const s = drSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot read from a released reader'));
    const cap = newPromiseCapability();
    readableStreamDefaultReaderRead(this, { chunkSteps: chunk => cap.resolve({ value: chunk, done: false }), closeSteps: () => cap.resolve({ value: undefined, done: true }), errorSteps: e => cap.reject(e) });
    return cap.promise;
  },
  releaseLock() {
    const s = drSlot(this);
    if (!s) throw new TypeError('Illegal invocation');
    if (s.stream === undefined) return;
    readableStreamDefaultReaderRelease(this);
  }
});
function readableStreamDefaultReaderRead(reader, rr) {
  const stream = slotOf(reader).stream, s = slotOf(stream);
  s.disturbed = true;
  if (s.state === 'closed') rr.closeSteps();
  else if (s.state === 'errored') rr.errorSteps(s.storedError);
  else controllerPullSteps(s.controller, rr);
}
function readableStreamDefaultReaderRelease(reader) {
  readerGenericRelease(reader);
  readableStreamDefaultReaderErrorReadRequests(reader, new TypeError('Reader was released'));
}
function readableStreamDefaultReaderErrorReadRequests(reader, e) {
  const r = slotOf(reader);
  const reqs = r.readRequests;
  r.readRequests = [];
  for (const rr of reqs) rr.errorSteps(e);
}

// --- ReadableStream methods

attributes(ReadableStream.prototype, {
  locked: { get() { rsSlot(this); return isReadableStreamLocked(this); } }
});
const asyncIteratorPrototype = Object.getPrototypeOf(Object.getPrototypeOf(async function* () {}).prototype);
const readableStreamAsyncIteratorPrototype = Object.create(asyncIteratorPrototype);
operations(ReadableStream.prototype, {
  cancel(reason = undefined) {
    if (!isReadableStreamLike(this)) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (isReadableStreamLocked(this)) return promiseRejectedWith(new TypeError('Cannot cancel a stream that already has a reader'));
    return readableStreamCancel(this, reason);
  },
  getReader(options = undefined) {
    rsSlot(this);
    let mode;
    if (options !== undefined && options !== null) {
      if (!isObject(options)) throw new TypeError("Failed to execute 'getReader' on 'ReadableStream': parameter 1 is not of type 'ReadableStreamGetReaderOptions'.");
      mode = options.mode;
    } else if (options === null) mode = undefined;
    if (mode === undefined) return acquireReadableStreamDefaultReader(this);
    if (String(mode) !== 'byob') throw new TypeError("The provided value '" + String(mode) + "' is not a valid enum value of type ReadableStreamReaderMode.");
    return acquireReadableStreamBYOBReader(this);
  },
  pipeThrough(transform, options = undefined) {
    rsSlot(this);
    required(arguments, 1, 'pipeThrough');
    if (!isObject(transform)) throw new TypeError("Failed to execute 'pipeThrough' on 'ReadableStream': parameter 1 is not of type 'ReadableWritablePair'.");
    const readable = transform.readable, writable = transform.writable;
    if (!isReadableStreamLike(readable)) throw new TypeError("Failed to execute 'pipeThrough' on 'ReadableStream': Failed to read the 'readable' property of the pair.");
    if (!isWritableStreamLike(writable)) throw new TypeError("Failed to execute 'pipeThrough' on 'ReadableStream': Failed to read the 'writable' property of the pair.");
    const opts = convertPipeOptions(options);
    if (isReadableStreamLocked(this)) throw new TypeError('ReadableStream.prototype.pipeThrough cannot be used on a locked ReadableStream');
    if (isWritableStreamLocked(writable)) throw new TypeError('ReadableStream.prototype.pipeThrough cannot be used on a locked WritableStream');
    const promise = readableStreamPipeTo(this, writable, opts.preventClose, opts.preventAbort, opts.preventCancel, opts.signal);
    setPromiseIsHandled(promise);
    return readable;
  },
  pipeTo(destination, options = undefined) {
    if (!isReadableStreamLike(this)) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (arguments.length < 1) return promiseRejectedWith(new TypeError("Failed to execute 'pipeTo' on 'ReadableStream': 1 argument required, but only 0 present."));
    if (!isWritableStreamLike(destination)) return promiseRejectedWith(new TypeError("Failed to execute 'pipeTo' on 'ReadableStream': parameter 1 is not of type 'WritableStream'."));
    let opts;
    try { opts = convertPipeOptions(options); } catch (e) { return promiseRejectedWith(e); }
    if (isReadableStreamLocked(this)) return promiseRejectedWith(new TypeError('ReadableStream.prototype.pipeTo cannot be used on a locked ReadableStream'));
    if (isWritableStreamLocked(destination)) return promiseRejectedWith(new TypeError('ReadableStream.prototype.pipeTo cannot be used on a locked WritableStream'));
    return readableStreamPipeTo(this, destination, opts.preventClose, opts.preventAbort, opts.preventCancel, opts.signal);
  },
  tee() { rsSlot(this); return readableStreamTee(this, false); },
  values(options = undefined) {
    rsSlot(this);
    let preventCancel = false;
    if (options !== undefined && options !== null) {
      if (!isObject(options)) throw new TypeError("Failed to execute 'values' on 'ReadableStream': parameter 1 is not of type 'ReadableStreamIteratorOptions'.");
      preventCancel = !!options.preventCancel;
    }
    const reader = acquireReadableStreamDefaultReader(this);
    const it = create(readableStreamAsyncIteratorPrototype);
    setSlot(it, { isRSIterator: true, reader, preventCancel, ongoingPromise: null, isFinished: false });
    return it;
  }
});
defineProperty(ReadableStream.prototype, Symbol.asyncIterator, { value: ReadableStream.prototype.values, writable: true, enumerable: false, configurable: true });
function convertPipeOptions(options) {
  const out = { preventAbort: false, preventCancel: false, preventClose: false, signal: undefined };
  if (options === undefined || options === null) return out;
  if (!isObject(options)) throw new TypeError('The options argument is not an object');
  out.preventAbort = !!options.preventAbort;
  out.preventCancel = !!options.preventCancel;
  out.preventClose = !!options.preventClose;
  const signal = options.signal;
  if (signal !== undefined) {
    if (!isObject(signal) || !slotOf(signal) || slotOf(signal).isSignal !== true && !(signal instanceof AbortSignal)) throw new TypeError("Failed to read the 'signal' property: the provided value is not of type 'AbortSignal'.");
    out.signal = signal;
  }
  return out;
}
defineMethod(ReadableStream, 'from', function from(asyncIterable) {
  required(arguments, 1, 'from');
  return readableStreamFromIterable(asyncIterable);
});
function defineMethod(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: true, configurable: true }); }
function defineHidden(o, k, v) { defineProperty(o, k, { value: v, writable: true, enumerable: false, configurable: true }); }

// async iterator
function rsIter(o) { const s = slotOf(o); if (!s || !s.isRSIterator) throw new TypeError('Illegal invocation'); return s; }
defineMethod(readableStreamAsyncIteratorPrototype, 'next', { next() {
  let s;
  try { s = rsIter(this); } catch (e) { return promiseRejectedWith(e); }
  const nextSteps = () => {
    if (s.isFinished) return promiseResolvedWith({ value: undefined, done: true });
    const cap = newPromiseCapability();
    readableStreamDefaultReaderRead(s.reader, {
      chunkSteps: chunk => { s.ongoingPromise = null; cap.resolve({ value: chunk, done: false }); },
      closeSteps: () => { s.ongoingPromise = null; s.isFinished = true; readableStreamDefaultReaderRelease(s.reader); cap.resolve({ value: undefined, done: true }); },
      errorSteps: e => { s.ongoingPromise = null; s.isFinished = true; readableStreamDefaultReaderRelease(s.reader); cap.reject(e); }
    });
    return cap.promise;
  };
  const ongoing = s.ongoingPromise;
  const result = ongoing !== null ? transformPromiseWith(ongoing, nextSteps, nextSteps) : nextSteps();
  s.ongoingPromise = result;
  return result;
} }.next);
defineMethod(readableStreamAsyncIteratorPrototype, 'return', { return(value = undefined) {
  let s;
  try { s = rsIter(this); } catch (e) { return promiseRejectedWith(e); }
  const returnSteps = () => {
    if (s.isFinished) return promiseResolvedWith({ value, done: true });
    s.isFinished = true;
    if (!s.preventCancel) {
      const result = readerGenericCancel(s.reader, value);
      readableStreamDefaultReaderRelease(s.reader);
      return transformPromiseWith(result, () => ({ value, done: true }), undefined);
    }
    readableStreamDefaultReaderRelease(s.reader);
    return promiseResolvedWith({ value, done: true });
  };
  const ongoing = s.ongoingPromise;
  const result = ongoing !== null ? transformPromiseWith(ongoing, returnSteps, returnSteps) : returnSteps();
  s.ongoingPromise = result;
  return result;
} }.return);

// ReadableStream.from
function readableStreamFromIterable(asyncIterable) {
  let iterator, nextMethod;
  const asyncMethod = asyncIterable == null ? undefined : asyncIterable[Symbol.asyncIterator];
  let isAsync = true;
  if (asyncMethod !== undefined && asyncMethod !== null) {
    if (typeof asyncMethod !== 'function') throw new TypeError('@@asyncIterator is not a function');
    iterator = apply(asyncMethod, asyncIterable, []);
  } else {
    const syncMethod = asyncIterable == null ? undefined : asyncIterable[Symbol.iterator];
    if (syncMethod === undefined || syncMethod === null || typeof syncMethod !== 'function') throw new TypeError('The object is not iterable');
    iterator = apply(syncMethod, asyncIterable, []);
    isAsync = false;
  }
  if (!isObject(iterator)) throw new TypeError('The iterator is not an object');
  nextMethod = iterator.next;
  let stream;
  const pullAlgorithm = () => {
    let nextResult;
    try { nextResult = apply(nextMethod, iterator, []); } catch (e) { return promiseRejectedWith(e); }
    let nextPromise;
    if (isAsync) nextPromise = promiseResolvedWith(nextResult);
    else {
      if (!isObject(nextResult)) return promiseRejectedWith(new TypeError('The iterator result is not an object'));
      const done = !!nextResult.done;
      let value;
      try { value = nextResult.value; } catch (e) { return promiseRejectedWith(e); }
      nextPromise = transformPromiseWith(promiseResolvedWith(value), v => ({ done, value: v }), undefined);
    }
    return transformPromiseWith(nextPromise, iterResult => {
      if (!isObject(iterResult)) throw new TypeError('The promise returned by the iterator.next() method must fulfill with an object');
      const done = !!iterResult.done;
      if (done) readableStreamDefaultControllerClose(slotOf(stream).controller);
      else readableStreamDefaultControllerEnqueue(slotOf(stream).controller, iterResult.value);
    }, undefined);
  };
  const cancelAlgorithm = reason => {
    let returnMethod;
    try { returnMethod = iterator.return; } catch (e) { return promiseRejectedWith(e); }
    if (returnMethod === undefined || returnMethod === null) return promiseResolvedWith(undefined);
    let returnResult;
    try { returnResult = apply(returnMethod, iterator, [reason]); } catch (e) { return promiseRejectedWith(e); }
    const returnPromise = promiseResolvedWith(returnResult);
    return transformPromiseWith(returnPromise, iterResult => { if (!isObject(iterResult)) throw new TypeError('The promise returned by the iterator.return() method must fulfill with an object'); }, undefined);
  };
  stream = createReadableStream(noop, pullAlgorithm, cancelAlgorithm, 0);
  return stream;
}

// --- tee

function readableStreamTee(stream, cloneForBranch2) {
  if (slotOf(slotOf(stream).controller).isDefaultController) return readableStreamDefaultTee(stream, cloneForBranch2);
  return readableByteStreamTee(stream);
}
function readableStreamDefaultTee(stream, cloneForBranch2) {
  const reader = acquireReadableStreamDefaultReader(stream);
  let reading = false, readAgain = false, canceled1 = false, canceled2 = false, reason1, reason2, branch1, branch2;
  const cancelCap = newPromiseCapability();
  const pullAlgorithm = () => {
    if (reading) { readAgain = true; return promiseResolvedWith(undefined); }
    reading = true;
    readableStreamDefaultReaderRead(reader, {
      chunkSteps: chunk => {
        queueMicrotaskStreams(() => {
          readAgain = false;
          let chunk1 = chunk, chunk2 = chunk;
          if (!canceled2 && cloneForBranch2) {
            try { chunk2 = structuredCloneImpl(chunk2); } catch (cloneError) {
              readableStreamDefaultControllerError(slotOf(branch1).controller, cloneError);
              readableStreamDefaultControllerError(slotOf(branch2).controller, cloneError);
              cancelCap.resolve(readableStreamCancel(stream, cloneError));
              return;
            }
          }
          if (!canceled1) readableStreamDefaultControllerEnqueue(slotOf(branch1).controller, chunk1);
          if (!canceled2) readableStreamDefaultControllerEnqueue(slotOf(branch2).controller, chunk2);
          reading = false;
          if (readAgain) pullAlgorithm();
        });
      },
      closeSteps: () => {
        reading = false;
        if (!canceled1) readableStreamDefaultControllerClose(slotOf(branch1).controller);
        if (!canceled2) readableStreamDefaultControllerClose(slotOf(branch2).controller);
        if (!canceled1 || !canceled2) cancelCap.resolve(undefined);
      },
      errorSteps: () => { reading = false; }
    });
    return promiseResolvedWith(undefined);
  };
  const cancel1Algorithm = reason => {
    canceled1 = true; reason1 = reason;
    if (canceled2) cancelCap.resolve(readableStreamCancel(stream, [reason1, reason2]));
    return cancelCap.promise;
  };
  const cancel2Algorithm = reason => {
    canceled2 = true; reason2 = reason;
    if (canceled1) cancelCap.resolve(readableStreamCancel(stream, [reason1, reason2]));
    return cancelCap.promise;
  };
  branch1 = createReadableStream(noop, pullAlgorithm, cancel1Algorithm);
  branch2 = createReadableStream(noop, pullAlgorithm, cancel2Algorithm);
  uponRejection(slotOf(reader).closedCapability.promise, r => {
    readableStreamDefaultControllerError(slotOf(branch1).controller, r);
    readableStreamDefaultControllerError(slotOf(branch2).controller, r);
    if (!canceled1 || !canceled2) cancelCap.resolve(undefined);
  });
  return [branch1, branch2];
}

// --- pipeTo

function readableStreamPipeTo(source, dest, preventClose, preventAbort, preventCancel, signal) {
  const reader = acquireReadableStreamDefaultReader(source);
  const writer = acquireWritableStreamDefaultWriter(dest);
  slotOf(source).disturbed = true;
  let shuttingDown = false;
  const cap = newPromiseCapability();
  let currentWrite = promiseResolvedWith(undefined);
  let abortAlgorithm;
  if (signal !== undefined) {
    abortAlgorithm = () => {
      const error = signal.reason;
      const actions = [];
      if (!preventAbort) actions.push(() => (slotOf(dest).state === 'writable' ? writableStreamAbort(dest, error) : promiseResolvedWith(undefined)));
      if (!preventCancel) actions.push(() => (slotOf(source).state === 'readable' ? readableStreamCancel(source, error) : promiseResolvedWith(undefined)));
      shutdownWithAction(() => Promise.all(actions.map(a => a())), true, error);
    };
    if (signal.aborted) { abortAlgorithm(); return cap.promise; }
    signal.addEventListener('abort', abortAlgorithm);
  }
  function pipeLoop() {
    return new Promise((resolveLoop, rejectLoop) => {
      function next(done) { if (done) resolveLoop(); else uponPromise(pipeStep(), next, rejectLoop); }
      next(false);
    });
  }
  function pipeStep() {
    if (shuttingDown) return promiseResolvedWith(true);
    return transformPromiseWith(slotOf(writer).readyCapability.promise, () => new Promise((resolveRead, rejectRead) => {
      readableStreamDefaultReaderRead(reader, {
        chunkSteps: chunk => { currentWrite = transformPromiseWith(writableStreamDefaultWriterWrite(writer, chunk), undefined, noop); resolveRead(false); },
        closeSteps: () => resolveRead(true),
        errorSteps: rejectRead
      });
    }), undefined);
  }
  function isOrBecomesErrored(stream, promise, action) {
    if (slotOf(stream).state === 'errored') action(slotOf(stream).storedError);
    else uponRejection(promise, action);
  }
  function isOrBecomesClosed(stream, promise, action) {
    if (slotOf(stream).state === 'closed') action();
    else uponFulfillment(promise, action);
  }
  function shutdownWithAction(action, originalIsError, originalError) {
    if (shuttingDown) return;
    shuttingDown = true;
    if (slotOf(dest).state === 'writable' && !writableStreamCloseQueuedOrInFlight(dest)) uponFulfillment(waitForWritesToFinish(), doTheRest);
    else doTheRest();
    function doTheRest() { uponPromise(action(), () => finalize(originalIsError, originalError), newError => finalize(true, newError)); }
  }
  function shutdown(isError, error) {
    if (shuttingDown) return;
    shuttingDown = true;
    if (slotOf(dest).state === 'writable' && !writableStreamCloseQueuedOrInFlight(dest)) uponFulfillment(waitForWritesToFinish(), () => finalize(isError, error));
    else finalize(isError, error);
  }
  function waitForWritesToFinish() {
    const oldCurrentWrite = currentWrite;
    return uponFulfillment(currentWrite, () => (oldCurrentWrite !== currentWrite ? waitForWritesToFinish() : undefined));
  }
  function finalize(isError, error) {
    writableStreamDefaultWriterRelease(writer);
    readableStreamDefaultReaderRelease(reader);
    if (signal !== undefined) signal.removeEventListener('abort', abortAlgorithm);
    if (isError) cap.reject(error); else cap.resolve(undefined);
  }
  isOrBecomesErrored(source, slotOf(reader).closedCapability.promise, storedError => {
    if (!preventAbort) shutdownWithAction(() => writableStreamAbort(dest, storedError), true, storedError);
    else shutdown(true, storedError);
  });
  isOrBecomesErrored(dest, slotOf(writer).closedCapability.promise, storedError => {
    if (!preventCancel) shutdownWithAction(() => readableStreamCancel(source, storedError), true, storedError);
    else shutdown(true, storedError);
  });
  isOrBecomesClosed(source, slotOf(reader).closedCapability.promise, () => {
    if (!preventClose) shutdownWithAction(() => writableStreamDefaultWriterCloseWithErrorPropagation(writer), false, undefined);
    else shutdown(false, undefined);
  });
  if (writableStreamCloseQueuedOrInFlight(dest) || slotOf(dest).state === 'closed') {
    const destClosed = new TypeError('the destination writable stream closed before all data could be piped to it');
    if (!preventCancel) shutdownWithAction(() => readableStreamCancel(source, destClosed), true, destClosed);
    else shutdown(true, destClosed);
  }
  setPromiseIsHandled(pipeLoop());
  return cap.promise;
}
