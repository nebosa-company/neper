/**
 * LC47 step execution — dry-run, runtime execution, trace building, and typed
 * output resolution for AI automation steps.
 *
 * This module is the bridge between the block definitions (registry / built-ins)
 * and a flow engine that executes AI actions inside automation flows. It handles
 * prompt resolution, model invocation, output coercion, redacted trace records,
 * and typed-output parsing for downstream predicates (e.g. if/else branches).
 *
 * Pure helpers + async model invocation — no provider coupling; the caller
 * injects the model function.
 */

import { getBlock } from './registry.js';
import { estimateBlockCost } from './types.js';

// ---------------------------------------------------------------------------
// 1. dry-run — preview everything without calling a provider
// ---------------------------------------------------------------------------

/**
 * Dry-run an AI step: resolve the prompt template, pick the model, estimate
 * cost — all without touching any provider.
 *
 * @param {string}  blockKey   registered block key (e.g. "custom-prompt")
 * @param {Object}  config     block config (prompt, outputSchema, model, …)
 * @param {Object}  sources    field values keyed by field name for token substitution
 * @param {string}  [modelId]  optional model override from the step config
 * @returns {{ prompt: string, model: string, costEstimate: Object, blockKey: string, blockLabel: string }}
 */
export function dryRunAiStep(blockKey, config, sources, modelId) {
  const block = getBlock(blockKey);
  if (!block) throw new Error(`Unknown block key: ${blockKey}`);

  const resolvedPrompt = block.buildPrompt
    ? block.buildPrompt(config, sources || {})
    : '';

  const model = modelId || config.model || 'default-model';
  const costEstimate = estimateBlockCost(1, block);

  return {
    prompt: resolvedPrompt,
    model,
    costEstimate,
    blockKey,
    blockLabel: block.label,
  };
}

// ---------------------------------------------------------------------------
// 2. runtime execution
// ---------------------------------------------------------------------------

const REDACT_LENGTH = 100;

/** Redact a prompt for trace records — truncate to first N chars. */
function redact(text) {
  if (!text) return '';
  return text.length <= REDACT_LENGTH ? text : text.slice(0, REDACT_LENGTH) + '…';
}

let _traceSeq = 0;

/** Simple monotonic trace-id generator (suitable for in-process flows). */
function nextTraceId() {
  _traceSeq += 1;
  return `ai-trace-${Date.now()}-${_traceSeq}`;
}

/**
 * Execute an AI step: resolve config, call the injected model function, coerce
 * the output, and return a structured result suitable for both the flow engine
 * and trace building.
 *
 * @param {string}   blockKey
 * @param {Object}   config       block config
 * @param {Object}   sources      field values for token substitution
 * @param {Function} modelFn      async (prompt: string, model: string) => string
 * @returns {Promise<{ ok: boolean, value?: *, blockKey: string, model: string, promptRedacted: string, traceId: string, error?: string }>}
 */
export async function executeAiStep(blockKey, config, sources, modelFn) {
  const block = getBlock(blockKey);
  if (!block) throw new Error(`Unknown block key: ${blockKey}`);

  const prompt = block.buildPrompt
    ? block.buildPrompt(config, sources || {})
    : '';

  const model = config.model || 'default-model';
  const traceId = nextTraceId();

  try {
    const raw = await modelFn(prompt, model);
    const col = { name: config.fieldName || 'output', type: config.outputType || 'text' };

    // Prefer the block's own coerce; fall back to a passthrough.
    const coerced = block.coerce
      ? block.coerce(String(raw == null ? '' : raw), col, config)
      : { ok: true, value: raw };

    return {
      ok: coerced.ok,
      value: coerced.value,
      blockKey,
      model,
      promptRedacted: redact(prompt),
      traceId,
    };
  } catch (err) {
    return {
      ok: false,
      value: undefined,
      blockKey,
      model,
      promptRedacted: redact(prompt),
      traceId,
      error: err.message || String(err),
    };
  }
}

// ---------------------------------------------------------------------------
// 3. trace record
// ---------------------------------------------------------------------------

/**
 * Build a redacted trace record from a step execution result.
 *
 * The trace contains only metadata — step identity, model, redacted prompt
 * prefix, output type, status, correlation, and cost-class charge. The full
 * prompt and response payload are intentionally excluded.
 *
 * @param {Object} stepResult  the return value of executeAiStep
 * @param {Object} stepConfig  step-level config (may include stepId, outputType, costClassCharge, correlationId)
 * @returns {{ stepId: string, blockKey: string, model: string, promptRedacted: string, outputType: string, status: string, correlationId?: string, costClassCharge?: string }}
 */
export function buildAiStepTrace(stepResult, stepConfig = {}) {
  const block = getBlock(stepResult.blockKey);

  return {
    stepId: stepConfig.stepId || stepResult.traceId || 'unknown-step',
    blockKey: stepResult.blockKey,
    model: stepResult.model,
    promptRedacted: stepResult.promptRedacted || redact(stepConfig.prompt || ''),
    outputType: stepConfig.outputType || (block ? (block.configSchema && block.configSchema.outputType && 'declared') || 'text' : 'text'),
    status: stepResult.ok ? 'completed' : 'failed',
    correlationId: stepConfig.correlationId || undefined,
    costClassCharge: stepConfig.costClassCharge || (block ? block.costClass : undefined),
  };
}

// ---------------------------------------------------------------------------
// 4. typed output resolution for branch predicates
// ---------------------------------------------------------------------------

/**
 * Resolve the typed value from a step result for consumption by downstream
 * predicates (e.g. an if/else branch condition).
 *
 * For structured-output steps (those that declared an outputSchema), the value
 * is expected to be a parsed JSON object whose keys the predicate can read.
 * For free-text steps the raw string value is returned as-is.
 *
 * @param {Object} stepResult  the return value of executeAiStep
 * @returns {*}
 */
export function resolveTypedOutput(stepResult) {
  if (!stepResult.ok || stepResult.value === undefined || stepResult.value === null) {
    return null;
  }

  const value = stepResult.value;

  // If the value is already a plain object (JSON was parsed by coerce), return
  // it directly — branch predicates can dereference its keys.
  if (typeof value === 'object' && !Array.isArray(value)) {
    return value;
  }

  // For structured output configs, attempt a last-resort JSON parse of a
  // string value (the block's coerce already tried; this covers edge cases).
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return parsed;
    } catch {
      // Not JSON — return as-is (raw text).
    }
  }

  return value;
}

/** Reset internal sequence counter (for test determinism). */
export function _resetStepSeq() {
  _traceSeq = 0;
}
