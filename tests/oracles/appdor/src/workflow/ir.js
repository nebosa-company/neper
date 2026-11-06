/**
 * Workflow IR — the serializable definition a durable run executes.
 * (LC29 / condition-action-catalog — `STEP_TYPES` below is the step-type
 * registry; the IR shape itself belongs to LC27, which is tagged elsewhere.)
 *
 * This exists because the synchronous interpreter refused to fake durable
 * waits. Its header said so — *"there is deliberately no `delay` step: durable
 * waits need host-side scheduling that does not exist"* — and that scheduling
 * now exists, so this is the definition format that can express what it was
 * refusing to pretend about: delays, human approval gates, and parallel
 * branches, while staying a plain JSON document that survives
 * `JSON.parse(JSON.stringify(x))` unchanged.
 *
 * 🔴 That sentence used to cite `automations/engine.js`, which **no longer
 * exists** — `52-automations-become-workflows.sql` renamed the subsystem and
 * the module became `src/workflow/flow-engine.js`. A reader following the
 * citation found nothing, and a citation nobody can follow is indistinguishable
 * from one that was never checked.
 *
 * The refusal itself has since been RE-SCOPED rather than lifted, and correctly:
 * `flow-engine.js` still declines a `delay` step, but for a reason that is
 * current instead of expired. It is the inline, synchronous half — transition
 * post-functions execute inside a transaction the caller already holds — and a
 * post-function that started a durable run would commit the record to its new
 * state with the assignment still pending. Durable waits are this engine's job.
 * The expired reason was "the scheduling does not exist"; the live one is
 * "waits belong to the other engine", and they are different sentences.
 *
 * ## Everything is a template
 *
 * Any config field may be a Jinja template, evaluated against the run context
 * immediately before the step executes (`src/template/jinja.js#renderDeep`).
 * That is one rule, not a per-field opt-in: a URL, a header value, a nested
 * JSON body, an array element and an object KEY all template the same way.
 * The `templated: false` flag exists for the handful of fields where a
 * template would be nonsense — a cron expression, a step id, a branch target —
 * because rendering those silently turns a typo into a different destination.
 *
 * ## Why step ids are mandatory and stable
 *
 * A durable run is replayed from its journal after a restart, and a journal
 * entry is matched to a step by id. Auto-generated positional ids would mean
 * that inserting a step above a completed one re-points its recorded result at
 * a different step — the run would resume having "already done" something it
 * never did. So ids are required, validated unique, and `validateWorkflow`
 * refuses a definition without them.
 */

import { t } from '../language.js';
// The routing matcher is the one thing that knows what a rule may say
// (LC31.12), so the validator asks IT rather than restating the vocabulary —
// a second copy of "which policies are allowed" is how a definition that saves
// cleanly comes to be refused at run time.
import { routingRuleProblem } from '../approvals/routing.js';
import { PLATFORM_EVENT_TYPE_PATTERN } from './event-bus.js';
import { normalizeSchedule, parseCron, isKnownTimeZone } from './schedule.js';

// --- step catalog ---------------------------------------------------------

/**
 * Every step type, with the properties the runtime and the builder both read.
 *
 *  - `kind`       control | data | effect — effects are what a dry run withholds
 *  - `suspends`   can this step park the run and wait for the outside world
 *  - `mutates`    does a successful execution change something a user can see
 *  - `body`       names of child-step arrays, so validation and key derivation
 *                 can walk the tree without special-casing each type
 *  - `raw`        config fields NOT to render as templates
 *  - `output`     WHAT this step leaves behind in `steps.<id>`, as a type name
 *
 * `output` is the newest of the five and the one with a reason worth stating.
 * LC30.23 asks a per-step test to show "typed output", and until this key
 * existed the only typed-output notion in the codebase was the AI step's own
 * `outputType` config field — a per-step author choice, not a property of the
 * step type. So a preview had two ways to answer "what comes back": guess from
 * the handler's return value (which a preview does not have, because it does not
 * run the handler) or keep a second table somewhere else, free to drift from
 * this one. It is declared HERE so there is one list of step types with one
 * list of facts about each. `OUTPUT_TYPES` names the vocabulary.
 */
/**
 * The vocabulary `STEP_TYPES[*].output` draws on.
 *
 * Names, not prose. A description reads better in a panel and would be nine
 * English sentences living in a module the i18n gate scans — untranslated text
 * in thirty-six locales, which is exactly what that gate exists to stop. The
 * builder already shows a step's raw `type` on its card (`webhook`, `set`,
 * `foreach`), so the raw output name is the vocabulary a reader of this screen
 * is already fluent in.
 *
 * Deliberately coarse either way. This is what a builder is TOLD comes back,
 * not a schema an engine validates against — "records" is the useful answer to
 * "what can I bind to downstream", and a full JSON Schema per step type would
 * be a second, heavier promise that nothing currently checks.
 */
