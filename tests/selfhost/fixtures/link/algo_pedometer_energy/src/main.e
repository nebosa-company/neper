// `e.algo.pedometer`'s distance and energy estimates: a stride of 41.5% of the height walking and 65% running, and
// 0.75 or 1.0 kcal per kilogram per kilometre (hand-computed with exact decimals). Every check has its own exit code.
use e.os
use e.mem
use e.algo.pedometer as ped

fn close(a: f64, b: f64) -> bool {
    var d = a - b
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 10,000 steps at 180 cm: 10,000 x 74.7 cm = 7,470 m walking; at 65%: 10,000 x 117 cm = 11,700 m running.
    if !close(ped.distance_m(10000usize, 180.0f64, false), 7470.0f64) { os.exit(1) }
    if !close(ped.distance_m(10000usize, 180.0f64, true), 11700.0f64) { os.exit(2) }
    if !close(ped.distance_m(0usize, 180.0f64, false), 0.0f64) { os.exit(3) }
    // 7.47 km at 70 kg walking: 0.75 x 70 x 7.47 = 392.175 kcal; running 11.7 km: 1.0 x 70 x 11.7 = 819 kcal.
    if !close(ped.calories_kcal(7470.0f64, 70.0f64, false), 392.175f64) { os.exit(4) }
    if !close(ped.calories_kcal(11700.0f64, 70.0f64, true), 819.0f64) { os.exit(5) }
    // Linear in weight: double the weight, double the energy.
    if !close(ped.calories_kcal(1000.0f64, 120.0f64, false), 2.0f64 * ped.calories_kcal(1000.0f64, 60.0f64, false)) { os.exit(6) }
    // 1 km of walking by a 60 kg person: 45 kcal.
    if !close(ped.calories_kcal(1000.0f64, 60.0f64, false), 45.0f64) { os.exit(7) }
    ret ok
}
