/**
 * Jinja2-subset template engine — the one templating language every step
 * config field, HTTP body, connector parameter and Python step shares.
 *
 * The repo already had `{{path}}` interpolation in `automations/step-catalog`.
 * That is enough to paste a field into a Slack message and nothing more: it
 * cannot default a missing value, cannot loop a list into a JSON array, and
 * cannot decide anything. Every automation that needed one of those grew a
 * `script` step instead, which is a 10,000-step budget and a grants review to
 * avoid writing `| default("")`.
 *
 * So this is real Jinja, minus the parts that need a file system:
 *   {{ expr }}                       output (HTML-escaped only on demand)
 *   {% if %} / {% elif %} / {% else %} / {% endif %}
 *   {% for x in seq %} … {% else %} … {% endfor %}   (loop.index/first/last/…)
 *   {% set name = expr %}
 *   {# comment #}
 *   filters (|), tests (is), the ternary `a if c else b`, and/or/not,
 *   comparисons, arithmetic, ~ concat, lists, dicts, attribute + subscript
 *   access, and function calls on the filter/test registries only.
 *
 * No `{% include %}`, `{% extends %}`, `{% macro %}` or `{% import %}`: they
 * all resolve a *name* against a loader, and a template loader that reaches
 * outside the automation is an SSRF surface with a syntax. No `{% raw %}`
 * either — nothing here re-emits template source.
 *
 * ## Why `renderValue` exists beside `render`
 *
 * A config field holding `{{ order.total }}` must produce the NUMBER 42, not
 * the string "42" — a webhook body that ships `{"total":"42"}` where the
 * receiver's schema says integer is a 400 the author cannot see from the
 * builder. When a template is exactly one `{{ … }}` and nothing else, the
 * native value is returned unstringified. Anything with literal text around
 * it is a string, because that is what concatenation means.
 *
 * Deliberately: undefined is EMPTY, never the literal "undefined". Jinja's
 * default undefined renders as '' and that is the behaviour authors expect;
 * a payload carrying the seven characters `undefined` is a bug that reaches
 * production silently. `strict: true` turns it into an error instead, which
 * is what the workflow validator uses at save time.
 *
 * ## TemplateError messages deliberately do not translate
 *
 * Every message this engine throws is parser/renderer structural text in the
 * template language's own terms — it quotes tokens, tag names, filter and
 * test names that must appear verbatim so the author can paste them back into
 * the template. The formula engine drew this exact line in
 * `src/formula/type-check.js`: the parser's structural message stays
 * untranslated (`detail`), and the author-facing sentence around it is a
 * catalogue key the EDITOR resolves. This engine has no editor layer of its
 * own yet, and it runs where no viewer exists — the ai-proxy loads it through
 * the SDK and the workflow-worker through the effects adapter, and a message
 * thrown mid-run lands in run logs read by people in different languages, so
 * translating at throw time would freeze the runner's locale into shared
 * data. The strings are recorded in `scripts/i18n-hardcoded-ignore.txt`; the
 * keyed rendering belongs to whichever desk builds the template-diagnostics
 * layer that `type-check.js` models.
 */

// --- lexer ----------------------------------------------------------------

const OPERATORS = [
  '**', '//', '==', '!=', '<=', '>=', '~', '+', '-', '*', '/', '%',
  '<', '>', '(', ')', '[', ']', '{', '}', ',', '.', ':', '|', '=',
];

const KEYWORDS = new Set(['and', 'or', 'not', 'in', 'is', 'if', 'else', 'true', 'false', 'none', 'True', 'False', 'None']);

/** Tokenize a Jinja expression (the inside of {{ }} or {% %}). */
export function tokenizeExpression(src) {
  const tokens = [];
  let i = 0;
  const text = String(src);

  while (i < text.length) {
    const ch = text[i];

    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') { i++; continue; }

    // strings
    if (ch === '"' || ch === "'") {
      const quote = ch;
      let out = '';
      i++;
      while (i < text.length && text[i] !== quote) {
        if (text[i] === '\\' && i + 1 < text.length) {
          const next = text[i + 1];
          out += next === 'n' ? '\n' : next === 't' ? '\t' : next === 'r' ? '\r' : next;
          i += 2;
        } else {
          out += text[i];
          i++;
        }
      }
      if (i >= text.length) throw new TemplateError('unterminated string literal');
      i++;
      tokens.push({ type: 'string', value: out });
      continue;
    }

    // numbers
    if (ch >= '0' && ch <= '9') {
      let out = '';
      while (i < text.length && /[0-9_]/.test(text[i])) { out += text[i]; i++; }
      if (text[i] === '.' && /[0-9]/.test(text[i + 1] || '')) {
        out += '.';
        i++;
        while (i < text.length && /[0-9_]/.test(text[i])) { out += text[i]; i++; }
      }
      tokens.push({ type: 'number', value: Number(out.replace(/_/g, '')) });
      continue;
    }

    // names & keywords
    if (/[A-Za-z_$]/.test(ch)) {
      let out = '';
      while (i < text.length && /[A-Za-z0-9_$]/.test(text[i])) { out += text[i]; i++; }
      tokens.push({ type: KEYWORDS.has(out) ? 'keyword' : 'name', value: out });
      continue;
    }

    const op = OPERATORS.find((o) => text.startsWith(o, i));
    if (op) {
      tokens.push({ type: 'op', value: op });
      i += op.length;
      continue;
    }

    throw new TemplateError(`unexpected character "${ch}" in expression`);
  }

  tokens.push({ type: 'eof', value: null });
  return tokens;
}

export class TemplateError extends Error {
  constructor(message, line) {
    super(line ? `${message} (line ${line})` : message);
    this.name = 'TemplateError';
    this.line = line;
  }
}

// --- expression parser ----------------------------------------------------

