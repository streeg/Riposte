-- Riposte per-frame loop: gathers the upcoming hits from every timing source,
-- decides what the overlay should show and hands it a frame to draw.
--
-- Timing sources, most trusted first:
--   1. learned  - recorded arrival times of this attack (rp_learning)
--   2. declared - the attack's own keyframes, a first guess (rp_timelines)
--   3. none     - "learning" label until the first hit arrives

local core = require("rp_core")
local rules = require("rp_rules")
local timelines = require("rp_timelines")
local learning = require("rp_learning")
local overlay = require("rp_overlay")
local cfg, valid, dbg = core.cfg, core.valid, core.dbg
local state, ui = core.state, core.state.ui

local M = {}

local lastGameTime = 0

function M.tick()
  if not cfg.Visualizer and not cfg.ShowGrazeText then return end
  state.tick = state.tick + 1

  -- Outside a battle: nothing to draw and nothing to search. Write learned
  -- timings to disk here, never mid-fight.
  if not core.inBattle() and not state.attack and not timelines.pollPending() and not overlay.visible() then
    learning.flushIfDirty()
    if core.research then core.rs("flush") end
    timelines.clear()
    return
  end

  local hits = {}
  local counts = timelines.collect(hits)
  local isLearning = learning.update(hits, counts)

  -- latency compensation: the drawing runs VisualOffset ahead of the game
  local offset = cfg.VisualOffset or 0
  if offset ~= 0 then
    for _, h in ipairs(hits) do h.remaining = h.remaining - offset end
  end

  local ctx = (hits[1] and hits[1].attacker) or ui.ctx
  if not valid(ctx) then
    overlay.hide()
    return
  end
  local t = core.gameTime(ctx)
  if t + 1 < lastGameTime then
    core.resetTimedState()
    rules.resetCache()
    dbg("game clock restarted, state cleared")
  end
  local dt = t - lastGameTime
  if dt < 0 or dt > 0.25 then dt = 0.016 end
  lastGameTime = t

  -- the rings: nearest first, one per hit (two timeline objects can report the
  -- same hit), within the lead time
  table.sort(hits, function(a, b) return a.remaining < b.remaining end)
  local upcoming = {}
  if cfg.Visualizer then
    for _, h in ipairs(hits) do
      local prev = upcoming[#upcoming]
      local twin = prev and math.abs(prev.remaining - h.remaining) < 0.02
      if not twin and h.remaining >= 0 and h.remaining <= cfg.LeadTime and #upcoming < cfg.MaxRings then
        upcoming[#upcoming + 1] = h
      end
    end
  end

  -- impact burst: the predicted moment of the previous lead ring has passed
  if ui.nextHit and t >= ui.nextHit.at then
    if t - ui.nextHit.at < overlay.FLASH_TIME then ui.flash = { t0 = ui.nextHit.at, color = ui.nextHit.color } end
    ui.nextHit = nil
  end
  local flashActive = ui.flash ~= nil and t >= ui.flash.t0 and t < ui.flash.t0 + overlay.FLASH_TIME
  if not flashActive then ui.flash = nil end

  local f = {
    t = t, dt = dt, upcoming = upcoming, learning = isLearning, flashActive = flashActive,
    msgActive = ui.msg ~= nil and t < ui.msgUntil and t > ui.msgUntil - 5,
    lateActive = t < ui.lateUntil and t > ui.lateUntil - 5,
  }
  if #upcoming == 0 and not f.msgActive and not f.lateActive and not f.learning and not flashActive then
    overlay.fadeOut(dt)
    return
  end

  if #upcoming > 0 then
    local lead = upcoming[1]
    -- the live flags still describe the previous hit; trust them only when the
    -- kind of this hit has not been learned yet
    f.kind = lead.kind
    f.flags = lead.kind and rules.codeFlags(lead.kind) or rules.attackFlags(lead.attacker.AC_jRPG_CharacterStats)
    local a = state.attack
    f.win = rules.heroWindows(lead.attacker, (a and valid(a.target) and a.target) or state.lastPresser)
  end
  overlay.render(f)
end

return M
