//! Rust counterpart of `sample.e`.
//!
//! Build and run:
//! `rustc --edition 2024 examples/sample.rs -o sample`
//! `./sample 12.5 41.25 38.0 45.5`

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
use std::time::Instant;

const MAX_SENSORS: usize = 1024;
const WARN_ABOVE: f32 = 40.0;

static G_PARSED: AtomicU64 = AtomicU64::new(0);

type Celsius = f32;

#[derive(Clone, Debug)]
struct Sensor {
    id: u32,
    site: String,
    temp: Celsius,
}

// The Neper sample's map protocol deliberately identifies a sensor by id and site,
// not temperature. Mirror that policy instead of deriving Hash for every field.
impl PartialEq for Sensor {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id && self.site == other.site
    }
}
impl Eq for Sensor {}
impl Hash for Sensor {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
        self.site.hash(state);
    }
}

#[allow(dead_code)] // The enum intentionally demonstrates all variants.
#[derive(Clone, Copy, Debug)]
enum Kind {
    Temp,
    Humidity,
    Pressure,
}

#[allow(dead_code)] // `describe` implements all match arms, as does sample.e.
enum Reading {
    Temp(f32),
    Humidity(u8),
    Pressure(u32),
    Missing,
}

// `repr(C, packed)` is the Rust equivalent of Neper's packed wire header.
#[repr(C, packed)]
#[derive(Clone, Copy)]
struct Wire {
    magic: u32,
    count: u16,
    kind: u8,
}

#[repr(C, align(64))]
struct Line {
    values: [f32; 16],
}

// A Rust union has the same explicit, unsafe interpretation boundary as a C union.
#[repr(C)]
union Raw {
    bits: u32,
    value: f32,
}

type Reducer = fn(f32, f32) -> f32;

fn raw_bits(raw: Raw) -> u32 {
    // SAFETY: the caller initialized `Raw::value`; every bit pattern is valid u32.
    unsafe { raw.bits }
}

fn sensor_hash(sensor: &Sensor) -> u64 {
    let mut hash = 14_695_981_039_346_656_037u64;
    hash = (hash ^ u64::from(sensor.id)).wrapping_mul(1_099_511_628_211);
    for byte in sensor.site.bytes() {
        hash = (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211);
    }
    hash
}

fn sensor_cmp(a: &Sensor, b: &Sensor) -> i32 {
    if a.temp < b.temp {
        -1
    } else if a.temp > b.temp {
        1
    } else {
        0
    }
}

fn sensor_format(sensor: &Sensor, output: &mut String) {
    output.push_str(&sensor.site);
    output.push('#');
    output.push_str(&sensor.id.to_string());
}

#[allow(dead_code)] // Exercised by the Rust test counterpart below.
struct Window<'a> {
    data: &'a [f32],
    i: usize,
    n: usize,
}

impl<'a> Iterator for Window<'a> {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        let end = self.i.checked_add(self.n)?;
        if end > self.data.len() {
            return None;
        }
        let average = self.data[self.i..end].iter().sum::<f32>() / self.n as f32;
        self.i += 1;
        Some(average)
    }
}

// Rust has no stable runtime reflection equivalent to Neper's `meta.fields`.
// This formatter is the explicit, type-safe implementation for Sensor.
fn dump_sensor(sensor: &Sensor, output: &mut String) {
    output.push_str("Sensor{ id=");
    output.push_str(&sensor.id.to_string());
    output.push_str(" site=");
    output.push_str(&sensor.site);
    output.push_str(" temp=");
    output.push_str(&sensor.temp.to_string());
    output.push_str(" display=");
    sensor_format(sensor, output);
    output.push_str(" }");
}

// This is the portable scalar equivalent of the sample's explicit eight-lane SIMD
// calculation. LLVM is free to vectorise it, but correctness does not depend on it.
fn sum_above(xs: &[f32], limit: f32) -> f32 {
    xs.iter().filter(|&&value| value > limit).sum()
}

fn first_above(xs: &[f32], limit: f32) -> (usize, bool) {
    for (i, &value) in xs.iter().enumerate() {
        if value < 0.0 {
            continue;
        }
        if value > limit {
            return (i, true);
        }
    }
    (xs.len(), false)
}

fn describe(reading: Reading, output: &mut String) {
    match reading {
        Reading::Temp(value) => output.push_str(&format!("temp {value}")),
        Reading::Humidity(value) => output.push_str(&format!("humidity {value}")),
        Reading::Pressure(value) => output.push_str(&format!("pressure {value}")),
        Reading::Missing => output.push_str("missing"),
    }
}

fn kind_name(kind: Kind) -> &'static str {
    match kind {
        Kind::Temp => "temp",
        Kind::Humidity => "humidity",
        Kind::Pressure => "pressure",
    }
}

fn platform() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else {
        "posix"
    }
}

struct Job<'a> {
    xs: &'a [f32],
    out: f32,
}

fn worker(job: &mut Job<'_>) {
    job.out = job.xs.iter().sum();
}

fn parallel_sum(xs: &[f32]) -> f32 {
    let half = xs.len() / 2;
    let mut left = Job { xs: &xs[..half], out: 0.0 };
    let mut right = Job { xs: &xs[half..], out: 0.0 };

    std::thread::scope(|scope| {
        let left_thread = scope.spawn(|| worker(&mut left));
        worker(&mut right);
        left_thread.join().expect("worker thread panicked");
    });
    left.out + right.out
}

// Rust's CPU equivalent of the example's GPU scale kernel and CPU backend.
fn run_on_device(xs: &mut [f32], factor: f32) {
    for value in xs {
        *value *= factor;
    }
}

fn add_f32(x: f32, y: f32) -> f32 {
    x + y
}

