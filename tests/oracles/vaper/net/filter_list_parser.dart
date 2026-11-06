/// Parses Adblock Plus / EasyList filter list syntax into two rule sets:
/// network rules (domain blocklist) and cosmetic rules (CSS selector hiders).
///
/// Supports:
///   `||domain.com^`       → block all requests to domain.com (any subdomain).
///   `##.selector`         → cosmetic: hide elements matching .selector (global).
///   `###id`               → cosmetic: hide elements matching #id (global).
///   Lines starting with `!` or `[Adblock` → comments/header, ignored.
///   Exception rules (`@@`) → ignored (safe to skip for now).
///   Site-specific cosmetic rules (`example.com##.selector`) → ignored (out of scope).
class FilterListParser {
  /// Parses [text] and returns a [FilterListRules] containing all rules.
  static FilterListRules parse(String text) {
    final domains = <String>{};
    final cosmetic = <String>{};

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) continue; // comment
      if (line.startsWith('[Adblock')) continue; // header
      if (line.startsWith('@@')) continue; // exception — skip

      // Cosmetic rule: `##.selector` (global hide rule).
      // Site-specific rules like `example.com##.selector` are out of scope
      // and intentionally ignored — only universal rules (no site prefix) are
      // applied, meaning the line must start with `##`.
      if (line.startsWith('##')) {
        final selector = line.substring(2).trim();
        if (selector.isNotEmpty && !selector.startsWith('+js(')) {
          cosmetic.add(selector);
        }
        continue;
      }

      // Network rule: `||host.com^` or `||host.com^$options`.
      if (line.startsWith('||')) {
        var end = line.indexOf('^', 2);
        if (end == -1) end = line.length;
        final host = line.substring(2, end).toLowerCase().trim();
        // Reject patterns with path or regex characters (/ ? * [ — leave them to a future engine).
        if (host.isNotEmpty &&
            !host.contains('/') &&
            !host.contains('*') &&
            !host.contains('[')) {
          domains.add(host);
        }
        continue;
      }
    }

    return FilterListRules(
      networkDomains: domains,
      cosmeticSelectors: cosmetic,
    );
  }
}

/// The parsed output of one or more filter lists.
class FilterListRules {
  FilterListRules({
    required this.networkDomains,
    required this.cosmeticSelectors,
  });

  /// Domains (and their subdomains) to block in network requests.
  final Set<String> networkDomains;

  /// CSS selectors whose matching elements should be hidden (display:none).
  final Set<String> cosmeticSelectors;

  /// Merges [other] into this set (mutates in place).
  void merge(FilterListRules other) {
    networkDomains.addAll(other.networkDomains);
    cosmeticSelectors.addAll(other.cosmeticSelectors);
  }
}
