// Runs a command when someone sits down at Irulan and picks up a keyboard,
// the trackpad or a controller: `av on`, so the TV and receiver come on
// without anyone reaching for a remote.
//
// An earlier version turned the TV on every two seconds, which made it
// impossible to switch off, so what counts is deliberately narrow. Three
// things do, each because it means someone has just arrived:
//
//   - A keyboard or pointer press after none for a while (five minutes by
//     default). Every press restarts that wait, so typing never fires twice
//     and switching the TV off from the keyboard isn't undone by the next
//     keystroke. The first press after starting counts as after a wait.
//   - A controller's PS/Home button, on a single press.
//   - A controller connecting. A DualSense that's off wakes and connects
//     when its PS button is pressed, but that press happens before its event
//     device exists, so the connection is all there is to see. Controllers
//     already connected at startup don't count, so restarting this never
//     fires.
//
// Nothing fires within a cooldown (30 seconds by default) of the last time
// anything did, so waking a controller and then pressing its PS button again
// sends one command, not two.
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
//
// usage: av-wake [--idle SECONDS] [--cooldown SECONDS] -- <command> [arguments...]

use std::collections::{BTreeSet, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::process::{self, Command};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const USAGE: &str =
    "usage: av-wake [--idle SECONDS] [--cooldown SECONDS] -- <command> [arguments...]";

const EV_KEY: u16 = 0x01;
const BTN_MODE: u16 = 0x13c;

const KEY_A: usize = 30;
const BTN_LEFT: usize = 0x110;
const BTN_SOUTH: usize = 0x130;
const BTN_TOUCH: usize = 0x14a;

const IDLE: Duration = Duration::from_secs(300);
const COOLDOWN: Duration = Duration::from_secs(30);

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
}

#[derive(Debug, PartialEq)]
struct Options {
    idle: Duration,
    cooldown: Duration,
    command: Vec<String>,
}

// Times are durations since boot, read from /proc/uptime. Instant leaves time
// spent suspended out on Linux, so a keyboard last used to type `systemctl
// suspend` would still look busy the next morning, and the first press after
// resuming wouldn't fire.
#[derive(Debug, Default)]
struct History {
    last_press: Option<Duration>,
    last_fire: Option<Duration>,
}

struct State {
    options: Options,
    history: Mutex<History>,
    watched: Mutex<HashSet<String>>,
}

