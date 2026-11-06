/// HTTP response caching semantics (a pragmatic subset of RFC 9111) used by
/// [CachedLoader] to decide what may be stored, whether a stored response is
/// still fresh, and when it must be revalidated. Pure functions — no I/O — so
/// they are trivially unit-testable.
library;

import 'dart:io' show HttpDate;

/// Whether a stored response is currently usable.
class HttpFreshness {
  const HttpFreshness({required this.fresh, required this.mustRevalidate});

  /// Within its freshness lifetime.
  final bool fresh;

  /// `no-cache` (or stored explicitly stale) — must be revalidated before reuse
  /// even if otherwise fresh.
  final bool mustRevalidate;

  /// Safe to serve straight from cache without contacting the origin.
  bool get usableWithoutRevalidation => fresh && !mustRevalidate;
}

/// Whether a response with [status] and [headers] may be stored in a private
/// (browser) cache. Refuses `no-store`, responses that vary on per-user request
/// headers, and responses with neither explicit freshness nor a validator (so a
/// cache entry can always be either trusted-fresh or revalidated, never served
/// stale uncontrolled).
bool httpIsCacheable(int status, Map<String, String> headers) {
  // Only the status codes whose bodies we actually reuse.
  const storable = {200, 203, 301, 308, 410};
  if (!storable.contains(status)) return false;

  final cc = parseCacheControl(headers['cache-control']);
  if (cc.containsKey('no-store')) return false;

  final vary = headers['vary']?.toLowerCase() ?? '';
  if (vary == '*' || vary.contains('cookie') || vary.contains('authorization')) {
    return false;
  }

  final hasFreshness = cc.containsKey('max-age') ||
      cc.containsKey('s-maxage') ||
      headers.containsKey('expires');
  final hasValidator = (headers['etag']?.isNotEmpty ?? false) ||
      (headers['last-modified']?.isNotEmpty ?? false);
  return hasFreshness || hasValidator;
}

/// Computes whether a stored response (with its response [headers]) first
/// stored at [created] is still fresh. [now] is injectable so freshness math
/// is deterministic under test (defaults to the wall clock).
HttpFreshness httpFreshness(
  Map<String, String> headers,
  DateTime created, {
  DateTime Function() now = DateTime.now,
}) {
  final cc = parseCacheControl(headers['cache-control']);
  // `no-cache` (and `must-revalidate` once stale) force revalidation.
  if (cc.containsKey('no-cache')) {
    return const HttpFreshness(fresh: false, mustRevalidate: true);
  }

  // Explicit lifetime first; else heuristic freshness (RFC 9111 §4.2.2) for
  // `Last-Modified`-only responses — suppressed by `must-revalidate` (and by
  // `no-cache`, which returned above), which demand explicit freshness.
  final lifetime = httpFreshnessLifetimeSeconds(headers, now: now) ??
      (cc.containsKey('must-revalidate')
          ? null
          : httpHeuristicLifetimeSeconds(headers, now: now));
  if (lifetime == null) {
    // No freshness information: treat as stale (revalidate if we can).
    return HttpFreshness(
      fresh: false,
      mustRevalidate: cc.containsKey('must-revalidate'),
    );
  }

  final currentAge = httpCurrentAgeSeconds(headers, created, now());
  final fresh = currentAge < lifetime;
  // A stale `must-revalidate` response may NEVER be reused without successful
  // revalidation (RFC 9111 §5.2.2.2) — not even when revalidation fails.
  return HttpFreshness(
    fresh: fresh,
    mustRevalidate: !fresh && cc.containsKey('must-revalidate'),
  );
}

/// The current age in seconds of a stored response (its response [headers]
/// plus the time it was first stored at [created]) as observed at [now] —
/// RFC 9111 §4.2.3, simplified to `Age`-at-store + resident time.
int httpCurrentAgeSeconds(
  Map<String, String> headers,
  DateTime created,
  DateTime now,
) {
  final ageAtStore = int.tryParse(headers['age'] ?? '') ?? 0;
  final resident = now.difference(created).inSeconds;
  return ageAtStore + (resident < 0 ? 0 : resident);
}