function parser(tokens) {
  let pos = 0;
  const peek = () => tokens[pos];
  const next = () => tokens[pos++];
  const at = (type, value) => tokens[pos].type === type && (value === undefined || tokens[pos].value === value);
  const eat = (type, value) => (at(type, value) ? (pos++, true) : false);
  const expect = (type, value) => {
    if (!at(type, value)) throw new TemplateError(`expected ${value || type}, got "${peek().value}"`);
    return next();
  };

  // lowest precedence: inline if
  function parseExpression() {
    const body = parseOr();
    if (at('keyword', 'if')) {
      next();
      const cond = parseOr();
      let alt = { type: 'const', value: undefined };
      if (eat('keyword', 'else')) alt = parseExpression();
      return { type: 'ternary', cond, then: body, else: alt };
    }
    return body;
  }

  function parseOr() {
    let left = parseAnd();
    while (at('keyword', 'or')) { next(); left = { type: 'or', left, right: parseAnd() }; }
    return left;
  }

  function parseAnd() {
    let left = parseNot();
    while (at('keyword', 'and')) { next(); left = { type: 'and', left, right: parseNot() }; }
    return left;
  }

  function parseNot() {
    if (at('keyword', 'not')) { next(); return { type: 'not', operand: parseNot() }; }
    return parseComparison();
  }

  const COMPARE = ['==', '!=', '<', '>', '<=', '>='];

  function parseComparison() {
    let left = parseConcat();
    for (;;) {
      if (peek().type === 'op' && COMPARE.includes(peek().value)) {
        const op = next().value;
        left = { type: 'compare', op, left, right: parseConcat() };
      } else if (at('keyword', 'in')) {
        next();
        left = { type: 'in', left, right: parseConcat(), negate: false };
      } else if (at('keyword', 'not') && tokens[pos + 1] && tokens[pos + 1].value === 'in') {
        next(); next();
        left = { type: 'in', left, right: parseConcat(), negate: true };
      } else if (at('keyword', 'is')) {
        next();
        const negate = eat('keyword', 'not');
        // A test name may collide with a keyword — `is none`, `is defined`,
        // `is true`. The lexer cannot know that `none` here names a test
        // rather than the null literal, so the parser decides by position.
        if (peek().type !== 'name' && peek().type !== 'keyword') {
          throw new TemplateError(`expected a test name after "is", got "${peek().value}"`);
        }
        const name = next().value;
        let args = [];
        if (at('op', '(')) args = parseCallArgs();
        else if (peek().type === 'string' || peek().type === 'number' || peek().type === 'name') {
          // `is divisibleby 3` — Jinja allows one bare argument.
          args = [parseConcat()];
        }
        left = { type: 'test', name, operand: left, args, negate };
      } else {
        return left;
      }
    }
  }

  function parseConcat() {
    let left = parseAdditive();
    while (at('op', '~')) { next(); left = { type: 'concat', left, right: parseAdditive() }; }
    return left;
  }

  function parseAdditive() {
    let left = parseMultiplicative();
    while (at('op', '+') || at('op', '-')) {
      const op = next().value;
      left = { type: 'binary', op, left, right: parseMultiplicative() };
    }
    return left;
  }

  function parseMultiplicative() {
    let left = parseUnary();
    while (at('op', '*') || at('op', '/') || at('op', '//') || at('op', '%')) {
      const op = next().value;
      left = { type: 'binary', op, left, right: parseUnary() };
    }
    return left;
  }

  /**
   * Unary binds tighter than a filter, but the filter applies to the RESULT.
   *
   * `{{ -5|abs }}` is 5, not -5. Jinja parses the sign onto the literal and
   * then pipes it, and getting this backwards is silent: the template renders
   * a number either way, and the wrong one only shows up in the receiving
   * system. So the sign is consumed by `parseSigned` (which cannot see `|`)
   * and `parseFilterChain` wraps whatever came back.
   */
  function parseUnary() {
    return parseFilterChain(parseSigned());
  }

  function parseSigned() {
    if (at('op', '-')) { next(); return { type: 'neg', operand: parseSigned() }; }
    if (at('op', '+')) { next(); return parseSigned(); }
    return parsePower();
  }

  function parsePower() {
    const base = parsePostfix();
    if (at('op', '**')) { next(); return { type: 'binary', op: '**', left: base, right: parseUnary() }; }
    return base;
  }

  function parseFilterChain(start) {
    let node = start;
    while (at('op', '|')) {
      next();
      const name = expect('name').value;
      const args = at('op', '(') ? parseCallArgs() : [];
      // `(x|first).name` — attribute access after a filter still applies.
      node = parsePostfixOps({ type: 'filter', name, operand: node, args });
    }
    return node;
  }

  function parseCallArgs() {
    expect('op', '(');
    const args = [];
    const kwargs = {};
    while (!at('op', ')')) {
      if (peek().type === 'name' && tokens[pos + 1] && tokens[pos + 1].type === 'op' && tokens[pos + 1].value === '=') {
        const key = next().value;
        next();
        kwargs[key] = parseExpression();
      } else {
        args.push(parseExpression());
      }
      if (!eat('op', ',')) break;
    }
    expect('op', ')');
    if (Object.keys(kwargs).length) args.kwargs = kwargs;
    return args;
  }

  function parsePostfix() {
    return parsePostfixOps(parsePrimary());
  }

  function parsePostfixOps(start) {
    let node = start;
    for (;;) {
      if (at('op', '.')) {
        next();
        const name = peek().type === 'number' ? String(next().value) : expect('name').value;
        node = { type: 'attr', object: node, name };
      } else if (at('op', '[')) {
        next();
        const index = parseExpression();
        expect('op', ']');
        node = { type: 'subscript', object: node, index };
      } else if (at('op', '(')) {
        node = { type: 'call', callee: node, args: parseCallArgs() };
      } else {
        return node;
      }
    }
  }

  function parsePrimary() {
    const token = peek();

    if (token.type === 'string') { next(); return { type: 'const', value: token.value }; }
    if (token.type === 'number') { next(); return { type: 'const', value: token.value }; }

    if (token.type === 'keyword') {
      if (token.value === 'true' || token.value === 'True') { next(); return { type: 'const', value: true }; }
      if (token.value === 'false' || token.value === 'False') { next(); return { type: 'const', value: false }; }
      if (token.value === 'none' || token.value === 'None') { next(); return { type: 'const', value: null }; }
    }

    if (token.type === 'name') { next(); return { type: 'name', name: token.value }; }

    if (at('op', '(')) {
      next();
      const inner = parseExpression();
      // A tuple in parens is used by `{% for k, v in … %}` only; a bare
      // grouped expression is far more common, so a trailing comma decides.
      if (at('op', ',')) {
        const items = [inner];
        while (eat('op', ',') && !at('op', ')')) items.push(parseExpression());
        expect('op', ')');
        return { type: 'list', items };
      }
      expect('op', ')');
      return inner;
    }

    if (at('op', '[')) {
      next();
      const items = [];
      while (!at('op', ']')) {
        items.push(parseExpression());
        if (!eat('op', ',')) break;
      }
      expect('op', ']');
      return { type: 'list', items };
    }

    if (at('op', '{')) {
      next();
      const entries = [];
      while (!at('op', '}')) {
        const key = parseExpression();
        expect('op', ':');
        entries.push([key, parseExpression()]);
        if (!eat('op', ',')) break;
      }
      expect('op', '}');
      return { type: 'dict', entries };
    }

    throw new TemplateError(`unexpected token "${token.value ?? 'end of expression'}"`);
  }

  const ast = parseExpression();
  if (!at('eof')) throw new TemplateError(`unexpected trailing input "${peek().value}"`);
  return ast;
}

