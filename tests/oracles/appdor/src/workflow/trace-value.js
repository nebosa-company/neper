import { redactSample } from './hook-ingress.js';

const SENSITIVE_QUERY = /token|secret|password|signature|credential|authorization|api.?key/i;
const SENSITIVE_KEY = /^(?:private[-_]?key|client[-_]?secret|credential(?:s)?|session[-_]?token)$/i;

function utf8Length(value) {
  let bytes = 0;
  for (const character of value) {
    const point = character.codePointAt(0);
    bytes += point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
  }
  return bytes;
}

function safeString(value, maxString) {
  let out = value.replace(/\b(Bearer|Basic)\s+[^\s"'<>]+/gi, '$1 [redacted]');
  out = out.replace(/https?:\/\/[^\s"'<>]+/gi, (match) => {
    const suffix = match.match(/[),.;]+$/)?.[0] || '';
    const address = suffix ? match.slice(0, -suffix.length) : match;
    try {
      const url = new URL(address);
      if (url.username || url.password) { url.username = '[redacted]'; url.password = ''; }
      for (const key of url.searchParams.keys()) {
        if (SENSITIVE_QUERY.test(key)) url.searchParams.set(key, '[redacted]');
      }
      if (url.username || [...url.searchParams.keys()].some((key) => SENSITIVE_QUERY.test(key))) return url.href + suffix;
    } catch { /* An ordinary string remains an ordinary string. */ }
    return match;
  });
  return out.length > maxString ? `${out.slice(0, maxString)}[truncated]` : out;
}

/** A bounded, credential-redacted copy for inspection; never a replay value. */
export function traceValue(value, { maxBytes = 32768, maxString = 4096, maxItems = 100 } = {}) {
  let remaining = 1000;
  const walk = (item, depth = 0) => {
    if (remaining-- <= 0 || depth > 12) return '[truncated]';
    if (typeof item === 'string') return safeString(item, maxString);
    if (Array.isArray(item)) {
      const out = item.slice(0, maxItems).map((one) => walk(one, depth + 1));
      if (item.length > maxItems) out.push('[truncated]');
      return out;
    }
    if (item && typeof item === 'object') {
      const entries = Object.entries(item);
      const out = Object.fromEntries(entries.slice(0, maxItems).map(([key, one]) => [key, SENSITIVE_KEY.test(key) ? '[redacted]' : walk(one, depth + 1)]));
      if (entries.length > maxItems) out._truncated = true;
      return out;
    }
    return item;
  };
  const out = walk(redactSample(value));
  const encoded = JSON.stringify(out);
  if (encoded && utf8Length(encoded) > maxBytes) {
    return { _truncated: true, preview: encoded.slice(0, Math.floor(maxBytes / 4)), marker: '[truncated]' };
  }
  return out;
}
