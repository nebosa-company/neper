// Script elements (HTML Standard 4.12.1): preparing and running classic scripts, `src` loading through the host's fetch,
// async / defer ordering, document.currentScript and the load / error events. Modules are not supported yet.

const MODULES_SUPPORTED = true;
const javascriptTypes = ['application/ecmascript', 'application/javascript', 'application/x-ecmascript', 'application/x-javascript',
  'text/ecmascript', 'text/javascript', 'text/javascript1.0', 'text/javascript1.1', 'text/javascript1.2', 'text/javascript1.3',
  'text/javascript1.4', 'text/javascript1.5', 'text/jscript', 'text/livescript', 'text/x-ecmascript', 'text/x-javascript'];
function scriptState(el) {
  const s = slotOf(el);
  if (!s.script) s.script = { alreadyStarted: false, parserInserted: false, forceAsync: true, executing: false };
  return s.script;
}
function isScriptElement(el) { const s = slotOf(el); return s.nodeType === ELEMENT_NODE && s.localName === 'script' && (s.namespaceURI === HTML_NS || s.namespaceURI === SVG_NS); }
function scriptKind(el) {
  const s = slotOf(el);
  if (s.namespaceURI === SVG_NS) return 'classic';
  const type = getAttributeValue(el, 'type');
  if (type === null || type === '') {
    const lang = getAttributeValue(el, 'language');
    if (lang === null || lang === '' || /^(javascript|ecmascript|jscript|livescript)/i.test(lang)) return 'classic';
    return 'none';
  }
  const t = asciiLowercase(stripAndCollapse(type));
  const semi = t.indexOf(';');
  const essence = (semi >= 0 ? t.slice(0, semi) : t).trim();
  if (javascriptTypes.indexOf(essence) >= 0) return 'classic';
  if (t === 'module') return 'module';
  if (t === 'importmap') return 'importmap';
  return 'none';
}
const deferredScripts = [];
const asyncPending = [];
let parsing = false;

function scriptSourceText(el) {
  let out = '';
  for (const c of childrenOf(el)) if (nodeType(c) === TEXT_NODE) out += N.value(idOf(c));
  return out;
}
function fireScriptEvent(el, type) {
  const ev = new Event(type, { bubbles: false, cancelable: false });
  slotOf(ev).isTrusted = true;
  dispatch(ev, el);
}
function executeScript(el, source, name) {
  const doc = slotOf(el).doc;
  const ds = slotOf(doc);
  const old = ds.currentScript;
  ds.currentScript = isShadowRoot(rootNode(el)) ? null : el;
  try { N.runScript(source, name); } finally { ds.currentScript = old; }
}

function prepareScript(el, parserInserted) {
  const st = scriptState(el);
  if (st.alreadyStarted) return;
  const hadParserInserted = st.parserInserted;
  st.parserInserted = parserInserted === true || st.parserInserted;
  const src = getAttributeValue(el, 'src');
  const text = scriptSourceText(el);
  if (src === null && text === '') return;
  if (!isConnected(el)) return;
  const kind = scriptKind(el);
  if (kind === 'none' || kind === 'importmap') return;
  if (st.parserInserted) st.forceAsync = false;
  st.alreadyStarted = true;
  if (kind === 'classic' && getAttributeValue(el, 'nomodule') !== null && MODULES_SUPPORTED) return;
  const doc = slotOf(el).doc;
  if (kind === 'module') {
    const baseUrl = documentBaseURL(doc);
    const isAsync = getAttributeValue(el, 'async') !== null;
    let run;
    if (src === null) run = () => { N.runModule(baseUrl, text); };
    else {
      if (src === '') { scheduleTimer(() => fireScriptEvent(el, 'error'), 0, false, []); return; }
      const parsed = N.urlParse(src, baseUrl);
      if (parsed === null) { scheduleTimer(() => fireScriptEvent(el, 'error'), 0, false, []); return; }
      run = () => { if (N.runModule(parsed[0])) fireScriptEvent(el, 'load'); else fireScriptEvent(el, 'error'); };
    }
    if (isAsync || !st.parserInserted) scheduleTimer(run, 0, false, []);
    else apply(arrayPush, deferredScripts, [run]);
    return;
  }
  if (src !== null) {
    if (src === '') { scheduleTimer(() => fireScriptEvent(el, 'error'), 0, false, []); return; }
    const parsed = N.urlParse(src, documentBaseURL(doc));
    if (parsed === null) { scheduleTimer(() => fireScriptEvent(el, 'error'), 0, false, []); return; }
    const url = parsed[0];
    const isAsync = getAttributeValue(el, 'async') !== null || st.forceAsync;
    const isDefer = getAttributeValue(el, 'defer') !== null;
    const run = () => {
      const r = N.fetchText(url);
      if (r === null || r[0] < 200 || r[0] >= 300) { fireScriptEvent(el, 'error'); return; }
      executeScript(el, r[1], url);
      fireScriptEvent(el, 'load');
    };
    if (st.parserInserted && !isAsync && isDefer) { apply(arrayPush, deferredScripts, [run]); return; }
    if (isAsync) { scheduleTimer(run, 0, false, []); return; }
    run();
    return;
  }
  executeScript(el, text, documentBaseURL(doc));
}
elementInserted = function (el) { if (isScriptElement(el)) prepareScript(el, false); };

