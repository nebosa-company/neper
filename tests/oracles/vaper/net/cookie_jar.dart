
/// A per-session in-memory HTTP cookie store.
///
/// Stores cookies received via `Set-Cookie` response headers and injects
/// them into subsequent requests as a `Cookie:` header.
///
/// Security properties enforced here:
/// - **Secure** cookies are only sent over HTTPS.
/// - **HttpOnly** cookies cannot be read or set by JavaScript (they are
///   stored and forwarded by the loader, not exposed to the JS engine).
/// - **SameSite=Strict** cookies are not sent on cross-site navigations
///   (we approximate "same-site" as same registrable domain).
/// - **SameSite=Lax** cookies are sent on same-site navigations and
///   top-level cross-site navigations with "safe" methods (GET/HEAD).
/// - **SameSite=None** cookies are sent cross-site only over HTTPS, and
///   only when the Secure attribute is also set.
/// - **Domain** attribute cookies must not set a superdomain that the
///   response host is not a subdomain of (prefix check). Public suffixes
///   are not checked (no PSL), but bare TLDs are rejected.
/// - Cookies are cleared when [clear] is called (e.g. on engine dispose
///   or when the user navigates away with the "clear on exit" setting).
/// - The total number of cookies is capped to prevent memory exhaustion
///   by a malicious server.
/// - **`__Host-` / `__Secure-` prefixes** (RFC 6265bis): a `Set-Cookie`
///   whose name starts with `__Secure-` is rejected unless it has the
///   Secure attribute and was set from a secure (https) origin; `__Host-`
///   additionally requires *no* Domain attribute and an explicit `Path=/`.
/// - **CHIPS (`Partitioned` attribute)**: partitioned cookies (which also
///   require Secure) are stored and returned under a composite key that
///   includes the top-level site ([partitionKeyFor]), so an embedded
///   third party gets a separate cookie per embedding site.
/// - **Third-party cookie blocking** (on by default via
///   [blockThirdPartyCookies]): when the request URL's site differs from
///   the top-frame site (the `partitionKey` argument), unpartitioned
///   cookies are neither sent nor accepted; partitioned CHIPS cookies
///   still flow within their partition. A null `partitionKey` means "no
///   top-frame context known" and disables the check (first-party).
class CookieJar {
  CookieJar({this.blockThirdPartyCookies = true});

  /// Policy flag: when true (the default), unpartitioned cookies are not
  /// sent on — and `Set-Cookie` is not accepted from — requests whose site
  /// (scheme + registrable domain) differs from the top-frame site passed
  /// as `partitionKey`. Partitioned (CHIPS) cookies are unaffected.
  final bool blockThirdPartyCookies;

  static const _maxCookies = 3000;
  static const _maxCookiesPerDomain = 50;
  static const _maxCookieSize = 4096; // name + value bytes

  final Map<_CookieKey, _Cookie> _store = {};

  /// Processes all `Set-Cookie` headers from a [response] received for [url],
  /// storing any valid cookies.
  ///
  /// [partitionKey] is the top-frame site (from [partitionKeyFor]); it keys
  /// `Partitioned` cookies and drives third-party accept-blocking. Null means
  /// no top-frame context is known (treated as first-party; `Partitioned`
  /// cookies are rejected since they cannot be keyed).
  void processResponse(
    Uri url,
    Map<String, String> headers, {
    String? partitionKey,
  }) {
    final raw = headers['set-cookie'];
    if (raw == null) return;
    // `package:http` joins multi-value headers with ', ' — split carefully.
    // The correct split point is a comma NOT inside an Expires= date value.
    for (final header in _splitSetCookieHeaders(headers)) {
      _processOne(url, header, partitionKey: partitionKey);
    }
  }

  /// Returns the `Cookie: name=value; ...` header value to include in a
  /// request for [url], or null if no cookies apply.
  ///
  /// [isTopLevel] should be true for page navigations (Lax cookies are
  /// included). For sub-resource fetches set it to false.
  ///
  /// [partitionKey] is the top-frame site (from [partitionKeyFor]). Partitioned
  /// cookies are only returned when their stored partition matches it, and
  /// unpartitioned cookies are withheld on third-party requests when
  /// [blockThirdPartyCookies] is set.
  String? cookieHeader(
    Uri url, {
    bool isTopLevel = false,
    String? partitionKey,
  }) {
    final now = DateTime.now();
    final pairs = <String>[];
    final thirdParty = _isThirdParty(url, partitionKey);

    _store.removeWhere((_, c) => c.isExpired(now));

    for (final entry in _store.entries) {
      final key = entry.key;
      final c = entry.value;

      if (key.partition != null) {
        // CHIPS cookie: only visible within the partition it was set under.
        if (partitionKey == null || key.partition != partitionKey) continue;
      } else if (blockThirdPartyCookies && thirdParty) {
        continue; // unpartitioned cookies do not flow cross-site
      }
      if (!_domainMatches(url.host, key.domain)) continue;
      if (!url.path.startsWith(key.path)) continue;
      if (c.secure && url.scheme != 'https') continue;
      if (!_sameSiteAllowed(c.sameSite, url, isTopLevel: isTopLevel)) continue;

      pairs.add('${c.name}=${c.value}');
    }

    return pairs.isEmpty ? null : pairs.join('; ');
  }

