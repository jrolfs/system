// Switches kanata's base layer to follow the focused window: `plain` while a
// terminal has focus, `mac` otherwise.
//
// The Mac-style shortcuts in layout.kbd turn ⌘C into Ctrl+C, which is a copy
// in a browser and an interrupt in a terminal. kanata sees key events and
// nothing else, so it can't tell the two apart on its own; Hyprland can.
// This listens to Hyprland's event socket and tells kanata over its TCP
// server whenever focus crosses that line. It's what hyprkan does, reduced to
// the one rule this setup needs and written without dependencies, like the
// repo's other small tools.
//
// `plain` is also kanata's starting layer and the right one for the text
// console, so leaving the session puts it back: on its own when Hyprland's
// socket closes, and through `set plain` from the service's stop hook when
// the session is stopped first.
//
// Usage:
//   hypr-kanata-layers <kanata port> follow <terminal class>...
//   hypr-kanata-layers <kanata port> set <layer>

use std::env;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::exit;
use std::thread::sleep;
use std::time::Duration;

const USAGE: &str = "usage: hypr-kanata-layers <kanata port> follow <terminal class>...\n       hypr-kanata-layers <kanata port> set <layer>";

fn event_socket() -> Result<PathBuf, String> {
    let runtime = env::var("XDG_RUNTIME_DIR").map_err(|_| "XDG_RUNTIME_DIR is not set")?;
    let instance = env::var("HYPRLAND_INSTANCE_SIGNATURE")
        .map_err(|_| "HYPRLAND_INSTANCE_SIGNATURE is not set; is this running inside Hyprland's session?")?;

    Ok(PathBuf::from(runtime).join("hypr").join(instance).join(".socket2.sock"))
}

// A connection per change rather than one held open: kanata pushes its own
// layer-change notifications to every connected client, and a client that
// never reads them would eventually fill the socket's buffer.
fn change_layer(port: u16, layer: &str) -> std::io::Result<()> {
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    writeln!(stream, "{{\"ChangeLayer\":{{\"new\":\"{layer}\"}}}}")
}

// kanata may still be starting, or restarting after a switch. A few tries
// cover that without a dropped focus change leaving the wrong layer in place
// until the next one.
fn change_layer_retrying(port: u16, layer: &str) -> bool {
    for attempt in 0..5 {
        match change_layer(port, layer) {
            Ok(()) => return true,
            Err(error) if attempt == 4 => eprintln!("hypr-kanata-layers: kanata on port {port}: {error}"),
            Err(_) => sleep(Duration::from_millis(200)),
        }
    }

    false
}

fn follow(port: u16, terminals: &[String]) -> ! {
    let path = event_socket().unwrap_or_else(|error| {
        eprintln!("hypr-kanata-layers: {error}");
        exit(1);
    });

    let socket = UnixStream::connect(&path).unwrap_or_else(|error| {
        eprintln!("hypr-kanata-layers: {}: {error}", path.display());
        exit(1);
    });

    // Nothing reports focus until it next changes, and an empty workspace is
    // the common case at login, so start out as if a non-terminal had it.
    let mut current = if change_layer_retrying(port, "mac") { Some("mac") } else { None };

    for line in BufReader::new(socket).lines() {
        let Ok(line) = line else { break };

        // `activewindow>>CLASS,TITLE`, with an empty class when nothing has
        // focus (an empty workspace), which counts as not-a-terminal.
        let Some(window) = line.strip_prefix("activewindow>>") else { continue };
        let class = window.split(',').next().unwrap_or("");

        let layer = if terminals.iter().any(|terminal| terminal == class) { "plain" } else { "mac" };

        // Hyprland repeats this event whenever the focused window's title
        // changes, which a terminal does constantly.
        if current == Some(layer) {
            continue;
        }

        if change_layer_retrying(port, layer) {
            current = Some(layer);
        }
    }

    // Hyprland closed the socket, so the session is ending or Hyprland is
    // restarting. Either way the console's layout is the safe one to leave,
    // and exiting non-zero lets systemd restart this in the second case.
    eprintln!("hypr-kanata-layers: Hyprland's event socket closed");
    change_layer_retrying(port, "plain");
    exit(1);
}

fn main() {
    let arguments: Vec<String> = env::args().skip(1).collect();

    let (port, mode, rest) = match arguments.as_slice() {
        [port, mode, rest @ ..] => (port, mode.as_str(), rest),
        _ => {
            eprintln!("{USAGE}");
            exit(64);
        }
    };

    let port: u16 = port.parse().unwrap_or_else(|_| {
        eprintln!("hypr-kanata-layers: {port} is not a port number");
        exit(64);
    });

    match (mode, rest) {
        ("follow", terminals) => follow(port, terminals),
        ("set", [layer]) => exit(if change_layer_retrying(port, layer) { 0 } else { 1 }),
        _ => {
            eprintln!("{USAGE}");
            exit(64);
        }
    }
}
