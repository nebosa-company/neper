// Document lifecycle: readyState changes and the DOMContentLoaded / load events, driven by the page that owns the context.

function fireSimple(target, type, bubbles, legacyTarget) {
  const ev = new Event(type, { bubbles, cancelable: false });
  slotOf(ev).isTrusted = true;
  if (legacyTarget) dispatch(ev, target, legacyTarget);
  else dispatch(ev, target);
}
defineProperty(global, '__lifecycle', {
  value: {
    interactive() {
      const s = slotOf(mainDocument);
      s.readyState = 'interactive';
      fireSimple(mainDocument, 'readystatechange', false);
    },
    domContentLoaded() { fireSimple(mainDocument, 'DOMContentLoaded', true); },
    complete() {
      const s = slotOf(mainDocument);
      s.readyState = 'complete';
      fireSimple(mainDocument, 'readystatechange', false);
    },
    load() { fireSimple(global, 'load', false, mainDocument); },
    pageshow() {
      const ev = new PageTransitionEvent('pageshow', { persisted: false });
      slotOf(ev).isTrusted = true;
      dispatch(ev, global, mainDocument);
    }
  },
  writable: true, configurable: true
});
