pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "../config"

// The images the wallpaper picker offers: everything directly in Config.wallpaperDir,
// which Nix points at the repo's wallpapers in the store.
Singleton {
    id: root

    readonly property string dir: Config.wallpaperDir
    property alias model: fm

    FolderListModel {
        id: fm
        // an empty folder URL would list the working directory, so park it on nothing
        folder: root.dir !== "" ? "file://" + root.dir : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
        showDirs: false
        sortField: FolderListModel.Name
    }
}
