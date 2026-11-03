Riposte - Clair Obscur: Expedition 33 (UE4SS Lua mod)

A timing circle for every enemy hit, and a grace period that turns near-miss
dodges, parries, jumps and gradient parries into reduced damage.
No game files are changed.

REQUIREMENT
  RE-UE4SS 3.0.1 or newer: https://github.com/UE4SS-RE/RE-UE4SS/releases

INSTALL
  1. Extract UE4SS into  Expedition 33\Sandfall\Binaries\Win64\
  2. Extract this archive into the game folder  Expedition 33\
     (the mod ends up in  Sandfall\Binaries\Win64\ue4ss\Mods\Riposte\)
  3. Start the game. ue4ss\UE4SS.log should contain "[Riposte] v... loaded".
  Linux / Steam Deck: launch option  WINEDLLOVERRIDES="dwmapi=n,b" %command%
  Do not run together with Graded Defense (both would reduce the same hits).

UNINSTALL
  Delete  ue4ss\Mods\Riposte\

SETTINGS
  Scripts\riposte_config.lua (commented). Restart the game after editing.
  Ctrl+F8 = forget the recorded timing of the current attack (re-learn it).

HOW TO READ THE CIRCLE
  Press while the shrinking ring is inside the disc of the move you want:
  green = parry, blue = dodge, yellow = grace window (reduced damage).
  Orange = jump attack, purple = gradient attack.

MIT License. Kudos to jjmmaaxx for Graded Defense, which Riposte started from.
Written with Claude (AI).
