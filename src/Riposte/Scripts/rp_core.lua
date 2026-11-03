-- Riposte core: config, logging, shared state and small game helpers.
-- Every other module requires this one; it requires nothing of Riposte.

local M = {}

M.VERSION = "1.0.0"
M.cfg = require("riposte_config")
local cfg = M.cfg

-------------------------------------------------------------------------------
-- logging
-------------------------------------------------------------------------------

local TAG = "[Riposte] "
function M.log(msg) print(TAG .. msg .. "\n") end
function M.dbg(msg) if cfg.Debug then M.log(msg) end end

-- Errors from code that runs up to 100x a second: each distinct message is
-- written at most once per 10 s, and no more than 20 error lines per minute
-- overall, so a broken game patch cannot flood UE4SS.log.
local errSeen, errWindow, errCount, errMuted = {}, 0, 0, false
function M.logError(where, err)
  local msg = "error in " .. where .. ": " .. tostring(err)
  local now = os.time()
  local e = errSeen[msg]
  if e and now - e.last < 10 then e.suppressed = e.suppressed + 1; return end
  if now - errWindow >= 60 then errWindow, errCount, errMuted = now, 0, false end
  errCount = errCount + 1
  if errCount > 20 then
    if not errMuted then
      errMuted = true
      M.log("too many errors, muting error output for up to a minute (the mod may be outdated for this game version)")
    end
    return
  end
  local extra = (e and e.suppressed > 0) and string.format(" (repeated %dx since last report)", e.suppressed) or ""
  errSeen[msg] = { last = now, suppressed = 0 }
  M.log(msg .. extra)
end

-------------------------------------------------------------------------------
-- game facts
-------------------------------------------------------------------------------

M.PATH = {
  CHAR = "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Character_Battle_Base.BP_jRPG_Character_Battle_Base_C:",
  DAMAGES = "/Game/Gameplay/Battle/BP_BattleDamages.BP_BattleDamages_C:",
  TIMELINE = "/Game/Gameplay/Battle/SkillCombos/BP_BattleSequenceTimeline.BP_BattleSequenceTimeline_C:",
  STATS = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_CharacterBattleStats.AC_jRPG_CharacterBattleStats_C:",
}

M.ACTION_EFFECT = 4  -- EBattleActionEvent::ActionEffect
M.REASON_BUFF = 2    -- EDamageReason::BuffEffect (never defendable)
M.REASON_LUMINA = 6  -- EDamageReason::Lumina     (never defendable)

function M.valid(obj)
  return obj ~= nil and obj.IsValid ~= nil and obj:IsValid()
end
local valid = M.valid

local KSL = nil
function M.gameTime(ctx)
  if not valid(KSL) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
  return KSL:GetGameTimeInSeconds(ctx)
end

function M.isEnemy(char) return char["Enemy?"] == true end

-- Folder of this script, for the files the mod writes next to itself.
M.scriptDir = (debug.getinfo(1, "S").source or ""):match("^@?(.*[/\\])") or "ue4ss/Mods/Riposte/Scripts/"

-------------------------------------------------------------------------------
-- battle activity: any battle hook refreshes it; outside a battle the mod
-- does no per-frame work at all
-------------------------------------------------------------------------------

local BATTLE_IDLE_SECONDS = 20
local battleUntil = 0
function M.markBattle() battleUntil = os.time() + BATTLE_IDLE_SECONDS end
function M.inBattle() return os.time() < battleUntil end

-------------------------------------------------------------------------------
-- shared state
-------------------------------------------------------------------------------

M.state = {
  tick = 0,            -- overlay ticks (game time restarts on a level load)
  attack = nil,        -- running enemy sequence, see rp_learning
  lastAttackName = nil,
  lastPresser = nil,   -- hero that pressed a defensive move most recently
  lastMove = {},       -- hero address -> { kind, t, endt }
  lastHit = {},        -- hero address -> { t, full, hpBefore, stats, flags..., applied, refunded }
  ui = {
    ctx = nil,         -- any live battle object, used as world context
    msg = nil, msgColor = nil, msgTime = 0, msgUntil = 0,
    lateUntil = 0,     -- a full hit landed; a late press can graze until then
    nextHit = nil,     -- { at, color } predicted moment of the lead ring
    flash = nil,       -- { t0, color } impact burst
  },
}

-- A level was loaded: the game clock restarted, timed state is meaningless.
function M.resetTimedState()
  local s, ui = M.state, M.state.ui
  ui.msgUntil, ui.lateUntil, ui.nextHit, ui.flash = 0, 0, nil, nil
  s.lastMove, s.lastHit = {}, {}
  s.attack = nil
end

local MSG_TIME = 1.2
function M.showMessage(text, ctx, color)
  if not cfg.ShowGrazeText or not valid(ctx) then return end
  local ui = M.state.ui
  ui.msg, ui.msgColor, ui.msgTime = text, color, MSG_TIME
  ui.msgUntil = M.gameTime(ctx) + MSG_TIME
end

-------------------------------------------------------------------------------
-- optional research recorder (tools/research, dev only); nil = zero cost
-------------------------------------------------------------------------------

M.research = nil

function M.loadResearch()
  if not cfg.Research then return end
  local ok, mod = pcall(require, "riposte_research")
  if not ok or type(mod) ~= "table" then
    M.log("research module failed to load: " .. tostring(mod))
    return
  end
  M.research = mod
  pcall(mod.init, M.scriptDir, M.log, M.gameTime, function() return M.state.attack end)
  M.log("research mode on: recording to " .. M.scriptDir .. "riposte_research.txt")
end

-- Call a research function, guarded. Callers check `core.research` first so
-- nothing is evaluated when research is off.
function M.rs(fnName, ...)
  local ok, err = pcall(M.research[fnName], ...)
  if not ok then M.logError("research." .. fnName, err) end
end

return M