export const OUTPUT_TYPES = Object.freeze([
  'none',
  'value',
  'text',
  'record',
  'records',
  'response',
  'result',
  'receipt',
  'run',
  'approval',
]);

export const STEP_TYPES = {
  // --- control flow
  if: { kind: 'control', suspends: false, mutates: false, body: ['then', 'else'], raw: [], output: 'none' },
  case: { kind: 'control', suspends: false, mutates: false, body: ['cases.steps', 'default'], raw: [], output: 'none' },
  foreach: { kind: 'control', suspends: false, mutates: false, body: ['steps'], raw: ['as'], output: 'none' },
  fork: { kind: 'control', suspends: true, mutates: false, body: ['branches.steps'], raw: ['join', 'branches.name'], output: 'none' },
  'try': { kind: 'control', suspends: false, mutates: false, body: ['steps', 'catch'], raw: [], output: 'none' },
  stop: { kind: 'control', suspends: false, mutates: false, body: [], raw: [], output: 'none' },
  fail: { kind: 'control', suspends: false, mutates: false, body: [], raw: [], output: 'none' },

  // --- waiting
  delay: { kind: 'control', suspends: true, mutates: false, body: [], raw: [], output: 'none' },
  'wait-signal': { kind: 'control', suspends: true, mutates: false, body: [], raw: ['signal', 'timeoutAction'], output: 'value' },
  // An `effect`, not a `control`, even though what it mostly does is wait: it
  // creates an `approval_runs` row and notifies people, and both are visible
  // outside this process. Declaring it `control` would exempt it from the
  // dry-run gate, so a preview would file real approvals and page real people.
  // `approvers` is NOT raw on purpose — a hand-written definition may name one
  // as `{{ triggerMeta.changedBy }}`, and the members picker only ever emits
  // literal ids, which render to themselves.
  // `routing` and `callbackSecret` ARE raw (LC31.12, LC31.10). The routing list
  // is a structure the matcher walks, not prose, and rendering it as a template
  // would stringify the conditions it is made of. The secret is raw for the
  // reason `mcpTool` gives about its own: a signing key chosen at execution
  // time is a signing key the builder never approved.
  approval: {
    kind: 'effect', suspends: true, mutates: true, body: [], output: 'approval',
    raw: ['rule', 'timeoutAction', 'table', 'routing', 'callbackSecret', 'evidenceFields'],
  },

  // --- data
  set: { kind: 'data', suspends: false, mutates: false, body: [], raw: ['name'], output: 'value' },
  transform: { kind: 'data', suspends: false, mutates: false, body: [], raw: ['pipeline.op'], output: 'value' },
  parse: { kind: 'data', suspends: false, mutates: false, body: [], raw: ['format'], output: 'value' },
  serialize: { kind: 'data', suspends: false, mutates: false, body: [], raw: ['format'], output: 'text' },
  query: { kind: 'data', suspends: false, mutates: false, body: [], raw: ['table'], output: 'records' },

  // --- effects
  webhook: { kind: 'effect', suspends: false, mutates: true, body: [], raw: [], output: 'response' },
  // The destination and schema version are author-approved catalog choices,
  // never values a run may redirect with a template. Payload and subject stay
  // templated so an emitted event can carry the record that caused it.
  'emit-event': {
    kind: 'effect', suspends: false, mutates: true, body: [],
    raw: ['eventType', 'schemaVersion', 'retainDays'], output: 'record',
  },
  connector: { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['channel', 'action', 'connectionId'], output: 'result' },
  // Calling a tool on an external MCP server (LC37.6). `connectionId` and
  // `tool` are RAW — never templated — because both are the subject of an
  // approval: the connection was allowlisted for that specific tool, and a
  // template would let a run choose at execution time what a builder approved
  // at design time. Only the ARGUMENTS may be templates.
  mcpTool: { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['connectionId', 'tool'], output: 'result' },
  'create-record': { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['table'], output: 'record' },
  'update-record': { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['table'], output: 'record' },
  'delete-record': { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['table'], output: 'none' },
  // Lot traceability (src/traceability/lot-steps.js). `fields` and `tables`
  // are column and table maps, never templates.
  'lot-receipt': { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['fields', 'tables'], output: 'record' },
  'lot-disposition': { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['fields', 'tables'], output: 'record' },
  email: { kind: 'effect', suspends: false, mutates: true, body: [], raw: [], output: 'receipt' },
  notify: { kind: 'effect', suspends: false, mutates: true, body: [], raw: [], output: 'receipt' },
  python: { kind: 'effect', suspends: false, mutates: true, body: [], raw: ['source', 'requirements'], output: 'value' },
  'run-workflow': { kind: 'effect', suspends: true, mutates: true, body: [], raw: ['workflowId', 'mode'], output: 'run' },
  log: { kind: 'data', suspends: false, mutates: false, body: [], raw: [], output: 'none' },
};

