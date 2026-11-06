/**
 * Which approval a record gets (LC31.12).
 *
 * "Anything over £10,000 goes to the CFO, everything else goes to a manager"
 * is the first thing anybody asks of an approvals feature, and until now the
 * only answer this product had was "pick the approvers by hand every time".
 * The engine could not help: `startApproval` takes a definition, and nothing
 * chose one.
 *
 * An ORDERED list, evaluated first-match-wins, is the whole design. Order is
 * the only thing that makes a catch-all expressible, and it is the thing an
 * admin actually edits — moving rule 2 above rule 1 has to change which
 * definition the next instance uses, and that is what `matchApprovalRule`
 * guarantees by never sorting, scoring, or preferring the "most specific"
 * match. The list is read in the order it is stored.
 *
 * ## Every instance records which rule matched
 *
 * `routeApproval` stamps `matchedRule` into the definition it returns, and
 * `approval_runs.definition` is stored whole. So the answer to "why was the
 * CFO asked about this one" is on the row itself, and stays true after the
 * rules are reordered — which is exactly when the question gets asked.
 *
 * ## Quorum is refused rather than silently downgraded
 *
 * The runs these rules instantiate go through `newRunRow` → `startApproval`,
 * whose step evaluation implements `any` and `all` and nothing else. A rule
 * asking for `quorum(2 of 3)` would therefore have settled on ONE approval —
 * the same class of silent downgrade `normalizeStepRule` was written to stop
 * (`all-must-approve` behaving as first-response). So a quorum policy is a
 * named refusal here, not a rule that quietly means something weaker.
 *
 * Pure. The caller supplies the rules and the record's field values.
 */

import { normalizeStepRule } from './advanced.js';
import { simpleDefinition } from './runs-ui.js';

/**
 * @typedef {import('./runs-ui.js').ApprovalDefinition} ApprovalDefinition
 *
 * One rule, as the matcher reads it after `normalizeRoutingRules`.
 *
 * @typedef {Object} RoutingRule
 * @property {string} id
 * @property {string|null} name
 * @property {{field?: string, op?: string, value?: any}|null} when
 * @property {string[]} approvers
 * @property {string|{quorum: number}} policy
 * @property {string|null} escalateTo
 * @property {ApprovalDefinition|null} definition
 *
 * The two answers `routeApproval` can give. Named typedefs rather than an
 * inline union in the `@returns`: an inline one is not read as DISCRIMINATED,
 * so `if (routed.ok) return null` narrows nothing and every `routed.error`
 * below it is an error on a property the checker cannot see.
 *
 * @typedef {Object} RoutedOk
 * @property {true} ok
 * @property {ApprovalDefinition} definition
 * @property {{id: string, index: number, name: string|null}|null} matched
 *
 * @typedef {Object} RoutedRefusal
 * @property {false} ok
 * @property {string} error
 * @property {RoutingRule} [rule]
 *
 * @typedef {RoutedOk|RoutedRefusal} Routed
 */

/** The comparisons a rule may make. Everything else is a refusal. */
export const ROUTING_OPS = Object.freeze([
  'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains', 'in', 'empty', 'notEmpty',
]);

/** A dotted path into the record's values. */
function valueAt(record, field) {
  if (!record || !field) return undefined;
  return String(field).split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), record);
}

/**
 * Numbers when both sides are numbers, strings otherwise.
 *
 * `'12000' > '9000'` is false as strings, and an amount arriving as text out of
 * a jsonb column is the normal case rather than the exotic one — this is the
 * comparison the whole feature turns on.
 */
function compare(left, right) {
  const a = Number(left);
  const b = Number(right);
  if (left !== '' && right !== '' && left != null && right != null && !isNaN(a) && !isNaN(b)) {
    return a === b ? 0 : a < b ? -1 : 1;
  }
  const sa = String(left ?? '');
  const sb = String(right ?? '');
  return sa === sb ? 0 : sa < sb ? -1 : 1;
}

/**
 * Does one condition hold for this record?
 *
 * A rule with no condition is the catch-all and always holds — which is how a
 * list ends, and why the last rule needs no special vocabulary.
 */
/**
 * @param {{field?: string, op?: string, value?: any}|null|undefined} when
 * @param {Record<string, any>} record
 * @returns {boolean}
 */
