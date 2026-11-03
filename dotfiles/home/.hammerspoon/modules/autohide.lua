local _ = require('modules.utilities')

local M = {}

local autoHideWatcher = nil
local appsToHide = {}
local lastHideTime = {}

-- An app that lost focus to a Touch ID prompt, left visible until focus moves
-- on from the prompt
local heldForPrompt = nil

local DEBOUNCE_INTERVAL = 1 -- Adjust this value (in seconds) as needed

-- Touch ID prompts belong to these rather than to the app that asked:
-- SecurityAgent for sudo and system authorizations, coreautha for apps using
-- LocalAuthentication. Focus going to one is not the app being left.
local AUTH_AGENTS = {
  ["com.apple.SecurityAgent"] = true,
  ["com.apple.LocalAuthentication.UIAgent"] = true,
}

local function isAuthAgent(app)
  return app ~= nil and AUTH_AGENTS[app:bundleID()] == true
end

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

-- Read from what is frontmost once the transition settles, not from the event,
-- so a prompt that closes and hands focus straight back counts as a return.
local function settleHeld()
  local held = heldForPrompt
  if not held then return end

  local frontmost = hs.application.frontmostApplication()
  if isAuthAgent(frontmost) then return end

  heldForPrompt = nil
  if frontmost and frontmost:pid() == held:pid() then return end

  if held:isRunning() then
    hide(held)
  end
end

local function createWatcher()
  -- Not `_`, which would shadow the utilities module in here.
  return hs.application.watcher.new(function(_name, eventType, appObject)
    if not appObject then return end

    if eventType == hs.application.watcher.activated then
      if heldForPrompt and not isAuthAgent(appObject) then
        -- Small delay to ensure the focus transition has completed
        hs.timer.doAfter(0.1, settleHeld)
      end
    elseif eventType == hs.application.watcher.deactivated then
      if shouldAutoHide(appObject:name()) then
        -- Small delay to ensure the focus transition has completed
        hs.timer.doAfter(0.1, function()
          if isAuthAgent(hs.application.frontmostApplication()) then
            heldForPrompt = appObject
          else
            hide(appObject)
          end
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
  heldForPrompt = nil

  autoHideWatcher = createWatcher()
  autoHideWatcher:start()
end

function M.stop()
  if autoHideWatcher then
    autoHideWatcher:stop()
    autoHideWatcher = nil
  end
  lastHideTime = {} -- Clear the hide times when stopping
  heldForPrompt = nil
end

function M.updateApps(apps)
  appsToHide = normalizeAll(apps)
end

return M
