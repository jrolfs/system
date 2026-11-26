-- The desktop picture, across every space.
--
-- macOS keeps the picture in a store WallpaperAgent owns rather than reads
-- (~/Library/Application Support/com.apple.wallpaper/Store/Index.plist), so
-- writing the preference does nothing: the only public way in is NSWorkspace,
-- which is hs.screen:desktopImageURL here. That paints the *active* space of
-- each screen and nothing else — System Settings writes an "all spaces and
-- displays" scope no public API reaches.
--
-- Reaching a space you are not on means hs.spaces.gotoSpace, and that works by
-- driving the Mission Control UI: it takes over the screen, and keystrokes
-- during the hop land wherever it went. Fine when you ask for it (M.walk),
-- not fine unprompted from a darwin-rebuild switch, when you may well be
-- typing. So M.apply paints the space you are on and arms a watcher, and the
-- rest are corrected as you arrive at them, invisibly.
--
-- Driven from home-manager activation (modules/home/wallpaper.nix), which is
-- where the path is declared.

local M = {}

-- The URL every space should be showing once it has been visited. Set by
-- M.apply; nil until then, which is what disarms the watcher's work.
M.target = nil

-- gotoSpace returns as soon as it has pressed the Mission Control button, not
-- when the switch has landed, so M.walk has to wait before painting.
M.settleTime = 1.0

local watcher = nil
local pending = nil

local function paint()
  if not M.target then
    return
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:desktopImageURL() ~= M.target then
      screen:desktopImageURL(M.target)
    end
  end
end

local function painted()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:desktopImageURL() ~= M.target then
      return false
    end
  end

  return true
end

local function userSpaces()
  local spaces = {}

  for _, ids in pairs(hs.spaces.allSpaces() or {}) do
    for _, id in ipairs(ids) do
      -- Fullscreen spaces belong to their app's window, not to the desktop.
      if hs.spaces.spaceType(id) == "user" then
        spaces[#spaces + 1] = id
      end
    end
  end

  return spaces
end

-- Paint on arrival. The watcher fires as the new space becomes active, so a
-- beat's delay keeps the paint off the space being left; and paint() is a
-- no-op for a space that is already right (1.4ms a screen, against 64ms for a
-- write), which every space is once this has caught up.
--
-- Only the newest event is worth acting on, so an outstanding paint is dropped
-- rather than left to stack up: paint() works on whatever space is current when
-- it fires, not the one the event was about, so switching quickly through four
-- spaces would otherwise paint the fourth one four times.
local function watch()
  if watcher then
    return
  end

  watcher = hs.spaces.watcher.new(function()
    if pending then
      pending:stop()
    end

    pending = hs.timer.doAfter(0.3, paint)
  end):start()
end

-- Point the desktop at `path`, here and from now on.
--
-- Returns "missing" if the file isn't there, "unchanged" if the spaces in front
-- of you already show it, or "set". In all three cases the other spaces are
-- left to the watcher, which is armed for the rest of this Hammerspoon session
-- — a reload before you have visited them all means they wait for the next
-- switch to re-arm it.
function M.apply(path)
  -- Percent-encoded file:// URL via NSURL, so it compares equal to what the
  -- getter hands back. Nil for a path that doesn't exist, which is the check we
  -- want anyway: pointing the desktop at a missing file paints it black.
  local url = hs.fs.urlFromPath(path)

  if not url then
    return "missing"
  end

  M.target = url
  watch()

  if painted() then
    return "unchanged"
  end

  paint()

  return "set"
end

-- Paint every space now, rather than as you get to them. Drives Mission
-- Control, so it takes the screen for about a second a space.
function M.walk(path)
  if path then
    local url = hs.fs.urlFromPath(path)

    if not url then
      return "missing"
    end

    M.target = url
    watch()
  end

  if not M.target then
    return "no picture declared yet"
  end

  local origin = hs.spaces.focusedSpace()
  local remaining = {}

  for _, id in ipairs(userSpaces()) do
    if id ~= origin then
      remaining[#remaining + 1] = id
    end
  end

  paint()

  local index = 0

  local function step()
    index = index + 1
    local id = remaining[index]

    if not id then
      pending = nil

      if hs.spaces.focusedSpace() ~= origin then
        hs.spaces.gotoSpace(origin)
      end

      return
    end

    -- Needs Accessibility. A space we can't reach keeps its old picture until
    -- the watcher catches it; the rest still get painted.
    local ok, err = hs.spaces.gotoSpace(id)

    if not ok then
      print("wallpaper: could not reach space " .. tostring(id) .. ": " .. tostring(err))
      return step()
    end

    pending = hs.timer.doAfter(M.settleTime, function()
      paint()
      step()
    end)
  end

  step()

  return "walking " .. #remaining .. " space(s)"
end

return M
