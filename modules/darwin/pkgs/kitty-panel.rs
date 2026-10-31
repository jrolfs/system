// Drives a kitty panel's animation over its remote-control socket: the slide
// that moves the panel window on and off the right edge of the screen, and the
// progress bar drawn in its tab bar while a command runs in it.
//
// Exists because both need a frame rate a shell cannot give them. Each
// `kitten @` is a process spawn and a fresh socket connection, about 20ms on
// this machine, so a 220ms slide driven that way gets ten frames and looks like
// it is stepping. Here one connection stays open for the whole animation and a
// frame costs a single write, which is how the slide gets twenty-odd.
//
// The slide moves the window rather than animating its contents in a shader,
// because macOS draws background_blur behind the window as soon as it is on
// screen: a shader can slide the text in, but the frosted pane would already
// be sitting at its final position.
//
// Built by `pkgs.rustTool` in overlays/default.nix, which is plain rustc with no
// crates, so the JSON below is written by hand.

use std::f64::consts::TAU;
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::process::ExitCode;
use std::thread::sleep;
use std::time::{Duration, Instant};

// The framing `kitten @` puts around a command, captured from its own traffic.
// `no_response` is what makes a frame one write and nothing else: kitty sends
// no reply, so there is never a read to wait on between frames.
const COMMAND_START: &[u8] = b"\x1bP@kitty-cmd";
const COMMAND_END: &[u8] = b"\x1b\\";

struct Panel {
    socket: UnixStream,
}

impl Panel {
    // Accepts the address the way kitty prints it in $KITTY_LISTEN_ON, so the
    // command running inside the panel can pass that straight through.
    fn connect(address: &str) -> std::io::Result<Panel> {
        let path = address.strip_prefix("unix:").unwrap_or(address);
        Ok(Panel { socket: UnixStream::connect(path)? })
    }

    fn send(&mut self, command: &str, payload: &str) -> std::io::Result<()> {
        let body = format!(
            r#"{{"cmd":"{command}","version":[0,26,0],"no_response":true,"payload":{payload}}}"#
        );
        let mut frame = Vec::with_capacity(COMMAND_START.len() + body.len() + COMMAND_END.len());
        frame.extend_from_slice(COMMAND_START);
        frame.extend_from_slice(body.as_bytes());
        frame.extend_from_slice(COMMAND_END);
        self.socket.write_all(&frame)
    }
}

// Enough of JSON's string escaping for a tab title, which is whatever label the
// caller passed plus the bar this draws. Everything outside ASCII goes through
// as UTF-8, which JSON allows.
fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if (control as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", control as u32))
            }
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

// Comfortably above the 60 to 120Hz a display refreshes at, so the window is
// never waiting on this. Where a frame lands is worked out from the clock, so a
// late frame shortens nothing; it only draws a little further along.
const FRAME: Duration = Duration::from_micros(8_333);

#[derive(Clone, Copy)]
enum Direction {
    // Arrives quickly and settles, which reads as the panel being placed.
    In,
    // Leaves slowly and accelerates away, which reads as it being dismissed.
    Out,
}

fn ease(direction: Direction, t: f64) -> f64 {
    match direction {
        Direction::In => 1.0 - (1.0 - t).powi(3),
        Direction::Out => t.powi(3),
    }
}

