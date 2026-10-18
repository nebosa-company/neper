# L164 — gRPC remainder: server side, deadlines and stubs from .proto descriptors

| field | value |
|---|---|
| category | library / Library |
| score | 0.95 of 1 |
| queue position | 72 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from L101 (D2646): e.net.http2 and the e.net.grpc client protocol exist and are checked against hpack/h2 and recorded grpcio transcripts. Acceptance: (1) a server side over e.net.http2 (unary, then streaming); (2) deadlines, retries and message compression; (3) the gRPC-over-HTTP/3 binding on e.net.http3 frames; (4) a TLS dial helper; (5) stub generation from .proto descriptors (e.fmt.protobuf needs a descriptor reader first) with typed request and response messages. PART (D2923): e.net.grpcserver (preface, SETTINGS, HPACK, flow control, request events, flow-controlled responses, trailers-only, deadlines, resets) and e.net.grpccodec (gzip/deflate/identity decompression) checked with grpcio against a live loopback server (14 calls). NOT DONE: retries and backoff, gRPC over HTTP/3, a TLS dial helper, send-side compression wiring, stub generation (e.fmt.protobuf has no descriptor reader). PART (D3004-D3008): send-side compression (net_grpccompress, decoded by Python gzip/zlib), e.fmt.protodesc descriptor reader (32 cases vs protobuf MessageToDict), typed stubs e.fmt.protomsg/e.net.grpcstub (242 Python-serialised instances round trip), e.net.grpcretry (gRFC A6 vs a Python model), e.net.grpctls dial helper. Missing: gRPC over HTTP/3, retry wired into a transport loop, hedging, perAttemptRecvTimeout. PART (D3401): e.net.grpccall retry and hedging loop over e.net.grpc with deadline and per-attempt timeout; net_grpccall 331 runs, 60 against live grpcio, 271 against an independent A6 model. Missing: HTTP/3, transparent retries, a socket run; per_attempt_ns has no live oracle. PART (D4601): transparent retries (REFUSED_STREAM reset, GOAWAY below the stream id) first one per call, not counted or throttled; net_grpccall 401 cases (41 goaway scripts agree with live grpcio; the REFUSED_STREAM half is the gRFC model, grpcio treats it as UNAVAILABLE); 15/15 loopback socket scenarios agree with the model. Missing: HTTP/3 (no oracle), hedging combined with transparent retry has no vector, per_attempt_ns has no grpcio oracle.

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
