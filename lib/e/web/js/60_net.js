// Networking and binary data: Blob, File, FileReader, FormData, Headers, Request, Response, fetch, XMLHttpRequest.
// Bodies travel as "binary strings" (one code unit per byte) between this layer and the host.

function bytesToBinary(u8) {
  let out = '';
  const n = u8.length;
  for (let i = 0; i < n; i += 4096) out += String.fromCharCode.apply(null, u8.subarray(i, Math.min(n, i + 4096)));
  return out;
}
function binaryToBytes(s) {
  const u8 = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) u8[i] = s.charCodeAt(i);
  return u8;
}
function bufferSourceBytes(x) {
  if (x instanceof ArrayBuffer) return new Uint8Array(x);
  if (ArrayBuffer.isView(x)) return new Uint8Array(x.buffer, x.byteOffset, x.byteLength);
  return null;
}

// --- Blob and File

function Blob(blobParts = undefined, options = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Blob': Please use the 'new' operator");
  initBlob(this, blobParts, options, 'Blob');
}
function initBlob(self, blobParts, options, who) {
  let endings = 'transparent', type = '';
  if (options !== undefined && options !== null) {
    if (!isObject(options)) throw new TypeError("Failed to construct '" + who + "': The provided value is not of type 'BlobPropertyBag'.");
    if (options.endings !== undefined) {
      endings = String(options.endings);
      if (endings !== 'transparent' && endings !== 'native') throw new TypeError("Failed to construct '" + who + "': The provided value '" + endings + "' is not a valid enum value of type EndingType.");
    }
    if (options.type !== undefined) { const t = toDOMString(options.type); type = /^[\x20-\x7E]*$/.test(t) ? asciiLowercase(t) : ''; }
  }
  let bytes = '';
  if (blobParts !== undefined) {
    if (!isObject(blobParts) || typeof blobParts[symIterator] !== 'function') throw new TypeError("Failed to construct '" + who + "': The provided value cannot be converted to a sequence.");
    for (const p of blobParts) {
      if (isObject(p) && slotOf(p) && slotOf(p).isBlob) bytes += slotOf(p).bytes;
      else if (bufferSourceBytes(p) !== null) bytes += bytesToBinary(bufferSourceBytes(p));
      else {
        let str = toUSVString(p);
        if (endings === 'native') str = str.replace(/\r\n|\r|\n/g, '\n');
        bytes += N.utf8Encode(str);
      }
    }
  }
  setSlot(self, { isBlob: true, bytes, type });
}
iface('Blob', Blob, null);
function blobSlot(o) { const s = slotOf(o); if (!s || !s.isBlob) illegal(); return s; }
attributes(Blob.prototype, {
  size: { get() { return blobSlot(this).bytes.length; } },
  type: { get() { return blobSlot(this).type; } }
});
operations(Blob.prototype, {
  slice(start = undefined, end = undefined, contentType = undefined) {
    const s = blobSlot(this);
    const len = s.bytes.length;
    let from = start === undefined ? 0 : Math.trunc(+start) || 0, to = end === undefined ? len : Math.trunc(+end) || 0;
    from = from < 0 ? Math.max(len + from, 0) : Math.min(from, len);
    to = to < 0 ? Math.max(len + to, 0) : Math.min(to, len);
    const b = new Blob([], { type: contentType === undefined ? '' : toDOMString(contentType) });
    slotOf(b).bytes = s.bytes.slice(from, Math.max(from, to));
    return b;
  },
  text() { const s = blobSlot(this); return Promise.resolve(N.utf8Decode(s.bytes)); },
  arrayBuffer() { const s = blobSlot(this); return Promise.resolve(binaryToBytes(s.bytes).buffer); },
  bytes() { const s = blobSlot(this); return Promise.resolve(binaryToBytes(s.bytes)); },
  stream() { const s = blobSlot(this); return streamOfBytes(binaryToBytes(s.bytes)); }
});
function streamOfBytes(u8) {
  return new ReadableStream({ type: 'bytes', start(controller) { if (u8.length > 0) controller.enqueue(u8.slice()); controller.close(); } });
}
// Reads a stream-backed body to the end as a binary string.
async function readStreamBody(stream) {
  const reader = stream.getReader();
  let out = '';
  for (;;) {
    const r = await reader.read();
    if (r.done) break;
    if (!(r.value instanceof Uint8Array)) throw new TypeError('Failed to read the body: a chunk is not a Uint8Array');
    out += bytesToBinary(r.value);
  }
  return out;
}

function File(fileBits, fileName, options = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'File': Please use the 'new' operator");
  required(arguments, 2, 'File');
  initBlob(this, fileBits, options, 'File');
  const s = slotOf(this);
  s.isFile = true;
  s.name = toUSVString(fileName);
  s.lastModified = options && options.lastModified !== undefined ? Math.trunc(+options.lastModified) : Date.now();
}
iface('File', File, Blob);
attributes(File.prototype, {
  name: { get() { const s = slotOf(this); if (!s || !s.isFile) illegal(); return s.name; } },
  lastModified: { get() { const s = slotOf(this); if (!s || !s.isFile) illegal(); return s.lastModified; } },
  webkitRelativePath: { get() { return ''; } }
});

