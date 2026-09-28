import QtQuick
import QtQuick.Layouts
import Quickshell

// Agents + usage. Status values are tmx's (working / ready /
// awaiting-decision / idle / background) — rendered, never re-derived.
Card {
    id: card

    title: "Agents"
    icon: "󰚩"
    stale: Data.agents.stale
    error: Data.agents.error
    lastOk: Data.agents.lastOk

    readonly property var order: ({
            "awaiting-decision": 0,
            "working": 1,
            "ready": 2,
            "idle": 3,
            "background": 4
        })
    readonly property var style: ({
            "awaiting-decision": {
                color: Theme.red,
                label: "needs you",
                pulse: 700
            },
            "working": {
                color: Theme.peach,
                label: "working",
                pulse: 1400
            },
            "ready": {
                color: Theme.green,
                label: "ready",
                pulse: 0
            },
            "idle": {
                color: Theme.overlay0,
                label: "idle",
                pulse: 0
            },
            "background": {
                color: Theme.blue,
                label: "background",
                pulse: 0
            }
        })

    readonly property var byId: Theme.index(Data.agents.items, "id")
    readonly property var sorted: (Data.agents.items || []).slice().sort((a, b) => {
        const d = (order[a.status] ?? 9) - (order[b.status] ?? 9);
        return d !== 0 ? d : String(a.name).localeCompare(String(b.name));
    })

    // ── usage ────────────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        columns: 3
        columnSpacing: 14
        rowSpacing: 4
        opacity: Data.limits.stale ? 0.5 : 1

        Repeater {
            model: [
                {
                    name: "Claude 5h",
                    value: Data.limits.claude_5h,
                    reset: Data.limits.claude_5h_reset,
                    cached: Data.limits.claude_stale
                },
                {
                    name: "Claude week",
                    value: Data.limits.claude_week,
                    reset: Data.limits.claude_week_reset,
                    cached: Data.limits.claude_stale
                },
                {
                    name: "Codex week",
                    value: Data.limits.codex_week,
                    reset: Data.limits.codex_week_reset,
                    cached: Data.limits.codex_stale
                }
            ]

            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4
                // coctl fell back to a cached reading for this provider.
                opacity: modelData.cached ? 0.5 : 1

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: modelData.name
                        color: Theme.subtext0
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: modelData.value === undefined || modelData.value === null ? "—" : Math.round(modelData.value) + "%"
                        color: Theme.level(modelData.value)
                        font.family: Theme.mono
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }
                Meter {
                    Layout.fillWidth: true
                    value: modelData.value ?? 0
                    color: Theme.level(modelData.value)
                }
                Text {
                    text: modelData.cached ? "cached reading" : modelData.reset ? "resets in " + Theme.until(modelData.reset, Data.now) : ""
                    color: Theme.overlay0
                    font.family: Theme.mono
                    font.pixelSize: 9
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        visible: Data.today.loaded
        opacity: Data.today.stale ? 0.5 : 1
        text: "today  $" + (Data.today.claude_cost ?? 0).toFixed(2) + "  ·  claude " + ((Data.today.claude_tokens ?? 0) / 1e6).toFixed(1) + "M  ·  codex " + ((Data.today.codex_tokens ?? 0) / 1e6).toFixed(1) + "M tok"
        color: Theme.subtext0
        font.family: Theme.mono
        font.pixelSize: 10
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.surface0
    }

    // ── agent rows ───────────────────────────────────────────────────────
    Text {
        visible: Data.agents.loaded && card.sorted.length === 0
        text: "no agents running"
        color: Theme.overlay0
        font.family: Theme.sans
        font.pixelSize: 12
    }

    Repeater {
        // Keyed by id + status: a status change swaps the row (with the
        // row's intro animation) instead of mutating it in place.
        model: ScriptModel {
            values: card.sorted.map(a => Object.assign({
                    key: a.id + "|" + a.status + "|" + a.name
                }, a))
            objectProp: "key"
        }

        RowLayout {
            id: row

            required property var modelData
            // ScriptModel reuses a row whose key is unchanged; read the other
            // fields (age, location) from the latest poll, not the first one.
            readonly property var live: card.byId[modelData.id] || modelData
            readonly property var st: card.style[modelData.status] || card.style.idle

            Layout.fillWidth: true
            spacing: 10
            opacity: Data.agents.stale ? 0.5 : 1

            // Status dot with a halo that breathes while the agent is busy
            // or blocked on the user.
            Item {
                implicitWidth: 14
                implicitHeight: 14

                Rectangle {
                    id: halo
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: row.st.color
                    opacity: 0
                    visible: row.st.pulse > 0

                    SequentialAnimation on opacity {
                        running: row.st.pulse > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.45
                            to: 0
                            duration: row.st.pulse
                            easing.type: Easing.OutQuad
                        }
                    }
                    SequentialAnimation on scale {
                        running: row.st.pulse > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.6
                            to: 1.4
                            duration: row.st.pulse
                            easing.type: Easing.OutQuad
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: row.st.color
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    spacing: 6
                    Text {
                        text: row.modelData.kind === "codex" ? "󰆍" : "󰚩"
                        color: row.modelData.kind === "codex" ? Theme.teal : Theme.mauve
                        font.family: Theme.mono
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name || row.modelData.repo
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.live.repo + "  ·  " + row.live.location
                    color: Theme.overlay1
                    font.family: Theme.mono
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
                // What the agent is doing right now (comux reads it from the
                // tool's own log). Absent means "no reading", so just hide.
                Text {
                    Layout.fillWidth: true
                    visible: !!row.live.detail
                    text: row.live.detail || ""
                    color: Theme.lavender
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.italic: true
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                spacing: 1
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: row.st.label
                    color: row.st.color
                    font.family: Theme.sans
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.alignment: Qt.AlignRight
                    visible: !!row.live.since_ms
                    text: Theme.ago(row.live.since_ms, Data.now)
                    color: Theme.overlay0
                    font.family: Theme.mono
                    font.pixelSize: 10
                }
            }

            // Row intro: slide in from the right.
            transform: Translate {
                id: slide
                x: 24
            }
            Component.onCompleted: slideIn.start()
            NumberAnimation {
                id: slideIn
                target: slide
                property: "x"
                to: 0
                duration: 450
                easing.type: Easing.OutCubic
            }
        }
    }

    // ── recent attention events ──────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: (Data.attention.items || []).length > 0
        spacing: 3

        Text {
            text: "recent"
            color: Theme.overlay0
            font.family: Theme.sans
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        Repeater {
            model: (Data.attention.items || []).slice(0, 3)

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: Theme.ago(modelData.ts * 1000, Data.now)
                    color: Theme.overlay0
                    font.family: Theme.mono
                    font.pixelSize: 10
                    Layout.preferredWidth: 26
                }
                Text {
                    Layout.fillWidth: true
                    // Bodies are the agent's last message: markdown, maybe
                    // multi-line. Show the first line with markup stripped.
                    text: modelData.title + " — " + String(modelData.body || "").split("\n").map(l => l.replace(/[#*`>_]/g, "").trim()).filter(l => l)[0]
                    color: Theme.subtext0
                    font.family: Theme.sans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