fn parse(arguments: &[String]) -> Result<Options, String> {
    let mut idle = IDLE;
    let mut cooldown = COOLDOWN;
    let mut rest = arguments;

    while let Some(first) = rest.first() {
        let setting = match first.as_str() {
            "--" => {
                rest = &rest[1..];
                break;
            }
            "--idle" => &mut idle,
            "--cooldown" => &mut cooldown,
            option if option.starts_with('-') => return Err(format!("unknown option {option}")),
            _ => break,
        };

        let value = rest
            .get(1)
            .ok_or_else(|| format!("{first} needs a number of seconds"))?;

        *setting = value
            .parse()
            .map(Duration::from_secs)
            .map_err(|_| format!("{first} needs a number of seconds, not {value}"))?;

        rest = &rest[2..];
    }

    if rest.is_empty() {
        return Err("no command to run".to_string());
    }

    Ok(Options {
        idle,
        cooldown,
        command: rest.to_vec(),
    })
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

fn trigger_for(class: Class, code: u16) -> Option<Trigger> {
    match class {
        Class::Keyboard | Class::Pointer => Some(Trigger::Press),
        Class::Gamepad if code == BTN_MODE => Some(Trigger::HomeButton),
        Class::Gamepad => None,
    }
}

fn quiet_for(last: Option<Duration>, now: Duration, gap: Duration) -> bool {
    last.is_none_or(|time| now.saturating_sub(time) >= gap)
}

// Whether a trigger at `now` fires, recording it either way.
fn decide(history: &mut History, trigger: Trigger, now: Duration, options: &Options) -> bool {
    let wanted = match trigger {
        Trigger::Press => {
            let idle = quiet_for(history.last_press, now, options.idle);
            history.last_press = Some(now);
            idle
        }
        Trigger::HomeButton | Trigger::Arrival => true,
    };

    if !wanted || !quiet_for(history.last_fire, now, options.cooldown) {
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

fn consider(trigger: Trigger, class: Class, name: &str, state: &Arc<State>) {
    let (fire, idle) = {
        let mut history = state.history.lock().unwrap();

        // Read under the lock so presses from two devices are recorded in
        // order. Zero only if /proc/uptime vanished mid-run, which the
        // cooldown turns into firing at most once more.
        let now = since_boot().unwrap_or_default();
        let idle = history.last_press.map(|time| now.saturating_sub(time));

        (decide(&mut history, trigger, now, &state.options), idle)
    };

    if !fire {
        return;
    }

    let what = class.label();

    match (trigger, idle) {
        (Trigger::Press, Some(idle)) => {
            eprintln!("av-wake: {what} on {name} after {} idle", describe(idle))
        }
        (Trigger::Press, None) => eprintln!("av-wake: {what} on {name}, first press since starting"),
        (Trigger::HomeButton, _) => eprintln!("av-wake: PS button on {name}"),
        (Trigger::Arrival, _) => eprintln!("av-wake: {what} connected ({name})"),
    }

    // In a thread of its own, so a slow Home Assistant never holds up reading
    // the devices.
    let state = Arc::clone(state);

    thread::spawn(move || {
        let command = &state.options.command;

        match Command::new(&command[0]).args(&command[1..]).status() {
            Ok(status) if !status.success() => eprintln!("av-wake: {} failed, {status}", command[0]),
            Ok(_) => {}
            Err(error) => eprintln!("av-wake: could not run {}: {error}", command[0]),
        }
    });
}

fn watch(mut device: File, name: String, class: Class, state: Arc<State>) {
    let mut buffer = [0u8; EVENT_SIZE];

    // A read error is the device going away (switched off, out of range,
    // unplugged), which ends this thread. The scan starts another if it comes
    // back.
    while device.read_exact(&mut buffer).is_ok() {
        let kind = u16::from_ne_bytes([buffer[16], buffer[17]]);
        let code = u16::from_ne_bytes([buffer[18], buffer[19]]);
        let value = i32::from_ne_bytes([buffer[20], buffer[21], buffer[22], buffer[23]]);

        // Presses only: 0 is the release and 2 the repeat a held key sends,
        // and neither is someone arriving.
        if kind != EV_KEY || value != 1 {
            continue;
        }

        if let Some(trigger) = trigger_for(class, code) {
            consider(trigger, class, &name, &state);
        }
    }

    eprintln!("av-wake: {name} went away");
    state.watched.lock().unwrap().remove(&name);
}

fn main() {
    let arguments: Vec<String> = env::args().skip(1).collect();

    let options = parse(&arguments).unwrap_or_else(|message| {
        eprintln!("av-wake: {message}");
        eprintln!("{USAGE}");
        process::exit(64);
    });

    // Checked up front so a sandbox that hides /proc/uptime (systemd's
    // ProcSubset=pid) fails the service instead of quietly firing nothing.
    if since_boot().is_none() {
        eprintln!("av-wake: can't read the time since boot from /proc/uptime");
        process::exit(69);
    }

    let state = Arc::new(State {
        options,
        history: Mutex::new(History::default()),
        watched: Mutex::new(HashSet::new()),
    });

    let mut previous: Option<BTreeSet<String>> = None;

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
                            eprintln!("av-wake: can't read {name}: {error}");
                        }

                        continue;
                    }
                };

                state.watched.lock().unwrap().insert(name.clone());
                eprintln!("av-wake: watching {name} ({}: {})", class.label(), device_name(name));

                if class == Class::Gamepad && arrived(previous.as_ref(), name) {
                    consider(Trigger::Arrival, class, name, &state);
                }

                let name = name.clone();
                let state = Arc::clone(&state);

                thread::spawn(move || watch(device, name, class, state));
            }

            previous = Some(present);
        }

        thread::sleep(SCAN);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OPTIONS: Options = Options {
        idle: IDLE,
        cooldown: COOLDOWN,
        command: Vec::new(),
    };

    const fn at(seconds: u64) -> Duration {
        Duration::from_secs(seconds)
    }

    // Replays triggers from a fresh start and returns the times that fired.
    fn fired(triggers: &[(u64, Trigger)]) -> Vec<u64> {
        let mut history = History::default();

        triggers
            .iter()
            .filter(|(seconds, trigger)| decide(&mut history, *trigger, at(*seconds), &OPTIONS))
            .map(|(seconds, _)| *seconds)
            .collect()
    }

    fn names(list: &[&str]) -> BTreeSet<String> {
        list.iter().map(|name| name.to_string()).collect()
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

    #[test]
    fn only_controllers_respond_to_the_ps_button_alone() {
        assert_eq!(trigger_for(Class::Gamepad, BTN_MODE), Some(Trigger::HomeButton));
        assert_eq!(trigger_for(Class::Gamepad, 0x130), None);
        assert_eq!(trigger_for(Class::Keyboard, 30), Some(Trigger::Press));
        assert_eq!(trigger_for(Class::Pointer, 0x14a), Some(Trigger::Press));
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
            parse(&arguments(&["--idle", "600", "--cooldown", "5", "--", "av", "on"])),
            Ok(Options {
                idle: at(600),
                cooldown: at(5),
                command: arguments(&["av", "on"]),
            })
        );

        assert_eq!(
            parse(&arguments(&["--", "av", "--cooldown"])).map(|options| options.command),
            Ok(arguments(&["av", "--cooldown"]))
        );

        assert_eq!(
            parse(&arguments(&["av", "on"])),
            Ok(Options {
                idle: IDLE,
                cooldown: COOLDOWN,
                command: arguments(&["av", "on"]),
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
