import QtQuick

// A Phosphor glyph. `glyph` is the codepoint from Phosphor's style.css,
// written as a JavaScript string escape, e.g. "\ue19a".
Text {
  property string glyph

  text: glyph
  color: Theme.foreground
  font.family: Theme.icons
  font.pixelSize: Theme.iconSize
  verticalAlignment: Text.AlignVCenter
}