function FileReader() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'FileReader': Please use the 'new' operator");
  setSlot(this, { listeners: [], isTarget: true, isReader: true, readyState: 0, result: null, error: null });
}
iface('FileReader', FileReader, EventTarget);
constants(FileReader, { EMPTY: 0, LOADING: 1, DONE: 2 });
function frSlot(o) { const s = slotOf(o); if (!s || !s.isReader) illegal(); return s; }
function frFire(reader, type, extra) {
  const ev = new ProgressEvent(type, extra || {});
  slotOf(ev).isTrusted = true;
  dispatch(ev, reader);
}
function frRead(reader, blob, kind, encoding) {
  const s = frSlot(reader);
  if (s.readyState === 1) throw domError('InvalidStateError', 'The object is in an invalid state.');
  if (!isObject(blob) || !slotOf(blob) || !slotOf(blob).isBlob) throw new TypeError("Failed to execute 'read' on 'FileReader': parameter 1 is not of type 'Blob'.");
  s.readyState = 1; s.result = null;
  const bytes = slotOf(blob).bytes, type = slotOf(blob).type;
  scheduleTimer(() => {
    if (s.aborted) { s.aborted = false; return; }
    frFire(reader, 'loadstart');
    s.result = kind === 'text' ? N.utf8Decode(bytes) : kind === 'dataurl' ? 'data:' + (type || 'application/octet-stream') + ';base64,' + btoa(bytes) : kind === 'binarystring' ? bytes : binaryToBytes(bytes).buffer;
    s.readyState = 2;
    frFire(reader, 'progress', { lengthComputable: true, loaded: bytes.length, total: bytes.length });
    frFire(reader, 'load', { lengthComputable: true, loaded: bytes.length, total: bytes.length });
    frFire(reader, 'loadend', { lengthComputable: true, loaded: bytes.length, total: bytes.length });
  }, 0, false, []);
}
operations(FileReader.prototype, {
  readAsArrayBuffer(blob) { frRead(this, blob, 'arraybuffer'); },
  readAsBinaryString(blob) { frRead(this, blob, 'binarystring'); },
  readAsText(blob, encoding = undefined) { frRead(this, blob, 'text', encoding); },
  readAsDataURL(blob) { frRead(this, blob, 'dataurl'); },
  abort() { const s = frSlot(this); if (s.readyState === 1) { s.readyState = 2; s.result = null; s.aborted = true; frFire(this, 'abort'); frFire(this, 'loadend'); } }
});
attributes(FileReader.prototype, {
  readyState: { get() { return frSlot(this).readyState; } },
  result: { get() { return frSlot(this).result; } },
  error: { get() { return frSlot(this).error; } }
});
defineHandlerAttrs(FileReader.prototype, ['loadstart', 'progress', 'load', 'abort', 'error', 'loadend']);

// --- FormData

function FormData(form = undefined, submitter = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'FormData': Please use the 'new' operator");
  const s = setSlot(this, { isFormData: true, entries: [] });
  if (form !== undefined) {
    if (!isObject(form) || !slotOf(form) || slotOf(form).localName !== 'form') throw new TypeError("Failed to construct 'FormData': parameter 1 is not of type 'HTMLFormElement'.");
    for (const e of constructEntryList(form, submitter)) s.entries.push(e);
  }
}
iface('FormData', FormData, null);
const constructEntryList = (form, submitter) => constructEntryListImpl(form, submitter);
function fdSlot(o) { const s = slotOf(o); if (!s || !s.isFormData) illegal(); return s; }
function fdValue(value, filename) {
  if (isObject(value) && slotOf(value) && slotOf(value).isBlob) {
    if (!slotOf(value).isFile || filename !== undefined) {
      const f = new File([value], filename !== undefined ? filename : (slotOf(value).isFile ? slotOf(value).name : 'blob'), { type: slotOf(value).type });
      return f;
    }
    return value;
  }
  return toUSVString(value);
}
operations(FormData.prototype, {
  append(name, value, filename = undefined) { const s = fdSlot(this); required(arguments, 2, 'append'); s.entries.push([toUSVString(name), fdValue(value, filename === undefined ? undefined : toUSVString(filename))]); },
  delete(name) { const s = fdSlot(this); required(arguments, 1, 'delete'); const n = toUSVString(name); s.entries = s.entries.filter(e => e[0] !== n); },
  get(name) { const s = fdSlot(this); required(arguments, 1, 'get'); const n = toUSVString(name); for (const e of s.entries) if (e[0] === n) return e[1]; return null; },
  getAll(name) { const s = fdSlot(this); required(arguments, 1, 'getAll'); const n = toUSVString(name); return s.entries.filter(e => e[0] === n).map(e => e[1]); },
  has(name) { const s = fdSlot(this); required(arguments, 1, 'has'); const n = toUSVString(name); return s.entries.some(e => e[0] === n); },
  set(name, value, filename = undefined) {
    const s = fdSlot(this);
    required(arguments, 2, 'set');
    const n = toUSVString(name);
    const v = fdValue(value, filename === undefined ? undefined : toUSVString(filename));
    let found = false;
    const out = [];
    for (const e of s.entries) { if (e[0] === n) { if (!found) { found = true; out.push([n, v]); } } else out.push(e); }
    if (!found) out.push([n, v]);
    s.entries = out;
  },
  forEach(callback, thisArg = undefined) {
    const s = fdSlot(this);
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError("Failed to execute 'forEach' on 'FormData': parameter 1 is not of type 'Function'.");
    for (let i = 0; i < s.entries.length; i++) apply(callback, thisArg, [s.entries[i][1], s.entries[i][0], this]);
  },
  keys() { fdSlot(this); return makeListIterator(this, 'key', s => s.entries); },
  values() { fdSlot(this); return makeListIterator(this, 'value', s => s.entries); },
  entries() { fdSlot(this); return makeListIterator(this, 'key+value', s => s.entries); }
});
defineProperty(FormData.prototype, symIterator, { value: FormData.prototype.entries, writable: true, enumerable: false, configurable: true });
const ListIteratorProtos = {};
function makeListIterator(target, kind, getList) {
  const name = 'List Iterator';
  let proto = ListIteratorProtos[target.constructor.name];
  if (!proto) {
    proto = create(IteratorProto);
    defineProperty(proto, symToStringTag, { value: target.constructor.name + ' Iterator', configurable: true });
    operations(proto, {
      next() {
        const s = slotOf(this);
        if (!s || !s.isListIterator) illegal();
        const list = s.getList(slotOf(s.target));
        if (s.index >= list.length) return { value: undefined, done: true };
        const e = list[s.index++];
        return { value: s.kind === 'key' ? e[0] : s.kind === 'value' ? e[1] : [e[0], e[1]], done: false };
      }
    });
    defineProperty(proto, 'next', { enumerable: true });
    ListIteratorProtos[target.constructor.name] = proto;
  }
  const it = create(proto);
  setSlot(it, { isListIterator: true, target, kind, index: 0, getList });
  return it;
}

// --- Headers

