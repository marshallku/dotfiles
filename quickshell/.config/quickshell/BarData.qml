pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Owns every process the top bar runs. Lives outside the per-screen Variants
// (same reason as Data) so a second monitor never doubles the status scripts.
//
// The status scripts in scripts/bar/ print {text, tooltip, class} JSON.
Singleton {
    id: root

    readonly property string scripts: Quickshell.shellDir + "/scripts/bar"
    readonly property string hyprDo: Quickshell.env("HOME") + "/.config/hypr/scripts/hypr-do.sh"

    readonly property Feed serverHealth: Feed {
        script: "server_health.sh"
        interval: 30000
    }
    readonly property Feed grafana: Feed {
        script: "grafana_status.sh"
        interval: 60000
    }
    readonly property Feed ytmusic: Feed {
        script: "ytmusic_status.sh"
        interval: 2000
    }
    readonly property Feed uptime: Feed {
        script: "system_uptime.sh"
        interval: 30000
    }
    readonly property Feed obs: Feed {
        script: "obs_status.sh"
        interval: 1000
    }
    readonly property Feed tailscale: Feed {
        script: "tailscale_status.sh"
        interval: 10000
    }
    readonly property Feed adguardvpn: Feed {
        script: "adguardvpn_status.sh"
        interval: 5000
    }
    readonly property Feed cpu: Feed {
        script: "cpu_stats.sh"
        interval: 2000
    }
    readonly property Feed memory: Feed {
        script: "memory_stats.sh"
        interval: 2000
    }
    readonly property Feed gpu: Feed {
        script: "gpu_stats.sh"
        interval: 5000
    }
    readonly property Feed disk: Feed {
        script: "disk_usage.sh"
        interval: 30000
    }

    readonly property var feeds: ({
            serverHealth,
            grafana,
            ytmusic,
            uptime,
            obs,
            tailscale,
            adguardvpn,
            cpu,
            memory,
            gpu,
            disk
        })

    // Run a shell command from a click. With `feed`, that feed re-polls once
    // the command exits — so a toggle shows its new state without waiting out the poll interval.
    function exec(cmd, feed) {
        const line = feed ? cmd + "; qs ipc call bar refresh " + feed : cmd;
        Quickshell.execDetached(["sh", "-c", line]);
    }

    // Through the hypr-do.sh shim, not Hyprland.dispatch: under a Lua config
    // Hyprland rejects the legacy "workspace N" (the waybar 0.15.0 bug this
    // bar replaced), and Quickshell 0.3.1's Hyprland.usingLua only turns true
    // after a legacy dispatch has failed — the first click would be lost.
    // `target` is a workspace id or an "e+1"-style string.
    function focusWorkspace(target) {
        Quickshell.execDetached([hyprDo, "workspace", String(target)]);
    }

    // Script output is Pango markup; Qt's StyledText reads the same entities
    // but, like HTML, collapses runs of spaces (the scripts' "icon  value"
    // gaps) and wants <br> for line breaks.
    function markup(s) {
        return (s || "").replace(/ (?= )/g, "&nbsp;").replace(/\n/g, "<br>");
    }

    IpcHandler {
        target: "bar"

        function refresh(name: string): void {
            const feed = root.feeds[name];
            if (feed)
                feed.refresh();
        }
    }

    // A failed run (nonzero exit, timeout, unparsable output) keeps the last
    // value instead of blanking the pill.
    component Feed: Process {
        id: feed

        property string script
        property int interval
        property string text
        property string tooltip
        property string cls

        function refresh() {
            if (!running)
                running = true;
        }

        function ingest(out) {
            let v = null;
            try {
                v = JSON.parse(out);
            } catch (e) {
                return;
            }
            if (!v || typeof v !== "object")
                return;
            text = v.text || "";
            tooltip = v.tooltip || "";
            cls = v["class"] || "";
        }

        command: [root.scripts + "/" + script]
        stdout: StdioCollector {
            onStreamFinished: feed.ingest(text)
        }

        onRunningChanged: {
            if (running)
                watchdog.restart();
            else
                watchdog.stop();
        }

        property Timer poll: Timer {
            interval: feed.interval
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: feed.refresh()
        }

        property Timer watchdog: Timer {
            interval: 20000
            onTriggered: feed.running = false
        }
    }

    // ---- Audio -------------------------------------------------------------

    readonly property PwNode sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [root.sink]
    }

    // ---- Network -----------------------------------------------------------
    // Bandwidth of the default-route interface (IPv4, else IPv6), from two
    // /proc reads 2s apart.

    property string netIface: ""
    property bool netWifi: false
    property real netRxBps: 0
    property real netTxBps: 0
    property string netIp: ""
    property string netSsid: ""
    property var netPrev: null

    function ingestNet(out) {
        const [route4, route6, dev] = out.split("--sep--");
        let iface = "";
        for (const line of route4.split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            if (f.length > 2 && f[1] === "00000000") {
                iface = f[0];
                break;
            }
        }
        // ipv6_route: dest, prefix len, ..., device last; ::/0 is the default.
        for (const line of (iface ? [] : (route6 || "").split("\n"))) {
            const f = line.trim().split(/\s+/);
            if (f.length === 10 && /^0+$/.test(f[0]) && f[1] === "00" && f[9] !== "lo") {
                iface = f[9];
                break;
            }
        }
        let rx = -1, tx = -1;
        for (const line of (dev || "").split("\n")) {
            const [name, rest] = line.split(":");
            if (rest !== undefined && name.trim() === iface) {
                const f = rest.trim().split(/\s+/);
                rx = Number(f[0]);
                tx = Number(f[8]);
            }
        }
        const now = Date.now();
        const prev = netPrev;
        if (iface && rx >= 0 && prev && prev.iface === iface) {
            const dt = (now - prev.at) / 1000;
            netRxBps = Math.max(0, (rx - prev.rx) * 8 / dt);
            netTxBps = Math.max(0, (tx - prev.tx) * 8 / dt);
        } else {
            netRxBps = 0;
            netTxBps = 0;
        }
        netPrev = iface && rx >= 0 ? {
            iface,
            rx,
            tx,
            at: now
        } : null;
        if (iface !== netIface) {
            netIface = iface;
            netInfo.refresh();
        }
    }

    function ingestNetInfo(out) {
        const [wifi, ip, ssid] = out.split("\n");
        netWifi = wifi === "1";
        netIp = ip || "";
        netSsid = ssid || "";
    }

    // Bits per second with SI prefixes ("1.2Mb/s").
    function formatBits(bps) {
        const units = ["b/s", "kb/s", "Mb/s", "Gb/s"];
        let i = 0;
        while (bps >= 1000 && i < units.length - 1) {
            bps /= 1000;
            i++;
        }
        return (i > 0 && bps < 10 ? bps.toFixed(1) : Math.round(bps)) + units[i];
    }

    Process {
        id: netDev
        command: ["sh", "-c", "cat /proc/net/route; echo --sep--; cat /proc/net/ipv6_route; echo --sep--; cat /proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: root.ingestNet(text)
        }
    }

    // Slow-changing details for the tooltip: wifi flag, CIDR address, SSID.
    Process {
        id: netInfo

        function refresh() {
            if (!running && root.netIface)
                running = true;
        }

        command: ["sh", "-c", "[ -d /sys/class/net/$1/wireless ] && echo 1 || echo 0; ip -o -4 addr show dev \"$1\" | awk '{print $4; exit}'; command -v iwgetid >/dev/null && iwgetid -r \"$1\"", "sh", root.netIface]
        stdout: StdioCollector {
            onStreamFinished: root.ingestNetInfo(text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!netDev.running)
                netDev.running = true;
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: netInfo.refresh()
    }
}
