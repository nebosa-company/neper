# M2.5 H07 closure: error detail and partial failure

This is H07's closure record (D659). The checked standard-library path returns a
portable `err`, preserves every documented partial result, and writes richer failure
provenance into caller-owned `os.ErrorDetail` at the operation that failed. The
legacy temporal `os.last_error_detail` remains only as the M2 compatibility path.

## Selected design and alternatives

Path-taking `e.os`, `e.fs` and `e.proc` calls take an `*os.ErrorDetail`; byte I/O
uses `os.read_detail` and `os.write_detail`. Generic streams use additive
`io.DetailReader` and `io.DetailWriter` callback types so native or library
provenance crosses adapters without changing the established `Reader`/`Writer` ABI.
Successful operations and end-of-stream leave the caller's value unchanged.

Exceptions and process-global messages were rejected because they obscure ordinary
`err` propagation and ownership. Replacing the existing callback structs would have
forced every stream and codec through an ABI migration for optional evidence. Reading
ambient host state inside generic adapters was rejected because another failure or
thread can change it. Native code zero identifies a library-originated limit,
no-progress or allocation failure rather than pretending it came from the host.

## Normative behavior and implementation

`spec.md` section 5 defines cleanup precedence, borrowed labels, checked host byte
I/O and exact outputs on failure. `module-apis.md` owns the additive `e.io` surface.
The implementation is split deliberately:

- `lib/e/os.windows.e` and `lib/e/os.linux.e` capture native read/write provenance
  directly (D614), while path calls and their `e.fs`/`e.proc` wrappers are D417,
  D443, D479 and D480;
- `lib/e/io.e` retains an accepted buffered prefix exactly once (D655), carries
  caller-owned detail through reader and writer callbacks (D656-D657), and preserves
  nested data-plus-error, copy progress and failed allocation steps (D658);
- allocation-backed detail constructors reset to their entry mark on either failed
  allocation, and `read_all_detail` distinguishes a hard limit from arena exhaustion.

`operation` and `subject` are borrowed labels. The caller keeps any dynamic label
storage alive while reading the detail. A consuming resource call still consumes on
success or failure as section 5 specifies; detail transport does not create a retry
right or a second ownership identity.

## Compatibility

The plain `Reader`, `Writer` and M2 `last_error_detail` declarations are unchanged.
The detail stream family is additive, so existing source and callback layouts remain
valid. Importers observe the new `e.io` Interface hash and rebuild normally; `.em`
format 11 needs no further bump because no existing artifact field or ABI meaning was
reinterpreted.

## Evidence and measurements

`link/error_detail` runs on Windows and Linux and covers a primary failure followed by
failed cleanup, direct and nested wrappers, caller values surviving later failures,
concurrent read/write failures, checked generic file adapters and a buffered native
failure. `link/io_streams` covers partial write plus retry without duplication,
detail-aware copy, success without detail clobbering, and rollback at both the state
and buffer allocation steps. The process fixture covers nested spawn/pipe provenance;
the compiler's constrained-arena fixture covers its own allocation-exhaustion path.

The unchanged `io_printf` workload remained 130,048 bytes on Windows. On Linux it
changed from 127,584 to 127,848 bytes (+264 bytes) because `write_all` now retains its
accepted-prefix count. Detail-only functions remain absent from programs that do not
reach them by ordinary dead-function elimination; no existing callback gains a field
or an extra runtime argument.

The eight-worker sc500k static gate records the compiler-side declaration cost:
Windows debug arena high-water is 2,285 MB (+1 MB), release remains 2,990 MB and both
images are unchanged; Linux debug remains 2,283 MB with a 272-byte image increase,
while release is 2,989 MB (+1 MB) with a 192-byte image increase. D659 explicitly
re-pins those deterministic cells.

H07 is closed for the delivered checked CPU surface. Plain legacy callbacks still
return only `err` by design; a caller requiring provenance selects the additive detail
type. One `ErrorDetail` describes the terminal failure returned by an operation, not a
history of multiple independent failures.