function normalizeHeaderValue(v) { return toDOMString(v).replace(/^[\t\n\r ]+|[\t\n\r ]+$/g, ''); }
function validHeaderName(n) { return /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(n); }
function validHeaderValue(v) { return !/[\0\r\n]/.test(v); }
function Headers(init = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Headers': Please use the 'new' operator");
  const s = setSlot(this, { isHeaders: true, list: [], guard: 'none' });
  if (init !== undefined && init !== null) fillHeaders(this, init);
}
iface('Headers', Headers, null);
function hSlot(o) { const s = slotOf(o); if (!s || !s.isHeaders) illegal(); return s; }
function fillHeaders(h, init) {
  if (isObject(init)) {
    if (typeof init[symIterator] === 'function') {
      for (const pair of init) {
        const items = Array.from(pair);
        if (items.length !== 2) throw new TypeError("Failed to construct 'Headers': Invalid value");
        appendHeader(h, toDOMString(items[0]), toDOMString(items[1]));
      }
    } else {
      for (const key of Reflect.ownKeys(init)) {
        if (typeof key !== 'string') continue;
        const d = getOwnPropertyDescriptor(init, key);
        if (d !== undefined && d.enumerable) appendHeader(h, key, toDOMString(init[key]));
      }
    }
  } else throw new TypeError("Failed to construct 'Headers': The provided value is not of type '(sequence<sequence<ByteString>> or record<ByteString, ByteString>)'.");
}
function appendHeader(h, name, value) {
  const s = hSlot(h);
  const v = normalizeHeaderValue(value);
  if (!validHeaderName(name)) throw new TypeError("Failed to execute 'append' on 'Headers': Invalid name");
  if (!validHeaderValue(v)) throw new TypeError("Failed to execute 'append' on 'Headers': Invalid value");
  if (s.guard === 'immutable') throw new TypeError('Headers are immutable');
  if (s.guard === 'request' && forbiddenRequestHeader(name)) return;
  if (s.guard === 'response' && forbiddenResponseHeader(name)) return;
  s.list.push([asciiLowercase(name), v, name]);
}
function forbiddenRequestHeader(n) {
  const l = asciiLowercase(n);
  return ['accept-charset', 'accept-encoding', 'access-control-request-headers', 'access-control-request-method', 'connection', 'content-length', 'cookie', 'cookie2', 'date', 'dnt', 'expect', 'host', 'keep-alive', 'origin', 'referer', 'set-cookie', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'via'].indexOf(l) >= 0 || l.startsWith('proxy-') || l.startsWith('sec-');
}
function forbiddenResponseHeader(n) { const l = asciiLowercase(n); return l === 'set-cookie' || l === 'set-cookie2'; }
function sortedHeaderList(s) {
  const names = [];
  for (const e of s.list) if (names.indexOf(e[0]) < 0) names.push(e[0]);
  names.sort();
  const out = [];
  for (const n of names) {
    if (n === 'set-cookie') { for (const e of s.list) if (e[0] === n) out.push([n, e[1]]); }
    else out.push([n, s.list.filter(e => e[0] === n).map(e => e[1]).join(', ')]);
  }
  return out;
}
operations(Headers.prototype, {
  append(name, value) { hSlot(this); required(arguments, 2, 'append'); appendHeader(this, toDOMString(name), toDOMString(value)); },
  delete(name) { const s = hSlot(this); required(arguments, 1, 'delete'); const n = toDOMString(name); if (!validHeaderName(n)) throw new TypeError("Failed to execute 'delete' on 'Headers': Invalid name"); if (s.guard === 'immutable') throw new TypeError('Headers are immutable'); const l = asciiLowercase(n); s.list = s.list.filter(e => e[0] !== l); },
  get(name) { const s = hSlot(this); required(arguments, 1, 'get'); const n = toDOMString(name); if (!validHeaderName(n)) throw new TypeError("Failed to execute 'get' on 'Headers': Invalid name"); const l = asciiLowercase(n); const vals = s.list.filter(e => e[0] === l).map(e => e[1]); return vals.length ? vals.join(', ') : null; },
  getSetCookie() { const s = hSlot(this); return s.list.filter(e => e[0] === 'set-cookie').map(e => e[1]); },
  has(name) { const s = hSlot(this); required(arguments, 1, 'has'); const n = toDOMString(name); if (!validHeaderName(n)) throw new TypeError("Failed to execute 'has' on 'Headers': Invalid name"); const l = asciiLowercase(n); return s.list.some(e => e[0] === l); },
  set(name, value) {
    const s = hSlot(this);
    required(arguments, 2, 'set');
    const n = toDOMString(name), v = normalizeHeaderValue(value);
    if (!validHeaderName(n)) throw new TypeError("Failed to execute 'set' on 'Headers': Invalid name");
    if (!validHeaderValue(v)) throw new TypeError("Failed to execute 'set' on 'Headers': Invalid value");
    if (s.guard === 'immutable') throw new TypeError('Headers are immutable');
    if (s.guard === 'request' && forbiddenRequestHeader(n)) return;
    if (s.guard === 'response' && forbiddenResponseHeader(n)) return;
    const l = asciiLowercase(n);
    const idx = s.list.findIndex(e => e[0] === l);
    if (idx < 0) { s.list.push([l, v, n]); return; }
    s.list[idx] = [l, v, n];
    s.list = s.list.filter((e, i) => i === idx || e[0] !== l);
  },
  forEach(callback, thisArg = undefined) {
    const s = hSlot(this);
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError("Failed to execute 'forEach' on 'Headers': parameter 1 is not of type 'Function'.");
    for (const e of sortedHeaderList(s)) apply(callback, thisArg, [e[1], e[0], this]);
  },
  keys() { hSlot(this); return makeListIterator(this, 'key', s => sortedHeaderList(s)); },
  values() { hSlot(this); return makeListIterator(this, 'value', s => sortedHeaderList(s)); },
  entries() { hSlot(this); return makeListIterator(this, 'key+value', s => sortedHeaderList(s)); }
});
defineProperty(Headers.prototype, symIterator, { value: Headers.prototype.entries, writable: true, enumerable: false, configurable: true });
function headersFrom(list, guard) {
  const h = new Headers();
  slotOf(h).guard = 'none';
  for (const e of list) slotOf(h).list.push([asciiLowercase(e[0]), e[1], e[0]]);
  slotOf(h).guard = guard;
  return h;
}

// --- Body mixin shared by Request and Response