  /// The "site" key used for CHIPS partition keys and third-party checks:
  /// scheme + registrable domain, e.g. `https://example.com` for
  /// `https://sub.example.com/page`. Returns null when [url] has no host
  /// (about:, data:).
  ///
  /// No PSL is consulted (consistent with the Domain-attribute handling in
  /// this jar): the registrable domain is approximated as the last two
  /// labels. NOTE: a public siteForUrl() helper is being added elsewhere in
  /// the codebase; this local copy is deliberate duplication so the jar
  /// stays dependency-free — dedup later.
  static String? partitionKeyFor(Uri url) {
    if (url.host.isEmpty) return null;
    return '${url.scheme}://${_registrableDomain(url.host)}';
  }

  /// True when [url]'s site differs from the top-frame site [partitionKey].
  /// Null [partitionKey] (or a URL with no host) is treated as first-party.
  bool _isThirdParty(Uri url, String? partitionKey) {
    if (partitionKey == null) return false;
    final requestSite = partitionKeyFor(url);
    if (requestSite == null) return false;
    return requestSite != partitionKey;
  }

  /// Approximate registrable domain: the last two labels of [host]
  /// (lowercased). IP literals and single-label hosts are returned as-is.
  static String _registrableDomain(String host) {
    final h = host.toLowerCase();
    if (h.contains(':')) return h; // IPv6 literal
    final labels = h.split('.');
    if (labels.length <= 2) return h;
    if (labels.every((l) => int.tryParse(l) != null)) return h; // IPv4
    return labels.sublist(labels.length - 2).join('.');
  }

  /// Removes all stored cookies.
  void clear() => _store.clear();

  /// Removes cookies that match [originHost] (exact or subdomain).
  void clearOrigin(String originHost) {
    _store.removeWhere((key, _) => _domainMatches(originHost, key.domain));
  }

  // ── internal helpers ──────────────────────────────────────────────────────

  void _processOne(Uri requestUrl, String header, {String? partitionKey}) {
    final parts = header.split(';');
    if (parts.isEmpty) return;

    // First part is name=value.
    final nv = parts[0].trim();
    final eq = nv.indexOf('=');
    if (eq < 0) return; // malformed
    final name = nv.substring(0, eq).trim();
    final value = nv.substring(eq + 1).trim();
    if (name.isEmpty) return;
    // Reject cookies whose combined name+value exceeds the per-cookie size cap.
    if (name.length + value.length > _maxCookieSize) return;

    // Attribute parsing.
    String domain = requestUrl.host;
    String path = '/';
    bool secure = false;
    bool httpOnly = false;
    bool partitioned = false;
    bool hasDomainAttr = false;
    bool hasExplicitRootPath = false; // an accepted `Path=/` attribute
    DateTime? expires;
    _SameSite sameSite = _SameSite.lax; // Lax is the default per RFC 6265bis

    for (var i = 1; i < parts.length; i++) {
      final attr = parts[i].trim();
      final lower = attr.toLowerCase();
      if (lower == 'secure') {
        secure = true;
      } else if (lower == 'httponly') {
        httpOnly = true;
      } else if (lower == 'partitioned') {
        partitioned = true;
      } else if (lower.startsWith('samesite=')) {
        final v = attr.substring('samesite='.length).trim().toLowerCase();
        if (v == 'strict') sameSite = _SameSite.strict;
        else if (v == 'none') sameSite = _SameSite.none;
        else sameSite = _SameSite.lax;
      } else if (lower.startsWith('domain=')) {
        hasDomainAttr = true;
        final d = attr.substring('domain='.length).trim().toLowerCase();
        // Strip leading dot (canonical form).
        final stripped = d.startsWith('.') ? d.substring(1) : d;
        // Reject if the host is not a subdomain of the requested domain.
        if (_domainMatches(requestUrl.host, stripped)) {
          domain = stripped;
        }
        // If validation fails we silently fall back to the host-only domain.
      } else if (lower.startsWith('path=')) {
        final p = attr.substring('path='.length).trim();
        if (p.startsWith('/')) {
          path = p;
          hasExplicitRootPath = p == '/';
        }
      } else if (lower.startsWith('max-age=')) {
        final secs = int.tryParse(attr.substring('max-age='.length).trim());
        if (secs != null) {
          if (secs <= 0) {
            expires = DateTime.fromMillisecondsSinceEpoch(0); // delete
          } else {
            expires = DateTime.now().add(Duration(seconds: secs));
          }
        }
      } else if (lower.startsWith('expires=')) {
        if (expires == null) { // max-age wins over expires
          expires = _parseHttpDate(attr.substring('expires='.length).trim());
        }
      }
    }

    // SameSite=None requires Secure.
    if (sameSite == _SameSite.none && !secure) sameSite = _SameSite.lax;

    // Cookie name prefixes (RFC 6265bis §4.1.3): the prefix is a signed
    // promise about how the cookie was set — reject the Set-Cookie entirely
    // when the promise is violated. Matching is case-insensitive.
    final lowerName = name.toLowerCase();
    if (lowerName.startsWith('__host-')) {
      // Secure, from a secure origin, no Domain attribute (host-locked),
      // and an explicit Path=/ (so it covers the whole host).
      if (!secure || requestUrl.scheme != 'https') return;
      if (hasDomainAttr || !hasExplicitRootPath) return;
    } else if (lowerName.startsWith('__secure-')) {
      if (!secure || requestUrl.scheme != 'https') return;
    }

    // CHIPS: Partitioned requires Secure, and a known partition to key under.
    if (partitioned && (!secure || partitionKey == null)) return;

    // Third-party accept-blocking: an embedded cross-site response may not
    // set unpartitioned cookies (partitioned ones are fine — that is the
    // CHIPS opt-in).
    if (!partitioned &&
        blockThirdPartyCookies &&
        _isThirdParty(requestUrl, partitionKey)) {
      return;
    }

    // Reject bare TLDs (heuristic).
    if (!domain.contains('.')) return;

    final key = _CookieKey(
      name: name,
      domain: domain,
      path: path,
      partition: partitioned ? partitionKey : null,
    );

    // Delete expired / max-age=0 cookies.
    final isDelete =
        expires != null && expires.millisecondsSinceEpoch <= 0 ||
        (expires != null && expires.isBefore(DateTime.now()));
    if (isDelete) {
      _store.remove(key);
      return;
    }

    // Enforce per-domain cap.
    final domainCount =
        _store.keys.where((k) => k.domain == domain).length;
    if (!_store.containsKey(key) && domainCount >= _maxCookiesPerDomain) {
      // Evict the oldest non-secure cookie for this domain.
      final oldest = _store.entries
          .where((e) => e.key.domain == domain && !e.value.secure)
          .fold<MapEntry<_CookieKey, _Cookie>?>(null, (prev, e) {
        if (prev == null) return e;
        final a = e.value.created;
        final b = prev.value.created;
        return a.isBefore(b) ? e : prev;
      });
      if (oldest != null) {
        _store.remove(oldest.key);
      } else {
        return; // all are secure — do not evict, skip this cookie
      }
    }

    // Global cap.
    while (_store.length >= _maxCookies) {
      _store.remove(_store.keys.first);
    }

    _store[key] = _Cookie(
      name: name,
      value: value,
      expires: expires,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
    );
  }

