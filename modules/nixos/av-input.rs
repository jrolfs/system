// Turns the TV on when someone sits down at Irulan and picks up a keyboard,
// the trackpad or a controller, and off when they're done with it: it runs
// `<command> on` and `<command> off`, which are `av on` and `av off`, so the
// TV and receiver follow without anyone reaching for a remote.
//
// An earlier version turned the TV on every two seconds, which made it
// impossible to switch off, so what counts is deliberately narrow. With
// --wake, three things turn it on, each because it means someone has just
// arrived:
//
//   - A keyboard or pointer press after none for a while (five minutes by
//     default). Every press restarts that wait, so typing never fires twice
//     and switching the TV off from the keyboard isn't undone by the next
//     keystroke. The first press after starting counts as after a wait.
//   - A tap of a controller's PS/Home button: let go within half a second.
//     Holding it is how a DualSense is switched off, and that hold starts
//     with the same press, so counting presses would take the receiver from
//     the Apple TV just to put a controller away.
//   - A controller connecting. A DualSense that's off wakes and connects
//     when its PS button is pressed, but that press happens before its event
//     device exists, so the connection is all there is to see. Controllers
//     already connected at startup don't count, so restarting this never
//     fires.
//
// Nothing turns it on within a cooldown (30 seconds by default) of the last
// time anything did, so waking a controller and then pressing its PS button
// again sends one command, not two.
//
// Two things turn it off:
//
//   - Hyper+Escape on any keyboard, with --off-key. Hyper is Ctrl, Alt, Shift
//     and Super held together, as on the desktop.
//   - Every controller gone for a while, with --controllers-gone: switched
//     off, flat or out of range, and none back in that time. With --vt, only
//     while that virtual terminal, the arcade station's, is on screen. Nobody
//     asked for this one, so it runs `<command> off --automatic`, which lets
//     the command decline.
//
// A modifier decides nothing until it's let go. Tapped on its own it's a
// press like any other key, and held for a chord, the chord's key decides.
// Otherwise Hyper+Escape after a break would turn the TV on with its Ctrl, a
// moment before its Escape turned it off.
//
// With --marker, the file's modification time is the last time someone turned
// the TV off (`av off` touches it), and the first press at least ten seconds
// later turns it back on without waiting out the idle time: whoever put the
// TV away and then reaches for the keyboard wants it back. The ten seconds
// are for whatever the hand that turned it off brushes on its way back.
//
// Devices are told apart by the keys they report in sysfs, never by name or
// event number, which change across reconnects. They're only read, never
// grabbed. Kanata grabs the physical keyboards, so their own devices go quiet
// and every keystroke arrives through its virtual one instead. A watcher on a
// grabbed device simply never wakes.
//
// Reads /dev/input/event* directly, like arcade-hotkey, so it needs root and
// works on whichever virtual terminal is showing. Built by `pkgs.rustTool` in
// overlays/default.nix.

use std::collections::{BTreeSet, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::process::{self, Command};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime};

const USAGE: &str = "usage: av-input [--wake] [--idle SECONDS] [--cooldown SECONDS] [--off-key] \
                     [--controllers-gone SECONDS] [--vt N] [--marker PATH] -- <command> [arguments...]";

const EV_KEY: u16 = 0x01;
const BTN_MODE: u16 = 0x13c;
const KEY_ESC: u16 = 1;
const KEY_LEFTCTRL: u16 = 29;
const KEY_LEFTSHIFT: u16 = 42;
const KEY_RIGHTSHIFT: u16 = 54;
const KEY_LEFTALT: u16 = 56;
const KEY_RIGHTCTRL: u16 = 97;
const KEY_RIGHTALT: u16 = 100;
const KEY_LEFTMETA: u16 = 125;
const KEY_RIGHTMETA: u16 = 126;

const KEY_A: usize = 30;
const BTN_LEFT: usize = 0x110;
const BTN_SOUTH: usize = 0x130;
const BTN_TOUCH: usize = 0x14a;

// A bit for each modifier key, the right-hand one of a pair next to the left,
// so letting go of one side doesn't count as letting go of both.
const CTRL: u8 = 0b0000_0001;
const SHIFT: u8 = 0b0000_0100;
const ALT: u8 = 0b0001_0000;
const SUPER: u8 = 0b0100_0000;

const MODIFIERS: [(u16, u8); 8] = [
    (KEY_LEFTCTRL, CTRL),
    (KEY_RIGHTCTRL, CTRL << 1),
    (KEY_LEFTSHIFT, SHIFT),
    (KEY_RIGHTSHIFT, SHIFT << 1),
    (KEY_LEFTALT, ALT),
    (KEY_RIGHTALT, ALT << 1),
    (KEY_LEFTMETA, SUPER),
    (KEY_RIGHTMETA, SUPER << 1),
];

