# L224 — Browser: ad and tracker blocking on every request

| field | value |
|---|---|
| category | library / Library |
| score | 0.95 of 1 |
| queue position | 185 of 212 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> PART: e.net.fetch.Config.block_hosts and allow_hosts (from e.net.policy.parse_filter_list: ||host^ rules and @@||host^ exceptions) refuse any request that has a referrer (a subresource) to a listed host or its subdomains with BlockedByFilter before connecting, count them in Client.blocked, never filter the document, and an empty list blocks nothing; examples/browser reads an optional neper-browser.filters list; net_fetch_filter pins listed host, subdomain, unlisted host, document, exception and no list. `$third-party` rules block only requests from another site (hosts equal or one a subdomain of the other count as one site) and page.blocked_count reports the refusals since a page began loading; net_fetch_filter pins both. Request-type options (`$script`, `$image`, `$stylesheet`, `$xhr`, `$font`, `$document`, and `~type` negations) apply too: Request.dest is set by the page for script, stylesheet, image, font and xhr fetches and a typed rule blocks only those types (net_fetch_filter pins script-only, ~image and untyped). `$domain=a.com|~b.com` limits a rule to pages on the listed domains (net_fetch_filter pins listed, unlisted and excluded pages). `||host/path^` limits a rule to URLs under that path (net_fetch_filter pins both). Still open: a profile switch to turn blocking off. e.net.policy already parses Adblock Plus filter lists (parse_filter_list). Nothing applies them when a page loads. Acceptance: e.web.page asks the parsed rules before each subresource and script fetch (document, script, image, stylesheet, xhr, font types and the third-party flag known to the loader), a blocked request fails as blocked and is counted per page, the main document is never blocked, rules load from the profile and can be switched off, and a fixture with a blocked tracker script, an allowed first-party script and an exception rule pins all three outcomes.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
