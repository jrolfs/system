pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "../config"

// Wallpapers for the CURRENT colorscheme: ~/.config/colorschemes/<theme>/wallpapers
// (every theme ships its own set). Reactive to Config.theme, so switching themes
// repopulates the picker on its own. Native, no external daemon.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.config/colorschemes/${Config.theme}/wallpapers`
    property alias model: fm

    FolderListModel {
        id: fm
        folder: "file://" + root.dir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }
}
