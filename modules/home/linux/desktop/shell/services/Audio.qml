pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// Audio: default output (sink) + input (source) volume/mute, plus the lists of real
// output/input devices and a way to switch the default. PwObjectTracker keeps the default
// nodes' `audio` bound; without it volume/muted go stale or straight null (gotcha #5).
// `defaultAudioSink`/`Source` swap out as devices come and go, and the tracker rebinds.
Singleton {
    id: root

    // output (sink)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false
    readonly property bool ready: sink !== null && sink.audio !== null

    // input (source / mic)
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real sourceVolume: (source && source.audio) ? source.audio.volume : 0
    readonly property bool sourceMuted: (source && source.audio) ? source.audio.muted : false

    // device lists (real devices, not per-app streams)
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

    function nodeLabel(n) {
        if (!n) return "";
        return n.description || n.nickname || n.name || "Audio device";
    }

    // output controls
    function setVolume(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v)); }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
    function setSink(n) { if (n) Pipewire.preferredDefaultAudioSink = n; }

    // input controls
    function setSourceVolume(v) { if (source && source.audio) source.audio.volume = Math.max(0, Math.min(1, v)); }
    function toggleSourceMute() { if (source && source.audio) source.audio.muted = !source.audio.muted; }
    function setSource(n) { if (n) Pipewire.preferredDefaultAudioSource = n; }

    PwObjectTracker {
        objects: {
            const o = [];
            if (root.sink) o.push(root.sink);
            if (root.source) o.push(root.source);
            return o;
        }
    }
}
