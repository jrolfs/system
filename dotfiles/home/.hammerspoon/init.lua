require("hs.ipc")

local _ = require("modules.utilities")

_.bindHyper("h", function()
  hs.reload()
end)

_.bindHyper("c", require("modules.finder").copyPath)

local autohide = require('modules.autohide')

autohide.start({
  "1Password",
  "ChatGPT",
  "Dash",
  "DevDocs",
  "Discord",
  "Find My",
  "Kaset",
  "Linear",
  "Maps",
  "Music",
  "Obsidian",
  "Photos",
  "Plexamp",
  "Reminders",
  "Resilio Sync",
  "Sirius",
  "Spotify", -- { name = "Spotify", when = autohide.maxDisplays(1) },
  "WhatsApp",
  "Yaak",
  "YouTube",
  "iPhone Mirroring",
  "kitty",
})

require('modules.touchid-focus').start()

local zed = require('modules.zed')

_.bindHyper("z", zed.toast.view)
_.bindHyper("x", zed.toast.dismiss)

local displays = require('modules.displays')

_.bindHyper("d", displays.choose)

require("modules.notifications").bind({
  leader = { {"ctrl", "alt", "cmd", "shift"}, "n" },
  activate = "return",
  details = "o",
  close = "x",
  next = "k",
  previous = "j",
})

_.alert("Loaded Hammerspoon configuration", { emoji = "🔨" })
