-- Riposte learned timings: the main timing source. For every enemy attack
-- (a BP_EpicBattleSequenceActor) Riposte records when its hits really reach a
-- hero and replays those times the next time the same attack plays. Research
-- over 25 runs of 6 enemies: replay error <= 15 ms. Learned times also beat
-- declared ones (a ranged attack's declared keyframe is the launch, and some
-- declared effects never hit).

local core = require("rp_core")
local rules = require("rp_rules")
local timelines = require("rp_timelines")
local cfg, valid, isEnemy, log, dbg = core.cfg, core.valid, core.isEnemy, core.log, core.dbg
local state = core.state

local M = {}

local learned = {}  -- sequence name -> { offsets..., kinds = { code, ... } }
local pending = {}  -- sequence name -> a run whose hit count disagreed (not saved)
local dirty = false -- written to disk when the battle is over, never mid-fight
local FILE = core.scriptDir .. "riposte_learned.txt"

-------------------------------------------------------------------------------
-- file: one attack per line, "SEQ_Name|2.586j,3.799n"
-------------------------------------------------------------------------------

function M.load()
  local f = io.open(FILE, "r")
  if not f then return end
  local n = 0
  for line in f:lines() do
    local name, list = line:match("^(.-)|(.*)$")
    if name and name ~= "" then
      local offs = { kinds = {} }
      for item in list:gmatch("[^,]+") do
        local num, code = item:match("^%s*([%d.]+)(%a?)")
        if tonumber(num) then
          offs[#offs + 1] = tonumber(num)
          offs.kinds[#offs] = code ~= "" and code or nil
        end
      end
      if #offs > 0 then learned[name] = offs; n = n + 1 end
    end
  end
  f:close()
  log("learned timings loaded for " .. n .. " attack(s)")
end

local function save()
  local f = io.open(FILE, "w")
  if not f then
    log("could not write " .. FILE)
    return
  end
  local names = {}
  for name in pairs(learned) do names[#names + 1] = name end
  table.sort(names) -- stable file, easy to diff and share
  for _, name in ipairs(names) do
    local offs, parts = learned[name], {}
    for i, o in ipairs(offs) do parts[i] = string.format("%.3f", o) .. (offs.kinds and offs.kinds[i] or "") end
    f:write(name, "|", table.concat(parts, ","), "\n")
  end
  f:close()
end

function M.flushIfDirty()
  if dirty then
    dirty = false
    pcall(save)
  end
end

-------------------------------------------------------------------------------
-- attack lifecycle
-------------------------------------------------------------------------------

-- Store what was observed during the attack that just ended.
local function commit()
  local a = state.attack
  state.attack = nil
  if core.research and a then core.rs("onCommit", a, learned[a.name]) end
  if not a or #a.observed == 0 then return end
  local prev = learned[a.name]
  local function averageWith(other)
    for i, o in ipairs(a.observed) do
      a.observed[i] = (o + other[i]) / 2
      a.observed.kinds[i] = a.observed.kinds[i] or (other.kinds and other.kinds[i])
    end
  end
  if prev and #prev == #a.observed then
    averageWith(prev)
    pending[a.name] = nil
  elseif prev then
    -- A different hit count is either a bad run (cut short, stray damage) or a
    -- bad first recording. One run proves nothing; two in a row with the same
    -- new count replace the stored timing, so a wrong recording can heal.
    local p = pending[a.name]
    if p and #p == #a.observed then
      averageWith(p)
      pending[a.name] = nil
      dbg(string.format("%s: %d hit(s) seen twice in a row instead of %d, relearned", a.name, #a.observed, #prev))
    else
      pending[a.name] = a.observed
      dbg(string.format("%s ran with %d hit(s) instead of %d; kept the stored timing until the next run agrees",
        a.name, #a.observed, #prev))
      return
    end
  end
  learned[a.name] = a.observed
  if cfg.Debug then
    local parts = {}
    for i, o in ipairs(a.observed) do parts[i] = string.format("%.2f", o) .. (a.observed.kinds[i] or "") end
    dbg("learned " .. a.name .. ": hits at " .. table.concat(parts, ", ") .. (a.declared and " (also declared)" or ""))
  end
  dirty = true
end
M.commit = commit

-- Post hook on BP_jRPG_Character_Battle_Base_C:OnBattleSequenceStarts.
function M.onSequenceStarts(Context, BattleSequence)
  local char, seq = Context:get(), BattleSequence:get()
  commit()
  core.markBattle()
  timelines.requestPoll() -- the attack's timeline may be new: find it right away
  if not valid(char) or not valid(seq) or not isEnemy(char) then return end
  local name = "?"
  pcall(function() name = seq.LevelSequence:GetFName():ToString() end)
  local a = { actor = seq, attacker = char, name = name, t0 = core.gameTime(char), observed = { kinds = {} }, declared = false }
  -- the sequence actor names its targets: the circle shows their windows
  pcall(function()
    seq.TargetCharacters:ForEach(function(_, e)
      local h = e:get()
      if valid(h) and not isEnemy(h) then a.target = h; return true end
    end)
  end)
  state.attack, state.lastAttackName = a, name
  if core.research then core.rs("onSequenceStart", seq, name, char) end
  dbg("enemy sequence " .. name .. (learned[name] and " (timing known)" or " (timing not known yet)"))
end

-- Post hook on AC_jRPG_CharacterBattleStats_C:ReceiveDamageFromObject: a hit
-- reached a character, dodged or not.
function M.onHitArrives(Context, ...)
  local a = state.attack
  if not a then return end
  local stats = Context:get()
  if not valid(stats) then return end
  local hero = stats:GetOwner()
  if not valid(hero) or isEnemy(hero) then return end
  core.markBattle()
  if not valid(a.target) then a.target = hero end
  local off = core.gameTime(hero) - a.t0
  if off < 0 or off > 60 then return end
  local last = a.observed[#a.observed]
  if last and off - last < 0.05 then return end -- same hit on another party member
  a.observed[#a.observed + 1] = off
  local code = "?"
  pcall(function() code = rules.flagsCode(rules.attackFlags(a.attacker.AC_jRPG_CharacterStats)) end)
  if code ~= "?" then a.observed.kinds[#a.observed] = code end
  if core.research then
    local params = {}
    for i, p in ipairs({ ... }) do
      local okP, v = pcall(function() return p:get() end)
      params[i] = okP and core.research.scalar(v) or "?"
    end
    local heroName = "?"
    pcall(function() heroName = hero:GetClass():GetFName():ToString() end)
    core.rs("onHit", a, off, code, learned[a.name], heroName, params)
  end
  dbg(string.format("hit arrives %.3fs into %s (kind %s)", off, a.name, code))
end

-- Called every battle tick while an enemy attack runs. Replaces the declared
-- hits of the attacker with learned ones when known. Returns true while an
-- attack with no timing at all is being learned.
function M.update(hits, counts)
  local a = state.attack
  if not a then return false end
  core.markBattle()
  local learning = false
  local ok = pcall(function()
    if not valid(a.actor) or not valid(a.attacker) or a.actor.IsFinished == true then
      commit()
      return
    end
    if counts.running then a.declared = true end
    local elapsed = core.gameTime(a.attacker) - a.t0
    if core.research then
      local own, me = {}, a.attacker:GetAddress()
      for _, h in ipairs(hits) do
        if valid(h.attacker) and h.attacker:GetAddress() == me then own[#own + 1] = h end
      end
      local code = nil
      pcall(function() code = rules.flagsCode(rules.attackFlags(a.attacker.AC_jRPG_CharacterStats)) end)
      core.rs("onTick", a, elapsed, own, code)
    end
    local offs = learned[a.name]
    if offs then
      for i = #hits, 1, -1 do hits[i] = nil end
      for i, o in ipairs(offs) do
        hits[#hits + 1] = { remaining = o - elapsed, attacker = a.attacker, kind = offs.kinds and offs.kinds[i] }
      end
    elseif not a.declared then
      learning = elapsed < 30
      if learning then state.ui.ctx = a.attacker end
    end
  end)
  if not ok then state.attack = nil end
  return learning
end

-- Hotkey: forget the learned timing of the running (or last) enemy attack.
-- What the running attack has observed so far becomes the new recording.
function M.forget()
  local a = state.attack
  local name = (a and a.name) or state.lastAttackName
  if not name then
    log("forget: no enemy attack seen yet")
    return
  end
  local had = learned[name] ~= nil
  learned[name], pending[name] = nil, nil
  pcall(save)
  dirty = false
  log("forget: timing of " .. name .. (had and " forgotten, will be re-learned" or " was not stored"))
  core.markBattle()
  core.showMessage("TIMING RESET", state.ui.ctx, { 1, 1, 1 })
end

return M
