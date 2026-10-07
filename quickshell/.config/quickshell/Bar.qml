import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland

// Top bar, one per screen. The data comes from BarData so a second screen
// adds no processes.
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        left: 8
        right: 8
    }
    // 28px pills with 8px above and below: the 44px reserve DesktopWidget's
    // offsets are measured from.
    implicitHeight: 44
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    // A script-backed pill: colour and dimming keyed by the script's class.
    component FeedPill: BarPill {
        property var feed
        property color base: "#e2e0f0"
        property var classColors: ({})
        property var dimClasses: []

        text: feed.text
        tooltip: feed.tooltip
        textColor: classColors[feed.cls] || base
        dim: dimClasses.indexOf(feed.cls) >= 0
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        FeedPill {
            feed: BarData.serverHealth
            base: "#a8e6a3"
            classColors: ({
                    unhealthy: "#f38ba8"
                })
        }
        FeedPill {
            feed: BarData.grafana
            base: "#c793fa"
            classColors: ({
                    error: "#c49deb"
                })
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec(BarData.scripts + "/grafana_status.sh --open");
            }
        }
        Workspaces {
            screen: bar.modelData
        }
        FeedPill {
            readonly property string script: BarData.scripts + "/ytmusic_status.sh"

            feed: BarData.ytmusic
            base: "#f28b82"
            classColors: ({
                    paused: "#b8b5d0"
                })
            dimClasses: ["paused"]
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec(script + " --toggle-panel");
                else if (button === Qt.MiddleButton)
                    BarData.exec(script + " --play-pause", "ytmusic");
            }
            onScrolled: step => BarData.exec(script + (step > 0 ? " --next" : " --previous"), "ytmusic")
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        FeedPill {
            feed: BarData.uptime
            base: "#8bd5ca"
        }
        BarPill {
            text: "󰥔  " + Qt.formatDateTime(clock.date, "MM/dd  HH:mm")
            tooltip: Qt.locale("en_US").toString(clock.date, "yyyy-MM-dd dddd")
            textColor: "#98c379"
            bold: true
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec("gsimplecal");
            }

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        // Idle prints empty text (hidden); recording/streaming is a solid
        // blinking pill instead of the usual translucent one.
        BarPill {
            id: obsPill

            readonly property string cls: BarData.obs.cls

            text: BarData.obs.text
            tooltip: BarData.obs.tooltip
            textColor: "#ffffff"
            bold: true
            color: cls === "streaming" ? Qt.rgba(214 / 255, 36 / 255, 110 / 255, 0.85) : Qt.rgba(224 / 255, 36 / 255, 36 / 255, 0.85)
            border.color: cls === "streaming" ? Qt.rgba(1, 90 / 255, 150 / 255, 0.6) : Qt.rgba(1, 90 / 255, 90 / 255, 0.6)
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec(BarData.scripts + "/obs_status.sh --toggle-record", "obs");
                else if (button === Qt.RightButton)
                    BarData.exec("obs");
            }

            SequentialAnimation on opacity {
                running: obsPill.visible
                loops: Animation.Infinite
                onRunningChanged: {
                    if (!running)
                        obsPill.opacity = 1;
                }
                NumberAnimation {
                    to: 0.5
                    duration: 700
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1
                    duration: 700
                    easing.type: Easing.InOutSine
                }
            }
        }
        FeedPill {
            feed: BarData.tailscale
            classColors: ({
                    connected: "#8bd5ca",
                    "exit-node": "#f5a97f",
                    disconnected: "#b8b5d0"
                })
            dimClasses: ["disconnected"]
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec(BarData.scripts + "/tailscale_toggle.sh", "tailscale");
                else if (button === Qt.RightButton)
                    BarData.exec("kitty --hold -e tailscale status");
            }
        }
        FeedPill {
            feed: BarData.adguardvpn
            classColors: ({
                    connected: "#a8e6a3",
                    disconnected: "#b8b5d0"
                })
            dimClasses: ["disconnected"]
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec(BarData.scripts + "/adguardvpn_toggle.sh", "adguardvpn");
                else if (button === Qt.RightButton)
                    BarData.exec("notify-send 'AdGuard VPN' 'Refreshing status…'", "adguardvpn");
            }
        }
        BarPill {
            readonly property PwNode sink: BarData.sink
            readonly property bool ready: sink !== null && sink.audio !== null
            readonly property bool muted: ready && sink.audio.muted
            readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
            readonly property string icon: {
                const forms = {
                    headphone: "󰋋",
                    "hands-free": "󰋋",
                    headset: "󰋎",
                    phone: "󰄜",
                    portable: "󰦧",
                    car: "󰄋"
                };
                const form = ready ? sink.properties["device.form-factor"] : "";
                return forms[form] || (volume < 34 ? "󰕿" : volume < 67 ? "󰖀" : "󰕾");
            }

            text: !ready ? "" : muted ? "󰝟  Muted" : icon + "  " + volume + "%"
            tooltip: ready ? sink.description : ""
            textColor: muted ? "#8885a5" : "#dbb6ee"
            dim: muted
            onClicked: button => {
                if (button === Qt.LeftButton)
                    sink.audio.muted = !sink.audio.muted;
                else if (button === Qt.RightButton)
                    BarData.exec(BarData.scripts + "/audio_sink_toggle.sh");
                else if (button === Qt.MiddleButton)
                    BarData.exec("pavucontrol");
            }
            onScrolled: step => sink.audio.volume = Math.max(0, Math.min(1, (volume + step * 5) / 100))
        }
        FeedPill {
            feed: BarData.cpu
            base: "#7dc4e4"
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec("kitty -e htop");
            }
        }
        FeedPill {
            feed: BarData.memory
            base: "#c8b8ff"
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec("kitty -e htop");
            }
        }
        FeedPill {
            feed: BarData.gpu
            base: "#74c7ec"
            onClicked: button => {
                if (button === Qt.LeftButton)
                    BarData.exec("command -v nvtop >/dev/null && kitty -e nvtop");
            }
        }
        FeedPill {
            feed: BarData.disk
            base: "#f5a97f"
            classColors: ({
                    critical: "#f38ba8"
                })
        }
        BarPill {
            readonly property string down: BarData.formatBits(BarData.netRxBps)
            readonly property string up: BarData.formatBits(BarData.netTxBps)

            text: !BarData.netIface ? "󰤮  Offline" : (BarData.netWifi ? "󰤨" : "󰛳") + "  " + down + " ↓ " + up + " ↑"
            tooltip: !BarData.netIface ? "" : BarData.netWifi ? (BarData.netSsid || BarData.netIface) + "\nIP: " + BarData.netIp : BarData.netIface + "\nIP: " + BarData.netIp + "\nDown: " + down + "   Up: " + up
            textColor: BarData.netIface ? "#7dc4e4" : "#f38ba8"
        }
        BarPill {
            readonly property var dev: UPower.displayDevice
            readonly property int pct: Math.round(dev.percentage * 100)
            readonly property bool charging: dev.state === UPowerDeviceState.Charging
            readonly property bool full: dev.state === UPowerDeviceState.FullyCharged
            readonly property var icons: ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
            readonly property real secs: charging ? dev.timeToFull : dev.timeToEmpty

            // Desktops report no laptop battery: hidden.
            text: !dev.isLaptopBattery ? "" : (charging ? "󰂄" : full ? "󰁹" : icons[Math.min(10, Math.floor(pct / 10))]) + "  " + pct + "%"
            tooltip: pct + "%" + (secs > 0 ? " – " + Math.floor(secs / 3600) + "h " + Math.floor(secs % 3600 / 60) + "m" : "") + "\nPower: " + dev.changeRate.toFixed(1) + "W"
            textColor: charging ? "#a8e6a3" : pct <= 15 ? "#f38ba8" : pct <= 30 ? "#f5a97f" : "#f0c674"
        }
    }
}
