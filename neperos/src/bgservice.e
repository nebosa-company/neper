// The background services process (C174, C176, D4007): started by the kernel in the unified boot (archive entry 45),
// it keeps working while no app is in front. It holds three things behind one stamped endpoint (16 requests in,
// slot 2; 17 replies out, slot 3; bgclient.e is the other end):
//
//  - the audio mixer: e.audio.mixer over three streams (media, ring, alarm) whose volumes, and Vibrate, the settings
//    server pushes whenever they change; a tone is generated, mixed at the stream's volume and written to the sink
//    (a null sink under QEMU, the Pixel's HAL behind the same call), and the loudest sample is the answer;
//  - the clock's ringer: it holds the Clock's alarms and timer (the settings server reads /clock at boot and the Clock
//    app pushes every change), compares them with the wall clock every second, and when one is due and the Clock is not
//    in front it counts a notification through the status service, vibrates when Vibrate is on, and rings the alarm
//    stream every two seconds until the Clock (opened from the notification) stops it;
//  - nothing else of its own: the step counter is the sensor hub's.
//
// The process is a client of the status service (slot 6, endpoint 3). It never touches the filesystem: the settings
// server is the one process that does at boot, and the Clock writes /clock itself.
use e.mem
use e.os
use e.time
use e.audio
use e.audio.mixer as mix
use bgclient
use power

const REQ: usize = 2usize
const REP: usize = 3usize
const STATUS_REQ: usize = 6usize
const NO_SLOT: usize = 99usize
const TIMED_OUT: usize = 18446744073709551614usize
const OP_POST_QUIET: usize = 6usize
const OP_POST_APP_QUIET: usize = 7usize
// (C176) The battery provider's word to the status service: present | charging << 8 | level.
const OP_SET_BATTERY: usize = 8usize
const BATTERY_PRESENT: usize = 2147483648usize

// An app's place in Settings' notification list (Messages, Mail, Clock, Tasks, Weather, Stocks, Wallet, Chat) from its
// archive entry, 99 for an app that has none.
fn notify_index(app: usize) -> usize {
    if app == 16usize { ret 0usize }
    if app == 26usize { ret 1usize }
    if app == 14usize { ret 2usize }
    if app == 15usize { ret 3usize }
    if app == 18usize { ret 4usize }
    if app == 17usize { ret 5usize }
    if app == 20usize { ret 6usize }
    if app == 32usize { ret 7usize }
    ret 99usize
}

// A notification as the app that owns slot `index` of the list: the status service counts it when the user has that
// app's switch on.
fn post_as(index: usize) {
    let sent = os.send(STATUS_REQ, OP_POST_APP_QUIET, NO_SLOT)
    let sent_index = os.send(STATUS_REQ, index, NO_SLOT)
}

const RATE: u32 = 8000u32
const AMPLITUDE: i32 = 16000i32
const MAX_FRAMES: usize = 8000usize

type Schedule = struct { raw: [66]u8 }

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var more = true
    while more {
        at -= 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        if rest == 0usize { more = false }
    }
    say(digits[at..20usize])
}

fn now_ms() -> usize {
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret 0usize }
    ret usize(now.nanos / 1000000i64)
}

fn wall_seconds() -> usize {
    let (wall, wall_error) = time.now()
    if wall_error != ok || wall.nanos <= 0i64 { ret 0usize }
    ret usize(wall.nanos / 1000000000i64)
}

// The tone's square wave: `frames` samples at RATE, the half period of each note in frames. TONE_ALARM is three beeps
// with gaps, TONE_CHIME two notes, TONE_BEEP one.
fn tone_sample(tone: usize, frame: usize) -> i32 {
    var half = 4usize
    if tone == bgclient.TONE_CHIME { half = 6usize }
    // 8000 / (2 x 4) = 1000 Hz for a beep; the chime 667 Hz then 1000 Hz; the alarm 800 Hz bursts.
    if tone == bgclient.TONE_ALARM { half = 5usize }
    if tone == bgclient.TONE_CHIME && frame >= 2000usize { half = 4usize }
    if tone == bgclient.TONE_ALARM {
        // Three bursts of a tenth of a second in each 0.3 s.
        if (frame / 800usize) % 2usize == 1usize { ret 0i32 }
    }
    if (frame / half) % 2usize == 0usize { ret AMPLITUDE }
    ret 0i32 - AMPLITUDE
}