/// The explicit freshness lifetime in seconds declared by [headers]
/// (`max-age`, then `s-maxage`, then `Expires` − `Date`), or null when none is
/// declared. [now] is only consulted when `Expires` is present without `Date`.
int? httpFreshnessLifetimeSeconds(
  Map<String, String> headers, {
  DateTime Function() now = DateTime.now,
}) {
  final cc = parseCacheControl(headers['cache-control']);
  final maxAge = int.tryParse(cc['max-age'] ?? '');
  if (maxAge != null) return maxAge < 0 ? 0 : maxAge;
  final sMaxAge = int.tryParse(cc['s-maxage'] ?? '');
  if (sMaxAge != null) return sMaxAge < 0 ? 0 : sMaxAge;

  final expires = headers['expires'];
  if (expires != null) {
    final exp = _httpDate(expires);
    if (exp != null) {
      final date = _httpDate(headers['date'] ?? '') ?? now().toUtc();
      final secs = exp.difference(date).inSeconds;
      return secs < 0 ? 0 : secs;
    }
  }
  return null;
}

/// Heuristic freshness lifetime (RFC 9111 §4.2.2) for a response with a
/// `Last-Modified` validator but no explicit lifetime: 10% of the interval
/// between `Date` (falling back to [now]) and `Last-Modified`, clamped to
/// 24 hours. Null when `Last-Modified` is absent/unparseable (nothing to base
/// a heuristic on).
int? httpHeuristicLifetimeSeconds(
  Map<String, String> headers, {
  DateTime Function() now = DateTime.now,
}) {
  final lastModified = _httpDate(headers['last-modified'] ?? '');
  if (lastModified == null) return null;
  final date = _httpDate(headers['date'] ?? '') ?? now().toUtc();
  final interval = date.difference(lastModified).inSeconds;
  if (interval <= 0) return 0;
  final heuristic = interval ~/ 10;
  const dayLimit = 24 * 60 * 60;
  return heuristic > dayLimit ? dayLimit : heuristic;
}

/// Whether a stale stored response may still be served when revalidation
/// fails with a transport error. `must-revalidate` forbids it outright
/// (RFC 9111 §5.2.2.2). `stale-if-error=N` (RFC 5861) permits it only within
/// N seconds past expiry. With neither directive the (lenient, pre-existing)
/// default is to serve the stale copy rather than fail the load.
bool httpCanServeStaleOnError(
  Map<String, String> headers,
  DateTime created, {
  DateTime Function() now = DateTime.now,
}) {
  final cc = parseCacheControl(headers['cache-control']);
  if (cc.containsKey('must-revalidate')) return false;
  final staleIfError = int.tryParse(cc['stale-if-error'] ?? '');
  if (staleIfError != null) {
    final lifetime = httpFreshnessLifetimeSeconds(headers, now: now) ??
        httpHeuristicLifetimeSeconds(headers, now: now) ??
        0;
    final currentAge = httpCurrentAgeSeconds(headers, created, now());
    return currentAge <= lifetime + staleIfError;
  }
  return true;
}

/// Conditional request headers to revalidate a stored response, derived from its
/// validators (`ETag` → `If-None-Match`, `Last-Modified` → `If-Modified-Since`).
/// Empty when the response carries no validator.
Map<String, String> conditionalHeaders(Map<String, String> stored) {
  final out = <String, String>{};
  final etag = stored['etag'];
  if (etag != null && etag.isNotEmpty) out['if-none-match'] = etag;
  final lastModified = stored['last-modified'];
  if (lastModified != null && lastModified.isNotEmpty) {
    out['if-modified-since'] = lastModified;
  }
  return out;
}

/// Parses a `Cache-Control` header into a directive → value map (valueless
/// directives map to `''`). Keys are lowercased.
Map<String, String> parseCacheControl(String? value) {
  final out = <String, String>{};
  if (value == null) return out;
  for (final part in value.split(',')) {
    final p = part.trim().toLowerCase();
    if (p.isEmpty) continue;
    final eq = p.indexOf('=');
    if (eq < 0) {
      out[p] = '';
    } else {
      out[p.substring(0, eq)] = p.substring(eq + 1).replaceAll('"', '').trim();
    }
  }
  return out;
}

DateTime? _httpDate(String s) {
  if (s.isEmpty) return null;
  try {
    return HttpDate.parse(s);
  } catch (_) {
    return null;
  }
}
