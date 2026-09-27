pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The only owner of collector processes. Lives outside the per-screen
// Variants so two monitors never double the subprocesses or HTTP requests.
//
// Every section follows the same contract: a fresh {ok:true} replaces it;
// anything else (nonzero exit, timeout, unparsable output, ok:false) keeps
// the last good values and flips `stale`, so a failed probe can never leave
// a green server on screen without a stale marker.
Singleton {
    id: root

    readonly property string scripts: Quickshell.shellDir + "/scripts"

    property var agents: empty()
    property var attention: empty()
    property var limits: empty()
    property var today: empty()
    property var servers: empty()
    property var nodes: empty()
    property var tailscale: empty()

    // Ticks once a second so relative ages ("3m ago") re-evaluate.
    property real now: Date.now()

    function empty() {
        return {
            loaded: false,
            stale: false,
            error: "",
            lastOk: 0,
            items: []
        };
    }

    function merge(prev, next) {
        if (next && next.ok === true)
            return Object.assign({
                items: []
            }, next, {
                loaded: true,
                stale: false,
                error: "",
                lastOk: Date.now()
            });
        return Object.assign({}, prev, {
            stale: prev.loaded,
            error: (next && next.error) ? next.error : "collector failed"
        });
    }

    function parse(text) {
        try {
            const v = JSON.parse(text);
            return (v && typeof v === "object") ? v : null;
        } catch (e) {
            return null;
        }
    }

    function ingestAgents(text) {
        const v = parse(text);
        agents = merge(agents, v ? v.agents : null);
        attention = merge(attention, v ? v.attention : null);
    }

    function ingestUsage(text) {
        const v = parse(text);
        limits = merge(limits, v ? v.limits : null);
        today = merge(today, v ? v.today : null);
    }

    function ingestHomelab(text) {
        const v = parse(text);
        servers = merge(servers, v ? v.servers : null);
        nodes = merge(nodes, v ? v.nodes : null);
        tailscale = merge(tailscale, v ? v.tailscale : null);
    }

    // A run that exits nonzero, prints nothing, or is killed by the watchdog
    // still closes stdout, so streamFinished always fires; parse() rejecting
    // the (empty or partial) text is what routes it to the stale path.
    component Collector: Process {
        id: proc

        property int watchdogMs: 20000
        property var ingest

        // In-flight guard: a slow run is never stacked with another.
        function kick() {
            if (!running)
                running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: proc.ingest(text)
        }

        onRunningChanged: {
            if (running)
                watchdog.restart();
            else
                watchdog.stop();
        }

        property Timer watchdog: Timer {
            interval: proc.watchdogMs
            onTriggered: proc.running = false
        }
    }

    Collector {
        id: agentsProc
        command: [root.scripts + "/agents.sh"]
        ingest: root.ingestAgents
    }

    Collector {
        id: usageProc
        command: [root.scripts + "/usage.sh"]
        watchdogMs: 40000
        ingest: root.ingestUsage
    }

    Collector {
        id: homelabProc
        command: [root.scripts + "/homelab.sh"]
        ingest: root.ingestHomelab
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: agentsProc.kick()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: usageProc.kick()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: homelabProc.kick()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
}
