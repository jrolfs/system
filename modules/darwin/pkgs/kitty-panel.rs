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
use std::ffi::{c_int, c_ulong};
use std::fs::File;
use std::io::Write;
use std::os::fd::AsRawFd;
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

// Shades from sparse to solid, so each cell of the one-row tab bar is a stipple
// whose density can vary, and a row of them grades like an ombre. The last is
// what the crest of the swell reaches, and dropping it softens the crest.
const SHADES: [char; 4] = ['░', '▒', '▓', '█'];

// Four shades are too few to grade smoothly on their own: rounded to the
// nearest, a slope reads as bands with hard edges. Each cell rounds against a
// threshold of its own instead, a one-row Bayer matrix, so where the density
// falls between two shades, neighbouring cells alternate between them in
// proportion, the way ordered dithering does with pixels.
const DITHER: [f64; 4] = [0.125, 0.625, 0.375, 0.875];

// Between the label, the bar and the clock in the title, so the tab title
// template can give each part its own colour. U+2063 INVISIBLE SEPARATOR rather
// than anything printable, since nothing that ends up in a title can contain
// it, and if the template ever failed to split on it, it would still not be
// seen.
const SEPARATOR: char = '\u{2063}';

// A title change re-renders the whole tab bar, and nothing about a slow swell
// needs more than this.
const TICK: Duration = Duration::from_millis(83);

// A colour as lightness, chroma, and hue in radians.
#[derive(Clone, Copy)]
struct Oklch {
    lightness: f64,
    chroma: f64,
    hue: f64,
}

fn to_linear(channel: u8) -> f64 {
    let value = f64::from(channel) / 255.0;
    if value <= 0.04045 { value / 12.92 } else { ((value + 0.055) / 1.055).powf(2.4) }
}

fn from_linear(value: f64) -> u8 {
    let value = value.clamp(0.0, 1.0);
    let encoded = if value <= 0.003_130_8 { 12.92 * value } else { 1.055 * value.powf(1.0 / 2.4) - 0.055 };
    (encoded * 255.0).round() as u8
}

// The conversions and their matrices are Björn Ottosson's, from the post that
// introduced Oklab: https://bottosson.github.io/posts/oklab/
impl Oklch {
    fn from_srgb([red, green, blue]: [u8; 3]) -> Oklch {
        let (red, green, blue) = (to_linear(red), to_linear(green), to_linear(blue));
        let l = (0.412_221_470_8 * red + 0.536_332_536_3 * green + 0.051_445_992_9 * blue).cbrt();
        let m = (0.211_903_498_2 * red + 0.680_699_545_1 * green + 0.107_396_956_6 * blue).cbrt();
        let s = (0.088_302_461_9 * red + 0.281_718_837_6 * green + 0.629_978_700_5 * blue).cbrt();
        let a = 1.977_998_495_1 * l - 2.428_592_205_0 * m + 0.450_593_709_9 * s;
        let b = 0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766_0 * s;
        Oklch {
            lightness: 0.210_454_255_3 * l + 0.793_617_785_0 * m - 0.004_072_046_8 * s,
            chroma: a.hypot(b),
            hue: b.atan2(a),
        }
    }

    fn to_srgb(self) -> [u8; 3] {
        let (a, b) = (self.chroma * self.hue.cos(), self.chroma * self.hue.sin());
        let l = (self.lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b).powi(3);
        let m = (self.lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b).powi(3);
        let s = (self.lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b).powi(3);
        [
            from_linear(4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s),
            from_linear(-1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s),
            from_linear(-0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s),
        ]
    }
}

// `#rrggbb`, the way palette.nix writes its colours.
fn parse_colour(text: &str) -> Option<[u8; 3]> {
    let digits = text.strip_prefix('#').unwrap_or(text);
    if digits.len() != 6 {
        return None;
    }
    let channel = |at: usize| u8::from_str_radix(digits.get(at..at + 2)?, 16).ok();
    Some([channel(0)?, channel(2)?, channel(4)?])
}

// The bar's colours, from the track's to the crest's. Blended in OKLCH, because
// in sRGB the straight line between gruvbox's blue and purple runs through
// grey. The hue always increases, the way that runs from red through yellow,
// green and blue, so from blue it reaches purple through violet. The two sit
// nearly opposite each other, which makes the shorter way round a coin toss,
// and that toss went through yellow and orange.
struct Gradient {
    track: Oklch,
    crest: Oklch,
}

impl Gradient {
    fn at(&self, t: f64) -> [u8; 3] {
        let turn = (self.crest.hue - self.track.hue).rem_euclid(TAU);
        Oklch {
            lightness: self.track.lightness + (self.crest.lightness - self.track.lightness) * t,
            chroma: self.track.chroma + (self.crest.chroma - self.track.chroma) * t,
            hue: self.track.hue + turn * t,
        }
        .to_srgb()
    }
}

