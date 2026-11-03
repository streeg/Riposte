-- Riposte offline simulation: runs the real mod scripts against a fake UE4SS /
-- game API and plays one enemy attack through every hook. Catches runtime
-- errors, undefined globals and broken module wiring without the game.
-- Run with: python tools/test/run.py

local SCRIPTS, OUTDIR = ...
package.path = SCRIPTS .. "/?.lua;" .. package.path

-------------------------------------------------------------------------------
-- fake engine
-------------------------------------------------------------------------------

local TIME, NOW = 100.0, 1000      -- game clock, os.time()
os.time = function() return NOW end
local LOGS, HOOKS, LOOPS, KEYS = {}, {}, {}, {}
local nextAddr = 0x1000

-- auto-vivifying stub: any field is another stub, any call returns a stub
local function stub(name)
  local t = {}
  return setmetatable(t, {
    __index = function(self, k)
      if k == "IsValid" then return function() return true end end
      if k == "IsInViewport" then return function() return true end end
      if k == "GetAddress" then return function() return 0xBEEF end end
      local child = stub(name .. "." .. tostring(k))
      rawset(self, k, child)
      return child
    end,
    __call = function() return stub(name .. "()") end,
  })
end

local function obj(fields)
  nextAddr = nextAddr + 0x10
  local addr = nextAddr
  local o = fields or {}
  o.IsValid = function() return true end
  o.GetAddress = function() return addr end
  o.GetClass = o.GetClass or function()
    return { GetFName = function() return { ToString = function() return "FakeClass" end } end }
  end
  return o
end

local function param(v) return { get = function() return v end } end
local function array(list)
  return {
    ForEach = function(_, cb) for i, v in ipairs(list) do if cb(i, param(v)) then break end end end,
    GetArrayNum = function() return #list end,
  }
end

local KSL = obj({ GetGameTimeInSeconds = function() return TIME end })

