# collect the pilot screenshots - moved from _migration\archive\mwx-debug\aw-weapons\collect_pilot_images.py on 27 Nov 2026.
#!/usr/bin/env python3
"""Copy the AW materials, techsets and only the referenced images of the pilot guns into the
zone source.

The AW `dumpzone h1 patch_common_mp image` dump is ~6.7 GB; the zone source must not carry all of
it. Every material JSON lists its images in textureTable; this script copies just those .h1Image
files from images/ and streamed_images/.

Usage: collect_pilot_images.py <dump_dir> <zone_source> <material_name> [<material_name> ...]
"""
import json
import os
import shutil
import sys


def material_images(dump, material):
    path = os.path.join(dump, "materials", "m", material + ".json")
    if not os.path.exists(path):
        print("material %s not found in the dump" % material)
        return set()
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        data = json.load(f)
    images = set()
    for entry in data.get("textureTable", []) or []:
        if isinstance(entry, dict) and entry.get("image"):
            images.add(entry["image"])
    return images


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    dump, source = sys.argv[1], sys.argv[2]
    materials = sys.argv[3:]

    images = set()
    for material in materials:
        found = material_images(dump, material)
        images |= found
        print("material %-32s %2i images" % (material, len(found)))

    copied = 0
    missing = []
    for name in sorted(images):
        got = False
        for sub in ("images", "streamed_images"):
            src = os.path.join(dump, sub, name + ".h1Image")
            if os.path.exists(src):
                dst_dir = os.path.join(source, sub)
                os.makedirs(dst_dir, exist_ok=True)
                shutil.copy2(src, os.path.join(dst_dir, name + ".h1Image"))
                copied += 1
                got = True
                # a streamed image's payload lives next to the header as <name>_streamN.pixels
                for f in os.listdir(os.path.join(dump, sub)):
                    if f.startswith(name + "_stream") and f.endswith(".pixels"):
                        shutil.copy2(os.path.join(dump, sub, f), os.path.join(dst_dir, f))
                        copied += 1
        if not got:
            missing.append(name)
    print("copied %i image files (%i not dumped)" % (copied, len(missing)))
    for name in missing:
        print("  missing image: %s" % name)

    for folder in ("materials", "techsets"):
        src = os.path.join(dump, folder)
        dst = os.path.join(source, folder)
        if not os.path.isdir(src):
            continue
        os.makedirs(dst, exist_ok=True)
        for root, _dirs, files in os.walk(src):
            rel = os.path.relpath(root, src)
            target = os.path.join(dst, rel) if rel != "." else dst
            os.makedirs(target, exist_ok=True)
            for f in files:
                shutil.copy2(os.path.join(root, f), os.path.join(target, f))
        print("copied %s" % folder)
    return 0


if __name__ == "__main__":
    sys.exit(main())
