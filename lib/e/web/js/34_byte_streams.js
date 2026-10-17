// Streams Standard: byte streams (ReadableByteStreamController, ReadableStreamBYOBRequest, ReadableStreamBYOBReader).

function ReadableByteStreamController() { throw new TypeError('Illegal constructor'); }
iface('ReadableByteStreamController', ReadableByteStreamController, null);
function ReadableStreamBYOBRequest() { throw new TypeError('Illegal constructor'); }
iface('ReadableStreamBYOBRequest', ReadableStreamBYOBRequest, null);
function rbcSlot(o) { const s = slotOf(o); if (!s || s.isByteController !== true) throw new TypeError('Illegal invocation'); return s; }
function byobReqSlot(o) { const s = slotOf(o); if (!s || s.isBYOBRequest !== true) throw new TypeError('Illegal invocation'); return s; }

attributes(ReadableByteStreamController.prototype, {
  byobRequest: { get() { rbcSlot(this); return readableByteStreamControllerGetBYOBRequest(this); } },
  desiredSize: { get() { rbcSlot(this); return readableByteStreamControllerGetDesiredSize(this); } }
});
operations(ReadableByteStreamController.prototype, {
  close() {
    const c = rbcSlot(this);
    if (c.closeRequested) throw new TypeError('The stream has already been closed; do not close it again!');
    if (slotOf(c.stream).state !== 'readable') throw new TypeError('The stream (in ' + slotOf(c.stream).state + ' state) is not in the readable state and cannot be closed');
    readableByteStreamControllerClose(this);
  },
  enqueue(chunk) {
    const c = rbcSlot(this);
    required(arguments, 1, 'enqueue');
    if (viewKind(chunk) === null) throw new TypeError('chunk must be an array buffer view');
    if (viewByteLength(chunk) === 0) throw new TypeError('chunk must have non-zero byteLength');
    if (apply(abByteLengthGetter, viewBuffer(chunk), []) === 0) throw new TypeError('chunk\'s buffer must have non-zero byteLength');
    if (c.closeRequested) throw new TypeError('stream is closed or draining');
    if (slotOf(c.stream).state !== 'readable') throw new TypeError('The stream (in ' + slotOf(c.stream).state + ' state) is not in the readable state and cannot be enqueued to');
    readableByteStreamControllerEnqueue(this, chunk);
  },
  error(e = undefined) { rbcSlot(this); readableByteStreamControllerError(this, e); }
});
attributes(ReadableStreamBYOBRequest.prototype, {
  view: { get() { return byobReqSlot(this).view; } }
});
operations(ReadableStreamBYOBRequest.prototype, {
  respond(bytesWritten) {
    const r = byobReqSlot(this);
    required(arguments, 1, 'respond');
    const n = enforceRangeUnsignedLongLong(bytesWritten, 'bytesWritten');
    if (r.controller === undefined) throw new TypeError('This BYOB request has been invalidated');
    if (isDetachedBuffer(viewBuffer(r.view))) throw new TypeError('The BYOB request\'s buffer has been detached and so cannot be used as a response');
    readableByteStreamControllerRespond(r.controller, n);
  },
  respondWithNewView(view) {
    const r = byobReqSlot(this);
    required(arguments, 1, 'respondWithNewView');
    if (viewKind(view) === null) throw new TypeError('You can only respond with array buffer views');
    if (r.controller === undefined) throw new TypeError('This BYOB request has been invalidated');
    if (isDetachedBuffer(viewBuffer(view))) throw new TypeError('The given view\'s buffer has been detached and so cannot be used as a response');
    readableByteStreamControllerRespondWithNewView(r.controller, view);
  }
});
function enforceRangeUnsignedLongLong(v, name) {
  const n = Number(v);
  if (n !== n || n === Infinity || n === -Infinity) throw new TypeError(name + ' is not a finite number');
  const t = Math.trunc(n);
  if (t < 0 || t > 9007199254740991) throw new TypeError(name + ' is out of range');
  return t;
}

// --- internal operations

