/**
 * Refusing to fetch the inside of our own network.
 *
 * The automation worker's `http` step took a URL straight from an automation's
 * config — user-authored — and called `fetch()` on it, from **inside the
 * compose network**. Nothing validated it.
 *
 * That was arbitrary SQL as a database superuser, reachable by any user who
 * could create an automation. Verified from the worker container:
 *
 *     POST http://meta:8080/query  {"query":"select current_user, ..."}
 *     → [{"current_user":"supabase_admin","users":2}]
 *
 * `postgres-meta` has no authentication of its own; it does not need any,
 * because it is not published — the compose network *was* its boundary. So a
 * feature working exactly as designed handed an app editor the whole database:
 * every tenant's records, realm ownership, RLS itself.
 *
 * Outbound webhook URLs are user-authored too and go through the same guard.
 *
 * ## Why the check is on the resolved ADDRESS, not the hostname
 *
 * Blocking the names — `meta`, `db`, `localhost` — is the obvious fix and it
 * does not work. `http://127.0.0.1`, `http://[::1]`, `http://2130706433`
 * (127.0.0.1 as an integer) and any public DNS name with an A record pointing
 * at 10.x all defeat a name blocklist. Resolving first and judging the address
 * catches the whole class, including a hostname somebody controls that simply
 * answers with a private IP.
 *
 * ## DNS rebinding, and why this file now returns the addresses
 *
 * On its own this check does not close rebinding: the name can resolve
 * differently between the check and the fetch, which turns a one-line attack
 * into a race rather than removing it. That was recorded here as open for two
 * releases on the reading that pinning "needs the connection pinned to the
 * checked address, which Node's fetch does not expose" — true of `fetch`, and
 * not true of `node:http`, whose `lookup` option is handed straight to
 * `net.connect`.
 *
 * So a verdict now carries `addresses`: exactly the answers this check
 * approved. `io/pinned-fetch.js` connects to one of those and to nothing
 * else, so the address that was judged is the address that is dialled.
 */

/** Parse an IPv4 dotted quad to a 32-bit integer, or null. */
function ipv4ToInt(value) {
  const parts = String(value).split('.');
  if (parts.length !== 4) return null;
  let out = 0;
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    const n = Number(part);
    if (n > 255) return null;
    out = out * 256 + n;
  }
  return out;
}

/**
 * Address ranges that must never be the target of a user-supplied fetch.
 * Named so a reader can see what each one is for.
 */
/** @type {[string, number, string][]} CIDR base, prefix bits, why. */
const BLOCKED_V4 = [
  ['0.0.0.0', 8, 'this network'],
  ['10.0.0.0', 8, 'private'],
  ['100.64.0.0', 10, 'carrier-grade NAT'],
  ['127.0.0.0', 8, 'loopback'],
  ['169.254.0.0', 16, 'link-local — cloud metadata lives here'],
  ['172.16.0.0', 12, 'private — the compose network'],
  ['192.0.0.0', 24, 'IETF protocol assignments'],
  ['192.168.0.0', 16, 'private'],
  ['198.18.0.0', 15, 'benchmarking'],
  ['224.0.0.0', 4, 'multicast'],
  ['240.0.0.0', 4, 'reserved'],
];

