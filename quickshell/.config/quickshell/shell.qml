import QtQuick
import Quickshell

// Entry point (`qs`). Top bar + desktop widget on every screen, IPC power
// menu. Collectors live in the Data / BarData singletons, shared across
// screens.
ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        DesktopWidget {}
    }

    PowerMenu {}
}