function readableByteStreamControllerCallPullIfNeeded(controller) {
  const c = slotOf(controller);
  if (!readableByteStreamControllerShouldCallPull(controller)) return;
  if (c.pulling) { c.pullAgain = true; return; }
  c.pulling = true;
  const pullPromise = c.pullAlgorithm();
  uponPromise(pullPromise, () => {
    c.pulling = false;
    if (c.pullAgain) { c.pullAgain = false; readableByteStreamControllerCallPullIfNeeded(controller); }
  }, e => readableByteStreamControllerError(controller, e));
}
function readableByteStreamControllerClearAlgorithms(controller) { const c = slotOf(controller); c.pullAlgorithm = undefined; c.cancelAlgorithm = undefined; }
function readableByteStreamControllerError(controller, e) {
  const c = slotOf(controller), stream = c.stream;
  if (slotOf(stream).state !== 'readable') return;
  readableByteStreamControllerClearPendingPullIntos(controller);
  resetQueue(c);
  readableByteStreamControllerClearAlgorithms(controller);
  readableStreamError(stream, e);
}
function readableByteStreamControllerClearPendingPullIntos(controller) {
  readableByteStreamControllerInvalidateBYOBRequest(controller);
  slotOf(controller).pendingPullIntos = [];
}
function readableByteStreamControllerInvalidateBYOBRequest(controller) {
  const c = slotOf(controller);
  if (c.byobRequest === null) return;
  const r = slotOf(c.byobRequest);
  r.controller = undefined;
  r.view = null;
  c.byobRequest = null;
}
function readableStreamHasDefaultReader(stream) { const r = slotOf(stream).reader; return r !== undefined && slotOf(r).isDefaultReader === true; }
function readableStreamHasBYOBReader(stream) { const r = slotOf(stream).reader; return r !== undefined && slotOf(r).isBYOBReader === true; }
function readableStreamGetNumReadIntoRequests(stream) { return slotOf(slotOf(stream).reader).readIntoRequests.length; }
function readableByteStreamControllerShouldCallPull(controller) {
  const c = slotOf(controller), stream = c.stream;
  if (slotOf(stream).state !== 'readable') return false;
  if (c.closeRequested) return false;
  if (!c.started) return false;
  if (readableStreamHasDefaultReader(stream) && readableStreamGetNumReadRequests(stream) > 0) return true;
  if (readableStreamHasBYOBReader(stream) && readableStreamGetNumReadIntoRequests(stream) > 0) return true;
  return readableByteStreamControllerGetDesiredSize(controller) > 0;
}
function readableByteStreamControllerGetDesiredSize(controller) {
  const c = slotOf(controller), state = slotOf(c.stream).state;
  if (state === 'errored') return null;
  if (state === 'closed') return 0;
  return c.strategyHWM - c.queueTotalSize;
}
function readableByteStreamControllerClose(controller) {
  const c = slotOf(controller), stream = c.stream;
  if (c.closeRequested || slotOf(stream).state !== 'readable') return;
  if (c.queueTotalSize > 0) { c.closeRequested = true; return; }
  if (c.pendingPullIntos.length > 0) {
    const first = c.pendingPullIntos[0];
    if (first.bytesFilled % first.elementSize !== 0) {
      const e = new TypeError('Insufficient bytes to fill elements in the given buffer');
      readableByteStreamControllerError(controller, e);
      throw e;
    }
  }
  readableByteStreamControllerClearAlgorithms(controller);
  readableStreamClose(stream);
}
function cloneArrayBuffer(buffer, byteOffset, byteLength) { return apply(ArrayBuffer.prototype.slice, buffer, [byteOffset, byteOffset + byteLength]); }
function readableByteStreamControllerEnqueue(controller, chunk) {
  const c = slotOf(controller), stream = c.stream;
  if (c.closeRequested || slotOf(stream).state !== 'readable') return;
  const buffer = viewBuffer(chunk), byteOffset = viewByteOffset(chunk), byteLength = viewByteLength(chunk);
  if (isDetachedBuffer(buffer)) throw new TypeError('chunk\'s buffer is detached and so cannot be enqueued');
  const transferredBuffer = transferArrayBuffer(buffer);
  if (c.pendingPullIntos.length > 0) {
    const first = c.pendingPullIntos[0];
    if (isDetachedBuffer(first.buffer)) throw new TypeError('The BYOB request\'s buffer has been detached and so cannot be filled with an enqueued chunk');
    readableByteStreamControllerInvalidateBYOBRequest(controller);
    first.buffer = transferArrayBuffer(first.buffer);
    if (first.readerType === 'none') readableByteStreamControllerEnqueueDetachedPullIntoToQueue(controller, first);
  }
  if (readableStreamHasDefaultReader(stream)) {
    readableByteStreamControllerProcessReadRequestsUsingQueue(controller);
    if (readableStreamGetNumReadRequests(stream) === 0) {
      readableByteStreamControllerEnqueueChunkToQueue(controller, transferredBuffer, byteOffset, byteLength);
    } else {
      if (c.pendingPullIntos.length > 0) readableByteStreamControllerShiftPendingPullInto(controller);
      readableStreamFulfillReadRequest(stream, new Uint8Array(transferredBuffer, byteOffset, byteLength), false);
    }
  } else if (readableStreamHasBYOBReader(stream)) {
    readableByteStreamControllerEnqueueChunkToQueue(controller, transferredBuffer, byteOffset, byteLength);
    readableByteStreamControllerProcessPullIntoDescriptorsUsingQueue(controller);
  } else {
    readableByteStreamControllerEnqueueChunkToQueue(controller, transferredBuffer, byteOffset, byteLength);
  }
  readableByteStreamControllerCallPullIfNeeded(controller);
}
function readableByteStreamControllerEnqueueChunkToQueue(controller, buffer, byteOffset, byteLength) {
  const c = slotOf(controller);
  apply(arrayPush, c.queue, [{ buffer, byteOffset, byteLength }]);
  c.queueTotalSize += byteLength;
}
function readableByteStreamControllerEnqueueClonedChunkToQueue(controller, buffer, byteOffset, byteLength) {
  let clone;
  try { clone = cloneArrayBuffer(buffer, byteOffset, byteLength); } catch (e) { readableByteStreamControllerError(controller, e); throw e; }
  readableByteStreamControllerEnqueueChunkToQueue(controller, clone, 0, byteLength);
}
function readableByteStreamControllerEnqueueDetachedPullIntoToQueue(controller, desc) {
  if (desc.bytesFilled > 0) readableByteStreamControllerEnqueueClonedChunkToQueue(controller, desc.buffer, desc.byteOffset, desc.bytesFilled);
  readableByteStreamControllerShiftPendingPullInto(controller);
}
function readableByteStreamControllerFillPullIntoDescriptorFromQueue(controller, desc) {
  const c = slotOf(controller);
  const maxBytesToCopy = Math.min(c.queueTotalSize, desc.byteLength - desc.bytesFilled);
  const maxBytesFilled = desc.bytesFilled + maxBytesToCopy;
  let totalBytesToCopyRemaining = maxBytesToCopy;
  let ready = false;
  const remainderBytes = maxBytesFilled % desc.elementSize;
  const maxAlignedBytes = maxBytesFilled - remainderBytes;
  if (maxAlignedBytes >= desc.minimumFill) { totalBytesToCopyRemaining = maxAlignedBytes - desc.bytesFilled; ready = true; }
  const queue = c.queue;
  while (totalBytesToCopyRemaining > 0) {
    const head = queue[0];
    const bytesToCopy = Math.min(totalBytesToCopyRemaining, head.byteLength);
    const destStart = desc.byteOffset + desc.bytesFilled;
    const dest = new Uint8Array(desc.buffer, destStart, bytesToCopy);
    dest.set(new Uint8Array(head.buffer, head.byteOffset, bytesToCopy));
    if (head.byteLength === bytesToCopy) queue.shift();
    else { head.byteOffset += bytesToCopy; head.byteLength -= bytesToCopy; }
    c.queueTotalSize -= bytesToCopy;
    readableByteStreamControllerFillHeadPullIntoDescriptor(controller, bytesToCopy, desc);
    totalBytesToCopyRemaining -= bytesToCopy;
  }
  return ready;
}
function readableByteStreamControllerFillHeadPullIntoDescriptor(controller, size, desc) {
  readableByteStreamControllerInvalidateBYOBRequest(controller);
  desc.bytesFilled += size;
}
function readableByteStreamControllerProcessPullIntoDescriptorsUsingQueue(controller) {
  const c = slotOf(controller);
  while (c.pendingPullIntos.length > 0) {
    if (c.queueTotalSize === 0) return;
    const desc = c.pendingPullIntos[0];
    if (readableByteStreamControllerFillPullIntoDescriptorFromQueue(controller, desc)) {
      readableByteStreamControllerShiftPendingPullInto(controller);
      readableByteStreamControllerCommitPullIntoDescriptor(c.stream, desc);
    }
  }
}
function readableByteStreamControllerProcessReadRequestsUsingQueue(controller) {
  const c = slotOf(controller), reader = slotOf(c.stream).reader, r = slotOf(reader);
  while (r.readRequests.length > 0) {
    if (c.queueTotalSize === 0) return;
    const rr = r.readRequests.shift();
    readableByteStreamControllerFillReadRequestFromQueue(controller, rr);
  }
}
function readableByteStreamControllerFillReadRequestFromQueue(controller, readRequest) {
  const c = slotOf(controller);
  const entry = c.queue.shift();
  c.queueTotalSize -= entry.byteLength;
  readableByteStreamControllerHandleQueueDrain(controller);
  readRequest.chunkSteps(new Uint8Array(entry.buffer, entry.byteOffset, entry.byteLength));
}
function readableByteStreamControllerHandleQueueDrain(controller) {
  const c = slotOf(controller), stream = c.stream;
  if (c.queueTotalSize === 0 && c.closeRequested) { readableByteStreamControllerClearAlgorithms(controller); readableStreamClose(stream); }
  else readableByteStreamControllerCallPullIfNeeded(controller);
}
function readableByteStreamControllerShiftPendingPullInto(controller) { return slotOf(controller).pendingPullIntos.shift(); }
function readableByteStreamControllerCommitPullIntoDescriptor(stream, desc) {
  const s = slotOf(stream);
  let done = false;
  if (s.state === 'closed') done = true;
  const filledView = readableByteStreamControllerConvertPullIntoDescriptor(desc);
  if (desc.readerType === 'default') readableStreamFulfillReadRequest(stream, filledView, done);
  else readableStreamFulfillReadIntoRequest(stream, filledView, done);
}
function readableByteStreamControllerConvertPullIntoDescriptor(desc) {
  const buffer = transferArrayBuffer(desc.buffer);
  return new desc.viewConstructor(buffer, desc.byteOffset, desc.bytesFilled / desc.elementSize);
}
function readableByteStreamControllerRespondInClosedState(controller, first) {
  const c = slotOf(controller);
  if (first.readerType === 'none') readableByteStreamControllerShiftPendingPullInto(controller);
  const stream = c.stream;
  if (readableStreamHasBYOBReader(stream)) {
    while (readableStreamGetNumReadIntoRequests(stream) > 0) {
      const desc = readableByteStreamControllerShiftPendingPullInto(controller);
      readableByteStreamControllerCommitPullIntoDescriptor(stream, desc);
    }
  }
}
function readableByteStreamControllerRespondInReadableState(controller, bytesWritten, desc) {
  const c = slotOf(controller);
  readableByteStreamControllerFillHeadPullIntoDescriptor(controller, bytesWritten, desc);
  if (desc.readerType === 'none') {
    readableByteStreamControllerEnqueueDetachedPullIntoToQueue(controller, desc);
    readableByteStreamControllerProcessPullIntoDescriptorsUsingQueue(controller);
    return;
  }
  if (desc.bytesFilled < desc.minimumFill) return;
  readableByteStreamControllerShiftPendingPullInto(controller);
  const remainderSize = desc.bytesFilled % desc.elementSize;
  if (remainderSize > 0) {
    const end = desc.byteOffset + desc.bytesFilled;
    readableByteStreamControllerEnqueueClonedChunkToQueue(controller, desc.buffer, end - remainderSize, remainderSize);
  }
  desc.bytesFilled -= remainderSize;
  readableByteStreamControllerCommitPullIntoDescriptor(c.stream, desc);
  readableByteStreamControllerProcessPullIntoDescriptorsUsingQueue(controller);
}
function readableByteStreamControllerRespondInternal(controller, bytesWritten) {
  const c = slotOf(controller), first = c.pendingPullIntos[0];
  readableByteStreamControllerInvalidateBYOBRequest(controller);
  if (slotOf(c.stream).state === 'closed') readableByteStreamControllerRespondInClosedState(controller, first);
  else readableByteStreamControllerRespondInReadableState(controller, bytesWritten, first);
  readableByteStreamControllerCallPullIfNeeded(controller);
}
function readableByteStreamControllerRespond(controller, bytesWritten) {
  const c = slotOf(controller), first = c.pendingPullIntos[0];
  const state = slotOf(c.stream).state;
  if (state === 'closed') { if (bytesWritten !== 0) throw new TypeError('bytesWritten must be 0 when calling respond() on a closed stream'); }
  else {
    if (bytesWritten === 0) throw new TypeError('bytesWritten must be greater than 0 when calling respond() on a readable stream');
    if (first.bytesFilled + bytesWritten > first.byteLength) throw new RangeError('bytesWritten out of range');
  }
  first.buffer = transferArrayBuffer(first.buffer);
  readableByteStreamControllerRespondInternal(controller, bytesWritten);
}
function readableByteStreamControllerRespondWithNewView(controller, view) {
  const c = slotOf(controller), first = c.pendingPullIntos[0];
  const state = slotOf(c.stream).state;
  if (state === 'closed') { if (viewByteLength(view) !== 0) throw new TypeError('The view\'s length must be 0 when calling respondWithNewView() on a closed stream'); }
  else if (viewByteLength(view) === 0) throw new TypeError('The view\'s length must be greater than 0 when calling respondWithNewView() on a readable stream');
  if (first.byteOffset + first.bytesFilled !== viewByteOffset(view)) throw new RangeError('The region specified by view does not match byobRequest');
  if (first.bufferByteLength !== apply(abByteLengthGetter, viewBuffer(view), [])) throw new RangeError('The buffer of view has different capacity than byobRequest');
  if (first.bytesFilled + viewByteLength(view) > first.byteLength) throw new RangeError('The region specified by view is larger than byobRequest');
  const viewLength = viewByteLength(view);
  first.buffer = transferArrayBuffer(viewBuffer(view));
  readableByteStreamControllerRespondInternal(controller, viewLength);
}
function readableByteStreamControllerGetBYOBRequest(controller) {
  const c = slotOf(controller);
  if (c.byobRequest === null && c.pendingPullIntos.length > 0) {
    const first = c.pendingPullIntos[0];
    const view = new Uint8Array(first.buffer, first.byteOffset + first.bytesFilled, first.byteLength - first.bytesFilled);
    const req = create(ReadableStreamBYOBRequest.prototype);
    setSlot(req, { isBYOBRequest: true, controller, view });
    c.byobRequest = req;
  }
  return c.byobRequest;
}
function readableByteStreamControllerPullInto(controller, view, min, readIntoRequest) {
  const c = slotOf(controller), stream = c.stream;
  const kind = viewKind(view);
  const ctor = viewConstructors[kind];
  const elementSize = kind === 'DataView' ? 1 : viewElementSizes[kind];
  const minimumFill = min * elementSize;
  const byteOffset = viewByteOffset(view), byteLength = viewByteLength(view);
  let buffer;
  try { buffer = transferArrayBuffer(viewBuffer(view)); } catch (e) { readIntoRequest.errorSteps(e); return; }
  const desc = { buffer, bufferByteLength: apply(abByteLengthGetter, buffer, []), byteOffset, byteLength, bytesFilled: 0, minimumFill, elementSize, viewConstructor: ctor, readerType: 'byob' };
  if (c.pendingPullIntos.length > 0) {
    apply(arrayPush, c.pendingPullIntos, [desc]);
    readableStreamAddReadIntoRequest(stream, readIntoRequest);
    return;
  }
  if (slotOf(stream).state === 'closed') {
    readIntoRequest.closeSteps(new ctor(desc.buffer, byteOffset, 0));
    return;
  }
  if (c.queueTotalSize > 0) {
    if (readableByteStreamControllerFillPullIntoDescriptorFromQueue(controller, desc)) {
      const filledView = readableByteStreamControllerConvertPullIntoDescriptor(desc);
      readableByteStreamControllerHandleQueueDrain(controller);
      readIntoRequest.chunkSteps(filledView);
      return;
    }
    if (c.closeRequested) {
      const e = new TypeError('Insufficient bytes to fill elements in the given buffer');
      readableByteStreamControllerError(controller, e);
      readIntoRequest.errorSteps(e);
      return;
    }
  }
  apply(arrayPush, c.pendingPullIntos, [desc]);
  readableStreamAddReadIntoRequest(stream, readIntoRequest);
  readableByteStreamControllerCallPullIfNeeded(controller);
}
function readableByteStreamControllerCancelSteps(controller, reason) {
  readableByteStreamControllerClearPendingPullIntos(controller);
  resetQueue(slotOf(controller));
  const result = slotOf(controller).cancelAlgorithm(reason);
  readableByteStreamControllerClearAlgorithms(controller);
  return result;
}
function readableByteStreamControllerPullSteps(controller, readRequest) {
  const c = slotOf(controller), stream = c.stream;
  if (c.queueTotalSize > 0) { readableByteStreamControllerFillReadRequestFromQueue(controller, readRequest); return; }
  const autoAllocateChunkSize = c.autoAllocateChunkSize;
  if (autoAllocateChunkSize !== undefined) {
    let buffer;
    try { buffer = new ArrayBuffer(autoAllocateChunkSize); } catch (e) { readRequest.errorSteps(e); return; }
    apply(arrayPush, c.pendingPullIntos, [{ buffer, bufferByteLength: autoAllocateChunkSize, byteOffset: 0, byteLength: autoAllocateChunkSize, bytesFilled: 0, minimumFill: 1, elementSize: 1, viewConstructor: Uint8Array, readerType: 'default' }]);
  }
  readableStreamAddReadRequest(stream, readRequest);
  readableByteStreamControllerCallPullIfNeeded(controller);
}
function readableByteStreamControllerReleaseSteps(controller) {
  const c = slotOf(controller);
  if (c.pendingPullIntos.length > 0) {
    const first = c.pendingPullIntos[0];
    first.readerType = 'none';
    c.pendingPullIntos = [first];
  }
}
function setUpReadableByteStreamController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm, autoAllocateChunkSize) {
  const controller = create(ReadableByteStreamController.prototype);
  const c = setSlot(controller, { isByteController: true, stream, pullAgain: false, pulling: false, byobRequest: null, queue: [], queueTotalSize: 0, closeRequested: false, started: false, strategyHWM: hwm, pullAlgorithm, cancelAlgorithm, autoAllocateChunkSize, pendingPullIntos: [] });
  slotOf(stream).controller = controller;
  const startResult = startAlgorithm(controller);
  uponPromise(promiseResolvedWith(startResult), () => {
    c.started = true;
    readableByteStreamControllerCallPullIfNeeded(controller);
  }, r => readableByteStreamControllerError(controller, r));
}
function setUpReadableByteStreamControllerFromUnderlyingSource(stream, source, dict, hwm) {
  const startAlgorithm = controller => (dict.start ? apply(dict.start, source, [controller]) : undefined);
  const pullAlgorithm = () => (dict.pull ? promiseCallStreams(dict.pull, source, [slotOf(stream).controller]) : promiseResolvedWith(undefined));
  const cancelAlgorithm = reason => (dict.cancel ? promiseCallStreams(dict.cancel, source, [reason]) : promiseResolvedWith(undefined));
  const autoAllocateChunkSize = dict.autoAllocateChunkSize;
  if (autoAllocateChunkSize === 0) throw new TypeError('autoAllocateChunkSize must be greater than 0');
  setUpReadableByteStreamController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, hwm, autoAllocateChunkSize);
}
function createReadableByteStream(startAlgorithm, pullAlgorithm, cancelAlgorithm) {
  const stream = create(ReadableStream.prototype);
  initializeReadableStream(stream);
  setUpReadableByteStreamController(stream, startAlgorithm, pullAlgorithm, cancelAlgorithm, 0, undefined);
  return stream;
}

