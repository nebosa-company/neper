/// CORS (Cross-Origin Resource Sharing) and cross-origin response policies
/// (CORP / COEP / COOP) for Vaper.
///
/// Pure policy logic, mirroring [CspPolicy]'s pattern: no I/O lives here — the
/// engine classifies requests, builds/validates preflights, and checks
/// responses through these functions, and performs the actual network work
/// itself. Everything is trivially unit-testable with plain maps.
///
/// Spec references: Fetch (CORS protocol, §3.2; CORP check, §3.5) and HTML
/// (COEP / COOP). Header-name keys are expected lowercased, as
/// [FetchedResource.headers] already guarantees.
library;

// ─── Request classification: simple vs preflighted ──────────────────────────

/// HTTP methods that never require a CORS preflight (CORS-safelisted methods).
const Set<String> corsSafelistedMethods = {'GET', 'HEAD', 'POST'};

/// `Content-Type` essences a CORS-safelisted request may carry.
const Set<String> _safelistedContentTypes = {
  'application/x-www-form-urlencoded',
  'multipart/form-data',
  'text/plain',
};

/// Request-header names that are CORS-safelisted (subject to value checks).
const Set<String> _safelistedHeaderNames = {
  'accept',
  'accept-language',
  'content-language',
  'content-type',
};

/// Whether the request header `name: value` is CORS-safelisted — i.e. sending
/// it cross-origin does not require a preflight. Per the Fetch spec the value
/// must also be short (≤ 128 bytes), and `content-type` is only safelisted for
/// the three form/plain essences (so `application/json` forces a preflight).
bool isCorsSafelistedRequestHeader(String name, String value) {
  final lower = name.trim().toLowerCase();
  if (!_safelistedHeaderNames.contains(lower)) return false;
  if (value.length > 128) return false;
  if (lower == 'content-type') {
    final semi = value.indexOf(';');
    final essence =
        (semi == -1 ? value : value.substring(0, semi)).trim().toLowerCase();
    return _safelistedContentTypes.contains(essence);
  }
  return true;
}

/// The header names in [headers] that are NOT CORS-safelisted — the names a
/// preflight must list in `Access-Control-Request-Headers`. Lowercased and
/// sorted (the spec's serialization order); empty for a simple request.
List<String> corsUnsafeHeaderNames(Map<String, String> headers) {
  final unsafe = <String>[
    for (final e in headers.entries)
      if (!isCorsSafelistedRequestHeader(e.key, e.value))
        e.key.trim().toLowerCase(),
  ]..sort();
  return unsafe;
}

/// Whether a request with [method] and [headers] is "simple" — sendable
/// cross-origin without a preflight. Non-simple requests (PUT/DELETE/PATCH,
/// or any non-safelisted header such as `Authorization` or a JSON
/// content-type) must be approved by an OPTIONS preflight first.
bool isSimpleCorsRequest(String method, Map<String, String> headers) =>
    corsSafelistedMethods.contains(method.toUpperCase()) &&
    corsUnsafeHeaderNames(headers).isEmpty;

// ─── Preflight (OPTIONS) request/response ────────────────────────────────────

/// The request headers for a CORS preflight: an OPTIONS request announcing the
/// intended [method] and non-safelisted header names, from [origin].
Map<String, String> corsPreflightRequestHeaders({
  required String origin,
  required String method,
  required List<String> unsafeHeaderNames,
}) => {
  'origin': origin,
  'access-control-request-method': method.toUpperCase(),
  if (unsafeHeaderNames.isNotEmpty)
    'access-control-request-headers': unsafeHeaderNames.join(','),
};

/// Validates a preflight response. Returns null when the actual request may
/// proceed, else a human-readable block reason (surfaced to JS as a network
/// error). Checks, in order: an ok (2xx) status, the CORS origin/credentials
/// check, `Access-Control-Allow-Methods`, and `Access-Control-Allow-Headers`.
/// The `*` wildcard is honored only for uncredentialed requests, and never
/// covers `authorization` (which must be listed explicitly).
String? corsPreflightBlockReason({
  required String documentOrigin,
  required String method,
  required List<String> unsafeHeaderNames,
  required int statusCode,
  required Map<String, String> responseHeaders,
  required bool credentialed,
}) {
  if (statusCode < 200 || statusCode >= 300) {
    return 'CORS preflight: HTTP $statusCode';
  }
  final originReason = corsResponseBlockReason(
    documentOrigin: documentOrigin,
    responseHeaders: responseHeaders,
    credentialed: credentialed,
  );
  if (originReason != null) return originReason;

  final methods = _splitHeaderList(
    responseHeaders['access-control-allow-methods'],
  ).map((m) => m.toUpperCase()).toSet();
  final methodWildcard = methods.contains('*') && !credentialed;
  final wantedMethod = method.toUpperCase();
  if (!methodWildcard &&
      !methods.contains(wantedMethod) &&
      !corsSafelistedMethods.contains(wantedMethod)) {
    return 'CORS preflight: method $wantedMethod not allowed by '
        'Access-Control-Allow-Methods';
  }

  final allowedHeaders = _splitHeaderList(
    responseHeaders['access-control-allow-headers'],
  ).map((h) => h.toLowerCase()).toSet();
  final headerWildcard = allowedHeaders.contains('*') && !credentialed;
  for (final name in unsafeHeaderNames) {
    final covered = allowedHeaders.contains(name) ||
        (headerWildcard && name != 'authorization');
    if (!covered) {
      return 'CORS preflight: header $name not allowed by '
          'Access-Control-Allow-Headers';
    }
  }
  return null;
}