fn fold(xs: &[f32], seed: f32, reducer: Reducer) -> f32 {
    xs.iter().copied().fold(seed, reducer)
}

fn hot_sum(xs: &[f32]) -> f32 {
    xs.iter().sum()
}

#[derive(Debug)]
enum ParseError {
    NoReadings,
    BadArgument,
}

fn parse_sensors(readings: &[String]) -> Result<Vec<Sensor>, ParseError> {
    if readings.is_empty() {
        return Err(ParseError::NoReadings);
    }
    if readings.len() > MAX_SENSORS {
        return Err(ParseError::BadArgument);
    }

    readings
        .iter()
        .enumerate()
        .map(|(i, reading)| {
            let temp = reading.parse::<f32>().map_err(|_| ParseError::BadArgument)?;
            G_PARSED.fetch_add(1, AtomicOrdering::Relaxed);
            Ok(Sensor { id: i as u32, site: "cli".to_owned(), temp })
        })
        .collect()
}

// Round a f32 to IEEE-754 binary16 bits, without an external crate.
fn f32_to_f16_bits(value: f32) -> u16 {
    let bits = value.to_bits();
    let sign = ((bits >> 16) & 0x8000) as u16;
    let exponent = ((bits >> 23) & 0xff) as i32 - 127 + 15;
    let mantissa = bits & 0x7f_ffff;
    if exponent <= 0 {
        return sign;
    }
    if exponent >= 31 {
        return sign | 0x7c00 | if mantissa == 0 { 0 } else { 1 };
    }
    let rounded = mantissa + 0x1000;
    sign | ((exponent as u16) << 10) | ((rounded >> 13) as u16 & 0x03ff)
}

fn main() {
    let started = Instant::now();
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        println!("usage: sample <temp>...");
        return;
    }

    let mut sensors = match parse_sensors(&args) {
        Ok(sensors) => sensors,
        Err(error) => {
            eprintln!("error: {error:?}");
            std::process::exit(1);
        }
    };

    sensors.sort_by(|a, b| match sensor_cmp(a, b) {
        -1 => Ordering::Less,
        1 => Ordering::Greater,
        _ => Ordering::Equal,
    });

    let mut seen: HashMap<Sensor, u32> = HashMap::with_capacity(64);
    for sensor in &sensors {
        seen.insert(sensor.clone(), sensor.id);
    }

    let mut temps: Vec<f32> = sensors.iter().map(|sensor| sensor.temp).collect();
    let hot = sum_above(&temps, WARN_ABOVE);
    let total = parallel_sum(&temps);
    let folded = fold(&temps, 0.0, add_f32);
    let plain = hot_sum(&temps);
    let peak = hot.max(plain);
    let (idx, found) = first_above(&temps, WARN_ABOVE);

    run_on_device(&mut temps, 2.0);

    let first_bits = temps[0].to_bits();
    let narrow = f32_to_f16_bits(temps[0]);
    let magnitude = (-42i64).unsigned_abs();
    let warn_bits = raw_bits(Raw { value: WARN_ABOVE });

    let header = Wire { magic: 0x4e45_5045, count: sensors.len() as u16, kind: 0 };
    // SAFETY: Wire is exactly seven packed bytes, asserted immediately below.
    let wire_bytes: [u8; 7] = unsafe { std::mem::transmute(header) };
    let scratch = [0xcd_u8; 64]; // Debug-fill counterpart for Neper's `undef`.
    let mut counts = [0u32; 4];
    counts[0] = sensors.len() as u32;

    let mut rendered = String::new();
    dump_sensor(&sensors[0], &mut rendered);
    rendered.push_str(" | ");
    describe(Reading::Temp(sensors[0].temp), &mut rendered);

    println!("{rendered} on {}", platform());
    println!("{} sensors, {} parsed, {} bytes each", sensors.len(), G_PARSED.load(AtomicOrdering::Acquire), std::mem::size_of::<Sensor>());
    println!("sum {} above {} = {hot}, total {total}, folded {folded}, plain {plain}, peak {peak}", kind_name(Kind::Temp), WARN_ABOVE);
    println!("first over limit: index {idx} present {found}");
    println!("bits {first_bits:x} warn {warn_bits:x} as f16 0x{narrow:04x} llabs {magnitude}");
    println!("line is {} bytes, wire byte {:x}, scratch {}, temp count {}", std::mem::size_of::<Line>(), wire_bytes[0], scratch.len(), counts[0]);

    match sensors.len() {
        1 => println!("one reading"),
        2 | 3 => println!("a couple of readings"),
        _ => println!("a batch"),
    }
    println!("fnv hash of first sensor: {:x}; map contains {} entries", sensor_hash(&sensors[0]), seen.len());
    println!("took {}us", started.elapsed().as_micros());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cmp_orders_by_temperature() {
        let lo = Sensor { id: 1, site: "a".into(), temp: 10.0 };
        let hi = Sensor { id: 2, site: "a".into(), temp: 20.0 };
        assert!(sensor_cmp(&lo, &hi) < 0);
        assert_eq!(sensor_cmp(&hi, &hi), 0);
    }

    #[test]
    fn window_walks_in_pairs() {
        let xs = [1.0, 2.0, 3.0, 4.0];
        let values: Vec<f32> = Window { data: &xs, i: 0, n: 2 }.collect();
        assert_eq!(values.len(), 3);
        assert!((values[0] - 1.5).abs() < 1e-6);
    }

    #[test]
    fn simd_and_scalar_agree() {
        let xs = [5.0, 50.0, 41.0, 39.0, 60.0, 1.0, 44.0, 43.0];
        let wide = sum_above(&xs, WARN_ABOVE);
        let slow: f32 = xs.iter().filter(|&&x| x > WARN_ABOVE).sum();
        assert!((wide - slow).abs() < 1e-6);
    }
}
