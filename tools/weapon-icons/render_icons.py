#!/usr/bin/env python3
"""Render MWX weapon icons in the MWR CAC style with hmw-workbench.

    py -3 tools/weapon-icons/render_icons.py --refs iw5_exocrossbow,iw5_dlcgun23,iw5_dlcgun18,iw5_combatknife

For each ref it loads the *world* model (orbit, no hands) and renders:
  out/<ref>-list.png    512x256  (CAC list cell, 2x for downscaling)
  out/<ref>-header.png  512x256  (big CAC header icon)
  out/<ref>-hud.png     256x128  (HUD / kill feed)
The camera is the style measured from the MWR CAC icons (style.json).

The output is PNG. Converting it to the game's .h1Image + _streamN.pixels is the open
step (see docs/weapon-icons.md); this tool stops at the render + contact sheet.
"""
import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_client import Mcp  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
DEFAULT_STYLE = {
    "yaw": 90,
    "pitch": 10,
    "fov": 32,
    "dist": 70,
    "width": 512,
    "height": 256,
    "sizes": {"list": [512, 256], "header": [512, 256], "hud": [256, 128]},
}


def load_style():
    p = os.path.join(HERE, "style.json")
    style = dict(DEFAULT_STYLE)
    if os.path.exists(p):
        style.update(json.load(open(p, encoding="utf-8")))
    return style


def render(ref, style, mcp):
    weapon = ref if ref.endswith("_mp") else ref + "_mp"
    r = mcp.call("load_weapon", {"weapon": weapon, "world": True, "first_person": False})
    info = r.get("result", {})
    text = ""
    for block in info.get("content", []):
        if block.get("type") == "text":
            text = block.get("text", "")
    paths = []
    import shutil
    for name, (w, h) in style["sizes"].items():
        # the workbench only accepts paths inside its own repo root
        rel = "review/icons/%s-%s.png" % (ref, name)
        mcp.call("screenshot", {"path": rel, "view": "orbit", "width": w, "height": h,
                                "yaw": style["yaw"], "pitch": style["pitch"],
                                "dist": style["dist"], "fov": style["fov"]})
        src = os.path.join(r"C:\Games\cod-hwm\hmw-workbench", rel.replace("/", os.sep))
        dst = os.path.join(OUT, "%s-%s.png" % (ref, name))
        import time
        for _ in range(50):
            if os.path.exists(src):
                break
            time.sleep(0.1)
        if os.path.exists(src):
            shutil.copyfile(src, dst)
        paths.append((name, dst))
    print("%-18s %s" % (ref, ", ".join(p for _, p in paths)))
    return text, paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refs", default="iw5_exocrossbow,iw5_dlcgun23,iw5_dlcgun18,iw5_combatknife")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    style = load_style()
    mcp = Mcp()
    mcp.initialize()
    try:
        for ref in [r.strip() for r in args.refs.split(",") if r.strip()]:
            render(ref, style, mcp)
    finally:
        mcp.p.stdin.close()
        mcp.p.terminate()


if __name__ == "__main__":
    main()



