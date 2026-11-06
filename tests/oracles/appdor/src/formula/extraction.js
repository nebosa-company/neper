/**
 * Extraction functions (docs/formulas.md:191-193): `jsonquery` and `xmlquery`.
 * No benchmark competitor's formula tier offers these natively
 * (REQ-FORMULAENGINE-13).
 *
 * Both are self-contained (no DOM/XPath dependency): a JSONPath-class walker for
 * JSON and a minimal well-formed-XML parser + path walker for XML. A
 * non-matching path returns blank rather than an error.
 */

import { isError, valueError } from './errors.js';
import { toText, isBlank } from './values.js';

const CATEGORY = 'extraction';

// --- JSON ------------------------------------------------------------------

function jsonPathTokens(path) {
  const p = String(path).replace(/^\$\.?/, '');
  const tokens = [];
  const re = /\[(\d+)\]|\["([^"]*)"\]|\['([^']*)'\]|([^.[\]]+)/g;
  let m;
  while ((m = re.exec(p)) !== null) {
    if (m[1] !== undefined) tokens.push(Number(m[1]));
    else if (m[2] !== undefined) tokens.push(m[2]);
    else if (m[3] !== undefined) tokens.push(m[3]);
    else if (m[4] !== undefined) tokens.push(m[4]);
  }
  return tokens;
}

function walkJson(value, tokens) {
  let cur = value;
  for (const t of tokens) {
    if (cur == null) return null;
    if (typeof t === 'number') {
      if (!Array.isArray(cur) || t < 0 || t >= cur.length) return null;
      cur = cur[t];
    } else {
      if (typeof cur !== 'object' || Array.isArray(cur) || !(t in cur)) return null;
      cur = cur[t];
    }
  }
  return cur;
}

// --- XML -------------------------------------------------------------------

function parseXml(text) {
  let i = 0;
  const src = String(text);
  const n = src.length;

  const skipWs = () => {
    while (i < n && /\s/.test(src[i])) i++;
  };

  const parseNode = () => {
    skipWs();
    // Skip declarations, comments, processing instructions.
    while (src.startsWith('<?', i) || src.startsWith('<!--', i) || src.startsWith('<!', i)) {
      if (src.startsWith('<!--', i)) {
        const end = src.indexOf('-->', i);
        i = end === -1 ? n : end + 3;
      } else {
        const end = src.indexOf('>', i);
        i = end === -1 ? n : end + 1;
      }
      skipWs();
    }
    if (src[i] !== '<') return null;
    i++; // consume '<'
    let tag = '';
    while (i < n && !/[\s/>]/.test(src[i])) tag += src[i++];
    const attrs = {};
    // Attributes.
    while (i < n && src[i] !== '>' && src[i] !== '/') {
      skipWs();
      if (src[i] === '>' || src[i] === '/') break;
      let name = '';
      while (i < n && !/[\s=/>]/.test(src[i])) name += src[i++];
      skipWs();
      let val = '';
      if (src[i] === '=') {
        i++;
        skipWs();
        const q = src[i];
        if (q === '"' || q === "'") {
          i++;
          while (i < n && src[i] !== q) val += src[i++];
          i++;
        }
      }
      if (name) attrs[name] = val;
    }
    if (src[i] === '/') {
      i += 2; // '/>'
      return { tag, attrs, children: [], text: '' };
    }
    i++; // consume '>'
    const children = [];
    let textContent = '';
    while (i < n) {
      if (src.startsWith('</', i)) {
        i += 2;
        while (i < n && src[i] !== '>') i++;
        i++; // consume '>'
        break;
      }
      if (src[i] === '<') {
        const child = parseNode();
        if (child) children.push(child);
      } else {
        textContent += src[i++];
      }
    }
    return { tag, attrs, children, text: textContent.trim() };
  };

  return parseNode();
}

function xmlPathSegments(path) {
  return String(path)
    .replace(/^\//, '')
    .split('/')
    .filter((s) => s.length > 0);
}

function walkXml(root, path) {
  if (!root) return null;
  const segments = xmlPathSegments(path);
  if (segments.length === 0) return null;

  let attr = null;
  const last = segments[segments.length - 1];
  const attrMatch = last.match(/^@(.+)$/);
  if (attrMatch) {
    attr = attrMatch[1];
    segments.pop();
  }

  let nodes = [root];
  // First segment must match the root tag.
  const first = parseSeg(segments[0]);
  if (!root || root.tag !== first.tag) return null;
  nodes = first.index != null ? (first.index === 0 ? [root] : []) : [root];

  for (let s = 1; s < segments.length; s++) {
    const seg = parseSeg(segments[s]);
    let next = [];
    for (const node of nodes) {
      const matches = node.children.filter((c) => c.tag === seg.tag);
      if (seg.index != null) {
        if (matches[seg.index]) next.push(matches[seg.index]);
      } else {
        next = next.concat(matches);
      }
    }
    nodes = next;
  }

  if (nodes.length === 0) return null;
  const values = nodes.map((nd) => (attr ? (attr in nd.attrs ? nd.attrs[attr] : null) : nd.text));
  const filtered = values.filter((v) => v !== null);
  if (filtered.length === 0) return null;
  return filtered.length === 1 ? filtered[0] : filtered;
}

function parseSeg(seg) {
  const m = seg.match(/^([^[]+)(?:\[(\d+)\])?$/);
  if (!m) return { tag: seg, index: null };
  return { tag: m[1], index: m[2] != null ? Number(m[2]) : null };
}

// --- catalog ---------------------------------------------------------------

const extraction = {
  JSONQUERY: {
    category: CATEGORY,
    aliases: ['JSON_QUERY'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      if (isBlank(args[0])) return null;
      const text = toText(args[0]);
      if (isError(text)) return text;
      let data;
      try {
        data = JSON.parse(text);
      } catch {
        return valueError('jsonquery: invalid JSON input');
      }
      const result = walkJson(data, jsonPathTokens(toText(args[1])));
      return result === undefined ? null : result;
    },
  },
  XMLQUERY: {
    category: CATEGORY,
    aliases: ['XML_QUERY'],
    minArgs: 2,
    maxArgs: 2,
    fn: (args) => {
      if (isBlank(args[0])) return null;
      const text = toText(args[0]);
      if (isError(text)) return text;
      let root;
      try {
        root = parseXml(text);
      } catch {
        return valueError('xmlquery: invalid XML input');
      }
      if (!root) return valueError('xmlquery: invalid XML input');
      const result = walkXml(root, toText(args[1]));
      return result === undefined ? null : result;
    },
  },
};

export default extraction;
