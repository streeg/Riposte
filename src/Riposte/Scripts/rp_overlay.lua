-- Riposte overlay: draws a prepared frame (see rp_tick). Pure presentation.
--
-- Look: a "target" made of anti-aliased Slate rounded boxes (no textures).
--   * window zones: faint fill + crisp hairline edge; the zone the ring is in
--     lights up
--   * approaching ring: fades in, colour blends smoothly between zones, the
--     next hit gets a soft two-layer glow, later hits of a combo are dimmer
--   * centre: coloured dot with a white pip and a halo that breathes while the
--     ring is in the perfect window
--   * impact: a ring bursts out of the centre at the hit moment
--   * text: bold, spaced caps with outline and shadow; graze messages pop in
--   * the whole overlay fades in and out instead of blinking
--
-- Every UMG setter invalidates Slate layout/paint, so values are only pushed
-- when they visibly change.

local UEHelpers = require("UEHelpers")
local core = require("rp_core")
local cfg, valid, dbg = core.cfg, core.valid, core.dbg
local ui = core.state.ui

local M = {}

local VIS_COLLAPSED, VIS_HIT_TEST_INVISIBLE = 1, 3
local DRAW_ROUNDED_BOX, ROUNDING_HALF_HEIGHT = 4, 1
local WHITE, BLACK = { 1, 1, 1 }, { 0, 0, 0 }
local FADE_IN, FADE_OUT = 0.10, 0.18    -- overlay fade times (s)
local FLASH_GROW = 38                   -- impact burst growth (units)
local BLEND = 0.05                      -- colour cross-fade before each zone edge (s)
M.FLASH_TIME = 0.30                     -- impact burst duration (s)

local W = nil -- widgets, built lazily

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end
M.clamp01, M.smooth = clamp01, smooth

local function setRGBA(structColor, c, a)
  structColor.R = c[1]; structColor.G = c[2]; structColor.B = c[3]; structColor.A = a
end

-------------------------------------------------------------------------------
-- widgets
-------------------------------------------------------------------------------

local function centerSlot(slot, z)
  slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
  slot:SetAlignment({ X = 0.5, Y = 0.5 })
  slot:SetPosition({ X = cfg.OffsetX, Y = cfg.OffsetY })
  slot:SetZOrder(z)
end

-- A round image. The outline is drawn white and the fill at fillAlpha; the
-- colour and overall opacity are applied per frame with SetColorAndOpacity.
local function makeDisc(canvas, tree, imageClass, z, outline, fillAlpha)
  local img = StaticConstructObject(imageClass, tree)
  local brush = img.Brush
  brush.DrawAs = DRAW_ROUNDED_BOX
  brush.OutlineSettings.RoundingType = ROUNDING_HALF_HEIGHT
  brush.OutlineSettings.bUseBrushTransparency = false
  brush.OutlineSettings.Width = outline
  setRGBA(brush.OutlineSettings.Color.SpecifiedColor, WHITE, outline > 0 and 1 or 0)
  setRGBA(brush.TintColor.SpecifiedColor, WHITE, fillAlpha)
  local slot = canvas:AddChildToCanvas(img)
  centerSlot(slot, z)
  img:SetVisibility(VIS_COLLAPSED)
  return { img = img, slot = slot, on = false, outline = outline }
end

local function show(disc, on)
  if disc.on ~= on then
    disc.img:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_COLLAPSED)
    disc.on = on
  end
end

-- radius = outer edge of the disc in UI units
local function place(disc, radius, c, alpha)
  if not radius or radius <= 0.5 or not alpha or alpha <= 0.004 then
    show(disc, false)
    return
  end
  show(disc, true)
  if disc.r == nil or math.abs(disc.r - radius) > 0.15 then
    disc.r = radius
    disc.slot:SetSize({ X = radius * 2, Y = radius * 2 })
  end
  local p = disc.c
  if p == nil or math.abs(p[1] - c[1]) + math.abs(p[2] - c[2]) + math.abs(p[3] - c[3]) + math.abs(p[4] - alpha) > 0.008 then
    disc.c = { c[1], c[2], c[3], alpha }
    disc.img:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = alpha })
  end
end