export function conditionHolds(when, record) {
  if (!when) return true;
  const op = String(when.op || 'eq');
  const value = valueAt(record, when.field);
  switch (op) {
    case 'empty': return value == null || value === '' || (Array.isArray(value) && !value.length);
    case 'notEmpty': return !(value == null || value === '' || (Array.isArray(value) && !value.length));
    case 'eq': return compare(value, when.value) === 0;
    case 'neq': return compare(value, when.value) !== 0;
    case 'gt': return compare(value, when.value) > 0;
    case 'gte': return compare(value, when.value) >= 0;
    case 'lt': return compare(value, when.value) < 0;
    case 'lte': return compare(value, when.value) <= 0;
    case 'contains': return String(value ?? '').toLowerCase().includes(String(when.value ?? '').toLowerCase());
    case 'in': return (Array.isArray(when.value) ? when.value : []).some((v) => compare(value, v) === 0);
    // An operator nobody implemented must not read as "matches everything":
    // that would make a typo route every record to the first rule.
    default: return false;
  }
}

/**
 * The rules as the matcher reads them: in order, each with an id.
 *
 * Ids are positional only when the author supplied none. A rule that carries
 * its own id keeps it through a reorder, which is what lets an audit trail
 * naming `rule-cfo` still mean something afterwards.
 */
/**
 * @param {Array<Record<string, any>>|null|undefined} rules
 * @returns {RoutingRule[]}
 */
export function normalizeRoutingRules(rules) {
  return (Array.isArray(rules) ? rules : [])
    .filter((r) => r && typeof r === 'object')
    .map((r, i) => ({
      id: String(r.id || `rule-${i + 1}`),
      name: r.name || null,
      when: r.when || null,
      approvers: (r.approvers || []).map((a) => String(a || '').trim()).filter(Boolean),
      policy: r.policy || r.rule || 'any',
      escalateTo: r.escalateTo || null,
      definition: r.definition || null,
    }));
}

/**
 * The first rule that holds, with its position — or null when none does.
 *
 * @param {Array<Record<string, any>>|null|undefined} rules
 * @param {Record<string, any>} record the record's field values
 * @returns {{index: number, rule: RoutingRule}|null}
 */
export function matchApprovalRule(rules, record) {
  const ordered = normalizeRoutingRules(rules);
  for (let index = 0; index < ordered.length; index++) {
    if (conditionHolds(ordered[index].when, record)) return { index, rule: ordered[index] };
  }
  return null;
}

/**
 * The definition a record's approval should start from.
 *
 * @param {Array<Record<string, any>>|null|undefined} rules the ordered list
 * @param {Record<string, any>} record the record's field values
 * @param {ApprovalDefinition|null} [fallback] the definition to use when no rule holds
 * @returns {Routed}
 */
export function routeApproval(rules, record, fallback = null) {
  const match = matchApprovalRule(rules, record);
  if (!match) {
    if (!fallback) return { ok: false, error: 'no-rule-matched' };
    return { ok: true, definition: fallback, matched: null };
  }
  const { rule, index } = match;

  const policy = normalizeStepRule(rule.policy);
  if (policy && typeof policy === 'object' && policy.quorum) {
    return { ok: false, error: 'quorum-unsupported', rule };
  }
  if (policy !== 'any' && policy !== 'all') return { ok: false, error: 'unknown-policy', rule };

  const definition = rule.definition
    ? { ...rule.definition }
    : simpleDefinition(rule.approvers, policy);
  if (!rule.definition && !rule.approvers.length) return { ok: false, error: 'rule-asks-nobody', rule };

  // Stamped onto the definition the run keeps, so the row itself answers "why
  // these people" after the list has moved on.
  definition.matchedRule = { id: rule.id, index, name: rule.name || null };
  if (rule.escalateTo) definition.escalateTo = rule.escalateTo;
  return { ok: true, definition, matched: definition.matchedRule };
}

/**
 * What is wrong with one rule, or null when nothing is.
 *
 * Exists so the workflow validator does not have to know which refusal codes
 * are authoring mistakes and which are ordinary. `no-rule-matched` is the
 * ordinary one: it only means this rule's condition is false for an empty
 * record, which is exactly what a conditional rule should be. Everything else
 * — a quorum the chain engine cannot enforce, a rule that asks nobody — is a
 * definition that will misroute an approval, and the person writing it should
 * hear about it at SAVE rather than at audit.
 *
 * @param {Record<string, any>} rule
 * @returns {string|null}
 */
export function routingRuleProblem(rule) {
  // Read through the two fields this function actually uses. The union IS
  // discriminated, but the checker runs with `strict: false` (see the header of
  // tsconfig.json on why that is a gate rather than a migration), and without
  // strictNullChecks it does not narrow `Routed` on `routed.ok`. Widening the
  // declared return type to make the narrowing unnecessary would be the worse
  // trade: every OTHER caller would lose the discrimination to spare this one
  // a cast.
  const routed = /** @type {{ok: boolean, error?: string}} */ (routeApproval([rule], {}, null));
  if (routed.ok || routed.error === 'no-rule-matched') return null;
  return routed.error;
}
