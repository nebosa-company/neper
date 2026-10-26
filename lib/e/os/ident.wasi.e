// `e.os.ident` on WebAssembly (C182): a module has no user database, locale, time zone or adapter to read,
// so each identity is `NotFound`, as an unset one is on the other hosts. The declarations are the fence's.

use e.mem
use e.os

fn hostname(a: *mem.Arena) -> (str, err) { ret ("wasi", ok) }
fn user_name(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn locale_name(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn time_zone_id(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
fn mac_address(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