-- A ring whose band is centred on `centre` (the outline grows inwards from the
-- edge, so the box is pushed out by half its width).
local function placeBand(disc, centre, c, alpha)
  place(disc, centre + disc.outline / 2, c, alpha)
end

local function build()
  local owner = UEHelpers.GetGameInstance()
  if not valid(owner) then return nil end
  local userWidgetClass = StaticFindObject("/Script/UMG.UserWidget")
  local treeClass = StaticFindObject("/Script/UMG.WidgetTree")
  local canvasClass = StaticFindObject("/Script/UMG.CanvasPanel")
  local imageClass = StaticFindObject("/Script/UMG.Image")
  local textClass = StaticFindObject("/Script/UMG.TextBlock")

  local w = { rings = {} }
  w.root = StaticConstructObject(userWidgetClass, owner)
  w.root.WidgetTree = StaticConstructObject(treeClass, w.root)
  local tree = w.root.WidgetTree
  local canvas = StaticConstructObject(canvasClass, tree)
  tree.RootWidget = canvas

  local th = cfg.RingThickness
  w.zoneGraze = makeDisc(canvas, tree, imageClass, 0, 1.5, 0.30)
  w.zoneDodge = makeDisc(canvas, tree, imageClass, 1, 1.5, 0.30)
  w.zonePerfect = makeDisc(canvas, tree, imageClass, 2, 2, 0.35)
  w.glowWide = makeDisc(canvas, tree, imageClass, 3, th * 4, 0)
  w.glowNear = makeDisc(canvas, tree, imageClass, 4, th * 2.2, 0)
  for i = 1, cfg.MaxRings do
    w.rings[i] = makeDisc(canvas, tree, imageClass, 5, th, 0)
  end
  w.flash = makeDisc(canvas, tree, imageClass, 6, 3, 0)
  w.coreHalo = makeDisc(canvas, tree, imageClass, 7, 0, 1)
  w.core = makeDisc(canvas, tree, imageClass, 8, 0, 1)
  w.pip = makeDisc(canvas, tree, imageClass, 9, 0, 1)

  local function makeText(z, size, spacing)
    local text = StaticConstructObject(textClass, tree)
    pcall(function() text.Font.Size = size end)
    pcall(function() text.Font.LetterSpacing = spacing end)
    pcall(function()
      text.Font.OutlineSettings.OutlineSize = 2
      setRGBA(text.Font.OutlineSettings.OutlineColor, BLACK, 0.55)
    end)
    pcall(function()
      text.ShadowOffset.X = 0; text.ShadowOffset.Y = 2
      setRGBA(text.ShadowColorAndOpacity, BLACK, 0.45)
    end)
    local slot = canvas:AddChildToCanvas(text)
    centerSlot(slot, z)
    slot:SetAutoSize(true)
    text:SetVisibility(VIS_COLLAPSED)
    return { text = text, slot = slot, shown = nil, on = false }
  end
  w.label = makeText(10, 16, 160)
  w.message = makeText(11, 28, 60)

  w.root:AddToViewport(50)
  w.root:SetVisibility(VIS_COLLAPSED)
  w.visible = false
  w.alpha = 0
  dbg("overlay built")
  return w
end

-- Text with colour; opacity and scale are for the pop / fade animation.
local function setText(entry, str, y, color, alpha, scale)
  if str == nil or (alpha or 1) <= 0.004 then
    if entry.on then entry.text:SetVisibility(VIS_COLLAPSED); entry.on = false end
    return
  end
  if not entry.on then entry.text:SetVisibility(VIS_HIT_TEST_INVISIBLE); entry.on = true end
  if entry.y == nil or math.abs(entry.y - y) > 0.5 then
    entry.y = y
    entry.slot:SetPosition({ X = cfg.OffsetX, Y = cfg.OffsetY + y })
  end
  if entry.shown ~= str then
    entry.text:SetText(FText(str))
    entry.shown = str
  end
  local c = color or WHITE
  if entry.color ~= c then
    entry.color = c
    pcall(function()
      entry.text:SetColorAndOpacity({ SpecifiedColor = { R = c[1], G = c[2], B = c[3], A = 1 }, ColorUseRule = 0 })
    end)
  end
  local a = alpha or 1
  if entry.alpha == nil or math.abs(entry.alpha - a) > 0.01 then
    entry.alpha = a
    entry.text:SetRenderOpacity(a)
  end
  local s = scale or 1
  if entry.scale == nil or math.abs(entry.scale - s) > 0.005 then
    entry.scale = s
    pcall(function() entry.text:SetRenderScale({ X = s, Y = s }) end)
  end
