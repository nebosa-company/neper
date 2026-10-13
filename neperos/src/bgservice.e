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

const REQ: usize = 2usize
const REP: usize = 3usize
const STATUS_REQ: usize = 6usize
const NO_SLOT: usize = 99usize
const TIMED_OUT: usize = 18446744073709551614usize
const OP_POST_QUIET: usize = 6usize
const OP_POST_APP_QUIET: usize = 7usize

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
                    say("services volumes ")
                    say_num(volumes[0usize])
                    say(" ")
                    say_num(volumes[1usize])
                    say(" ")
                    say_num(volumes[2usize])
                    if vibrate { say(" vibrate on\n") } else { say(" vibrate off\n") }
                }
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
