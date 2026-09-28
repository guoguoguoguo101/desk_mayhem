"""Point GLB materials at the shared texture file and drop embedded copies.

Blender's GLB export stores each image inside every model and also writes a
second PNG beside that model. The canonical file lives in a textures folder.
"""

import hashlib
import json
import os
import struct
import sys

JSON_TYPE = 0x4E4F534A
BIN_TYPE = 0x004E4942


def _chunk(data, offset):
    length, chunk_type = struct.unpack_from("<II", data, offset)
    start = offset + 8
    return chunk_type, data[start : start + length], start + length


def _pad(data, fill):
    extra = (-len(data)) % 4
    return data + (fill * extra)


def _hash_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def texture_index(roots):
    grouped = {}
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.lower().endswith((".png", ".jpg", ".jpeg")):
                    continue
                path = os.path.join(dirpath, name)
                grouped.setdefault(_hash_file(path), []).append(path)
    canonical = {}
    duplicates = []
    for digest, paths in grouped.items():
        shared = [path for path in paths if os.path.basename(os.path.dirname(path)) == "textures"]
        if not shared or len(paths) == 1:
            continue
        chosen = sorted(shared, key=lambda path: (len(os.path.basename(path)), path))[0]
        canonical[digest] = chosen
        duplicates.extend(path for path in paths if os.path.normcase(path) != os.path.normcase(chosen))
    return canonical, duplicates


def _remap_views(node, remap, dropped):
    if isinstance(node, dict):
        if isinstance(node.get("bufferView"), int):
            index = node["bufferView"]
            if index in dropped:
                raise RuntimeError("removed bufferView %s is still referenced" % index)
            if index in remap:
                node["bufferView"] = remap[index]
        for value in node.values():
            _remap_views(value, remap, dropped)
    elif isinstance(node, list):
        for value in node:
            _remap_views(value, remap, dropped)


def externalize_glb(path, canonical):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:4] != b"glTF":
        raise RuntimeError("%s is not a GLB" % path)
    json_type, json_bytes, next_offset = _chunk(data, 12)
    if json_type != JSON_TYPE:
        raise RuntimeError("%s is missing a JSON chunk" % path)
    document = json.loads(json_bytes)
    bin_type, blob, _ = _chunk(data, next_offset)
    if bin_type != BIN_TYPE:
        raise RuntimeError("%s is missing a BIN chunk" % path)
    views = document.get("bufferViews", [])
    dropped = set()
    replaced = 0
    for image in document.get("images", []):
        view_index = image.get("bufferView")
        if view_index is None:
            continue
        view = views[view_index]
        start = view.get("byteOffset", 0)
        raw = blob[start : start + view["byteLength"]]
        target = canonical.get(hashlib.sha256(raw).hexdigest())
        if target is None:
            continue
        relative = os.path.relpath(target, os.path.dirname(path)).replace("\\", "/")
        image.pop("bufferView", None)
        image.pop("mimeType", None)
        image["uri"] = relative
        dropped.add(view_index)
        replaced += 1
    if not dropped:
        return 0
    new_views = []
    remap = {}
    new_blob = bytearray()
    for index, view in enumerate(views):
        if index in dropped:
            continue
        pad = (-len(new_blob)) % 4
        new_blob.extend(b"\x00" * pad)
        start = view.get("byteOffset", 0)
        remap[index] = len(new_views)
        copied = dict(view)
        copied["byteOffset"] = len(new_blob)
        new_blob.extend(blob[start : start + view["byteLength"]])
        new_views.append(copied)
    _remap_views(document, remap, dropped)
    if new_views:
        document["bufferViews"] = new_views
        document["buffers"] = [{"byteLength": len(new_blob)}]
    else:
        document.pop("bufferViews", None)
        document.pop("buffers", None)
    raw_json = _pad(json.dumps(document, separators=(",", ":")).encode("utf-8"), b" ")
    raw_bin = _pad(bytes(new_blob), b"\x00")
    out = bytearray()
    out.extend(b"glTF")
    out.extend(struct.pack("<II", 2, 0))
    out.extend(struct.pack("<II", len(raw_json), JSON_TYPE))
    out.extend(raw_json)
    out.extend(struct.pack("<II", len(raw_bin), BIN_TYPE))
    out.extend(raw_bin)
    struct.pack_into("<I", out, 8, len(out))
    with open(path, "wb") as handle:
        handle.write(out)
    return replaced


def main(roots):
    canonical, duplicates = texture_index(roots)
    replaced = 0
    rewritten = 0
    for root in roots:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.lower().endswith(".glb"):
                    continue
                path = os.path.join(dirpath, name)
                count = externalize_glb(path, canonical)
                if count:
                    rewritten += 1
                    replaced += count
                    print("externalized %s (%s images)" % (path, count))
    removed = 0
    for path in duplicates:
        if os.path.isfile(path):
            os.remove(path)
            removed += 1
            print("removed %s" % path)
    print("rewritten=%s images=%s removed=%s" % (rewritten, replaced, removed))


if __name__ == "__main__":
    folders = sys.argv[1:] or [os.path.join("assets", "environment")]
    main(folders)
