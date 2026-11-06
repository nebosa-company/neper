/**
 * The rule webhook door — an external system delivering AT a rule (LC30.24,
 * LC28 `TRIGGER_TYPES.webhook`).
 *
 * ## The defect this closes, said plainly
 *
 * `src/workflow/ir.js` has declared `webhook: { ingress: 'http' }` as a trigger
 * type since the IR was written, and **nothing served that ingress**. The
 * worker matches `schedule`, the three record actions, `metadata-change`,
 * `view-membership`, `form-submitted` and `inbound-email`, and nothing else. A
 * rule saved with `trigger_type: 'webhook'` could never fire. The one inbound
 * HTTP door that existed — `POST /inbound/<token>` — is TABLE-scoped: it maps a
 * payload onto a table's columns and inserts a ROW, which fires table-change
 * rules. There was no address an external system could deliver to that named a
 * RULE.
 *
 * That is why LC30.9 could not be scored: its premise, "a webhook-triggered
 * rule in listen-for-test mode", had no referent on this deployment. Building
 * the capture half alone would have produced a sample library with no source.
 *
 * ## The product questions, answered
 *
 * The previous verdict flagged five and decided none. They are decided here,
 * and the reasoning is in `docs/decisions/007-a-rule-has-an-address.md`:
 *
 *  - **URL scheme** — `{base}/api/hooks/{token}`, one opaque token per rule.
 *    The IR's `path` config is not honoured: an author-chosen path is a
 *    namespace to collide in and an enumerable surface, and it buys nothing a
 *    token does not.
 *  - **Auth** — the timestamped `t=…,v1=…` signature, always, verified by
 *    `verifyInboundSignature`. There is no token-only mode. The forms door has
 *    one and it is already deprecated and observably so; a new door starting
 *    where the old one is trying to end would be a second thing to migrate.
 *  - **Replay** — the shared `webhook_deliveries` ledger, keyed by the same
 *    deterministic uuid the other two doors use. A byte-identical replay
 *    collides on the primary key, and the collision IS the detection.
 *  - **Quota** — a delivery that RUNS enqueues a `workflow_requests` row, so it
 *    is metered by `beginWorkflow`'s existing quota gate rather than by a
 *    second accounting. A delivery that is CAPTURED runs nothing and consumes
 *    no run quota, which is the property that makes listen-for-test cheap
 *    enough to leave armed.
 *  - **Scope** — the rule, and through it the application. A hook cannot
 *    outlive its rule (the row cascades) and cannot name another one.
 *
 * ## What is NOT here
 *
 * No transport and no database. The route in `services/ai-proxy/server.mjs`
 * reads the body, verifies the signature with the SAME verifier the other two
 * doors use, claims the delivery id, and asks the functions below what to do
 * with it. Every judgement is here and asserted by
 * `tests/workflow/hook-ingress.test.js` without a server.
 */

/** The prefix a rule-hook token carries. A sibling of `cs_` and `ih_`. */
export const HOOK_PREFIX = 'wh_';

/**
 * How long listen-for-test stays armed, in milliseconds.
 *
 * Fifteen minutes, and short on purpose. An armed hook does not run the rule —
 * it swallows the delivery into the sample library — so an author who forgets
 * they armed it has quietly disabled their own automation. A window measured in
 * minutes turns that from an outage into a retry; the control re-arms in one
 * click, which is the right cost to pay for the property.
 */
export const LISTEN_WINDOW_MS = 15 * 60 * 1000;

/**
 * How many samples a rule keeps, and how long.
 *
 * LC30's own open question Q7 asks how long captured samples are retained, who
 * can see them, and whether they take part in export. Answered in ADR 007:
 * twenty per rule, thirty days, visible to whoever may edit the rule, and NOT
 * exported — a sample is real production data captured for a debugging session,
 * and a debugging convenience should not become a second copy of the record
 * corpus in every backup.
 */
export const SAMPLE_LIMIT = 20;
export const SAMPLE_RETENTION_DAYS = 30;

