import { dateTime } from '../i18n/prefs.js';

// Stored scalar facts and server-verified attachment versions. Computed and
// linked values still need their own dependency model.
export const EVIDENCE_TYPES = new Set([
  'text', 'longtext', 'number', 'currency', 'percent', 'checkbox', 'date', 'datetime',
  'email', 'url', 'phone', 'select', 'rating', 'duration', 'attachment',
]);

export function evidenceFields(columns = []) {
  return columns.filter((c) => c?.id && c.name && !c.is_deleted && EVIDENCE_TYPES.has(c.type));
}

export async function loadApprovalEvidence(client, rows) {
  const bound = rows.filter((r) => r.definition?.evidenceFields?.length);
  if (!bound.length) return rows;
  const byId = new Map();
  for (let offset = 0; offset < bound.length; offset += 100) {
    const { data, error } = await client.rpc('get_approval_evidence', { p_ids: bound.slice(offset, offset + 100).map((r) => r.id) });
    if (error) throw error;
    for (const item of data || []) byId.set(item.approval_id, item.evidence);
  }
  return rows.map((row) => row.definition?.evidenceFields?.length
    ? { ...row, evidence: byId.get(row.id) || { state: 'unavailable', fields: [] } } : row);
}

export function evidenceAllowsDecision(row) {
  return !row.definition?.evidenceFields?.length || (row.evidence?.state === 'current'
    && row.evidence.fields?.length === row.definition.evidenceFields.length);
}

export function renderApprovalEvidence(row, { escapeHtml: esc, t }) {
  if (!row.definition?.evidenceFields?.length) {
    return `<p class="text-2xs text-muted mt-2" data-approval-evidence="unbound">${esc(t('approvals.evidence.unbound'))}</p>`;
  }
  const evidence = row.evidence || { state: 'unavailable', fields: [] };
  const value = (v, present, kind) => !present ? t('approvals.evidence.unset') : v === null ? t('approvals.evidence.empty')
    : kind === 'attachment' && Array.isArray(v) ? v.join('\n') : typeof v === 'object' ? JSON.stringify(v) : String(v);
  return `<div class="mt-2 text-xs" data-approval-evidence="${esc(evidence.state)}">
    <p class="${evidence.state === 'current' ? 'text-muted' : 'text-danger font-medium'}">${esc(t(`approvals.evidence.${evidence.state}`))}</p>
    ${evidence.version != null ? `<p class="text-2xs text-muted">${esc(t('approvals.evidence.version', null, { version: evidence.version, at: dateTime(evidence.capturedAt) }))}</p>` : ''}
    ${evidence.fields?.length ? `<div class="overflow-auto"><table class="w-full text-left mt-1"><thead><tr>
      <th class="p-1">${esc(t('approvals.evidence.field'))}</th><th class="p-1">${esc(t('approvals.evidence.requested'))}</th><th class="p-1">${esc(t('approvals.evidence.now'))}</th>
      </tr></thead><tbody>${evidence.fields.map((f) => `<tr class="${f.changed ? 'text-danger' : 'text-secondary'}">
        <th class="p-1 font-normal align-top">${esc(f.name)}</th><td class="p-1 whitespace-pre-wrap break-all align-top">${esc(value(f.before, f.beforePresent, f.kind))}</td><td class="p-1 whitespace-pre-wrap break-all align-top">${esc(value(f.after, f.afterPresent, f.kind))}${f.kind === 'attachment' ? `<p class="text-2xs mt-1">${esc(t(`approvals.evidence.files.${f.fileState || 'missing'}`))}</p>` : ''}</td>
      </tr>`).join('')}</tbody></table></div>` : ''}
    ${evidence.fields?.some((f) => f.kind === 'attachment') ? `<p class="text-2xs text-muted mt-2">${esc(t('approvals.evidence.files.note'))}</p>` : ''}
    ${evidence.fields?.length < row.definition.evidenceFields.length ? `<p class="text-2xs text-muted">${esc(t('approvals.evidence.hidden'))}</p>` : ''}
  </div>`;
}
