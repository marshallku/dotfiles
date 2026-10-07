import QtQuick
import QtQuick.Layouts
import Quickshell

// Homelab detail: what the bar compresses into server_health / grafana /
// tailscale icons. Each section dims + badges independently when stale.
Card {
    id: card

    title: "Homelab"
    icon: "󰒋"
    stale: Data.servers.stale || Data.nodes.stale || Data.tailscale.stale
    error: [Data.servers.error, Data.nodes.error, Data.tailscale.error].filter(e => e).join(" · ")
    lastOk: Math.min(...[Data.servers, Data.nodes, Data.tailscale].filter(s => s.stale).map(s => s.lastOk).concat([Date.now()]))

    readonly property var nodeByName: Theme.index(Data.nodes.items, "name")

    component NodeMetric: RowLayout {
        property string label
        property var value

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 6

        Text {
            text: parent.label
            color: Theme.overlay1
            font.family: Theme.mono
            font.pixelSize: 10
        }
        Meter {
            Layout.fillWidth: true
            value: parent.value ?? 0
            color: Theme.level(parent.value)
        }
        Text {
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignRight
            text: parent.value === null || parent.value === undefined ? "—" : Math.round(parent.value) + "%"
            color: Theme.subtext0
            font.family: Theme.mono
            font.pixelSize: 10
        }
    }

    component SectionLabel: Text {
        color: Theme.overlay0
        font.family: Theme.sans
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    function uptime(s) {
        if (!s)
            return "—";
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        return d > 0 ? d + "d " + h + "h" : h + "h";
    }

    // ── servers ──────────────────────────────────────────────────────────
    SectionLabel {
        text: "servers"
    }

    Repeater {
        model: Data.servers.items || []

        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 10
            opacity: Data.servers.stale ? 0.5 : 1

            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                // Never green while stale: last-good health is not health.
                color: Data.servers.stale ? Theme.overlay0 : (modelData.up ? Theme.green : Theme.red)
                Behavior on color {
                    ColorAnimation {
                        duration: 400
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: modelData.name
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }
            Text {
                text: modelData.group
                color: Theme.overlay0
                font.family: Theme.mono
                font.pixelSize: 10
            }
            Text {
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
                text: modelData.up ? modelData.latency_ms + " ms" : (modelData.code ? "HTTP " + modelData.code : "down")
                color: !modelData.up ? Theme.red : modelData.latency_ms > 500 ? Theme.peach : Theme.subtext0
                font.family: Theme.mono
                font.pixelSize: 11
            }
        }
    }

    // ── nodes ────────────────────────────────────────────────────────────
    SectionLabel {
        Layout.topMargin: 6
        text: "nodes"
    }

    Repeater {
        model: ScriptModel {
            // Keyed by node name so meters persist and animate between polls.
            values: Data.nodes.items || []
            objectProp: "name"
        }

        ColumnLayout {
            id: node
            required property var modelData
            // Row persists across polls (keyed by name); values come from the latest one.
            readonly property var live: card.nodeByName[modelData.name] || modelData
            Layout.fillWidth: true
            spacing: 4
            opacity: Data.nodes.stale ? 0.5 : 1

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: node.modelData.name
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: "up " + card.uptime(node.live.uptime_s)
                    color: Theme.overlay0
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Three fixed instances, not a Repeater over an array: an
                // array model rebuilds its delegates on every poll, which
                // would reset the meters instead of animating them.
                NodeMetric {
                    label: "cpu"
                    value: node.live.cpu
                }
                NodeMetric {
                    label: "mem"
                    value: node.live.mem
                }
                NodeMetric {
                    label: "disk"
                    value: node.live.disk
                }
            }
        }
    }

    // ── tailscale ────────────────────────────────────────────────────────
    RowLayout {
        Layout.topMargin: 6
        Layout.fillWidth: true
        SectionLabel {
            text: "tailscale"
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: Data.tailscale.loaded
            text: (Data.tailscale.items || []).filter(p => p.online).length + "/" + (Data.tailscale.items || []).length + " online  ·  " + (Data.tailscale.state || "")
            color: Data.tailscale.state === "Running" ? Theme.subtext0 : Theme.peach
            font.family: Theme.mono
            font.pixelSize: 10
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        opacity: Data.tailscale.stale ? 0.5 : 1

        Repeater {
            model: Data.tailscale.items || []

            Rectangle {
                required property var modelData
                radius: 8
                color: modelData.online ? Qt.rgba(0.65, 0.89, 0.63, 0.10) : Qt.rgba(0.42, 0.44, 0.53, 0.12)
                border.width: 1
                border.color: modelData.online ? Qt.rgba(0.65, 0.89, 0.63, 0.35) : "transparent"
                implicitWidth: peer.implicitWidth + 14
                implicitHeight: peer.implicitHeight + 6

                Text {
                    id: peer
                    anchors.centerIn: parent
                    text: modelData.name
                    color: modelData.online ? Theme.green : Theme.overlay0
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }
        }
    }
}