// --- BYOB reader

function ReadableStreamBYOBReader(stream) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'ReadableStreamBYOBReader': Please use the 'new' operator");
  required(arguments, 1, 'ReadableStreamBYOBReader');
  if (!isReadableStreamLike(stream)) throw new TypeError("Failed to construct 'ReadableStreamBYOBReader': parameter 1 is not of type 'ReadableStream'.");
  setUpBYOBReader(this, stream);
}
iface('ReadableStreamBYOBReader', ReadableStreamBYOBReader, null);
function setUpBYOBReader(reader, stream) {
  if (isReadableStreamLocked(stream)) throw new TypeError('This stream has already been locked for exclusive reading by another reader');
  if (!slotOf(slotOf(stream).controller).isByteController) throw new TypeError('Cannot construct a ReadableStreamBYOBReader for a stream not constructed with a byte source');
  setSlot(reader, { isBYOBReader: true, stream: undefined, readIntoRequests: [], closedCapability: undefined });
  readerGenericInitialize(reader, stream);
}
function acquireReadableStreamBYOBReader(stream) {
  const reader = create(ReadableStreamBYOBReader.prototype);
  setUpBYOBReader(reader, stream);
  return reader;
}
function brSlot(o) { const s = slotOf(o); return s && s.isBYOBReader === true ? s : null; }
attributes(ReadableStreamBYOBReader.prototype, {
  closed: { get() { const s = brSlot(this); if (!s) return promiseRejectedWith(new TypeError('Illegal invocation')); return s.closedCapability.promise; } }
});
operations(ReadableStreamBYOBReader.prototype, {
  cancel(reason = undefined) {
    const s = brSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot cancel a stream using a released reader'));
    return readerGenericCancel(this, reason);
  },
  read(view, options = undefined) {
    const s = brSlot(this);
    if (!s) return promiseRejectedWith(new TypeError('Illegal invocation'));
    if (arguments.length < 1) return promiseRejectedWith(new TypeError("Failed to execute 'read' on 'ReadableStreamBYOBReader': 1 argument required, but only 0 present."));
    if (viewKind(view) === null) return promiseRejectedWith(new TypeError('view must be an array buffer view'));
    let min = 1;
    if (options !== undefined && options !== null) {
      if (!isObject(options)) return promiseRejectedWith(new TypeError('options must be an object'));
      if (options.min !== undefined) {
        try { min = enforceRangeUnsignedLongLong(options.min, 'min'); } catch (e) { return promiseRejectedWith(e); }
      }
    }
    if (viewByteLength(view) === 0) return promiseRejectedWith(new TypeError('view must have non-zero byteLength'));
    if (apply(abByteLengthGetter, viewBuffer(view), []) === 0) return promiseRejectedWith(new TypeError('view\'s buffer must have non-zero byteLength'));
    if (isDetachedBuffer(viewBuffer(view))) return promiseRejectedWith(new TypeError('view\'s buffer has been detached'));
    if (min === 0) return promiseRejectedWith(new TypeError('options.min must be greater than 0'));
    const kind = viewKind(view);
    if (kind !== 'DataView') { if (min > apply(Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Int8Array.prototype), 'length').get, view, [])) return promiseRejectedWith(new RangeError('options.min must be less than or equal to view\'s length')); }
    else if (min > viewByteLength(view)) return promiseRejectedWith(new RangeError('options.min must be less than or equal to view\'s byteLength'));
    if (s.stream === undefined) return promiseRejectedWith(new TypeError('Cannot read from a released reader'));
    const cap = newPromiseCapability();
    readableStreamBYOBReaderRead(this, view, min, { chunkSteps: chunk => cap.resolve({ value: chunk, done: false }), closeSteps: chunk => cap.resolve({ value: chunk, done: true }), errorSteps: e => cap.reject(e) });
    return cap.promise;
  },
  releaseLock() {
    const s = brSlot(this);
    if (!s) throw new TypeError('Illegal invocation');
    if (s.stream === undefined) return;
    readableStreamBYOBReaderRelease(this);
  }
});
function readableStreamAddReadIntoRequest(stream, rr) { apply(arrayPush, slotOf(slotOf(stream).reader).readIntoRequests, [rr]); }
function readableStreamFulfillReadIntoRequest(stream, chunk, done) {
  const rr = slotOf(slotOf(stream).reader).readIntoRequests.shift();
  if (done) rr.closeSteps(chunk); else rr.chunkSteps(chunk);
}
function readableStreamBYOBReaderRead(reader, view, min, readIntoRequest) {
  const stream = slotOf(reader).stream, s = slotOf(stream);
  s.disturbed = true;
  if (s.state === 'errored') readIntoRequest.errorSteps(s.storedError);
  else readableByteStreamControllerPullInto(s.controller, view, min, readIntoRequest);
}
function readableStreamBYOBReaderRelease(reader) {
  readerGenericRelease(reader);
  readableStreamBYOBReaderErrorReadIntoRequests(reader, new TypeError('Reader was released'));
}
function readableStreamBYOBReaderErrorReadIntoRequests(reader, e) {
  const r = slotOf(reader);
  const reqs = r.readIntoRequests;
  r.readIntoRequests = [];
  for (const rr of reqs) rr.errorSteps(e);
}

