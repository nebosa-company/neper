// Streams Standard: TransformStream, queuing strategies and the text encoding streams.

function TransformStream(transformer = undefined, writableStrategy = undefined, readableStrategy = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'TransformStream': Please use the 'new' operator");
  const wstrat = convertQueuingStrategy(writableStrategy, 'TransformStream writable strategy');
  const rstrat = convertQueuingStrategy(readableStrategy, 'TransformStream readable strategy');
  let t = transformer;
  if (t === undefined) t = null;
  const dict = convertTransformer(t);
  if (dict.hasReadableType) throw new RangeError('Invalid readableType specified');
  if (dict.hasWritableType) throw new RangeError('Invalid writableType specified');
  const readableHighWaterMark = extractHighWaterMark(rstrat, 0);
  const readableSizeAlgorithm = extractSizeAlgorithm(rstrat);
  const writableHighWaterMark = extractHighWaterMark(wstrat, 1);
  const writableSizeAlgorithm = extractSizeAlgorithm(wstrat);
  const startCap = newPromiseCapability();
  initializeTransformStream(this, startCap.promise, writableHighWaterMark, writableSizeAlgorithm, readableHighWaterMark, readableSizeAlgorithm);
  setUpTransformStreamDefaultControllerFromTransformer(this, t, dict);
  if (dict.start) startCap.resolve(apply(dict.start, t, [slotOf(this).controller]));
  else startCap.resolve(undefined);
}
iface('TransformStream', TransformStream, null);
function convertTransformer(t) {
  const dict = {};
  if (t === null) return dict;
  if (!isObject(t)) throw new TypeError('The transformer is not an object.');
  for (const name of ['cancel', 'flush']) {
    const v = t[name];
    if (v !== undefined) {
      if (typeof v !== 'function') throw new TypeError('The transformer ' + name + ' is not a function.');
      dict[name] = v;
    }
  }
  if (t.readableType !== undefined) dict.hasReadableType = true;
  const st = t.start;
  if (st !== undefined) {
    if (typeof st !== 'function') throw new TypeError('The transformer start is not a function.');
    dict.start = st;
  }
  const tr = t.transform;
  if (tr !== undefined) {
    if (typeof tr !== 'function') throw new TypeError('The transformer transform is not a function.');
    dict.transform = tr;
  }
  if (t.writableType !== undefined) dict.hasWritableType = true;
  return dict;
}
function tsSlot(o) { const s = slotOf(o); if (!s || s.isTransformStream !== true) throw new TypeError('Illegal invocation'); return s; }
attributes(TransformStream.prototype, {
  readable: { get() { return tsSlot(this).readable; } },
  writable: { get() { return tsSlot(this).writable; } }
});
function initializeTransformStream(stream, startPromise, writableHWM, writableSizeAlgorithm, readableHWM, readableSizeAlgorithm) {
  const s = setSlot(stream, { isTransformStream: true, readable: undefined, writable: undefined, backpressure: undefined, backpressureChangeCapability: undefined, controller: undefined });
  const startAlgorithm = () => startPromise;
  const writeAlgorithm = chunk => transformStreamDefaultSinkWriteAlgorithm(stream, chunk);
  const abortAlgorithm = reason => transformStreamDefaultSinkAbortAlgorithm(stream, reason);
  const closeAlgorithm = () => transformStreamDefaultSinkCloseAlgorithm(stream);
  s.writable = createWritableStream(startAlgorithm, writeAlgorithm, closeAlgorithm, abortAlgorithm, writableHWM, writableSizeAlgorithm);
  const pullAlgorithm = () => transformStreamDefaultSourcePullAlgorithm(stream);
  const cancelAlgorithm = reason => transformStreamDefaultSourceCancelAlgorithm(stream, reason);
  s.readable = createReadableStream(startAlgorithm, pullAlgorithm, cancelAlgorithm, readableHWM, readableSizeAlgorithm);
  s.backpressure = undefined;
  s.backpressureChangeCapability = undefined;
  transformStreamSetBackpressure(stream, true);
  s.controller = undefined;
}
function transformStreamError(stream, e) {
  const s = slotOf(stream);
  readableStreamDefaultControllerError(slotOf(s.readable).controller, e);
  transformStreamErrorWritableAndUnblockWrite(stream, e);
}
function transformStreamErrorWritableAndUnblockWrite(stream, e) {
  const s = slotOf(stream);
  transformStreamDefaultControllerClearAlgorithms(s.controller);
  writableStreamDefaultControllerErrorIfNeeded(slotOf(s.writable).controller, e);
  transformStreamUnblockWrite(stream);
}
function transformStreamUnblockWrite(stream) {
  if (slotOf(stream).backpressure === true) transformStreamSetBackpressure(stream, false);
}
function transformStreamSetBackpressure(stream, backpressure) {
  const s = slotOf(stream);
  if (s.backpressureChangeCapability !== undefined) s.backpressureChangeCapability.resolve(undefined);
  s.backpressureChangeCapability = newPromiseCapability();
  s.backpressure = backpressure;
}