/**
 * Step types contributed by installed apps (LC39.2).
 *
 * Registered into a map the VALIDATOR consults, which is the whole point:
 * `validateWorkflow` rejects an unknown step type, so a workflow using an
 * extension step would have failed validation while the palette happily offered
 * it. A type that only the palette knows about is a type the engine denies.
 *
 * Every registered step is `mutates: true` and `runnable: false`. The first
 * because it runs vendor code and the dry-run gate must assume it changes
 * something; the second because no runtime executes one yet, and a step the
 * runtime cannot run must fail at the point it is reached rather than be
 * treated as a no-op success.
 */
const pluginSteps = new Map();

export function registerPluginStepType(namespace, id, definition = {}) {
  if (!namespace || !id) return { ok: false, error: 'namespace-and-id-required' };
  const key = `${namespace}.${id}`;
  if (STEP_TYPES[id]) return { ok: false, error: `collides-with-core:${id}` };
  pluginSteps.set(key, {
    kind: 'effect',
    suspends: false,
    mutates: true,
    body: [],
    raw: [],
    installed: true,
    runnable: false,
    label: definition.label || id,
    provenance: definition.provenance || null,
  });
  return { ok: true, key };
}

export function unregisterPluginStepType(key) {
  return { ok: pluginSteps.delete(key) };
}

export function listPluginStepTypes() {
  return [...pluginSteps.entries()].map(([key, meta]) => ({ type: key, ...meta }));
}

/**
 * Resolve a step type — core first, then installed apps.
 *
 * The one accessor every consumer should use. `STEP_TYPES[type]` is still
 * exported and still correct for the built-ins; what it cannot do is see an
 * installed one, which is why the validator below now asks this instead.
 */
export function stepType(type) {
  return STEP_TYPES[type] || pluginSteps.get(type) || null;
}

/** Every trigger type that can start a run. */
export const TRIGGER_TYPES = {
  // The user's model: a table change and a dashboard button both ARRIVE as
  // webhooks. They are separate types anyway, because the builder must show
  // different config and the payload schemas differ — but they share one
  // ingress path, so there is exactly one place that authenticates and
  // deduplicates inbound events.
  webhook: { ingress: 'http', config: ['path', 'auth', 'secret', 'dedupeKey'], output: 'response' },
  // `excludeOrigins` is LC12.13: the origins this rule was scoped NOT to hear,
  // read by `originScopeDecision` in `workflow/event-stream.js` before the rule
  // is admitted. It can only subtract — a name here refuses a change the
  // platform would have delivered, and no value in it makes a rule hear a
  // change the platform suppressed.
  'table-change': { ingress: 'http', config: ['table', 'events', 'watchFields', 'filter', 'excludeOrigins'] },
  // The builder's own objects changing, rather than a table's rows: a page
  // added, renamed, removed. Scoped to an APPLICATION, not a table, because a
  // page belongs to one and to no table — which is why `workflows.table_id`
  // stopped being NOT NULL in 85-metadata-changes.sql.
  //
  // A separate type from `table-change` even though both arrive as changes on a
  // queue. They subscribe on different scopes, their payloads share no field
  // beyond `action`, and collapsing them would make "when a record changes"
  // silently match page edits for anyone who left the object filter blank.
  'metadata-change': { ingress: 'http', config: ['objects', 'events'] },
  // Durable cross-app bus subscription. `filter` is evaluated before a run is
  // created; version is explicit so a schema upgrade never widens an existing
  // rule in place.
  'platform-event': { ingress: 'event-bus', config: ['eventType', 'schemaVersion', 'filter'] },
  // Membership of a SAVED view, as an event (LC28.5). Not a filter on
  // `table-change`, and the distinction is the whole trigger: a filtered
  // table-change fires when a matching record changes, this fires when a record
  // CROSSES the boundary — the interesting moment is the one where the filter's
  // answer changed, which a per-change filter cannot see because it only ever
  // evaluates the after-snapshot.
  //
  // `viewId` names a shared saved view, never an ad-hoc one. See
  // `view-membership.js` for why that is a property of the module rather than a
  // convention at the call site.
  'view-membership': { ingress: 'http', config: ['viewId', 'events'] },
  // A form submission, which is NOT the insert it produces (LC28.6). The row
  // lands in the same table a direct API insert lands in, so an `insert` rule
  // cannot tell the two apart — and the difference matters, because a form
  // submission carries a form, a version, a submitter class and the answers as
  // given, none of which an API insert has. A rule that wants "when somebody
  // fills in the intake form" must not also fire for the nightly import.
  'form-submitted': { ingress: 'http', config: ['formId', 'submitterClass'] },
  // Mail arriving at an address this workspace owns (LC28.11). Its own ingress
  // rather than a `webhook` with a mail-shaped body: the replay identity is the
  // RFC 2822 Message-ID rather than a signature, a redelivery must be
  // ACKNOWLEDGED rather than refused — a provider retries anything that is not
  // 2xx — and a reply has to be tied to the thread it answers.
  'inbound-email': { ingress: 'http', config: ['mailbox', 'events'] },
  button: { ingress: 'http', config: ['label', 'surface', 'confirm', 'inputs'] },
  schedule: { ingress: 'timer', config: ['cron', 'timezone', 'catchUp'] },
  manual: { ingress: 'manual', config: ['inputs'] },
  'workflow-call': { ingress: 'internal', config: ['inputs'] },
};

