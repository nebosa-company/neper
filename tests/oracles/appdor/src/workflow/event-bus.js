/**
 * Platform event bus (LC28.28-LC28.30) — cross-app events as first-class
 * citizens.
 *
 * Modules and re-platformed system apps publish typed events to a
 * discoverable event-type catalog with versioned payload schemas; workflow
 * rules (and, via LC35, external webhooks) subscribe by event type with
 * condition pre-filters. Custom app events let one citizen-built app emit a
 * named, schema-declared event that rules in other solutions consume —
 * decoupled app-to-app composition.
 *
 * Delivery contract: at-least-once per subscription, best-effort ordering
 * per subject (documented, not guaranteed), publisher-side schema validation
 * (malformed events are rejected at publish, not at N consumers), a
 * configurable retention window for inspection and admin replay (replays are
 * flagged and excluded from dedupe invariants), and causation ids +
 * cascade-depth counters so bus-mediated chains hit the same loop guards as
 * direct ones. Pure and in-memory; the host persists retained events.
 */

import { matchesFilter } from '../views/query.js';

let seq = 0;
const uid = (p) => `${p}_${Date.now().toString(36)}_${(seq++).toString(36)}`;

export const DEFAULT_RETENTION_MS = 7 * 24 * 3600 * 1000;
export const PLATFORM_EVENT_TYPE_PATTERN = /^[a-z][a-z0-9_-]*(?::[a-z][a-z0-9_-]*)?(?:\.[a-z][a-z0-9_-]*)*$/;

const JSON_TYPES = new Set(['string', 'number', 'integer', 'boolean', 'object', 'array', 'null']);

/** The declaration contract mirrored by public.platform_event_types. */
export function validateEventSchema(schema = {}) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return { ok: false, error: 'event-schema-object-required' };
  /** @type {Record<string, any>} */
  const declaration = schema;
  if (!Number.isInteger(declaration.version) || declaration.version < 1) return { ok: false, error: 'event-schema-version-invalid' };
  if (declaration.type !== undefined && declaration.type !== 'object') return { ok: false, error: 'event-schema-root-must-be-object' };
  if (declaration.additionalProperties !== undefined && typeof declaration.additionalProperties !== 'boolean') {
    return { ok: false, error: 'event-schema-additional-properties-invalid' };
  }
  const required = declaration.required === undefined ? [] : declaration.required;
  if (!Array.isArray(required) || required.some((key) => typeof key !== 'string' || !key)) {
    return { ok: false, error: 'event-schema-required-invalid' };
  }
  if (new Set(required).size !== required.length) return { ok: false, error: 'event-schema-required-duplicate' };
  const properties = declaration.properties === undefined ? {} : declaration.properties;
  if (!properties || typeof properties !== 'object' || Array.isArray(properties)) {
    return { ok: false, error: 'event-schema-properties-invalid' };
  }
  for (const spec of Object.values(properties)) {
    if (!spec || typeof spec !== 'object' || Array.isArray(spec) || !JSON_TYPES.has(spec.type)) {
      return { ok: false, error: 'event-schema-property-type-invalid' };
    }
  }
  return { ok: true };
}

const payloadType = (value) => {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
};

export function validateEventPayload(schema, payload) {
  const declaration = validateEventSchema(schema);
  if (!declaration.ok) return declaration;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return { ok: false, error: 'event-payload-object-required' };
  for (const field of schema.required || []) {
    if (payload[field] === undefined) return { ok: false, error: `event-payload-missing-required "${field}"` };
  }
  for (const [field, spec] of Object.entries(schema.properties || {})) {
    if (payload[field] === undefined) continue;
    const actual = payloadType(payload[field]);
    const valid = spec.type === 'integer'
      ? Number.isInteger(payload[field])
      : spec.type === 'number'
        ? typeof payload[field] === 'number' && Number.isFinite(payload[field])
        : actual === spec.type;
    if (!valid) return { ok: false, error: `event-payload-type-invalid "${field}"` };
  }
  if (schema.additionalProperties === false) {
    const declared = new Set(Object.keys(schema.properties || {}));
    const extra = Object.keys(payload).find((field) => !declared.has(field));
    if (extra) return { ok: false, error: `event-payload-property-unknown "${extra}"` };
  }
  return { ok: true };
}

