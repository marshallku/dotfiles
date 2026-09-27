pragma Singleton

import QtQuick
import Quickshell

// Catppuccin Mocha (celestial-dark.md) — same palette as copad/tmux.
Singleton {
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color base: "#1e1e2e"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color overlay0: "#6c7086"
    readonly property color overlay1: "#7f849c"
    readonly property color subtext0: "#a6adc8"
    readonly property color subtext1: "#bac2de"
    readonly property color text: "#cdd6f4"

    readonly property color mauve: "#cba6f7"
    readonly property color blue: "#89b4fa"
    readonly property color lavender: "#b4befe"
    readonly property color teal: "#94e2d5"
    readonly property color green: "#a6e3a1"
    readonly property color yellow: "#f9e2af"
    readonly property color peach: "#fab387"
    readonly property color red: "#f38ba8"

    readonly property color cardBg: Qt.rgba(0.07, 0.07, 0.11, 0.72)
    readonly property color cardBorder: Qt.rgba(0.80, 0.65, 0.97, 0.18)

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string sans: "Pretendard"

    readonly property int radius: 14
    readonly property int gap: 12
    readonly property int pad: 16

    // Threshold colour for a 0–100 utilisation value.
    function level(pct) {
        if (pct === null || pct === undefined)
            return overlay0;
        if (pct >= 90)
            return red;
        if (pct >= 70)
            return peach;
        if (pct >= 50)
            return yellow;
        return green;
    }

    // {item[key]: item}. Qt's JS engine has no Object.fromEntries.
    function index(items, key) {
        const out = {};
        for (const it of (items || []))
            out[it[key]] = it;
        return out;
    }

    // `now` is passed in (Data.now) so bindings re-evaluate every second.
    function ago(ms, now) {
        if (!ms)
            return "";
        const s = Math.max(0, Math.floor((now - ms) / 1000));
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    function until(epochSec, now) {
        if (!epochSec)
            return "";
        const s = Math.max(0, Math.floor(epochSec - now / 1000));
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m";
        return Math.floor(s / 86400) + "d " + Math.floor((s % 86400) / 3600) + "h";
    }
}
