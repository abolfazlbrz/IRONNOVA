#!/usr/bin/env python3
"""Build an offline, license-audited IRONNOVA exercise image catalog.

Sources are fetched at build time only. Media is bundled inside the app and is
never requested from third-party image hosts at runtime.
"""
from __future__ import annotations
import hashlib, io, json, re, shutil, sys, time, unicodedata, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "iron-exercises"
CATALOG_OUT = ROOT / "assets" / "iron-exercise-catalog.json"
MIN_EXERCISES = 1000
SOURCES = [
    ("repdb", "https://codeload.github.com/RepDB/exercise-dataset/zip/refs/heads/main"),
    ("cc0", "https://codeload.github.com/MarvinNazari/exercise-images/zip/refs/heads/main"),
    ("workout-guide", "https://codeload.github.com/bryllim/workout-guide/zip/refs/heads/main"),
]

def get_zip(url: str) -> zipfile.ZipFile:
    last = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "IRONNOVA-Exercise-Asset-Builder/1.0"})
            with urllib.request.urlopen(req, timeout=180) as response:
                payload = response.read()
            if len(payload) < 1024:
                raise RuntimeError(f"archive unexpectedly small: {len(payload)} bytes")
            return zipfile.ZipFile(io.BytesIO(payload))
        except Exception as exc:
            last = exc
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"could not download {url}: {last}")

def find_member(zf: zipfile.ZipFile, suffix: str) -> str:
    matches = [n for n in zf.namelist() if n.endswith(suffix)]
    if len(matches) != 1:
        raise RuntimeError(f"expected one {suffix}, found {len(matches)}")
    return matches[0]

def read_json(zf: zipfile.ZipFile, suffix: str):
    return json.loads(zf.read(find_member(zf, suffix)).decode("utf-8"))

