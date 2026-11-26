pragma Singleton
import Quickshell
import Quickshell.Services.Mpris

// MPRIS media players. Hands the control center one "current" player, preferring a
// real player that's actually playing over the playerctld proxy (that one's just an
// aggregator, not the real thing). The Media service deferred back in Phase 2; its
// consumer (control center) finally exists.
Singleton {
    id: root

    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }
    readonly property var players: asArray(Mpris.players)

    readonly property var player: {
        // drop the playerctld aggregator, it's a proxy not a real player
        const ps = players.filter(p => p.dbusName && p.dbusName.indexOf("playerctld") < 0);
        const isSpotify = p => /spotify/i.test((p.dbusName || "") + " " + (p.identity || ""));
        // Spotify is the preferred player, so it's always a candidate. Everything else
        // (yes Brave, you) only counts while it's actually playing, otherwise an idle
        // browser MPRIS stub hijacks the card with some weird icon.
        const pool = ps.filter(p => isSpotify(p) || p.isPlaying);
        // whatever's actually playing wins (Spotify first if more than one is), then idle
        // Spotify, then nobody at all.
        return pool.find(p => p.isPlaying && isSpotify(p))
            ?? pool.find(p => p.isPlaying)
            ?? pool.find(isSpotify)
            ?? null;
    }
    readonly property bool hasPlayer: player !== null
}