end

-------------------------------------------------------------------------------
-- visibility
-------------------------------------------------------------------------------

function M.visible() return W ~= nil and W.visible end

function M.hide()
  if W and W.visible and valid(W.root) then
    W.root:SetVisibility(VIS_COLLAPSED)
    W.visible = false
    W.alpha = 0
  end
end

-- Nothing to show: fade out rather than vanish.
function M.fadeOut(dt)
  if W and W.visible and valid(W.root) then
    W.alpha = W.alpha - dt / FADE_OUT
    if W.alpha <= 0 then M.hide() else W.root:SetRenderOpacity(W.alpha) end
  end
end

-------------------------------------------------------------------------------
-- drawing
-------------------------------------------------------------------------------

-- What the next hit asks for: zone sizes, colours and the label.
local function describe(flags, win)
  local d = { perfectColor = cfg.ColorPerfect, farColor = cfg.ColorFar, coreColor = WHITE, labelColor = WHITE }
  if flags.jumpable then
    d.perfect, d.wide, d.label = win.jump, win.jump, "JUMP"
    d.perfectColor = cfg.ColorJump or { 1.00, 0.45, 0.00 }
    d.farColor, d.coreColor, d.labelColor = d.perfectColor, d.perfectColor, d.perfectColor
  elseif flags.gradient then
    d.perfect, d.wide, d.label = win.gradient, win.gradient, "GRADIENT PARRY"
    d.perfectColor = cfg.ColorGradient or { 0.70, 0.35, 1.00 }
    d.farColor, d.coreColor, d.labelColor = d.perfectColor, d.perfectColor, d.perfectColor
  elseif flags.unblockable then
    d.perfect, d.wide, d.label = win.dodge, win.dodge, "DODGE"
  elseif flags.undodgeable then
    d.perfect, d.wide, d.label = win.parry, win.parry, "PARRY"
  else
    d.perfect, d.wide, d.label = win.parry, win.dodge, "DODGE  ·  PARRY"
  end
  return d
end

local lastPredictLog = -1000

