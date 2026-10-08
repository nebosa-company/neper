// A dimensioned unit-conversion registry in the ConvUtils/StdConvs style, over caller storage. A
// unit is a symbol, a name, a family (its dimension) and an affine map to the family's base unit:
// base = value * scale + offset. The built-in families are length (metre), area (square metre),
// volume (cubic metre), mass (kilogram), time (second), temperature (kelvin) and data (byte), with
// SI, US customary, imperial and IEC (binary) units; the factors are the exact definitions where
// there is one. A family is any u32, so a caller can register units of its own dimension (above
// 100 by convention). Conversion needs equal families (`Incompatible` otherwise). Temperature
// maps are affine and apply to readings, not to temperature differences; a year is the Julian
// 365.25 days; a month is not offered (it has no fixed length). No live rates (currency is out of scope).

error Invalid
error Unknown
error Incompatible
error Duplicate
error TooSmall

const LENGTH: u32 = 1u32
const AREA: u32 = 2u32
const VOLUME: u32 = 3u32
const MASS: u32 = 4u32
const TIME: u32 = 5u32
const TEMPERATURE: u32 = 6u32
const DATA: u32 = 7u32
const BUILTIN: usize = 79usize

type Unit = struct { symbol: str, name: str, family: u32, scale: f64, offset: f64 }
type Registry = struct { units: []Unit, count: usize }

fn unit(symbol: str, name: str, family: u32, scale: f64) -> Unit {
    ret Unit { symbol: symbol, name: name, family: family, scale: scale, offset: 0.0f64 }
}