// Mix `tone` for `ms` milliseconds at gain Q16 `gain`; the loudest sample (absolute value, 16-bit scale).
fn mix_tone(a: *mem.Arena, tone: usize, ms: usize, gain: i32) -> usize {
    var frames = ms * 8usize
    if frames > MAX_FRAMES { frames = MAX_FRAMES }
    if frames == 0usize { ret 0usize }
    let format = audio.Format { rate: RATE, channels: 1u8, sample: .I16 }
    let mark = mem.mark(a)
    let (source_bytes, source_error) = mem.alloc[u8](a, frames * 2usize)
    if source_error != ok { ret 0usize }
    let (out_bytes, out_error) = mem.alloc[u8](a, frames * 2usize)
    if out_error != ok {
        mem.reset(a, mark)
        ret 0usize
    }
    let (voices, voices_error) = mem.alloc[mix.Voice](a, 2usize)
    if voices_error != ok {
        mem.reset(a, mark)
        ret 0usize
    }
    var i = 0usize
    while i < frames {
        let v = tone_sample(tone, i)
        let packed = mem.bitcast[u16](i16(v))
        audio.write_u16(source_bytes, i * 2usize, packed)
        i += 1usize
    }
    let (source, source_view_error) = audio.view(source_bytes, format)
    let (out_value, out_view_error) = audio.view(out_bytes, format)
    var out = out_value
    var peak = 0usize
    if source_view_error == ok && out_view_error == ok {
        var m: mix.Mixer = zero
        let init_error = mix.init(&m, format, voices)
        if init_error == ok {
            let (slot, play_error) = mix.play(&m, source, gain, false)
            if play_error == ok {
                let (mixed, mix_error) = mix.mix_into(&m, &out)
                if mix_error == ok {
                    var f = 0usize
                    while f < out.count {
                        let (s, s_error) = audio.sample_i32(out, f, 0u8)
                        var magnitude = s / 65536i32
                        if magnitude < 0i32 { magnitude = 0i32 - magnitude }
                        if usize(magnitude) > peak { peak = usize(magnitude) }
                        f += 1usize
                    }
                }
            }
        }
    }
    mem.reset(a, mark)
    ret peak
}

// The Q16 gain of a volume of 0 to 10.
fn gain_of(volume: usize) -> i32 {
    var v = volume
    if v > 10usize { v = 10usize }
    ret i32(v * 65536usize / 10usize)
}

fn say_hhmm(minutes: usize) {
    if minutes / 60usize < 10usize { say("0") }
    say_num(minutes / 60usize)
    say(":")
    if minutes % 60usize < 10usize { say("0") }
    say_num(minutes % 60usize)
}

// The alarms of the Clock's 64 bytes (version 1: the count at 1, five of four bytes from 2: minutes low, high, on, days).
fn alarm_count(sc: *Schedule) -> usize {
    if sc.raw[0usize] != 1u8 { ret 0usize }
    var n = usize(sc.raw[1usize])
    if n > 5usize { n = 5usize }
    ret n
}

fn alarm_minutes(sc: *Schedule, i: usize) -> usize {
    ret usize(sc.raw[2usize + i * 4usize]) + usize(sc.raw[3usize + i * 4usize]) * 256usize
}

fn alarm_on(sc: *Schedule, i: usize) -> bool {
    ret sc.raw[4usize + i * 4usize] != 0u8
}

fn alarm_days(sc: *Schedule, i: usize) -> usize {
    ret usize(sc.raw[5usize + i * 4usize])
}

// The timer's end as wall seconds (flags bit 0 running, the end at 38, four bytes), 0 when it is not running.
fn timer_end(sc: *Schedule) -> usize {
    if sc.raw[0usize] != 1u8 || (sc.raw[33usize] & 1u8) == 0u8 { ret 0usize }
    ret usize(sc.raw[38usize]) + usize(sc.raw[39usize]) * 256usize + usize(sc.raw[40usize]) * 65536usize + usize(sc.raw[41usize]) * 16777216usize
}