// ─── The CORS response check ─────────────────────────────────────────────────

/// The CORS check on a cross-origin response: the document at [documentOrigin]
/// may read it only when `Access-Control-Allow-Origin` is `*` (uncredentialed
/// requests only) or matches the document origin — and, for [credentialed]
/// requests, `Access-Control-Allow-Credentials: true` is also present.
/// Returns null when readable, else the block reason.
String? corsResponseBlockReason({
  required String documentOrigin,
  required Map<String, String> responseHeaders,
  required bool credentialed,
}) {
  final acao = responseHeaders['access-control-allow-origin']?.trim();
  if (acao == null || acao.isEmpty) {
    return 'CORS: missing Access-Control-Allow-Origin';
  }
  if (acao == '*') {
    if (credentialed) {
      return 'CORS: wildcard Access-Control-Allow-Origin cannot authorize a '
          'credentialed request';
    }
  } else if ((corsSerializeOrigin(acao) ?? acao) != documentOrigin) {
    return "CORS: Access-Control-Allow-Origin '$acao' does not match "
        "origin $documentOrigin";
  }
  if (credentialed) {
    final acac = responseHeaders['access-control-allow-credentials']?.trim();
    if (acac != 'true') {
      return 'CORS: credentialed request without '
          'Access-Control-Allow-Credentials: true';
    }
  }
  return null;
}

/// Serializes the origin of [url] as `scheme://host[:non-default-port]`, or
/// null for non-http(s) / hostless URLs (about:, data:, …). The same
/// normalization the engine uses for document origins.
String? corsSerializeOrigin(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return null;
  if (u.scheme != 'http' && u.scheme != 'https') return null;
  final defaultPort = u.scheme == 'https' ? 443 : 80;
  final port = u.hasPort && u.port != defaultPort ? ':${u.port}' : '';
  return '${u.scheme}://${u.host}$port';
}

// ─── Preflight result cache (Access-Control-Max-Age) ─────────────────────────

/// A successful preflight's grant: which methods/headers it authorized, until
/// when. Wildcards are stored as flags (they never apply to credentialed
/// requests or the `authorization` header at match time).
class _PreflightEntry {
  _PreflightEntry({
    required this.methods,
    required this.methodWildcard,
    required this.headerNames,
    required this.headerWildcard,
    required this.expires,
  });

  final Set<String> methods; // uppercased
  final bool methodWildcard;
  final Set<String> headerNames; // lowercased
  final bool headerWildcard;
  final DateTime expires;
}

/// Caches successful CORS preflight results per (document origin, request URL,
/// credentials mode) so repeated non-simple requests don't re-issue OPTIONS,
/// honoring `Access-Control-Max-Age` (default 5 s, capped at 2 h — matching
/// mainstream engines). Time is injectable for tests.
class CorsPreflightCache {
  CorsPreflightCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Lifetime when the response carries no `Access-Control-Max-Age`.
  static const Duration defaultMaxAge = Duration(seconds: 5);

  /// Upper bound on `Access-Control-Max-Age` (Chromium's cap).
  static const Duration maxAgeCap = Duration(hours: 2);

  /// Hard cap on entries — a preflight cache shouldn't grow unbounded.
  static const int maxEntries = 256;

  final DateTime Function() _now;
  final Map<String, _PreflightEntry> _entries = {};

  static String _key(String origin, Uri url, bool credentialed) =>
      '$origin ${credentialed ? 'cred' : 'anon'} $url';

