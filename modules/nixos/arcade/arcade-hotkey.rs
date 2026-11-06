// Tapping the PS/Home button three times quickly on any gamepad runs a
// command: on Irulan, the switch between the emulator station and the desktop.
//
// It used to be a hold, but holding PS is also how a DualSense turns itself
// off, so a hold long enough to switch was the start of one that powered the
// pad down, and the pad waking again took Pegasus with it. One or two presses
// are RetroArch's menu, so three it is. They still reach RetroArch, whose
// menu ends up open on the way out of a game, which is harmless.
//
// Reads /dev/input/event* directly rather than through SDL or a desktop's
// input stack, so it works on whichever virtual terminal is showing,
// including a text console, and needs nothing but root. Devices are only
// read, never grabbed, so every press still reaches whatever else is
// listening. Built by `pkgs.rustTool` in overlays/default.nix.
//
// usage: arcade-hotkey <command> [arguments...]

use std::collections::HashSet;
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::process::{self, Command};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const EV_KEY: u16 = 0x01;
const BTN_MODE: u16 = 0x13c;

// Every gamepad reports this button, and no keyboard, mouse or the
// DualSense's separate touchpad and motion-sensor devices do, which makes it
// the test for "is this a controller".
const BTN_SOUTH: usize = 0x130;

const TAPS: u32 = 3;

// The most time between one press and the next for them to count as one
// gesture. Quick enough that two separate trips into RetroArch's menu don't
// add up to a switch.
const GAP: Duration = Duration::from_millis(500);

// Two controllers can't bounce the screen back and forth between them, and
// six quick taps switch once, not twice.
const COOLDOWN: Duration = Duration::from_secs(2);

// struct input_event on 64-bit Linux: a 16-byte timeval, then u16 type,
// u16 code and i32 value.
const EVENT_SIZE: usize = 24;

fn is_gamepad(event: &str) -> bool {
    let path = format!("/sys/class/input/{event}/device/capabilities/key");
    let Ok(bits) = fs::read_to_string(path) else {
        return false;
    };

    // Space-separated hex words, most significant first, each as wide as a
    // C long. Trailing zero words are omitted, so count from the end.
    let words: Vec<&str> = bits.split_whitespace().collect();
    let index = BTN_SOUTH / 64;

    let Some(position) = words.len().checked_sub(index + 1) else {
        return false;
    };

    u64::from_str_radix(words[position], 16)
        .map(|word| word & (1 << (BTN_SOUTH % 64)) != 0)
        .unwrap_or(false)
}

fn fire(command: &[String], last: &Mutex<Option<Instant>>) {
    let mut last = last.lock().unwrap();

    if last.is_some_and(|time| time.elapsed() < COOLDOWN) {
        return;
    }

    *last = Some(Instant::now());

    if let Err(error) = Command::new(&command[0]).args(&command[1..]).status() {
        eprintln!("arcade-hotkey: could not run {}: {error}", command[0]);
    }
}

fn watch(
    name: String,
    command: Arc<Vec<String>>,
    watched: Arc<Mutex<HashSet<String>>>,
    last: Arc<Mutex<Option<Instant>>>,
) {
    if let Ok(mut device) = File::open(format!("/dev/input/{name}")) {
        eprintln!("arcade-hotkey: watching {name}");

        // Taps so far in the current gesture, and when the latest landed.
        // Per controller, so two pads' presses never combine into one.
        let mut taps = 0u32;
        let mut previous: Option<Instant> = None;
        let mut buffer = [0u8; EVENT_SIZE];

        // A read error is the controller going away (disconnected, out of
        // battery), which ends this thread; the scan picks it up again when
        // it reconnects.
        while device.read_exact(&mut buffer).is_ok() {
            let kind = u16::from_ne_bytes([buffer[16], buffer[17]]);
            let code = u16::from_ne_bytes([buffer[18], buffer[19]]);
            let value = i32::from_ne_bytes([buffer[20], buffer[21], buffer[22], buffer[23]]);

            // Presses only: 0 is the release and 2 the key repeat a held
            // button sends, neither of which is a tap.
            if kind != EV_KEY || code != BTN_MODE || value != 1 {
                continue;
            }

            let now = Instant::now();

            if previous.is_none_or(|time| now.duration_since(time) > GAP) {
                taps = 0;
            }

            taps += 1;
            previous = Some(now);

            if taps == TAPS {
                taps = 0;
                fire(&command, &last);
            }
        }
    }

    watched.lock().unwrap().remove(&name);
}

fn main() {
    let command: Vec<String> = env::args().skip(1).collect();

    if command.is_empty() {
        eprintln!("usage: arcade-hotkey <command> [arguments...]");
        process::exit(64);
    }

    let command = Arc::new(command);
    let watched = Arc::new(Mutex::new(HashSet::new()));
    let last = Arc::new(Mutex::new(None));

    // Polled rather than notified: Bluetooth controllers come and go, and a
    // two-second delay before a newly paired one counts is invisible in
    // practice, where inotify on /dev/input would be the only std-only
    // alternative and isn't in std.
    loop {
        if let Ok(entries) = fs::read_dir("/dev/input") {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();

                if !name.starts_with("event") || !is_gamepad(&name) {
                    continue;
                }

                if !watched.lock().unwrap().insert(name.clone()) {
                    continue;
                }

                let command = Arc::clone(&command);
                let watched = Arc::clone(&watched);
                let last = Arc::clone(&last);

                thread::spawn(move || watch(name, command, watched, last));
            }
        }

        thread::sleep(Duration::from_secs(2));
    }
}
