#!/bin/bash
# Vibe Dev v8 — ротация завершённых фич в архив по ссылке (L3-F5, c3/c10).
#
# done/superseded/rejected с evidence физически выносятся в feature_list.archive.json (ПОЛНОЕ
# тело + evidence_hash); в горячем feature_list.json остаётся однострочный индекс-стаб. Горячий
# контекст остаётся тонким (карта скоупа как индекс), тело/доказательство грузятся по требованию.
#
# evidence_hash = sha256 тела архивной фичи → /audit и git pre-commit проверяют целостность
# доказательства архивной фичи БЕЗ загрузки тела (c10).
#
# Идемпотентна (стаб не архивирует повторно). Атомарна (temp + os.replace обоих файлов).
# done без evidence НЕ архивируется (warn) — доказательство обязательно (c10). На резолвере L2-F1.
#
# Использование: bash scripts/archive-features.sh [<путь-проекта>]
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh"

ROOT="$(vibe_resolve_root "${1:-$PWD}" strict)" || exit 1
FL="$(vibe_path_feature_list "$ROOT")"
ARCH="$(vibe_path_archive "$ROOT")"
[ -f "$FL" ] || { echo "❌ Нет feature_list.json в $ROOT" >&2; exit 1; }

FL="$FL" ARCH="$ARCH" python3 <<'PYEOF'
import json, os, hashlib

FL = os.environ["FL"]; ARCH = os.environ["ARCH"]
ARCHIVE_STATES = {"done", "superseded", "rejected"}

def body_hash(f):
    return "sha256:" + hashlib.sha256(
        json.dumps(f, sort_keys=True, ensure_ascii=False).encode("utf-8")
    ).hexdigest()

data = json.load(open(FL, encoding="utf-8"))
try:
    arch = json.load(open(ARCH, encoding="utf-8")) if os.path.exists(ARCH) else {}
except Exception:
    arch = {}
arch.setdefault("version", data.get("version", "8.0"))
arch.setdefault("archived", [])
arch_ids = {a.get("id") for a in arch["archived"] if isinstance(a, dict)}

moved = skipped = 0
for bucket, feats in (data.get("features") or {}).items():
    if not isinstance(feats, list):
        continue
    keep = []
    for f in feats:
        if not isinstance(f, dict):
            keep.append(f); continue
        if "evidence_hash" in f:          # уже стаб — идемпотентность
            keep.append(f); continue
        state = f.get("state", bucket)
        if state not in ARCHIVE_STATES:
            keep.append(f); continue
        # c10: done архивируем ТОЛЬКО с evidence-доказательством; superseded/rejected — свободно
        ev = f.get("evidence")
        has_ev = isinstance(ev, dict) and len(ev) > 0
        if state == "done" and not has_ev:
            keep.append(f); skipped += 1     # без доказательства не прячем — оставляем на виду
            continue
        h = body_hash(f)
        if f.get("id") not in arch_ids:
            arch["archived"].append(f)
            arch_ids.add(f.get("id"))
        stub = {
            "id": f.get("id"), "name": f.get("name"), "state": state,
            "evidence_ref": "archive#" + str(f.get("id")),
            "history_ref": "log#" + str(f.get("id")),
            "evidence_hash": h,
        }
        keep.append(stub)
        moved += 1
    data["features"][bucket] = keep

def atomic(path, obj):
    tmp = path + ".arch.tmp"
    with open(tmp, "w", encoding="utf-8") as w:
        json.dump(obj, w, ensure_ascii=False, indent=2)
        w.write("\n"); w.flush(); os.fsync(w.fileno())
    os.replace(tmp, path)

if moved:
    atomic(ARCH, arch)      # сначала архив (тело durable), потом горячий стаб
    atomic(FL, data)
warn = (" (пропущено %d done без evidence — оставлены в горячем, добавь доказательство)" % skipped) if skipped else ""
print("✓ архивировано %d, всего в архиве %d%s" % (moved, len(arch["archived"]), warn))
PYEOF
