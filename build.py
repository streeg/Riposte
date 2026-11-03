#!/usr/bin/env python3
"""Riposte build tool.

    python build.py                      build release zips into dist/
    python build.py install [GAME_DIR]   copy the mod into a game install
    python build.py install --dev        ...with Debug + Research on (research module included)

GAME_DIR is the folder that contains Sandfall/ (default: the RIPOSTE_GAME_DIR
environment variable). Learned timings already in the game folder are kept.
"""
import os
import re
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src", "Riposte")
RESEARCH = os.path.join(ROOT, "tools", "research", "riposte_research.lua")
DIST = os.path.join(ROOT, "dist")
MOD_PATH = "Sandfall/Binaries/Win64/ue4ss/Mods/Riposte"
CONFIG = "Scripts/riposte_config.lua"

# Optional config presets: (description, overrides)
PRESETS = {
    "Forgiving": ("Bigger grace windows and stronger reduction. For learning a tough boss.",
                  {"OuterEarly": "0.40", "OuterLate": "0.30", "MaxReduction": "0.95", "MinReduction": "0.20"}),
    "Strict": ("Small grace windows and weaker reduction. Close to vanilla, with a little slack.",
               {"OuterEarly": "0.12", "OuterLate": "0.08", "MaxReduction": "0.60"}),
    "TrainerOnly": ("Timing circle only. Damage rules are 100% vanilla (no grace period).",
                    {"GracePeriod": "false"}),
    "GraceOnly": ("Grace period only. No timing circle (the GRAZE text still shows).",
                  {"Visualizer": "false"}),
}

# Files in src/ that are never shipped (created by the mod at runtime).
RUNTIME_FILES = {"riposte_learned.txt", "riposte_research.txt"}


def version():
    with open(os.path.join(SRC, "Scripts", "rp_core.lua"), encoding="utf-8") as f:
        m = re.search(r'M.VERSION = "([^"]+)"', f.read())
    if not m:
        sys.exit("VERSION not found in rp_core.lua")
    return m.group(1)


def read_config():
    with open(os.path.join(SRC, CONFIG), encoding="utf-8") as f:
        return f.read()


def release_config(text):
    """Release builds: Debug off and no Research option (its module is not shipped)."""
    text = re.sub(r"\n  Debug = (true|false),", "\n  Debug = false,", text)
    text = re.sub(r"\n\n  -- Research \(developers only\).*?Research = (true|false),\n", "\n", text, flags=re.S)
    if "Research" in text:
        sys.exit("could not strip the Research option from the config")
    return text


def set_value(text, key, value):
    new, n = re.subn(r"(\n  %s = )[^,\n]+," % re.escape(key), r"\g<1>%s," % value, text, count=1)
    if n != 1:
        sys.exit("config key not found: " + key)
    return new


def shipped_files():
    for root, _, files in os.walk(SRC):
        for name in sorted(files):
            if name in RUNTIME_FILES:
                continue
            full = os.path.join(root, name)
            yield full, os.path.relpath(full, SRC).replace(os.sep, "/")


def write_zip(path, entries):
    """entries: list of (archive_name, bytes). Forward slashes only (Proton/Deck safe)."""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in entries:
            z.writestr(zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)), data, zipfile.ZIP_DEFLATED)


def build():
    v = version()
    os.makedirs(DIST, exist_ok=True)
    cfg = release_config(read_config())

    entries = []
    for full, rel in shipped_files():
        if rel == CONFIG:
            data = cfg.encode("utf-8")
        else:
            with open(full, "rb") as f:
                data = f.read()
        entries.append((MOD_PATH + "/" + rel, data))
    main_zip = os.path.join(DIST, "Riposte-%s.zip" % v)
    write_zip(main_zip, entries)
    print("built", os.path.relpath(main_zip, ROOT))

    for name, (desc, overrides) in PRESETS.items():
        text = cfg
        for k, val in overrides.items():
            text = set_value(text, k, val)
        text = text.replace("-- Riposte settings.", "-- Riposte settings - preset: %s\n-- %s\n--" % (name, desc), 1)
        out = os.path.join(DIST, "Riposte-Preset-%s-%s.zip" % (name, v))
        write_zip(out, [(MOD_PATH + "/" + CONFIG, text.encode("utf-8"))])
        print("built", os.path.relpath(out, ROOT))


def install(args):
    dev = "--dev" in args
    rest = [a for a in args if a != "--dev"]
    game = rest[0] if rest else os.environ.get("RIPOSTE_GAME_DIR")
    if not game:
        sys.exit("give the game folder (the one containing Sandfall/) or set RIPOSTE_GAME_DIR")
    ue4ss = os.path.join(game, "Sandfall", "Binaries", "Win64", "ue4ss", "Mods")
    if not os.path.isdir(ue4ss):
        sys.exit("UE4SS Mods folder not found: " + ue4ss)
    dest = os.path.join(ue4ss, "Riposte")
    for full, rel in shipped_files():
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(full, target)
    cfg_path = os.path.join(dest, CONFIG)
    with open(cfg_path, encoding="utf-8") as f:
        text = f.read()
    if dev:
        text = set_value(text, "Debug", "true")
        text = set_value(text, "Research", "true")
        shutil.copyfile(RESEARCH, os.path.join(dest, "Scripts", "riposte_research.lua"))
    else:
        text = release_config(text)
        stale = os.path.join(dest, "Scripts", "riposte_research.lua")
        if os.path.exists(stale):
            os.remove(stale)
    with open(cfg_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("installed Riposte %s%s to %s" % (version(), " (dev)" if dev else "", dest))
    old = os.path.join(ue4ss, "GradedDefense", "enabled.txt")
    if os.path.exists(old):
        print("WARNING: GradedDefense is also enabled; both would apply grazes. Disable one of them.")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "install":
        install(sys.argv[2:])
    elif len(sys.argv) == 1:
        build()
    else:
        sys.exit(__doc__)