/** What a delivery caused. */
export const DELIVERY = {
  CAPTURED: 'captured',
  QUEUED: 'queued',
  DISABLED: 'disabled',
};

/**
 * Does this look like a rule-hook token at all?
 *
 * A SHAPE check and deliberately not a lookup, for the reason
 * `looksLikeStreamToken` records: it lets the route answer a malformed token
 * without touching the database, so a scanner spraying paths cannot make the
 * deployment do a query per request.
 *
 * @param {string} token
 * @returns {boolean}
 */
export function looksLikeHookToken(token) {
  const s = String(token || '');
  return s.startsWith(HOOK_PREFIX) && /^[a-z_0-9]+$/i.test(s) && s.length > HOOK_PREFIX.length + 16;
}

/**
 * The public URL an external system is told to POST to.
 *
 * @param {string} baseUrl
 * @param {string} token
 * @returns {string}
 */
export function hookUrl(baseUrl, token) {
  return `${String(baseUrl || '').replace(/\/+$/, '')}/api/hooks/${token}`;
}

/**
 * The moment listen-for-test should stop, as an ISO string.
 *
 * @param {number|Date} [now]
 * @returns {string}
 */
export function armListenUntil(now = Date.now()) {
  const ms = now instanceof Date ? now.getTime() : Number(now);
  return new Date(ms + LISTEN_WINDOW_MS).toISOString();
}

/**
 * Is this hook in listen-for-test mode right now?
 *
 * Expressed against the CLOCK rather than a boolean flag, so an armed hook
 * disarms itself. A flag would need something to clear it, and the something
 * would be a timer in a browser tab that may already be closed.
 *
 * @param {{listen_until?: string|null}} hook
 * @param {number|Date} [now]
 * @returns {boolean}
 */
export function isListening(hook, now = Date.now()) {
  const until = hook && hook.listen_until ? Date.parse(hook.listen_until) : NaN;
  if (!Number.isFinite(until)) return false;
  return until > (now instanceof Date ? now.getTime() : Number(now));
}

/**
 * Keys whose VALUES never belong in a stored sample (LC30.N5).
 *
 * Matched on the key, case-insensitively, at any depth. Matching on the value
 * — "does this look like a JWT" — was considered and rejected: it fails open
 * for every secret that does not look like one, and it fails closed for record
 * data that happens to be a long opaque string, which is exactly the data an
 * author captured a sample to look at.
 */
const SECRET_KEYS = /^(authorization|proxy-authorization|cookie|set-cookie|x-api-key|api[-_]?key|secret|client[-_]?secret|password|passwd|token|access[-_]?token|refresh[-_]?token|signature|x-signature|x-appdor-signature)$/i;

/** What a redacted value reads as. Not empty: the KEY was there, and that matters. */
export const REDACTED = '[redacted]';

/**
 * Scrub a payload before it is stored (LC30.N5).
 *
 * A captured sample is real traffic, and real traffic carries the credential
 * the sender authenticated with. Storing it would turn a debugging convenience
 * into a credential store that every rule editor can read.
 *
 * Depth-bounded, because a payload is attacker-supplied and a cyclic or
 * pathologically deep document must cost a bounded amount of work rather than a
 * stack. Beyond the bound the subtree is dropped rather than kept unscrubbed —
 * a sample that is missing a branch is a worse sample; one carrying an
 * unredacted secret is a worse deployment.
 *
 * @param {*} value
 * @param {number} [depth]
 * @returns {*}
 */
export function redactSample(value, depth = 0) {
  if (depth > 12) return null;
  if (Array.isArray(value)) return value.slice(0, 200).map((v) => redactSample(v, depth + 1));
  if (value && typeof value === 'object') {
    /** @type {Object.<string, *>} */
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      // Matched on the LEAF of the key, not the whole key. The regex is
      // anchored `^…$`, so it matches `token` and not `event.token` — and a
      // flat projection keyed by SOURCE PATH produces exactly the latter. That
      // shape is coming (the connector intake stores mapped paths rather than
      // the nested document), and against it an anchored leaf regex matches
      // nothing at all: the deny-list becomes the empty set silently, which is
      // the worst way for a redaction to fail.
      //
      // For a nested key with no separator in it, `split(...).pop()` is the key
      // itself, so this is identical to what it replaced on every payload shape
      // that reaches it today. `authorizations[0].token` resolves to `token`.
      const leaf = k.split(/[.[]/).pop();
      out[k] = SECRET_KEYS.test(leaf) ? REDACTED : redactSample(v, depth + 1);
    }
    return out;
  }
  return value;
}

