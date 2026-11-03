-- Riposte hook plumbing: Blueprint hooks that survive the battle Blueprints
-- loading late (and reloading), game-thread timers, and the hotkey.

local core = require("rp_core")
local valid, log = core.valid, core.log

local M = {}

local hooks = {}

-- Wrap a callback so an error is logged (rate-limited) instead of propagating.
function M.guarded(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then core.logError(name, err) end
  end
end

-- Hook a Blueprint function by path, as soon as it exists.
function M.add(path, fn)
  hooks[#hooks + 1] = { path = path, fn = fn }
end

-- Registers every hook whose function is loaded; re-registers if the Blueprint
-- was unloaded and loaded again (a new UFunction at a new address).
function M.ensure()
  for _, h in ipairs(hooks) do
    local fnObj = StaticFindObject(h.path)
    if valid(fnObj) then
      local addr = fnObj:GetAddress()
      if h.addr ~= addr then
        local ok, err = pcall(RegisterHook, h.path, M.guarded(h.path, h.fn))
        if ok then
          h.addr = addr
          log("hooked " .. h.path)
          if core.research then core.rs("signature", h.path, fnObj) end
        else
          log("could not hook " .. h.path .. ": " .. tostring(err))
        end
      end
    end
  end
end

-- Run fn on the game thread every `ms` milliseconds.
function M.everyMs(ms, name, fn)
  local safe = M.guarded(name, fn)
  if LoopInGameThreadWithDelay then
    LoopInGameThreadWithDelay(ms, function() safe() end)
  else
    local queued = false
    LoopAsync(ms, function()
      if not queued then
        queued = true
        ExecuteInGameThread(function()
          queued = false
          safe()
        end)
      end
      return false
    end)
  end
end

-- Hotkey by name ("F8"), optionally with Ctrl. The callback runs on the game thread.
function M.key(keyName, withCtrl, name, fn)
  if not keyName or keyName == "" or not RegisterKeyBind or not Key then return end
  local key = Key[string.upper(keyName)]
  if not key then
    log("key '" .. tostring(keyName) .. "' is not a valid key name")
    return
  end
  local run = M.guarded(name, fn)
  local function onKey()
    if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
  end
  local ok, err
  if withCtrl ~= false and ModifierKey then
    ok, err = pcall(RegisterKeyBind, key, { ModifierKey.CONTROL }, onKey)
  else
    ok, err = pcall(RegisterKeyBind, key, onKey)
  end
  if not ok then log("could not register key " .. keyName .. ": " .. tostring(err)) end
end

return M
