-- Riposte settings. Edit, save, restart the game.
-- All times are in seconds.
return {
  ---------------------------------------------------------------------------
  -- 1. Grace period
  ---------------------------------------------------------------------------
  GracePeriod = true,

  -- Size of the extra window on the EARLY side: you pressed, the vanilla
  -- window ran out, and the hit landed up to this long afterwards.
  OuterEarly = 0.25,

  -- Size of the extra window on the LATE side: the hit landed and you pressed
  -- up to this long afterwards. The damage was already dealt by then, so the
  -- reduced part is handed back as HP. It cannot undo a hit that killed the
  -- character. Set to 0 to turn the late side off.
  OuterLate = 0.20,

  -- Damage reduction right at the edge of the vanilla window (1.0 = 100 %).
  -- It falls off linearly to MinReduction at the far edge of the outer window.
  MaxReduction = 0.90,
  MinReduction = 0.00,

  -- Which moves can graze. A jump only counts against jumpable attacks and a
  -- gradient parry only against gradient attacks, as in vanilla.
  GrazeDodge = true,
  GrazeParry = true,
  GrazeJump = true,
  GrazeGradient = true,

  ---------------------------------------------------------------------------
  -- 2. Timing circle
  ---------------------------------------------------------------------------
  Visualizer = true,

  -- How long before a hit its ring appears.
  LeadTime = 1.20,
  -- Most rings on screen at once (multi-hit combos).
  MaxRings = 4,

  -- Position of the centre, as an offset from the middle of the screen
  -- (in UI units, 1080p-ish; +X right, +Y down).
  OffsetX = 0,
  OffsetY = 180,

  -- Radius of the centre dot (the hit moment) and ring speed in units/second.
  CoreRadius = 14,
  RingSpeed = 220,
  RingThickness = 5,

  -- Latency compensation (seconds). Your screen, TV or wireless controller adds
  -- delay between what you see and what the game receives. A positive value
  -- makes the ring reach the centre this much BEFORE the hit, so "press when
  -- it touches the dot" matches your setup. Rhythm-game style calibration:
  -- if you keep getting hit slightly late while the ring looks right, raise it
  -- by 0.01 at a time. Typical: 0.00 (monitor, wired) .. 0.08 (TV, Bluetooth).
  -- Only the drawing moves; the real dodge / parry windows are untouched.
  VisualOffset = 0.00,

  -- Show the name of the move the attack asks for under the circle.
  ShowLabel = true,
  -- Show "GRAZE -63%" when a graze happens.
  ShowGrazeText = true,

  -- Colours: {R, G, B} 0..1
  ColorFar = { 1.00, 1.00, 1.00 },    -- ring still outside every window
  ColorGraze = { 1.00, 0.80, 0.10 },  -- inside the outer (graze) window
  ColorDodge = { 0.20, 0.75, 1.00 },  -- inside the dodge window
  ColorPerfect = { 0.20, 1.00, 0.35 },-- inside the parry window (normal attacks)
  -- Jump and gradient attacks get their own colour: the ring, the centre dot
  -- and the window disc use it for the whole approach, so the kind of attack
  -- is visible as soon as the ring appears.
  ColorJump = { 1.00, 0.45, 0.00 },     -- jump attack
  ColorGradient = { 0.70, 0.35, 1.00 }, -- gradient attack
  ColorLate = { 1.00, 0.25, 0.20 },   -- hit already landed (late graze window)

  ---------------------------------------------------------------------------
  -- 3. Learned timings (riposte_learned.txt)
  ---------------------------------------------------------------------------
  -- Hotkey that forgets the recorded timing of the current (or last) enemy
  -- attack only, so it is re-learned the next time it plays. Use it when a
  -- circle is clearly wrong. Key names: see Mods/Keybinds/Scripts/main.lua
  -- (F1..F12, A..Z, NUM_ZERO..). Set ForgetKey = "" to disable.
  ForgetKey = "F8",
  ForgetKeyCtrl = true, -- true = Ctrl+F8, false = F8 alone

  ---------------------------------------------------------------------------
  -- Debug: prints every press, hit and predicted hit time to UE4SS.log.
  -- Leave off while playing: writing the log during fights can cause stutter.
  ---------------------------------------------------------------------------
  Debug = false,

  -- Research (developers only): needs tools/research/riposte_research.lua,
  -- which release builds do not ship. Records how enemy attacks are built and
  -- every attack run to riposte_research.txt. `python build.py install --dev`
  -- turns it on.
  Research = false,
}