/** Is this literal IP address one we refuse to connect to? */
export function isBlockedAddress(ip) {
  const value = String(ip || '').trim().toLowerCase().replace(/^\[|\]$/g, '');
  if (!value) return true;

  // IPv6, including the ::ffff:127.0.0.1 form that smuggles v4 through a v6 check.
  if (value.includes(':')) {
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(value);
    if (mapped) return isBlockedAddress(mapped[1]);
    // The SAME address after normalisation. `new URL('http://[::ffff:127.0.0.1]')`
    // reports its hostname as `[::ffff:7f00:1]` — hex, not dotted — so a check
    // that only knows the dotted form passes loopback straight through.
    const hex = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(value);
    if (hex) {
      const n = (parseInt(hex[1], 16) << 16) + parseInt(hex[2], 16);
      return isBlockedAddress([n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join('.'));
    }
    if (value === '::' || value === '::1') return true;
    const head = value.split(':')[0];
    // fc00::/7 unique-local, fe80::/10 link-local.
    if (/^f[cd]/.test(head)) return true;
    if (/^fe[89ab]/.test(head)) return true;
    return false;
  }

  const addr = ipv4ToInt(value);
  if (addr === null) return true;   // not an address we can reason about
  return BLOCKED_V4.some(([base, bits]) => {
    const mask = bits === 0 ? 0 : (-1 << (32 - bits)) >>> 0;
    return (addr & mask) >>> 0 === (ipv4ToInt(base) & mask) >>> 0;
  });
}

/**
 * The IPv4 address an IPv6 literal is really carrying, or null.
 *
 * `::ffff:127.0.0.1` and `::ffff:7f00:1` are the same address written two
 * ways, and `new URL()` normalises to the second — so a caller that only
 * knows the dotted form is looking at loopback and does not recognise it.
 */
function mappedIpv4(value) {
  const dotted = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(value);
  if (dotted) return dotted[1];
  const hex = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(value);
  if (!hex) return null;
  const n = (parseInt(hex[1], 16) << 16) + parseInt(hex[2], 16);
  return [n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join('.');
}

/** Which rule blocked it, for an error message worth reading. */
export function blockReason(ip) {
  const value = String(ip || '').trim().toLowerCase().replace(/^\[|\]$/g, '');

  // IPv6 first, and unwrapped rather than lumped together. `isBlockedAddress`
  // has always refused these; `blockReason` did not understand them, so a
  // correct refusal of `::ffff:127.0.0.1` came back as the useless "is not a
  // public address" when the honest answer was "is loopback". The reason is
  // the part of the message the author can act on, so a blocked address that
  // cannot explain itself is a half-finished refusal.
  if (value.includes(':')) {
    const mapped = mappedIpv4(value);
    if (mapped) return blockReason(mapped);
    if (value === '::' || value === '::1') return 'loopback';
    const head = value.split(':')[0];
    if (/^f[cd]/.test(head)) return 'a unique-local address';
    if (/^fe[89ab]/.test(head)) return 'link-local — cloud metadata lives here';
    return 'not a public address';
  }

  const addr = ipv4ToInt(value);
  if (addr !== null) {
    for (const [base, bits, why] of BLOCKED_V4) {
      const mask = bits === 0 ? 0 : (-1 << (32 - bits)) >>> 0;
      if ((addr & mask) >>> 0 === (ipv4ToInt(base) & mask) >>> 0) return why;
    }
  }
  return 'not a public address';
}

/**
 * Check a user-supplied URL before fetching it.
 *
 * @param {string} url
 * @param {{lookup: (host: string) => Promise<string[]>}} deps DNS resolver,
 *   injected so this module stays pure and testable without a network.
 * @returns {Promise<{ok: true, url: URL, addresses: string[]}|{ok: false, error: string}>}
 *   `addresses` are the answers this call approved, for a caller that pins the
 *   connection to them. A literal address approves itself.
 */
/**
 * Everything the guard can decide WITHOUT a resolver.
 *
 * Split out because two callers need the same vocabulary from places with
 * very different capabilities. The worker can resolve a name and judge the
 * answer; a browser cannot resolve anything at all, and the dry-run preview
 * runs in a browser. Sharing this means a refusal reads identically wherever
 * it was decided — `refused: 127.0.0.1 is loopback` — instead of the preview
 * inventing a second, weaker set of words for the same verdict.
 *
 * @returns {{ok: false, error: string}
 *   | {ok: true, url: URL, addresses: string[]}
 *   | {ok: true, url: URL, host: string, resolved: false}}
 *   The third form means "nothing here is refusable without DNS". It is a
 *   deliberate non-answer, not an approval: see `checkOutboundUrlSync`.
 */
function judgeWithoutDns(url) {
  let parsed;
  try {
    parsed = new URL(String(url));
  } catch {
    return { ok: false, error: 'not a valid URL' };
  }

  // `file:`, `gopher:`, `ftp:` — and crucially not a scheme-relative or
  // internal one that fetch might still act on.
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return { ok: false, error: `refused: ${parsed.protocol} is not http or https` };
  }

  const host = parsed.hostname.toLowerCase().replace(/^\[|\]$/g, '');

  // A bare literal address needs no DNS and must be judged directly.
  if (/^[\d.]+$/.test(host) || host.includes(':')) {
    if (isBlockedAddress(host)) {
      return { ok: false, error: `refused: ${host} is ${blockReason(host)}` };
    }
    return { ok: true, url: parsed, addresses: [host] };
  }

  // A name with no dots is a container or a search-domain host — `meta`,
  // `db`, `kong`. Refused before DNS, because resolving it is the attack.
  if (!host.includes('.')) {
    return { ok: false, error: `refused: "${host}" is an internal hostname` };
  }

  // Two dotted names that DNS would answer honestly and we still refuse, so
  // that the answer is the same with a resolver and without one.
  //
  // `metadata.google.internal` resolves to 169.254.169.254 on GCP, so the
  // address check catches it there — and nowhere else. Naming it means the
  // preview refuses it on a laptop too, which is where an author writes the
  // step. `*.localhost` is required by RFC 6761 to resolve to loopback, so
  // the name is as good as the address.
  if (host === 'metadata.google.internal' || host.endsWith('.metadata.google.internal')) {
    return { ok: false, error: `refused: ${host} is the cloud metadata endpoint` };
  }
  if (host === 'localhost' || host.endsWith('.localhost')) {
    return { ok: false, error: `refused: ${host} is loopback` };
  }

  return { ok: true, url: parsed, host, resolved: false };
}

/**
 * The guard, minus the half that needs a network.
 *
 * For hosts that can be judged from the string alone — literal IPv4 and IPv6
 * (including the `::ffff:` mapped forms), dotless container names, the
 * metadata endpoint, `localhost` — this is the same verdict, in the same
 * words, that `checkOutboundUrl` would return.
 *
 * **It cannot judge a public-looking name.** `evil.example.com` with an A
 * record pointing at 169.254.169.254 returns `{ok: true, resolved: false}`
 * here, and only `checkOutboundUrl` will refuse it. That is why the value it
 * returns says `resolved: false` rather than just `ok: true`: a caller that
 * treats the two as the same thing has a hole, and one that reports the
 * caveat is telling the truth. The dry-run preview is the intended caller —
 * it makes no request, so an unjudged name reaches nothing; the live run goes
 * through the resolving guard before a socket is opened.
 */
export function checkOutboundUrlSync(url) {
  return judgeWithoutDns(url);
}

/**
 * @param {string} url
 * @param {{lookup?: Function}} [opts] `lookup` resolves a host to addresses;
 *   without it an unresolved host is refused rather than assumed safe.
 */
export async function checkOutboundUrl(url, { lookup } = {}) {
  // `judgeWithoutDns` returns one of three shapes — refused, decided from a
  // literal address, or "this is a name, resolve it". The third is the only
  // one that reaches the DNS path below, and the union does not narrow through
  // the `.addresses` truthiness test, so the shape is named once here.
  const literal = /** @type {{ok: boolean, url?: URL, addresses?: string[], host?: string, resolved?: false, error?: string}} */ (
    judgeWithoutDns(url)
  );
  if (!literal.ok || literal.addresses) return literal;
  const { url: parsed, host } = literal;

  if (!lookup) return { ok: false, error: 'refused: cannot resolve host to check it' };
  let addresses;
  try {
    addresses = await lookup(host);
  } catch {
    return { ok: false, error: `refused: ${host} did not resolve` };
  }
  if (!addresses || !addresses.length) {
    return { ok: false, error: `refused: ${host} did not resolve` };
  }
  // EVERY address must be public: one private answer among several is enough
  // to reach the inside, and which one gets used is not ours to choose.
  for (const addr of addresses) {
    if (isBlockedAddress(addr)) {
      return { ok: false, error: `refused: ${host} resolves to ${addr}, which is ${blockReason(addr)}` };
    }
  }
  return { ok: true, url: parsed, addresses: [...addresses] };
}