const IDLE: Duration = Duration::from_secs(300);
const COOLDOWN: Duration = Duration::from_secs(30);
const AFTER_OFF: Duration = Duration::from_secs(10);
const TAP: Duration = Duration::from_millis(500);

// Polled rather than notified, as in arcade-hotkey: inotify isn't in std, and
// two seconds is nothing next to how long the TV takes to come on.
const SCAN: Duration = Duration::from_secs(2);

// struct input_event on 64-bit Linux: a 16-byte timeval, then u16 type,
// u16 code and i32 value.
const EVENT_SIZE: usize = 24;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Class {
    Keyboard,
    Pointer,
    Gamepad,
}

impl Class {
    fn label(self) -> &'static str {
        match self {
            Class::Keyboard => "keyboard",
            Class::Pointer => "pointer",
            Class::Gamepad => "controller",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Trigger {
    Press,
    HomeButton,
    Arrival,
    OffKey,
}

#[derive(Debug, PartialEq)]
struct Options {
    wake: bool,
    idle: Duration,
    cooldown: Duration,
    off_key: bool,
    controllers_gone: Option<Duration>,
    vt: Option<u32>,
    marker: Option<String>,
    command: Vec<String>,
}

const DEFAULTS: Options = Options {
    wake: false,
    idle: IDLE,
    cooldown: COOLDOWN,
    off_key: false,
    controllers_gone: None,
    vt: None,
    marker: None,
    command: Vec::new(),
};

// Times are durations since boot, read from /proc/uptime. Instant leaves time
// spent suspended out on Linux, so a keyboard last used to type `systemctl
// suspend` would still look busy the next morning, and the first press after
// resuming wouldn't fire.
#[derive(Debug, Default)]
struct History {
    last_press: Option<Duration>,
    last_fire: Option<Duration>,
}

// One keyboard's modifiers, from its own presses and releases.
#[derive(Debug, Default)]
struct Modifiers {
    held: u8,
    chord: bool,
}

impl Modifiers {
    fn hyper(&self) -> bool {
        [CTRL, SHIFT, ALT, SUPER]
            .iter()
            .all(|&left| self.held & (left | left << 1) != 0)
    }
}

// Whether controllers were connected at the last scan, and since when there
// have been none.
#[derive(Debug, Default)]
struct Departure {
    connected: bool,
    since: Option<Duration>,
}

struct State {
    options: Options,
    history: Mutex<History>,
    watched: Mutex<HashSet<String>>,
}

fn parse(arguments: &[String]) -> Result<Options, String> {
    let mut options = DEFAULTS;
    let mut rest = arguments;

    while let Some(first) = rest.first() {
        let option = first.as_str();
        let value = || {
            rest.get(1)
                .ok_or_else(|| format!("{option} needs a value"))
        };
        let seconds = |value: &String| {
            value
                .parse()
                .map(Duration::from_secs)
                .map_err(|_| format!("{option} needs a number of seconds, not {value}"))
        };

        let taken = match option {
            "--" => {
                rest = &rest[1..];
                break;
            }
            "--wake" => {
                options.wake = true;
                1
            }
            "--off-key" => {
                options.off_key = true;
                1
            }
            "--idle" => {
                options.idle = seconds(value()?)?;
                2
            }
            "--cooldown" => {
                options.cooldown = seconds(value()?)?;
                2
            }
            "--controllers-gone" => {
                options.controllers_gone = Some(seconds(value()?)?);
                2
            }
            "--vt" => {
                let value = value()?;
                options.vt = Some(
                    value
                        .parse()
                        .map_err(|_| format!("--vt needs a terminal number, not {value}"))?,
                );
                2
            }
            "--marker" => {
                options.marker = Some(value()?.clone());
                2
            }
            _ if option.starts_with('-') => return Err(format!("unknown option {option}")),
            _ => break,
        };

        rest = &rest[taken..];
    }

    if rest.is_empty() {
        return Err("no command to run".to_string());
    }

    options.command = rest.to_vec();
    Ok(options)
}

fn classify(capabilities: &str) -> Option<Class> {
    // Space-separated hex words, most significant first, each as wide as a C
    // long, with high zero words left out. Reversed, word n holds codes 64n
    // to 64n + 63.
    let words: Vec<u64> = capabilities
        .split_whitespace()
        .rev()
        .map(|word| u64::from_str_radix(word, 16).unwrap_or(0))
        .collect();

    let has = |code: usize| {
        words
            .get(code / 64)
            .is_some_and(|word| word & (1 << (code % 64)) != 0)
    };

    // Keyboard first. Kanata's virtual device reports every code there is,
    // BTN_SOUTH included, so arcade-hotkey's gamepad test on its own would
    // turn the device all keystrokes come through into a controller, and
    // kanata restarting into a controller connecting. Controllers have no
    // KEY_A.
    if has(KEY_A) {
        Some(Class::Keyboard)
    } else if has(BTN_SOUTH) {
        Some(Class::Gamepad)
    } else if has(BTN_LEFT) || has(BTN_TOUCH) {
        Some(Class::Pointer)
    } else {
        None
    }
}

// A controller's key event, given when the PS button went down, if it's
// down. Times are the events' own, so a slow read can't stretch a tap.
fn controller_trigger(home: &mut Option<Duration>, code: u16, value: i32, time: Duration) -> Option<Trigger> {
    if code != BTN_MODE {
        return None;
    }

    match value {
        1 => {
            *home = Some(time);
            None
        }
        0 => home
            .take()
            .filter(|&down| time.saturating_sub(down) <= TAP)
            .map(|_| Trigger::HomeButton),
        _ => None,
    }
}

// A keyboard's key event, folded into its modifiers.
fn keyboard_trigger(modifiers: &mut Modifiers, code: u16, value: i32, off_key: bool) -> Option<Trigger> {
    if let Some(&(_, bit)) = MODIFIERS.iter().find(|(modifier, _)| *modifier == code) {
        match value {
            1 => {
                if modifiers.held == 0 {
                    modifiers.chord = false;
                }
                modifiers.held |= bit;
            }
            0 => {
                modifiers.held &= !bit;

                if modifiers.held == 0 && !modifiers.chord {
                    return Some(Trigger::Press);
                }
            }
            _ => {}
        }

        return None;
    }

    if value != 1 {
        return None;
    }

    if modifiers.held != 0 {
        modifiers.chord = true;
    }

    if off_key && code == KEY_ESC && modifiers.hyper() {
        Some(Trigger::OffKey)
    } else {
        Some(Trigger::Press)
    }
}

fn quiet_for(last: Option<Duration>, now: Duration, gap: Duration) -> bool {
    last.is_none_or(|time| now.saturating_sub(time) >= gap)
}

// Whether a trigger at `now` fires, recording it either way. `off` is when
// the TV was last turned off, if known.
fn decide(
    history: &mut History,
    trigger: Trigger,
    now: Duration,
    off: Option<Duration>,
    options: &Options,
) -> bool {
    let wanted = match trigger {
        // Keyboard activity like any other press, so a key brushed straight
        // after can't count as the first in a while.
        Trigger::OffKey => {
            history.last_press = Some(now);
            return true;
        }
        Trigger::Press => {
            let idle = quiet_for(history.last_press, now, options.idle);
            let back = off.is_some_and(|off| {
                now.saturating_sub(off) >= AFTER_OFF && history.last_fire.is_none_or(|fire| fire < off)
            });
            history.last_press = Some(now);
            idle || back
        }
        Trigger::HomeButton | Trigger::Arrival => true,
    };

    if !options.wake || !wanted || !quiet_for(history.last_fire, now, options.cooldown) {
        return false;
    }

    history.last_fire = Some(now);
    true
}

// A device arrived if the previous scan didn't list it, whether it's new or
// came back. The first scan has nothing to compare with, so nothing present
// at startup arrives. Comparing listings rather than asking which devices
// have a watcher means a device whose watcher keeps failing can't arrive
// over and over, and a Bluetooth link that drops and recovers between two
// scans doesn't count.
fn arrived(previous: Option<&BTreeSet<String>>, name: &str) -> bool {
    previous.is_some_and(|names| !names.contains(name))
}

// Whether every controller has now been gone for `wait`, given how many this
// scan found. Fires once per departure: only a controller connecting again
// starts another. None at startup is no departure at all.
fn all_gone(departure: &mut Departure, controllers: usize, now: Duration, wait: Duration) -> bool {
    if controllers > 0 {
        *departure = Departure {
            connected: true,
            since: None,
        };
        return false;
    }

    if departure.connected {
        *departure = Departure {
            connected: false,
            since: Some(now),
        };
    }

    match departure.since {
        Some(since) if now.saturating_sub(since) >= wait => {
            departure.since = None;
            true
        }
        _ => false,
    }
}

fn describe(duration: Duration) -> String {
    let seconds = duration.as_secs();

    match seconds {
        0..60 => format!("{seconds}s"),
        60..3600 => format!("{}m", seconds / 60),
        _ => format!("{}h{}m", seconds / 3600, seconds % 3600 / 60),
    }
}

fn since_boot() -> Option<Duration> {
    let uptime = fs::read_to_string("/proc/uptime").ok()?;
    let seconds: f64 = uptime.split_whitespace().next()?.parse().ok()?;
    Duration::try_from_secs_f64(seconds).ok()
}

// The marker's time, moved onto the clock since boot.
fn last_off(marker: &str, now: Duration) -> Option<Duration> {
    let modified = fs::metadata(marker).ok()?.modified().ok()?;
    let age = SystemTime::now().duration_since(modified).unwrap_or_default();
    Some(now.saturating_sub(age))
}

fn on_screen(vt: u32) -> bool {
    fs::read_to_string("/sys/class/tty/tty0/active").is_ok_and(|active| active.trim() == format!("tty{vt}"))
}

fn device_class(name: &str) -> Option<Class> {
    fs::read_to_string(format!("/sys/class/input/{name}/device/capabilities/key"))
        .ok()
        .and_then(|capabilities| classify(&capabilities))
}

fn device_name(name: &str) -> String {
    fs::read_to_string(format!("/sys/class/input/{name}/device/name"))
        .map(|text| text.trim().to_string())
        .unwrap_or_default()
}

// In a thread of its own, so a slow Home Assistant never holds up reading the
// devices.
fn run(state: &Arc<State>, action: &'static [&'static str]) {
    let state = Arc::clone(state);

    thread::spawn(move || {
        let command = &state.options.command;

        match Command::new(&command[0]).args(&command[1..]).args(action).status() {
            Ok(status) if !status.success() => eprintln!("av-input: {} {} failed, {status}", command[0], action[0]),
            Ok(_) => {}
            Err(error) => eprintln!("av-input: could not run {}: {error}", command[0]),
        }
    });
}

fn consider(trigger: Trigger, class: Class, name: &str, state: &Arc<State>) {
    let (fire, idle) = {
        let mut history = state.history.lock().unwrap();

        // Read under the lock so presses from two devices are recorded in
        // order. Zero only if /proc/uptime vanished mid-run, which the
        // cooldown turns into firing at most once more.
        let now = since_boot().unwrap_or_default();
        let idle = history.last_press.map(|time| now.saturating_sub(time));
        let off = state.options.marker.as_deref().and_then(|marker| last_off(marker, now));

        (decide(&mut history, trigger, now, off, &state.options), idle)
    };

    if !fire {
        return;
    }

    let what = class.label();

    match (trigger, idle) {
        (Trigger::Press, Some(idle)) => {
            eprintln!("av-input: {what} on {name} after {} idle", describe(idle))
        }
        (Trigger::Press, None) => eprintln!("av-input: {what} on {name}, first press since starting"),
        (Trigger::HomeButton, _) => eprintln!("av-input: PS button tapped on {name}"),
        (Trigger::Arrival, _) => eprintln!("av-input: {what} connected ({name})"),
        (Trigger::OffKey, _) => eprintln!("av-input: Hyper+Escape on {name}"),
    }

    run(state, if trigger == Trigger::OffKey { &["off"] } else { &["on"] });
}

fn watch(mut device: File, name: String, class: Class, state: Arc<State>) {
    let mut buffer = [0u8; EVENT_SIZE];
    let mut modifiers = Modifiers::default();
    let mut home = None;

    // A read error is the device going away (switched off, out of range,
    // unplugged), which ends this thread. The scan starts another if it comes
    // back.
    while device.read_exact(&mut buffer).is_ok() {
        let seconds = i64::from_ne_bytes(buffer[0..8].try_into().unwrap());
        let microseconds = i64::from_ne_bytes(buffer[8..16].try_into().unwrap());
        let kind = u16::from_ne_bytes([buffer[16], buffer[17]]);
        let code = u16::from_ne_bytes([buffer[18], buffer[19]]);
        let value = i32::from_ne_bytes([buffer[20], buffer[21], buffer[22], buffer[23]]);

        if kind != EV_KEY {
            continue;
        }

        let time = Duration::from_secs(seconds.max(0) as u64) + Duration::from_micros(microseconds.max(0) as u64);

        let trigger = match class {
            Class::Keyboard => keyboard_trigger(&mut modifiers, code, value, state.options.off_key),
            // Presses only: 0 is the release, and neither it nor a held
            // button is someone arriving.
            Class::Pointer => (value == 1).then_some(Trigger::Press),
            Class::Gamepad => controller_trigger(&mut home, code, value, time),
        };

        if let Some(trigger) = trigger {
            consider(trigger, class, &name, &state);
        }
    }

    eprintln!("av-input: {name} went away");
    state.watched.lock().unwrap().remove(&name);
}

fn main() {
    let arguments: Vec<String> = env::args().skip(1).collect();

    let options = parse(&arguments).unwrap_or_else(|message| {
        eprintln!("av-input: {message}");
        eprintln!("{USAGE}");
        process::exit(64);
    });

    // Checked up front so a sandbox that hides /proc/uptime (systemd's
    // ProcSubset=pid) fails the service instead of quietly firing nothing.
    if since_boot().is_none() {
        eprintln!("av-input: can't read the time since boot from /proc/uptime");
        process::exit(69);
    }

    let state = Arc::new(State {
        options,
        history: Mutex::new(History::default()),
        watched: Mutex::new(HashSet::new()),
    });

    let mut previous: Option<BTreeSet<String>> = None;
    let mut departure = Departure::default();

    loop {
        if let Ok(entries) = fs::read_dir("/dev/input") {
            let present: BTreeSet<String> = entries
                .flatten()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .filter(|name| name.starts_with("event"))
                .collect();

            for name in &present {
                if state.watched.lock().unwrap().contains(name) {
                    continue;
                }

                let Some(class) = device_class(name) else {
                    continue;
                };

                let device = match File::open(format!("/dev/input/{name}")) {
                    Ok(device) => device,
                    Err(error) => {
                        // Tried again every scan, but said once per
                        // appearance, so running without root doesn't fill
                        // the journal.
                        if previous.as_ref().is_none_or(|names| !names.contains(name)) {
                            eprintln!("av-input: can't read {name}: {error}");
                        }

                        continue;
                    }
                };

                state.watched.lock().unwrap().insert(name.clone());
                eprintln!("av-input: watching {name} ({}: {})", class.label(), device_name(name));

                if class == Class::Gamepad && arrived(previous.as_ref(), name) {
                    consider(Trigger::Arrival, class, name, &state);
                }

                let name = name.clone();
                let state = Arc::clone(&state);

                thread::spawn(move || watch(device, name, class, state));
            }

            if let Some(wait) = state.options.controllers_gone {
                let controllers = present
                    .iter()
                    .filter(|name| device_class(name) == Some(Class::Gamepad))
                    .count();
                let now = since_boot().unwrap_or_default();

                if all_gone(&mut departure, controllers, now, wait) {
                    match state.options.vt {
                        Some(vt) if !on_screen(vt) => {
                            eprintln!("av-input: no controller for {}, but tty{vt} isn't on screen", describe(wait))
                        }
                        _ => {
                            eprintln!("av-input: no controller for {}", describe(wait));
                            run(&state, &["off", "--automatic"]);
                        }
                    }
                }
            }

            previous = Some(present);
        }

        thread::sleep(SCAN);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn waking() -> Options {
        Options {
            wake: true,
            ..DEFAULTS
        }
    }

    const fn at(seconds: u64) -> Duration {
        Duration::from_secs(seconds)
    }

    // Replays triggers from a fresh start, with the TV last turned off at
    // `off`, and returns the times that fired.
    fn fired_after_off(off: Option<u64>, triggers: &[(u64, Trigger)]) -> Vec<u64> {
        let mut history = History::default();
        let options = waking();

        triggers
            .iter()
            .filter(|(seconds, trigger)| decide(&mut history, *trigger, at(*seconds), off.map(at), &options))
            .map(|(seconds, _)| *seconds)
            .collect()
    }

    fn fired(triggers: &[(u64, Trigger)]) -> Vec<u64> {
        fired_after_off(None, triggers)
    }

    // Feeds one keyboard (code, value) events and returns what each decided.
    fn keys(off_key: bool, events: &[(u16, i32)]) -> Vec<Trigger> {
        let mut modifiers = Modifiers::default();

        events
            .iter()
            .filter_map(|&(code, value)| keyboard_trigger(&mut modifiers, code, value, off_key))
            .collect()
    }

    const KEY_C: u16 = 46;

    // Hyper+Escape as kanata sends it: the four modifiers down, Escape down
    // and up, the four up.
    fn hyper_escape() -> Vec<(u16, i32)> {
        let modifiers = [KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTSHIFT, KEY_LEFTMETA];
        let mut events: Vec<_> = modifiers.iter().map(|&code| (code, 1)).collect();
        events.extend([(KEY_ESC, 1), (KEY_ESC, 0)]);
        events.extend(modifiers.iter().map(|&code| (code, 0)));
        events
    }

    fn names(list: &[&str]) -> BTreeSet<String> {
        list.iter().map(|name| name.to_string()).collect()
    }

    // Replays scans' controller counts, one every two seconds from zero, and
    // returns the times that fired.
    fn gone(counts: &[usize], wait: u64) -> Vec<u64> {
        let mut departure = Departure::default();

        counts
            .iter()
            .enumerate()
            .map(|(scan, &count)| (scan as u64 * 2, count))
            .filter(|&(seconds, count)| all_gone(&mut departure, count, at(seconds), at(wait)))
            .map(|(seconds, _)| seconds)
            .collect()
    }

    #[test]
    fn first_press_after_starting_fires() {
        assert_eq!(fired(&[(1000, Trigger::Press)]), [1000]);
    }

    #[test]
    fn typing_never_fires_again() {
        // A press every minute for two hours, each well inside the idle time.
        let typing: Vec<_> = (0..120).map(|minute| (minute * 60, Trigger::Press)).collect();
        assert_eq!(fired(&typing), [0]);
    }

    #[test]
    fn a_press_after_the_idle_time_fires() {
        assert_eq!(
            fired(&[(0, Trigger::Press), (299, Trigger::Press), (598, Trigger::Press), (898, Trigger::Press)]),
            [0, 898]
        );
    }

    #[test]
    fn a_press_inside_the_cooldown_still_counts_as_activity() {
        // The PS button fires. A first keyboard press 10 seconds later is
        // idle but inside the cooldown, and it restarts the idle time, so the
        // next one doesn't fire either.
        assert_eq!(
            fired(&[(0, Trigger::HomeButton), (10, Trigger::Press), (200, Trigger::Press)]),
            [0]
        );
    }

    #[test]
    fn the_ps_button_fires_on_each_press_outside_the_cooldown() {
        let presses = [0, 1, 2, 29, 30, 45, 61].map(|seconds| (seconds, Trigger::HomeButton));
        assert_eq!(fired(&presses), [0, 30, 61]);
    }

    #[test]
    fn every_trigger_shares_the_cooldown() {
        assert_eq!(
            fired(&[(0, Trigger::Arrival), (5, Trigger::HomeButton), (20, Trigger::Press), (31, Trigger::Arrival)]),
            [0, 31]
        );
    }

    #[test]
    fn the_ps_button_leaves_the_idle_time_alone() {
        assert_eq!(fired(&[(0, Trigger::HomeButton), (40, Trigger::Press)]), [0, 40]);
    }

    #[test]
    fn nothing_turns_the_tv_on_without_wake() {
        let mut history = History::default();
        let options = DEFAULTS;

        for (seconds, trigger) in [(0, Trigger::Press), (400, Trigger::HomeButton), (500, Trigger::Arrival)] {
            assert!(!decide(&mut history, trigger, at(seconds), None, &options));
        }
    }

    #[test]
    fn the_off_key_always_fires_and_counts_as_typing() {
        // Idle for ten minutes, then Hyper+Escape, then a key brushed two
        // seconds later: the brush is inside the idle time Hyper+Escape just
        // restarted.
        assert_eq!(
            fired(&[(0, Trigger::Press), (600, Trigger::OffKey), (602, Trigger::Press)]),
            [0, 600]
        );

        let mut history = History::default();
        assert!(decide(&mut history, Trigger::OffKey, at(0), None, &DEFAULTS));
    }

    #[test]
    fn the_first_press_after_an_off_turns_the_tv_back_on() {
        // On at 0, off at 100, typing throughout: the presses inside ten
        // seconds of the off are ignored, the next fires, and the rest are
        // typing again.
        let typing: Vec<_> = [0, 60, 101, 105, 112, 120, 180].map(|seconds| (seconds, Trigger::Press)).to_vec();
        assert_eq!(fired_after_off(Some(100), &typing), [0, 112]);
    }

    #[test]
    fn an_off_before_the_last_on_changes_nothing() {
        assert_eq!(
            fired_after_off(
                Some(50),
                &[(0, Trigger::Press), (60, Trigger::HomeButton), (100, Trigger::Press), (200, Trigger::Press)]
            ),
            [0, 60]
        );
    }

    #[test]
    fn a_lone_modifier_counts_when_let_go() {
        assert_eq!(keys(false, &[(KEY_LEFTSHIFT, 1)]), []);
        assert_eq!(keys(false, &[(KEY_LEFTSHIFT, 1), (KEY_LEFTSHIFT, 2), (KEY_LEFTSHIFT, 0)]), [Trigger::Press]);
        assert_eq!(keys(false, &[(KEY_LEFTCTRL, 1), (KEY_LEFTSHIFT, 1), (KEY_LEFTSHIFT, 0), (KEY_LEFTCTRL, 0)]), [Trigger::Press]);
    }

    #[test]
    fn a_chord_counts_once_on_its_key() {
        assert_eq!(
            keys(false, &[(KEY_LEFTCTRL, 1), (KEY_C, 1), (KEY_C, 0), (KEY_LEFTCTRL, 0)]),
            [Trigger::Press]
        );
    }

    #[test]
    fn hyper_escape_turns_the_tv_off_only_when_asked_to() {
        assert_eq!(keys(true, &hyper_escape()), [Trigger::OffKey]);
        assert_eq!(keys(false, &hyper_escape()), [Trigger::Press]);
    }

    #[test]
    fn escape_without_all_of_hyper_is_a_press() {
        assert_eq!(keys(true, &[(KEY_ESC, 1), (KEY_ESC, 0)]), [Trigger::Press]);
        assert_eq!(
            keys(true, &[(KEY_LEFTCTRL, 1), (KEY_LEFTALT, 1), (KEY_LEFTSHIFT, 1), (KEY_ESC, 1)]),
            [Trigger::Press]
        );
    }

    #[test]
    fn either_side_of_a_modifier_counts() {
        let events = [(KEY_RIGHTCTRL, 1), (KEY_LEFTALT, 1), (KEY_LEFTSHIFT, 1), (KEY_LEFTMETA, 1), (KEY_ESC, 1)];
        assert_eq!(keys(true, &events), [Trigger::OffKey]);
    }

    #[test]
    fn letting_go_of_one_side_keeps_the_other() {
        let events = [
            (KEY_LEFTCTRL, 1),
            (KEY_RIGHTCTRL, 1),
            (KEY_LEFTCTRL, 0),
            (KEY_LEFTALT, 1),
            (KEY_LEFTSHIFT, 1),
            (KEY_LEFTMETA, 1),
            (KEY_ESC, 1),
        ];
        assert_eq!(keys(true, &events), [Trigger::OffKey]);
    }

    #[test]
    fn a_held_key_repeating_is_one_press() {
        assert_eq!(keys(false, &[(KEY_C, 1), (KEY_C, 2), (KEY_C, 2), (KEY_C, 0)]), [Trigger::Press]);
    }

    #[test]
    fn devices_present_at_startup_never_arrive() {
        assert!(!arrived(None, "event15"));
    }

    #[test]
    fn a_device_missing_from_the_previous_scan_arrives() {
        let previous = names(&["event12", "event14"]);
        assert!(arrived(Some(&previous), "event15"));
        assert!(!arrived(Some(&previous), "event14"));
    }

    #[test]
    fn a_controller_that_leaves_and_comes_back_arrives_again() {
        let connected = names(&["event12", "event15"]);
        let asleep = names(&["event12"]);
        assert!(!arrived(Some(&connected), "event15"));
        assert!(arrived(Some(&asleep), "event15"));
    }

    // Feeds one controller (code, value, milliseconds) events and returns what
    // each decided.
    fn buttons(events: &[(u16, i32, u64)]) -> Vec<Trigger> {
        let mut home = None;

        events
            .iter()
            .filter_map(|&(code, value, millis)| {
                controller_trigger(&mut home, code, value, Duration::from_millis(millis))
            })
            .collect()
    }

    #[test]
    fn a_tap_of_the_ps_button_counts_when_let_go() {
        assert_eq!(buttons(&[(BTN_MODE, 1, 1000)]), []);
        assert_eq!(buttons(&[(BTN_MODE, 1, 1000), (BTN_MODE, 0, 1120)]), [Trigger::HomeButton]);
        assert_eq!(buttons(&[(BTN_MODE, 1, 1000), (BTN_MODE, 0, 1500)]), [Trigger::HomeButton]);
    }

    #[test]
    fn holding_the_ps_button_never_counts() {
        // Let go after a second, and the hold that switches a DualSense off,
        // whose device goes away before any release.
        assert_eq!(buttons(&[(BTN_MODE, 1, 1000), (BTN_MODE, 0, 2000)]), []);
        assert_eq!(buttons(&[(BTN_MODE, 1, 1000)]), []);
    }

    #[test]
    fn each_tap_of_a_triple_counts() {
        let taps = [0, 300, 600].map(|start| [(BTN_MODE, 1, start), (BTN_MODE, 0, start + 100)]);
        assert_eq!(buttons(&taps.concat()), [Trigger::HomeButton; 3]);
    }

    #[test]
    fn other_buttons_and_a_stray_release_are_nothing() {
        assert_eq!(buttons(&[(BTN_SOUTH as u16, 1, 0), (BTN_SOUTH as u16, 0, 100)]), []);
        assert_eq!(buttons(&[(BTN_MODE, 0, 100)]), []);
        assert_eq!(buttons(&[(BTN_MODE, 1, 0), (BTN_SOUTH as u16, 1, 50), (BTN_MODE, 0, 100)]), [Trigger::HomeButton]);
    }

    #[test]
    fn no_controllers_since_starting_never_fires() {
        assert_eq!(gone(&[0; 60], 30), []);
    }

    #[test]
    fn the_last_controller_leaving_fires_once_after_the_wait() {
        // Two controllers, then one, then none from 8 seconds.
        let mut counts = vec![2, 2, 1, 1];
        counts.extend([0; 40]);
        assert_eq!(gone(&counts, 30), [38]);
    }

    #[test]
    fn a_controller_back_inside_the_wait_cancels_it() {
        let mut counts = vec![1, 0, 0, 0, 0, 1, 1];
        counts.extend([0; 20]);
        assert_eq!(gone(&counts, 30), [44]);
    }

    #[test]
    fn each_departure_fires_again() {
        let mut counts = vec![1];
        counts.extend([0; 20]);
        counts.push(1);
        counts.extend([0; 20]);
        assert_eq!(gone(&counts, 30), [32, 74]);
    }

    // /sys/class/input/event*/device/capabilities/key on Irulan, 2026-11-07.
    #[test]
    fn classifies_irulans_devices() {
        let devices = [
            ("Sleep Button", "4000 0 0", None),
            ("Power Button", "8000 10000000000000 0", None),
            ("Video Bus", "3e000b00000000 0 0 0", None),
            ("HDA Intel PCH Front Headphone", "0", None),
            (
                "kanata",
                "ffffffffffff ffffffffffffffff ffffffffffffffff ffffffffffffffff ffffffffffffffff \
                 ffffffffffffffff ffffffffffffffff ffffffffffffffff fffffffffffffffe",
                Some(Class::Keyboard),
            ),
            ("BlueZ 5.87 (MCS)", "300 6800000000 0 0", None),
            ("Apple Inc. Magic Trackpad", "e520 10000 0 0 0 0", Some(Class::Pointer)),
            ("DualSense Wireless Controller", "7fdb000000000000 0 0 0 0", Some(Class::Gamepad)),
            ("DualSense Wireless Controller Motion Sensors", "0", None),
            (
                "Teclado",
                "10000 0 0 1 101007b02001007 ff98003a000047ff ffbeffdfffefffff fffffffffffffffe",
                Some(Class::Keyboard),
            ),
            ("DualSense Wireless Controller Touchpad", "2420 10000 0 0 0 0", Some(Class::Pointer)),
        ];

        for (name, capabilities, class) in devices {
            assert_eq!(classify(capabilities), class, "{name}");
        }
    }

    fn arguments(list: &[&str]) -> Vec<String> {
        list.iter().map(|argument| argument.to_string()).collect()
    }

    #[test]
    fn parses_options_and_command() {
        assert_eq!(
            parse(&arguments(&[
                "--wake",
                "--idle",
                "600",
                "--cooldown",
                "5",
                "--off-key",
                "--controllers-gone",
                "30",
                "--vt",
                "7",
                "--marker",
                "/run/av/off",
                "--",
                "av",
            ])),
            Ok(Options {
                wake: true,
                idle: at(600),
                cooldown: at(5),
                off_key: true,
                controllers_gone: Some(at(30)),
                vt: Some(7),
                marker: Some("/run/av/off".to_string()),
                command: arguments(&["av"]),
            })
        );

        assert_eq!(
            parse(&arguments(&["--", "av", "--cooldown"])).map(|options| options.command),
            Ok(arguments(&["av", "--cooldown"]))
        );

        assert_eq!(
            parse(&arguments(&["av"])),
            Ok(Options {
                command: arguments(&["av"]),
                ..DEFAULTS
            })
        );
    }

    #[test]
    fn rejects_bad_arguments() {
        for bad in [
            &[][..],
            &["--"],
            &["--idle", "300"],
            &["--idle"],
            &["--idle", "5m", "--", "av"],
            &["--idle", "-1", "--", "av"],
            &["--wait", "3", "--", "av"],
            &["--vt", "tty7", "--", "av"],
            &["--marker"],
        ] {
            assert!(parse(&arguments(bad)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn describes_idle_times() {
        assert_eq!(describe(at(45)), "45s");
        assert_eq!(describe(at(41 * 60 + 20)), "41m");
        assert_eq!(describe(at(3 * 3600 + 5 * 60)), "3h5m");
    }
}
