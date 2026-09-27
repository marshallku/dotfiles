import QtQuick
import Quickshell

// Entry point (`qs`). Desktop widget on every screen + IPC power menu.
// Collectors live in the Data singleton, shared across screens.
ShellRoot {
    Variants {
        model: Quickshell.screens

        DesktopWidget {}
    }

    PowerMenu {}
}