  /// Records a successful preflight response for [url] requested by
  /// [origin]. A non-positive `Access-Control-Max-Age` disables caching.
  void store({
    required String origin,
    required Uri url,
    required Map<String, String> responseHeaders,
    required bool credentialed,
  }) {
    var maxAge = defaultMaxAge;
    final raw = responseHeaders['access-control-max-age']?.trim();
    if (raw != null) {
      final secs = int.tryParse(raw);
      if (secs == null) {
        // Unparseable: keep the default.
      } else if (secs <= 0) {
        return; // caching explicitly disabled
      } else {
        maxAge = Duration(seconds: secs);
        if (maxAge > maxAgeCap) maxAge = maxAgeCap;
      }
    }
    final methods = _splitHeaderList(
      responseHeaders['access-control-allow-methods'],
    ).map((m) => m.toUpperCase()).toSet();
    final headers = _splitHeaderList(
      responseHeaders['access-control-allow-headers'],
    ).map((h) => h.toLowerCase()).toSet();
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first); // evict oldest
    }
    _entries[_key(origin, url, credentialed)] = _PreflightEntry(
      methods: methods,
      methodWildcard: methods.contains('*') && !credentialed,
      headerNames: headers,
      headerWildcard: headers.contains('*') && !credentialed,
      expires: _now().add(maxAge),
    );
  }

  /// Whether a fresh cached grant already authorizes [method] +
  /// [unsafeHeaderNames] for [url] from [origin] — if so the preflight is
  /// skipped. Expired entries are purged on the way.
  bool isAllowed({
    required String origin,
    required Uri url,
    required String method,
    required List<String> unsafeHeaderNames,
    required bool credentialed,
  }) {
    final key = _key(origin, url, credentialed);
    final entry = _entries[key];
    if (entry == null) return false;
    if (!_now().isBefore(entry.expires)) {
      _entries.remove(key);
      return false;
    }
    final wantedMethod = method.toUpperCase();
    final methodOk = entry.methodWildcard ||
        entry.methods.contains(wantedMethod) ||
        corsSafelistedMethods.contains(wantedMethod);
    if (!methodOk) return false;
    for (final name in unsafeHeaderNames) {
      final covered = entry.headerNames.contains(name) ||
          (entry.headerWildcard && name != 'authorization');
      if (!covered) return false;
    }
    return true;
  }

  /// Drops every cached grant (navigation partitioning / tests).
  void clear() => _entries.clear();

  /// Number of live entries (diagnostics / tests).
  int get size => _entries.length;
}

// ─── CORP: Cross-Origin-Resource-Policy ─────────────────────────────────────

/// Parsed `Cross-Origin-Resource-Policy` values. [none] covers both an absent
/// header and an unrecognized value (ignored, per spec).
enum CorpPolicy { none, sameOrigin, sameSite, crossOrigin }

/// Parses a `Cross-Origin-Resource-Policy` header value.
CorpPolicy parseCorp(String? header) => switch (header?.trim().toLowerCase()) {
  'same-origin' => CorpPolicy.sameOrigin,
  'same-site' => CorpPolicy.sameSite,
  'cross-origin' => CorpPolicy.crossOrigin,
  _ => CorpPolicy.none,
};

/// The CORP check for a no-cors response fetched by a document at
/// [documentOrigin] (null for about:/data: documents). Returns null when the
/// resource may be embedded, else the block reason.
///
/// - Same-origin responses always pass; non-http(s) responses (data:) are
///   exempt (CORP gates network responses only).
/// - `same-origin` blocks every cross-origin embedding.
/// - `same-site` requires the same registrable domain, and an https document
///   may not embed a non-https same-site resource.
/// - No/unknown CORP passes — unless [embedderRequiresCorp] (the document was
///   served with `Cross-Origin-Embedder-Policy: require-corp`), which blocks
///   cross-origin responses lacking CORP. (COEP's CORS-approval escape hatch
///   is layered on by [noCorsResponseBlockReason].)
String? corpBlockReason({
  required String? documentOrigin,
  required Uri resourceUrl,
  required String? corpHeader,
  required bool embedderRequiresCorp,
}) {
  if (resourceUrl.scheme != 'http' && resourceUrl.scheme != 'https') {
    return null; // CORP applies to network responses only
  }
  final resourceOrigin = corsSerializeOrigin(resourceUrl.toString());
  if (resourceOrigin == null) return null;
  if (documentOrigin == resourceOrigin) return null; // same-origin: always ok

  switch (parseCorp(corpHeader)) {
    case CorpPolicy.crossOrigin:
      return null;
    case CorpPolicy.sameOrigin:
      return 'blocked by Cross-Origin-Resource-Policy: same-origin';
    case CorpPolicy.sameSite:
      final docUri = documentOrigin == null ? null : Uri.tryParse(documentOrigin);
      final docHost = docUri?.host ?? '';
      final sameSite = docHost.isNotEmpty &&
          _registrableDomain(docHost) == _registrableDomain(resourceUrl.host);
      if (!sameSite) {
        return 'blocked by Cross-Origin-Resource-Policy: same-site '
            '(cross-site request)';
      }
      if (docUri?.scheme == 'https' && resourceUrl.scheme != 'https') {
        return 'blocked by Cross-Origin-Resource-Policy: same-site '
            '(https document, non-https resource)';
      }
      return null;
    case CorpPolicy.none:
      if (embedderRequiresCorp) {
        return 'blocked by Cross-Origin-Embedder-Policy: require-corp '
            '(cross-origin response without Cross-Origin-Resource-Policy)';
      }
      return null;
  }
}

