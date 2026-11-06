/**
 * LC47 AI block registry — the single registration surface for every AI primitive.
 *
 * Each block is defined once with a machine-readable config schema, typed I/O
 * contracts, cost class, and capability descriptor, then consumed through both
 * the field-type registry (LC8) and the automation step registry (LC29) without
 * a parallel vocabulary. The introspection API (introspect()) is the contract
 * for visual builders, the AI app generator, agents, and plugins.
 *
 * Pure — no model, no network, no DOM.
 *
 * ## Why there is no `t()` in this file
 *
 * `step-execution.js` imports `getBlock` from here, and the flow engine
 * (`workflow/flow-engine.js`) imports `step-execution.js` to run `ai` steps.
 * The flow engine is loaded by `services/workflow-worker`, which is plain Node:
 * `language.js` pulls locale JSON through `localization/bundle-loader.js`
 * without an import attribute, so anything that reaches it dies at boot with
 * `ERR_IMPORT_ATTRIBUTE_MISSING` — not at the first translated string, at
 * import. One `t()` here would therefore take the worker down.
 *
 * So this file emits CODES. Prose for them is rendered by whoever has a screen.
 */

import { estimateBlockCost, PROVENANCE } from './types.js';

/** @type {Map<string, Object>} */
const _blocks = new Map();

/**
 * Register a block. Idempotent within a session; last write wins.
 * @param {Object} def  BlockDefinition from types.js
 */
export function registerBlock(def) {
  if (!def || !def.key) throw new Error('block requires a key');
  _blocks.set(def.key, Object.freeze({ ...def }));
}

/**
 * Look up a registered block by key.
 * @param {string} key
 * @returns {Object|undefined}
 */
export function getBlock(key) {
  return _blocks.get(key);
}

/** @returns {string[]} all registered block keys */
export function listBlockKeys() {
  return [..._blocks.keys()];
}

/** @returns {Object[]} all registered block definitions */
export function listBlocks() {
  return [..._blocks.values()];
}

/**
 * The introspection API (LC47.4): block list with config schemas, output
 * contracts, cost classes — everything a visual builder, generator, agent,
 * or plugin needs to compose blocks without hardcoded knowledge.
 *
 * @param {Object} [opts]
 * @param {boolean} [opts.includePrompts]  default false — prompts are large
 * @returns {{blocks: Object[]}}
 */
export function introspect(opts = {}) {
  const blocks = listBlocks().map((b) => {
    const out = {
      key: b.key,
      label: b.label,
      description: b.description,
      costClass: b.costClass,
      configSchema: b.configSchema,
      inputContract: b.inputContract,
      outputContract: b.outputContract,
      capability: b.capability,
      dryRunBehavior: b.dryRunBehavior,
    };
    if (opts.includePrompts) out._buildPromptExample = b.buildPrompt({}, { _source: 'example' });
    return out;
  });
  return { blocks };
}

/**
 * Resolve a block as a field-type descriptor (LC8 surface).
 * The field-type registry can call this to get a first-class typed field
 * whose output participates in views, formulas, conditions, and the API.
 *
 * @param {string} blockKey
 * @returns {Object|null} field type descriptor
 */
export function asFieldType(blockKey) {
  const b = getBlock(blockKey);
  if (!b) return null;
  const outputTypes = b.outputContract.supportedTypes || ['text'];
  // The AI field is a computed field that stores values in canonical LC8 codecs.
  return {
    id: `ai-${b.key}`,
    name: b.label,
    category: 'ai',
    kind: 'computed',
    computed: true,
    sortable: outputTypes.includes('number') || outputTypes.includes('date') || outputTypes.includes('select'),
    aggregatable: outputTypes.includes('number'),
    filterOperators: ['is', 'isNot', 'isEmpty', 'isNotEmpty'],
    aiBlock: b.key,
    outputType: outputTypes[0],
    block: () => b,
  };
}

/**
 * Build the AI-field provenance metadata for a cell write.
 * @param {string} blockKey
 * @param {string} model
 * @param {Object} [meta]  { confidence, citations, costClassCharge, timestamp }
 */
export function provenanceStamp(blockKey, model, meta = {}) {
  return {
    block: blockKey,
    model: model || 'unknown',
    timestamp: meta.timestamp || new Date().toISOString(),
    costClassCharge: meta.costClassCharge || null,
    confidence: meta.confidence ?? null,
    citations: meta.citations || [],
    state: PROVENANCE.GENERATED,
  };
}

/**
 * `mayRecompute` refusal code: the cell was hand-edited and the field has not
 * opted into overwrite. Copy lives at locale key `ai.recompute.editedLocked`.
 */
export const RECOMPUTE_EDITED_LOCKED = 'edited_locked';

/**
 * Check whether a cell may be auto-recomputed.
 * @param {Object} cellProvenance  { state, ... }
 * @param {boolean} allowOverwrite  per-field opt-out, default false
 * @returns {{allowed: boolean, reason?: string}}
 */
export function mayRecompute(cellProvenance, allowOverwrite = false) {
  const state = (cellProvenance && cellProvenance.state) || PROVENANCE.EMPTY;
  if (state === PROVENANCE.EMPTY || state === PROVENANCE.PENDING || state === PROVENANCE.FAILED) {
    return { allowed: true };
  }
  if (state === PROVENANCE.GENERATED || state === PROVENANCE.STALE) {
    return { allowed: true };
  }
  if (state === PROVENANCE.EDITED) {
    if (allowOverwrite) return { allowed: true };
    // `allowed` is the machine channel and every caller in the tree branches on
    // it; `applications.js:4908` is the only consumer and reads nothing else.
    // This used to be `t('ai.recompute.editedLocked')` — the sentence, resolved
    // here. It cannot be: see the header. The key still exists in both bundles,
    // so a screen that wants the sentence maps this code to it and loses
    // nothing, and `checkBudgetForOp` below already answered in codes.
    return { allowed: false, reason: RECOMPUTE_EDITED_LOCKED };
  }
  return { allowed: false, reason: `Unknown provenance state: ${state}` };
}

/**
 * Budget check result for a planned operation.
 * @param {number} recordCount
 * @param {Object} block
 * @param {Object} budget  { monthlyCalls, monthlyCostUsd, ratePerMinute }
 * @param {Object} usage   { calls, costUsd }
 * @returns {{allowed: boolean, reason?: string, estimate: Object, remaining: Object}}
 */
export function checkBudgetForOp(recordCount, block, budget = {}, usage = {}) {
  const estimate = estimateBlockCost(recordCount, block);
  const usedCalls = (usage && usage.calls) || 0;
  const usedCost = (usage && usage.costUsd) || 0;
  const limitCalls = budget.monthlyCalls != null ? budget.monthlyCalls : 5000;
  const limitCost = budget.monthlyCostUsd != null ? budget.monthlyCostUsd : 50;

  const remaining = {
    calls: Math.max(0, limitCalls - usedCalls),
    costUsd: Math.round(Math.max(0, limitCost - usedCost) * 100) / 100,
  };

  if (usedCalls + recordCount > limitCalls) {
    return { allowed: false, reason: 'budget_exhausted', estimate, remaining };
  }
  if (usedCost + estimate.estimatedUsd > limitCost) {
    return { allowed: false, reason: 'budget_exhausted', estimate, remaining };
  }
  return { allowed: true, estimate, remaining };
}

/** All registered blocks, keyed. For test introspection. */
export function _resetForTest() {
  _blocks.clear();
}
