/**
 * The spreadsheet number/date format subset TEXT(value, format) accepts.
 *
 * Pure and dependency-free. Both functions answer `null` for a format they do
 * not support, and the caller turns that into #VALUE! -- the previous behaviour
 * (echoing tokens such as "yyyy-00-Th") produced plausible-looking garbage.
 *
 * Numbers: digit placeholders `0 # ?`, a decimal point, `,` thousands grouping,
 * `%` (x100), quoted "literals", `\x` escapes, optional `pos;neg;zero` sections.
 * Separators are `,` and `.`: the formula engine has no locale of its own, and
 * a formula that renders differently per viewer is worse than a fixed one.
 *
 * Dates: Excel's case-insensitive tokens (yyyy yy mmmm mmm mm m dddd ddd dd d
 * hh h ss AM/PM), where `m`/`mm` is MINUTES right after an hour or right before
 * seconds and MONTH otherwise, translated to the Moment-style vocabulary that
 * `formatDate` speaks.
 */

/** Round half away from zero at `d` decimals, ignoring binary noise. */
function roundAway(abs, d) {
  const f = 10 ** d;
  return Math.round(Number((abs * f).toPrecision(15))) / f;
}

/** Split a format on unquoted ';'. */
function sections(fmt) {
  const out = [''];
  let quoted = false;
  for (let i = 0; i < fmt.length; i += 1) {
    const c = fmt[i];
    if (c === '"') quoted = !quoted;
    if (c === '\\' && !quoted) { out[out.length - 1] += c + (fmt[i + 1] ?? ''); i += 1; continue; }
    if (c === ';' && !quoted) out.push(''); else out[out.length - 1] += c;
  }
  return out;
}

/** Does the format carry a digit placeholder outside quotes? */
export function hasDigitPlaceholder(fmt) {
  return /^(?:[^"\\0#?]|"[^"]*"|\\.)*[0#?]/.test(fmt);
}

/**
 * @param {number} n
 * @param {string} fmt
 * @returns {string|null} null when the format is not in the supported subset
 */
export function formatExcelNumber(n, fmt) {
  const secs = sections(fmt);
  let sec = secs[0];
  let value = n;
  let sign = '';
  if (n < 0) {
    if (secs.length > 1) { sec = secs[1]; value = -n; } else { sign = '-'; value = -n; }
  } else if (n === 0 && secs.length > 2) sec = secs[2];

  let pre = '';
  let post = '';
  let mask = '';
  let percents = 0;
  for (let i = 0; i < sec.length; i += 1) {
    const c = sec[i];
    let lit = null;
    if (c === '"') {
      const close = sec.indexOf('"', i + 1);
      if (close === -1) return null;
      lit = sec.slice(i + 1, close);
      i = close;
    } else if (c === '\\') { lit = sec[i + 1] ?? ''; i += 1; } else if (c === '_' || c === '*') { i += 1; continue; } else if (c === '%') { percents += 1; lit = '%'; } else if (/[0#?.,]/.test(c)) {
      if (post) return null; // a second mask run
      mask += c;
      continue;
    } else if (/[A-Za-z]/.test(c)) return null; // unquoted letters: a date token or an unknown code
    else lit = c;
    if (mask) post += lit; else pre += lit;
  }
  // A literal-only section ("zero" in `0.0;(0.0);"zero"`) is just its text.
  if (!/[0#?]/.test(mask)) return secs.length > 1 && sec !== secs[0] ? pre + post : null;

  const dot = mask.indexOf('.');
  const intMask = dot === -1 ? mask : mask.slice(0, dot);
  const decMask = dot === -1 ? '' : mask.slice(dot + 1);
  if (decMask.includes('.') || /,/.test(decMask)) return null;
  const grouping = /\d|[#?0]/.test(intMask) && intMask.replace(/,+$/, '').includes(',');
  const trailing = (intMask.match(/,+$/) || [''])[0].length; // each divides by 1000
  const minInt = (intMask.match(/0/g) || []).length;
  const decimals = decMask.length;
  const minDec = (decMask.match(/0/g) || []).length;

  let v = value * (100 ** percents) / (1000 ** trailing);
  v = roundAway(v, decimals);
  let [whole, frac = ''] = v.toFixed(decimals).split('.');
  while (frac.length > minDec && frac.endsWith('0')) frac = frac.slice(0, -1);
  whole = whole.replace(/^0+(?=\d)/, '');
  if (whole === '0' && minInt === 0 && frac) whole = '';
  if (whole.length < minInt) whole = whole.padStart(minInt, '0');
  if (grouping) whole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${sign}${pre}${whole}${frac ? `.${frac}` : ''}${post}`;
}

/**
 * Does this look like an Excel/Sheets date format rather than a Moment one?
 * Moment spells the year `Y`; a lowercase `y` is therefore decisive, and a
 * format of lowercase d/m with no uppercase D/M/Y is the dd-mm form.
 */
export function isExcelDateFormat(fmt) {
  const bare = fmt.replace(/"[^"]*"|\[[^\]]*\]/g, '');
  if (/y/.test(bare)) return true;
  return /d/.test(bare) && /m/.test(bare) && !/[DMY]/.test(bare);
}

/**
 * Translate an Excel date format to the Moment-style one `formatDate` reads.
 * @param {string} fmt
 * @returns {string|null}
 */
export function excelDateFormatToMoment(fmt) {
  const s = fmt;
  const tokens = [];
  const re = /"([^"]*)"|\\(.)|(yyyy|yy|mmmm|mmm|mm|m|dddd|ddd|dd|d|hh|h|ss|s|am\/pm|a\/p)|(.)/gi;
  let m;
  while ((m = re.exec(s)) !== null) {
    if (m[1] !== undefined) tokens.push({ lit: m[1] });
    else if (m[2] !== undefined) tokens.push({ lit: m[2] });
    else if (m[3] !== undefined) tokens.push({ tok: m[3].toLowerCase() });
    else if (/[A-Za-z]/.test(m[4])) return null; // an unknown letter would be echoed as a token
    else tokens.push({ lit: m[4] });
  }
  const isTok = (t, set) => t && t.tok && set.includes(t.tok);
  const MAP = { yyyy: 'YYYY', yy: 'YY', mmmm: 'MMMM', mmm: 'MMM', dddd: 'dddd', ddd: 'ddd', dd: 'DD', d: 'D', hh: 'HH', h: 'H', ss: 'ss', s: 's', 'am/pm': 'A', 'a/p': 'a' };
  const hasAmPm = tokens.some((t) => isTok(t, ['am/pm', 'a/p']));
  let out = '';
  tokens.forEach((t, i) => {
    if (t.lit !== undefined) { out += t.lit.replace(/[A-Za-z]+/g, (x) => `[${x}]`); return; }
    if (t.tok === 'm' || t.tok === 'mm') {
      // minutes right after an hour token, or right before seconds
      const prev = tokens[i - 1] && tokens[i - 1].lit === undefined ? tokens[i - 1] : tokens[i - 2];
      const next = tokens[i + 1] && tokens[i + 1].lit === undefined ? tokens[i + 1] : tokens[i + 2];
      const minutes = isTok(prev, ['h', 'hh']) || isTok(next, ['s', 'ss']);
      out += minutes ? t.tok : (t.tok === 'm' ? 'M' : 'MM');
      return;
    }
    const mapped = MAP[t.tok];
    out += hasAmPm && (t.tok === 'h' || t.tok === 'hh') ? (t.tok === 'h' ? 'h' : 'hh') : mapped;
  });
  return out;
}
