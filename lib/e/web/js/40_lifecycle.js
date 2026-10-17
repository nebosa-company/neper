// Document lifecycle: readyState changes and the DOMContentLoaded / load events, driven by the page that owns the context.

function fireSimple(target, type, bubbles, legacyTarget) {
  const ev = new Event(type, { bubbles, cancelable: false });
  slotOf(ev).isTrusted = true;
  if (legacyTarget) dispatch(ev, target, legacyTarget);
  else dispatch(ev, target);
}