// Scripts the markup parser created: run in tree order. Called once by the lifecycle.
function runParsedScripts() {
  const scripts = [];
  for (const d of descendantsOf(mainDocument)) if (nodeType(d) === ELEMENT_NODE && isScriptElement(d)) apply(arrayPush, scripts, [d]);
  for (const el of scripts) {
    const st = scriptState(el);
    if (st.alreadyStarted) continue;
    parsing = true;
    try { prepareScript(el, true); } catch (e) { reportException(e); }
  }
  parsing = false;
}

// parseFragment marks the scripts of parsed markup as already started (innerHTML does not run them).
function markScriptsStarted(rootId) {
  let id = nFirst(rootId);
  while (id >= 0) {
    if (N.kind(id) === 2 && N.name(id) === 'script') scriptState(wrap(id)).alreadyStarted = true;
    const f = nFirst(id);
    if (f >= 0) { id = f; continue; }
    while (id >= 0 && id !== rootId) {
      const n = nNext(id);
      if (n >= 0) { id = n; break; }
      id = nParent(id);
      if (id === rootId) { id = -1; }
    }
    if (id === rootId) break;
  }
}

defineProperty(global, '__lifecycle', {
  value: {
    run() {
      const s = slotOf(mainDocument);
      runParsedScripts();
      this.interactive();
      for (const run of deferredScripts.splice(0, deferredScripts.length)) { try { run(); } catch (e) { reportException(e); } N.runJobs(); }
      this.domContentLoaded();
      flushFrameLoads();
      this.complete();
      this.load();
      this.pageshow();
    },
    interactive() { slotOf(mainDocument).readyState = 'interactive'; fireSimple(mainDocument, 'readystatechange', false); },
    domContentLoaded() { fireSimple(mainDocument, 'DOMContentLoaded', true); },
    complete() { slotOf(mainDocument).readyState = 'complete'; fireSimple(mainDocument, 'readystatechange', false); },
    load() { fireSimple(global, 'load', false, mainDocument); },
    mouse(nodeId, type, x, y) {
      const target = wrap(nodeId);
      if (target === null) return true;
      const ev = new MouseEvent(type, { bubbles: true, cancelable: true, composed: true, clientX: Math.round(x), clientY: Math.round(y), view: global, button: 0, buttons: 0, detail: 1 });
      const s = slotOf(ev);
      s.isTrusted = true;
      s.isMouseClick = type === 'click';
      return dispatch(ev, target);
    },
    pageshow() { const ev = new PageTransitionEvent('pageshow', { persisted: false }); slotOf(ev).isTrusted = true; dispatch(ev, global, mainDocument); }
  },
  writable: true, configurable: true
});
