/// Classifies a host as loopback / private / link-local (the user's own machine
/// or local network), so the engine can block page-initiated sub-resource
/// requests from a *public* page to such hosts — stopping web pages from
/// probing or attacking local services and LAN devices (SSRF, local-network
/// scanning, CSRF-to-router). This is on the secure-by-default path.
///
/// IP literals + `localhost` only. Hostnames that *resolve* to private IPs
/// (DNS-rebinding) need a connect-time check against the resolved address — a
/// deeper follow-up at the HTTP-client layer.
bool isPrivateNetworkHost(String host) {
  if (host.isEmpty) return false;
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost')) return true;

  // Strip IPv6 brackets: [::1] -> ::1.
  final bare = h.startsWith('[') && h.endsWith(']')
      ? h.substring(1, h.length - 1)
      : h;

  final v4 = _parseIpv4(bare);
  if (v4 != null) return _isPrivateV4(v4);

  // IPv6: loopback (::1), unique-local (fc00::/7 → fc/fd), link-local (fe80::/10).
  if (bare == '::1') return true;
  if (bare.startsWith('fc') || bare.startsWith('fd')) return true;
  if (bare.startsWith('fe8') ||
      bare.startsWith('fe9') ||
      bare.startsWith('fea') ||
      bare.startsWith('feb')) {
    return true;
  }
  return false;
}

/// Parses dotted-quad IPv4 into 4 octets, or null if not a plain IPv4 literal.
List<int>? _parseIpv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final p in parts) {
    if (p.isEmpty || p.length > 3) return null;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    octets.add(n);
  }
  return octets;
}

bool _isPrivateV4(List<int> o) {
  final a = o[0], b = o[1];
  if (a == 0) return true; // 0.0.0.0/8 ("this network")
  if (a == 127) return true; // loopback
  if (a == 10) return true; // 10/8
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16/12
  if (a == 192 && b == 168) return true; // 192.168/16
  if (a == 169 && b == 254) return true; // link-local
  return false;
}