// Moves the panel's left edge from one x to another. `margin-left` with the
// dash, not the underscore the conf file uses: resize-os-window takes the
// panel kitten's flag names, and reports a wrong one only in a reply that
// `no_response` throws away.
fn slide(panel: &mut Panel, direction: Direction, from: f64, to: f64, duration: Duration) -> std::io::Result<()> {
    let start = Instant::now();
    let mut last = None;

    loop {
        let t = (start.elapsed().as_secs_f64() / duration.as_secs_f64()).min(1.0);
        let x = (from + (to - from) * ease(direction, t)).round() as i64;

        // Every frame is a relayout on kitty's side, so a frame that would not
        // move the window by a whole point is not sent.
        if last != Some(x) {
            panel.send(
                "resize-os-window",
                &format!(r#"{{"incremental":true,"action":"os-panel","unit":"cells","os_panel":["margin-left={x}"]}}"#),
            )?;
            last = Some(x);
        }

        if t >= 1.0 {
            return Ok(());
        }
        sleep(FRAME);
    }
}

// Eighth-height blocks, so each cell of the one-row tab bar is a column whose
// height can vary, and a row of them draws a waveform.
const BLOCKS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

// The tallest block the bar uses. Full height reads as a loading bar shouting
// at you; stopping short keeps it a texture.
const PEAK: f64 = 5.0;

// A title change re-renders the whole tab bar, and nothing about a slow swell
// needs more than this.
const TICK: Duration = Duration::from_millis(83);

// Heights for one frame of the bar, `width` cells across at `seconds` in.
//
// Two layers. A swell, a Gaussian bump drifting back and forth across the bar,
// sets where it is tall, and its soft edges are what make the heights grade
// smoothly instead of stepping. A ripple travelling through it keeps the swell
// moving even while the bump itself is near the end of a pass. The floor is the
// lowest block, so the track is always drawn and the bar never goes blank.
fn wave(width: usize, seconds: f64) -> String {
    if width == 0 {
        return String::new();
    }

    // Ping-pong rather than wrap, so the swell turns around instead of leaving
    // one end and reappearing at the other.
    let pass = (seconds / 3.2) % 2.0;
    let centre = if pass < 1.0 { pass } else { 2.0 - pass };
    let spread = 0.22;

    (0..width)
        .map(|cell| {
            let position = cell as f64 / (width.max(2) - 1) as f64;
            let swell = (-((position - centre) / spread).powi(2)).exp();
            let ripple = 0.5 + 0.5 * (TAU * (position * 3.0 - seconds * 0.9)).sin();
            let height = PEAK * swell * (0.55 + 0.45 * ripple);
            BLOCKS[(height.round() as usize).min(BLOCKS.len() - 1)]
        })
        .collect()
}

fn elapsed(seconds: u64) -> String {
    match seconds {
        hours if hours >= 3600 => format!("{}:{:02}:{:02}", hours / 3600, hours % 3600 / 60, hours % 60),
        _ => format!("{}:{:02}", seconds / 60, seconds % 60),
    }
}

// Keeps the tab title animated until the process is killed, which is how the
// caller stops it: it then sets the final title itself. `columns` is the
// panel's width in cells, so the title fills the tab bar and the one tab is
// the whole bar.
fn progress(panel: &mut Panel, label: &str, columns: usize) -> std::io::Result<()> {
    let start = Instant::now();
    loop {
        let seconds = start.elapsed().as_secs_f64();
        let clock = elapsed(seconds as u64);

        // Two spaces of margin at each end and between the parts.
        let used = label.chars().count() + clock.chars().count() + 8;
        let bar = wave(columns.saturating_sub(used), seconds);
        let title = format!("  {label}  {bar}  {clock}  ");

        panel.send("set-tab-title", &format!(r#"{{"title":{},"match":null}}"#, json_string(&title)))?;
        sleep(TICK);
    }
}

const USAGE: &str = "usage: kitty-panel slide in|out <address> <from-x> <to-x> <milliseconds>
       kitty-panel progress <address> <columns> <label...>";

// sysexits.h, as fda-run uses elsewhere in this repo.
const EX_USAGE: u8 = 64;
const EX_UNAVAILABLE: u8 = 69;
const EX_IOERR: u8 = 74;

fn usage() -> ExitCode {
    eprintln!("{USAGE}");
    ExitCode::from(EX_USAGE)
}

fn connect(address: &str) -> Result<Panel, ExitCode> {
    Panel::connect(address).map_err(|error| {
        eprintln!("kitty-panel: cannot reach {address}: {error}");
        ExitCode::from(EX_UNAVAILABLE)
    })
}

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let arguments: Vec<&str> = arguments.iter().map(String::as_str).collect();

    match arguments.as_slice() {
        ["slide", direction, address, from, to, milliseconds] => {
            let direction = match *direction {
                "in" => Direction::In,
                "out" => Direction::Out,
                _ => return usage(),
            };
            let (Ok(from), Ok(to), Ok(milliseconds)) =
                (from.parse::<f64>(), to.parse::<f64>(), milliseconds.parse::<u64>())
            else {
                return usage();
            };
            let mut panel = match connect(address) {
                Ok(panel) => panel,
                Err(code) => return code,
            };
            match slide(&mut panel, direction, from, to, Duration::from_millis(milliseconds.max(1))) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => {
                    eprintln!("kitty-panel: slide: {error}");
                    ExitCode::from(EX_IOERR)
                }
            }
        }

        ["progress", address, columns, label @ ..] if !label.is_empty() => {
            let Ok(columns) = columns.parse::<usize>() else {
                return usage();
            };
            let mut panel = match connect(address) {
                Ok(panel) => panel,
                Err(code) => return code,
            };
            match progress(&mut panel, &label.join(" "), columns) {
                Ok(()) => ExitCode::SUCCESS,
                // The panel closing under the bar is a normal way for it to
                // end, not a failure worth reporting.
                Err(error) if error.kind() == std::io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
                Err(error) => {
                    eprintln!("kitty-panel: progress: {error}");
                    ExitCode::from(EX_IOERR)
                }
            }
        }

        _ => usage(),
    }
}