function extractBody(object, keepalive) {
  if (object === null || object === undefined) return null;
  if (isObject(object) && slotOf(object) && slotOf(object).isBlob) return { bytes: slotOf(object).bytes, type: slotOf(object).type || null };
  if (typeof object === 'string' || object instanceof String) return { bytes: N.utf8Encode(toUSVString(object)), type: 'text/plain;charset=UTF-8' };
  if (isObject(object) && slotOf(object) && slotOf(object).isParams) return { bytes: N.utf8Encode(serializeUrlEncoded(slotOf(object).list)), type: 'application/x-www-form-urlencoded;charset=UTF-8' };
  if (isObject(object) && slotOf(object) && slotOf(object).isFormData) return multipartBody(slotOf(object).entries);
  const bs = bufferSourceBytes(object);
  if (bs !== null) return { bytes: bytesToBinary(bs), type: null };
  if (isReadableStreamLike(object)) { if (isReadableStreamLocked(object) || slotOf(object).disturbed) throw new TypeError('The stream is locked or disturbed'); return { stream: object, bytes: null, type: null }; }
  return { bytes: N.utf8Encode(toUSVString(object)), type: 'text/plain;charset=UTF-8' };
}
function multipartBody(entries) {
  const boundary = '----formdata-neper-' + Math.floor(Math.random() * 1e9);
  let out = '';
  for (const [name, value] of entries) {
    const esc = s => s.replace(/\n/g, '%0A').replace(/\r/g, '%0D').replace(/"/g, '%22');
    out += '--' + boundary + '\r\n';
    if (typeof value === 'string') out += N.utf8Encode('Content-Disposition: form-data; name="' + esc(name) + '"\r\n\r\n' + value.replace(/\r?\n|\r/g, '\r\n') + '\r\n');
    else out += N.utf8Encode('Content-Disposition: form-data; name="' + esc(name) + '"; filename="' + esc(slotOf(value).name) + '"\r\nContent-Type: ' + (slotOf(value).type || 'application/octet-stream') + '\r\n\r\n') + slotOf(value).bytes + '\r\n';
  }
  out += '--' + boundary + '--\r\n';
  return { bytes: out, type: 'multipart/form-data; boundary=' + boundary };
}
function bodyMixin(proto, isResponse) {
  const take = (self, name) => {
    const s = slotOf(self);
    if (!s || !(s.isRequest || s.isResponse)) illegal();
    if (s.bodyUsed || (s.body && s.body.stream && (isReadableStreamLocked(s.body.stream) || slotOf(s.body.stream).disturbed))) return Promise.reject(new TypeError("Failed to execute '" + name + "': body stream already read"));
    s.bodyUsed = true;
    if (s.body !== null && s.body.stream) return readStreamBody(s.body.stream);
    return Promise.resolve(s.body === null || s.body.bytes === null ? '' : s.body.bytes);
  };
  operations(proto, {
    text() { return take(this, 'text').then(b => N.utf8Decode(b)); },
    json() { return take(this, 'json').then(b => JSON.parse(N.utf8Decode(b))); },
    arrayBuffer() { return take(this, 'arrayBuffer').then(b => binaryToBytes(b).buffer); },
    bytes() { return take(this, 'bytes').then(b => binaryToBytes(b)); },
    blob() {
      const s = slotOf(this);
      const type = s && s.headers ? (slotOf(s.headers).list.filter(e => e[0] === 'content-type').map(e => e[1])[0] || '') : '';
      return take(this, 'blob').then(b => { const blob = new Blob([], { type }); slotOf(blob).bytes = b; return blob; });
    },
    formData() {
      const s = slotOf(this);
      const ct = s && s.headers ? (slotOf(s.headers).list.filter(e => e[0] === 'content-type').map(e => e[1])[0] || '') : '';
      return take(this, 'formData').then(b => {
        const fd = new FormData();
        if (/^application\/x-www-form-urlencoded/i.test(ct)) { for (const [n, v] of parseUrlEncoded(N.utf8Decode(b))) fd.append(n, v); return fd; }
        throw new TypeError('Failed to fetch: could not parse the body as FormData');
      });
    }
  });
  attributes(proto, {
    body: { get() { const s = slotOf(this); if (!s || !(s.isRequest || s.isResponse)) illegal(); if (s.body === null) return null; if (!s.body.stream) s.body.stream = streamOfBytes(binaryToBytes(s.body.bytes)); return s.body.stream; } },
    bodyUsed: { get() { const s = slotOf(this); if (!s || !(s.isRequest || s.isResponse)) illegal(); return s.bodyUsed || (!!(s.body && s.body.stream) && !!slotOf(s.body.stream).disturbed); } }
  });
}

// --- Request

function Request(input, init = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Request': Please use the 'new' operator");
  required(arguments, 1, 'Request');
  const s = setSlot(this, { isRequest: true, method: 'GET', url: '', headers: null, body: null, bodyUsed: false, signal: null, mode: 'cors', credentials: 'same-origin', cache: 'default', redirect: 'follow', referrer: 'about:client', referrerPolicy: '', integrity: '', keepalive: false });
  let inputSlot = isObject(input) ? slotOf(input) : null;
  if (inputSlot && inputSlot.isRequest) {
    s.url = inputSlot.url; s.method = inputSlot.method; s.mode = inputSlot.mode; s.credentials = inputSlot.credentials; s.cache = inputSlot.cache; s.redirect = inputSlot.redirect;
    s.referrer = inputSlot.referrer; s.referrerPolicy = inputSlot.referrerPolicy; s.integrity = inputSlot.integrity; s.keepalive = inputSlot.keepalive;
    s.headers = new Headers(inputSlot.headers); slotOf(s.headers).guard = 'request';
    s.body = inputSlot.body;
    s.signal = inputSlot.signal;
  } else {
    const parsed = N.urlParse(toUSVString(input), documentBaseURL(mainDocument));
    if (parsed === null) throw new TypeError("Failed to construct 'Request': Failed to parse URL from " + toUSVString(input));
    if (parsed[2] !== '' || parsed[3] !== '') throw new TypeError("Failed to construct 'Request': Request cannot be constructed from a URL that includes credentials");
    s.url = parsed[0];
    s.headers = new Headers(); slotOf(s.headers).guard = 'request';
  }
  if (init !== undefined && init !== null) {
    if (!isObject(init)) throw new TypeError("Failed to construct 'Request': The provided value is not of type 'RequestInit'.");
    if (init.method !== undefined) {
      const m = toDOMString(init.method);
      if (!validHeaderName(m)) throw new TypeError("Failed to construct 'Request': '" + m + "' is not a valid HTTP method.");
      const up = asciiLowercase(m);
      if (['connect', 'trace', 'track'].indexOf(up) >= 0) throw new TypeError("Failed to construct 'Request': '" + m + "' HTTP method is unsupported.");
      s.method = ['delete', 'get', 'head', 'options', 'post', 'put'].indexOf(up) >= 0 ? asciiUppercase(m) : m;
    }
    if (init.mode !== undefined) { s.mode = toDOMString(init.mode); if (s.mode === 'navigate') throw new TypeError('Invalid mode'); }
    if (init.credentials !== undefined) s.credentials = toDOMString(init.credentials);
    if (init.cache !== undefined) s.cache = toDOMString(init.cache);
    if (init.redirect !== undefined) s.redirect = toDOMString(init.redirect);
    if (init.referrer !== undefined) s.referrer = toDOMString(init.referrer);
    if (init.referrerPolicy !== undefined) s.referrerPolicy = toDOMString(init.referrerPolicy);
    if (init.integrity !== undefined) s.integrity = toDOMString(init.integrity);
    if (init.keepalive !== undefined) s.keepalive = !!init.keepalive;
    if (init.signal !== undefined && init.signal !== null) { if (!isAbortSignal(init.signal)) throw new TypeError("Failed to construct 'Request': member signal is not of type AbortSignal."); s.signal = init.signal; }
    if (init.headers !== undefined) { const h = new Headers(); slotOf(h).guard = 'request'; fillHeaders(h, init.headers); s.headers = h; }
    if (init.body !== undefined && init.body !== null) {
      if (s.method === 'GET' || s.method === 'HEAD') throw new TypeError("Failed to construct 'Request': Request with GET/HEAD method cannot have body.");
      const b = extractBody(init.body);
      s.body = b;
      if (b.type !== null && !slotOf(s.headers).list.some(e => e[0] === 'content-type')) appendHeader(s.headers, 'Content-Type', b.type);
    }
  }
  if (s.signal === null) s.signal = newSignal();
}
iface('Request', Request, null);
function reqSlot(o) { const s = slotOf(o); if (!s || !s.isRequest) illegal(); return s; }
attributes(Request.prototype, {
  method: { get() { return reqSlot(this).method; } },
  url: { get() { return reqSlot(this).url; } },
  headers: { get() { return reqSlot(this).headers; } },
  destination: { get() { reqSlot(this); return ''; } },
  referrer: { get() { const s = reqSlot(this); return s.referrer === 'about:client' ? 'about:client' : s.referrer; } },
  referrerPolicy: { get() { return reqSlot(this).referrerPolicy; } },
  mode: { get() { return reqSlot(this).mode; } },
  credentials: { get() { return reqSlot(this).credentials; } },
  cache: { get() { return reqSlot(this).cache; } },
  redirect: { get() { return reqSlot(this).redirect; } },
  integrity: { get() { return reqSlot(this).integrity; } },
  keepalive: { get() { return reqSlot(this).keepalive; } },
  isReloadNavigation: { get() { reqSlot(this); return false; } },
  isHistoryNavigation: { get() { reqSlot(this); return false; } },
  signal: { get() { return reqSlot(this).signal; } },
  duplex: { get() { reqSlot(this); return 'half'; } }
});
operations(Request.prototype, {
  clone() {
    const s = reqSlot(this);
    if (s.bodyUsed) throw new TypeError("Failed to execute 'clone' on 'Request': Request body is already used");
    const r = new Request(this);
    return r;
  }
});
bodyMixin(Request.prototype, false);

// --- Response

function Response(body = null, init = undefined) {
  if (new.target === undefined) throw new TypeError("Failed to construct 'Response': Please use the 'new' operator");
  const s = setSlot(this, { isResponse: true, status: 200, statusText: '', headers: null, body: null, bodyUsed: false, type: 'default', url: '', redirected: false });
  s.headers = new Headers(); slotOf(s.headers).guard = 'response';
  if (init !== undefined && init !== null) {
    if (!isObject(init)) throw new TypeError("Failed to construct 'Response': The provided value is not of type 'ResponseInit'.");
    if (init.status !== undefined) { const st = toUnsignedShort(init.status); if (st < 200 || st > 599) throw new RangeError("Failed to construct 'Response': The status provided (" + st + ') is outside the range [200, 599].'); s.status = st; }
    if (init.statusText !== undefined) { const t = toDOMString(init.statusText); if (/[^\t\x20-\x7E\x80-\xFF]/.test(t)) throw new TypeError('Invalid statusText'); s.statusText = t; }
    if (init.headers !== undefined) fillHeaders(s.headers, init.headers);
  }
  if (body !== null && body !== undefined) {
    if ([101, 204, 205, 304].indexOf(s.status) >= 0) throw new TypeError("Failed to construct 'Response': Response with null body status cannot have body");
    const b = extractBody(body);
    s.body = b;
    if (b.type !== null && !slotOf(s.headers).list.some(e => e[0] === 'content-type')) appendHeader(s.headers, 'Content-Type', b.type);
  }
}
iface('Response', Response, null);
function respSlot(o) { const s = slotOf(o); if (!s || !s.isResponse) illegal(); return s; }
attributes(Response.prototype, {
  type: { get() { return respSlot(this).type; } },
  url: { get() { return respSlot(this).url; } },
  redirected: { get() { return respSlot(this).redirected; } },
  status: { get() { return respSlot(this).status; } },
  ok: { get() { const st = respSlot(this).status; return st >= 200 && st <= 299; } },
  statusText: { get() { return respSlot(this).statusText; } },
  headers: { get() { return respSlot(this).headers; } }
});
operations(Response.prototype, {
  clone() {
    const s = respSlot(this);
    if (s.bodyUsed) throw new TypeError("Failed to execute 'clone' on 'Response': Response body is already used");
    const r = new Response(null, { status: s.status === 0 ? 200 : s.status, statusText: s.statusText });
    const rs = slotOf(r);
    rs.status = s.status; rs.type = s.type; rs.url = s.url; rs.redirected = s.redirected;
    rs.headers = new Headers(s.headers); slotOf(rs.headers).guard = slotOf(s.headers).guard;
    rs.body = s.body === null ? null : { bytes: s.body.bytes, type: s.body.type };
    return r;
  }
});
operations(Response, {
  error() { const r = new Response(null, { status: 200 }); const s = slotOf(r); s.status = 0; s.type = 'error'; slotOf(s.headers).guard = 'immutable'; return r; },
  redirect(url, status = 302) {
    const parsed = N.urlParse(toUSVString(url), documentBaseURL(mainDocument));
    if (parsed === null) throw new TypeError("Failed to execute 'redirect' on 'Response': Invalid URL");
    if ([301, 302, 303, 307, 308].indexOf(status) < 0) throw new RangeError("Failed to execute 'redirect' on 'Response': Invalid status code");
    const r = new Response(null, { status });
    slotOf(r.headers).guard = 'none';
    r.headers.set('Location', parsed[0]);
    slotOf(r.headers).guard = 'immutable';
    return r;
  },
  json(data, init = undefined) {
    const text = JSON.stringify(data);
    if (text === undefined) throw new TypeError("Failed to execute 'json' on 'Response': The data is not JSON serializable");
    const r = new Response(text, init);
    if (!slotOf(r.headers).list.some(e => e[0] === 'content-type') || true) { slotOf(r.headers).list = slotOf(r.headers).list.filter(e => e[0] !== 'content-type'); r.headers.set('Content-Type', 'application/json'); }
    return r;
  }
});
bodyMixin(Response.prototype, true);

// --- fetch

function performRequest(method, url, headers, bodyBinary) {
  const blob = urlBlobRegistry[url];
  if (blob !== undefined) return { status: 200, statusText: 'OK', url, headers: [['content-type', blob.type]], body: blob.bytes };
  if (url.startsWith('data:')) return dataURLResponse(url);
  const raw = N.net(method, url, headers.map(h => h[0] + ': ' + h[1]).join('\n'), bodyBinary === null ? '' : bodyBinary);
  return raw;
}
const urlBlobRegistry = {};
function dataURLResponse(url) {
  const comma = url.indexOf(',');
  if (comma < 0) return null;
  const meta = url.slice(5, comma);
  const payload = url.slice(comma + 1);
  const isBase64 = /;base64$/i.test(meta);
  const type = (isBase64 ? meta.slice(0, -7) : meta) || 'text/plain;charset=US-ASCII';
  let bytes;
  if (isBase64) { try { bytes = atob(percentDecodeToBinary(payload)); } catch (e) { return null; } }
  else bytes = percentDecodeToBinary(payload);
  return { status: 200, statusText: 'OK', url, headers: [['content-type', type]], body: bytes };
}
function percentDecodeToBinary(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '%' && /^[0-9a-fA-F]{2}$/.test(s.slice(i + 1, i + 3))) { out += String.fromCharCode(parseInt(s.slice(i + 1, i + 3), 16)); i += 2; }
    else out += N.utf8Encode(s[i] + (s.codePointAt(i) > 0xFFFF ? s[++i] : ''));
  }
  return out;
}
function fetchImpl(input, init) {
  return new Promise((resolve, reject) => {
    let request;
    try { request = new Request(input, init); } catch (e) { reject(e); return; }
    const rs = slotOf(request);
    if (isAbortSignal(rs.signal) && slotOf(rs.signal).aborted) { reject(slotOf(rs.signal).reason); return; }
    const abortHandler = () => { reject(slotOf(rs.signal).reason); aborted = true; };
    let aborted = false;
    scheduleTimer(() => {
      if (aborted) return;
      let raw = null;
      try {
        const headers = slotOf(rs.headers).list.map(e => [e[2] || e[0], e[1]]);
        raw = performRequest(rs.method, rs.url, headers, rs.body === null ? null : rs.body.bytes);
      } catch (e) { reject(new TypeError('Failed to fetch')); return; }
      if (raw === null) { reject(new TypeError('Failed to fetch')); return; }
      const r = new Response(null, { status: raw.status >= 200 && raw.status <= 599 ? raw.status : 200 });
      const s = slotOf(r);
      s.status = raw.status; s.statusText = raw.statusText || ''; s.url = raw.url || rs.url; s.type = 'basic'; s.redirected = (raw.url || rs.url) !== rs.url;
      slotOf(s.headers).guard = 'none';
      for (const h of raw.headers) slotOf(s.headers).list.push([asciiLowercase(h[0]), h[1], h[0]]);
      slotOf(s.headers).guard = 'immutable';
      s.body = rs.method === 'HEAD' || [101, 204, 205, 304].indexOf(raw.status) >= 0 ? null : { bytes: raw.body, type: null };
      resolve(r);
    }, 0, false, []);
    if (isAbortSignal(rs.signal)) apply(arrayPush, slotOf(rs.signal).algorithms, [abortHandler]);
  });
}
defineProperty(global, 'fetch', { value: function fetch(input, init = undefined) { required(arguments, 1, 'fetch'); return fetchImpl(input, init); }, writable: true, enumerable: true, configurable: true });
URL.createObjectURL = function createObjectURL(obj) {
  if (!isObject(obj) || !slotOf(obj) || !slotOf(obj).isBlob) throw new TypeError("Failed to execute 'createObjectURL' on 'URL': Overload resolution failed.");
  const url = 'blob:' + slotOf(mainDocument).origin + '/' + (++blobCounter) + '-' + Math.floor(Math.random() * 1e9);
  urlBlobRegistry[url] = { bytes: slotOf(obj).bytes, type: slotOf(obj).type };
  return url;
};
URL.revokeObjectURL = function revokeObjectURL(url) { delete urlBlobRegistry[toDOMString(url)]; };
defineProperty(URL, 'createObjectURL', { enumerable: true });
defineProperty(URL, 'revokeObjectURL', { enumerable: true });

