// Streams Standard: WritableStream, its default writer and default controller.

const closeSentinel = {};
function isWritableStreamLike(o) { return isObject(o) && slotOf(o) && slotOf(o).isWritableStream === true; }
function wsSlot(o) { const s = slotOf(o); if (!s || s.isWritableStream !== true) throw new TypeError('Illegal invocation'); return s; }

function WritableStream(underlyingSink = undefined, strategy = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'WritableStream': Please use the 'new' operator");
  const strat = convertQueuingStrategy(strategy, 'WritableStream strategy');
  let sink = underlyingSink;
  if (sink === undefined) sink = null;
  const dict = convertUnderlyingSink(sink);
  if (dict.hasType) throw new RangeError('Invalid type is specified');
  initializeWritableStream(this);
  const sizeAlgorithm = extractSizeAlgorithm(strat);
  const hwm = extractHighWaterMark(strat, 1);
  setUpWritableStreamDefaultControllerFromUnderlyingSink(this, sink, dict, hwm, sizeAlgorithm);
}
iface('WritableStream', WritableStream, null);
function convertUnderlyingSink(sink) {
  const dict = {};
  if (sink === null) return dict;
  if (!isObject(sink)) throw new TypeError('The underlying sink is not an object.');
  for (const name of ['abort', 'close', 'start']) {
    const v = sink[name];
    if (v !== undefined) {
      if (typeof v !== 'function') throw new TypeError('The underlying sink ' + name + ' is not a function.');
      dict[name] = v;
    }
  }
  if (sink.type !== undefined) dict.hasType = true;
  const w = sink.write;
  if (w !== undefined) {
    if (typeof w !== 'function') throw new TypeError('The underlying sink write is not a function.');
    dict.write = w;
  }
  return dict;
}
function initializeWritableStream(stream) {
  setSlot(stream, { isWritableStream: true, state: 'writable', storedError: undefined, writer: undefined, controller: undefined, inFlightWriteRequest: undefined, closeRequest: undefined, inFlightCloseRequest: undefined, pendingAbortRequest: undefined, writeRequests: [], backpressure: false });
}
function isWritableStreamLocked(stream) { return slotOf(stream).writer !== undefined; }
attributes(WritableStream.prototype, {
  locked: { get() { wsSlot(this); return isWritableStreamLocked(this); } }
});
operations(WritableStream.prototype, {
  abort(reason = undefined) {
    if (!isWritableStreamLike(this)) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (isWritableStreamLocked(this)) return promiseRejectedWith(new TypeError('Cannot abort a stream that already has a writer'));
    return writableStreamAbort(this, reason);
  },
  close() {
    if (!isWritableStreamLike(this)) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (isWritableStreamLocked(this)) return promiseRejectedWith(new TypeError('Cannot close a stream that already has a writer'));
    if (writableStreamCloseQueuedOrInFlight(this)) return promiseRejectedWith(new TypeError('Cannot close an already-closing stream'));
    return writableStreamClose(this);
  },
  getWriter() { wsSlot(this); return acquireWritableStreamDefaultWriter(this); }
});

// --- stream-level operations

