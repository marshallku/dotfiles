-- ###########################################################################
-- Hyprland config (Lua).
--
-- Migrated from hyprland.conf (hyprlang) — hyprlang is deprecated since
-- Hyprland 0.55 and its support was removed from the tree in 0.57
-- (commit a9902ea6, "config: remove legacy config support").
--
-- Refer to the wiki: https://wiki.hypr.land/Configuring/Start/
-- API stubs for LSP autocomplete: /usr/share/hypr/stubs/hl.meta.lua
-- Validate edits without restarting:  Hyprland --verify-config
-- ###########################################################################


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Monitor + workspace<->monitor bindings are per-machine and kept local
-- (not tracked in dotfiles). Copy monitors_local.lua.example to
-- monitors_local.lua and edit it for this machine.
--
-- Probe for the file rather than pcall(require, ...): a pcall would also
-- swallow a genuine error inside monitors_local.lua, and `--verify-config`
-- would still print "config ok". Missing file -> fallback; broken file -> the
-- error propagates and gets reported like any other config error.
local configDir       = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local monitorsPresent = false

do
    local f = io.open(configDir .. "monitors_local.lua", "r")

    if f then
        f:close()
        monitorsPresent = true
    end
end

if monitorsPresent then
    require("monitors_local")
else
    -- Fallback: light up every output at its preferred mode.
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "/home/marshall/.local/bin/copad"
local fileManager = "dolphin"
local menu        = "wofi --show drun"
local browser     = "firefox"

local scripts     = "~/.config/hypr/scripts"


-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    -- Propagate compositor env into systemd --user + D-Bus activation so
    -- dbus-activated services (e.g. dunst -> org.freedesktop.Notifications,
    -- copadd auto-started by systemd) can see WAYLAND_DISPLAY and pick
    -- the Wayland backend instead of falling back to X11.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")

    hl.exec_cmd("waybar")
    -- Ensure the wallpaper symlink resolves before hyprpaper reads it (fresh stow).
    hl.exec_cmd(scripts .. "/wallpaper.sh ensure && hyprpaper")
    hl.exec_cmd("fcitx5")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprlock")
    -- copad GUI — keeps a registered GUI client attached to copadd at all
    -- times, so remote control via web-bridge (Slice 3+) can reach
    -- terminal.*/tab.list/session.list GUI-owned methods after WOL+SSH wake.
    -- Absolute path because exec runs before user shell PATH resolves.
    hl.exec_cmd(terminal)
end)

-- Surface a missing monitors_local.lua once the compositor is up, so the
-- fallback above is not silently mistaken for a working layout.
if not monitorsPresent then
    hl.on("hyprland.start", function()
        hl.exec_cmd("notify-send -u critical Hyprland " ..
            "'monitors_local.lua not found, using preferred/auto fallback. " ..
            "Copy monitors_local.lua.example to set this machine up.'")
    end)
end


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Font rendering for XWayland apps (like Cursor IDE)
-- NOTE: the hyprlang config wrote this value with literal double quotes
-- (env = FREETYPE_PROPERTIES,"truetype:...") which hyprlang passed through
-- verbatim, so FreeType saw a module named `"truetype` and ignored the
-- property. Unquoted here, which is what was intended.
hl.env("FREETYPE_PROPERTIES", "truetype:interpreter-version=38")
hl.env("GDK_SCALE", "1")
hl.env("QT_SCALE_FACTOR", "1")
hl.env("WINIT_X11_SCALE_FACTOR", "1")

-- Dark theme preference (GTK / Qt / Freedesktop portal)
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("GTK_THEME_VARIANT", "dark")
hl.env("GTK_THEME_PREFER_DARK", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not
-- applied on-the-fly for security reasons

-- hl.config({ ecosystem = { enforce_permissions = true } })

-- hl.permission({ binary = "/usr/(bin|local/bin)/grim", permission = "screencopy", allow = "allow" })


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 2,

        -- Catppuccin mauve -> lavender, matched to hyprlock/dunst accent
        col = {
            active_border   = { colors = { "rgba(cba6f7ee)", "rgba(b4befeee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled  = true,
            size     = 8,
            passes   = 2,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true, -- You probably want this
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },

    xwayland = {
        force_zero_scaling   = false,
        use_nearest_neighbor = false,
    },
})

-- Default curves, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only" — uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({ name = "no-gaps-wtv1", match = { float = false, workspace = "w[tv1]" }, border_size = 0, rounding = 0 })
-- hl.window_rule({ name = "no-gaps-f1",   match = { float = false, workspace = "f[1]"   }, border_size = 0, rounding = 0 })


---------------
---- INPUT ----
---------------

-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        repeat_rate  = 50,
        repeat_delay = 200,

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- See https://wiki.hypr.land/Configuring/Basics/Gestures/
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- See https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q",     hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B",     hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + C",     hl.dsp.window.close())
-- hl.bind(mainMod .. " + M",  hl.dsp.exit())
hl.bind(mainMod .. " + E",     hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V",     hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P",     hl.dsp.window.pseudo())          -- dwindle
hl.bind(mainMod .. " + J",     hl.dsp.layout("togglesplit"))    -- dwindle
hl.bind(mainMod .. " + R",     hl.dsp.exec_cmd("~/.config/waybar/scripts/launch.sh"))
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("hyprlock"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging.
-- These replace hyprlang's `bindm`. No bind option is needed: the dispatchers
-- run CA::mouse("movewindow"/"resizewindow") and set releasePending on the
-- keybind themselves, so they get held-until-release semantics on their own.
-- (The upstream Lua example passes `{ mouse = true }` here; it is not a real
-- bind option — `hyprctl binds` reports mouse=false either way.)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s +10%"))
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"))
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"))
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"))

-- Screenshot
-- Region select by default, SPACE toggles window picking (see the screenshot submap)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(scripts .. "/screenshot.sh interactive"))
hl.bind("Print",                   hl.dsp.exec_cmd(scripts .. "/screenshot.sh screen"))
hl.bind("SHIFT + Print",           hl.dsp.exec_cmd(scripts .. "/screenshot.sh window"))
hl.bind("SUPER + Print",           hl.dsp.exec_cmd(scripts .. "/screenshot.sh region"))

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Ignore maximize requests from apps
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_initial_focus = true,
})

-- Opacity for browsers and Cursor
hl.window_rule({
    name    = "opacity-browsers",
    match   = { class = "^(firefox|Firefox|Cursor)$" },
    opacity = "0.92 0.88",
})

hl.window_rule({
    name    = "opacity-kitty",
    match   = { class = "^(kitty)$" },
    opacity = "0.88 0.8",
})

-- hl.window_rule({
--     name    = "opacity-copad",
--     match   = { class = "^com\\.marshall\\.copad$" },
--     opacity = "0.92 0.88",
-- })


-----------------
---- SUBMAPS ----
-----------------

-- Active while screenshot.sh is waiting on a selection.
-- screenshot.sh enters/leaves it with `hyprctl dispatch 'hl.dsp.submap("...")'`.
hl.define_submap("screenshot", function()
    hl.bind("space",  hl.dsp.exec_cmd(scripts .. "/screenshot.sh toggle"))
    hl.bind("escape", hl.dsp.exec_cmd(scripts .. "/screenshot.sh abort"))
end)
