# Changelog

## 1.0.0 - first Riposte release

Riposte starts from Graded Defense 1.0 by jjmmaaxx (kudos!) and changes the
following.

### Timing circle
- New look: faint window fills with crisp edges, the active zone lights up, a
  soft two-layer glow on the next ring, smooth colour blending between zones,
  rings fade in, later hits of a combo are dimmer.
- Centre dot with a white pip and a halo that pulses inside the perfect window;
  a burst ring at the moment of impact.
- Bold, spaced labels with outline and shadow; GRAZE messages pop in and fade
  out (LATE GRAZE in red).
- The overlay fades in and out instead of blinking.
- Windows are drawn for the character the attack actually targets (read from
  the attack's TargetCharacters), not the first party member.
- New `VisualOffset` setting: latency compensation for TVs, Bluetooth and
  wireless controllers.

### Learned timings
- Hotkey **Ctrl+F8** (`ForgetKey`): forget the recorded timing of the current
  or last attack only.
- A wrong recording heals itself: if an attack shows a different hit count
  twice in a row, the new count replaces the stored one.

### Performance
- The object search that finds attack timelines never runs outside battle; in
  battle it runs in a short burst when an enemy attack starts, then once per
  second (was 10 times per second, always).
- Outside battle the overlay tick returns immediately.
- Widget properties are only pushed when they visibly change.
- Learned timings are written to disk after the battle, never mid-fight.
- Debug logging off by default.

### Robustness
- Errors are rate-limited: each distinct error at most once per 10 s, at most
  20 error lines per minute.
- If a game update renames the attack keyframe field, Riposte finds the new
  name; if it can't, it logs one clear "mod may be outdated" warning and keeps
  working with learned timings.
- Version number in the log line.

### Renamed
- Mod folder `GradedDefense` -> `Riposte`, config `gd_config.lua` ->
  `riposte_config.lua`, option `GradedDefense` -> `GracePeriod`, learned file
  `gd_learned.txt` -> `riposte_learned.txt`.