function writableStreamAbort(stream, reason) {
  const s = slotOf(stream);
  if (s.state === 'closed' || s.state === 'errored') return promiseResolvedWith(undefined);
  slotOf(s.controller).abortController.abort(reason);
  const state = s.state;
  if (state === 'closed' || state === 'errored') return promiseResolvedWith(undefined);
  if (s.pendingAbortRequest !== undefined) return s.pendingAbortRequest.promise;
  let wasAlreadyErroring = false;
  if (state === 'erroring') { wasAlreadyErroring = true; reason = undefined; }
  const cap = newPromiseCapability();
  s.pendingAbortRequest = { promise: cap.promise, resolve: cap.resolve, reject: cap.reject, reason, wasAlreadyErroring };
  if (!wasAlreadyErroring) writableStreamStartErroring(stream, reason);
  return cap.promise;
}
function writableStreamClose(stream) {
  const s = slotOf(stream);
  const state = s.state;
  if (state === 'closed' || state === 'errored') return promiseRejectedWith(new TypeError('The stream (in ' + state + ' state) is not in the writable state and cannot be closed'));
  const cap = newPromiseCapability();
  s.closeRequest = cap;
  const writer = s.writer;
  if (writer !== undefined && s.backpressure && state === 'writable') slotOf(writer).readyCapability.resolve(undefined);
  writableStreamDefaultControllerClose(s.controller);
  return cap.promise;
}
function writableStreamAddWriteRequest(stream) {
  const cap = newPromiseCapability();
  apply(arrayPush, slotOf(stream).writeRequests, [cap]);
  return cap.promise;
}
function writableStreamDealWithRejection(stream, error) {
  const state = slotOf(stream).state;
  if (state === 'writable') { writableStreamStartErroring(stream, error); return; }
  writableStreamFinishErroring(stream);
}
function writableStreamStartErroring(stream, reason) {
  const s = slotOf(stream), controller = s.controller;
  s.state = 'erroring';
  s.storedError = reason;
  const writer = s.writer;
  if (writer !== undefined) writableStreamDefaultWriterEnsureReadyPromiseRejected(writer, reason);
  if (!writableStreamHasOperationMarkedInFlight(stream) && slotOf(controller).started) writableStreamFinishErroring(stream);
}
function writableStreamFinishErroring(stream) {
  const s = slotOf(stream);
  s.state = 'errored';
  writableStreamDefaultControllerErrorSteps(s.controller);
  const storedError = s.storedError;
  for (const wr of s.writeRequests) wr.reject(storedError);
  s.writeRequests = [];
  if (s.pendingAbortRequest === undefined) { writableStreamRejectCloseAndClosedPromiseIfNeeded(stream); return; }
  const abortRequest = s.pendingAbortRequest;
  s.pendingAbortRequest = undefined;
  if (abortRequest.wasAlreadyErroring) {
    abortRequest.reject(storedError);
    writableStreamRejectCloseAndClosedPromiseIfNeeded(stream);
    return;
  }
  const promise = writableStreamDefaultControllerAbortSteps(s.controller, abortRequest.reason);
  uponPromise(promise, () => { abortRequest.resolve(undefined); writableStreamRejectCloseAndClosedPromiseIfNeeded(stream); }, reason => { abortRequest.reject(reason); writableStreamRejectCloseAndClosedPromiseIfNeeded(stream); });
}
function writableStreamFinishInFlightWrite(stream) {
  const s = slotOf(stream);
  s.inFlightWriteRequest.resolve(undefined);
  s.inFlightWriteRequest = undefined;
}
function writableStreamFinishInFlightWriteWithError(stream, error) {
  const s = slotOf(stream);
  s.inFlightWriteRequest.reject(error);
  s.inFlightWriteRequest = undefined;
  writableStreamDealWithRejection(stream, error);
}
function writableStreamFinishInFlightClose(stream) {
  const s = slotOf(stream);
  s.inFlightCloseRequest.resolve(undefined);
  s.inFlightCloseRequest = undefined;
  if (s.state === 'erroring') {
    s.storedError = undefined;
    if (s.pendingAbortRequest !== undefined) { s.pendingAbortRequest.resolve(undefined); s.pendingAbortRequest = undefined; }
  }
  s.state = 'closed';
  const writer = s.writer;
  if (writer !== undefined) slotOf(writer).closedCapability.resolve(undefined);
}
function writableStreamFinishInFlightCloseWithError(stream, error) {
  const s = slotOf(stream);
  s.inFlightCloseRequest.reject(error);
  s.inFlightCloseRequest = undefined;
  if (s.pendingAbortRequest !== undefined) { s.pendingAbortRequest.reject(error); s.pendingAbortRequest = undefined; }
  writableStreamDealWithRejection(stream, error);
}
function writableStreamCloseQueuedOrInFlight(stream) { const s = slotOf(stream); return s.closeRequest !== undefined || s.inFlightCloseRequest !== undefined; }
function writableStreamHasOperationMarkedInFlight(stream) { const s = slotOf(stream); return s.inFlightWriteRequest !== undefined || s.inFlightCloseRequest !== undefined; }
function writableStreamMarkCloseRequestInFlight(stream) { const s = slotOf(stream); s.inFlightCloseRequest = s.closeRequest; s.closeRequest = undefined; }
function writableStreamMarkFirstWriteRequestInFlight(stream) { const s = slotOf(stream); s.inFlightWriteRequest = s.writeRequests.shift(); }
function writableStreamRejectCloseAndClosedPromiseIfNeeded(stream) {
  const s = slotOf(stream);
  if (s.closeRequest !== undefined) { s.closeRequest.reject(s.storedError); s.closeRequest = undefined; }
  const writer = s.writer;
  if (writer !== undefined) { slotOf(writer).closedCapability.reject(s.storedError); setPromiseIsHandled(slotOf(writer).closedCapability.promise); }
}
function writableStreamUpdateBackpressure(stream, backpressure) {
  const s = slotOf(stream), writer = s.writer;
  if (writer !== undefined && backpressure !== s.backpressure) {
    if (backpressure) slotOf(writer).readyCapability = newPromiseCapability();
    else slotOf(writer).readyCapability.resolve(undefined);
  }
  s.backpressure = backpressure;
}

