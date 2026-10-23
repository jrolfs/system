import Quickshell
import QtQuick

ShellRoot {
  Variants {
    model: Quickshell.screens

    Bar {
      required property var modelData
      screen: modelData
    }
  }
}
