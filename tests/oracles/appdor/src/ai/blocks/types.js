/**
 * LC47 block registry — typed contracts for AI blocks.
 *
 * Every AI primitive is described by a machine-readable definition that both
 * the field-type surface (LC8) and the automation-step surface (LC29) consume,
 * so one block definition yields one field type AND one action step with
 * identical config, output typing, metering, and failure semantics.
 *
 * Pure — no model, no network, no DOM.
 */

/** @typedef {'categorize'|'extract'|'summarize'|'sentiment'|'translate'|'web-research'|'custom-prompt'} BlockKey */

/** @typedef {'low'|'medium'|'high'} CostClass */

/**
 * @typedef {Object} BlockDefinition
 * @property {BlockKey} key           stable namespaced block key
 * @property {string} label           human-readable, i18n-externalised
 * @property {string} description     one-sentence summary
 * @property {CostClass} costClass    relative expense band for estimation/credits
 * @property {Object} configSchema    JSON-schema-ish descriptor for block config fields
 * @property {Object} inputContract   { sourceFields: string[], attachmentInputs: boolean, freeParams: string[] }
 * @property {Object} outputContract  { typeCategory: string, supportedTypes: string[], multiTarget: boolean }
 * @property {Object} capability      { supportsAttachments, supportsWebAccess, deterministicFallback, supportedOutputTypes }
 * @property {string} dryRunBehavior  one-sentence description of what a dry-run shows
 * @property {(config: Object, sources: Record<string,*>) => string} buildPrompt
 * @property {(raw: string, column: Object) => {ok:boolean, value?:*, exact?:boolean, reason?:string}} coerce
 */

/** @returns {{calls: number, costUsd: number, tokens: number}} */
export function emptyUsage() {
  return { calls: 0, costUsd: 0, tokens: 0 };
}

/** Cost estimate for a planned run: recordCount × block base cost. */
export function estimateBlockCost(recordCount, block) {
  const COST_PER_RECORD = { low: 0.001, medium: 0.005, high: 0.02 };
  return {
    records: recordCount,
    costClass: (block && block.costClass) || 'medium',
    estimatedUsd: Math.round(recordCount * (COST_PER_RECORD[(block && block.costClass) || 'medium'] || 0.005) * 1000) / 1000,
  };
}

/** Provenance states for an AI-field cell. */
export const PROVENANCE = {
  EMPTY: 'empty',
  PENDING: 'pending',
  GENERATED: 'generated',
  EDITED: 'edited',
  STALE: 'stale',
  FAILED: 'failed',
};

/** Failure taxonomy — machine-readable outcomes for every surface. */
export const FAILURE_CODES = {
  PROVIDER_UNREACHABLE: 'provider_unreachable',
  RATE_LIMITED: 'rate_limited',
  TIMEOUT: 'timeout',
  INVALID_OUTPUT: 'invalid_output',
  CONTENT_FILTERED: 'content_filtered',
  BUDGET_EXHAUSTED: 'budget_exhausted',
  NO_MODEL_CONFIGURED: 'no_model_configured',
  WEB_ACCESS_DENIED: 'web_access_denied',
};

/** Which failures are transient (retryable). */
export function isTransient(code) {
  return [FAILURE_CODES.PROVIDER_UNREACHABLE, FAILURE_CODES.RATE_LIMITED, FAILURE_CODES.TIMEOUT].includes(code);
}

/** Which failures are terminal (non-retryable). */
export function isTerminal(code) {
  return !isTransient(code);
}
