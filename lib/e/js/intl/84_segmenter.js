
  // ---------------------------------------------------------------- Intl.Segmenter (UAX #29, simplified)
  var SegmenterSlots = slotted('Segmenter'), SegmentsSlots = slotted('Segments'), SegmentIterSlots = slotted('Segment Iterator');
  var RE_EXTEND = /^[\p{Grapheme_Extend}\p{Emoji_Modifier}‌]$/u, RE_SPACING = /^\p{Mc}$/u, RE_CONTROL = /^[\p{Cc}\p{Zl}\p{Zp}­؜᠎​‎‏‪-‮⁠-⁯﻿]$/u;
  var RE_EXTPICT = /^\p{Extended_Pictographic}$/u, RE_RI = /^[\u{1F1E6}-\u{1F1FF}]$/u;
  var RE_LETTER = /^[\p{L}\p{Nl}]$/u, RE_DIGIT = /^\p{Nd}$/u, RE_NUMBER = /^[\p{N}]$/u, RE_HAN = /^[\p{Script=Han}\p{Script=Hiragana}]$/u, RE_KATAKANA = /^\p{Script=Katakana}$/u;
  var RE_HSPACE = /^[\p{Zs}\t]$/u, RE_MARK = /^\p{M}$/u;
  function cpAt(s, i) {
    var c = apply(strCharCodeAt, s, [i]);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      var d = apply(strCharCodeAt, s, [i + 1]);
      if (d >= 0xdc00 && d <= 0xdfff) return { cp: (c - 0xd800) * 0x400 + (d - 0xdc00) + 0x10000, len: 2 };
    }
    return { cp: c, len: 1 };
  }
  function cpStr(cp) { return String.fromCodePoint(cp); }
  function isMatch(re, cp) { return cp < 0xd800 || cp > 0xdfff ? re.test(cpStr(cp)) : false; }
  function hangulType(cp) {
    if ((cp >= 0x1100 && cp <= 0x115f) || (cp >= 0xa960 && cp <= 0xa97c)) return 'L';
    if ((cp >= 0x1160 && cp <= 0x11a7) || (cp >= 0xd7b0 && cp <= 0xd7c6)) return 'V';
    if ((cp >= 0x11a8 && cp <= 0x11ff) || (cp >= 0xd7cb && cp <= 0xd7fb)) return 'T';
    if (cp >= 0xac00 && cp <= 0xd7a3) return (cp - 0xac00) % 28 === 0 ? 'LV' : 'LVT';
    return '';
  }
  // Offsets of the grapheme cluster boundaries of s (0 and s.length included).
  function graphemeBreaks(s) {
    var breaks = [0], i = 0, n = s.length;
    if (n === 0) return breaks;
    var cur = cpAt(s, 0), prev, riRun = 0, pictRun = false, afterZwj = false;
    var prevCp = cur.cp, prevHangul = hangulType(cur.cp);
    riRun = isMatch(RE_RI, cur.cp) ? 1 : 0;
    pictRun = isMatch(RE_EXTPICT, cur.cp);
    i = cur.len;
    while (i < n) {
      cur = cpAt(s, i);
      var c = cur.cp, brk = true;
      var curHangul = hangulType(c);
      if (prevCp === 13 && c === 10) brk = false;
      else if (prevCp === 13 || prevCp === 10 || isMatch(RE_CONTROL, prevCp) && prevCp !== 0x200c) brk = true;
      else if (c === 13 || c === 10 || (isMatch(RE_CONTROL, c) && c !== 0x200d && c !== 0x200c)) brk = true;
      else if (c === 0x200d || isMatch(RE_EXTEND, c) || isMatch(RE_SPACING, c)) brk = false;
      else if (prevHangul && curHangul && ((prevHangul === 'L' && (curHangul === 'L' || curHangul === 'V' || curHangul === 'LV' || curHangul === 'LVT')) ||
        ((prevHangul === 'LV' || prevHangul === 'V') && (curHangul === 'V' || curHangul === 'T')) || ((prevHangul === 'LVT' || prevHangul === 'T') && curHangul === 'T'))) brk = false;
      else if (isMatch(RE_RI, c) && riRun % 2 === 1) brk = false;
      else if (afterZwj && pictRun && isMatch(RE_EXTPICT, c)) brk = false;
      if (brk) push(breaks, i);
      // update the state for the next code point
      if (isMatch(RE_RI, c)) riRun = brk ? 1 : riRun + 1; else riRun = 0;
      if (isMatch(RE_EXTPICT, c)) { if (brk || !afterZwj) pictRun = true; afterZwj = false; }
      else if (c === 0x200d) afterZwj = pictRun;
      else if (isMatch(RE_EXTEND, c)) { /* extends keep the picture run */ }
      else { pictRun = false; afterZwj = false; }
      if (brk && !isMatch(RE_EXTPICT, c)) pictRun = false;
      prevCp = c; prevHangul = curHangul;
      i += cur.len;
    }
    push(breaks, n);
    return breaks;
  }
  function graphemeEndAt(s, i, gb) {
    for (var k = 0; k < gb.length; k++) if (gb[k] > i) return gb[k];
    return s.length;
  }
  var MID_LETTER = ":··՟״‧︓﹕：", MID_NUM_LET = ".‘’․﹒＇．'", MID_NUM = ",;;։،؍٬߸⁄︐︔﹐﹔，；";
  function wordBreaks(s) {
    var gb = graphemeBreaks(s), breaks = [0], n = s.length, i = 0;
    function isAlnumAt(pos) { if (pos >= n) return false; var c = cpAt(s, pos).cp; return isMatch(RE_LETTER, c) || isMatch(RE_NUMBER, c) || c === 95; }
    function isLetterAt(pos) { if (pos >= n) return false; var c = cpAt(s, pos).cp; return isMatch(RE_LETTER, c); }
    function isDigitAt(pos) { if (pos >= n) return false; return isMatch(RE_DIGIT, cpAt(s, pos).cp); }
    while (i < n) {
      var c = cpAt(s, i).cp, end;
      if (c === 13 && i + 1 < n && s.charCodeAt(i + 1) === 10) end = i + 2;
      else if (c === 10 || c === 13 || c === 0x0b || c === 0x0c || c === 0x85 || c === 0x2028 || c === 0x2029) end = i + 1;
      else if (isMatch(RE_HSPACE, c)) {
        end = i + 1;
        while (end < n && isMatch(RE_HSPACE, cpAt(s, end).cp)) end++;
      } else if (isMatch(RE_HAN, c)) end = graphemeEndAt(s, i, gb);
      else if (isMatch(RE_KATAKANA, c)) {
        end = graphemeEndAt(s, i, gb);
        while (end < n && isMatch(RE_KATAKANA, cpAt(s, end).cp)) end = graphemeEndAt(s, end, gb);
      } else if (isLetterAt(i) || isDigitAt(i) || c === 95 || isMatch(RE_NUMBER, c)) {
        end = graphemeEndAt(s, i, gb);
        while (end < n) {
          var d = cpAt(s, end).cp;
          if (isMatch(RE_HAN, d) || isMatch(RE_KATAKANA, d) && !isMatch(RE_KATAKANA, c)) break;
          if (isAlnumAt(end)) { end = graphemeEndAt(s, end, gb); continue; }
          var ch = s.charAt(end);
          var midLetter = MID_LETTER.indexOf(ch) >= 0 || MID_NUM_LET.indexOf(ch) >= 0, midNum = MID_NUM.indexOf(ch) >= 0 || MID_NUM_LET.indexOf(ch) >= 0;
          var before = end - 1, after = end + 1;
          if (midLetter && isLetterAt(before) && isLetterAt(after)) { end = after; continue; }
          if (midNum && isDigitAt(before) && isDigitAt(after)) { end = after; continue; }
          break;
        }
      } else end = graphemeEndAt(s, i, gb);
      push(breaks, end);
      i = end;
    }
    return breaks;
  }
  var RE_SENT_TERM = /^[.?!․‼‽⁇⁈⁉。！．？｡]$/u, RE_CLOSE = /^[\p{Pe}\p{Pf}\p{Pi}"'»”’]$/u, RE_LOWER = /^\p{Ll}$/u;
  function sentenceBreaks(s) {
    var breaks = [0], n = s.length, i = 0;
    while (i < n) {
      var c = cpAt(s, i), cp = c.cp;
      var next = i + c.len;
      if (cp === 13 && next < n && s.charCodeAt(next) === 10) { push(breaks, next + 1); i = next + 1; continue; }
      if (cp === 10 || cp === 13 || cp === 0x85 || cp === 0x2028 || cp === 0x2029) { push(breaks, next); i = next; continue; }
      if (isMatch(RE_SENT_TERM, cp)) {
        var j = next;
        while (j < n && isMatch(RE_SENT_TERM, cpAt(s, j).cp)) j += cpAt(s, j).len;
        while (j < n && isMatch(RE_CLOSE, cpAt(s, j).cp)) j += cpAt(s, j).len;
        var k = j;
        while (k < n && isMatch(RE_HSPACE, cpAt(s, k).cp)) k += cpAt(s, k).len;
        var aterm = cp === 0x2e || cp === 0x2024 || cp === 0xff0e;
        var nextCp = k < n ? cpAt(s, k).cp : -1;
        var prevCp = i > 0 ? cpAt(s, i - 1).cp : -1;
        if (k === j && k < n && nextCp !== 10 && nextCp !== 13 && nextCp !== 0x2029 && nextCp !== 0x2028 && nextCp !== 0x85) {
          // no space after the terminator: "3.14", "a.b"
          if (!(isMatch(RE_SENT_TERM, cp) && !aterm)) { i = j; continue; }
        }
        if (aterm && nextCp !== -1 && isMatch(RE_LOWER, nextCp)) { i = k; continue; }
        // trailing separators belong to this sentence
        if (k < n && (nextCp === 10 || nextCp === 13 || nextCp === 0x2029 || nextCp === 0x2028 || nextCp === 0x85)) {
          var m = k + cpAt(s, k).len;
          if (nextCp === 13 && m < n && s.charCodeAt(m) === 10) m++;
          push(breaks, m); i = m; continue;
        }
        if (k < n) push(breaks, k);
        i = k;
        continue;
      }
      i = next;
    }
    if (breaks[breaks.length - 1] !== n) push(breaks, n);
    return breaks;
  }
  function segmentBreaks(granularity, s) {
    if (s.length === 0) return [0];
    var b = granularity === 'word' ? wordBreaks(s) : granularity === 'sentence' ? sentenceBreaks(s) : graphemeBreaks(s);
    // remove duplicates and non-increasing entries
    var out = [0];
    for (var i = 1; i < b.length; i++) if (b[i] > out[out.length - 1]) push(out, b[i]);
    return out;
  }
  function Segmenter() {
    if (new.target === undefined) throw new TypeErr("Constructor Intl.Segmenter requires 'new'");
    var locales = arguments.length > 0 ? arguments[0] : undefined, options = arguments.length > 1 ? arguments[1] : undefined;
    var o = create(getPrototypeFromNewTarget(new.target, Segmenter.prototype, 'Segmenter'));
    var requested = canonicalizeLocaleList(locales);
    options = getOptionsObject(options);
    var matcher = getOption(options, 'localeMatcher', 'string', ['lookup', 'best fit'], 'best fit');
    var r = resolveLocale(AVAILABLE, requested, create(null), [], create(null));
    var granularity = getOption(options, 'granularity', 'string', ['grapheme', 'word', 'sentence'], 'grapheme');
    SegmenterSlots.set(o, nullObject({ locale: r.locale, granularity: granularity }));
    return o;
  }
  var SegmentsProto = create(Obj.prototype), SegmentIteratorProto = create(getProto(getProto([][symIterator]())));
  function segmentData(st, breaks, k) {
    var s = st.string, start = breaks[k], end = breaks[k + 1], seg = apply(strSlice, s, [start, end]);
    var d = { segment: seg, index: start, input: s };
    if (st.granularity === 'word') {
      var wordLike = false;
      for (var i = 0; i < seg.length; ) { var c = cpAt(seg, i); if (isMatch(RE_LETTER, c.cp) || isMatch(RE_NUMBER, c.cp) || isMatch(RE_HAN, c.cp)) { wordLike = true; break; } i += c.len; }
      d.isWordLike = wordLike;
    }
    return d;
  }
  var segmentsMethods = {
    containing(index) {
      var st = SegmentsSlots.get(this), n = +index;
      n = n !== n ? 0 : (n === Infinity || n === -Infinity ? n : (n < 0 ? -mathFloor(-n) : mathFloor(n)));
      if (n === 0) n = 0;
      var s = st.string;
      if (n < 0 || n >= s.length) return undefined;
      var b = st.breaks, k = 0;
      while (k + 1 < b.length - 1 && b[k + 1] <= n) k++;
      return segmentData(st, b, k);
    }
  };
  defineProperty(SegmentsProto, 'containing', { value: defineLen(segmentsMethods.containing, 1), writable: true, enumerable: false, configurable: true });
  define(SegmentsProto, symIterator, defineLen({
    [symIterator]() {
      var st = SegmentsSlots.get(this), it = create(SegmentIteratorProto);
      SegmentIterSlots.set(it, nullObject({ string: st.string, granularity: st.granularity, breaks: st.breaks, pos: 0 }));
      return it;
    }
  }[symIterator], 0));
  defineProperty(SegmentsProto[symIterator], 'name', { value: '[Symbol.iterator]', writable: false, enumerable: false, configurable: true });
  var iterMethods = {
    next() {
      var st = SegmentIterSlots.get(this), b = st.breaks;
      if (b.length < 2 || st.pos >= b.length - 1) return { value: undefined, done: true };
      var d = segmentData(st, b, st.pos);
      st.pos++;
      return { value: d, done: false };
    }
  };
  defineProperty(SegmentIteratorProto, 'next', { value: defineLen(iterMethods.next, 0), writable: true, enumerable: false, configurable: true });
  tag(SegmentIteratorProto, 'Segmenter String Iterator');
  var segmenterMethods = {
    segment(string) {
      var st = SegmenterSlots.get(this), s = toStr(string), seg = create(SegmentsProto);
      SegmentsSlots.set(seg, nullObject({ string: s, granularity: st.granularity, breaks: segmentBreaks(st.granularity, s) }));
      return seg;
    },
    resolvedOptions() {
      var st = SegmenterSlots.get(this);
      return { locale: st.locale, granularity: st.granularity };
    }
  };
  installProto(Segmenter, segmenterMethods, 'Intl.Segmenter');
  makeSupportedLocalesOf(Segmenter, function () { return AVAILABLE; });
  define(Intl, 'Segmenter', Segmenter);