/**
 * The builder objects that emit metadata events.
 *
 * One entry, and the list exists anyway: it is what `metadata-change`
 * validates against, so adding `view` here and a `create trigger` in SQL is the
 * whole of adding a second object. A rule may NOT leave the list blank to mean
 * "everything" — a blank filter would quietly widen to match objects that did
 * not exist when it was written, and a rule that grows new triggers on its own
 * is not something an author can reason about.
 */
export const METADATA_OBJECTS = ['page'];

/** The actions a metadata object reports, matching `metadata_changes.action`. */
export const METADATA_EVENTS = ['insert', 'update', 'delete', 'restore'];

/**
 * The two states of a run that never started, and why they are two.
 *
 * `suppressed` — delivery refused the change before a run existed (LC5.8):
 * loop prevention, a mirrored write, a batch already folded.
 * `skipped-quota` — the run WOULD have happened and the monthly allowance
 * stopped it (LC56.2, LC33). One is the product working correctly on the data;
 * the other is the plan. An admin filtering for "what did my migration
 * suppress last night" must not find their quota refusals mixed in.
 *
 * Deliberately NOT in TERMINAL_STATUSES — those are the states a run reaches by
 * EXECUTING, and the sweepers and journal replay reason about runs that ran.
 * There is no journal to replay for a run that never began.
 */
export const NEVER_STARTED_STATUSES = ['suppressed', 'skipped-quota'];

export const RUN_STATUSES = ['pending', 'running', 'suspended', 'paused', 'succeeded', 'failed', 'cancelled', ...NEVER_STARTED_STATUSES];

/** Statuses from which no further transition happens. */
export const TERMINAL_STATUSES = ['succeeded', 'failed', 'cancelled'];

// --- normalization --------------------------------------------------------

/**
 * Fill in defaults without inventing ids.
 *
 * Normalizing is separate from validating because the builder normalizes on
 * every keystroke and validates on save. A normalize that threw would make the
 * builder unusable while a definition is half-typed.
 */
export function normalizeWorkflow(definition = {}) {
  return {
    id: definition.id || null,
    // Resolved at call time, in the author's language — the fallback name is
    // DATA once saved, exactly like a name they typed. Serialization always
    // stores the filled-in name, so the worker's deserialize path never
    // reaches this branch in practice; when it does, `t()` under plain Node
    // answers in the source locale, which is what an ownerless string gets.
    name: definition.name || t('workflow.untitled'),
    version: definition.version ?? 1,
    enabled: definition.enabled !== false,
    trigger: normalizeTrigger(definition.trigger),
    steps: (definition.steps || []).map(normalizeStep),
    inputs: definition.inputs || {},
    settings: {
      maxSteps: 10000,
      maxDurationMs: 7 * 24 * 60 * 60 * 1000,
      onFailure: 'stop',
      concurrency: 'parallel',
      retryPolicy: { attempts: 3, backoffMs: 1000, multiplier: 2, maxBackoffMs: 60000 },
      ...(definition.settings || {}),
    },
  };
}