/// The full embedding gate for a cross-origin **no-cors** subresource response
/// (script / stylesheet / image / font): the CORP check, with COEP's escape
/// hatch — under `require-corp` a response lacking CORP may still be embedded
/// when its headers pass the (uncredentialed) CORS check for [documentOrigin].
/// Returns null when the response may be used, else the block reason.
String? noCorsResponseBlockReason({
  required String? documentOrigin,
  required Uri resourceUrl,
  required Map<String, String> responseHeaders,
  required bool embedderRequiresCorp,
}) {
  final corpHeader = responseHeaders['cross-origin-resource-policy'];
  final reason = corpBlockReason(
    documentOrigin: documentOrigin,
    resourceUrl: resourceUrl,
    corpHeader: corpHeader,
    embedderRequiresCorp: embedderRequiresCorp,
  );
  if (reason == null) return null;
  if (embedderRequiresCorp &&
      parseCorp(corpHeader) == CorpPolicy.none &&
      documentOrigin != null &&
      corsResponseBlockReason(
            documentOrigin: documentOrigin,
            responseHeaders: responseHeaders,
            credentialed: false,
          ) ==
          null) {
    return null; // CORS-approved: readable is strictly stronger than embeddable
  }
  return reason;
}

// ─── COEP: Cross-Origin-Embedder-Policy ─────────────────────────────────────

/// Parsed `Cross-Origin-Embedder-Policy` values. Only [requireCorp] changes
/// engine behavior (gating cross-origin no-cors subresources);
/// [credentialless] is parsed but treated as [unsafeNone] for embedding (its
/// credential-stripping semantics are a documented gap).
enum CoepPolicy { unsafeNone, requireCorp, credentialless }

/// Parses a `Cross-Origin-Embedder-Policy` header value. Unknown values fall
/// back to `unsafe-none`, per spec.
CoepPolicy parseCoep(String? header) => switch (header?.trim().toLowerCase()) {
  'require-corp' => CoepPolicy.requireCorp,
  'credentialless' => CoepPolicy.credentialless,
  _ => CoepPolicy.unsafeNone,
};

// ─── COOP: Cross-Origin-Opener-Policy ───────────────────────────────────────

/// Parsed `Cross-Origin-Opener-Policy` values.
///
/// COOP is parsed and **recorded only**: it severs `window.opener` links
/// between browsing-context-group members, and Vaper is a single-process
/// browser where every tab is its own isolate with no scripted window
/// relationships (no `window.open` handles, no cross-window DOM access) — so
/// the isolation COOP asks for already holds by construction and enforcement
/// is a deliberate no-op.
enum CoopPolicy { unsafeNone, sameOrigin, sameOriginAllowPopups }

/// Parses a `Cross-Origin-Opener-Policy` header value. Unknown values fall
/// back to `unsafe-none`, per spec.
CoopPolicy parseCoop(String? header) => switch (header?.trim().toLowerCase()) {
  'same-origin' => CoopPolicy.sameOrigin,
  'same-origin-allow-popups' => CoopPolicy.sameOriginAllowPopups,
  _ => CoopPolicy.unsafeNone,
};

// ─── Shared helpers ──────────────────────────────────────────────────────────

/// Splits a comma-separated header list into trimmed, non-empty tokens.
List<String> _splitHeaderList(String? value) => value == null
    ? const []
    : [
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

/// Two-label public suffixes under two-letter ccTLDs (co.uk, com.au, …) for
/// the registrable-domain approximation below.
const Set<String> _ccSecondLevel = {'co', 'com', 'net', 'org', 'gov', 'ac', 'edu'};

/// Registrable-domain ("site") approximation: the last two host labels, or
/// three when the host ends in a well-known `<sld>.<cc>` public suffix
/// (example.co.uk → example.co.uk). IP literals are their own site.
///
/// NOTE: this duplicates the spirit of cookie_jar.dart's same-site
/// approximation (Vaper carries no Public Suffix List); if a real PSL ever
/// lands, both call sites should switch to it.
String _registrableDomain(String host) {
  final h = host.toLowerCase();
  // IPv6 literal or anything non-dotted: the host is its own site.
  if (h.contains(':') || !h.contains('.')) return h;
  final labels = h.split('.');
  // IPv4 literal: every label numeric.
  if (labels.every((l) => l.isNotEmpty && int.tryParse(l) != null)) return h;
  var take = 2;
  if (labels.length >= 3 &&
      labels.last.length == 2 &&
      _ccSecondLevel.contains(labels[labels.length - 2])) {
    take = 3;
  }
  return labels.sublist(labels.length - take).join('.');
}