// One frame of the bar, `width` cells across at `seconds` in.
//
// Two layers. A swell, a Gaussian bump drifting back and forth across the bar,
// sets where it is strong, and its soft edges are what fade it out to either
// side. A ripple travelling through it keeps the swell moving even while the
// bump itself is near the end of a pass. Strength sets both a cell's shade and
// how far along the gradient its colour is. The floor is the sparsest shade in
// the track's colour, so the track is always drawn and the bar never goes
// blank.
fn ombre(width: usize, seconds: f64, gradient: &Gradient) -> String {
    if width == 0 {
        return String::new();
    }

    // Ping-pong rather than wrap, so the swell turns around instead of leaving
    // one end and reappearing at the other.
    let pass = (seconds / 3.2) % 2.0;
    let centre = if pass < 1.0 { pass } else { 2.0 - pass };
    let spread = 0.22;
    let densest = (SHADES.len() - 1) as f64;

    let mut bar = String::new();
    let mut last = None;
    for cell in 0..width {
        let position = cell as f64 / (width.max(2) - 1) as f64;
        let swell = (-((position - centre) / spread).powi(2)).exp();
        let ripple = 0.5 + 0.5 * (TAU * (position * 3.0 - seconds * 0.9)).sin();
        let strength = swell * (0.7 + 0.3 * ripple);

        // The template can only give the bar one colour, so it carries its
        // own. kitty keeps a title exactly as it was set, and applies every SGR
        // code in what the template produces, whichever part it came from.
        let colour = gradient.at(strength);
        if last != Some(colour) {
            let [red, green, blue] = colour;
            bar.push_str(&format!("\x1b[38;2;{red};{green};{blue}m"));
            last = Some(colour);
        }

        let shade = (strength * densest + DITHER[cell % DITHER.len()]).floor() as usize;
        bar.push(SHADES[shade.min(SHADES.len() - 1)]);
    }
    bar
}

fn elapsed(seconds: u64) -> String {
    match seconds {
        hours if hours >= 3600 => format!("{}:{:02}:{:02}", hours / 3600, hours % 3600 / 60, hours % 60),
        _ => format!("{}:{:02}", seconds / 60, seconds % 60),
    }
}

// struct winsize, and the request that fills it, from <sys/ttycom.h>.
#[repr(C)]
#[derive(Default)]
struct WindowSize {
    rows: u16,
    columns: u16,
    width: u16,
    height: u16,
}

const TIOCGWINSZ: c_ulong = 0x4008_7468;

unsafe extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
}

// The width in cells of the window this runs in, which is the panel's. Asked
// every frame rather than once, because the panel is still being sized while
// the command in it starts: a width read then has come back 30 columns short
// of where it settled two seconds later.
fn columns(terminal: &File) -> std::io::Result<usize> {
    let mut size = WindowSize::default();
    if unsafe { ioctl(terminal.as_raw_fd(), TIOCGWINSZ, &mut size as *mut WindowSize) } == -1 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(usize::from(size.columns))
}

// Keeps the tab title animated until the process is killed, which is how the
// caller stops it: it then sets the final title itself. `reserve` is the cells
// of the window's width the title cannot have, so the one tab fills the bar.
fn progress(panel: &mut Panel, terminal: &File, gradient: &Gradient, label: &str, reserve: usize) -> std::io::Result<()> {
    let start = Instant::now();
    loop {
        let seconds = start.elapsed().as_secs_f64();
        let clock = elapsed(seconds as u64);

        // Two spaces between the parts and after the clock; the template puts
        // the margin and the logo in front of the label.
        let room = columns(terminal)?.saturating_sub(reserve);
        let used = label.chars().count() + clock.chars().count() + 6;
        let bar = ombre(room.saturating_sub(used), seconds, gradient);
        let title = format!("{label}  {SEPARATOR}{bar}{SEPARATOR}  {clock}  ");

        panel.send("set-tab-title", &format!(r#"{{"title":{},"match":null}}"#, json_string(&title)))?;
        sleep(TICK);
    }
}

const USAGE: &str = "usage: kitty-panel slide in|out <address> <from-x> <to-x> <milliseconds>
       kitty-panel progress <address> <reserve> <track-colour> <crest-colour> <label...>";

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

        ["progress", address, reserve, track, crest, label @ ..] if !label.is_empty() => {
            let (Ok(reserve), Some(track), Some(crest)) =
                (reserve.parse::<usize>(), parse_colour(track), parse_colour(crest))
            else {
                return usage();
            };
            let gradient = Gradient { track: Oklch::from_srgb(track), crest: Oklch::from_srgb(crest) };
            let terminal = match File::open("/dev/tty") {
                Ok(terminal) => terminal,
                Err(error) => {
                    eprintln!("kitty-panel: progress: no terminal to measure: {error}");
                    return ExitCode::from(EX_UNAVAILABLE);
                }
            };
            let mut panel = match connect(address) {
                Ok(panel) => panel,
                Err(code) => return code,
            };
            match progress(&mut panel, &terminal, &gradient, &label.join(" "), reserve) {
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
