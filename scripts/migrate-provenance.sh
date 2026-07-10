#!/bin/bash
# Vibe Dev v8 — ретро-миграция провенанса (L3-F1, правка критика M3).
#
# Проставляет провенанс-голову фичам, у которых её нет. ЧЕСТНАЯ реконструкция:
#   origin=inference, source_ref.kind=unknown (источник НЕ выдумываем — иначе лог наполнится
#   необнаружимой ложью), by=agent, seq=0. captured_at — из СУЩЕСТВУЮЩЕГО top-level captured_at
#   фичи (реальные проекты его несут), иначе mtime файла. НЕ затираем реальную дату захвата (M3).
#
# Идемпотентна (фичи с provenance не трогает). Атомарна (temp + os.replace). Резолвит проект
# через единый резолвер (L2-F1) — не пишет в чужой проект.
#
# Использование: bash scripts/migrate-provenance.sh [<путь-проекта>]
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh"

ROOT="$(vibe_resolve_root "${1:-$PWD}" strict)" || exit 1
FL="$(vibe_path_feature_list "$ROOT")"
if [ ! -f "$FL" ]; then
  echo "❌ Нет feature_list.json в $ROOT" >&2
  exit 1
fi

python3 - "$FL" <<'PYEOF'
import json, sys, os, datetime

fl = sys.argv[1]
try:
    data = json.load(open(fl))
except Exception as e:
    print("❌ feature_list.json не читается как JSON: %s" % e); sys.exit(1)

# mtime файла как честный fallback (когда у фичи нет своего captured_at)
mt = datetime.datetime.fromtimestamp(os.path.getmtime(fl), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

migrated = kept = 0
for bucket, feats in (data.get('features') or {}).items():
    if not isinstance(feats, list):
        continue
    for f in feats:
        if not isinstance(f, dict):
            continue
        if isinstance(f.get('provenance'), dict):
            kept += 1
            continue  # идемпотентность — уже мигрирована
        # M3: сохранить существующий captured_at фичи, НЕ ставить mtime поверх реальной даты
        cap = str(f.get('captured_at') or '').strip() or mt
        f['provenance'] = {
            "origin": "inference",              # честно: источник реконструирован, не known
            "source_ref": {"kind": "unknown", "ref": "retro-migration"},  # M1: отличимо от живой inference
            "captured_at": cap,
            "by": "agent",
            "seq": 0
        }
        f.pop('captured_at', None)  # снять коллизию: один авторитетный captured_at — в provenance
        migrated += 1

tmp = fl + ".provmigrate.tmp"
with open(tmp, "w") as w:
    json.dump(data, w, ensure_ascii=False, indent=2)
    w.write("\n")
os.replace(tmp, fl)  # атомарный rename
print("✓ провенанс-миграция: реконструировано %d, уже было %d (origin=inference — честная метка)" % (migrated, kept))
PYEOF
