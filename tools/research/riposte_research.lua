-- Riposte research module (dev only, not shipped). Loaded when riposte_config.Research = true.
--
-- Goal: find where each enemy attack keeps its real hit times, so the timing
-- circle can be exact on the first encounter instead of learning by observing.
-- Writes riposte_research.txt next to this file:
--   === SEQUENCE <name>   once per attack: reflective dump of the battle
--                         sequence actor, its LevelSequence / MovieScene
--                         (tracks, sections, event keys, animation notifies)
--   --- RUN <name>        every time an attack plays: declared hit times,
--                         attack-kind flag changes, presses, hit arrivals with
--                         the prediction error, damage that went through
--   === SIGNATURE / ENUM / OBJECT   one-off facts about game functions/types
-- Everything is buffered and appended to disk only while out of battle.

local R = {}

local path = nil
local log = function() end
local buf = {}
local seen = {}           -- section headers already in the file (dump once ever)
local MAX_DEPTH = 10
local MAX_ARRAY = 60
local MAX_LINES_PER_DUMP = 6000

local function w(s) buf[#buf + 1] = s end

local gameTime = nil   -- function(ctx) -> seconds, from main
local getAttack = nil  -- function() -> running attack table, from main

function R.init(scriptDir, logger, gameTimeFn, getAttackFn)
  path = scriptDir .. "riposte_research.txt"
  log = logger or log
  gameTime, getAttack = gameTimeFn, getAttackFn
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      local key = line:match("^=== (%u+ %S+)")
      if key then seen[key] = true end
    end
    f:close()
  end
end

function R.flush()
  if #buf == 0 or not path then return end
  local f = io.open(path, "a")
  if not f then return end
  f:write(table.concat(buf, "\n"), "\n")
  f:close()
  buf = {}
end

local function once(key)
  if seen[key] then return false end
  seen[key] = true
  return true
end

-------------------------------------------------------------------------------
-- reflection helpers (every step guarded: unknown property types just print ?)
-------------------------------------------------------------------------------

local function valid(o) return o ~= nil and o.IsValid ~= nil and o:IsValid() end

local function pname(p)
  local ok, n = pcall(function() return p:GetFName():ToString() end)
  return ok and n or "?"
end

local function ptype(p)
  local ok, n = pcall(function() return p:GetClass():GetFName():ToString() end)
  return ok and n or "?"
end

local function objName(o)
  local ok, s = pcall(function() return o:GetFullName() end)
  if ok and type(s) == "string" then return s end
  return "?"
end

local function className(o)
  local ok, s = pcall(function() return o:GetClass():GetFName():ToString() end)
  return ok and s or "?"
end

local function scalar(v)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.4f", v)
  end
  if t == "boolean" or t == "string" or t == "nil" then return tostring(v) end
  local ok, s = pcall(function() return v:ToString() end)
  if ok and type(s) == "string" then return '"' .. s .. '"' end
  if valid(v) then return objName(v) end
  return "<" .. t .. ">"
end

-- Objects worth opening when referenced: Sequencer data and animation data.
local function shouldFollow(o)
  local c = className(o)
  return c:find("MovieScene") ~= nil or c:find("^Anim") ~= nil or c:find("^AN_") ~= nil
    or c:find("^ANS_") ~= nil or c:find("AnimNotify") ~= nil or c:find("Section") ~= nil
    or c:find("Track") ~= nil or c:find("Channel") ~= nil
end

-- Field names that are big and never about timing.
local SKIP = {
  BoneCompressionSettings = true, CurveCompressionSettings = true, CompressedData = true,
  RawCurveData = true, Skeleton = true, AssetUserData = true, BoneTree = true,
  RetargetSource = true, AnimationTrackNames = true, TrackToSkeletonMapTable = true,
  ThumbnailInfo = true, ParentAsset = true, AssetMappingTable = true,
}

local lines, visited

local dumpValue

local function dumpStruct(container, struct, indent, depth, ownOnly)
  local s = struct
  while valid(s) do
    local props = {}
    pcall(function() s:ForEachProperty(function(p) props[#props + 1] = p end) end)
    for _, p in ipairs(props) do
      local n = pname(p)
      if not SKIP[n] then
        local ok, v = pcall(function() return container[n] end)
        if ok then dumpValue(n, p, v, indent, depth) else w(indent .. n .. " = ?") end
      end
      if lines > MAX_LINES_PER_DUMP then return end
    end
    if ownOnly then return end
    local ok, sup = pcall(function() return s:GetSuperStruct() end)
    s = ok and sup or nil
    if valid(s) then
      local sn = pname(s)
      if sn == "Object" or sn == "Actor" or sn == "ActorComponent" then return end
    end
  end
end

local function dumpObject(o, indent, depth, ownOnly)
  if not valid(o) then return end
  local key = o:GetAddress()
  if visited[key] then w(indent .. "(already shown above)"); return end
  visited[key] = true
  local ok, cls = pcall(function() return o:GetClass() end)
  if ok and valid(cls) then dumpStruct(o, cls, indent, depth, ownOnly) end
end

dumpValue = function(n, p, v, indent, depth)
  lines = lines + 1
  if lines > MAX_LINES_PER_DUMP then
    if lines == MAX_LINES_PER_DUMP + 1 then w(indent .. "... (dump truncated)") end
    return
  end
  local t = ptype(p)
  if depth > MAX_DEPTH then w(indent .. n .. " (" .. t .. ") ..."); return end
  if t == "StructProperty" then
    local ok, st = pcall(function() return p:GetStruct() end)
    w(indent .. n .. " {" .. (ok and pname(st) or "?") .. "}")
    if ok and valid(st) then dumpStruct(v, st, indent .. "  ", depth + 1, false) end
  elseif t == "ArrayProperty" then
    local count = 0
    pcall(function() count = v:GetArrayNum() end)
    w(indent .. n .. " [" .. count .. "]")
    if count > 0 then
      local okI, inner = pcall(function() return p:GetInner() end)
      if okI then
        pcall(function()
          v:ForEach(function(i, elem)
            if i > MAX_ARRAY then w(indent .. "  ... " .. (count - MAX_ARRAY) .. " more"); return true end
            local okE, ev = pcall(function() return elem:get() end)
            if okE then dumpValue("[" .. i .. "]", inner, ev, indent .. "  ", depth + 1) end
          end)
        end)
      end
    end
  elseif t == "ObjectProperty" or t == "WeakObjectProperty" then
    if valid(v) then
      w(indent .. n .. " = " .. objName(v))
      if shouldFollow(v) then dumpObject(v, indent .. "  ", depth + 1, false) end
    else
      w(indent .. n .. " = None")
    end
  elseif t == "ClassProperty" then
    w(indent .. n .. " = " .. (valid(v) and objName(v) or "None"))
  elseif t == "MapProperty" or t == "SetProperty" then
    local count = "?"
    pcall(function() local c = 0; v:ForEach(function() c = c + 1 end); count = c end)
    w(indent .. n .. " <" .. t .. ", " .. tostring(count) .. " entries>")
  else
    w(indent .. n .. " = " .. scalar(v))
  end
end

local function beginDump() lines, visited = 0, {} end

-------------------------------------------------------------------------------
-- one-off dumps
-------------------------------------------------------------------------------

-- Parameters of a hooked game function.
function R.signature(fnPath, fnObj)
  local short = fnPath:match("([^:]+)$") or fnPath
  if not once("SIGNATURE " .. short) then return end
  local parts = {}
  pcall(function()
    fnObj:ForEachProperty(function(p) parts[#parts + 1] = pname(p) .. ":" .. ptype(p) end)
  end)
  w("=== SIGNATURE " .. short .. "  (" .. table.concat(parts, ", ") .. ")")
end

-- Names of the battle enums (action events, damage reasons, ...).
function R.dumpEnums()
  pcall(function()
    for _, e in ipairs(FindAllOf("Enum") or {}) do
      local n = pname(e)
      if n:find("BattleAction") or n:find("DamageReason") or n:find("DefensiveMove")
        or n:find("AttackType") or n:find("BattleSequence") then
        if once("ENUM " .. n) then
          local names = {}
          pcall(function()
            e:ForEachName(function(name, value) names[#names + 1] = scalar(name) .. "=" .. tostring(value) end)
          end)
          w("=== ENUM " .. n .. "  " .. table.concat(names, ", "))
        end
      end
    end
  end)
end

-- Own-class fields of an object (shallow), once per label.
function R.dumpOnce(label, o)
  if not valid(o) or not once("OBJECT " .. label) then return end
  w("=== OBJECT " .. label .. "  " .. objName(o))
  beginDump()
  MAX_DEPTH = 2
  dumpObject(o, "  ", 0, true)
  MAX_DEPTH = 10
end

-------------------------------------------------------------------------------
-- round 2: impact timers, sequence-actor calls, montages
-------------------------------------------------------------------------------

local fmt = string.format
local KSL = nil
local function ksl()
  if not valid(KSL) then KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
  return KSL
end

local function classFunctions(cls)
  local names = {}
  pcall(function() cls:ForEachFunction(function(f) names[#names + 1] = pname(f) end) end)
  return names
end

local function findProp(obj, name)
  local found = nil
  pcall(function()
    local s = obj:GetClass()
    while valid(s) and not found do
      s:ForEachProperty(function(p) if pname(p) == name then found = p; return true end end)
      s = s:GetSuperStruct()
    end
  end)
  return found
end

local function elapsedOf(a)
  local ok, t = pcall(gameTime, a.attacker)
  return ok and (t - a.t0) or -1
end

-- Hook the battle sequence actor's own functions that sound like impact
-- scheduling, to log when they run during an enemy attack. The class is
-- shared by every attack and stays loaded, so this is done once.
local actorHooked = false
local HOOK_PATTERN = { "Impact", "ActionEffect", "Keyframe", "Timer", "Hit", "Damage", "Effect" }
local function hookSequenceActor(seq)
  if actorHooked then return end
  actorHooked = true
  local cls = seq:GetClass()
  local clsPath = objName(cls):match("^%S+ (.+)$")
  local fns = classFunctions(cls)
  if once("CLASSFUNCS " .. pname(cls)) then
    w("=== CLASSFUNCS " .. pname(cls) .. "  " .. table.concat(fns, ", "))
  end
  if not clsPath or not RegisterHook then return end
  for _, n in ipairs(fns) do
    local match = false
    for _, pat in ipairs(HOOK_PATTERN) do if n:find(pat) then match = true end end
    if match and not n:find("^ExecuteUbergraph") then
      local ok, err = pcall(RegisterHook, clsPath .. ":" .. n, function(ctx)
        pcall(function()
          local a = getAttack and getAttack()
          if not a or ctx:get():GetAddress() ~= a.actor:GetAddress() then return end
          w(fmt("  %7.3f  call %s", elapsedOf(a), n))
        end)
      end)
      if not ok then w("  (could not hook " .. n .. ": " .. tostring(err) .. ")") end
    end
  end
end

local function dumpMontage(m, mname)
  w(fmt("=== MONTAGE %s  %s", mname, objName(m)))
  beginDump()
  for _, field in ipairs({ "SequenceLength", "RateScale", "Notifies" }) do
    local p = findProp(m, field)
    if p then
      local ok, v = pcall(function() return m[field] end)
      if ok then dumpValue(field, p, v, "  ", 0) end
    end
  end
end

-- Watch the attack actor's impact timers and keyframe state, and the
-- attacker's montage, logging every change with the time into the attack.
local function watch(a, elapsed)
  local rs = a.rs
  local st = rs.st
  if not st then st = {}; rs.st = st end
  local seq = a.actor

  pcall(function()
    local cti = seq.currentTimerIndex
    if cti ~= st.cti then w(fmt("  %7.3f  currentTimerIndex -> %s", elapsed, tostring(cti))); st.cti = cti end
    local nk = seq.NextKeyframeTime
    if type(nk) == "number" and nk ~= st.nk then w(fmt("  %7.3f  NextKeyframeTime -> %.3f", elapsed, nk)); st.nk = nk end
    local c = 0
    seq.BattleSequenceKeyframes:ForEach(function() c = c + 1 end)
    if c ~= st.kf then w(fmt("  %7.3f  BattleSequenceKeyframes count -> %d", elapsed, c)); st.kf = c end
    local tm = 0
    seq.TimeMap:ForEach(function() tm = tm + 1 end)
    if tm ~= st.tm then w(fmt("  %7.3f  TimeMap count -> %d", elapsed, tm)); st.tm = tm end
  end)

  pcall(function()
    local k = ksl()
    local n = seq.impactTimers:GetArrayNum()
    if n ~= st.ntimers then w(fmt("  %7.3f  impactTimers count -> %d", elapsed, n)); st.ntimers = n end
    seq.impactTimers:ForEach(function(i, e)
      local h = e:get()
      local okA, active = pcall(function() return k:K2_IsTimerActiveHandle(seq, h) end)
      if not okA then
        if not st.timerErr then st.timerErr = true; w("  timer query failed: " .. tostring(active)) end
        return true
      end
      local key = "t" .. i
      local prev = st[key]
      if active then
        local rem = k:K2_GetTimerRemainingTimeHandle(seq, h)
        local fireAt = elapsed + rem
        if not prev or not prev.active or math.abs((prev.fireAt or -9) - fireAt) > 0.03 then
          w(fmt("  %7.3f  impactTimer[%d] ACTIVE: fires in %.3f -> at %.3f", elapsed, i, rem, fireAt))
        end
        st[key] = { active = true, fireAt = fireAt }
      else
        if prev and prev.active then w(fmt("  %7.3f  impactTimer[%d] fired/cleared", elapsed, i)) end
        st[key] = { active = false }
      end
    end)
  end)

  pcall(function()
    local ai = a.attacker.Mesh:GetAnimInstance()
    local m = ai:GetCurrentActiveMontage()
    local mname = valid(m) and pname(m) or nil
    if mname ~= st.montage then
      st.montage = mname
      w(fmt("  %7.3f  montage -> %s", elapsed, tostring(mname)))
      if mname and once("MONTAGE " .. mname) then dumpMontage(m, mname) end
    end
    st.ai, st.m = ai, m
  end)
end

-------------------------------------------------------------------------------
-- attack runs
-------------------------------------------------------------------------------

-- A new enemy sequence started. Full structure dump the first time ever.
local enumsDone = false
function R.onSequenceStart(seq, name, attacker)
  if not enumsDone then enumsDone = true; R.dumpEnums() end -- battle enums are loaded by now
  pcall(hookSequenceActor, seq)
  local attackerClass = className(attacker)
  if once("CLASSFUNCS " .. attackerClass) then
    local ok, cls = pcall(function() return attacker:GetClass() end)
    if ok then w("=== CLASSFUNCS " .. attackerClass .. "  " .. table.concat(classFunctions(cls), ", ")) end
  end
  w(string.format("--- RUN %s  (attacker %s)", name, className(attacker)))
  if not once("SEQUENCE " .. name) then return end
  local clock = os.clock()
  w("=== SEQUENCE " .. name .. "  actor " .. objName(seq))
  beginDump()
  w("  [battle sequence actor, own fields]")
  dumpObject(seq, "    ", 0, true)
  local ok, ls = pcall(function() return seq.LevelSequence end)
  if ok and valid(ls) then
    w("  [LevelSequence " .. objName(ls) .. "]")
    pcall(function()
      local dc = ls.DirectorClass
      if valid(dc) then
        local fns = {}
        dc:ForEachFunction(function(fn) fns[#fns + 1] = pname(fn) end)
        w("    DirectorClass " .. objName(dc) .. " functions: " .. table.concat(fns, ", "))
      end
    end)
    local okM, ms = pcall(function() return ls.MovieScene end)
    if okM and valid(ms) then
      w("  [MovieScene]")
      dumpObject(ms, "    ", 0, false)
    end
  end
  w(string.format("  (dump took %.0f ms, %d lines)", (os.clock() - clock) * 1000, lines))
end

-- Called every overlay tick while an enemy attack runs.
function R.onTick(a, elapsed, hits, flagsCodeNow)
  if not a.rs then a.rs = {} end
  local rs = a.rs
  watch(a, elapsed)
  if flagsCodeNow and flagsCodeNow ~= rs.code then
    w(string.format("  %7.3f  flags -> %s", elapsed, flagsCodeNow))
    rs.code = flagsCodeNow
  end
  if not rs.declLogged and hits and #hits > 0 then
    rs.declLogged = true
    local parts = {}
    for i, h in ipairs(hits) do parts[i] = string.format("%.3f", elapsed + h.remaining) end
    w(string.format("  %7.3f  declared hits (timeline) at: %s", elapsed, table.concat(parts, ", ")))
  end
end

function R.onPress(a, kind, off, immuneUntilOff)
  w(string.format("  %7.3f  press %s (immune until %.3f)", off, kind, immuneUntilOff))
end

-- A hit reached a hero. predicted = learned offsets known before this run.
function R.onHit(a, off, code, predicted, heroClass, params)
  local err = ""
  if predicted and #predicted > 0 then
    local best = nil
    for _, p in ipairs(predicted) do
      if best == nil or math.abs(off - p) < math.abs(off - best) then best = p end
    end
    err = string.format("  predicted %.3f  error %+.3f", best, off - best)
  end
  local extra = ""
  pcall(function()
    local st = a.rs and a.rs.st
    if st and valid(st.m) then
      extra = fmt("  montage %s @ %.3f", st.montage or "?", st.ai:Montage_GetPosition(st.m))
    end
  end)
  w(string.format("  %7.3f  HIT on %s kind %s%s%s", off, heroClass, code, err, extra))
  if params and #params > 0 then w("           params: " .. table.concat(params, " | ")) end
end

function R.onDamage(a, off, full, flagsCode, reduced)
  w(string.format("  %7.3f  damage went through: %.0f (kind %s)%s", off or -1, full or -1, flagsCode,
    reduced and reduced > 0 and string.format(", graze -%d%%", math.floor(reduced * 100 + 0.5)) or ""))
end

function R.onCommit(a, learnedNow)
  local parts = {}
  for i, o in ipairs(a.observed or {}) do parts[i] = string.format("%.3f", o) end
  w(string.format("  end: %d hit(s) observed [%s]; declared timeline: %s; stored timing: %s",
    #(a.observed or {}), table.concat(parts, ", "), tostring(a.declared),
    learnedNow and (#learnedNow .. " hit(s)") or "none"))
end

R.scalar = scalar
return R