/** Parse a Jinja expression string into an AST. */
export function parseExpressionSource(src) {
  return parser(tokenizeExpression(src));
}

// --- template parser ------------------------------------------------------

// Only OPENING delimiters are matched in text mode: a stray `}}`, `%}` or `#}`
// in plain text (a JSON body ending in `}}`) is just text. The close of a tag
// is found by scanning the expression, so a `}}` inside a string literal or a
// nested dict literal does not end it early.
const TAG_RE = /\{\{-?|\{%-?|\{#/;

const BACKSLASH = String.fromCharCode(92);

function findTagClose(src, from, closeToken) {
  let depth = 0;
  for (let k = from; k < src.length; k++) {
    const ch = src[k];
    if (ch === '"' || ch === "'") {
      for (k++; k < src.length && src[k] !== ch; k++) if (src[k] === BACKSLASH) k++;
      continue;
    }
    if (ch === '{') { depth++; continue; }
    if (ch === '}' && depth > 0) { depth--; continue; }
    if (src.startsWith(closeToken, k)) return k;
  }
  return -1;
}

/**
 * Split a template into a node tree.
 *
 * Whitespace control (`{%-` / `-%}`) is honoured because a `{% for %}` that
 * emits a newline per iteration produces invalid JSON, and the author's only
 * other option is to write the loop on one unreadable line.
 */
export function parseTemplate(source) {
  const src = String(source ?? '');
  const tokens = [];
  let i = 0;
  let line = 1;

  while (i < src.length) {
    const rest = src.slice(i);
    const match = rest.match(TAG_RE);
    if (!match) { tokens.push({ kind: 'text', value: rest, line }); break; }

    if (match.index > 0) {
      const text = rest.slice(0, match.index);
      tokens.push({ kind: 'text', value: text, line });
      line += (text.match(/\n/g) || []).length;
      i += match.index;
      continue;
    }

    const open = match[0];
    if (open === '{#') {
      const end = src.indexOf('#}', i + 2);
      if (end === -1) throw new TemplateError('unterminated comment', line);
      line += (src.slice(i, end).match(/\n/g) || []).length;
      i = end + 2;
      continue;
    }

    const isOutput = open.startsWith('{{');
    const closeToken = isOutput ? '}}' : '%}';
    const end = findTagClose(src, i + open.length, closeToken);
    if (end === -1) throw new TemplateError(`unterminated ${isOutput ? 'expression' : 'tag'}`, line);

    let body = src.slice(i + open.length, end);
    const trimRight = body.endsWith('-');
    if (trimRight) body = body.slice(0, -1);

    tokens.push({
      kind: isOutput ? 'output' : 'tag',
      value: body.trim(),
      trimLeft: open.endsWith('-'),
      trimRight,
      line,
    });
    line += (src.slice(i, end).match(/\n/g) || []).length;
    i = end + closeToken.length;
  }

  // apply whitespace control to neighbouring text nodes
  for (let n = 0; n < tokens.length; n++) {
    if (tokens[n].kind === 'text') continue;
    if (tokens[n].trimLeft && tokens[n - 1] && tokens[n - 1].kind === 'text') {
      tokens[n - 1].value = tokens[n - 1].value.replace(/\s+$/, '');
    }
    if (tokens[n].trimRight && tokens[n + 1] && tokens[n + 1].kind === 'text') {
      tokens[n + 1].value = tokens[n + 1].value.replace(/^\s*\n?/, '');
    }
  }

  return buildTree(tokens);
}

function buildTree(tokens) {
  let pos = 0;

  function parseBody(stopTags) {
    const nodes = [];
    while (pos < tokens.length) {
      const token = tokens[pos];

      if (token.kind === 'text') { pos++; nodes.push({ type: 'text', value: token.value }); continue; }
      if (token.kind === 'output') {
        pos++;
        nodes.push({ type: 'output', expr: parseExpressionSource(token.value), line: token.line });
        continue;
      }

      const keyword = token.value.split(/\s+/)[0];
      if (stopTags && stopTags.includes(keyword)) return nodes;
      pos++;

      if (keyword === 'if') {
        nodes.push(parseIf(token));
      } else if (keyword === 'for') {
        nodes.push(parseFor(token));
      } else if (keyword === 'set') {
        const m = token.value.match(/^set\s+([A-Za-z_$][\w$]*)\s*=\s*([\s\S]+)$/);
        if (!m) throw new TemplateError('malformed {% set %}', token.line);
        nodes.push({ type: 'set', name: m[1], expr: parseExpressionSource(m[2]), line: token.line });
      } else {
        throw new TemplateError(`unknown tag "${keyword}"`, token.line);
      }
    }
    if (stopTags) throw new TemplateError(`missing {% end… %} for ${stopTags[stopTags.length - 1]}`);
    return nodes;
  }

  function parseIf(token) {
    const condSrc = token.value.replace(/^if\s+/, '');
    const branches = [{ cond: parseExpressionSource(condSrc), body: parseBody(['elif', 'else', 'endif']) }];
    let fallback = [];
    for (;;) {
      const tag = tokens[pos];
      if (!tag) throw new TemplateError('missing {% endif %}', token.line);
      const keyword = tag.value.split(/\s+/)[0];
      pos++;
      if (keyword === 'elif') {
        branches.push({
          cond: parseExpressionSource(tag.value.replace(/^elif\s+/, '')),
          body: parseBody(['elif', 'else', 'endif']),
        });
      } else if (keyword === 'else') {
        fallback = parseBody(['endif']);
      } else {
        break; // endif
      }
    }
    return { type: 'if', branches, fallback, line: token.line };
  }

  function parseFor(token) {
    const m = token.value.match(/^for\s+([A-Za-z_$][\w$]*(?:\s*,\s*[A-Za-z_$][\w$]*)?)\s+in\s+([\s\S]+?)(?:\s+if\s+([\s\S]+))?$/);
    if (!m) throw new TemplateError('malformed {% for %}', token.line);
    const names = m[1].split(',').map((s) => s.trim());
    const node = {
      type: 'for',
      names,
      seq: parseExpressionSource(m[2]),
      guard: m[3] ? parseExpressionSource(m[3]) : null,
      body: parseBody(['else', 'endfor']),
      empty: [],
      line: token.line,
    };
    const tag = tokens[pos];
    pos++;
    if (tag && tag.value.split(/\s+/)[0] === 'else') {
      node.empty = parseBody(['endfor']);
      pos++;
    }
    return node;
  }

  return parseBody(null);
}

// --- limits ---------------------------------------------------------------

/** Hard ceilings on author-controlled sizes (padding widths, batch counts). */
const MAX_WIDTH = 10000;
const MAX_STRING = 1000000;
/** Total loop iterations and output characters one render may spend. */
export const DEFAULT_WORK_BUDGET = { iterations: 1000000, chars: 5000000 };

function boundedInt(value, name, { min = 0, max = MAX_WIDTH, fallback } = {}) {
  const n = Math.trunc(Number(value));
  if (!Number.isFinite(n)) {
    if (fallback !== undefined) return fallback;
    throw new TemplateError(`${name} must be a whole number`);
  }
  if (n < min) throw new TemplateError(`${name} must be at least ${min}`);
  return Math.min(n, max);
}

function budgetOf(options) {
  if (!options.budget) options.budget = { iterations: 0, chars: 0 };
  return options.budget;
}

function spend(options, kind, amount, line) {
  const budget = budgetOf(options);
  budget[kind] += amount;
  const limit = (options.workBudget || DEFAULT_WORK_BUDGET)[kind];
  if (budget[kind] > limit) {
    throw new TemplateError(`render exceeded its ${kind === 'chars' ? 'output size' : 'work'} limit`, line);
  }
}

// --- filters --------------------------------------------------------------

const jsonStable = (v, indent) => JSON.stringify(v, null, indent || undefined);

function toIterable(v) {
  if (v == null) return [];
  if (Array.isArray(v)) return v;
  if (typeof v === 'string') return v.split('');
  if (typeof v === 'object') return Object.values(v);
  return [v];
}

function getAttribute(obj, path) {
  return String(path).split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

/** The filter registry. Extendable via `registerFilter` for connector packs. */
export const FILTERS = {
  // strings
  upper: (v) => String(v ?? '').toUpperCase(),
  lower: (v) => String(v ?? '').toLowerCase(),
  title: (v) => String(v ?? '').replace(/\w\S*/g, (w) => w[0].toUpperCase() + w.slice(1).toLowerCase()),
  capitalize: (v) => { const s = String(v ?? ''); return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase(); },
  trim: (v, chars) => {
    const s = String(v ?? '');
    if (!chars) return s.trim();
    // A character SET, not a pattern: a backslash, "^" or "a-z" are literal members.
    const set = new Set([...String(chars)]);
    const cps = [...s];
    let start = 0;
    let end = cps.length;
    while (start < end && set.has(cps[start])) start++;
    while (end > start && set.has(cps[end - 1])) end--;
    return cps.slice(start, end).join('');
  },
  replace: (v, from, to) => String(v ?? '').split(String(from)).join(String(to ?? '')),
  truncate: (v, len = 255, killwords = false, end = '…') => {
    const s = String(v ?? '');
    if (s.length <= len) return s;
    if (killwords) return s.slice(0, len) + end;
    const cut = s.slice(0, len);
    return cut.slice(0, cut.lastIndexOf(' ') > 0 ? cut.lastIndexOf(' ') : len) + end;
  },
  indent: (v, width = 4, first = false) => {
    const pad = ' '.repeat(boundedInt(width, 'indent width', { fallback: 4 }));
    const lines = String(v ?? '').split('\n');
    return lines.map((l, idx) => (idx === 0 && !first ? l : pad + l)).join('\n');
  },
  center: (v, width = 80) => {
    const s = String(v ?? '');
    const total = Math.max(0, boundedInt(width, 'center width', { fallback: 80 }) - s.length);
    const left = Math.floor(total / 2);
    return ' '.repeat(left) + s + ' '.repeat(total - left);
  },
  wordcount: (v) => (String(v ?? '').match(/\S+/g) || []).length,
  striptags: (v) => String(v ?? '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim(),
  escape: (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'),
  urlencode: (v) => (v && typeof v === 'object'
    ? Object.entries(v).map(([k, val]) => `${encodeURIComponent(k)}=${encodeURIComponent(val)}`).join('&')
    : encodeURIComponent(String(v ?? ''))),

  // numbers
  abs: (v) => Math.abs(Number(v)),
  round: (v, precision = 0, method = 'common') => {
    const factor = 10 ** boundedInt(precision, 'round precision', { max: 15, fallback: 0 });
    const n = Number(v) * factor;
    const rounded = method === 'ceil' ? Math.ceil(n) : method === 'floor' ? Math.floor(n) : Math.round(n);
    return rounded / factor;
  },
  int: (v, fallback = 0) => { const n = parseInt(v, 10); return Number.isNaN(n) ? fallback : n; },
  float: (v, fallback = 0) => { const n = parseFloat(v); return Number.isNaN(n) ? fallback : n; },
  string: (v) => (v == null ? '' : typeof v === 'object' ? jsonStable(v) : String(v)),

  // sequences
  length: (v) => (v == null ? 0 : typeof v === 'object' && !Array.isArray(v) ? Object.keys(v).length : (v.length ?? 0)),
  count: (v) => FILTERS.length(v),
  first: (v) => toIterable(v)[0],
  last: (v) => { const list = toIterable(v); return list[list.length - 1]; },
  join: (v, sep = '', attribute) => toIterable(v).map((x) => (attribute ? getAttribute(x, attribute) : x)).map((x) => (x == null ? '' : String(x))).join(String(sep)),
  list: (v) => toIterable(v),
  reverse: (v) => (typeof v === 'string' ? v.split('').reverse().join('') : toIterable(v).slice().reverse()),
  sort: (v, reverse = false, caseSensitive = false, attribute = null) => {
    const list = toIterable(v).slice();
    const fold = (x) => (!caseSensitive && typeof x === 'string' ? x.toLowerCase() : x);
    list.sort((a, b) => {
      const x = fold(attribute ? getAttribute(a, attribute) : a);
      const y = fold(attribute ? getAttribute(b, attribute) : b);
      if (x === y) return 0;
      if (x == null) return -1;
      if (y == null) return 1;
      return x < y ? -1 : 1;
    });
    return reverse ? list.reverse() : list;
  },
  unique: (v, attribute = null) => {
    const seen = new Set();
    return toIterable(v).filter((x) => {
      const key = JSON.stringify(attribute ? getAttribute(x, attribute) : x);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  },
  sum: (v, attribute = null, start = 0) => toIterable(v).reduce((acc, x) => acc + (Number(attribute ? getAttribute(x, attribute) : x) || 0), start),
  min: (v, attribute = null) => toIterable(v).reduce((acc, x) => { const n = attribute ? getAttribute(x, attribute) : x; return acc === undefined || n < acc ? n : acc; }, undefined),
  max: (v, attribute = null) => toIterable(v).reduce((acc, x) => { const n = attribute ? getAttribute(x, attribute) : x; return acc === undefined || n > acc ? n : acc; }, undefined),
  map: (v, attribute) => toIterable(v).map((x) => getAttribute(x, attribute)),
  select: (v, test, ...args) => toIterable(v).filter((x) => applyTest(test, x, args)),
  reject: (v, test, ...args) => toIterable(v).filter((x) => !applyTest(test, x, args)),
  selectattr: (v, attribute, test = 'defined', ...args) => toIterable(v).filter((x) => applyTest(test, getAttribute(x, attribute), args)),
  rejectattr: (v, attribute, test = 'defined', ...args) => toIterable(v).filter((x) => !applyTest(test, getAttribute(x, attribute), args)),
  batch: (v, size, fill) => {
    const list = toIterable(v);
    size = boundedInt(size, 'batch size', { min: 1, max: Math.max(1, list.length) });
    const out = [];
    for (let i = 0; i < list.length; i += size) {
      const chunk = list.slice(i, i + size);
      while (fill !== undefined && chunk.length < size) chunk.push(fill);
      out.push(chunk);
    }
    return out;
  },
  slice: (v, count, fill) => {
    const list = toIterable(v);
    count = boundedInt(count, 'slice count', { min: 1 });
    const per = Math.ceil(list.length / count);
    const out = [];
    for (let i = 0; i < count; i++) {
      const chunk = list.slice(i * per, (i + 1) * per);
      while (fill !== undefined && chunk.length < per) chunk.push(fill);
      out.push(chunk);
    }
    return out;
  },

  // mappings
  keys: (v) => Object.keys(v || {}),
  values: (v) => Object.values(v || {}),
  items: (v) => Object.entries(v || {}),
  dictsort: (v, reverse = false, by = 'key') => Object.entries(v || {}).sort((a, b) => {
    const i = by === 'value' ? 1 : 0;
    const cmp = a[i] < b[i] ? -1 : a[i] > b[i] ? 1 : 0;
    return reverse ? -cmp : cmp;
  }),

  // serialization — the reason this engine exists in an integration product
  tojson: (v, indent) => jsonStable(v, indent),
  json: (v, indent) => jsonStable(v, indent),
  fromjson: (v) => { try { return JSON.parse(String(v)); } catch { return null; } },
  b64encode: (v) => b64encodeText(String(v ?? '')),
  b64decode: (v) => b64decodeText(String(v ?? '')),

  // dates — epoch ms or ISO in, formatted out. No locale: automations are
  // machine-to-machine and a locale-shifted timestamp is a support ticket.
  datetimeformat: (v, format = 'YYYY-MM-DDTHH:mm:ss[Z]') => formatDate(v, format),
  date: (v, format = 'YYYY-MM-DD') => formatDate(v, format),
  timestamp: (v) => { const d = toDate(v); return d ? Math.floor(d.getTime() / 1000) : null; },

  // control
  default: (v, fallback = '', booleanMode = false) => (v === undefined || v === null || (booleanMode && !v) ? fallback : v),
  safe: (v) => v,
};

FILTERS.d = FILTERS.default;
FILTERS.e = FILTERS.escape;

/** Register an extra filter (connector packs use this for provider formats). */
export function registerFilter(name, fn) {
  if (typeof fn !== 'function') throw new TemplateError(`filter "${name}" must be a function`);
  FILTERS[name] = fn;
  return FILTERS[name];
}

// --- tests ----------------------------------------------------------------

export const TESTS = {
  defined: (v) => v !== undefined,
  undefined: (v) => v === undefined,
  none: (v) => v === null,
  null: (v) => v === null,
  string: (v) => typeof v === 'string',
  number: (v) => typeof v === 'number' && !Number.isNaN(v),
  integer: (v) => Number.isInteger(v),
  float: (v) => typeof v === 'number' && !Number.isInteger(v),
  boolean: (v) => typeof v === 'boolean',
  sequence: (v) => Array.isArray(v) || typeof v === 'string',
  mapping: (v) => !!v && typeof v === 'object' && !Array.isArray(v),
  iterable: (v) => Array.isArray(v) || typeof v === 'string' || (!!v && typeof v === 'object'),
  even: (v) => Number(v) % 2 === 0,
  odd: (v) => Math.abs(Number(v) % 2) === 1,
  divisibleby: (v, n) => Number(n) !== 0 && Number(v) % Number(n) === 0,
  truthy: (v) => !!v,
  falsy: (v) => !v,
  empty: (v) => v == null || (Array.isArray(v) ? v.length === 0 : typeof v === 'string' ? v === '' : Object.keys(v).length === 0),
  eq: (v, other) => v === other,
  ne: (v, other) => v !== other,
  lt: (v, other) => v < other,
  le: (v, other) => v <= other,
  gt: (v, other) => v > other,
  ge: (v, other) => v >= other,
  in: (v, seq) => toIterable(seq).includes(v),
  startingwith: (v, prefix) => String(v ?? '').startsWith(String(prefix)),
  endingwith: (v, suffix) => String(v ?? '').endsWith(String(suffix)),
  matching: (v, pattern) => matchesPattern(v, pattern),
};

const MAX_PATTERN = 200;
const MAX_MATCH_INPUT = 10000;
// A group that is itself repeated and contains a repetition: (a+)+, (a*)*
const NESTED_QUANTIFIER = /\((?:[^()\\]|\\.)*[+*](?:[^()\\]|\\.)*\)[+*{]/;

function matchesPattern(value, pattern) {
  const source = String(pattern ?? '');
  if (source.length > MAX_PATTERN) throw new TemplateError('"matching" pattern is too long');
  if (NESTED_QUANTIFIER.test(source)) throw new TemplateError('"matching" pattern has a nested repetition');
  let re;
  try { re = new RegExp(source); } catch { throw new TemplateError('"matching" pattern is not a valid expression'); }
  return re.test(String(value ?? '').slice(0, MAX_MATCH_INPUT));
}

function applyTest(name, value, args) {
  const test = Object.hasOwn(TESTS, name) ? TESTS[name] : undefined;
  if (!test) throw new TemplateError(`unknown test "${name}"`);
  return !!test(value, ...args);
}

/** Register an extra test. */
export function registerTest(name, fn) {
  if (typeof fn !== 'function') throw new TemplateError(`test "${name}" must be a function`);
  TESTS[name] = fn;
  return TESTS[name];
}

// --- small codecs (base64 of a *string*, not of field bytes) ---------------

function b64encodeText(str) {
  const bytes = typeof TextEncoder === 'undefined' ? Buffer.from(str, 'utf8') : new TextEncoder().encode(str);
  let binary = '';
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}

function b64decodeText(str) {
  // Lenient on whitespace, URL-safe alphabet and missing padding; strict otherwise.
  const clean = str.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  let binary;
  try {
    binary = atob(clean + '='.repeat((4 - (clean.length % 4)) % 4));
  } catch {
    throw new TemplateError('b64decode: input is not valid base64');
  }
  const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
  return typeof TextDecoder === 'undefined' ? Buffer.from(bytes).toString('utf8') : new TextDecoder('utf-8', { fatal: false }).decode(bytes);
}

function toDate(v) {
  if (v == null || v === '') return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v === 'number') return new Date(v < 1e11 ? v * 1000 : v);
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

const PAD = (n, width = 2) => String(n).padStart(width, '0');

function formatDate(value, format) {
  const d = toDate(value);
  if (!d) return '';
  const map = {
    YYYY: d.getUTCFullYear(),
    MM: PAD(d.getUTCMonth() + 1),
    DD: PAD(d.getUTCDate()),
    HH: PAD(d.getUTCHours()),
    mm: PAD(d.getUTCMinutes()),
    ss: PAD(d.getUTCSeconds()),
    SSS: PAD(d.getUTCMilliseconds(), 3),
  };
  return String(format).replace(/\[([^\]]*)\]|YYYY|MM|DD|HH|mm|ss|SSS/g, (m, literal) => (literal !== undefined ? literal : map[m]));
}

// --- evaluation -----------------------------------------------------------

/**
 * Property names that are never a template author's data.
 *
 * `{{ constructor }}` used to render `function Object() { [native code] }`,
 * because the name lookup was `node.name in scope` and `'constructor' in {}`
 * is true — the prototype chain answered a question about the automation's
 * variables. From there `constructor.constructor("…")()` is the standard
 * escape, and this engine renders webhook bodies for a multi-tenant product.
 *
 * Two changes close it: names resolve by OWN property only, and these keys
 * are refused on every attribute and subscript access regardless of the
 * object they are read from.
 */
const BLOCKED_PROPERTIES = new Set([
  '__proto__', 'constructor', 'prototype',
  '__defineGetter__', '__defineSetter__', '__lookupGetter__', '__lookupSetter__',
]);

function readProperty(obj, key, options) {
  if (BLOCKED_PROPERTIES.has(String(key))) {
    if (options.strict) throw new TemplateError(`access to "${key}" is not allowed`);
    return undefined;
  }
  return obj[key];
}

/**
 * Declared parameter names (after the piped value) per filter, so a keyword
 * argument lands in its positional slot: sort(attribute="n") is the third
 * extra argument. A name not listed here is an error, never silently dropped.
 */
const FILTER_PARAMS = {
  default: ['default_value', 'boolean'],
  d: ['default_value', 'boolean'],
  round: ['precision', 'method'],
  join: ['d', 'attribute'],
  sort: ['reverse', 'case_sensitive', 'attribute'],
  unique: ['attribute'],
  sum: ['attribute', 'start'],
  min: ['attribute'],
  max: ['attribute'],
  map: ['attribute'],
  select: ['test'],
  reject: ['test'],
  selectattr: ['attribute', 'test'],
  rejectattr: ['attribute', 'test'],
  batch: ['linecount', 'fill_with'],
  slice: ['slices', 'fill_with'],
  truncate: ['length', 'killwords', 'end'],
  indent: ['width', 'first'],
  center: ['width'],
  trim: ['chars'],
  replace: ['old', 'new'],
  int: ['default'],
  float: ['default'],
  tojson: ['indent'],
  json: ['indent'],
  datetimeformat: ['format'],
  date: ['format'],
  dictsort: ['reverse', 'by'],
};
const TEST_PARAMS = {
  divisibleby: ['num'],
  matching: ['pattern'],
  in: ['seq'],
};

function bindArguments(node, scope, options, params, kind) {
  const args = node.args.map((a) => evalNode(a, scope, options));
  const kwargs = node.args.kwargs;
  if (!kwargs) return args;
  const names = params || [];
  for (const [key, expr] of Object.entries(kwargs)) {
    const slot = names.indexOf(key);
    if (slot < 0) throw new TemplateError(`${kind} "${node.name}" has no argument "${key}"`);
    if (slot < node.args.length) throw new TemplateError(`${kind} "${node.name}" got "${key}" twice`);
    args[slot] = evalNode(expr, scope, options);
  }
  return args;
}

function evalNode(node, scope, options) {
  switch (node.type) {
    case 'const': return node.value;

    case 'name': {
      if (Object.hasOwn(scope, node.name)) return scope[node.name];
      if (options.strict) throw new TemplateError(`undefined variable "${node.name}"`);
      return undefined;
    }

    case 'attr': {
      const obj = evalNode(node.object, scope, options);
      if (obj == null) {
        if (options.strict) throw new TemplateError(`cannot read "${node.name}" of ${obj}`);
        return undefined;
      }
      return readProperty(obj, node.name, options);
    }

    case 'subscript': {
      const obj = evalNode(node.object, scope, options);
      const key = evalNode(node.index, scope, options);
      if (obj == null) return undefined;
      if (Array.isArray(obj) && typeof key === 'number' && key < 0) return obj[obj.length + key];
      return readProperty(obj, key, options);
    }

    case 'list': return node.items.map((n) => evalNode(n, scope, options));

    case 'dict': {
      const out = {};
      for (const [k, v] of node.entries) out[evalNode(k, scope, options)] = evalNode(v, scope, options);
      return out;
    }

    case 'filter': {
      const filter = Object.hasOwn(FILTERS, node.name) ? FILTERS[node.name] : undefined;
      if (typeof filter !== 'function') throw new TemplateError(`unknown filter "${node.name}"`);
      const args = bindArguments(node, scope, options, FILTER_PARAMS[node.name], 'filter');
      return filter(evalNode(node.operand, scope, options), ...args);
    }

    case 'test': {
      const args = bindArguments(node, scope, options, TEST_PARAMS[node.name], 'test');
      const result = applyTest(node.name, evalNode(node.operand, scope, options), args);
      return node.negate ? !result : result;
    }

    case 'call': {
      // Calls are permitted only on values that are already functions in the
      // context (a host-provided helper). There is no global object to reach,
      // so `{{ constructor.constructor("…")() }}` has nothing to resolve.
      const callee = evalNode(node.callee, scope, options);
      if (typeof callee !== 'function') throw new TemplateError('attempted to call a non-function');
      return callee(...node.args.map((a) => evalNode(a, scope, options)));
    }

    case 'not': return !truthy(evalNode(node.operand, scope, options));
    case 'neg': return -Number(evalNode(node.operand, scope, options));
    case 'and': { const l = evalNode(node.left, scope, options); return truthy(l) ? evalNode(node.right, scope, options) : l; }
    case 'or': { const l = evalNode(node.left, scope, options); return truthy(l) ? l : evalNode(node.right, scope, options); }

    case 'ternary':
      return truthy(evalNode(node.cond, scope, options))
        ? evalNode(node.then, scope, options)
        : evalNode(node.else, scope, options);

    case 'concat': {
      const l = evalNode(node.left, scope, options);
      const r = evalNode(node.right, scope, options);
      return `${l == null ? '' : l}${r == null ? '' : r}`;
    }

    case 'in': {
      const needle = evalNode(node.left, scope, options);
      const hay = evalNode(node.right, scope, options);
      const found = typeof hay === 'string'
        ? hay.includes(String(needle))
        : hay && typeof hay === 'object' && !Array.isArray(hay)
          ? Object.hasOwn(hay, needle)
          : toIterable(hay).includes(needle);
      return node.negate ? !found : found;
    }

    case 'compare': {
      const l = evalNode(node.left, scope, options);
      const r = evalNode(node.right, scope, options);
      switch (node.op) {
        case '==': return looseEqual(l, r);
        case '!=': return !looseEqual(l, r);
        case '<': return l < r;
        case '>': return l > r;
        case '<=': return l <= r;
        case '>=': return l >= r;
        default: throw new TemplateError(`unknown comparison "${node.op}"`);
      }
    }

    case 'binary': {
      const l = evalNode(node.left, scope, options);
      const r = evalNode(node.right, scope, options);
      switch (node.op) {
        // `+` concatenates when either side is a string, matching Jinja's
        // behaviour of raising on mixed types far less usefully.
        case '+': return typeof l === 'string' || typeof r === 'string'
          ? `${l == null ? '' : l}${r == null ? '' : r}`
          : Array.isArray(l) && Array.isArray(r) ? [...l, ...r] : Number(l) + Number(r);
        case '-': return Number(l) - Number(r);
        case '*': {
          if (typeof l !== 'string') return Number(l) * Number(r);
          const times = Math.max(0, Math.trunc(Number(r)) || 0);
          if (l.length * times > MAX_STRING) throw new TemplateError('string repetition is too large');
          return l.repeat(times);
        }
        case '/': return Number(r) === 0 ? null : Number(l) / Number(r);
        case '//': return Number(r) === 0 ? null : Math.floor(Number(l) / Number(r));
        case '%': return Number(r) === 0 ? null : Number(l) % Number(r);
        case '**': return Number(l) ** Number(r);
        default: throw new TemplateError(`unknown operator "${node.op}"`);
      }
    }

    default:
      throw new TemplateError(`unknown node type "${node.type}"`);
  }
}

function looseEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a == null && b == null;
  if (typeof a === 'object' || typeof b === 'object') return JSON.stringify(a) === JSON.stringify(b);
  // "5" == 5 is true in a template, because a form field is always a string
  // and an author comparing it to a number means the number.
  if (typeof a === 'number' || typeof b === 'number') return Number(a) === Number(b);
  return false;
}

function truthy(v) {
  if (Array.isArray(v)) return v.length > 0;
  if (v && typeof v === 'object') return Object.keys(v).length > 0;
  return !!v;
}

function stringify(v) {
  if (v === undefined || v === null) return '';
  if (typeof v === 'object') return jsonStable(v);
  return String(v);
}

function renderNodes(nodes, scope, options, out) {
  for (const node of nodes) {
    switch (node.type) {
      case 'text':
        spend(options, 'chars', node.value.length);
        out.push(node.value);
        break;

      case 'output': {
        const text = stringify(evalNode(node.expr, scope, options));
        spend(options, 'chars', text.length, node.line);
        out.push(text);
        break;
      }

      case 'set':
        scope[node.name] = evalNode(node.expr, scope, options);
        break;

      case 'if': {
        let done = false;
        for (const branch of node.branches) {
          if (truthy(evalNode(branch.cond, scope, options))) {
            renderNodes(branch.body, scope, options, out);
            done = true;
            break;
          }
        }
        if (!done) renderNodes(node.fallback, scope, options, out);
        break;
      }

      case 'for': {
        const seq = evalNode(node.seq, scope, options);
        // `for k, v in mapping` unpacks entries; a single name keeps iterating values.
        let list = node.names.length === 2 && seq && typeof seq === 'object' && !Array.isArray(seq)
          ? Object.entries(seq)
          : toIterable(seq);
        const bindNames = (target, item) => {
          if (node.names.length === 2 && Array.isArray(item)) {
            target[node.names[0]] = item[0];
            target[node.names[1]] = item[1];
          } else {
            target[node.names[0]] = item;
          }
          return target;
        };
        if (node.guard) {
          list = list.filter((item) => truthy(evalNode(node.guard, bindNames({ ...scope }, item), options)));
        }
        if (!list.length) { renderNodes(node.empty, scope, options, out); break; }
        if (list.length > options.loopCap) {
          throw new TemplateError(`loop exceeded ${options.loopCap} iterations`, node.line);
        }
        spend(options, 'iterations', list.length, node.line);
        for (let i = 0; i < list.length; i++) {
          const item = list[i];
          // Each iteration gets its own scope: the loop variable and any
          // `{% set %}` in the body must not leak over an outer variable.
          const inner = bindNames({ ...scope }, item);
          inner.loop = {
            index: i + 1,
            index0: i,
            revindex: list.length - i,
            revindex0: list.length - i - 1,
            first: i === 0,
            last: i === list.length - 1,
            length: list.length,
            previtem: i > 0 ? list[i - 1] : undefined,
            nextitem: i < list.length - 1 ? list[i + 1] : undefined,
          };
          renderNodes(node.body, inner, options, out);
        }
        break;
      }

      default:
        throw new TemplateError(`cannot render node "${node.type}"`);
    }
  }
  return out;
}

// --- public API -----------------------------------------------------------

export const DEFAULT_LOOP_CAP = 10000;

/** True when the string contains any Jinja construct worth rendering. */
export function isTemplate(value) {
  return typeof value === 'string' && /\{\{|\{%|\{#/.test(value);
}

/**
 * Compile a template once, render it many times.
 * @returns {{ render: (context, options) => string, nodes: object[] }}
 */
export function compileTemplate(source) {
  const nodes = parseTemplate(source);
  return {
    nodes,
    render(context = {}, options = {}) {
      const opts = { strict: false, loopCap: DEFAULT_LOOP_CAP, ...options };
      return renderNodes(nodes, { ...context }, opts, []).join('');
    },
  };
}

/** Render a template to a string. */
export function render(source, context = {}, options = {}) {
  if (!isTemplate(source)) return String(source ?? '');
  return compileTemplate(source).render(context, options);
}

/**
 * Render preserving the native type when the template is a single expression.
 *
 * `{{ items }}` yields the array, `{{ n }}` the number, `x{{ n }}` the string
 * "x42". This is what makes a config field able to carry a JSON body rather
 * than a JSON-shaped string.
 */
export function renderValue(source, context = {}, options = {}) {
  if (!isTemplate(source)) return source;
  const trimmed = String(source).trim();
  const nodes = parseTemplate(trimmed);
  if (nodes.length === 1 && nodes[0].type === 'output') {
    const opts = { strict: false, loopCap: DEFAULT_LOOP_CAP, ...options };
    return evalNode(nodes[0].expr, { ...context }, opts);
  }
  return render(source, context, options);
}

/**
 * Render every string inside a structure, in place-safe fashion.
 *
 * This is what "the fields that configure a step can also be Jinja templates"
 * means operationally: the workflow runtime hands a whole step config through
 * here before executing it, so authors template a URL, a header value, a
 * nested JSON body and an array element with one rule and no per-field
 * opt-in. Object KEYS are templated too — providers exist whose payload keys
 * are record ids.
 */
export function renderDeep(value, context = {}, options = {}) {
  if (typeof value === 'string') return renderValue(value, context, options);
  if (Array.isArray(value)) return value.map((v) => renderDeep(v, context, options));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      out[isTemplate(k) ? String(render(k, context, options)) : k] = renderDeep(v, context, options);
    }
    return out;
  }
  return value;
}

/**
 * Validate a template without running it, for save-time feedback.
 * @returns {{ ok: boolean, error?: string, line?: number, variables: string[] }}
 */
export function validateTemplate(source) {
  try {
    const nodes = parseTemplate(source);
    return { ok: true, variables: [...collectNames(nodes, new Set())].sort() };
  } catch (e) {
    return { ok: false, error: e.message, line: e.line, variables: [] };
  }
}

function collectNames(nodes, acc, bound = new Set()) {
  for (const node of nodes) {
    switch (node.type) {
      case 'output': walkExpr(node.expr, acc, bound); break;
      case 'set': walkExpr(node.expr, acc, bound); bound.add(node.name); break;
      case 'if':
        for (const b of node.branches) { walkExpr(b.cond, acc, bound); collectNames(b.body, acc, bound); }
        collectNames(node.fallback, acc, bound);
        break;
      case 'for': {
        walkExpr(node.seq, acc, bound);
        const inner = new Set([...bound, ...node.names, 'loop']);
        if (node.guard) walkExpr(node.guard, acc, inner);
        collectNames(node.body, acc, inner);
        collectNames(node.empty, acc, bound);
        break;
      }
      default: break;
    }
  }
  return acc;
}

function walkExpr(node, acc, bound) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'name' && !bound.has(node.name)) acc.add(node.name);
  if (node.type === 'filter' && !Object.hasOwn(FILTERS, node.name)) throw new TemplateError(`unknown filter "${node.name}"`);
  if (node.type === 'test' && !Object.hasOwn(TESTS, node.name)) throw new TemplateError(`unknown test "${node.name}"`);
  if (Array.isArray(node.args) && node.args.kwargs) for (const v of Object.values(node.args.kwargs)) walkExpr(v, acc, bound);
  for (const key of ['left', 'right', 'operand', 'cond', 'then', 'else', 'object', 'index', 'callee']) {
    if (node[key]) walkExpr(node[key], acc, bound);
  }
  for (const key of ['items', 'args']) {
    if (Array.isArray(node[key])) for (const child of node[key]) walkExpr(child, acc, bound);
  }
  if (Array.isArray(node.entries)) for (const [k, v] of node.entries) { walkExpr(k, acc, bound); walkExpr(v, acc, bound); }
}