// ----------------------------------------------------------------------------------------------
// (C166) The microphone and the speaker.
//
// The capture buffer: ten seconds of 8 kHz mono 16-bit little-endian, filled as the scripted microphone "hears" it (by the
// monotonic clock, eight frames a millisecond) whether or not an app is looking; the speaker's sink counts what reaches
// it. The scripted microphone is a triangle wave whose period follows the recording's seed under a four-step swell, all in
// integers, so an independent oracle (scripts/neperos_mic_oracle.py) can produce the same bytes.
var capture: [160000]u8 = zero
var rec_running: bool = false
var rec_start_ms: usize = 0usize
var rec_frames: usize = 0usize
var rec_seed: usize = 0usize
var rec_watched_ms: usize = 0usize
var rec_unwatched: bool = false
var mic_allowed: bool = true
var spk_frames: usize = 0usize
var spk_sum: usize = 0usize
var spk_peak: usize = 0usize

fn mic_sample(seed: usize, n: usize) -> i32 {
    let period = 36usize + 4usize * (seed % 7usize)
    let half = period / 2usize
    let phase = n % period
    var v = phase
    if phase >= half { v = period - phase }
    let base = (i32(v) * 2i32 - i32(half)) * 9000i32 / i32(half)
    let swell = 1i32 + i32((n / 4000usize) % 4usize)
    ret base * swell / 4i32
}

// Bring the buffer up to the frames the clock says have arrived; the buffer filling ends the recording.
fn capture_fill(now: usize) {
    if !rec_running { ret }
    var want = (now - rec_start_ms) * 8usize
    if want >= 80000usize { want = 80000usize }
    while rec_frames < want {
        let v = mic_sample(rec_seed, rec_frames)
        let u = usize(v + 65536i32) & 65535usize
        capture[rec_frames * 2usize] = u8(u & 255usize)
        capture[rec_frames * 2usize + 1usize] = u8(u >> 8usize)
        rec_frames += 1usize
    }
    if rec_frames >= 80000usize {
        rec_running = false
        say("services recording full\n")
    }
}

// The newest 100 ms of the buffer as a level 0..100 (the loudest sample against the swell's top, 9000).
fn capture_level() -> usize {
    var from = 0usize
    if rec_frames > 800usize { from = rec_frames - 800usize }
    var top = 0usize
    var n = from
    while n < rec_frames {
        let u = usize(capture[n * 2usize]) | (usize(capture[n * 2usize + 1usize]) << 8usize)
        var m = u
        if u >= 32768usize { m = 65536usize - u }
        if m > top { top = m }
        n += 1usize
    }
    var level = top * 100usize / 9000usize
    if level > 100usize { level = 100usize }
    ret level
}

