# x.cloud.awssdk — 47 of 47 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/awssdk.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/awssdk.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn join(a: *mem.Arena, x: str, y: str) -> str
fn text(s: str) -> json.Value
fn obj(a: *mem.Arena) -> ir.Obj
fn managed_key() -> str
fn name_key() -> str
fn resource_error(a: *mem.Arena, logical_id: str, message: str) -> str
fn validate_bucket_name(a: *mem.Arena, name: str) -> (bool, str)
fn attr_bool(attrs: json.Value, key: str) -> bool
fn attr_str(attrs: json.Value, key: str) -> (str, bool)
fn user_tags(a: *mem.Arena, attrs: json.Value) -> json.Value
fn hex_value(c: u8) -> i32
fn continuation(b: u8, low: u8, high: u8) -> bool
fn utf8_step(s: str, at: usize) -> i64
fn lossy(a: *mem.Arena, bytes: str) -> str
fn percent_decode(a: *mem.Arena, s: str) -> str
fn assume_role_json(a: *mem.Arena, attrs: json.Value, name: str) -> (str, bool, str)
fn pair(a: *mem.Arena, k: str, v: str) -> json.Value
fn managed_iam_tags(a: *mem.Arena, name: str, user: json.Value) -> json.Value
fn desired_arns(a: *mem.Arena, attrs: json.Value) -> []const str
fn string_list(a: *mem.Arena, attrs: json.Value, key: str) -> []const str
fn attr_i64(attrs: json.Value, key: str) -> (i64, bool)
fn managed_tags(a: *mem.Arena, name: str, user: json.Value) -> json.Value
fn tag_key(tags: []const json.Value, at: usize) -> (str, bool)
fn tag_value(tags: []const json.Value, at: usize) -> (str, bool)
fn observed_user_tags(a: *mem.Arena, tags: json.Value) -> json.Value
fn items(v: json.Value) -> []const json.Value
fn petcow_name(tags: json.Value) -> (str, bool)
fn name_or_id(tags: json.Value, real_id: str) -> str
fn unmanaged(a: *mem.Arena, type_: str, tags: json.Value, real_id: str) -> json.Value
fn wrap_i32(v: i64) -> i64
fn ingress_permissions(a: *mem.Arena, name: str, attrs: json.Value) -> (json.Value, bool, str)
fn int_text(a: *mem.Arena, v: i64) -> str
fn lightsail_type_name(kind: str) -> str
fn req_attr(a: *mem.Arena, attrs: json.Value, key: str, kind: str) -> (str, bool, str)
fn lightsail_managed_tags(a: *mem.Arena, name: str) -> json.Value
fn ls_text(v: json.Value, key: str) -> (str, bool)
fn ls_nested(v: json.Value, outer: str, key: str) -> (str, bool)
fn ls_put(o: *ir.Obj, key: str, value: str, has: bool)
fn ls_observed(a: *mem.Arena, type_: str, name: str, attributes: json.Value, arn: str, has_arn: bool) -> json.Value
fn ls_instance(a: *mem.Arena, item: json.Value) -> (json.Value, bool)
fn ls_database(a: *mem.Arena, item: json.Value) -> (json.Value, bool)
fn ls_domain(a: *mem.Arena, item: json.Value) -> (json.Value, bool)

type LsPage = struct { good: bool, failure: str, items: []const json.Value, has_next: bool, next: str }
type LsSource = struct { ctx: *void, page: fn(*void, str, bool) -> LsPage }

fn ls_one(a: *mem.Arena, kind: str, item: json.Value) -> (json.Value, bool)
fn ls_list(a: *mem.Arena, kind: str, src: *const LsSource) -> (json.Value, bool, str)
fn ls_filter(a: *mem.Arena, observed: json.Value, managed: bool) -> json.Value
```

The pure mapping of Petcow's native AWS providers (L048), after `provider/aws/{s3,iam,ec2,lightsail}.rs`: the S3 bucket-name rules and `bool`, `str` and `tags` attributes, the IAM inline-policy percent-decoding (a malformed byte replaced as `from_utf8_lossy` does), `assume_role_json` (a string passes through, anything else is compact JSON in member order, a missing one is an error), the managed tag lists and sorted `managed_policy_arns`, the EC2 managed tags, user tags read back, PetCow name, display name of an unmanaged resource and integer and string-list attributes, the security-group ingress rules (ports cast to 32 bits as the original does), and the Lightsail type names, required attributes and identity tags. Tags are `[key, value]` pairs. The Lightsail list mapping (D3400) reads the SDK's wire JSON (`instances`, `relationalDatabases`, `domains`, `nextPageToken`): `ls_instance`, `ls_database` and `ls_domain` give the observed resource of one item (an item without a name is skipped, a missing member is not an attribute, a domain's records are `type name -> target` lines with their count), `ls_list` follows page tokens through an injected `LsSource` as `list_instances` does (a domain list is one call, a failed call is `in resource '<type>': <call>: <error>`), and `ls_filter` keeps the `petcow-` names for `discover` or the rest for `discover_unmanaged`. The SDK calls are host code. Checked against Petcow's own functions, extracted unchanged behind thin shims for the SDK builders, over 600 inputs on Windows (D2922), and the list mapping over 62 more (D3400).

## Missing declarations

- [ ] `join`
- [ ] `text`
- [ ] `obj`
- [ ] `managed_key`
- [ ] `name_key`
- [ ] `resource_error`
- [ ] `validate_bucket_name`
- [ ] `attr_bool`
- [ ] `attr_str`
- [ ] `user_tags`
- [ ] `hex_value`
- [ ] `continuation`
- [ ] `utf8_step`
- [ ] `lossy`
- [ ] `percent_decode`
- [ ] `assume_role_json`
- [ ] `pair`
- [ ] `managed_iam_tags`
- [ ] `desired_arns`
- [ ] `string_list`
- [ ] `attr_i64`
- [ ] `managed_tags`
- [ ] `tag_key`
- [ ] `tag_value`
- [ ] `observed_user_tags`
- [ ] `items`
- [ ] `petcow_name`
- [ ] `name_or_id`
- [ ] `unmanaged`
- [ ] `wrap_i32`
- [ ] `ingress_permissions`
- [ ] `int_text`
- [ ] `lightsail_type_name`
- [ ] `req_attr`
- [ ] `lightsail_managed_tags`
- [ ] `ls_text`
- [ ] `ls_nested`
- [ ] `ls_put`
- [ ] `ls_observed`
- [ ] `ls_instance`
- [ ] `ls_database`
- [ ] `ls_domain`
- [ ] `LsPage`
- [ ] `LsSource`
- [ ] `ls_one`
- [ ] `ls_list`
- [ ] `ls_filter`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/awssdk.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_awssdk/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 47.

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