function TransformStreamDefaultController() { throw new TypeError('Illegal constructor'); }
iface('TransformStreamDefaultController', TransformStreamDefaultController, null);
function tdcSlot(o) { const s = slotOf(o); if (!s || s.isTransformController !== true) throw new TypeError('Illegal invocation'); return s; }
attributes(TransformStreamDefaultController.prototype, {
  desiredSize: { get() { const c = tdcSlot(this); return readableStreamDefaultControllerGetDesiredSize(slotOf(slotOf(c.stream).readable).controller); } }
});
operations(TransformStreamDefaultController.prototype, {
  enqueue(chunk = undefined) { tdcSlot(this); transformStreamDefaultControllerEnqueue(this, chunk); },
  error(reason = undefined) { tdcSlot(this); transformStreamDefaultControllerError(this, reason); },
  terminate() { tdcSlot(this); transformStreamDefaultControllerTerminate(this); }
});
function setUpTransformStreamDefaultController(stream, controller, transformAlgorithm, flushAlgorithm, cancelAlgorithm) {
  const c = slotOf(controller);
  c.stream = stream;
  slotOf(stream).controller = controller;
  c.transformAlgorithm = transformAlgorithm;
  c.flushAlgorithm = flushAlgorithm;
  c.cancelAlgorithm = cancelAlgorithm;
}
function setUpTransformStreamDefaultControllerFromTransformer(stream, transformer, dict) {
  const controller = create(TransformStreamDefaultController.prototype);
  setSlot(controller, { isTransformController: true, stream: undefined, transformAlgorithm: undefined, flushAlgorithm: undefined, cancelAlgorithm: undefined, finishPromise: undefined });
  const transformAlgorithm = dict.transform
    ? chunk => promiseCallStreams(dict.transform, transformer, [chunk, controller])
    : chunk => {
      try { transformStreamDefaultControllerEnqueue(controller, chunk); } catch (e) { return promiseRejectedWith(e); }
      return promiseResolvedWith(undefined);
    };
  const flushAlgorithm = dict.flush ? () => promiseCallStreams(dict.flush, transformer, [controller]) : () => promiseResolvedWith(undefined);
  const cancelAlgorithm = dict.cancel ? reason => promiseCallStreams(dict.cancel, transformer, [reason]) : () => promiseResolvedWith(undefined);
  setUpTransformStreamDefaultController(stream, controller, transformAlgorithm, flushAlgorithm, cancelAlgorithm);
}
function transformStreamDefaultControllerClearAlgorithms(controller) {
  const c = slotOf(controller);
  c.transformAlgorithm = undefined; c.flushAlgorithm = undefined; c.cancelAlgorithm = undefined;
}
function transformStreamDefaultControllerEnqueue(controller, chunk) {
  const stream = slotOf(controller).stream, s = slotOf(stream);
  const readableController = slotOf(s.readable).controller;
  if (!readableStreamDefaultControllerCanCloseOrEnqueue(readableController)) throw new TypeError('Readable side is not in a state that permits enqueue');
  try { readableStreamDefaultControllerEnqueue(readableController, chunk); } catch (e) {
    transformStreamErrorWritableAndUnblockWrite(stream, e);
    throw slotOf(s.readable).storedError;
  }
  const backpressure = readableStreamDefaultControllerHasBackpressure(readableController);
  if (backpressure !== s.backpressure) transformStreamSetBackpressure(stream, true);
}
function transformStreamDefaultControllerError(controller, e) { transformStreamError(slotOf(controller).stream, e); }
function transformStreamDefaultControllerPerformTransform(controller, chunk) {
  const transformPromise = slotOf(controller).transformAlgorithm(chunk);
  return transformPromiseWith(transformPromise, undefined, r => { transformStreamError(slotOf(controller).stream, r); throw r; });
}
function transformStreamDefaultControllerTerminate(controller) {
  const stream = slotOf(controller).stream, s = slotOf(stream);
  readableStreamDefaultControllerClose(slotOf(s.readable).controller);
  transformStreamErrorWritableAndUnblockWrite(stream, new TypeError('TransformStream terminated'));
}
function transformStreamDefaultSinkWriteAlgorithm(stream, chunk) {
  const s = slotOf(stream), controller = s.controller;
  if (s.backpressure === true) {
    return transformPromiseWith(s.backpressureChangeCapability.promise, () => {
      const writable = s.writable;
      if (slotOf(writable).state === 'erroring') throw slotOf(writable).storedError;
      return transformStreamDefaultControllerPerformTransform(controller, chunk);
    }, undefined);
  }
  return transformStreamDefaultControllerPerformTransform(controller, chunk);
}
function transformStreamDefaultSinkAbortAlgorithm(stream, reason) {
  const s = slotOf(stream), controller = s.controller, c = slotOf(controller);
  if (c.finishPromise !== undefined) return c.finishPromise.promise;
  const readable = s.readable;
  c.finishPromise = newPromiseCapability();
  const cancelPromise = c.cancelAlgorithm(reason);
  transformStreamDefaultControllerClearAlgorithms(controller);
  uponPromise(cancelPromise, () => {
    if (slotOf(readable).state === 'errored') c.finishPromise.reject(slotOf(readable).storedError);
    else { readableStreamDefaultControllerError(slotOf(readable).controller, reason); c.finishPromise.resolve(undefined); }
  }, r => {
    readableStreamDefaultControllerError(slotOf(readable).controller, r);
    c.finishPromise.reject(r);
  });
  return c.finishPromise.promise;
}
function transformStreamDefaultSinkCloseAlgorithm(stream) {
  const s = slotOf(stream), controller = s.controller, c = slotOf(controller);
  if (c.finishPromise !== undefined) return c.finishPromise.promise;
  const readable = s.readable;
  c.finishPromise = newPromiseCapability();
  const flushPromise = c.flushAlgorithm();
  transformStreamDefaultControllerClearAlgorithms(controller);
  uponPromise(flushPromise, () => {
    if (slotOf(readable).state === 'errored') c.finishPromise.reject(slotOf(readable).storedError);
    else { readableStreamDefaultControllerClose(slotOf(readable).controller); c.finishPromise.resolve(undefined); }
  }, r => {
    readableStreamDefaultControllerError(slotOf(readable).controller, r);
    c.finishPromise.reject(r);
  });
  return c.finishPromise.promise;
}
function transformStreamDefaultSourceCancelAlgorithm(stream, reason) {
  const s = slotOf(stream), controller = s.controller, c = slotOf(controller);
  if (c.finishPromise !== undefined) return c.finishPromise.promise;
  const writable = s.writable;
  c.finishPromise = newPromiseCapability();
  const cancelPromise = c.cancelAlgorithm(reason);
  transformStreamDefaultControllerClearAlgorithms(controller);
  uponPromise(cancelPromise, () => {
    if (slotOf(writable).state === 'errored') c.finishPromise.reject(slotOf(writable).storedError);
    else {
      writableStreamDefaultControllerErrorIfNeeded(slotOf(writable).controller, reason);
      transformStreamUnblockWrite(stream);
      c.finishPromise.resolve(undefined);
    }
  }, r => {
    writableStreamDefaultControllerErrorIfNeeded(slotOf(writable).controller, r);
    transformStreamUnblockWrite(stream);
    c.finishPromise.reject(r);
  });
  return c.finishPromise.promise;
}
function transformStreamDefaultSourcePullAlgorithm(stream) {
  transformStreamSetBackpressure(stream, false);
  return slotOf(stream).backpressureChangeCapability.promise;
}

