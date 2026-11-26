pragma Singleton
import QtQuick
import Quickshell
import "../config"

// Synced lyrics for whatever MPRIS is playing, from lrclib.net (free, keyless, returns
// timestamped LRC). Nothing local provides lyrics — the player exposes no xesam:asText and
// no lyrics daemon is installed.
//
// The shape of this follows what the established Quickshell shells converged on (caelestia's
// C++ Lyrics service, noctalia's mpris-lyrics plugin):
//
//   · DEBOUNCED track changes. A track change is a cascade of separate title/artist/album
//     property updates, and acting on the first one means fetching with half-updated
//     metadata. The first version here started a Process synchronously inside that cascade
//     and QML gave no ordering guarantee that the process's command binding had updated —
//     so changing songs refetched the OLD track's lyrics and the widget looked stuck.
//     Fetching 350ms after the last change, reading the player's properties FRESH at fire
//     time, kills that class of bug outright.
//   · A GENERATION token per fetch; responses landing after another fetch started are
//     dropped, so rapid skipping can't interleave stale lyrics.
//   · A CACHE (in memory, misses included) so skipping back to a track never refetches.
//   · /api/get exact match (title+artist+album+duration) first, /api/search fallback picking
//     the synced result closest in duration.
//   · SYNCED-ONLY display: a one-line bar readout can't do anything honest with un-timed
//     lyrics, so plain-only results count as misses.
//
// Fetches use XMLHttpRequest — no subprocess, callbacks close over their generation token.
// Timing reads MprisPlayer.position, which advances on read here (verified against wall
// clock; positionSupported is true), so a poll plus binary search is enough. MPRIS emits no
// position-change notifications by spec, so polling is the only option regardless.
Singleton {
    id: root

    readonly property var p: Media.player

    // Track identity. Gated on the config toggle so flipping lyrics ON refetches for the
    // current track immediately (the key going "" <-> real drives the whole pipeline).
    readonly property string trackKey: (Config.mediaLyrics && p && (p.trackTitle ?? "") !== "")
        ? [p.trackTitle, p.trackArtist ?? "", p.trackAlbum ?? ""].join(" | ")
        : ""

    property var lines: []          // [[seconds, text], ...] sorted; empty text = musical gap
    property bool synced: false
    property bool loading: false
    // true from the moment a track change invalidates the lyrics until its fetch (or cache
    // hit) resolves — the island reads this to hold its size instead of flapping mid-skip
    property bool pending: false
    readonly property bool available: synced && lines.length > 0

    // the line that should be showing right now (-1 = before the first stamp)
    property int index: -1
    readonly property string currentLine: (index >= 0 && index < lines.length) ? lines[index][1] : ""
    // at -1 this previews the opening line, so the widget shows something during the intro
    readonly property string nextLine: (index + 1 >= 0 && index + 1 < lines.length) ? lines[index + 1][1] : ""

    // stale-response guard + cache (misses cached too; capped)
    property int gen: 0
    property var cache: ({})
    property var cacheKeys: []

    onTrackKeyChanged: {
        lines = []; synced = false; index = -1;
        pending = trackKey !== "";
        debounce.restart();
    }
    Timer { id: debounce; interval: 350; onTriggered: root.doFetch() }

    function apply(entry) {
        synced = entry.synced;
        lines = entry.lines;
        index = -1;
        loading = false;
        pending = false;      // last, so anyone reacting to it sees the settled result
    }

    function store(key, entry) {
        cache[key] = entry;
        cacheKeys.push(key);
        if (cacheKeys.length > 40) delete cache[cacheKeys.shift()];
        if (key === trackKey) apply(entry);
    }

    function doFetch() {
        const key = trackKey;
        if (key === "" || !p) { loading = false; pending = false; return; }
        const hit = cache[key];
        if (hit) { apply(hit); return; }

        const g = ++gen;
        loading = true;
        // read the metadata NOW, not through bindings captured earlier
        const title = p.trackTitle ?? "";
        const artist = p.trackArtist ?? "";
        const album = p.trackAlbum ?? "";
        const dur = Math.round(p.length ?? 0);

        let q = "track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist)
              + "&album_name=" + encodeURIComponent(album);
        if (dur > 0 && dur < 36000) q += "&duration=" + dur;   // livestreams report absurd lengths; skip

        get("https://lrclib.net/api/get?" + q, function(st, body) {
            if (g !== root.gen) return;                        // a newer fetch owns the state now
            if (st === 200) {
                const d = parseJson(body);
                if (d && useResult(d, key)) return;
            }
            // fuzzy fallback: same title+artist, prefer synced, then closest duration
            const q2 = "track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist);
            get("https://lrclib.net/api/search?" + q2, function(st2, body2) {
                if (g !== root.gen) return;
                const arr = st2 === 200 ? parseJson(body2) : null;
                if (Array.isArray(arr) && arr.length > 0) {
                    arr.sort(function(a, b) {
                        const sa = a.syncedLyrics ? 0 : 1, sb = b.syncedLyrics ? 0 : 1;
                        if (sa !== sb) return sa - sb;
                        return Math.abs((a.duration || 0) - dur) - Math.abs((b.duration || 0) - dur);
                    });
                    if (useResult(arr[0], key)) return;
                }
                store(key, { synced: false, lines: [] });      // a cached miss, so no re-asking
            });
        });
    }

    // returns true if the result yielded synced lines (and stored them)
    function useResult(d, key) {
        if (!d || d.instrumental === true) { store(key, { synced: false, lines: [] }); return true; }
        const rows = parseLrc(d.syncedLyrics || "");
        if (rows.length === 0) return false;
        store(key, { synced: true, lines: rows });
        return true;
    }

    function get(url, cb) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE) cb(x.status, x.responseText);
        };
        x.open("GET", url);
        x.send();
    }

    function parseJson(s) {
        try { return JSON.parse(s); } catch (e) { return null; }
    }

    // LRC -> [[seconds, text], ...]. Honors [offset:ms] (positive shifts lines earlier, per
    // the usual LRC convention); stamped empty lines are KEPT — they're the musical gaps,
    // and they blank the readout during an interlude instead of freezing the last line.
    function parseLrc(lrc) {
        const rows = [];
        let offset = 0;
        const stampRe = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
        for (const raw of lrc.split(/\r?\n/)) {
            const om = raw.match(/^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$/i);
            if (om) { offset = parseInt(om[1]) / 1000; continue; }
            stampRe.lastIndex = 0;
            const stamps = [];
            let m;
            while ((m = stampRe.exec(raw)) !== null)
                stamps.push(parseInt(m[1]) * 60 + parseFloat(m[2]));
            if (stamps.length === 0) continue;                 // [ar:], [ti:] and friends
            const text = raw.replace(/\[\d+:\d+(?:\.\d+)?\]/g, "").trim();
            for (const t of stamps) rows.push([Math.max(0, t - offset), text]);
        }
        rows.sort(function(a, b) { return a[0] - b[0]; });
        return rows;
    }

    // Walk the stamps to wherever the player says it is. Recomputed from scratch each tick
    // (binary search) rather than advanced by one, so seeks and restarts land on the right
    // line instead of stranding the highlight.
    Timer {
        running: root.available && (root.p?.isPlaying ?? false)
        interval: 250
        repeat: true
        onTriggered: {
            const pos = root.p ? root.p.position : 0;
            const ls = root.lines;
            let lo = 0, hi = ls.length - 1, found = -1;
            while (lo <= hi) {
                const mid = (lo + hi) >> 1;
                if (ls[mid][0] <= pos) { found = mid; lo = mid + 1; } else { hi = mid - 1; }
            }
            if (found !== root.index) root.index = found;
        }
    }
}
