/** Shared chart bucket identity. Date buckets use UTC in browser and SQL. */
export const NO_VALUE = '\x00no-value';
const isEmpty = (v) => v == null || v === '' || (Array.isArray(v) && !v.length);
const toDate = (v) => { const d = new Date(v); return Number.isNaN(d.getTime()) ? null : d; };
export function bucketKey(value, bucket) {
  if (isEmpty(value)) return NO_VALUE;
  // An array cell (multiselect / link) is a distinct object per record; key it
  // by content so equal selections share one bucket instead of one bar each.
  if (!bucket) return Array.isArray(value) ? value.join(', ') : value;
  if (bucket === 'year' || bucket === 'month' || bucket === 'quarter' || bucket === 'day' || bucket === 'week') {
    const d = toDate(value);
    if (!d) return NO_VALUE;
    const y = d.getUTCFullYear();
    if (bucket === 'year') return String(y);
    if (bucket === 'month') return `${y}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    if (bucket === 'quarter') return `${y}-Q${Math.floor(d.getUTCMonth() / 3) + 1}`;
    if (bucket === 'day') return d.toISOString().slice(0, 10);
    if (bucket === 'week') {
      const start = Date.UTC(y, 0, 1);
      const week = Math.floor((d.getTime() - start) / (7 * 86400000)) + 1;
      return `${y}-W${String(week).padStart(2, '0')}`;
    }
  }
  if (typeof bucket === 'object' && bucket.size) {
    const n = Number(value);
    if (Number.isNaN(n)) return NO_VALUE;
    const lo = Math.floor(n / bucket.size) * bucket.size;
    return `${lo}–${lo + bucket.size}`;
  }
  return value;
}


export function matchesBucket(value, condition) {
  const key = bucketKey(value, condition.bucket);
  const canonical = key === NO_VALUE ? null : String(key);
  if (condition.op === 'notInBuckets') return !condition.values.some((v) => v === canonical);
  return canonical === (condition.value == null ? null : String(condition.value));
}
