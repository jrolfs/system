pragma Singleton
import Quickshell
import Quickshell.Io

// Clipboard history via cliphist (plus wl-clipboard). No native binding in 0.3, so
// it's process-backed: list and decode through cliphist, write through wl-copy.
Singleton {
    id: root

    // [{ id: "11222", preview: "menu" }, ...], newest first (cliphist's own order).
    property var entries: []

    function refresh() { listProc.running = true; }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (line.length === 0) continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    out.push({ id: line.slice(0, tab), preview: line.slice(tab + 1) });
                }
                root.entries = out;
            }
        }
    }

    // Copy a history entry back onto the clipboard: decode by id, pipe to wl-copy.
    // id gets checked digits-only before it ever touches the shell, 'cause feeding raw
    // input into `sh -c` is how ya hand a stranger a shell.
    function copy(entry) {
        if (!entry || !/^[0-9]+$/.test(String(entry.id)))
            return;
        decodeProc.command = ["sh", "-c", `cliphist decode ${entry.id} | wl-copy`];
        decodeProc.running = true;
    }
    Process { id: decodeProc }

    // Drop arbitrary text on the clipboard (say, a calculator result). Goes in as an
    // argv element, no shell, so the content can't get interpreted as anything.
    function setText(t) {
        setProc.command = ["wl-copy", "--", String(t)];
        setProc.running = true;
    }
    Process { id: setProc }
}