function normalizeTrigger(trigger) {
  if (!trigger) return { type: 'manual', config: {} };
  return { type: trigger.type || 'manual', config: trigger.config || {}, filter: trigger.filter || null };
}

function normalizeStep(step) {
  const out = { id: step.id, type: step.type, name: step.name || step.id, config: step.config || {} };
  if (step.retries !== undefined) out.retries = step.retries;
  if (step.continueOnError !== undefined) out.continueOnError = step.continueOnError;
  if (step.if !== undefined) out.if = step.if;

  for (const key of ['then', 'else', 'steps', 'catch', 'default']) {
    if (Array.isArray(step[key])) out[key] = step[key].map(normalizeStep);
  }
  if (Array.isArray(step.cases)) {
    out.cases = step.cases.map((c) => ({ when: c.when, name: c.name, steps: (c.steps || []).map(normalizeStep) }));
  }
  if (Array.isArray(step.branches)) {
    out.branches = step.branches.map((b) => ({ name: b.name, steps: (b.steps || []).map(normalizeStep) }));
  }
  return out;
}

// --- traversal ------------------------------------------------------------

/** Yield every step in a definition, depth-first, with its parent chain. */
export function walkSteps(steps, visit, path = []) {
  for (const step of steps || []) {
    visit(step, path);
    const childPath = [...path, step.id];
    for (const key of ['then', 'else', 'steps', 'catch', 'default']) {
      if (Array.isArray(step[key])) walkSteps(step[key], visit, childPath);
    }
    for (const group of [...(step.cases || []), ...(step.branches || [])]) {
      walkSteps(group.steps, visit, childPath);
    }
  }
}

/** Flat list of every step id in a definition. */
export function collectStepIds(definition) {
  const ids = [];
  walkSteps(definition.steps, (step) => ids.push(step.id));
  return ids;
}

// --- validation -----------------------------------------------------------

/**
 * What a user id looks like, for the one field that is compared against
 * `auth.uid()` by row-level security rather than merely stored.
 */
const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Validate a definition for save.
 * @returns {{ ok: boolean, errors: Array<{path: string, message: string}> }}
 */
/**
 * True when a record step's `values` carries at least one mapping.
 *
 * The stored shape is an object (`{ Field: '{{ trigger.x }}' }` — the form's
 * key/value rows convert to that); older definitions may hold an array of
 * rows. Either shape with nothing in it is the defect `recordStepNeedsValues`
 * names.
 */
function recordStepHasValues(config) {
  const values = config && config.values;
  if (Array.isArray(values)) return values.some((r) => r && (r.key || r.value));
  if (values && typeof values === 'object') return Object.keys(values).length > 0;
  return false;
}

