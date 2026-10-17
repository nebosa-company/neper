// DataTransfer: an item list with a files view (the usual way scripts build a FileList).

function DataTransfer() {
  if (new.target === undefined) throw new TypeError("Failed to construct 'DataTransfer': Please use the 'new' operator");
  const s = setSlot(this, { isDataTransfer: true, items: [], dropEffect: 'none', effectAllowed: 'none' });
  s.itemList = makeDataTransferItemList(s);
}
iface('DataTransfer', DataTransfer, null);
function DataTransferItem() { throw new TypeError('Illegal constructor'); }
iface('DataTransferItem', DataTransferItem, null);
function DataTransferItemList() { throw new TypeError('Illegal constructor'); }
iface('DataTransferItemList', DataTransferItemList, null);
function dataTransferSlot(o) { const s = slotOf(o); if (!s || !s.isDataTransfer) illegal(); return s; }
function makeDataTransferItem(entry) {
  const o = create(DataTransferItem.prototype);
  setSlot(o, { isDTItem: true, entry });
  return o;
}
function makeDataTransferItemList(dt) {
  const state = { isDTList: true, dt };
  return legacyObject(DataTransferItemList.prototype, { length: () => dt.items.length, item: i => (i < dt.items.length ? dt.items[i].item : null) }, state);
}
attributes(DataTransfer.prototype, {
  dropEffect: { get() { return dataTransferSlot(this).dropEffect; }, set(v) { const s = dataTransferSlot(this); const str = String(v); if (['none', 'copy', 'link', 'move'].indexOf(str) >= 0) s.dropEffect = str; } },
  effectAllowed: { get() { return dataTransferSlot(this).effectAllowed; }, set(v) { const s = dataTransferSlot(this); const str = String(v); if (['none', 'copy', 'copyLink', 'copyMove', 'link', 'linkMove', 'move', 'all', 'uninitialized'].indexOf(str) >= 0) s.effectAllowed = str; } },
  items: { get() { return dataTransferSlot(this).itemList; } },
  types: { get() { const s = dataTransferSlot(this); const out = []; for (const e of s.items) out.push(e.kind === 'file' ? 'Files' : e.type); return out; } },
  files: { get() { const s = dataTransferSlot(this); const files = s.items.filter(e => e.kind === 'file').map(e => e.file); return makeFileListFrom(() => files); } }
});
operations(DataTransfer.prototype, {
  getData(format) { const s = dataTransferSlot(this); const f = asciiLowercase(toDOMString(format)); for (const e of s.items) if (e.kind === 'string' && e.type === f) return e.data; return ''; },
  setData(format, data) { const s = dataTransferSlot(this); const f = asciiLowercase(toDOMString(format)); s.items = s.items.filter(e => !(e.kind === 'string' && e.type === f)); addStringItem(s, toDOMString(data), f); },
  clearData(format = undefined) { const s = dataTransferSlot(this); if (format === undefined) s.items = s.items.filter(e => e.kind === 'file'); else { const f = asciiLowercase(toDOMString(format)); s.items = s.items.filter(e => !(e.kind === 'string' && e.type === f)); } },
  setDragImage() {}
});
function addStringItem(s, data, type) {
  const entry = { kind: 'string', type, data };
  entry.item = makeDataTransferItem(entry);
  apply(arrayPush, s.items, [entry]);
  return entry.item;
}
attributes(DataTransferItemList.prototype, { length: { get() { const st = slotOf(this); if (!st || !st.isDTList) illegal(); return st.dt.items.length; } } });
operations(DataTransferItemList.prototype, {
  add(data, type = undefined) {
    const st = slotOf(this);
    if (!st || !st.isDTList) illegal();
    required(arguments, 1, 'add');
    const dt = st.dt;
    if (isObject(data) && slotOf(data) && slotOf(data).isFile) {
      const entry = { kind: 'file', type: slotOf(data).type, file: data };
      entry.item = makeDataTransferItem(entry);
      apply(arrayPush, dt.items, [entry]);
      return entry.item;
    }
    if (type === undefined) throw new TypeError("Failed to execute 'add' on 'DataTransferItemList': parameter 2 is required for strings.");
    const t = asciiLowercase(toDOMString(type));
    for (const e of dt.items) if (e.kind === 'string' && e.type === t) throw domError('NotSupportedError', 'An item already exists for this type');
    return addStringItem(dt, toDOMString(data), t);
  },
  remove(index) { const st = slotOf(this); if (!st || !st.isDTList) illegal(); required(arguments, 1, 'remove'); const i = toUnsignedLong(index); if (i < st.dt.items.length) st.dt.items.splice(i, 1); },
  clear() { const st = slotOf(this); if (!st || !st.isDTList) illegal(); st.dt.items = []; }
});
attributes(DataTransferItem.prototype, {
  kind: { get() { const s = slotOf(this); if (!s || !s.isDTItem) illegal(); return s.entry.kind; } },
  type: { get() { const s = slotOf(this); if (!s || !s.isDTItem) illegal(); return s.entry.type; } }
});
operations(DataTransferItem.prototype, {
  getAsFile() { const s = slotOf(this); if (!s || !s.isDTItem) illegal(); return s.entry.kind === 'file' ? s.entry.file : null; },
  getAsString(callback) { const s = slotOf(this); if (!s || !s.isDTItem) illegal(); if (callback === null || callback === undefined) return; if (typeof callback !== 'function') throw new TypeError('callback is not a function'); if (s.entry.kind === 'string') scheduleTimer(() => callback(s.entry.data), 0, false, []); }
});