-- f: { t, dt, upcoming = { {remaining, ...} }, flags, kind, win,
--      msgActive, lateActive, learning, flashActive }
function M.render(f)
  if not W or not valid(W.root) or not W.root:IsInViewport() then
    W = build()
    if not W then return end
  end
  if not W.visible then
    W.root:SetVisibility(VIS_HIT_TEST_INVISIBLE)
    W.visible = true
  end
  if W.alpha < 1 then
    W.alpha = math.min(1, W.alpha + f.dt / FADE_IN)
    W.root:SetRenderOpacity(smooth(W.alpha))
  end

  local t, speed, dot = f.t, cfg.RingSpeed, cfg.CoreRadius
  local labelText, labelColor, labelAlpha, zoneRadius = nil, WHITE, 0.92, 0

  if #f.upcoming > 0 then
    local d = describe(f.flags, f.win)
    local perfect, wide = d.perfect, d.wide
    labelText, labelColor = d.label, d.labelColor
    local outer = cfg.GracePeriod and cfg.OuterEarly or 0

    -- zone edges from the outside in; the ring colour cross-fades at each edge
    local stages = {}
    if outer > 0 then stages[#stages + 1] = { edge = wide + outer, color = cfg.ColorGraze } end
    if wide > perfect then stages[#stages + 1] = { edge = wide, color = cfg.ColorDodge } end
    stages[#stages + 1] = { edge = perfect, color = d.perfectColor }
    local function ringColor(r)
      local col = d.farColor
      for _, s in ipairs(stages) do col = mix(col, s.color, smooth((s.edge + BLEND - r) / BLEND)) end
      return col
    end

    -- zones: faint fill, crisp edge; the one holding the lead ring lights up
    local r1 = f.upcoming[1].remaining
    local inPerfect, inWide, inOuter = r1 <= perfect, r1 <= wide, r1 <= wide + outer
    zoneRadius = dot + (wide + outer) * speed
    place(W.zoneGraze, outer > 0 and zoneRadius or 0, cfg.ColorGraze, (inOuter and not inWide) and 0.55 or 0.32)
    place(W.zoneDodge, wide > perfect and (dot + wide * speed) or 0, cfg.ColorDodge, (inWide and not inPerfect) and 0.70 or 0.42)
    place(W.zonePerfect, dot + perfect * speed, d.perfectColor, inPerfect and 0.95 or 0.55)

    -- rings: fade in over the first 0.2 s; later hits of a combo are dimmer
    for i, ring in ipairs(W.rings) do
      local h = f.upcoming[i]
      if h then
        local r = h.remaining
        local appear = smooth((cfg.LeadTime - r) / 0.2)
        local col = ringColor(r)
        local centre = dot + r * speed - ring.outline / 2
        placeBand(ring, centre, col, appear * (i == 1 and 1 or 0.45))
        if i == 1 then
          local boost = inPerfect and 1.6 or (inWide and 1.25 or 1)
          placeBand(W.glowNear, centre, col, appear * 0.22 * boost)
          placeBand(W.glowWide, centre, col, appear * 0.09 * boost)
        end
      else
        show(ring, false)
      end
    end

    -- centre: coloured dot, white pip, halo that breathes inside the perfect window
    local pulse = inPerfect and (0.5 + 0.5 * math.sin(t * 28)) or 0
    local coreR = dot * (inPerfect and 1.12 or 1)
    place(W.coreHalo, coreR * (1.9 + 0.35 * pulse), d.perfectColor, 0.16 + 0.22 * pulse + (inPerfect and 0.1 or 0))
    place(W.core, coreR, inPerfect and d.perfectColor or d.coreColor, 0.95)
    place(W.pip, coreR * 0.38, WHITE, 0.95)

    ui.nextHit = { at = t + r1, color = d.perfectColor }

    if cfg.Debug and core.state.tick - lastPredictLog >= 25 then
      lastPredictLog = core.state.tick
      dbg(string.format("next hit in %.3fs (%s, kind %s), windows parry %.2f dodge %.2f jump %.2f",
        r1, labelText, f.kind or "live flag", f.win.parry, f.win.dodge, f.win.jump))
    end
  else
    place(W.zoneGraze, 0); place(W.zoneDodge, 0); place(W.zonePerfect, 0)
    show(W.glowNear, false); show(W.glowWide, false)
    for _, ring in ipairs(W.rings) do show(ring, false) end
    if f.lateActive then
      -- a hit just landed: the dot drains while a late press can still graze
      local left = clamp01((ui.lateUntil - t) / cfg.OuterLate)
      place(W.coreHalo, dot * (1.2 + 0.8 * left), cfg.ColorLate, 0.25 * left)
      place(W.core, dot * smooth(left), cfg.ColorLate, 0.95)
      place(W.pip, dot * 0.38 * smooth(left), WHITE, 0.9)
    else
      place(W.coreHalo, 0); place(W.core, 0); place(W.pip, 0)
    end
    if f.learning then
      labelText = "NEW ATTACK  ·  LEARNING TIMING"
      labelAlpha = 0.55 + 0.35 * (0.5 + 0.5 * math.sin(t * 4))
    end
  end

  -- impact burst
  if f.flashActive then
    local p = (t - ui.flash.t0) / M.FLASH_TIME
    local ease = 1 - (1 - p) * (1 - p) * (1 - p)
    placeBand(W.flash, dot + FLASH_GROW * ease, ui.flash.color, 0.85 * (1 - p) * (1 - p))
  else
    show(W.flash, false)
  end

  -- text: label under the circle, graze message above it with a pop
  local textGap = math.min(zoneRadius, 170)
  setText(W.label, cfg.ShowLabel and labelText or nil, textGap + 26, labelColor, labelAlpha)
  if f.msgActive then
    local age = t - (ui.msgUntil - ui.msgTime)
    local popIn = clamp01(age / 0.14)
    local scale = 1 + 0.35 * (1 - popIn) * (1 - popIn)
    local fade = clamp01((ui.msgUntil - t) / 0.3)
    setText(W.message, ui.msg, -(textGap + 34) - 6 * popIn, ui.msgColor or cfg.ColorGraze, smooth(popIn) * fade, scale)
  else
    setText(W.message, nil)
  end
end

return M
