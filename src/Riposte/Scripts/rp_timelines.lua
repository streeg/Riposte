-- Riposte declared timings: attacks that carry a "BattleKeyframes" track
-- declare their hit moments up front in a BP_BattleSequenceTimeline. Research
-- showed these include non-damaging effects too (e.g. a jump take-off), so
-- they are only a first guess; learned timings replace them (rp_learning).

local core = require("rp_core")
local cfg, valid, isEnemy, log, dbg = core.cfg, core.valid, core.isEnemy, core.log, core.dbg

local M = {}

local timelines = {}   -- timeline address -> BP_BattleSequenceTimeline_C
local pollNow = false  -- search on the next tick (an attack just started)
local hadRunning = false
local pollFound = 0

-- FindAllOf walks every object in the game (the most expensive call in the
-- mod): never outside battle, a short burst when an enemy attack starts, then
-- once a second as a fallback (the Declare hook was seen to stop delivering
-- after the first fight).
local POLL_BURST_TICKS, POLL_BURST_EVERY, POLL_SLOW_EVERY = 60, 6, 100
local burstUntil = 0

function M.requestPoll() pollNow = true end
function M.pollPending() return pollNow end

-- Out of battle: drop stale timeline objects.
function M.clear()
  if next(timelines) then
    for k in pairs(timelines) do timelines[k] = nil end
    hadRunning = false
  end
end

-- Post hook on BP_BattleSequenceTimeline_C:DeclareBattleSequenceTimingsAsList.
function M.onDeclared(Context)
  local tl = Context:get()
  if valid(tl) then
    timelines[tl:GetAddress()] = tl
    core.markBattle()
    dbg("attack timeline declared (hook)")
  end
end

local function poll()
  if not FindAllOf then return end
  local all = FindAllOf("BP_BattleSequenceTimeline_C")
  if not all then return end
  for _, tl in ipairs(all) do
    if valid(tl) then
      local key = tl:GetAddress()
      if timelines[key] == nil then pollFound = pollFound + 1 end
      timelines[key] = tl
    end
  end
end

-------------------------------------------------------------------------------
-- keyframe field: Blueprint struct fields carry a GUID suffix that can change
-- when the game is rebuilt, so the name is resolved at runtime
-------------------------------------------------------------------------------

local KEYFRAME_ACTION_DEFAULT = "ActionType_7_0B741BF041C3787D2F89AEB5282B2A8B"
local keyframeField = nil
local keyframeBroken = false

local function resolveActionField(keyframe)
  local ok, v = pcall(function() return keyframe[KEYFRAME_ACTION_DEFAULT] end)
  if ok and type(v) == "number" then return KEYFRAME_ACTION_DEFAULT end
  local candidates = {}
  pcall(function()
    for _, s in ipairs(FindAllOf("UserDefinedStruct") or {}) do
      pcall(function()
        s:ForEachProperty(function(prop)
          local n = prop:GetFName():ToString()
          if n:match("^ActionType_") then candidates[#candidates + 1] = n end
        end)
      end)
    end
  end)
  for _, n in ipairs(candidates) do
    local ok2, v2 = pcall(function() return keyframe[n] end)
    if ok2 and type(v2) == "number" then return n end
  end
  return nil
end

-- Upcoming hits of one timeline. Returns nil when it is a running enemy
-- attack, otherwise the reason it was skipped.
local function scan(tl, out)
  if not valid(tl) then return "gone" end
  if keyframeBroken then return "outdated" end
  local seq = tl.CurrentBattleSequence
  if not valid(seq) then return "no sequence" end
  local attacker = tl.BattleCharacter
  if not valid(attacker) then return "no attacker" end
  if not isEnemy(attacker) then return "player attack" end
  local seqActor = seq.LevelSequenceActor
  if not valid(seqActor) then return "no sequence actor" end
  local player = seqActor.SequencePlayer
  if not valid(player) or not player:IsPlaying() then return "not playing" end

  local timeOut = {}
  tl:GetCurrentBattleSequenceTime(timeOut)
  local now = timeOut.Time
  if type(now) ~= "number" then return "no clock" end
  local rate = player:GetPlayRate()
  if type(rate) ~= "number" or rate <= 0 then rate = 1 end

  tl.CurrentBattleSequenceTimeline:ForEach(function(k, v)
    if keyframeBroken then return true end
    local at, keyframe = k:get(), v:get()
    if not keyframeField then
      keyframeField = resolveActionField(keyframe)
      if not keyframeField then
        keyframeBroken = true
        log("WARNING: the attack keyframe layout changed (no ActionType_* field). The game was " ..
          "probably updated and Riposte may be outdated. Declared hit timings are off; the circle " ..
          "only shows timings learned from hits.")
        return true
      elseif keyframeField ~= KEYFRAME_ACTION_DEFAULT then
        log("keyframe field renamed by a game update, now using " .. keyframeField)
      end
    end
    if keyframe[keyframeField] == core.ACTION_EFFECT then
      out[#out + 1] = { remaining = (at - now) / rate, attacker = attacker }
    end
  end)
  return nil
end

-------------------------------------------------------------------------------
-- debug: one line whenever the set of tracked timelines changes state
-------------------------------------------------------------------------------

local lastSummary, lastSummaryAt = "", 0
local function logSummary(counts, hitCount)
  local parts = {}
  for why, n in pairs(counts) do parts[#parts + 1] = n .. " " .. why end
  if #parts == 0 then return end
  table.sort(parts)
  local text = table.concat(parts, ", ") .. "; " .. hitCount .. " hit(s) ahead"
  local now = os.time()
  if text ~= lastSummary and now ~= lastSummaryAt then
    lastSummary, lastSummaryAt = text, now
    dbg("timelines: " .. text .. " (found by poll so far: " .. pollFound .. ")")
  end
end

-- Called every battle tick. Appends declared upcoming hits to `hits` and
-- returns the per-reason counts (counts.running = a declared attack is playing).
function M.collect(hits)
  local tick = core.state.tick
  if pollNow then
    pollNow = false
    burstUntil = tick + POLL_BURST_TICKS
    poll()
  elseif tick < burstUntil and not hadRunning then
    if tick % POLL_BURST_EVERY == 0 then poll() end
  elseif tick % POLL_SLOW_EVERY == 0 then
    poll()
  end

  local counts = {}
  for key, tl in pairs(timelines) do
    local ok, why = pcall(scan, tl, hits)
    if not ok then why = "error: " .. tostring(why) end
    if not ok or why == "gone" then timelines[key] = nil end
    why = why or "running"
    counts[why] = (counts[why] or 0) + 1
  end
  hadRunning = counts.running ~= nil
  if hadRunning then core.markBattle() end
  if cfg.Debug then logSummary(counts, #hits) end
  return counts
end

return M