// --- XMLHttpRequest

function XMLHttpRequestEventTarget() { throw new TypeError('Illegal constructor'); }
iface('XMLHttpRequestEventTarget', XMLHttpRequestEventTarget, EventTarget);
defineHandlerAttrs(XMLHttpRequestEventTarget.prototype, ['loadstart', 'progress', 'abort', 'error', 'load', 'timeout', 'loadend']);
function XMLHttpRequestUpload() { throw new TypeError('Illegal constructor'); }
iface('XMLHttpRequestUpload', XMLHttpRequestUpload, XMLHttpRequestEventTarget);
function XMLHttpRequest() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'XMLHttpRequest': Please use the 'new' operator");
  const upload = create(XMLHttpRequestUpload.prototype);
  setSlot(upload, { listeners: [], isTarget: true });
  setSlot(this, { listeners: [], isTarget: true, isXHR: true, state: 0, upload, timeout: 0, withCredentials: false, responseType: '', method: 'GET', url: '', async: true, requestHeaders: [], sendFlag: false, status: 0, statusText: '', responseHeaders: [], responseBytes: '', mimeOverride: null, errorFlag: false, token: 0, handlers: {} });
}
iface('XMLHttpRequest', XMLHttpRequest, XMLHttpRequestEventTarget);
constants(XMLHttpRequest, { UNSENT: 0, OPENED: 1, HEADERS_RECEIVED: 2, LOADING: 3, DONE: 4 });
function xhrSlot(o) { const s = slotOf(o); if (!s || !s.isXHR) illegal(); return s; }
function xhrFire(xhr, target, type, loaded, total) {
  const ev = new ProgressEvent(type, { lengthComputable: total > 0, loaded, total });
  slotOf(ev).isTrusted = true;
  dispatch(ev, target);
}
function xhrReadyState(xhr, state) {
  const s = slotOf(xhr);
  s.state = state;
  const ev = new Event('readystatechange');
  slotOf(ev).isTrusted = true;
  dispatch(ev, xhr);
}
function xhrContentType(s) {
  const h = s.responseHeaders.filter(e => e[0] === 'content-type').map(e => e[1])[0];
  return s.mimeOverride || h || '';
}
function xhrResponseText(s) { return N.utf8Decode(s.responseBytes); }
function xhrRun(xhr, body) {
  const s = slotOf(xhr);
  let raw = null;
  try { raw = performRequest(s.method, s.url, s.requestHeaders, body); } catch (e) { raw = null; }
  return raw;
}
function xhrComplete(xhr, raw, sync) {
  const s = slotOf(xhr);
  if (raw === null) {
    s.errorFlag = true; s.state = 4; s.sendFlag = false; s.status = 0; s.statusText = ''; s.responseBytes = '';
    if (!sync) {
      xhrReadyState(xhr, 4);
      xhrFire(xhr, xhr, 'error', 0, 0); xhrFire(xhr, xhr, 'loadend', 0, 0);
    }
    return;
  }
  s.status = raw.status; s.statusText = raw.statusText || ''; s.responseHeaders = raw.headers.map(h => [asciiLowercase(h[0]), h[1]]); s.responseBytes = raw.body; s.responseUrl = raw.url || s.url;
  if (!sync) {
    xhrReadyState(xhr, 2);
    xhrReadyState(xhr, 3);
    xhrFire(xhr, xhr, 'progress', raw.body.length, raw.body.length);
  }
  s.state = 4; s.sendFlag = false;
  if (!sync) {
    xhrReadyState(xhr, 4);
    xhrFire(xhr, xhr, 'load', raw.body.length, raw.body.length);
    xhrFire(xhr, xhr, 'loadend', raw.body.length, raw.body.length);
  }
}
operations(XMLHttpRequest.prototype, {
  open(method, url, async = true, username = null, password = null) {
    const s = xhrSlot(this);
    required(arguments, 2, 'open');
    const m = toDOMString(method);
    if (!validHeaderName(m)) throw domError('SyntaxError', "Failed to execute 'open' on 'XMLHttpRequest': '" + m + "' is not a valid HTTP method.");
    const up = asciiUppercase(m);
    if (['CONNECT', 'TRACE', 'TRACK'].indexOf(up) >= 0) throw domError('SecurityError', "Failed to execute 'open' on 'XMLHttpRequest': '" + m + "' HTTP method is unsupported.");
    const parsed = N.urlParse(toUSVString(url), documentBaseURL(mainDocument));
    if (parsed === null) throw domError('SyntaxError', "Failed to execute 'open' on 'XMLHttpRequest': Invalid URL");
    s.method = ['DELETE', 'GET', 'HEAD', 'OPTIONS', 'POST', 'PUT'].indexOf(up) >= 0 ? up : m;
    s.url = parsed[0]; s.async = async === undefined ? true : !!async;
    if (!s.async && s.timeout !== 0) throw domError('InvalidAccessError', 'Synchronous requests must not set a timeout.');
    s.requestHeaders = []; s.sendFlag = false; s.errorFlag = false; s.responseBytes = ''; s.status = 0; s.statusText = ''; s.responseHeaders = [];
    s.token++;
    if (s.state !== 1) { s.state = 1; const ev = new Event('readystatechange'); slotOf(ev).isTrusted = true; dispatch(ev, this); }
  },
  setRequestHeader(name, value) {
    const s = xhrSlot(this);
    required(arguments, 2, 'setRequestHeader');
    if (s.state !== 1 || s.sendFlag) throw domError('InvalidStateError', "Failed to execute 'setRequestHeader' on 'XMLHttpRequest': The object's state must be OPENED.");
    const n = toDOMString(name), v = normalizeHeaderValue(value);
    if (!validHeaderName(n)) throw domError('SyntaxError', "Failed to execute 'setRequestHeader' on 'XMLHttpRequest': '" + n + "' is not a valid HTTP header field name.");
    if (!validHeaderValue(v)) throw domError('SyntaxError', "Failed to execute 'setRequestHeader' on 'XMLHttpRequest': '" + v + "' is not a valid HTTP header field value.");
    if (forbiddenRequestHeader(n)) return;
    const l = asciiLowercase(n);
    const ex = s.requestHeaders.find(h => asciiLowercase(h[0]) === l);
    if (ex) ex[1] += ', ' + v; else s.requestHeaders.push([n, v]);
  },
  send(body = null) {
    const s = xhrSlot(this);
    if (s.state !== 1 || s.sendFlag) throw domError('InvalidStateError', "Failed to execute 'send' on 'XMLHttpRequest': The object's state must be OPENED.");
    let bytes = null;
    if ((body !== null && body !== undefined) && s.method !== 'GET' && s.method !== 'HEAD') {
      const b = extractBody(body);
      bytes = b.bytes;
      if (b.type !== null && !s.requestHeaders.some(h => asciiLowercase(h[0]) === 'content-type')) s.requestHeaders.push(['Content-Type', b.type]);
    }
    s.sendFlag = true;
    const token = s.token;
    if (!s.async) {
      xhrFire(this, this, 'loadstart', 0, 0);
      const raw = xhrRun(this, bytes);
      if (raw === null) { s.errorFlag = true; s.state = 4; s.sendFlag = false; xhrReadyState(this, 4); xhrFire(this, this, 'error', 0, 0); xhrFire(this, this, 'loadend', 0, 0); throw domError('NetworkError', "Failed to execute 'send' on 'XMLHttpRequest': Failed to load '" + s.url + "'."); }
      xhrComplete(this, raw, true);
      xhrReadyState(this, 4);
      xhrFire(this, this, 'load', s.responseBytes.length, s.responseBytes.length);
      xhrFire(this, this, 'loadend', s.responseBytes.length, s.responseBytes.length);
      return;
    }
    xhrFire(this, this, 'loadstart', 0, 0);
    scheduleTimer(() => {
      if (s.token !== token || !s.sendFlag) return;
      const raw = xhrRun(this, bytes);
      if (s.token !== token || !s.sendFlag) return;
      xhrComplete(this, raw, false);
    }, 0, false, []);
  },
  abort() {
    const s = xhrSlot(this);
    s.token++;
    if (s.sendFlag || s.state === 2 || s.state === 3) {
      s.sendFlag = false; s.errorFlag = true;
      xhrReadyState(this, 4);
      xhrFire(this, this, 'abort', 0, 0); xhrFire(this, this, 'loadend', 0, 0);
    }
    s.state = 0; s.status = 0; s.statusText = ''; s.responseBytes = ''; s.responseHeaders = [];
  },
  getResponseHeader(name) {
    const s = xhrSlot(this);
    required(arguments, 1, 'getResponseHeader');
    if (s.state < 2 || s.errorFlag) return null;
    const l = asciiLowercase(toDOMString(name));
    const vals = s.responseHeaders.filter(e => e[0] === l && l !== 'set-cookie' && l !== 'set-cookie2').map(e => e[1]);
    return vals.length ? vals.join(', ') : null;
  },
  getAllResponseHeaders() {
    const s = xhrSlot(this);
    if (s.state < 2 || s.errorFlag) return '';
    return s.responseHeaders.filter(e => e[0] !== 'set-cookie' && e[0] !== 'set-cookie2').sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0).map(e => e[0] + ': ' + e[1] + '\r\n').join('');
  },
  overrideMimeType(mime) { const s = xhrSlot(this); required(arguments, 1, 'overrideMimeType'); if (s.state === 3 || s.state === 4) throw domError('InvalidStateError', 'The object is in an invalid state.'); s.mimeOverride = toDOMString(mime); }
});
attributes(XMLHttpRequest.prototype, {
  readyState: { get() { return xhrSlot(this).state; } },
  timeout: { get() { return xhrSlot(this).timeout; }, set(v) { const s = xhrSlot(this); if (!s.async && s.state !== 0) throw domError('InvalidAccessError', 'Synchronous requests must not set a timeout.'); s.timeout = toUnsignedLong(v); } },
  withCredentials: { get() { return xhrSlot(this).withCredentials; }, set(v) { const s = xhrSlot(this); if (s.state !== 0 && s.state !== 1) throw domError('InvalidStateError', 'The object is in an invalid state.'); s.withCredentials = !!v; } },
  upload: { get() { return xhrSlot(this).upload; } },
  responseType: {
    get() { return xhrSlot(this).responseType; },
    set(v) {
      const s = xhrSlot(this);
      const t = toDOMString(v);
      if (['', 'arraybuffer', 'blob', 'document', 'json', 'text'].indexOf(t) < 0) return;
      if (s.state === 3 || s.state === 4) throw domError('InvalidStateError', 'The object is in an invalid state.');
      if (!s.async && s.state !== 0) throw domError('InvalidAccessError', 'Synchronous requests from a document must not set a response type.');
      s.responseType = t;
    }
  },
  responseURL: { get() { const s = xhrSlot(this); return s.state === 4 && !s.errorFlag ? (s.responseUrl || s.url) : ''; } },
  status: { get() { return xhrSlot(this).status; } },
  statusText: { get() { return xhrSlot(this).statusText; } },
  responseText: {
    get() {
      const s = xhrSlot(this);
      if (s.responseType !== '' && s.responseType !== 'text') throw domError('InvalidStateError', "Failed to read the 'responseText' property from 'XMLHttpRequest': The value is only accessible if the object's 'responseType' is '' or 'text' (was '" + s.responseType + "').");
      if (s.state !== 3 && s.state !== 4) return '';
      return xhrResponseText(s);
    }
  },
  responseXML: {
    get() {
      const s = xhrSlot(this);
      if (s.responseType !== '' && s.responseType !== 'document') throw domError('InvalidStateError', "Failed to read the 'responseXML' property from 'XMLHttpRequest': The value is only accessible if the object's 'responseType' is '' or 'document' (was '" + s.responseType + "').");
      if (s.state !== 4) return null;
      const ct = xhrContentType(s);
      if (!/html|xml/i.test(ct)) return null;
      try { return new DOMParser().parseFromString(xhrResponseText(s), /html/i.test(ct) ? 'text/html' : 'application/xml'); } catch (e) { return null; }
    }
  },
  response: {
    get() {
      const s = xhrSlot(this);
      if (s.state !== 4 && !(s.responseType === '' || s.responseType === 'text') ) return null;
      switch (s.responseType) {
        case '': case 'text': return s.state === 3 || s.state === 4 ? xhrResponseText(s) : '';
        case 'arraybuffer': return s.errorFlag ? null : binaryToBytes(s.responseBytes).buffer;
        case 'blob': { if (s.errorFlag) return null; const b = new Blob([], { type: xhrContentType(s) }); slotOf(b).bytes = s.responseBytes; return b; }
        case 'json': { if (s.errorFlag || s.responseBytes === '') return null; try { return JSON.parse(xhrResponseText(s)); } catch (e) { return null; } }
        case 'document': return this.responseXML;
      }
      return null;
    }
  }
});
defineHandlerAttrs(XMLHttpRequest.prototype, ['readystatechange']);
