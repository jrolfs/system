pragma Singleton
import Quickshell

// Desktop app list plus ranked search, backed by Quickshell.DesktopEntries. The
// "Apps" service that got deferred from Phase 2; its consumer (the launcher) exists
// now.
Singleton {
    id: root

    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }

    // Launchable apps, NoDisplay ones hidden, alphabetical.
    readonly property var all: asArray(DesktopEntries.applications)
        .filter(e => e && !e.noDisplay)
        .slice()
        .sort((a, b) => a.name.localeCompare(b.name))

    // Ranked substring search, best first: name-prefix > word-start > name-substring >
    // genericName > keywords. Empty query just gives ya the whole list.
    function query(text) {
        const q = (text || "").trim().toLowerCase();
        if (q === "")
            return all;

        const scored = [];
        for (const e of all) {
            const name = (e.name || "").toLowerCase();
            const gen = (e.genericName || "").toLowerCase();
            let kw = "";
            try { kw = Array.from(e.keywords || []).join(" ").toLowerCase(); } catch (err) {}

            let score = -1;
            if (name.startsWith(q)) score = 0;
            else if (name.indexOf(" " + q) >= 0) score = 1;
            else if (name.indexOf(q) >= 0) score = 2;
            else if (gen.indexOf(q) >= 0) score = 3;
            else if (kw.indexOf(q) >= 0) score = 4;

            if (score >= 0)
                scored.push({ e: e, score: score });
        }
        scored.sort((a, b) => (a.score - b.score) || a.e.name.localeCompare(b.e.name));
        return scored.map(s => s.e);
    }
}
