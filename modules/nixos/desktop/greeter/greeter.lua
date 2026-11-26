-- The greeter's Hyprland, run by greetd as the `greeter` user. It exists to
-- give Quickshell a screen: no binds, so nothing at the login screen reaches
-- anything but the password field, and it exits once the greeter does.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- The TV, pinned rather than "auto" so the login screen's layout, which is
-- sized for 1920x1080 logical pixels, doesn't rest on Hyprland's guess.
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 2 })

hl.config({
  -- The QML animates itself. Hyprland's layer fade would run on top of it.
  animations = { enabled = false },
  decoration = { blur = { enabled = false }, shadow = { enabled = false } },

  input = {
    kb_layout = "us",
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
    },
  },

  -- Nothing here is an X11 client.
  xwayland = { enabled = false },

  cursor = {
    hide_on_key_press = true,
    inactive_timeout = 5,
  },

  misc = {
    background_color = "@background@",
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    -- Each of these otherwise puts a notification over the login screen:
    -- greetd starts Hyprland directly rather than through start-hyprland, and
    -- the greeter's environment has neither the XDG variables nor
    -- hyprland-guiutils that a desktop session would.
    disable_watchdog_warning = true,
    disable_xdg_env_checks = true,
    disable_hyprland_guiutils_check = true,
  },

  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },
})

hl.on("hyprland.start", function()
  hl.exec_cmd("@session@")
end)