print = function(s) LOGS[#LOGS + 1] = s end
StaticFindObject = function(path)
  if path:find("KismetSystemLibrary") then return KSL end
  if path:find("^/Script/UMG") then return stub(path) end
  return obj({}) -- every hooked UFunction "exists"
end
StaticConstructObject = function(cls) return stub("widget") end
FindAllOf = function() return nil end
RegisterHook = function(path, cb) HOOKS[path:match(":(.+)$")] = cb end
LoopInGameThreadWithDelay = function(ms, fn) LOOPS[ms] = fn end
LoopAsync, ExecuteInGameThread = function() end, function(f) f() end
RegisterKeyBind = function(key, mods, fn) KEYS[#KEYS + 1] = fn or mods end
Key, ModifierKey = { F8 = 119 }, { CONTROL = 1 }
FText = function(s) return s end
package.preload["UEHelpers"] = function() return { GetGameInstance = function() return obj({}) end } end

-- the config is read from src, but files are written to OUTDIR
package.preload["riposte_config"] = function()
  local cfg = dofile(SCRIPTS .. "/riposte_config.lua")
  cfg.Debug = true
  return cfg
end

-- strict globals from here on: a typo in the mod becomes an error
setmetatable(_G, {
  __newindex = function(_, k) error("mod assigned global '" .. tostring(k) .. "'", 2) end,
  __index = function(_, k) error("mod read undefined global '" .. tostring(k) .. "'", 2) end,
})

-------------------------------------------------------------------------------
-- load the mod
-------------------------------------------------------------------------------

local core = require("rp_core")
core.scriptDir = OUTDIR .. "/"
dofile(SCRIPTS .. "/main.lua")
LOOPS[3000]() -- attach hooks

local function tick(n, dt)
  for _ = 1, n do TIME = TIME + (dt or 0.01); LOOPS[10]() end
end
local function check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end end

-------------------------------------------------------------------------------
-- one enemy attack
-------------------------------------------------------------------------------

tick(100) -- idle: nothing should happen
check(not core.inBattle(), "idle before battle")

local heroStats
local hero = obj({
  ["Enemy?"] = false, ["Dead?"] = false,
  DefensiveMoveImmunityEndTime = 0,
  JumpImmuneDuration = 0.65, GradientParryImmuneDuration = 0.15,
  GetDodgeImmuneDuration = function() return 0.22 end,
  GetParryImmuneDuration = function() return 0.15 end,
})
heroStats = obj({ CurrentHP = 200, GetOwner = function() return hero end,
  SetHP = function(self, v) self.CurrentHP = v end })
local enemyStats = obj({ IsCurrentAttackJumpable = false, IsCurrentAttackGradient = false,
  IsCurrentAttackUnblockable = false, IsCurrentAttackUndodgeable = false })
local enemy = obj({ ["Enemy?"] = true, AC_jRPG_CharacterStats = enemyStats,
  BattleManagerReference = { PlayerCharacters = array({ hero }) } })
enemyStats.GetOwner = function() return enemy end
local seq = obj({ IsFinished = false, TargetCharacters = array({ hero }),
  LevelSequence = { GetFName = function() return { ToString = function() return "SEQ_Test_Attack" end } end } })

for _, name in ipairs({ "OnBattleSequenceStarts", "ReceiveDamageFromObject", "ApplyDebugOverrides",
  "TryStartDodge", "TryStartParry", "TryStartJump", "TryStartGradientParry", "DeclareBattleSequenceTimingsAsList" }) do
  check(HOOKS[name], "hook registered: " .. name)
end

-- run 1: learn the timing (hit lands 1.5 s in, pressed 0.1 s too early -> early graze)
HOOKS.OnBattleSequenceStarts(param(enemy), param(seq))
check(core.state.attack and core.state.attack.name == "SEQ_Test_Attack", "attack tracked")
check(core.state.attack.target == hero, "target read from TargetCharacters")
tick(110)                                           -- t0 + 1.10
hero.DefensiveMoveImmunityEndTime = TIME + 0.22
HOOKS.TryStartDodge(param(hero), param(true))       -- immune until t0 + 1.32
tick(40)                                            -- t0 + 1.50: hit lands 0.18 s after immunity
local dmg = obj({ DamageReason = 1, TargetCharacter = heroStats, SourceCharacter = enemyStats,
  CurrentInputDamages_Base = 100 })
HOOKS.ApplyDebugOverrides(param(dmg))
check(dmg.CurrentInputDamages_Base < 100 and dmg.CurrentInputDamages_Base > 0, "early graze reduced damage: " .. dmg.CurrentInputDamages_Base)
HOOKS.ReceiveDamageFromObject(param(heroStats))
tick(20)
seq.IsFinished = true
tick(1)
check(core.state.attack == nil, "attack committed when finished")

-- run 2: the learned ring must be on screen before the hit
seq.IsFinished = false
HOOKS.OnBattleSequenceStarts(param(enemy), param(seq))
tick(50)
check(core.state.ui.nextHit ~= nil, "learned ring drawn on the second run")
local predicted = core.state.ui.nextHit.at - core.state.attack.t0
check(math.abs(predicted - 1.50) < 0.03, string.format("prediction %.3f ~ 1.50", predicted))

-- late graze: full hit, then press 0.05 s later -> HP refund
tick(100)
local dmg2 = obj({ DamageReason = 1, TargetCharacter = heroStats, SourceCharacter = enemyStats,
  CurrentInputDamages_Base = 50 })
HOOKS.ApplyDebugOverrides(param(dmg2))
heroStats.CurrentHP = heroStats.CurrentHP - 50
HOOKS.ReceiveDamageFromObject(param(heroStats))
local before = heroStats.CurrentHP
tick(5)
hero.DefensiveMoveImmunityEndTime = TIME + 0.15
HOOKS.TryStartParry(param(hero), param(true))
check(heroStats.CurrentHP > before, "late graze refunded HP")

-- forget hotkey, then battle ends: learned file is written only when idle
KEYS[1]()
seq.IsFinished = true
tick(5)
NOW = NOW + 60
tick(200) -- message + overlay fade out, then the idle path writes the file

local f = io.open(OUTDIR .. "/riposte_learned.txt", "r")
local learnedText = f and f:read("a") or ""
if f then f:close() end

for _, line in ipairs(LOGS) do
  check(not line:find("error in "), "no runtime errors, got: " .. line)
end
check(learnedText:find("SEQ_Test_Attack|1.5", 1, true), "learned file written after the battle: " .. learnedText)

print("SIM OK")
return table.concat(LOGS, "\n"), learnedText
