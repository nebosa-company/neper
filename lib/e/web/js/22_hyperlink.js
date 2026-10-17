// HTMLHyperlinkElementUtils for <a> and <area>, and the document base URL (<base href>).

documentBaseURL = function (doc) {
  const s = slotOf(doc);
  const id = N.qs(idOf(doc), 'base[href]');
  if (id >= 0) {
    const base = wrap(id);
    const parsed = N.urlParse(getAttributeValue(base, 'href'), s.url);
    if (parsed !== null) return parsed[0];
  }
  return s.url;
};
function hyperlinkURL(el) {
  const href = getAttributeValue(el, 'href');
  if (href === null) return null;
  return N.urlParse(href, documentBaseURL(slotOf(el).doc));
}
function setHyperlinkComponent(el, component, value) {
  const c = hyperlinkURL(el);
  if (c === null) return;
  const out = N.urlSet(c[0], component, toUSVString(value));
  if (out !== null) setAttributeValue(el, 'href', out[0]);
}
function installHyperlinkUtils(proto) {
  attributes(proto, {
    origin: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[10]; } },
    protocol: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? ':' : c[1]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'protocol', v); } },
    username: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[2]; }, set(v) { elSlot(this); const c = hyperlinkURL(this); if (c === null || c[5] === '' || c[1] === 'file:') return; setHyperlinkComponent(this, 'username', v); } },
    password: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[3]; }, set(v) { elSlot(this); const c = hyperlinkURL(this); if (c === null || c[5] === '' || c[1] === 'file:') return; setHyperlinkComponent(this, 'password', v); } },
    host: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[4]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'host', v); } },
    hostname: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[5]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'hostname', v); } },
    port: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[6]; }, set(v) { elSlot(this); const c = hyperlinkURL(this); if (c === null || c[5] === '' || c[1] === 'file:') return; setHyperlinkComponent(this, 'port', v); } },
    pathname: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[7]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'pathname', v); } },
    search: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[8]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'search', v); } },
    hash: { get() { elSlot(this); const c = hyperlinkURL(this); return c === null ? '' : c[9]; }, set(v) { elSlot(this); setHyperlinkComponent(this, 'hash', v); } }
  });
}
installHyperlinkUtils(HTMLAnchorElement.prototype);
installHyperlinkUtils(htmlInterfaces.HTMLAreaElement.prototype);
operations(HTMLAnchorElement.prototype, { toString() { elSlot(this); const c = hyperlinkURL(this); const v = getAttributeValue(this, 'href'); return c === null ? (v === null ? '' : v) : c[0]; } });
operations(htmlInterfaces.HTMLAreaElement.prototype, { toString() { elSlot(this); const c = hyperlinkURL(this); const v = getAttributeValue(this, 'href'); return c === null ? (v === null ? '' : v) : c[0]; } });
