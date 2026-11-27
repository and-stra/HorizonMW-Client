#!/usr/bin/env python3
"""zone-check: name collisions between a zone we build and the zones loaded before it.

Rule (docs/guides/zones.md): our zones must not contain an asset whose name already
exists in a previously loaded zone, unless the content is identical (zonetool
linking always embeds identical copies) or the name is listed in overrides.txt.

  python zone_check.py index --zone <name> --dump <dump-dir> [--dump <dir> ...] --out index/prior.json
  python zone_check.py check --zone-source <zonetool dir> --index index/prior.json [--overrides overrides.txt]
  python zone_check.py list  --index index/prior.json

The dump layout is the zonetool one: <dump>/<type-dir>/<name>.<ext>
(materials/*.json, techsets/*.techset, images/*.h1Image, xmodel/*.xmb, ...).

"Identical" includes the assets a material/model references: the hash of a
material is folded with the hashes of the images/techsets it names, the hash of a
model with the materials it names. Without that, two materials that point at
different textures would compare equal.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time

# dump directory -> asset type (the zonetool layout)
TYPE_DIRS = {
    "materials": "material",
    "techsets": "techset",
    "images": "image",
    "streamed_images": "image",
    "xmodel": "xmodel",
    "xanim": "xanim",
    "xsurface": "xsurface",
    "weapons": "weapon",
    "attachments": "attachment",
    "effects": "fx",
    "physcollmap": "physcollmap",
    "physpreset": "physpreset",
    "localizedstrings": "localizedstring",
}

# sidecar files that belong to another asset and must not become names
SIDECARS = (".txt", ".technique", ".statebits", ".stateinfo", ".statebitsmap",
            ".cbi", ".cbt", ".cso", ".vertexdecl", ".pixels", ".json.lock")


def type_for_dir(name):
    """Type of an asset directory; zonetool also names some dirs `xanim.<set>`."""
    for prefix, asset_type in TYPE_DIRS.items():
        if name == prefix or name.startswith(prefix + "."):
            return asset_type
    return None


def primary_files(root):
    """(type, name, path) for every asset under a dump or zonetool source dir."""
    for entry in os.listdir(root):
        base = os.path.join(root, entry)
        if not os.path.isdir(base):
            continue
        asset_type = type_for_dir(entry)
        if asset_type is None:
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in filenames:
                low = fn.lower()
                if low.endswith(SIDECARS):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, base)
                name = os.path.splitext(rel)[0].replace("\\", "/")
                yield asset_type, name, path


def sha1_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def image_stream_files(path):
    """The _streamN.pixels payloads that belong to an image header."""
    folder, fn = os.path.split(path)
    stem = os.path.splitext(fn)[0]
    out = []
    for other in os.listdir(folder):
        if other.startswith(stem + "_stream") and other.endswith(".pixels"):
            out.append(os.path.join(folder, other))
    return sorted(out)


def strings_of(path, min_len=4):
    """Printable ASCII strings in a binary asset (for the reference folding)."""
    try:
        data = open(path, "rb").read()
    except OSError:
        return []
    return [m.decode("ascii") for m in re.findall(rb"[ -~]{%d,}" % min_len, data)]


def referenced_names(asset_type, path):
    """Names of other assets a material/model refers to."""
    if asset_type == "material":
        try:
            doc = json.load(open(path, "r", encoding="utf-8", errors="ignore"))
        except Exception:
            return []
        names = []

        def walk(node):
            if isinstance(node, dict):
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)
            elif isinstance(node, str):
                names.append(node)

        walk(doc)
        return names
    if asset_type in ("xmodel", "xanim"):
        return strings_of(path)
    return []


def hash_zone(root):
    """{type: {name: hash}} with referenced assets folded in."""
    assets = {}
    by_name = {}
    for asset_type, name, path in primary_files(root):
        assets.setdefault(asset_type, {})[name] = path
        by_name.setdefault(name, (asset_type, path))

    # one read per file: the reference folding must not re-hash an image for every
    # material that names it (a zone has thousands of references)
    cache = {}

    # one directory listing per folder: an image folder can hold tens of thousands of
    # _streamN.pixels files, listing it per image is quadratic
    stream_map = {}

    def streams_for(path):
        folder, fn = os.path.split(path)
        stem = os.path.splitext(fn)[0]
        if folder not in stream_map:
            found = {}
            try:
                for other in os.listdir(folder):
                    if "_stream" in other and other.endswith(".pixels"):
                        found.setdefault(other.split("_stream", 1)[0], []).append(
                            os.path.join(folder, other))
            except OSError:
                pass
            for paths in found.values():
                paths.sort()
            stream_map[folder] = found
        return stream_map[folder].get(stem, [])

    def base_hash(path):
        hit = cache.get(path)
        if hit is not None:
            return hit
        h = hashlib.sha1(sha1_file(path).encode())
        if path.lower().endswith((".h1image", ".png", ".dds")):
            for stream in streams_for(path):
                h.update(sha1_file(stream).encode())
        cache[path] = h.hexdigest()
        return cache[path]

    result = {}
    for asset_type, entries in assets.items():
        out = result.setdefault(asset_type, {})
        for name, path in entries.items():
            h = hashlib.sha1(base_hash(path).encode())
            for ref in referenced_names(asset_type, path):
                ref = ref.strip()
                hit = by_name.get(ref)
                if hit and hit[1] != path:
                    h.update(base_hash(hit[1]).encode())
            out[name] = h.hexdigest()
    return result


def load_index(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_index(path, index):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, sort_keys=True)
        f.write("\n")


def cmd_index(args):
    index = load_index(args.out) if os.path.exists(args.out) else {"zones": {}}
    for dump in args.dump:
        if not os.path.isdir(dump):
            print("skip (no such dir): %s" % dump)
            continue
        zone = args.zone or os.path.basename(os.path.normpath(dump))
        index["zones"][zone] = hash_zone(dump)
        counts = ", ".join("%s %d" % (t, len(v)) for t, v in sorted(index["zones"][zone].items()))
        print("%-28s %s" % (zone, counts))
    save_index(args.out, index)
    print("index: %s (%d zones)" % (args.out, len(index["zones"])))


def load_overrides(path):
    out = set()
    if path and os.path.exists(path):
        for line in open(path, "r", encoding="utf-8"):
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(line)
    return out


def find_collisions(ours, index, overrides):
    collisions, identical = [], []
    for asset_type, entries in sorted(ours.items()):
        for name, digest in sorted(entries.items()):
            key = "%s/%s" % (asset_type, name)
            for zone, zones in index["zones"].items():
                other = zones.get(asset_type, {}).get(name)
                if other is None:
                    continue
                if other == digest:
                    identical.append((asset_type, name, zone))
                elif key not in overrides:
                    collisions.append((asset_type, name, zone))
                break
    return collisions, identical


def cmd_check(args):
    if not os.path.exists(args.index):
        print("error: index %s missing - run tools/zone-check/build-index.ps1" % args.index)
        return 2
    index = load_index(args.index)
    overrides = load_overrides(args.overrides)

    ours = hash_zone(args.zone_source)
    collisions, identical = find_collisions(ours, index, overrides)

    print("zone-check %s: %d assets, %d identical duplicates, %d collisions"
          % (os.path.basename(os.path.normpath(args.zone_source)),
             sum(len(v) for v in ours.values()), len(identical), len(collisions)))
    for asset_type, name, zone in identical:
        print("  identical  %-10s %-46s (also in %s)" % (asset_type, name, zone))
    for asset_type, name, zone in collisions:
        print("  COLLISION  %-10s %-46s (differs from %s)" % (asset_type, name, zone))
    if collisions:
        print("fix: rename the asset (e.g. _aw suffix) and repoint the referencing asset, "
              "or add the name to tools/zone-check/overrides.txt")
    if args.json:
        report = {
            "zone": os.path.basename(os.path.normpath(args.zone_source)),
            "assets": sum(len(v) for v in ours.values()),
            "collisions": [{"type": t, "name": n, "zone": z} for t, n, z in collisions],
            "identical": [{"type": t, "name": n, "zone": z} for t, n, z in identical],
        }
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=1)
        print("report: %s" % args.json)
    if collisions:
        return 1
    return 0


def cmd_list(args):
    index = load_index(args.index)
    for zone, zones in sorted(index["zones"].items()):
        print(zone)
        for asset_type, entries in sorted(zones.items()):
            print("  %-12s %d" % (asset_type, len(entries)))
    return 0


def cmd_fix(args):
    index = load_index(args.index)
    overrides = load_overrides(args.overrides)

    paths = {}
    for asset_type, name, path in primary_files(args.zone_source):
        paths.setdefault((asset_type, name), path)

    ours = hash_zone(args.zone_source)
    collisions, _identical = find_collisions(ours, index, overrides)
    if not collisions:
        print("no collisions")
        return 0

    stamp = args.stamp or time.strftime("%Y%m%d-%H%M%S")
    backup = os.path.join(args.backup, stamp)
    moved = []
    for asset_type, name, zone in collisions:
        if args.types and asset_type not in args.types.split(","):
            continue
        path = paths.get((asset_type, name))
        if not path:
            print("skip (file not found): %s/%s" % (asset_type, name))
            continue
        rel = os.path.relpath(path, args.zone_source)
        dest = os.path.join(backup, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        os.replace(path, dest)
        moved.append((asset_type, name, zone, rel))
        if asset_type == "image":
            folder, fn = os.path.split(path)
            stem = os.path.splitext(fn)[0]
            for other in os.listdir(folder):
                if other.startswith(stem + "_stream") and other.endswith(".pixels"):
                    src_stream = os.path.join(folder, other)
                    srel = os.path.relpath(src_stream, args.zone_source)
                    sdest = os.path.join(backup, srel)
                    os.makedirs(os.path.dirname(sdest), exist_ok=True)
                    os.replace(src_stream, sdest)

    for asset_type, name, zone, rel in moved:
        print("moved %-10s %-46s (was in %s) -> %s" % (asset_type, name, zone, rel))
    print("%d file(s) moved to %s" % (len(moved), backup))

    left, _ = find_collisions(hash_zone(args.zone_source), index, overrides)
    left = [c for c in left if not args.types or c[0] in args.types.split(",")]
    if left:
        print("%d collision(s) left:" % len(left))
        for asset_type, name, zone in left:
            print("  %-10s %-46s (%s)" % (asset_type, name, zone))
        return 1
    print("no collisions left")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_index = sub.add_parser("index", help="add a dump to the prior-zone index")
    p_index.add_argument("--zone", help="zone name (default: dump folder name)")
    p_index.add_argument("--dump", action="append", required=True)
    p_index.add_argument("--out", required=True)
    p_index.set_defaults(func=cmd_index)

    p_check = sub.add_parser("check", help="check a zone source against the index")
    p_check.add_argument("--zone-source", required=True)
    p_check.add_argument("--index", required=True)
    p_check.add_argument("--overrides", default=os.path.join(os.path.dirname(__file__), "overrides.txt"))
    p_check.add_argument("--json", help="write the full report (collisions/identical per zone) here")
    p_check.set_defaults(func=cmd_check)

    p_list = sub.add_parser("list", help="show an index")
    p_list.add_argument("--index", required=True)
    p_list.set_defaults(func=cmd_list)

    p_fix = sub.add_parser("fix", help="move colliding assets out of a zone source (backup first)")
    p_fix.add_argument("--zone-source", required=True)
    p_fix.add_argument("--index", required=True)
    p_fix.add_argument("--backup", required=True)
    p_fix.add_argument("--types", default="", help="only these types (e.g. image,material)")
    p_fix.add_argument("--stamp", default="")
    p_fix.add_argument("--overrides", default=os.path.join(os.path.dirname(__file__), "overrides.txt"))
    p_fix.set_defaults(func=cmd_fix)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