export function validateWorkflow(definition) {
  const errors = [];
  const push = (path, message) => errors.push({ path, message });

  if (!definition || typeof definition !== 'object') {
    return { ok: false, errors: [{ path: '', message: t('workflow.validate.notObject') }] };
  }
  // A reused key — the io mapping validator already says exactly this
  // sentence in all 36 locales.
  if (!definition.name) push('name', t('io.mapping.name.required'));

  const trigger = definition.trigger;
  if (!trigger || !trigger.type) push('trigger', t('workflow.validate.triggerRequired'));
  else if (!TRIGGER_TYPES[trigger.type]) push('trigger.type', t('workflow.validate.unknownTrigger', null, { type: trigger.type }));
  else if (trigger.type === 'schedule') {
    const config = trigger.config || {};
    if (!config.cron) push('trigger.config.cron', t('workflow.validate.scheduleNeedsCron'));
    else {
      const schedule = normalizeSchedule({ cron: config.cron, timezone: config.timezone,
        onMissed: config.catchUp === 'one' ? 'one-catch-up' : config.catchUp });
      if (schedule.error) {
        const field = !isKnownTimeZone(config.timezone) ? 'timezone' : !parseCron(config.cron) ? 'cron' : 'catchUp';
        push(`trigger.config.${field}`, schedule.error);
      }
    }
  } else if (trigger.type === 'metadata-change') {
    const config = trigger.config || {};
    const objects = config.objects;
    if (!Array.isArray(objects) || !objects.length) {
      push('trigger.config.objects', t('workflow.validate.objectsRequired'));
    } else {
      for (const object of objects) {
        if (!METADATA_OBJECTS.includes(object)) push('trigger.config.objects', t('workflow.validate.nothingEmits', null, { object }));
      }
    }
    // Blank `events` means every action, the same default `table-change` uses.
    // A NAMED action that does not exist is a different thing: it is a rule
    // that will never fire, and saying so at save is the only chance to.
    for (const event of config.events || []) {
      if (!METADATA_EVENTS.includes(event)) push('trigger.config.events', t('workflow.validate.unknownEvent', null, { event }));
    }
  } else if (trigger.type === 'platform-event') {
    const config = trigger.config || {};
    if (!config.eventType) push('trigger.config.eventType', t('workflow.field.required', null, { field: t('webhooks.template.var.type') }));
    else if (!PLATFORM_EVENT_TYPE_PATTERN.test(String(config.eventType))) {
      push('trigger.config.eventType', t('io.mapping.name.invalidChars'));
    }
    if (!Number.isInteger(Number(config.schemaVersion)) || Number(config.schemaVersion) < 1) {
      push('trigger.config.schemaVersion', t('workflow.field.min', null, { field: t('webhooks.template.var.schemaVersion'), min: 1 }));
    }
  }

  if (!Array.isArray(definition.steps) || definition.steps.length === 0) {
    push('steps', t('workflow.validate.stepRequired'));
  }

  const seen = new Map();
  walkSteps(definition.steps, (step, path) => {
    const where = [...path, step.id || '?'].join('.');
    // Validation reports EVERY problem, so a missing id does not stop the
    // config checks below. Returning early here meant an author fixed the id,
    // saved, and was told about the missing url on the next round trip — one
    // problem per save, which is how a form earns its reputation.
    if (!step.id) push(where, t('workflow.validate.stepNeedsId'));
    else {
      if (!/^[A-Za-z0-9_-]+$/.test(step.id)) push(where, t('workflow.validate.stepIdCharset', null, { id: step.id }));
      if (seen.has(step.id)) push(where, t('workflow.validate.duplicateStepId', null, { id: step.id, first: seen.get(step.id) }));
      seen.set(step.id, where || step.id);
    }

    // `stepType`, not `STEP_TYPES[...]`: an installed app's step is a real step
    // type, and validating against the built-in map alone rejected every
    // workflow that used one — while the palette offered it.
    const meta = stepType(step.type);
    if (!meta) { push(where, t('workflow.validate.unknownStepType', null, { type: step.type })); return; }

    const config = step.config || {};
    switch (step.type) {
      case 'if':
        if (!config.condition) push(`${where}.config.condition`, t('workflow.validate.ifNeedsCondition'));
        break;
      case 'case':
        if (!Array.isArray(step.cases) || !step.cases.length) push(`${where}.cases`, t('workflow.validate.caseNeedsCase'));
        // The path is assembled from single-token pieces so the audit, which
        // reads a whole template literal as one candidate, does not mistake a
        // dotted address for prose. Same string either way.
        else step.cases.forEach((c, i) => { if (!c.when) push(where + '.cases[' + i + '].when', t('workflow.validate.caseNeedsWhen')); });
        break;
      case 'foreach':
        if (!config.items) push(`${where}.config.items`, t('workflow.validate.foreachNeedsItems'));
        break;
      case 'fork':
        if (!Array.isArray(step.branches) || step.branches.length < 2) {
          push(`${where}.branches`, t('workflow.validate.forkNeedsBranches'));
        }
        if (config.join && !['all', 'any', 'race'].includes(config.join)) {
          push(`${where}.config.join`, t('workflow.validate.forkJoinValues'));
        }
        break;
      case 'delay':
        if (config.ms === undefined && !config.until && !config.duration) {
          push(`${where}.config`, t('workflow.validate.delayNeedsWhen'));
        }
        break;
      case 'wait-signal':
        if (!config.signal) push(`${where}.config.signal`, t('workflow.validate.waitSignalNeedsName'));
        break;
      case 'approval': {
        // No signal field: the name is derived from the execution key, so two
        // approval steps — or two iterations of one inside a loop — cannot
        // collide on a signal an author typed twice.
        const approvers = config.approvers;
        if (config.evidenceFields !== undefined && (!Array.isArray(config.evidenceFields)
            || !config.evidenceFields.length || config.evidenceFields.length > 32
            || config.evidenceFields.some((id) => !UUID_SHAPE.test(String(id)))
            || new Set(config.evidenceFields).size !== config.evidenceFields.length)) {
          push(`${where}.config.evidenceFields`, t('approvals.evidence.selectFields', null, { minFields: 1, maxFields: 32 }));
        }
        if (!Array.isArray(approvers) || !approvers.filter(Boolean).length) {
          push(`${where}.config.approvers`, t('workflow.validate.approvalNeedsApprover'));
        }
        // Refused at save, not survived at run time. `approval_runs.current_approvers`
        // is a uuid array and the RLS predicate compares it with the caller's
        // id, so anything that is not a user id can never match anybody.
        // Measured on the live database: array['undefined']::uuid[] raises
        // 22P02, so the step throws when it files rather than waiting on a
        // person who cannot exist — but a validator that refuses the value is
        // worth more than a worker that survives it. The literal "undefined"
        // is what a picker built from an unloaded roster stores, and it did.
        for (const approver of Array.isArray(approvers) ? approvers : []) {
          if (!UUID_SHAPE.test(String(approver == null ? '' : approver).trim())) {
            push(`${where}.config.approvers`, t('workflow.validate.approverNotUser', null, { value: String(approver) }));
          }
        }
        // Refused HERE rather than discovered as a run that suspends and is
        // never woken: `approval_runs.row_id` and `table_id` are both NOT NULL,
        // so a schedule-, webhook- or manual-triggered workflow has no record
        // to attach an approval to unless it names one.
        if (!config.table) push(`${where}.config.table`, t('workflow.validate.approvalNeedsTable'));
        if (!config.record) {
          push(`${where}.config.record`, t('workflow.validate.approvalNeedsRecord'));
        }
        if (config.rule !== undefined && !['any', 'all'].includes(config.rule)) {
          push(`${where}.config.rule`, t('workflow.validate.approvalRuleValues'));
        }
        // The ordered routing list (LC31.12). Refused at SAVE for the same
        // reason the approver ids are: a rule that asks nobody, or one asking
        // for a quorum the chain engine cannot enforce, produces an approval
        // that is wrong in a way nobody notices until an audit — and by then
        // the wrong people have already signed off.
        if (config.routing !== undefined && config.routing !== null && config.routing !== '') {
          if (!Array.isArray(config.routing)) {
            // Keyed, like `workflow.validate.approverNotUser` above and unlike
            // the older English literals around it: this message is read by a
            // builder in whatever language they set the product to.
            push(`${where}.config.routing`, t('workflow.validate.routingNotList'));
          } else {
            config.routing.forEach((rule, i) => {
              // Asked of the matcher rather than decided here: which refusals
              // are authoring mistakes and which are ordinary belongs to the
              // module that owns the vocabulary.
              const problem = routingRuleProblem(rule);
              if (problem) {
                push(
                  `${where}.config.routing[${i}]`,
                  // The refusal travels as a CODE inside the sentence rather
                  // than as thirty-six translations of "quorum-unsupported".
                  // It names a shape the author wrote, not a state they are in.
                  t('workflow.validate.routingRuleUnusable', null, { n: i + 1, error: problem }),
                );
              }
            });
          }
        }
        break;
      }
      case 'webhook':
        if (!config.url) push(`${where}.config.url`, t('workflow.validate.webhookNeedsUrl'));
        break;
      case 'emit-event':
        if (!config.eventType) push(`${where}.config.eventType`, t('workflow.field.required', null, { field: t('webhooks.template.var.type') }));
        else if (!PLATFORM_EVENT_TYPE_PATTERN.test(String(config.eventType))) {
          push(`${where}.config.eventType`, t('io.mapping.name.invalidChars'));
        }
        if (!Number.isInteger(Number(config.schemaVersion)) || Number(config.schemaVersion) < 1) {
          push(`${where}.config.schemaVersion`, t('workflow.field.min', null, { field: t('webhooks.template.var.schemaVersion'), min: 1 }));
        }
        if (!config.payload || typeof config.payload !== 'object' || Array.isArray(config.payload)) {
          push(`${where}.config.payload`, t('importer.error.payloadNotObject'));
        }
        if (config.retainDays !== undefined
          && (!Number.isInteger(Number(config.retainDays)) || Number(config.retainDays) < 1 || Number(config.retainDays) > 3650)) {
          push(`${where}.config.retainDays`, t('workflow.field.oneOf', null, { field: 'retainDays', values: '1–3650' }));
        }
        break;
      case 'connector':
        if (!config.channel) push(`${where}.config.channel`, t('workflow.validate.connectorNeedsChannel'));
        if (!config.action) push(`${where}.config.action`, t('workflow.validate.connectorNeedsAction'));
        break;
      case 'python':
        if (!config.source) push(`${where}.config.source`, t('workflow.validate.pythonNeedsSource'));
        break;
      case 'create-record':
      case 'update-record':
      case 'delete-record':
        if (!config.table) push(`${where}.config.table`, t('workflow.validate.recordStepNeedsTable', null, { type: step.type }));
        // A create/update with no field mapping writes nothing the author can
        // see — and at run time the missing `p_values` is DROPPED from the
        // RPC body, so PostgREST answers "could not find the function
        // public.workflow_insert_row(p_actor, p_depth, p_table_id)" — a
        // schema-cache error that names no field on any form. Measured on the
        // D-241 seeded draft saved with `config: { table }` only: save was
        // enabled, the run failed, and the journal said none of this. The
        // form already marks `values` required; the save report must agree.
        if (step.type !== 'delete-record' && !recordStepHasValues(config)) {
          push(`${where}.config.values`, t('workflow.validate.recordStepNeedsValues', null, { type: step.type }));
        }
        break;
      case 'lot-receipt':
      case 'lot-disposition':
        if (!config.tables?.lots?.table) push(`${where}.config.tables`, t('workflow.validate.recordStepNeedsTable', null, { type: step.type }));
        break;
      case 'run-workflow':
        if (!config.workflowId) push(`${where}.config.workflowId`, t('workflow.validate.runWorkflowNeedsId'));
        break;
      default:
        break;
    }
  });

  return { ok: errors.length === 0, errors };
}

