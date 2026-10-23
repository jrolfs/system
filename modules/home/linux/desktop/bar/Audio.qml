import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Volume of the default output. Click to mute, scroll to change it.
Item {
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink?.audio?.volume ?? 0
  readonly property bool muted: sink?.audio?.muted ?? true

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // Pipewire only keeps a node's properties current while something tracks it.
  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  RowLayout {
    id: row
    spacing: 6

    Icon {
      // speaker-x, speaker-low, speaker-high
      glyph: muted ? "\ue45c" : volume < 0.5 ? "\ue44c" : "\ue44a"
      color: muted ? Theme.muted : Theme.foreground
    }

    Text {
      text: Math.round(volume * 100) + "%"
      color: muted ? Theme.muted : Theme.foreground
      font.family: Theme.sans
      font.pixelSize: Theme.fontSize
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (sink) sink.audio.muted = !sink.audio.muted
    onWheel: wheel => {
      if (!sink) return;
      const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
      sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
    }
  }
}
