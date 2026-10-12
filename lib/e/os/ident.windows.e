// Who and where this process is, on Windows: the DNS host name, the user's name, the user's
// default locale as a BCP 47 tag and the Windows time zone id (`W. Europe Standard Time`,
// not the localized display name; `e.tz.winzones` maps it to an IANA zone). The Linux
// variant has the same declarations.

use e.mem
use e.os

@import("kernel32.dll", "GetComputerNameExW")
extern fn raw_computer_name(kind: u32, buffer: *u16, size: *u32) -> i32

@import("advapi32.dll", "GetUserNameW")
extern fn raw_user_name(buffer: *u16, size: *u32) -> i32

@import("kernel32.dll", "GetUserDefaultLocaleName")
extern fn raw_locale_name(buffer: *u16, size: i32) -> i32

@import("kernel32.dll", "GetDynamicTimeZoneInformation")
extern fn raw_time_zone(info: *u8) -> u32

// UTF-16 (BMP and surrogate pairs) to UTF-8 in the arena.
fn narrow(a: *mem.Arena, units: []const u16, count: usize) -> (str, err) {
    let (out, alloc_error) = mem.alloc[u8](a, count * 3usize + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var n = 0usize
    var i = 0usize
    while i < count {
        var cp = u32(units[i])
        i += 1usize
        if cp >= 55296u32 && cp < 56320u32 && i < count {
            let low = u32(units[i])
            if low >= 56320u32 && low < 57344u32 {
                cp = 65536u32 + ((cp - 55296u32) << 10u32) + (low - 56320u32)
                i += 1usize
            }
        }
        if cp < 128u32 {
            out[n] = u8(cp)
            n += 1usize
        } else if cp < 2048u32 {
            out[n] = u8(192u32 + (cp >> 6u32))
            out[n + 1usize] = u8(128u32 + (cp & 63u32))
            n += 2usize
        } else if cp < 65536u32 {
            out[n] = u8(224u32 + (cp >> 12u32))
            out[n + 1usize] = u8(128u32 + ((cp >> 6u32) & 63u32))
            out[n + 2usize] = u8(128u32 + (cp & 63u32))
            n += 3usize
        } else {
            out[n] = u8(240u32 + (cp >> 18u32))
            out[n + 1usize] = u8(128u32 + ((cp >> 12u32) & 63u32))
            out[n + 2usize] = u8(128u32 + ((cp >> 6u32) & 63u32))
            out[n + 3usize] = u8(128u32 + (cp & 63u32))
            n += 4usize
        }
    }
    ret (out[0usize..n], ok)
}

fn hostname(a: *mem.Arena) -> (str, err) {
    var buf: [256]u16 = zero
    var size = 256u32
    if raw_computer_name(1u32, &buf[0usize], &size) == 0i32 { ret ("", os.Failed) }
    let (name, name_error) = narrow(a, buf[0usize..256usize], usize(size))
    if name_error != ok { ret ("", name_error) }
    if name.len == 0usize { ret ("", os.NotFound) }
    ret (name, ok)
}

fn user_name(a: *mem.Arena) -> (str, err) {
    var buf: [257]u16 = zero
    var size = 257u32
    if raw_user_name(&buf[0usize], &size) == 0i32 { ret ("", os.Failed) }
    // `size` counts the terminating NUL.
    var count = usize(size)
    if count > 0usize { count -= 1usize }
    let (name, name_error) = narrow(a, buf[0usize..257usize], count)
    if name_error != ok { ret ("", name_error) }
    if name.len == 0usize { ret ("", os.NotFound) }
    ret (name, ok)
}

fn locale_name(a: *mem.Arena) -> (str, err) {
    var buf: [86]u16 = zero
    let n = raw_locale_name(&buf[0usize], 85i32)
    if n <= 1i32 { ret ("", os.NotFound) }
    let (name, name_error) = narrow(a, buf[0usize..86usize], usize(n - 1i32))
    if name_error != ok { ret ("", name_error) }
    ret (name, ok)
}

// `TimeZoneKeyName` of DYNAMIC_TIME_ZONE_INFORMATION: 128 UTF-16 units at byte offset 172.
fn time_zone_id(a: *mem.Arena) -> (str, err) {
    var info: [432]u8 = zero
    let result = raw_time_zone(&info[0usize])
    if result == 4294967295u32 { ret ("", os.Failed) }
    var units: [128]u16 = zero
    var count = 0usize
    var i = 0usize
    while i < 128usize {
        let unit = u16(info[172usize + i * 2usize]) + u16(info[173usize + i * 2usize]) * 256u16
        if unit == 0u16 { break }
        units[i] = unit
        count += 1usize
        i += 1usize
    }
    if count == 0usize { ret ("", os.NotFound) }
    let (name, name_error) = narrow(a, units[0usize..128usize], count)
    if name_error != ok { ret ("", name_error) }
    ret (name, ok)
}