export function createBus(opts = {}) {
  const eventTypes = new Map(); // type → { schema, description, app }
  const subscriptions = new Map(); // id → { eventType, filter, deliver, ctx }
  const retained = []; // { event, deliveries: [{subscriptionId, ok}] }
  const retentionMs = opts.retentionMs || DEFAULT_RETENTION_MS;

  function prune(nowMs) {
    while (retained.length && nowMs - Date.parse(retained[0].event.at) > retentionMs) retained.shift();
  }

  function validate(type, payload) {
    const t = eventTypes.get(type);
    if (!t) return { ok: false, error: `event-type-not-declared "${type}"` };
    const result = validateEventPayload(t.schema, payload);
    return result.ok ? result : { ...result, error: `${result.error} "${type}"` };
  }

  function deliverTo(entry, event) {
    const results = [];
    for (const [id, sub] of subscriptions) {
      if (sub.eventType !== event.type) continue;
      if (sub.filter && !matchesFilter(sub.filter, event.payload || {}, (sub.ctx && sub.ctx.fields) || [], {})) {
        continue;
      }
      let ok = true;
      let error = null;
      try {
        sub.deliver(event);
      } catch (e) {
        ok = false;
        error = String(e && e.message ? e.message : e);
      }
      results.push({ subscriptionId: id, ok, error });
    }
    entry.deliveries.push(...results);
    return results;
  }

  return {
    /** Declare an event type with its payload schema (LC28.3 versioned). */
    declareEventType(type, { schema = { version: 1, required: [] }, description = '', app = null } = {}) {
      const normalized = { version: 1, required: [], ...schema };
      if (!PLATFORM_EVENT_TYPE_PATTERN.test(String(type)) || String(type).length > 160) {
        throw new TypeError(`event-type-invalid "${type}"`);
      }
      const declaration = validateEventSchema(normalized);
      if (!declaration.ok) throw new TypeError(`${declaration.error} "${type}"`);
      eventTypes.set(type, { type, schema: normalized, description, app });
    },

    /** The discoverable event-type catalog. */
    catalog: () => [...eventTypes.values()].map((t) => ({ type: t.type, version: t.schema.version, description: t.description, app: t.app })),

    schemaOf: (type) => (eventTypes.has(type) ? eventTypes.get(type).schema : null),

    /**
     * Publish an event. Malformed payloads are rejected here, at the
     * publisher, never surfaced as N consumer failures.
     */
    publish(type, payload, meta = {}) {
      const v = validate(type, payload);
      if (!v.ok) return { ok: false, error: v.error };
      const event = {
        id: uid('pev'),
        type,
        payload,
        at: meta.now || new Date().toISOString(),
        actor: meta.actor || null,
        app: meta.app || null,
        correlationId: meta.correlationId || uid('cor'),
        causationId: meta.causationId || null,
        cascadeDepth: meta.cascadeDepth || 0,
        subject: meta.subject || null,
        replay: false,
      };
      const entry = { event, deliveries: [] };
      retained.push(entry);
      prune(Date.parse(event.at));
      const deliveries = deliverTo(entry, event);
      return { ok: true, event, deliveries };
    },

    /**
     * Subscribe a workflow rule (or any consumer) to an event type with an
     * optional condition pre-filter.
     */
    subscribe(eventType, deliver, opts2 = {}) {
      const id = opts2.id || uid('sub');
      subscriptions.set(id, { eventType, deliver, filter: opts2.filter || null, ctx: opts2.ctx || null });
      return id;
    },

    unsubscribe: (id) => subscriptions.delete(id),

    /** Retained events for inspection (newest last). */
    retained: () => retained.map((r) => ({ event: r.event, deliveries: r.deliveries })),

    /**
     * Admin replay of a retained event (LC28.33): the replayed delivery is
     * flagged `replay: true` so run logs and dedupe treat it distinctly.
     */
    replay(eventId) {
      const entry = retained.find((r) => r.event.id === eventId);
      if (!entry) return { ok: false, error: 'event-not-retained' };
      const replayEvent = { ...entry.event, replay: true };
      const deliveries = deliverTo(entry, replayEvent);
      return { ok: true, event: replayEvent, deliveries };
    },
  };
}

/**
 * The emit-event workflow action body (LC28.29): publish a custom app
 * event through the bus, propagating causation and cascade depth from the
 * emitting run so bus-mediated chains hit LC27 loop guards like direct ones.
 */
export function emitAppEvent(bus, type, payload, runContext = {}) {
  return bus.publish(type, payload, {
    causationId: runContext.eventId || null,
    correlationId: runContext.correlationId,
    cascadeDepth: (runContext.cascadeDepth || 0) + 1,
    actor: runContext.actor || null,
    app: runContext.app || null,
    now: runContext.now,
  });
}
