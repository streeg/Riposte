-- Riposte rules: what kind of hit this is, which move counts against it, how
-- much a near miss reduces, and how long the defending hero's windows are.

local core = require("rp_core")
local cfg, valid = core.cfg, core.valid

local M = {}

-- Flags live on the ATTACKER's stats component. They switch to a hit's kind
-- only when that hit lands, so before it they still describe the previous hit.
function M.attackFlags(sourceStats)
  return {
    jumpable = sourceStats.IsCurrentAttackJumpable == true,
    gradient = sourceStats.IsCurrentAttackGradient == true,
    unblockable = sourceStats.IsCurrentAttackUnblockable == true,
    undodgeable = sourceStats.IsCurrentAttackUndodgeable == true,
  }
end

-- One letter per learned hit: j(ump) g(radient) u(nblockable) d (undodgeable) n(ormal).
function M.flagsCode(f)
  if f.jumpable then return "j" end
  if f.gradient then return "g" end
  if f.unblockable then return "u" end
  if f.undodgeable then return "d" end
  return "n"
end

function M.codeFlags(c)
  return { jumpable = c == "j", gradient = c == "g", unblockable = c == "u", undodgeable = c == "d" }
end

-- Does a move of this kind count against an attack with these flags?
-- A jump only counts against jump attacks and a gradient parry only against
-- gradient attacks, as in vanilla.
function M.moveFits(kind, atk)
  if atk.jumpable then return kind == "jump" and cfg.GrazeJump end
  if atk.gradient then return kind == "gradient" and cfg.GrazeGradient end
  if kind == "dodge" then return cfg.GrazeDodge and not atk.undodgeable end
  if kind == "parry" then return cfg.GrazeParry and not atk.unblockable end
  return false
end

-- t01 = how far into the grace window (0 = edge of the vanilla window, 1 = far edge)
function M.reductionAt(t01)
  if t01 < 0 then t01 = 0 elseif t01 > 1 then t01 = 1 end
  return cfg.MaxReduction - (cfg.MaxReduction - cfg.MinReduction) * t01
end

-------------------------------------------------------------------------------
-- window lengths of the defending hero, cached briefly per hero
-------------------------------------------------------------------------------

local DEFAULT_WINDOWS = { dodge = 0.22, parry = 0.15, jump = 0.65, gradient = 0.15 }
local windowsCache = {}

local function readWindows(hero)
  local function num(x, d) return (type(x) == "number" and x > 0) and x or d end
  return {
    dodge = num(hero:GetDodgeImmuneDuration(), DEFAULT_WINDOWS.dodge),
    parry = num(hero:GetParryImmuneDuration(), DEFAULT_WINDOWS.parry),
    jump = num(hero.JumpImmuneDuration, DEFAULT_WINDOWS.jump),
    gradient = num(hero.GradientParryImmuneDuration, DEFAULT_WINDOWS.gradient),
  }
end

-- target: the hero the attack aims at (may be nil; then the first living
-- party member of the attacker's battle is used).
function M.heroWindows(attacker, target)
  local key = valid(target) and target:GetAddress() or 0
  local tick = core.state.tick
  local c = windowsCache[key]
  if c and tick - c.at < 50 then return c.value end
  local value = nil
  if key ~= 0 and target["Dead?"] ~= true then
    local ok, v = pcall(readWindows, target)
    if ok then value = v end
  end
  if not value then
    pcall(function()
      attacker.BattleManagerReference.PlayerCharacters:ForEach(function(_, elem)
        local hero = elem:get()
        if valid(hero) and hero["Dead?"] ~= true then
          local ok, v = pcall(readWindows, hero)
          if ok then value = v; return true end
        end
      end)
    end)
  end
  value = value or DEFAULT_WINDOWS
  windowsCache[key] = { at = tick, value = value }
  return value
end

function M.resetCache() windowsCache = {} end

return M