// The i-th built-in unit (i < BUILTIN).
fn builtin(i: usize) -> Unit {
    if i == 0usize { ret unit("m", "metre", LENGTH, 1.0f64) }
    if i == 1usize { ret unit("km", "kilometre", LENGTH, 1000.0f64) }
    if i == 2usize { ret unit("cm", "centimetre", LENGTH, 0.01f64) }
    if i == 3usize { ret unit("mm", "millimetre", LENGTH, 0.001f64) }
    if i == 4usize { ret unit("um", "micrometre", LENGTH, 0.000001f64) }
    if i == 5usize { ret unit("nm", "nanometre", LENGTH, 0.000000001f64) }
    if i == 6usize { ret unit("mi", "mile", LENGTH, 1609.344f64) }
    if i == 7usize { ret unit("yd", "yard", LENGTH, 0.9144f64) }
    if i == 8usize { ret unit("ft", "foot", LENGTH, 0.3048f64) }
    if i == 9usize { ret unit("in", "inch", LENGTH, 0.0254f64) }
    if i == 10usize { ret unit("nmi", "nautical mile", LENGTH, 1852.0f64) }
    if i == 11usize { ret unit("au", "astronomical unit", LENGTH, 149597870700.0f64) }
    if i == 12usize { ret unit("ly", "light year", LENGTH, 9460730472580800.0f64) }
    if i == 13usize { ret unit("pc", "parsec", LENGTH, 30856775814913672.0f64) }
    if i == 14usize { ret unit("m2", "square metre", AREA, 1.0f64) }
    if i == 15usize { ret unit("km2", "square kilometre", AREA, 1000000.0f64) }
    if i == 16usize { ret unit("cm2", "square centimetre", AREA, 0.0001f64) }
    if i == 17usize { ret unit("mm2", "square millimetre", AREA, 0.000001f64) }
    if i == 18usize { ret unit("ha", "hectare", AREA, 10000.0f64) }
    if i == 19usize { ret unit("ac", "acre", AREA, 4046.8564224f64) }
    if i == 20usize { ret unit("ft2", "square foot", AREA, 0.09290304f64) }
    if i == 21usize { ret unit("in2", "square inch", AREA, 0.00064516f64) }
    if i == 22usize { ret unit("yd2", "square yard", AREA, 0.83612736f64) }
    if i == 23usize { ret unit("mi2", "square mile", AREA, 2589988.110336f64) }
    if i == 24usize { ret unit("m3", "cubic metre", VOLUME, 1.0f64) }
    if i == 25usize { ret unit("L", "litre", VOLUME, 0.001f64) }
    if i == 26usize { ret unit("mL", "millilitre", VOLUME, 0.000001f64) }
    if i == 27usize { ret unit("cm3", "cubic centimetre", VOLUME, 0.000001f64) }
    if i == 28usize { ret unit("gal", "US gallon", VOLUME, 0.003785411784f64) }
    if i == 29usize { ret unit("qt", "US quart", VOLUME, 0.000946352946f64) }
    if i == 30usize { ret unit("pt", "US pint", VOLUME, 0.000473176473f64) }
    if i == 31usize { ret unit("cup", "US cup", VOLUME, 0.0002365882365f64) }
    if i == 32usize { ret unit("floz", "US fluid ounce", VOLUME, 0.0000295735295625f64) }
    if i == 33usize { ret unit("tbsp", "US tablespoon", VOLUME, 0.00001478676478125f64) }
    if i == 34usize { ret unit("tsp", "US teaspoon", VOLUME, 0.00000492892159375f64) }
    if i == 35usize { ret unit("gal_uk", "imperial gallon", VOLUME, 0.00454609f64) }
    if i == 36usize { ret unit("ft3", "cubic foot", VOLUME, 0.028316846592f64) }
    if i == 37usize { ret unit("in3", "cubic inch", VOLUME, 0.000016387064f64) }
    if i == 38usize { ret unit("kg", "kilogram", MASS, 1.0f64) }
    if i == 39usize { ret unit("g", "gram", MASS, 0.001f64) }
    if i == 40usize { ret unit("mg", "milligram", MASS, 0.000001f64) }
    if i == 41usize { ret unit("ug", "microgram", MASS, 0.000000001f64) }
    if i == 42usize { ret unit("t", "tonne", MASS, 1000.0f64) }
    if i == 43usize { ret unit("lb", "pound", MASS, 0.45359237f64) }
    if i == 44usize { ret unit("oz", "ounce", MASS, 0.028349523125f64) }
    if i == 45usize { ret unit("st", "stone", MASS, 6.35029318f64) }
    if i == 46usize { ret unit("ton_us", "short ton", MASS, 907.18474f64) }
    if i == 47usize { ret unit("ton_uk", "long ton", MASS, 1016.0469088f64) }
    if i == 48usize { ret unit("ct", "carat", MASS, 0.0002f64) }
    if i == 49usize { ret unit("gr", "grain", MASS, 0.00006479891f64) }
    if i == 50usize { ret unit("s", "second", TIME, 1.0f64) }
    if i == 51usize { ret unit("ms", "millisecond", TIME, 0.001f64) }
    if i == 52usize { ret unit("us", "microsecond", TIME, 0.000001f64) }
    if i == 53usize { ret unit("ns", "nanosecond", TIME, 0.000000001f64) }
    if i == 54usize { ret unit("min", "minute", TIME, 60.0f64) }
    if i == 55usize { ret unit("h", "hour", TIME, 3600.0f64) }
    if i == 56usize { ret unit("d", "day", TIME, 86400.0f64) }
    if i == 57usize { ret unit("wk", "week", TIME, 604800.0f64) }
    if i == 58usize { ret unit("yr", "Julian year", TIME, 31557600.0f64) }
    if i == 59usize { ret unit("K", "kelvin", TEMPERATURE, 1.0f64) }
    if i == 60usize { ret Unit { symbol: "C", name: "degree Celsius", family: TEMPERATURE, scale: 1.0f64, offset: 273.15f64 } }
    if i == 61usize { ret Unit { symbol: "F", name: "degree Fahrenheit", family: TEMPERATURE, scale: 5.0f64 / 9.0f64, offset: 459.67f64 * 5.0f64 / 9.0f64 } }
    if i == 62usize { ret unit("R", "degree Rankine", TEMPERATURE, 5.0f64 / 9.0f64) }
    if i == 63usize { ret Unit { symbol: "Re", name: "degree Reaumur", family: TEMPERATURE, scale: 1.25f64, offset: 273.15f64 } }
    if i == 64usize { ret unit("B", "byte", DATA, 1.0f64) }
    if i == 65usize { ret unit("kB", "kilobyte", DATA, 1000.0f64) }
    if i == 66usize { ret unit("MB", "megabyte", DATA, 1000000.0f64) }
    if i == 67usize { ret unit("GB", "gigabyte", DATA, 1000000000.0f64) }
    if i == 68usize { ret unit("TB", "terabyte", DATA, 1000000000000.0f64) }
    if i == 69usize { ret unit("PB", "petabyte", DATA, 1000000000000000.0f64) }
    if i == 70usize { ret unit("KiB", "kibibyte", DATA, 1024.0f64) }
    if i == 71usize { ret unit("MiB", "mebibyte", DATA, 1048576.0f64) }
    if i == 72usize { ret unit("GiB", "gibibyte", DATA, 1073741824.0f64) }
    if i == 73usize { ret unit("TiB", "tebibyte", DATA, 1099511627776.0f64) }
    if i == 74usize { ret unit("PiB", "pebibyte", DATA, 1125899906842624.0f64) }
    if i == 75usize { ret unit("bit", "bit", DATA, 0.125f64) }
    if i == 76usize { ret unit("kbit", "kilobit", DATA, 125.0f64) }
    if i == 77usize { ret unit("Mbit", "megabit", DATA, 125000.0f64) }
    if i == 78usize { ret unit("Gbit", "gigabit", DATA, 125000000.0f64) }
    ret Unit { symbol: "", name: "", family: 0u32, scale: 0.0f64, offset: 0.0f64 }
}

