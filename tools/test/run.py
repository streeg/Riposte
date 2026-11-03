#!/usr/bin/env python3
"""Run the Riposte offline simulation (tools/test/sim.lua) under Lua 5.4.

    pip install lupa
    python tools/test/run.py
"""
import os
import sys
import tempfile

try:
    import lupa.lua54 as lua
except ImportError:
    sys.exit("needs lupa: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, "src", "Riposte", "Scripts").replace(os.sep, "/")
SIM = os.path.join(ROOT, "tools", "test", "sim.lua")

with tempfile.TemporaryDirectory() as out:
    rt = lua.LuaRuntime()
    chunk = rt.eval("function(src) return assert(load(src, '@sim.lua')) end")(open(SIM, encoding="utf-8").read())
    try:
        logs, learned = chunk(SCRIPTS, out.replace(os.sep, "/"))
    except lua.LuaError as e:
        print("FAILED:", e)
        sys.exit(1)
    print(logs)
    print("--- riposte_learned.txt:")
    print(learned or "(empty)")
    print("PASS")