// --- serialization --------------------------------------------------------

/**
 * A definition is exactly its JSON. Asserting that here rather than trusting
 * it means a step type that smuggles in a function, a Date or a Map fails at
 * save time instead of at the first restart, when the run cannot be rehydrated
 * and the only evidence is a `[object Object]` in a column.
 */
export function serializeWorkflow(definition) {
  return JSON.stringify(normalizeWorkflow(definition));
}

export function deserializeWorkflow(json) {
  return normalizeWorkflow(typeof json === 'string' ? JSON.parse(json) : json);
}

/**
 * True when a value is made only of things JSON actually preserves.
 *
 * The obvious implementation — compare `x` to `JSON.parse(JSON.stringify(x))`
 * — passes everything, because both sides go through the same lossy encoder.
 * `{fn: () => 1}` stringifies to `{}` on both sides and compares equal, and a
 * `Date` becomes the same ISO string twice. Those are exactly the two values a
 * step config is most likely to smuggle in, and both break a run at its first
 * restart, when the rehydrated definition is quietly not the one that was
 * saved. So this walks the structure and names the types instead.
 */
export function isSerializable(value, seen = new Set()) {
  if (value === null) return true;
  const type = typeof value;
  if (type === 'string' || type === 'boolean') return true;
  if (type === 'number') return Number.isFinite(value);
  if (type === 'undefined' || type === 'function' || type === 'symbol' || type === 'bigint') return false;
  if (type !== 'object') return false;

  if (seen.has(value)) return false; // a cycle cannot be JSON
  seen.add(value);

  if (Array.isArray(value)) return value.every((v) => isSerializable(v, seen));
  // Anything with a prototype other than Object.prototype — Date, Map, Set,
  // RegExp, a class instance — loses its identity in transit.
  const proto = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return false;
  return Object.values(value).every((v) => isSerializable(v, seen));
}