fn builtin_count() -> usize { ret BUILTIN }

fn family_name(family: u32) -> str {
    if family == LENGTH { ret "length" }
    if family == AREA { ret "area" }
    if family == VOLUME { ret "volume" }
    if family == MASS { ret "mass" }
    if family == TIME { ret "time" }
    if family == TEMPERATURE { ret "temperature" }
    if family == DATA { ret "data" }
    ret ""
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn finite(v: f64) -> bool { ret v - v == 0.0f64 }

// A registry holding the built-ins in `storage`, with room left for caller units.
fn registry(storage: []Unit) -> (Registry, err) {
    if storage.len < BUILTIN { ret (zero, TooSmall) }
    var i = 0usize
    while i < BUILTIN {
        storage[i] = builtin(i)
        i += 1usize
    }
    ret (Registry { units: storage, count: BUILTIN }, ok)
}

// Add a unit of an existing or new family. Refused: an empty symbol, a zero or non-finite scale
// or offset, a family of 0, a symbol already taken, or no room.
fn register(r: *Registry, u: Unit) -> err {
    if u.symbol.len == 0usize || u.family == 0u32 || !finite(u.scale) || u.scale == 0.0f64 || !finite(u.offset) { ret Invalid }
    var i = 0usize
    while i < r.count {
        if same(r.units[i].symbol, u.symbol) { ret Duplicate }
        i += 1usize
    }
    if r.count >= r.units.len { ret TooSmall }
    r.units[r.count] = u
    r.count += 1usize
    ret ok
}

fn find(r: *const Registry, symbol: str) -> (Unit, err) {
    var i = 0usize
    while i < r.count {
        if same(r.units[i].symbol, symbol) { ret (r.units[i], ok) }
        i += 1usize
    }
    ret (zero, Unknown)
}

// Units of `family`, as indices into the registry, in registration order.
fn family_units(r: *const Registry, family: u32, out: []usize) -> (usize, err) {
    var used = 0usize
    var i = 0usize
    while i < r.count {
        if r.units[i].family == family {
            if used >= out.len { ret (used, TooSmall) }
            out[used] = i
            used += 1usize
        }
        i += 1usize
    }
    ret (used, ok)
}

// Convert between two units of one family; a non-finite value or result is Invalid.
fn convert_between(value: f64, from: Unit, to: Unit) -> (f64, err) {
    if !finite(value) { ret (0.0f64, Invalid) }
    if from.family != to.family { ret (0.0f64, Incompatible) }
    if same(from.symbol, to.symbol) { ret (value, ok) }
    let base = value * from.scale + from.offset
    let result = (base - to.offset) / to.scale
    if !finite(result) { ret (0.0f64, Invalid) }
    ret (result, ok)
}

fn convert(r: *const Registry, value: f64, from: str, to: str) -> (f64, err) {
    let (a, from_error) = find(r, from)
    if from_error != ok { ret (0.0f64, from_error) }
    let (b, to_error) = find(r, to)
    if to_error != ok { ret (0.0f64, to_error) }
    let (result, convert_error) = convert_between(value, a, b)
    ret (result, convert_error)
}
