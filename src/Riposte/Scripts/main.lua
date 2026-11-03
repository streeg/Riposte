-- Riposte - UE4SS Lua mod for Clair Obscur: Expedition 33 (UE 5.4)
-- https://github.com/streeg/Riposte  -  MIT License
--
-- A timing circle for every enemy hit, and a grace period that turns
-- near-miss dodges, parries, jumps and gradient parries into reduced damage.
--
-- Kudos: built on Graded Defense 1.0 by jjmmaaxx
-- (https://www.nexusmods.com/clairobscurexpedition33/mods/951), used under its
-- Nexus permissions (modify and redistribute with credit).
--
-- Modules (all in this folder):
--   rp_core       config, logging, shared state, game helpers, battle activity
--   rp_rules      hit kinds, which move counts, reduction curve, hero windows
--   rp_learning   attack lifecycle + learned hit times (main timing source)
--   rp_timelines  hit times declared by the attack itself (first guess)
--   rp_defense    the grace period (early reduction, late HP refund)
--   rp_tick       per-frame loop: gathers hits, builds the frame to draw
--   rp_overlay    drawing only
--   rp_hooks      Blueprint hooks, timers, hotkey
--
-- Game-side facts this relies on (decompiled from the Blueprint bytecode and
-- confirmed in-game with the research recorder in tools/research):
--   * BP_jRPG_Character_Battle_Base_C:TryStartDodge/Parry/Jump/GradientParry
--     (out Success) call StartDefensiveMove, which sets
--     DefensiveMoveImmunityStartTime / EndTime on the game-time clock.
--   * AC_jRPG_CharacterBattleStats_C:ReceiveDamageFromObject cancels the hit if
--     the matching move is still active; otherwise it runs the BP_BattleDamages
--     pipeline, whose last steps are ApplyDebugOverrides ->
--     ApplyTargetClampAndRounding -> Finish -> ReduceHP(GetFinalDamages).
--   * Attack flags live on the ATTACKER's stats component and switch to a
--     hit's kind only when that hit lands.
--   * Every attack is a BP_EpicBattleSequenceActor; when it starts it calls
--     OnBattleSequenceStarts(self) on the attacker and lists TargetCharacters.
--   * UE4SS Lua hooks on Blueprint functions run after the function body.

local core = require("rp_core")
core.loadResearch()

local cfg, P = core.cfg, core.PATH
local hooks = require("rp_hooks")
local learning = require("rp_learning")
local timelines = require("rp_timelines")
local defense = require("rp_defense")
local tick = require("rp_tick")

-- the battle Blueprints load after the mod does; rp_hooks attaches when they exist
hooks.add(P.DAMAGES .. "ApplyDebugOverrides", defense.onDamageAboutToApply)
hooks.add(P.CHAR .. "TryStartDodge", defense.makePressHook("dodge"))
hooks.add(P.CHAR .. "TryStartParry", defense.makePressHook("parry"))
hooks.add(P.CHAR .. "TryStartJump", defense.makePressHook("jump"))
hooks.add(P.CHAR .. "TryStartGradientParry", defense.makePressHook("gradient"))
hooks.add(P.TIMELINE .. "DeclareBattleSequenceTimingsAsList", timelines.onDeclared)
hooks.add(P.CHAR .. "OnBattleSequenceStarts", learning.onSequenceStarts)
hooks.add(P.STATS .. "ReceiveDamageFromObject", learning.onHitArrives)

pcall(learning.load)
hooks.key(cfg.ForgetKey, cfg.ForgetKeyCtrl, "forget key", learning.forget)
hooks.everyMs(3000, "hooks", hooks.ensure)
hooks.everyMs(10, "tick", tick.tick)

core.log(string.format("v%s loaded (grace period %s, early %.2fs, late %.2fs, max -%d%%; visualizer %s, visual offset %.3fs; debug %s)",
  core.VERSION, tostring(cfg.GracePeriod), cfg.OuterEarly, cfg.OuterLate,
  math.floor(cfg.MaxReduction * 100 + 0.5), tostring(cfg.Visualizer), cfg.VisualOffset or 0, tostring(cfg.Debug)))