// --- execution keys -------------------------------------------------------

/**
 * The stable identity of one step *execution*, which is what a journal entry
 * is keyed by.
 *
 * A step inside a loop executes many times and each execution needs its own
 * journal slot, or the second iteration would replay the first's result and
 * the loop would silently do nothing after pass one. The frame path carries
 * the iteration indices and fork branch names, so `notify@fork:urgent/loop:3`
 * is a different key from `notify@fork:normal/loop:3` — and both are stable
 * across a restart, because they are derived from position in the definition
 * rather than from a counter that resets.
 */
export function executionKey(stepId, frames = []) {
  return frames.length ? `${stepId}@${frames.join('/')}` : stepId;
}

/** Push a loop frame. */
export function loopFrame(stepId, index) {
  return `loop:${stepId}:${index}`;
}

/** Push a fork-branch frame. */
export function forkFrame(stepId, branchName) {
  return `fork:${stepId}:${branchName}`;
}

// There is deliberately no attempt/retry frame. A retried attempt keeps the
// SAME execution key, so the journal's failure entries accumulate against one
// step and `failureCount` can tell a resumed run how many attempts already
// happened. Giving each attempt its own key would make a crash mid-retry look
// like a fresh step with no history, and the retry budget would reset on every
// restart — a step that fails permanently would then retry forever.