// --- queuing strategies

function strategyInit(init, name) {
  if (!isObject(init)) throw new TypeError("Failed to construct '" + name + "': The provided value is not of type 'QueuingStrategyInit'.");
  const hwm = init.highWaterMark;
  if (hwm === undefined) throw new TypeError("Failed to construct '" + name + "': Required member highWaterMark is undefined.");
  return Number(hwm);
}
function ByteLengthQueuingStrategy(init) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'ByteLengthQueuingStrategy': Please use the 'new' operator");
  required(arguments, 1, 'ByteLengthQueuingStrategy');
  setSlot(this, { isByteLengthStrategy: true, highWaterMark: strategyInit(init, 'ByteLengthQueuingStrategy') });
}
iface('ByteLengthQueuingStrategy', ByteLengthQueuingStrategy, null);
const byteLengthSizeFunction = { size(chunk) { return chunk.byteLength; } }.size;
defineProperty(byteLengthSizeFunction, 'length', { value: 1, configurable: true });
attributes(ByteLengthQueuingStrategy.prototype, {
  highWaterMark: { get() { const s = slotOf(this); if (!s || !s.isByteLengthStrategy) throw new TypeError('Illegal invocation'); return s.highWaterMark; } },
  size: { get() { const s = slotOf(this); if (!s || !s.isByteLengthStrategy) throw new TypeError('Illegal invocation'); return byteLengthSizeFunction; } }
});
function CountQueuingStrategy(init) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'CountQueuingStrategy': Please use the 'new' operator");
  required(arguments, 1, 'CountQueuingStrategy');
  setSlot(this, { isCountStrategy: true, highWaterMark: strategyInit(init, 'CountQueuingStrategy') });
}
iface('CountQueuingStrategy', CountQueuingStrategy, null);
const countSizeFunction = { size() { return 1; } }.size;
attributes(CountQueuingStrategy.prototype, {
  highWaterMark: { get() { const s = slotOf(this); if (!s || !s.isCountStrategy) throw new TypeError('Illegal invocation'); return s.highWaterMark; } },
  size: { get() { const s = slotOf(this); if (!s || !s.isCountStrategy) throw new TypeError('Illegal invocation'); return countSizeFunction; } }
});