// --- writer

function WritableStreamDefaultWriter(stream) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'WritableStreamDefaultWriter': Please use the 'new' operator");
  required(arguments, 1, 'WritableStreamDefaultWriter');
  if (!isWritableStreamLike(stream)) throw new TypeError("Failed to construct 'WritableStreamDefaultWriter': parameter 1 is not of type 'WritableStream'.");
  setUpWritableStreamDefaultWriter(this, stream);
}
iface('WritableStreamDefaultWriter', WritableStreamDefaultWriter, null);
function setUpWritableStreamDefaultWriter(writer, stream) {
  if (isWritableStreamLocked(stream)) throw new TypeError('This stream has already been locked for exclusive writing by another writer');
  const w = setSlot(writer, { isWriter: true, stream, readyCapability: undefined, closedCapability: undefined });
  slotOf(stream).writer = writer;
  const state = slotOf(stream).state;
  if (state === 'writable') {
    if (!writableStreamCloseQueuedOrInFlight(stream) && slotOf(stream).backpressure) w.readyCapability = newPromiseCapability();
    else w.readyCapability = settledCapability(promiseResolvedWith(undefined));
    w.closedCapability = newPromiseCapability();
  } else if (state === 'erroring') {
    w.readyCapability = settledCapability(promiseRejectedWith(slotOf(stream).storedError));
    setPromiseIsHandled(w.readyCapability.promise);
    w.closedCapability = newPromiseCapability();
  } else if (state === 'closed') {
    w.readyCapability = settledCapability(promiseResolvedWith(undefined));
    w.closedCapability = settledCapability(promiseResolvedWith(undefined));
  } else {
    const storedError = slotOf(stream).storedError;
    w.readyCapability = settledCapability(promiseRejectedWith(storedError));
    setPromiseIsHandled(w.readyCapability.promise);
    w.closedCapability = settledCapability(promiseRejectedWith(storedError));
    setPromiseIsHandled(w.closedCapability.promise);
  }
}
function acquireWritableStreamDefaultWriter(stream) {
  const writer = create(WritableStreamDefaultWriter.prototype);
  setUpWritableStreamDefaultWriter(writer, stream);
  return writer;
}
function wwSlot(o) { const s = slotOf(o); return s && s.isWriter === true ? s : null; }
attributes(WritableStreamDefaultWriter.prototype, {
  closed: { get() { const s = wwSlot(this); if (!s) return promiseRejectedWith(new TypeError('Illegal invocation')); return s.closedCapability.promise; } },
  desiredSize: { get() {
    const s = wwSlot(this);
    if (!s) throw new TypeError('Illegal invocation');
    if (s.stream === undefined) throw new TypeError('The writer has been released');
    return writableStreamDefaultWriterGetDesiredSize(this);
  } },
  ready: { get() { const s = wwSlot(this); if (!s) return promiseRejectedWith(new TypeError('Illegal invocation')); return s.readyCapability.promise; } }
});
operations(WritableStreamDefaultWriter.prototype, {
  abort(reason = undefined) {
    const s = wwSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot abort a stream using a released writer'));
    return writableStreamAbort(s.stream, reason);
  },
  close() {
    const s = wwSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot close a stream using a released writer'));
    if (writableStreamCloseQueuedOrInFlight(s.stream)) return promiseRejectedWith(new TypeError('Cannot close an already-closing stream'));
    return writableStreamClose(s.stream);
  },
  releaseLock() {
    const s = wwSlot(this);
    if (!s) throw new TypeError('Illegal invocation');
    if (s.stream === undefined) return;
    writableStreamDefaultWriterRelease(this);
  },
  write(chunk = undefined) {
    const s = wwSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot write to a stream using a released writer'));
    return writableStreamDefaultWriterWrite(this, chunk);
  }
});
function writableStreamDefaultWriterCloseWithErrorPropagation(writer) {
  const w = slotOf(writer), stream = w.stream, s = slotOf(stream);
  if (writableStreamCloseQueuedOrInFlight(stream) || s.state === 'closed') return promiseResolvedWith(undefined);
  if (s.state === 'errored') return promiseRejectedWith(s.storedError);
  return writableStreamClose(stream);
}
function writableStreamDefaultWriterEnsureClosedPromiseRejected(writer, error) {
  const w = slotOf(writer);
  if (!w.closedCapability.settled) w.closedCapability.reject(error);
  else w.closedCapability = settledCapability(promiseRejectedWith(error));
  setPromiseIsHandled(w.closedCapability.promise);
}
function writableStreamDefaultWriterEnsureReadyPromiseRejected(writer, error) {
  const w = slotOf(writer);
  if (!w.readyCapability.settled) w.readyCapability.reject(error);
  else w.readyCapability = settledCapability(promiseRejectedWith(error));
  setPromiseIsHandled(w.readyCapability.promise);
}
function writableStreamDefaultWriterGetDesiredSize(writer) {
  const stream = slotOf(writer).stream, state = slotOf(stream).state;
  if (state === 'errored' || state === 'erroring') return null;
  if (state === 'closed') return 0;
  return writableStreamDefaultControllerGetDesiredSize(slotOf(stream).controller);
}
function writableStreamDefaultWriterRelease(writer) {
  const w = slotOf(writer), stream = w.stream;
  const releasedError = new TypeError('Writer was released and can no longer be used to monitor the stream\'s closedness');
  writableStreamDefaultWriterEnsureReadyPromiseRejected(writer, releasedError);
  writableStreamDefaultWriterEnsureClosedPromiseRejected(writer, releasedError);
  slotOf(stream).writer = undefined;
  w.stream = undefined;
}
function writableStreamDefaultWriterWrite(writer, chunk) {
  const w = slotOf(writer), stream = w.stream, s = slotOf(stream), controller = s.controller;
  const chunkSize = writableStreamDefaultControllerGetChunkSize(controller, chunk);
  if (stream !== w.stream) return promiseRejectedWith(new TypeError('Cannot write to a stream using a released writer'));
  const state = s.state;
  if (state === 'errored') return promiseRejectedWith(s.storedError);
  if (writableStreamCloseQueuedOrInFlight(stream) || state === 'closed') return promiseRejectedWith(new TypeError('The stream is closing or closed and cannot be written to'));
  if (state === 'erroring') return promiseRejectedWith(s.storedError);
  const promise = writableStreamAddWriteRequest(stream);
  writableStreamDefaultControllerWrite(controller, chunk, chunkSize);
  return promise;
}

