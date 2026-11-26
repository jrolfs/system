pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Curated wallust colorschemes for the theme switcher. Each entry carries enough of the
// scheme to actually PREVIEW it — background, foreground, the accent, and the six hues —
// so a swatch can show what a theme looks like instead of just naming it. Actually
// applying a theme is the UI's job (Config.theme + theme-apply.sh).
Singleton {
    id: root

    // [{ name, bg, fg, accent, palette: [6 hues] }], alphabetical.
    property var list: []
    // raw payload of the last publish, so an unchanged refresh is a no-op (see below)
    property string lastRaw: ""

    function refresh() { lsProc.running = true; }

    Process {
        id: lsProc
        running: true
        // Pull each scheme's bg + accent with python3, NOT jq. jq isn't guaranteed to be
        // installed, and the day it went missing every swatch rendered empty/black (bg and
        // accent came back as empty strings). python3 is basically always there.
        command: ["python3", "-c", `
import glob, json, os
out = []
for f in sorted(glob.glob(os.path.expanduser('~/.config/wallust/colorschemes/*.json'))):
    n = os.path.basename(f)[:-5]
    try:
        d = json.load(open(f))
        sp = d.get('special', {}) or {}
        c = d.get('colors') or []
        # 1..6 are the hues (red/green/yellow/blue/magenta/cyan); 0 and 7 are just the
        # near-black and near-white ends, which tell you nothing about a scheme's character
        out.append({'name': n,
                    'bg': sp.get('background', ''),
                    'fg': sp.get('foreground', ''),
                    'accent': c[6] if len(c) > 6 else '',
                    'palette': [c[i] for i in (1, 2, 3, 4, 5, 6) if i < len(c)]})
    except Exception:
        pass
print(json.dumps(out))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw === "") return;
                // Only publish when something ACTUALLY changed. The switcher calls refresh()
                // every time it opens (to catch newly added schemes), and handing back an
                // equal-but-new array still swaps the array identity — which resets every view
                // bound to it, so the swatches got torn down and rebuilt ~50ms into the morph.
                // That's what read as the panel "loading in" after it had already opened.
                if (raw === root.lastRaw) return;
                let out = [];
                try { out = JSON.parse(raw); } catch (e) { return; }
                out.sort((a, b) => a.name.localeCompare(b.name));
                root.lastRaw = raw;
                root.list = out;
            }
        }
    }
}