// --- TextEncoderStream and TextDecoderStream

function TextEncoderStream() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'TextEncoderStream': Please use the 'new' operator");
  const encoder = new TextEncoder();
  let pendingHighSurrogate = null;
  const transformer = {
    transform(chunk, controller) {
      let s = String(chunk);
      if (pendingHighSurrogate !== null) { s = pendingHighSurrogate + s; pendingHighSurrogate = null; }
      if (s.length > 0) {
        const last = s.charCodeAt(s.length - 1);
        if (last >= 0xD800 && last <= 0xDBFF) { pendingHighSurrogate = s[s.length - 1]; s = s.slice(0, -1); }
      }
      if (s.length > 0) controller.enqueue(encoder.encode(s));
    },
    flush(controller) {
      if (pendingHighSurrogate !== null) controller.enqueue(encoder.encode('�'));
    }
  };
  const ts = new TransformStream(transformer);
  setSlot(this, { isEncoderStream: true, transform: ts });
}
iface('TextEncoderStream', TextEncoderStream, null);
attributes(TextEncoderStream.prototype, {
  encoding: { get() { if (!slotOf(this) || !slotOf(this).isEncoderStream) throw new TypeError('Illegal invocation'); return 'utf-8'; } },
  readable: { get() { if (!slotOf(this) || !slotOf(this).isEncoderStream) throw new TypeError('Illegal invocation'); return slotOf(this).transform.readable; } },
  writable: { get() { if (!slotOf(this) || !slotOf(this).isEncoderStream) throw new TypeError('Illegal invocation'); return slotOf(this).transform.writable; } }
});
function TextDecoderStream(label = 'utf-8', options = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'TextDecoderStream': Please use the 'new' operator");
  const decoder = new TextDecoder(label, options);
  const transformer = {
    transform(chunk, controller) {
      if (!ArrayBuffer.isView(chunk) && !isArrayBufferObject(chunk)) throw new TypeError('The chunk is not a BufferSource');
      const out = decoder.decode(chunk, { stream: true });
      if (out.length > 0) controller.enqueue(out);
    },
    flush(controller) {
      const out = decoder.decode();
      if (out.length > 0) controller.enqueue(out);
    }
  };
  const ts = new TransformStream(transformer);
  setSlot(this, { isDecoderStream: true, transform: ts, decoder });
}
iface('TextDecoderStream', TextDecoderStream, null);
attributes(TextDecoderStream.prototype, {
  encoding: { get() { const s = slotOf(this); if (!s || !s.isDecoderStream) throw new TypeError('Illegal invocation'); return s.decoder.encoding; } },
  fatal: { get() { const s = slotOf(this); if (!s || !s.isDecoderStream) throw new TypeError('Illegal invocation'); return s.decoder.fatal; } },
  ignoreBOM: { get() { const s = slotOf(this); if (!s || !s.isDecoderStream) throw new TypeError('Illegal invocation'); return s.decoder.ignoreBOM; } },
  readable: { get() { const s = slotOf(this); if (!s || !s.isDecoderStream) throw new TypeError('Illegal invocation'); return s.transform.readable; } },
  writable: { get() { const s = slotOf(this); if (!s || !s.isDecoderStream) throw new TypeError('Illegal invocation'); return s.transform.writable; } }
});
