pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS media players, narrowed to the one "current" player the media surfaces show.
Singleton {
    id: root

    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }
    readonly property var players: asArray(Mpris.players)

    // playerctld is an aggregator that mirrors whichever real player it last saw, so
    // counting it would show every track twice.
    readonly property var realPlayers: players.filter(p => p.dbusName && p.dbusName.indexOf("playerctld") < 0)
    readonly property var playing: realPlayers.filter(p => p.isPlaying)

    function isSpotify(p) { return /spotify/i.test((p.dbusName || "") + " " + (p.identity || "")); }

    // The player that most recently started playing. It keeps the card after a pause, so
    // pausing a video does not hand the card to some other idle player.
    property var lastActive: null
    property var _seenPlaying: []
    onPlayingChanged: {
        const fresh = playing.filter(p => _seenPlaying.indexOf(p) < 0);
        if (fresh.length > 0) lastActive = fresh[fresh.length - 1];
        else if (playing.length > 0 && playing.indexOf(lastActive) < 0) lastActive = playing[0];
        _seenPlaying = playing.slice();
    }

    // Playing beats paused. Among several playing, the newest one wins, then Spotify. With
    // nothing playing, the last player that was, then an idle Spotify. Other idle players
    // never count on their own: a browser keeps an MPRIS stub alive for every tab that
    // ever played anything, and that stub would otherwise take the card.
    readonly property var player: {
        const alive = p => p && realPlayers.indexOf(p) >= 0;
        if (playing.length > 0)
            return playing.indexOf(lastActive) >= 0 ? lastActive
                 : (playing.find(isSpotify) ?? playing[0]);
        if (alive(lastActive)) return lastActive;
        return realPlayers.find(isSpotify) ?? null;
    }
    readonly property bool hasPlayer: player !== null
}