def norm(value: str) -> str:
    value = unicodedata.normalize("NFKD", str(value or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "", value)

def slug(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", norm(value)).strip("-")
    return value[:72] or "exercise"

def read_member(zf: zipfile.ZipFile, root: str, rel: str):
    if not rel:
        return None, None
    rel = rel.replace("\\", "/").lstrip("/")
    candidates = [n for n in zf.namelist() if n.endswith(root + "/" + rel) or n.endswith("/" + rel)]
    if not candidates:
        return None, None
    name = min(candidates, key=len)
    data = zf.read(name)
    if not data or len(data) < 80:
        return None, None
    return name, data

def body_part(raw, muscles):
    s = str(raw or "").lower().replace("-", "_").replace(" ", "_")
    if s in ("upper_legs", "lower_legs", "legs", "quads", "quadriceps", "hamstrings", "glutes", "gluteus", "calves", "adductors", "abductors", "hip_flexors"): return "legs"
    if s in ("core", "waist", "abs", "abdominals", "obliques"): return "waist"
    if s in ("arms", "upper_arms", "biceps", "triceps", "forearms", "lower_arms"): return "upper_arms" if s != "forearms" else "lower_arms"
    if s in ("chest", "pectorals", "pectoralis_major", "pectoralis_minor"): return "chest"
    if s in ("back", "lats", "latissimus_dorsi", "middle_back", "lower_back", "traps", "trapezius"): return "back"
    if s in ("shoulders", "deltoids", "deltoid", "anterior_deltoid", "lateral_deltoid", "posterior_deltoid"): return "shoulders"
    if s in ("neck",): return "neck"
    if s in ("cardio", "full_body", "fullbody"): return "cardio"
    joined = " ".join(str(x).lower() for x in (muscles or []))
    for key, result in (("chest","chest"),("pector","chest"),("biceps","upper_arms"),("triceps","upper_arms"),("forearm","lower_arms"),("shoulder","shoulders"),("deltoid","shoulders"),("lat","back"),("trapez","back"),("back","back"),("quad","legs"),("hamstring","legs"),("glute","legs"),("calf","legs"),("abdom","waist"),("oblique","waist"),("core","waist"),("neck","neck")):
        if key in joined: return result
    return "other"

def equipment_value(raw):
    if isinstance(raw, list):
        raw = raw[0] if raw else "bodyweight"
    s = str(raw or "bodyweight").strip().lower().replace(" ", "_").replace("-", "_")
    aliases = {"body_weight":"bodyweight","body_only":"bodyweight","none":"bodyweight","no_equipment":"bodyweight","leverage_machine":"machine","cable_machine":"cable","resistance_band":"band","ez_bar":"ez_barbell"}
    return aliases.get(s, s or "other")

def is_valid_image(data: bytes, ext: str) -> bool:
    ext = ext.lower()
    if ext == ".webp": return data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    if ext == ".png": return data.startswith(b"\x89PNG\r\n\x1a\n")
    if ext in (".jpg", ".jpeg"): return data.startswith(b"\xff\xd8\xff")
    if ext == ".svg": return b"<svg" in data[:1000].lower()
    return False

def candidate(source, name, equipment, muscles, secondary, body, level, description, instructions, files, license_name, attribution, aliases=None):
    if not name or not files or not files[0]: return None
    return {
        "source": source, "name": str(name).strip(), "aliases": aliases or [],
        "equipment": equipment_value(equipment), "primary_muscles": muscles if isinstance(muscles, list) else ([muscles] if muscles else []),
        "secondary_muscles": secondary if isinstance(secondary, list) else ([secondary] if secondary else []),
        "body_part": body_part(body, muscles if isinstance(muscles, list) else [muscles]),
        "level": str(level or "beginner").lower(), "description_en": str(description or ""),
        "instructions_en": instructions if isinstance(instructions, list) else [],
        "files": files, "license": license_name, "attribution": attribution
    }

def build_candidates():
    all_candidates = []
    z = get_zip(SOURCES[0][1])
    rep = read_json(z, "/exercises.json")
    for x in rep.get("exercises", []):
        flat = (x.get("images") or {}).get("flat") or {}
        start = flat.get("start") or flat.get("main") or flat.get("peak")
        peak = flat.get("peak") or flat.get("main") or start
        all_candidates.append(candidate(
            "repdb", x.get("name_en"), x.get("equipment"), x.get("primary_muscles", []),
            x.get("secondary_muscles", []), x.get("body_part"), x.get("difficulty"),
            x.get("description_en"), x.get("instructions_en", []),
            [(z, start), (z, peak)], "RepDB Free Tier License (in-app use, attribution required)",
            "Exercise data by RepDB (repdb.co)"
        ))

    z = get_zip(SOURCES[1][1])
    mar = read_json(z, "/exercises.json")
    for x in mar.get("exercises", []):
        images = x.get("images") or {}
        start = images.get("start") or images.get("hold") or images.get("mid") or images.get("end")
        peak = images.get("end") or images.get("mid") or start
        all_candidates.append(candidate(
            "cc0", x.get("name"), x.get("equipment", []),
            (x.get("muscles") or {}).get("primary", []),
            (x.get("muscles") or {}).get("secondary", []),
            (x.get("muscles") or {}).get("primary", []), x.get("level"),
            x.get("description") or x.get("notes") or "",
            x.get("instructions") or [],
            [(z, start), (z, peak)], "CC0 1.0 Universal",
            "Open Exercise Illustrations by Marvin Nazari (CC0 1.0)"
        ))

    z = get_zip(SOURCES[2][1])
    manifest = read_json(z, "/packages/workout-guide/manifest.json")
    for x in manifest:
        frames = x.get("frames") or []
        if not frames: continue
        first = frames[0].get("path")
        last = frames[-1].get("path")
        all_candidates.append(candidate(
            "workout-guide", x.get("name"), x.get("equipment"),
            [x.get("primaryMuscle")] if x.get("primaryMuscle") else [],
            x.get("secondaryMuscles", []), x.get("primaryMuscle"), "beginner",
            "", [], [(z, first), (z, last)],
            "CC BY-SA 4.0", "Bryl Lim and Everkinetic (CC BY-SA 4.0)"
        ))
    return all_candidates

def main():
    if OUT.exists(): shutil.rmtree(OUT)
    OUT.mkdir(parents=True, exist_ok=True)
    used_names, used_hashes, catalog = set(), set(), []
    source_counts = {"repdb": 0, "cc0": 0, "workout-guide": 0}
    candidates = build_candidates()
    for item in candidates:
        if not item: continue
        keys = [norm(item["name"])] + [norm(a) for a in item["aliases"]]
        keys = [k for k in keys if k]
        if not keys or any(k in used_names for k in keys): continue
        prepared = []
        for archive, rel in item["files"]:
            member, data = read_member(archive, "", rel)
            if not data: continue
            ext = Path(rel).suffix.lower()
            if not is_valid_image(data, ext): continue
            prepared.append((rel, data, ext, hashlib.sha256(data).hexdigest()))
        if not prepared: continue
        main_frame = prepared[0]
        if main_frame[3] in used_hashes: continue
        exercise_slug = slug(item["name"])
        base = f"{item['source']}/{exercise_slug}"
        start_rel = f"assets/iron-exercises/{base}-start{main_frame[2]}"
        start_path = ROOT / start_rel
        start_path.parent.mkdir(parents=True, exist_ok=True)
        start_path.write_bytes(main_frame[1])
        used_hashes.add(main_frame[3])
        peak_rel = start_rel
        if len(prepared) > 1:
            peak_frame = prepared[-1]
            if peak_frame[3] not in used_hashes:
                peak_rel = f"assets/iron-exercises/{base}-peak{peak_frame[2]}"
                peak_path = ROOT / peak_rel
                peak_path.write_bytes(peak_frame[1])
                used_hashes.add(peak_frame[3])
        for k in keys: used_names.add(k)
        row = {
            "id": f"{item['source']}-{exercise_slug}",
            "name_en": item["name"], "name_fa": "",
            "body_part": item["body_part"], "equipment": item["equipment"],
            "primary_muscles": item["primary_muscles"], "secondary_muscles": item["secondary_muscles"],
            "level": item["level"], "description_en": item["description_en"],
            "instructions_en": item["instructions_en"], "source": item["source"],
            "license": item["license"], "attribution": item["attribution"],
            "images": {"flat": {"start": start_rel, "peak": peak_rel}}
        }
        catalog.append(row)
        source_counts[item["source"]] += 1
    if len(catalog) < MIN_EXERCISES:
        raise SystemExit(f"Only {len(catalog)} unique exercises with non-duplicate verified images; need {MIN_EXERCISES}. Sources: {source_counts}")
    payload = {
        "version": 1, "count": len(catalog), "uniqueImageCount": len(used_hashes),
        "offline": True, "sourceCounts": source_counts, "exercises": catalog
    }
    CATALOG_OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    credits = """IRONNOVA exercise-media credits

1) RepDB Free Tier
Exercise data by RepDB (repdb.co). Free in-app use with visible attribution.
https://github.com/RepDB/exercise-dataset
License: RepDB Free Tier License (see LICENSE-DATA.md). The dataset is bundled only inside the IRONNOVA application, not republished as a standalone dataset.

2) Open Exercise Illustrations
Artwork by Marvin Nazari. CC0 1.0 Universal.
https://github.com/MarvinNazari/exercise-images
These illustrations are AI-generated and are not reviewed by a qualified coach or medical professional. Verify exercise form with qualified instruction.

3) Workout Guide
Exercise illustrations by Bryl Lim, derived from Everkinetic. CC BY-SA 4.0.
https://github.com/bryllim/workout-guide
https://github.com/everkinetic/data
License: https://creativecommons.org/licenses/by-sa/4.0/
Changes: original frames are packaged locally without visual modification.
"""
    (ROOT / "assets" / "iron-exercise-credits.txt").write_text(credits, encoding="utf-8")
    print(f"IRONNOVA offline exercise catalog: {len(catalog)} unique exercises, {len(used_hashes)} unique image files; {source_counts}")
    print(f"Catalog bytes: {CATALOG_OUT.stat().st_size}; media bytes: {sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())}")

if __name__ == "__main__":
    main()
