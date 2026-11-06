/**
 * References group (docs/formulas.md:156-162), implemented against an injected
 * evaluation context (REQ-FORMULAENGINE-14) so the Neposer/Appdor shell supplies
 * tenancy and user identity and the package stays host-agnostic. Absent context
 * values resolve to blank; cross-record Formula Queries resolve through
 * host-supplied callbacks and return #N/A when the host does not provide them.
 */

import { naError } from './errors.js';
import { toText, looseEquals } from './values.js';

const CATEGORY = 'reference';

function ref(key) {
  return {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 0,
    fn: (_args, ctx) => {
      const v = ctx ? ctx[key] : undefined;
      return v === undefined ? null : v;
    },
  };
}

/**
 * The four context keys a ROW supplies, read off a row in either spelling.
 *
 * `CREATEDON()`, `UPDATEDON()`, `CREATEDBY()` and `UPDATEDBY()` are defined
 * immediately below and `evaluator.js` declares all four on its context type —
 * and for a long time nothing in the product filled one, so every one of them
 * evaluated to blank for every row, identically. The same shape as the
 * `CURRENTUSER()` defect recorded in `gridFormulaContext`; that pair's
 * per-viewer half was found and fixed, and this per-row half was not.
 *
 * It lives HERE, beside the definitions, because there are two evaluators that
 * must agree: the grid renders these live (`src/grid/computed.js`) and the
 * backfill worker computes and PERSISTS them (`src/formula/backfill.js`). Two
 * copies of this mapping is how the screen and the stored value come to
 * disagree about the same cell — and the stored one wins on the next read.
 *
 * Both spellings, because a row arrives from PostgREST as `created_at` and from
 * a caller's own object as `createdOn`.
 *
 * @param {object} row
 * @returns {{createdOn: any, updatedOn: any, createdBy: any, updatedBy: any}}
 */
export function rowMetaContext(row) {
  /** @type {Record<string, any>} */
  const r = row || {};
  return {
    createdOn: r.created_at ?? r.createdOn ?? null,
    updatedOn: r.updated_at ?? r.updatedOn ?? null,
    createdBy: r.created_by ?? r.createdBy ?? null,
    updatedBy: r.updated_by ?? r.updatedBy ?? null,
  };
}