fn main(a: *mem.Arena, args: []str) -> err {
    var sc: Schedule = zero
    // The volumes (media, ring, alarm) and Vibrate as Settings starts them, until the settings server says.
    var volumes: [3]usize = zero
    volumes[0usize] = 6usize
    volumes[1usize] = 8usize
    volumes[2usize] = 7usize
    var vibrate = true
    var foreground = false
    // The ring: what rings (RING_*), which alarm, the minute it was set for, the second it started and the last beep.
    var ringing = bgclient.RING_NONE
    var ring_index = 99usize
    var ring_minute = 0usize
    var ring_started = 0usize
    var last_beep = 0usize
    var last_check = 0usize
    var fired_stamp = 0usize
    var beeps = 0usize
    var last_peak = 0usize
    var rings = 0usize
    var posted = 0usize
    // (C176) The battery word last sent to the status service, and whether the low and critical notices were given.
    var last_battery = 0usize
    var low_told = false
    var critical_told = false
    say("services up\n")
    var running = true
    while running {
        let word = os.recv(REQ, 1000usize + 100usize)
        let now = now_ms()
        if word != TIMED_OUT && word != 18446744073709551615usize {
            let app = word >> 56usize
            let op = word & 15usize
            let kind = (word >> 4usize) & 15usize
            let payload = (word >> 8usize) & 281474976710655usize
            if op == bgclient.OP_PLAY {
                var stream = kind
                if stream > 2usize { stream = 0usize }
                let tone = payload & 255usize
                let ms = payload >> 8usize
                let peak = mix_tone(a, tone, ms, gain_of(volumes[stream]))
                beeps += 1usize
                last_peak = peak
                say("audio play stream ")
                say_num(stream)
                say(" tone ")
                say_num(tone)
                say(" volume ")
                say_num(volumes[stream])
                say(" peak ")
                say_num(peak)
                say("\n")
                let sent = os.send(REP, peak, NO_SLOT)
            } else if op == bgclient.OP_RING_STATE {
                var answer = 0usize
                if ringing != bgclient.RING_NONE { answer = (ring_index + 1usize) | (ringing << 8usize) | (ring_minute << 16usize) }
                let sent = os.send(REP, answer, NO_SLOT)
            } else if op == bgclient.OP_RING_STOP {
                // Whatever rang, this minute's alarm is answered: it does not ring again in the same minute.
                fired_stamp = wall_seconds() / 60usize
                if ringing != bgclient.RING_NONE {
                    say("services ring stopped\n")
                    ringing = bgclient.RING_NONE
                    ring_index = 99usize
                }
                let sent = os.send(REP, 1usize, NO_SLOT)
            } else if op == bgclient.OP_FOREGROUND {
                foreground = payload != 0usize
            } else if op == bgclient.OP_SCHEDULE {
                // Six bytes of the Clock's state; only the settings server (stamp 0) and the Clock (entry 14) may send it.
                if (app == 0usize || app == 14usize) && kind < 11usize {
                    var k = 0usize
                    while k < 6usize {
                        sc.raw[kind * 6usize + k] = u8((payload >> (8usize * k)) & 255usize)
                        k += 1usize
                    }
                    if kind == 10usize {
                        say("services schedule ")
                        say_num(alarm_count(&sc))
                        say(" alarms\n")
                    }
                }
            } else if op == bgclient.OP_NOTIFY {
                // An app posts as itself: the kernel's stamp names it, and only an app with a place in the list may.
                let who = notify_index(app)
                if kind == 1usize && app == 36usize {
                    // The Steps goal: the system's notification (Steps has no switch of its own in the list).
                    let sent_goal = os.send(STATUS_REQ, OP_POST_QUIET, NO_SLOT)
                    posted += 1usize
                    say("services notification goal app ")
                    say_num(app)
                    say("\n")
                } else if who < 8usize {
                    post_as(who)
                    posted += 1usize
                    say("services notification from app ")
                    say_num(app)
                    say("\n")
                } else {
                    say("services notification refused from app ")
                    say_num(app)
                    say("\n")
                }
            } else if op == bgclient.OP_VOLUMES {
                // From the settings server only.
                if app == 0usize {
                    volumes[0usize] = payload & 255usize
                    volumes[1usize] = (payload >> 8usize) & 255usize
                    volumes[2usize] = (payload >> 16usize) & 255usize
                    vibrate = ((payload >> 24usize) & 255usize) != 0usize
                    // (C166) Microphone access (Settings' switch), bits 32-39.
                    mic_allowed = ((payload >> 32usize) & 255usize) != 0usize
                    say("services volumes ")
                    say_num(volumes[0usize])
                    say(" ")
                    say_num(volumes[1usize])
                    say(" ")
                    say_num(volumes[2usize])
                    if vibrate { say(" vibrate on\n") } else { say(" vibrate off\n") }
                }
            } else if op == bgclient.OP_REC_START {
                var started = bgclient.REC_OK
                if !mic_allowed {
                    started = bgclient.REC_DENIED
                    say("services recording denied app ")
                    say_num(app)
                    say("\n")
                } else if !rec_running {
                    rec_running = true
                    rec_start_ms = now
                    rec_frames = 0usize
                    rec_seed = kind
                    rec_watched_ms = now
                    rec_unwatched = false
                    say("services recording started seed ")
                    say_num(kind)
                    say("\n")
                }
                let sent_started = os.send(REP, started, NO_SLOT)
            } else if op == bgclient.OP_REC_STATE {
                capture_fill(now)
                rec_watched_ms = now
                if kind == 1usize && rec_running && !rec_unwatched {
                    // The app says it is leaving with the recording running: it goes on, and the notification says so.
                    rec_unwatched = true
                    let leave_told = os.send(STATUS_REQ, OP_POST_QUIET, NO_SLOT)
                    posted += 1usize
                    say("services recording in background\n")
                }
                var state = 0usize
                if rec_running { state = 1usize }
                state = state | (rec_frames << 8usize) | (capture_level() << 40usize)
                if rec_unwatched { state = state | (1usize << 48usize) }
                let sent_state = os.send(REP, state, NO_SLOT)
            } else if op == bgclient.OP_REC_STOP {
                capture_fill(now)
                // The app that watches has it: a recording it stops is no longer an unwatched one.
                rec_unwatched = false
                if rec_running {
                    rec_running = false
                    say("services recording stopped frames ")
                    say_num(rec_frames)
                    say("\n")
                }
                let sent_frames = os.send(REP, rec_frames, NO_SLOT)
            } else if op == bgclient.OP_REC_READ {
                let offset = payload & 4294967295usize
                var want = (payload >> 32usize) & 65535usize
                var from = offset
                if from > rec_frames { from = rec_frames }
                if want > 256usize { want = 256usize }
                var count = rec_frames - from
                if count > want { count = want }
                let sent_count = os.send(REP, count, NO_SLOT)
                var w = 0usize
                while w * 4usize < count {
                    var out_word = 0usize
                    var j = 0usize
                    while j < 4usize && w * 4usize + j < count {
                        let at = (from + w * 4usize + j) * 2usize
                        let frame = usize(capture[at]) | (usize(capture[at + 1usize]) << 8usize)
                        out_word = out_word | (frame << (16usize * j))
                        j += 1usize
                    }
                    let sent_word = os.send(REP, out_word, NO_SLOT)
                    w += 1usize
                }
            } else if op == bgclient.OP_SPK_WRITE {
                // The words follow at once, three 16-bit frames each; the first block of a stream resets the counts.
                var words = payload & 65535usize
                let block_frames = (payload >> 16usize) & 65535usize
                var counted = 0usize
                if words > 32usize { words = 32usize }
                if kind == 1usize {
                    spk_frames = 0usize
                    spk_sum = 0usize
                    spk_peak = 0usize
                }
                let gain = gain_of(volumes[0usize])
                var w = 0usize
                while w < words {
                    let packed = os.recv(REQ, NO_SLOT)
                    var j = 0usize
                    while j < 3usize {
                        if counted < block_frames {
                            let frame = (packed >> (16usize * j)) & 65535usize
                            spk_sum = (spk_sum + (frame & 255usize) + (frame >> 8usize)) % 65521usize
                            var magnitude = frame
                            if frame >= 32768usize { magnitude = 65536usize - frame }
                            let heard = magnitude * usize(gain) / 65536usize
                            if heard > spk_peak { spk_peak = heard }
                            spk_frames += 1usize
                            counted += 1usize
                        }
                        j += 1usize
                    }
                    w += 1usize
                }
                let sent_taken = os.send(REP, counted, NO_SLOT)
            } else if op == bgclient.OP_SPK_STATS {
                let sent_spk_frames = os.send(REP, spk_frames, NO_SLOT)
                let sent_spk_sum = os.send(REP, spk_sum, NO_SLOT)
                let sent_spk_peak = os.send(REP, spk_peak, NO_SLOT)
            } else if op == bgclient.OP_STATS {
                let sent_beeps = os.send(REP, beeps, NO_SLOT)
                let sent_peak = os.send(REP, last_peak, NO_SLOT)
                let sent_rings = os.send(REP, rings, NO_SLOT)
                let sent_posted = os.send(REP, posted, NO_SLOT)
            } else {
                // An unknown request still gets one word, so the caller is not left waiting.
                let sent = os.send(REP, 0usize, NO_SLOT)
            }
        }
        // Once a second: the alarms and the timer against the wall clock.
        if now >= last_check + 1000usize {
            last_check = now
            // (C176) The battery provider: the scripted fuel gauge (power.e) against the wall clock. The level and the
            // charging state go to the status service when either changed; the low and critical levels are the
            // system's own notifications, once each while the charger is out.
            // (C166) The recording goes on without its app: the app says so when it leaves (REC_STATE with the leaving flag); an app
            // that died without saying is found by nobody having looked for twenty seconds. Either way it is "unwatched",
            // and the system's notification says a recording is running (once for this recording).
            if rec_running {
                capture_fill(now)
                if !rec_unwatched && now >= rec_watched_ms + 20000usize {
                    rec_unwatched = true
                    let rec_told = os.send(STATUS_REQ, OP_POST_QUIET, NO_SLOT)
                    posted += 1usize
                    say("services recording in background\n")
                }
            }
            let clock_now = wall_seconds()
            if clock_now != 0usize {
                let (level, charging) = power.level_at(clock_now % 86400usize)
                var charging_bit = 0usize
                if charging { charging_bit = 256usize }
                let battery_word = BATTERY_PRESENT | charging_bit | level
                if battery_word != last_battery {
                    last_battery = battery_word
                    let set_sent = os.send(STATUS_REQ, OP_SET_BATTERY, NO_SLOT)
                    let word_sent = os.send(STATUS_REQ, battery_word, NO_SLOT)
                    say("services battery ")
                    say_num(level)
                    if charging { say(" charging\n") } else { say(" discharging\n") }
                    if charging || level > power.LOW { low_told = false }
                    if charging || level > power.CRITICAL { critical_told = false }
                    if !charging && level <= power.LOW && !low_told {
                        low_told = true
                        let low_sent = os.send(STATUS_REQ, OP_POST_QUIET, NO_SLOT)
                        posted += 1usize
                        say("services battery low\n")
                    }
                    if !charging && level <= power.CRITICAL && !critical_told {
                        critical_told = true
                        let critical_sent = os.send(STATUS_REQ, OP_POST_QUIET, NO_SLOT)
                        posted += 1usize
                        say("services battery critical\n")
                    }
                }
            }
            if ringing == bgclient.RING_NONE && !foreground {
                let wall = wall_seconds()
                if wall != 0usize {
                    let minute = wall % 86400usize / 60usize
                    let day = (wall / 86400usize + 3usize) % 7usize
                    let stamp = wall / 60usize
                    var i = 0usize
                    while i < alarm_count(&sc) && ringing == bgclient.RING_NONE {
                        let days = alarm_days(&sc, i)
                        let today = days == 0usize || ((days >> day) & 1usize) == 1usize
                        if alarm_on(&sc, i) && today && alarm_minutes(&sc, i) == minute && fired_stamp != stamp {
                            fired_stamp = stamp
                            ringing = bgclient.RING_ALARM
                            ring_index = i
                            ring_minute = minute
                        }
                        i += 1usize
                    }
                    let end = timer_end(&sc)
                    if ringing == bgclient.RING_NONE && end != 0usize && wall >= end {
                        ringing = bgclient.RING_TIMER
                        ring_index = 0usize
                        ring_minute = minute
                        // The timer is handed on: it will not ring again from the same schedule.
                        sc.raw[33usize] = sc.raw[33usize] & 254u8
                    }
                    if ringing != bgclient.RING_NONE {
                        ring_started = now
                        last_beep = 0usize
                        rings += 1usize
                        say("services ringing ")
                        if ringing == bgclient.RING_ALARM { say("alarm ") } else { say("timer ") }
                        say_hhmm(ring_minute)
                        say("\n")
                        // The ring is the Clock's: its notification is the Clock's own (slot 2 of the list).
                        post_as(2usize)
                        posted += 1usize
                        say("services notification posted\n")
                        if vibrate { say("services vibrate\n") }
                    }
                }
            }
        }
        // While it rings: the alarm tone every two seconds, for a minute at most.
        if ringing != bgclient.RING_NONE {
            if now >= last_beep + 2000usize {
                let first_beep = last_beep == 0usize
                last_beep = now
                let peak = mix_tone(a, bgclient.TONE_ALARM, 600usize, gain_of(volumes[2usize]))
                beeps += 1usize
                last_peak = peak
                if first_beep {
                    say("audio ring peak ")
                    say_num(peak)
                    say("\n")
                }
            }
            if now >= ring_started + 60000usize {
                say("services ring timed out\n")
                ringing = bgclient.RING_NONE
                ring_index = 99usize
            }
        }
    }
    say("services done\n")
    ret ok
}
