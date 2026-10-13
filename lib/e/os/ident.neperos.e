// `e.os.ident` on NeperOS (C107, D4704): the machine has a fixed name, no user database, no
// locale or time-zone settings and no network adapter the program can read, so the identity
// that exists is answered and the rest is `NotFound`, which is what the other hosts say for an
// unset one. The declarations are the fence's.

use e.mem
use e.os

fn hostname(a: *mem.Arena) -> (str, err) { ret ("neperos", ok) }
fn user_name(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn locale_name(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn time_zone_id(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn mac_address(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