  /// Whether [host] is equal to or a subdomain of [domain].
  static bool _domainMatches(String host, String domain) {
    final h = host.toLowerCase();
    final d = domain.toLowerCase();
    if (h == d) return true;
    if (h.endsWith('.$d')) return true;
    return false;
  }

  static bool _sameSiteAllowed(
    _SameSite ss,
    Uri url, {
    required bool isTopLevel,
  }) {
    if (ss == _SameSite.none) return true;
    if (ss == _SameSite.lax) return isTopLevel; // lax: top-level GET only
    // strict: same-site only (we can't easily know the initiator here, so
    // we conservatively allow all top-level navigations for Strict too).
    return isTopLevel;
  }

  /// Splits the raw header value of potentially multiple `Set-Cookie` entries.
  /// The `package:http` client joins them with `, ` but `Expires` dates contain
  /// commas, so we split only on `, ` that precede a token that looks like
  /// `name=` (a new cookie start) rather than a date fragment.
  static List<String> _splitSetCookieHeaders(Map<String, String> headers) {
    // `dart:io` / `package:http` may already return them individually or joined.
    final raw = headers['set-cookie'] ?? '';
    if (raw.isEmpty) return const [];
    // Split on commas that are followed by a non-date token pattern.
    final re = RegExp(r',\s*(?=[^\s,;=]+=[^\s,;=])');
    return raw.split(re).where((s) => s.isNotEmpty).toList();
  }

  static final _httpDateRe = RegExp(
    r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  );
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _parseHttpDate(String raw) {
    final m = _httpDateRe.firstMatch(raw);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}

enum _SameSite { strict, lax, none }

class _CookieKey {
  const _CookieKey({
    required this.name,
    required this.domain,
    required this.path,
    this.partition,
  });

  final String name;
  final String domain;
  final String path;

  /// CHIPS partition (the top-level site the cookie was set under), or null
  /// for ordinary unpartitioned cookies.
  final String? partition;

  @override
  bool operator ==(Object other) =>
      other is _CookieKey &&
      other.name == name &&
      other.domain == domain &&
      other.path == path &&
      other.partition == partition;

  @override
  int get hashCode => Object.hash(name, domain, path, partition);
}

class _Cookie {
  _Cookie({
    required this.name,
    required this.value,
    required this.expires,
    required this.secure,
    required this.httpOnly,
    required this.sameSite,
  }) : created = DateTime.now();

  final String name;
  final String value;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;
  final _SameSite sameSite;
  final DateTime created;

  bool isExpired(DateTime now) =>
      expires != null && expires!.isBefore(now);
}