/**
 * @typedef {object} DeliveryPlan
 * @property {string} outcome one of DELIVERY
 * @property {number} status the HTTP status the route should answer with
 * @property {object} [sample] the row to insert into the sample library
 * @property {object} [request] the `workflow_requests` row to enqueue
 * @property {string} [reason]
 */

/**
 * What to do with a delivery that has already been authenticated.
 *
 * Three outcomes and no fourth. A disabled hook answers 404 rather than 403,
 * for the reason the change-stream door records: distinguishing "no such hook"
 * from "that hook is off" hands an unauthenticated caller an existence oracle
 * over every token it can guess.
 *
 * `capture` does not run the rule. That is the whole of listen-for-test: the
 * author asked to SEE the next delivery, not to have it processed, and running
 * it as well would mean the first real delivery after arming fires the rule
 * with a payload the author has not looked at yet.
 *
 * @param {object} hook the `workflow_hooks` row
 * @param {*} payload the parsed delivery body
 * @param {{now?: number|Date, deliveryId?: string}} [opts]
 * @returns {DeliveryPlan}
 */
export function planDelivery(hook, payload, opts = {}) {
  const now = opts.now === undefined ? Date.now() : opts.now;
  const at = new Date(now instanceof Date ? now.getTime() : Number(now)).toISOString();
  if (!hook || hook.enabled === false) {
    return { outcome: DELIVERY.DISABLED, status: 404, reason: 'unknown-hook' };
  }
  if (isListening(hook, now)) {
    return {
      outcome: DELIVERY.CAPTURED,
      status: 202,
      sample: {
        workflow_id: hook.workflow_id,
        application_id: hook.application_id,
        name: sampleName(at),
        payload: redactSample(payload),
        source: 'capture',
        captured_at: at,
        created_by: hook.created_by,
      },
    };
  }
  return {
    outcome: DELIVERY.QUEUED,
    status: 202,
    request: {
      workflow_id: hook.workflow_id,
      table_id: hook.table_id,
      input: payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : { body: payload },
      origin: 'webhook',
      status: 'queued',
      requested_by: hook.created_by,
    },
  };
}

/**
 * The name a captured sample gets.
 *
 * Timestamped rather than numbered, because a sample library is read to answer
 * "the delivery that broke it at 14:02", and a counter cannot answer that. The
 * author renames it if it deserves a name.
 *
 * @param {string} iso
 * @returns {string}
 */
export function sampleName(iso) {
  return `Delivery ${String(iso).replace('T', ' ').slice(0, 19)}Z`;
}

/**
 * Which samples fall outside the retention policy, newest kept.
 *
 * Both limbs, because either alone leaks: a count with no age keeps a sample
 * from a year ago on a quiet rule, and an age with no count keeps ten thousand
 * from a busy afternoon.
 *
 * @param {Array<{id: string, captured_at: string}>} samples
 * @param {number|Date} [now]
 * @returns {string[]} ids to delete
 */
export function expiredSamples(samples, now = Date.now()) {
  const ms = now instanceof Date ? now.getTime() : Number(now);
  const cutoff = ms - SAMPLE_RETENTION_DAYS * 86400000;
  const sorted = [...(samples || [])]
    .filter((s) => s && s.id)
    .sort((a, b) => Date.parse(b.captured_at || 0) - Date.parse(a.captured_at || 0));
  return sorted
    .filter((s, i) => i >= SAMPLE_LIMIT || Date.parse(s.captured_at || 0) < cutoff)
    .map((s) => s.id);
}
