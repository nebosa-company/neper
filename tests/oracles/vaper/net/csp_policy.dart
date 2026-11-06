/// Content Security Policy enforcement for Vaper.
///
/// Parses a `Content-Security-Policy` header value and answers whether a
/// given action is permitted. Enforces script-src, connect-src, img-src,
/// style-src, font-src (all with default-src fallback).
library;

/// A parsed CSP policy for one document.
class CspPolicy {
  factory CspPolicy.parse(String? header, {required String documentUrl}) {
    if (header == null) return empty;
    String? scriptSrc;
    String? connectSrc;
    String? imgSrc;
    String? styleSrc;
    String? fontSrc;
    String? defaultSrc;

    for (final directive in header.split(';')) {
      final parts = directive.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) continue;
      final name = parts.first.toLowerCase();
      final tokens = parts.skip(1).map((s) => s.toLowerCase()).toList();
      switch (name) {
        case 'script-src': scriptSrc = tokens.join(' ');
        case 'connect-src': connectSrc = tokens.join(' ');
        case 'img-src': imgSrc = tokens.join(' ');
        case 'style-src': styleSrc = tokens.join(' ');
        case 'font-src': fontSrc = tokens.join(' ');
        case 'default-src': defaultSrc = tokens.join(' ');
      }
    }

    return CspPolicy._(
      blocksScripts: (scriptSrc ?? defaultSrc) == "'none'",
      connectSources: _expand(connectSrc ?? defaultSrc, documentUrl),
      imgSources: _expand(imgSrc ?? defaultSrc, documentUrl),
      styleSources: _expand(styleSrc ?? defaultSrc, documentUrl),
      fontSources: _expand(fontSrc ?? defaultSrc, documentUrl),
    );
  }

  static const CspPolicy empty = CspPolicy._(
    blocksScripts: false,
    connectSources: null,
    imgSources: null,
    styleSources: null,
    fontSources: null,
  );

  const CspPolicy._({
    required this.blocksScripts,
    required this.connectSources,
    required this.imgSources,
    required this.styleSources,
    required this.fontSources,
  });

  final bool blocksScripts;
  final Set<String>? connectSources;
  final Set<String>? imgSources;
  final Set<String>? styleSources;
  final Set<String>? fontSources;

  /// True when [targetUrl] is blocked by connect-src (or default-src).
  bool blocksConnect(String targetUrl) =>
      _blockedBy(targetUrl, connectSources);

  /// True when [targetUrl] is blocked by img-src (or default-src).
  bool blocksImage(String targetUrl) => _blockedBy(targetUrl, imgSources);

  /// True when [targetUrl] is blocked by style-src (or default-src).
  bool blocksStyle(String targetUrl) => _blockedBy(targetUrl, styleSources);

  /// True when [targetUrl] is blocked by font-src (or default-src).
  bool blocksFont(String targetUrl) => _blockedBy(targetUrl, fontSources);

  bool _blockedBy(String targetUrl, Set<String>? sources) {
    if (sources == null) return false;
    if (sources.isEmpty) return true; // 'none'
    final target = Uri.tryParse(targetUrl);
    if (target == null || target.host.isEmpty) return true;
    if (sources.contains('${target.scheme}:')) return false; // scheme-source
    final targetOrigin = _normOrigin(targetUrl);
    for (final s in sources) {
      if (_sourceAllows(s, target, targetOrigin)) return false;
    }
    return true;
  }

  /// Whether a host-source [source] (`scheme://host[:port]`, host optionally a
  /// `*.domain` wildcard) permits [target]. An exact origin match short-circuits
  /// via [targetOrigin]; otherwise scheme + host (with `*.` subdomain matching)
  /// + optional port must line up.
  static bool _sourceAllows(String source, Uri target, String? targetOrigin) {
    if (targetOrigin != null && source == targetOrigin) return true;
    final si = source.indexOf('://');
    if (si < 0) return false; // scheme-source handled by the caller
    if (source.substring(0, si).toLowerCase() != target.scheme) return false;
    var hostPort = source.substring(si + 3);
    final slash = hostPort.indexOf('/');
    if (slash >= 0) hostPort = hostPort.substring(0, slash); // path is ignored
    String host;
    String? port;
    final colon = hostPort.lastIndexOf(':');
    if (colon > 0 && int.tryParse(hostPort.substring(colon + 1)) != null) {
      host = hostPort.substring(0, colon);
      port = hostPort.substring(colon + 1);
    } else {
      host = hostPort;
    }
    host = host.toLowerCase();
    final th = target.host.toLowerCase();
    final hostOk = host.startsWith('*.')
        ? (th == host.substring(2) || th.endsWith('.${host.substring(2)}'))
        : th == host;
    if (!hostOk) return false;
    if (port != null) {
      final tp = target.hasPort
          ? target.port
          : (target.scheme == 'https' ? 443 : 80);
      if (tp.toString() != port) return false;
    }
    return true;
  }

  static Set<String>? _expand(String? sources, String documentUrl) {
    if (sources == null) return null;
    final tokens = sources.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.contains('*')) return null;
    if (tokens.length == 1 && tokens.first == "'none'") return const {};
    final docOrigin = _normOrigin(documentUrl);
    final allowed = <String>{};
    for (final tok in tokens) {
      if (tok == "'self'" && docOrigin != null) {
        allowed.add(docOrigin);
      } else if (tok.startsWith('https:') || tok.startsWith('http:')) {
        if (tok.contains('://')) {
          // Keep host-sources as `scheme://host[:port]`, preserving a `*.`
          // wildcard (which `Uri`/`_normOrigin` would mangle) — path is dropped.
          var rest = tok.substring(tok.indexOf('://') + 3);
          final slash = rest.indexOf('/');
          if (slash >= 0) rest = rest.substring(0, slash);
          final scheme = tok.substring(0, tok.indexOf(':')).toLowerCase();
          if (rest.isNotEmpty) allowed.add('$scheme://${rest.toLowerCase()}');
        } else {
          allowed.add(tok);
        }
      }
    }
    return allowed;
  }

  static String? _normOrigin(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    final defaultPort = u.scheme == 'https' ? 443 : 80;
    final port = u.hasPort && u.port != defaultPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  }
}
