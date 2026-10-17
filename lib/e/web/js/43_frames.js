// Nested browsing contexts: an <iframe> owns a context of its own (a document and a realm); this window reaches it through
// contentWindow, and the child reaches its embedder through parent, top and frameElement.

const BLANK_DOCUMENT = '<!DOCTYPE html><html><head></head><body></body></html>';
function isIFrame(el) { const s = slotOf(el); return !!s && s.nodeType === ELEMENT_NODE && s.namespaceURI === HTML_NS && s.localName === 'iframe'; }
function frameStateOf(el) {
  const s = slotOf(el);
  if (!s.frame) s.frame = { win: null, token: 0 };
  return s.frame;
}
function frameWindowOf(el) { return isIFrame(el) && slotOf(el).frame ? slotOf(el).frame.win : null; }

function attachFrameWindow(el, st, win) {
  if (st.win !== null) N.frameDrop(st.win);
  st.win = win;
  defineProperty(win, '__frameElement', { value: el, writable: true, enumerable: false, configurable: true });
  refreshFrameIndexes();
  refreshNamedFor(el);
}
function frameInserted(el) {
  const st = frameStateOf(el);
  if (st.win !== null) return;
  attachFrameWindow(el, st, N.frameCreate(BLANK_DOCUMENT, 'about:blank'));
  processFrameAttributes(el, st, true);
}
function frameRemoved(el) {
  const st = frameStateOf(el);
  st.token++;
  if (st.win !== null) { N.frameDrop(st.win); st.win = null; }
  refreshFrameIndexes();
  refreshNamedFor(el);
}
function mimeOfAddress(address) {
  const path = address.replace(/[?#].*$/, '');
  if (/\.xhtml?$/i.test(path)) return 'application/xhtml+xml';
  if (/\.xml$/i.test(path)) return 'application/xml';
  if (/\.svg$/i.test(path)) return 'image/svg+xml';
  return 'text/html';
}
function fireFrameLoad(el) { fireSimple(el, 'load', false); }
const pendingFrameLoads = [];
function frameTask(fn) {
  const entry = { fn, done: false };
  const run = () => { if (entry.done) return; entry.done = true; fn(); };
  apply(arrayPush, pendingFrameLoads, [run]);
  scheduleTimer(run, 0, false, []);
}
function flushFrameLoads() {
  while (pendingFrameLoads.length) { const run = pendingFrameLoads.shift(); try { run(); } catch (e) { reportException(e); } }
}
function processFrameAttributes(el, st, initial) {
  const token = ++st.token;
  const srcdoc = getAttributeValue(el, 'srcdoc');
  const src = getAttributeValue(el, 'src');
  let address = 'about:blank', markup = null;
  if (srcdoc !== null) { address = 'about:srcdoc'; markup = srcdoc; }
  else if (src !== null && src.trim() !== '') {
    const parsed = N.urlParse(src.trim(), documentBaseURL(mainDocument));
    if (parsed !== null) address = parsed[0];
    else {
      // An invalid URL navigates to about:blank and still fires load.
      frameTask(() => { if (st.token === token && isConnected(el)) fireFrameLoad(el); });
      return;
    }
  }
  if (address === 'about:blank' && markup === null) {
    if (initial) frameTask(() => { if (st.token === token && isConnected(el)) fireFrameLoad(el); });
    else frameTask(() => { if (st.token !== token || !isConnected(el)) return; attachFrameWindow(el, st, N.frameCreate(BLANK_DOCUMENT, 'about:blank')); N.frameStart(st.win); fireFrameLoad(el); });
    return;
  }
  frameTask(() => {
    if (st.token !== token || !isConnected(el)) return;
    let text = markup;
    if (text === null) {
      const r = N.fetchText(address);
      text = r === null ? '' : r[1];
    }
    const mime = markup === null ? mimeOfAddress(address) : 'text/html';
    const win = N.frameCreate(mime === 'text/html' ? text : BLANK_DOCUMENT, address);
    if (mime !== 'text/html') win.__loadXML(text, mime);
    attachFrameWindow(el, st, win);
    N.frameStart(win);
    fireFrameLoad(el);
  });
}

const prevInsertedFrames = elementInserted;
elementInserted = function (el) {
  prevInsertedFrames(el);
  if (isIFrame(el) && shadowIncludingRoot(el) === mainDocument) frameInserted(el);
};
const prevRemovedFrames = elementRemoved;
elementRemoved = function (el, parent) {
  prevRemovedFrames(el, parent);
  if (isIFrame(el)) frameRemoved(el);
};
const prevAttrFrames = elementAttributeChanged;
elementAttributeChanged = function (el, name, oldValue, value) {
  prevAttrFrames(el, name, oldValue, value);
  if ((name === 'src' || name === 'srcdoc') && isIFrame(el) && frameStateOf(el).win !== null && isConnected(el)) processFrameAttributes(el, frameStateOf(el), false);
  else if (name === 'name' && isIFrame(el)) refreshFrameIndexes();
};

function iframeSlot(o) { const s = slotOf(o); if (!s || s.localName !== 'iframe' || s.nodeType !== ELEMENT_NODE) illegal(); return s; }
attributes(P('HTMLIFrameElement'), {
  contentWindow: { get() { iframeSlot(this); return frameWindowOf(this); } },
  contentDocument: { get() { iframeSlot(this); const w = frameWindowOf(this); return w === null ? null : w.document; } }
});
operations(P('HTMLIFrameElement'), {
  getSVGDocument() { iframeSlot(this); return null; }
});

// --- window.frames, indexed and named access

const frameIndexed = [];
function framesInOrder() {
  const out = [];
  for (const d of descendantsOf(mainDocument)) if (isIFrame(d)) { const w = frameWindowOf(d); if (w !== null) apply(arrayPush, out, [w]); }
  return out;
}
function refreshFrameIndexes() {
  const list = framesInOrder();
  for (let i = 0; i < Math.max(list.length, frameIndexed.length); i++) {
    const key = String(i);
    if (i < list.length) {
      if (frameIndexed.length <= i) {
        defineProperty(global, key, { get() { return framesInOrder()[i]; }, enumerable: true, configurable: true });
        apply(arrayPush, frameIndexed, [key]);
      }
    } else if (i < frameIndexed.length) {
      delete global[key];
    }
  }
  frameIndexed.length = list.length;
}
