// Reference results for `e.net.policy` (L046): the HTTP cache, cookie jar, CORS, CSP, private-network and filter-list code
// of Vaper's engine over the inputs `policy_vectors.mjs` writes.
// Usage: dart run scripts/policy_reference.dart IN.json OUT.json
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/cookie_jar.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/cors.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/csp_policy.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/filter_list_parser.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/http_cache.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/private_network.dart';

Map<String, String> hdrs(dynamic m) => {for (final e in (m as Map<String, dynamic>).entries) e.key: e.value as String};
DateTime ms(dynamic v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt(), isUtc: true);

dynamic run(Map<String, dynamic> c) {
  switch (c['op']) {
    case 'cc':
      return parseCacheControl(c['value'] as String?);
    case 'cacheable':
      return httpIsCacheable((c['status'] as num).toInt(), hdrs(c['headers']));
    case 'freshness':
      final r = httpFreshness(hdrs(c['headers']), ms(c['created']), now: () => ms(c['now']));
      return {'fresh': r.fresh, 'must': r.mustRevalidate};
    case 'age':
      return httpCurrentAgeSeconds(hdrs(c['headers']), ms(c['created']), ms(c['now']));
    case 'lifetime':
      return httpFreshnessLifetimeSeconds(hdrs(c['headers']), now: () => ms(c['now']));
    case 'heuristic':
      return httpHeuristicLifetimeSeconds(hdrs(c['headers']), now: () => ms(c['now']));
    case 'stale':
      return httpCanServeStaleOnError(hdrs(c['headers']), ms(c['created']), now: () => ms(c['now']));
    case 'conditional':
      return conditionalHeaders(hdrs(c['headers']));
    case 'private':
      return isPrivateNetworkHost(c['host'] as String);
    case 'filters':
      final r = FilterListParser.parse(c['text'] as String);
      return {'domains': r.networkDomains.toList(), 'selectors': r.cosmeticSelectors.toList()};
    case 'csp':
      final p = CspPolicy.parse(c['header'] as String?, documentUrl: c['doc'] as String);
      final urls = (c['urls'] as List<dynamic>).cast<String>();
      return {
        'blocksScripts': p.blocksScripts,
        'connect': p.connectSources?.toList(),
        'img': p.imgSources?.toList(),
        'style': p.styleSources?.toList(),
        'font': p.fontSources?.toList(),
        'blocked': {
          'connect': [for (final u in urls) p.blocksConnect(u)],
          'image': [for (final u in urls) p.blocksImage(u)],
          'style': [for (final u in urls) p.blocksStyle(u)],
          'font': [for (final u in urls) p.blocksFont(u)],
        },
      };
    case 'safelisted':
      return isCorsSafelistedRequestHeader(c['name'] as String, c['value'] as String);
    case 'unsafe':
      return corsUnsafeHeaderNames(hdrs(c['headers']));
    case 'simple':
      return isSimpleCorsRequest(c['method'] as String, hdrs(c['headers']));
    case 'preflight':
      return corsPreflightBlockReason(
        documentOrigin: c['origin'] as String,
        method: c['method'] as String,
        unsafeHeaderNames: (c['unsafe'] as List<dynamic>).cast<String>(),
        statusCode: (c['status'] as num).toInt(),
        responseHeaders: hdrs(c['headers']),
        credentialed: c['credentialed'] as bool,
      );
    case 'response':
      return corsResponseBlockReason(documentOrigin: c['origin'] as String, responseHeaders: hdrs(c['headers']), credentialed: c['credentialed'] as bool);
    case 'serialize':
      return corsSerializeOrigin(c['url'] as String);
    case 'corp':
      return corpBlockReason(documentOrigin: c['doc'] as String?, resourceUrl: Uri.parse(c['url'] as String), corpHeader: c['corp'] as String?, embedderRequiresCorp: c['requires'] as bool);
    case 'nocors':
      return noCorsResponseBlockReason(documentOrigin: c['doc'] as String?, resourceUrl: Uri.parse(c['url'] as String), responseHeaders: hdrs(c['headers']), embedderRequiresCorp: c['requires'] as bool);
    case 'parse':
      final v = c['value'] as String?;
      return {'corp': parseCorp(v).name, 'coep': parseCoep(v).name, 'coop': parseCoop(v).name};
    case 'pcache':
      var now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final cache = CorsPreflightCache(now: () => now);
      final out = <dynamic>[];
      for (final s in (c['steps'] as List<dynamic>)) {
        final m = s as Map<String, dynamic>;
        now = ms(m['t']);
        switch (m['k']) {
          case 'store':
            cache.store(origin: m['origin'] as String, url: Uri.parse(m['url'] as String), responseHeaders: hdrs(m['headers']), credentialed: m['credentialed'] as bool);
            out.add(null);
          case 'allowed':
            out.add(cache.isAllowed(origin: m['origin'] as String, url: Uri.parse(m['url'] as String), method: m['method'] as String, unsafeHeaderNames: (m['unsafe'] as List<dynamic>).cast<String>(), credentialed: m['credentialed'] as bool));
          default:
            out.add(cache.size);
        }
      }
      return out;
    case 'jar':
      final jar = CookieJar(blockThirdPartyCookies: c['block'] as bool);
      final out = <dynamic>[];
      for (final s in (c['steps'] as List<dynamic>)) {
        final m = s as Map<String, dynamic>;
        switch (m['k']) {
          case 'set':
            jar.processResponse(Uri.parse(m['url'] as String), {'set-cookie': m['header'] as String}, partitionKey: m['pk'] as String?);
            out.add(null);
          case 'get':
            out.add(jar.cookieHeader(Uri.parse(m['url'] as String), isTopLevel: m['top'] as bool, partitionKey: m['pk'] as String?));
          case 'key':
            out.add(CookieJar.partitionKeyFor(Uri.parse(m['url'] as String)));
          case 'clearOrigin':
            jar.clearOrigin(m['host'] as String);
            out.add(null);
          default:
            jar.clear();
            out.add(null);
        }
      }
      return out;
  }
  throw 'unknown op ${c['op']}';
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <dynamic>[];
  for (final c in inputs) {
    try {
      out.add({'v': run(c as Map<String, dynamic>)});
    } catch (e) {
      out.add({'x': e.toString()});
    }
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
