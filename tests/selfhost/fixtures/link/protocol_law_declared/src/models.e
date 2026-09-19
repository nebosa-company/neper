// Two declared strategy pairs: Key obeys equal-implies-equal-hash while Broken
// deliberately includes ignored data in its hash, so the property harness must
// distinguish a real contract violation from a passing implementation.

type Key = struct { id: u64, ignored: u64 }

fn key_eq(a: Key, b: Key) -> bool { ret a.id == b.id }
fn key_hash(value: Key) -> u64 { ret value.id *% 11400714819323198485u64 }

type Broken = struct { id: u64, ignored: u64 }

fn broken_eq(a: Broken, b: Broken) -> bool { ret a.id == b.id }
fn broken_hash(value: Broken) -> u64 { ret value.id ^ value.ignored }