// --- controller

function WritableStreamDefaultController() { throw new TypeError('Illegal constructor'); }
iface('WritableStreamDefaultController', WritableStreamDefaultController, null);
function wdcSlot(o) { const s = slotOf(o); if (!s || s.isWritableController !== true) throw new TypeError('Illegal invocation'); return s; }
attributes(WritableStreamDefaultController.prototype, {
  signal: { get() { return wdcSlot(this).abortController.signal; } }
});
operations(WritableStreamDefaultController.prototype, {
  error(e = undefined) {
    const c = wdcSlot(this);
    if (slotOf(c.stream).state !== 'writable') return;
    writableStreamDefaultControllerError(this, e);
  }
});
function setUpWritableStreamDefaultController(stream, startAlgorithm, writeAlgorithm, closeAlgorithm, abortAlgorithm, hwm, sizeAlgorithm) {
  const controller = create(WritableStreamDefaultController.prototype);
  const c = setSlot(controller, { isWritableController: true, stream, queue: [], queueTotalSize: 0, abortController: new AbortController(), started: false, strategySizeAlgorithm: sizeAlgorithm, strategyHWM: hwm, writeAlgorithm, closeAlgorithm, abortAlgorithm });
  slotOf(stream).controller = controller;
  const backpressure = writableStreamDefaultControllerGetBackpressure(controller);
  writableStreamUpdateBackpressure(stream, backpressure);
  const startResult = startAlgorithm(controller);
  uponPromise(promiseResolvedWith(startResult), () => {
    c.started = true;
    writableStreamDefaultControllerAdvanceQueueIfNeeded(controller);
  }, r => {
    c.started = true;
    writableStreamDealWithRejection(stream, r);
  });
}
function setUpWritableStreamDefaultControllerFromUnderlyingSink(stream, sink, dict, hwm, sizeAlgorithm) {
  const startAlgorithm = controller => (dict.start ? apply(dict.start, sink, [controller]) : undefined);
  const writeAlgorithm = chunk => (dict.write ? promiseCallStreams(dict.write, sink, [chunk, slotOf(stream).controller]) : promiseResolvedWith(undefined));
  const closeAlgorithm = () => (dict.close ? promiseCallStreams(dict.close, sink, []) : promiseResolvedWith(undefined));
  const abortAlgorithm = reason => (dict.abort ? promiseCallStreams(dict.abort, sink, [reason]) : promiseResolvedWith(undefined));
  setUpWritableStreamDefaultController(stream, startAlgorithm, writeAlgorithm, closeAlgorithm, abortAlgorithm, hwm, sizeAlgorithm);
}
function createWritableStream(startAlgorithm, writeAlgorithm, closeAlgorithm, abortAlgorithm, hwm = 1, sizeAlgorithm = () => 1) {
  const stream = create(WritableStream.prototype);
  initializeWritableStream(stream);
  setUpWritableStreamDefaultController(stream, startAlgorithm, writeAlgorithm, closeAlgorithm, abortAlgorithm, hwm, sizeAlgorithm);
  return stream;
}
function writableStreamDefaultControllerClearAlgorithms(controller) {
  const c = slotOf(controller);
  c.writeAlgorithm = undefined; c.closeAlgorithm = undefined; c.abortAlgorithm = undefined; c.strategySizeAlgorithm = undefined;
}
function writableStreamDefaultControllerClose(controller) {
  enqueueValueWithSize(slotOf(controller), closeSentinel, 0);
  writableStreamDefaultControllerAdvanceQueueIfNeeded(controller);
}
function writableStreamDefaultControllerGetChunkSize(controller, chunk) {
  const c = slotOf(controller);
  if (c.strategySizeAlgorithm === undefined) return 1;
  try { return c.strategySizeAlgorithm(chunk); } catch (e) { writableStreamDefaultControllerErrorIfNeeded(controller, e); return 1; }
}
function writableStreamDefaultControllerGetDesiredSize(controller) { const c = slotOf(controller); return c.strategyHWM - c.queueTotalSize; }
function writableStreamDefaultControllerWrite(controller, chunk, chunkSize) {
  const c = slotOf(controller);
  try { enqueueValueWithSize(c, chunk, chunkSize); } catch (e) { writableStreamDefaultControllerErrorIfNeeded(controller, e); return; }
  const stream = c.stream;
  if (!writableStreamCloseQueuedOrInFlight(stream) && slotOf(stream).state === 'writable') {
    writableStreamUpdateBackpressure(stream, writableStreamDefaultControllerGetBackpressure(controller));
  }
  writableStreamDefaultControllerAdvanceQueueIfNeeded(controller);
}
function writableStreamDefaultControllerAdvanceQueueIfNeeded(controller) {
  const c = slotOf(controller), stream = c.stream, s = slotOf(stream);
  if (!c.started) return;
  if (s.inFlightWriteRequest !== undefined) return;
  const state = s.state;
  if (state === 'erroring') { writableStreamFinishErroring(stream); return; }
  if (c.queue.length === 0) return;
  const value = peekQueueValue(c);
  if (value === closeSentinel) writableStreamDefaultControllerProcessClose(controller);
  else writableStreamDefaultControllerProcessWrite(controller, value);
}
function writableStreamDefaultControllerErrorIfNeeded(controller, error) {
  if (slotOf(slotOf(controller).stream).state === 'writable') writableStreamDefaultControllerError(controller, error);
}
function writableStreamDefaultControllerProcessClose(controller) {
  const c = slotOf(controller), stream = c.stream;
  writableStreamMarkCloseRequestInFlight(stream);
  dequeueValue(c);
  const sinkClosePromise = c.closeAlgorithm();
  writableStreamDefaultControllerClearAlgorithms(controller);
  uponPromise(sinkClosePromise, () => writableStreamFinishInFlightClose(stream), reason => writableStreamFinishInFlightCloseWithError(stream, reason));
}
function writableStreamDefaultControllerProcessWrite(controller, chunk) {
  const c = slotOf(controller), stream = c.stream;
  writableStreamMarkFirstWriteRequestInFlight(stream);
  const sinkWritePromise = c.writeAlgorithm(chunk);
  uponPromise(sinkWritePromise, () => {
    writableStreamFinishInFlightWrite(stream);
    const state = slotOf(stream).state;
    dequeueValue(c);
    if (!writableStreamCloseQueuedOrInFlight(stream) && state === 'writable') writableStreamUpdateBackpressure(stream, writableStreamDefaultControllerGetBackpressure(controller));
    writableStreamDefaultControllerAdvanceQueueIfNeeded(controller);
  }, reason => {
    if (slotOf(stream).state === 'writable') writableStreamDefaultControllerClearAlgorithms(controller);
    writableStreamFinishInFlightWriteWithError(stream, reason);
  });
}
function writableStreamDefaultControllerGetBackpressure(controller) { return writableStreamDefaultControllerGetDesiredSize(controller) <= 0; }
function writableStreamDefaultControllerError(controller, error) {
  const stream = slotOf(controller).stream;
  writableStreamDefaultControllerClearAlgorithms(controller);
  writableStreamStartErroring(stream, error);
}
function writableStreamDefaultControllerAbortSteps(controller, reason) {
  const c = slotOf(controller);
  const result = c.abortAlgorithm(reason);
  writableStreamDefaultControllerClearAlgorithms(controller);
  return result;
}
function writableStreamDefaultControllerErrorSteps(controller) { resetQueue(slotOf(controller)); }
