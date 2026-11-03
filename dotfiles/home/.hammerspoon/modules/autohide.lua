local _ = require('modules.utilities')

local M = {}

local autoHideWatcher = nil
local appsToHide = {}
local lastHideTime = {}

local DEBOUNCE_INTERVAL = 1 -- Adjust this value (in seconds) as needed

function M.maxDisplays(n)
  return function()
    return #hs.screen.allScreens() <= n
  end
end

local function normalize(entry)
  if type(entry) == 'string' then
    return { name = entry }
  end
  return entry
end

local function normalizeAll(apps)
  local result = {}
  for i, entry in ipairs(apps or {}) do
    result[i] = normalize(entry)
  end
  return result
end

local function shouldAutoHide(appName)
  if not appName then return false end

  local lowerAppName = string.lower(appName)

  -- Check if we've hidden this app recently
  local currentTime = hs.timer.secondsSinceEpoch()
  local lastTime = lastHideTime[lowerAppName]

  if lastTime and (currentTime - lastTime) < DEBOUNCE_INTERVAL then
    return false
  end

  for _, entry in ipairs(appsToHide) do
    if string.lower(entry.name) == lowerAppName then
      if entry.when and not entry.when() then
        return false
      end
      return true
    end
  end
  return false
end

-- System Events' "set visible" is this same Accessibility write, but it waits
-- out the default six-second timeout on an app that has stopped answering, as
-- one does while it quits, and Hammerspoon is blocked for all of it.
local HIDE_TIMEOUT = 1

local function hideApp(app)
  local frontmost = hs.application.frontmostApplication()

  local element = hs.axuielement.applicationElement(app)
  local ok = element ~= nil
    and element:setTimeout(HIDE_TIMEOUT):setAttributeValue("AXHidden", true) ~= nil

  -- Record the hide time if successful
  if ok then
    lastHideTime[string.lower(app:name())] = hs.timer.secondsSinceEpoch()
  end

  -- Ensure focus returns to the app we switched to
  if frontmost then
    frontmost:activate()
  end

  return ok
end

local function hide(app)
  if hideApp(app) then return end

  -- Quitting deactivates an app before it exits, so a hide that fails is
  -- usually an app on its way out rather than one refusing to hide.
  hs.timer.doAfter(2, function()
    if app:isRunning() then
      _.alert("Failed to hide " .. app:name())
    end
  end)
end

local function createWatcher()
  -- Not `_`, which would shadow the utilities module in here.
  return hs.application.watcher.new(function(_name, eventType, appObject)
    if eventType == hs.application.watcher.deactivated then
      if appObject and shouldAutoHide(appObject:name()) then
        -- Small delay to ensure the focus transition has completed
        hs.timer.doAfter(0.1, function()
          hide(appObject)
        end)
      end
    end
  end)
end

function M.start(apps)
  if autoHideWatcher then
    autoHideWatcher:stop()
  end

  appsToHide = normalizeAll(apps)
  lastHideTime = {} -- Reset the hide times when starting

  autoHideWatcher = createWatcher()
  autoHideWatcher:start()
end

function M.stop()
  if autoHideWatcher then
    autoHideWatcher:stop()
    autoHideWatcher = nil
  end
  lastHideTime = {} -- Clear the hide times when stopping
end

function M.updateApps(apps)
  appsToHide = normalizeAll(apps)
end

return M
