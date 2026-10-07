import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// One desktop panel per screen, on the Bottom layer: above the wallpaper
// (hyprpaper sits on Background, where same-layer order is undefined) and
// below every window — so it is only visible on an empty workspace, which
// is the point. Never takes keyboard focus or reserves space.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    // Ultrawide gets the cards side by side, narrower screens stack them.
    readonly property bool wide: modelData.width >= 2560
    readonly property int cardWidth: 440

    color: "transparent"
    anchors {
        top: true
        right: true
    }
    // Tiled windows start at the bar's 44px reserve + gaps_out 20 + border 2
    // (y=66, and 22px in from the right edge). Starting the cards inside
    // that edge keeps their tops from peeking through the gap above windows.
    margins {
        top: 80
        right: 40
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    GridLayout {
        id: grid
        columns: win.wide ? 2 : 1
        columnSpacing: Theme.gap
        rowSpacing: Theme.gap

        AgentsCard {
            Layout.preferredWidth: win.cardWidth
            Layout.alignment: Qt.AlignTop
        }
        HomelabCard {
            Layout.preferredWidth: win.cardWidth
            Layout.alignment: Qt.AlignTop
        }
    }
}