const reference = {
  ROW: { ...ref('rowId'), name: 'ROW' },
  ROWID: { ...ref('rowId'), aliases: ['RECORD_ID', 'RECORDID'] },
  TABLEID: ref('tableId'),
  APPID: ref('appId'),
  REALMID: ref('realmId'),
  USERID: ref('userId'),
  // Airtable's names for three functions that already existed. Aliases rather
  // than new entries: two implementations of "when was this row created" is how
  // they come to disagree about a row that has never been saved.
  CREATEDON: { ...ref('createdOn'), aliases: ['CREATED_ON', 'CREATED_TIME', 'CREATEDTIME'] },
  UPDATEDON: {
    ...ref('updatedOn'),
    aliases: ['UPDATED_ON', 'MODIFIEDON', 'LAST_MODIFIED_TIME', 'LASTMODIFIEDTIME'],
  },
  CREATEDBY: { ...ref('createdBy'), aliases: ['CREATED_BY'] },
  UPDATEDBY: { ...ref('updatedBy'), aliases: ['UPDATED_BY', 'MODIFIEDBY'] },
  BROWSERAGENT: { ...ref('browserAgent'), aliases: ['USERAGENT'] },

  // CURRENTUSER(): the current user's display name or identifier (volatile).
  CURRENTUSER: {
    category: CATEGORY,
    aliases: ['CURRENT_USER', 'USER', 'USERNAME'],
    volatile: true,
    minArgs: 0,
    maxArgs: 0,
    fn: (_args, ctx) => {
      // Resolves through the context like other reference functions, but is
      // volatile so it forces read-evaluated materialization classification.
      if (!ctx) return null;
      // Host can supply a user display name, a user id, or both.
      return ctx.currentUser ?? ctx.userName ?? ctx.userId ?? null;
    },
  },

  // Cross-record Formula Queries — resolve through host callbacks (phase 2 of the
  // catalog; depend on the relationship layer).
  GETRECORDS: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 2,
    fn: (args, ctx) => {
      if (ctx && typeof ctx.getRecords === 'function') return ctx.getRecords(args[0], args[1]);
      return naError('GetRecords requires a host relationship context');
    },
  },
  GETFIELDVALUES: {
    category: CATEGORY,
    minArgs: 2,
    maxArgs: 3,
    fn: (args, ctx) => {
      if (ctx && typeof ctx.getFieldValues === 'function') {
        return ctx.getFieldValues(args[0], args[1], args[2]);
      }
      return naError('GetFieldValues requires a host relationship context');
    },
  },
  CHILDREN: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 1,
    fn: (args, ctx) => {
      if (ctx && typeof ctx.children === 'function') return ctx.children(args[0]);
      return naError('CHILDREN requires a host hierarchy context');
    },
  },

  // Record-context functions for validation rules (Salesforce parity). ISCHANGED
  // and PRIORVALUE take a field NAME as a string; they read ctx.prior/ctx.fields.
  ISNEW: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 0,
    fn: (_args, ctx) => (ctx ? ctx.isNew === true : false),
  },
  ISCHANGED: {
    category: CATEGORY,
    minArgs: 1,
    maxArgs: 1,
    fn: (args, ctx) => {
      if (!ctx) return false;
      const name = toText(args[0]);
      if (ctx.prior && ctx.fields) return !looseEquals(ctx.fields[name], ctx.prior[name]);
      if (Array.isArray(ctx.changed)) return ctx.changed.includes(name);
      return false;
    },
  },
  PRIORVALUE: {
    category: CATEGORY,
    aliases: ['PRIOR_VALUE'],
    minArgs: 1,
    maxArgs: 1,
    fn: (args, ctx) => {
      if (!ctx || !ctx.prior) return null;
      const name = toText(args[0]);
      return ctx.prior[name] === undefined ? null : ctx.prior[name];
    },
  },
  ANCESTORS: {
    category: CATEGORY,
    minArgs: 0,
    maxArgs: 1,
    fn: (args, ctx) => {
      if (ctx && typeof ctx.ancestors === 'function') return ctx.ancestors(args[0]);
      return naError('ANCESTORS requires a host hierarchy context');
    },
  },

  // --- asking about a field rather than about its value -------------------
  //
  // All three are `lazy`, which is the whole point: `NAME({Amount})` must not
  // evaluate `{Amount}` — the answer is "Amount", and evaluating first would
  // throw that away and leave only the number, which every field holding the
  // same value would share.

  /** NAME({Field}): what the referenced field is called. */
  NAME: {
    category: CATEGORY,
    lazy: true,
    minArgs: 1,
    maxArgs: 1,
    fn: (nodes) => {
      const name = fieldNameOf(nodes[0]);
      // A literal or an expression has no name to give. #N/A rather than '' so
      // the formula says "not applicable" instead of quietly producing a blank
      // that reads as a field with an empty name.
      return name === null ? naError('NAME expects a field reference') : name;
    },
  },

  /**
   * PROPERTY({Field}, 'decimals'): one configured property of a field.
   *
   * Reads `ctx.fieldMeta` — a map of field name to its column config, which the
   * host supplies. Without it the answer is #N/A rather than a guess: a formula
   * that silently reports `decimals` as 0 for a column configured to 2 is worse
   * than one that says it cannot tell.
   */
  PROPERTY: {
    category: CATEGORY,
    lazy: true,
    minArgs: 2,
    maxArgs: 2,
    fn: (nodes, ctx, ev, scope) => {
      const meta = metaFor(nodes[0], ctx);
      if (!meta) return naError('PROPERTY requires a field reference and host field metadata');
      const key = toText(ev.eval(nodes[1], scope));
      const value = meta[key];
      return value === undefined ? naError(`No property "${key}" on that field`) : value;
    },
  },

  /** PROPERTIES({Field}): every configured property, as [key, value] pairs. */
  PROPERTIES: {
    category: CATEGORY,
    lazy: true,
    minArgs: 1,
    maxArgs: 1,
    fn: (nodes, ctx) => {
      const meta = metaFor(nodes[0], ctx);
      if (!meta) return naError('PROPERTIES requires a field reference and host field metadata');
      return Object.entries(meta).map(([key, value]) => [key, value]);
    },
  },
};

/** The field a node names, or null when the node is not a reference. */
function fieldNameOf(node) {
  if (!node || (node.type !== 'field' && node.type !== 'name')) return null;
  return node.name;
}

/** The host's metadata for the field a node names, or null. */
function metaFor(node, ctx) {
  const name = fieldNameOf(node);
  if (name === null) return null;
  const all = ctx && ctx.fieldMeta;
  if (!all || typeof all !== 'object') return null;
  const meta = all[name];
  return meta && typeof meta === 'object' ? meta : null;
}

export default reference;
