-- Riposte grace period. Vanilla cancels a hit only if it lands while the
-- hero's dodge / parry / jump immunity runs. Riposte adds a window on both
-- sides:
--   early - immunity ran out up to OuterEarly s before the hit: the damage is
--           scaled down before the game applies it;
--   late  - the press came up to OuterLate s after a full hit: the reduced
--           share is handed back as HP.
-- A graze never triggers a counter: only the game's own success does.

local core = require("rp_core")
local rules = require("rp_rules")
local cfg, valid, isEnemy, dbg = core.cfg, core.valid, core.isEnemy, core.dbg
local state = core.state

local M = {}

local function pct(r) return math.floor(r * 100 + 0.5) end

-- Post hook on BP_BattleDamages_C:ApplyDebugOverrides. Only reached when the
-- hit was NOT dodged / parried / jumped, right before the final rounding.
function M.onDamageAboutToApply(Context)
  local dmg = Context:get()
  local reason = dmg.DamageReason
  if reason == core.REASON_BUFF or reason == core.REASON_LUMINA then return end

  local targetStats, sourceStats = dmg.TargetCharacter, dmg.SourceCharacter
  if not valid(targetStats) or not valid(sourceStats) then return end
  local hero, attacker = targetStats:GetOwner(), sourceStats:GetOwner()
  if not valid(hero) or not valid(attacker) then return end
  if isEnemy(hero) or not isEnemy(attacker) then return end

  local t = core.gameTime(hero)
  local hit = rules.attackFlags(sourceStats)
  hit.t = t
  hit.full = dmg.CurrentInputDamages_Base
  hit.hpBefore = targetStats.CurrentHP
  hit.stats = targetStats
  hit.applied = 0
  state.ui.ctx = hero
  core.markBattle()

  local key = hero:GetAddress()
  local mv = state.lastMove[key]
  if cfg.GracePeriod and mv and rules.moveFits(mv.kind, hit) and cfg.OuterEarly > 0 then
    local late = t - mv.endt -- how long after the vanilla window closed the hit landed
    if late > 0 and late <= cfg.OuterEarly then
      local red = rules.reductionAt(late / cfg.OuterEarly)
      dmg.CurrentInputDamages_Base = hit.full * (1 - red)
      hit.applied = red
      core.showMessage(string.format("GRAZE  -%d%%", pct(red)), hero)
      dbg(string.format("early graze: %s pressed %.3fs too early -> -%d%% (%.0f -> %.0f)",
        mv.kind, late, pct(red), hit.full, hit.full * (1 - red)))
    else
      dbg(string.format("hit landed, last %s was %.3fs outside the window", mv.kind, late))
    end
  else
    dbg(string.format("hit landed (%.0f), no matching press", hit.full))
  end

  if core.research then
    core.rs("dumpOnce", "BattleDamages", dmg)
    core.rs("dumpOnce", "AttackerStats", sourceStats)
    core.rs("dumpOnce", "HeroCharacter", hero)
    local a = state.attack
    core.rs("onDamage", a, a and (t - a.t0) or nil, hit.full, rules.flagsCode(hit), hit.applied)
  end

  state.lastHit[key] = hit
  if hit.applied == 0 and cfg.GracePeriod and cfg.OuterLate > 0 then
    state.ui.lateUntil = t + cfg.OuterLate
  end
end

-- Post hook on TryStartDodge / TryStartParry / TryStartJump / TryStartGradientParry.
-- Party-wide moves call it once per hero.
function M.makePressHook(kind)
  return function(Context, Success)
    local hero = Context:get()
    if not valid(hero) or isEnemy(hero) then return end
    local started = true
    pcall(function() started = Success:get() end)
    if not started then return end

    local t = core.gameTime(hero)
    local key = hero:GetAddress()
    local endt = hero.DefensiveMoveImmunityEndTime
    state.lastMove[key] = { kind = kind, t = t, endt = endt }
    state.ui.ctx = hero
    state.lastPresser = hero
    core.markBattle()
    local a = state.attack
    if core.research and a then core.rs("onPress", a, kind, t - a.t0, (endt or t) - a.t0) end
    if cfg.Debug then dbg(string.format("press %s at %.3f, immune until %.3f", kind, t, endt or -1)) end

    -- late side: this press came just after a hit that landed in full
    local hit = state.lastHit[key]
    if not (cfg.GracePeriod and cfg.OuterLate > 0 and hit) then return end
    if hit.refunded or hit.applied > 0 or not rules.moveFits(kind, hit) then return end
    local late = t - hit.t
    if late < 0 or late > cfg.OuterLate then return end
    hit.refunded = true
    local stats = hit.stats
    if not valid(stats) or hero["Dead?"] == true then return end
    local cur = stats.CurrentHP
    if cur <= 0 then return end -- cannot undo a hit that killed the character
    local lost = math.min(hit.hpBefore - cur, hit.full)
    local red = rules.reductionAt(late / cfg.OuterLate)
    local refund = math.floor(lost * red + 0.5)
    if refund <= 0 then return end
    stats:SetHP(cur + refund)
    state.ui.lateUntil = 0
    core.showMessage(string.format("LATE GRAZE  -%d%%", pct(red)), hero, cfg.ColorLate)
    dbg(string.format("late graze: %s pressed %.3fs after the hit -> %d HP handed back", kind, late, refund))
  end
end

return M