// --- tee for byte streams

function cloneAsUint8Array(o) {
  const buffer = viewBuffer(o);
  return new Uint8Array(cloneArrayBuffer(buffer, viewByteOffset(o), viewByteLength(o)));
}
function readableByteStreamTee(stream) {
  let reader = acquireReadableStreamDefaultReader(stream);
  let reading = false, readAgainForBranch1 = false, readAgainForBranch2 = false, canceled1 = false, canceled2 = false, reason1, reason2, branch1, branch2;
  const cancelCap = newPromiseCapability();
  function forwardReaderError(thisReader) {
    uponRejection(slotOf(thisReader).closedCapability.promise, r => {
      if (thisReader !== reader) return;
      readableByteStreamControllerError(slotOf(branch1).controller, r);
      readableByteStreamControllerError(slotOf(branch2).controller, r);
      if (!canceled1 || !canceled2) cancelCap.resolve(undefined);
    });
  }
  function pullWithDefaultReader() {
    if (slotOf(reader).isBYOBReader) {
      readableStreamBYOBReaderRelease(reader);
      reader = acquireReadableStreamDefaultReader(stream);
      forwardReaderError(reader);
    }
    readableStreamDefaultReaderRead(reader, {
      chunkSteps: chunk => {
        queueMicrotaskStreams(() => {
          readAgainForBranch1 = false; readAgainForBranch2 = false;
          const chunk1 = chunk;
          let chunk2 = chunk;
          if (!canceled1 && !canceled2) {
            try { chunk2 = cloneAsUint8Array(chunk); } catch (e) {
              readableByteStreamControllerError(slotOf(branch1).controller, e);
              readableByteStreamControllerError(slotOf(branch2).controller, e);
              cancelCap.resolve(readableStreamCancel(stream, e));
              return;
            }
          }
          if (!canceled1) readableByteStreamControllerEnqueue(slotOf(branch1).controller, chunk1);
          if (!canceled2) readableByteStreamControllerEnqueue(slotOf(branch2).controller, chunk2);
          reading = false;
          if (readAgainForBranch1) pull1Algorithm();
          else if (readAgainForBranch2) pull2Algorithm();
        });
      },
      closeSteps: () => {
        reading = false;
        const c1 = slotOf(branch1).controller, c2 = slotOf(branch2).controller;
        if (!canceled1) readableByteStreamControllerClose(c1);
        if (!canceled2) readableByteStreamControllerClose(c2);
        if (slotOf(c1).pendingPullIntos.length > 0) readableByteStreamControllerRespond(c1, 0);
        if (slotOf(c2).pendingPullIntos.length > 0) readableByteStreamControllerRespond(c2, 0);
        if (!canceled1 || !canceled2) cancelCap.resolve(undefined);
      },
      errorSteps: () => { reading = false; }
    });
  }
  function pullWithBYOBReader(view, forBranch2) {
    if (slotOf(reader).isDefaultReader) {
      readableStreamDefaultReaderRelease(reader);
      reader = acquireReadableStreamBYOBReader(stream);
      forwardReaderError(reader);
    }
    const byobBranch = forBranch2 ? branch2 : branch1;
    const otherBranch = forBranch2 ? branch1 : branch2;
    readableStreamBYOBReaderRead(reader, view, 1, {
      chunkSteps: chunk => {
        queueMicrotaskStreams(() => {
          readAgainForBranch1 = false; readAgainForBranch2 = false;
          const byobCanceled = forBranch2 ? canceled2 : canceled1;
          const otherCanceled = forBranch2 ? canceled1 : canceled2;
          if (!otherCanceled) {
            let clonedChunk;
            try { clonedChunk = cloneAsUint8Array(chunk); } catch (e) {
              readableByteStreamControllerError(slotOf(byobBranch).controller, e);
              readableByteStreamControllerError(slotOf(otherBranch).controller, e);
              cancelCap.resolve(readableStreamCancel(stream, e));
              return;
            }
            if (!byobCanceled) readableByteStreamControllerRespondWithNewView(slotOf(byobBranch).controller, chunk);
            readableByteStreamControllerEnqueue(slotOf(otherBranch).controller, clonedChunk);
          } else if (!byobCanceled) readableByteStreamControllerRespondWithNewView(slotOf(byobBranch).controller, chunk);
          reading = false;
          if (readAgainForBranch1) pull1Algorithm();
          else if (readAgainForBranch2) pull2Algorithm();
        });
      },
      closeSteps: chunk => {
        reading = false;
        const byobCanceled = forBranch2 ? canceled2 : canceled1;
        const otherCanceled = forBranch2 ? canceled1 : canceled2;
        if (!byobCanceled) readableByteStreamControllerClose(slotOf(byobBranch).controller);
        if (!otherCanceled) readableByteStreamControllerClose(slotOf(otherBranch).controller);
        if (chunk !== undefined) {
          if (!byobCanceled) readableByteStreamControllerRespondWithNewView(slotOf(byobBranch).controller, chunk);
          if (!otherCanceled && slotOf(slotOf(otherBranch).controller).pendingPullIntos.length > 0) readableByteStreamControllerRespond(slotOf(otherBranch).controller, 0);
        }
        if (!byobCanceled || !otherCanceled) cancelCap.resolve(undefined);
      },
      errorSteps: () => { reading = false; }
    });
  }
  function pull1Algorithm() {
    if (reading) { readAgainForBranch1 = true; return promiseResolvedWith(undefined); }
    reading = true;
    const byobRequest = readableByteStreamControllerGetBYOBRequest(slotOf(branch1).controller);
    if (byobRequest === null) pullWithDefaultReader(); else pullWithBYOBReader(slotOf(byobRequest).view, false);
    return promiseResolvedWith(undefined);
  }
  function pull2Algorithm() {
    if (reading) { readAgainForBranch2 = true; return promiseResolvedWith(undefined); }
    reading = true;
    const byobRequest = readableByteStreamControllerGetBYOBRequest(slotOf(branch2).controller);
    if (byobRequest === null) pullWithDefaultReader(); else pullWithBYOBReader(slotOf(byobRequest).view, true);
    return promiseResolvedWith(undefined);
  }
  function cancel1Algorithm(reason) {
    canceled1 = true; reason1 = reason;
    if (canceled2) cancelCap.resolve(readableStreamCancel(stream, [reason1, reason2]));
    return cancelCap.promise;
  }
  function cancel2Algorithm(reason) {
    canceled2 = true; reason2 = reason;
    if (canceled1) cancelCap.resolve(readableStreamCancel(stream, [reason1, reason2]));
    return cancelCap.promise;
  }
  branch1 = createReadableByteStream(noop, pull1Algorithm, cancel1Algorithm);
  branch2 = createReadableByteStream(noop, pull2Algorithm, cancel2Algorithm);
  forwardReaderError(reader);
  return [branch1, branch2];
}
