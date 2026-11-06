/**
 * `{{ now }}` and `{{ today }}` for workflow templates.
 *
 * Until 2026-10-08 neither was bound. An unbound name renders as nothing rather
 * than failing, so "set the closing date to {{ now }}" wrote an empty value and
 * the run reported success; the repo's own workflow walk (S4-063) had already
 * filed it as HOLLOW. The only working spelling was `{{ run.startedAt | date }}`,
 * which nobody could guess.
 *
 * Both come from the run's START, not the wall clock, on purpose: a durable run
 * replays its templates when it resumes after a wait, and a value that moved
 * between the first attempt and the replay would make the same step write two
 * different dates. `run.startedAt` is journaled once when the run is created.
 *
 * UTC, like the template engine's `date` filter, so `{{ today }}` equals
 * `{{ run.startedAt | date }}` exactly.
 */

/**
 * @param {number|null|undefined} startedAt epoch milliseconds
 * @returns {{ now?: string, today?: string }} empty when the run has no start
 *   time, so the names stay unbound rather than becoming a wrong date
 */
export function runClock(startedAt) {
  const ms = typeof startedAt === 'number' ? startedAt : Number(startedAt);
  if (!Number.isFinite(ms) || ms <= 0) return {};
  const iso = new Date(ms).toISOString();
  return { now: iso, today: iso.slice(0, 10) };
}
