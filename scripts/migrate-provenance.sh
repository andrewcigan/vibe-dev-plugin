#!/bin/bash
# Vibe Dev v8 — ретро-миграция провенанса (L3-F1, правка критика M3).
#
# Проставляет провенанс-голову фичам, у которых её нет. ЧЕСТНАЯ реконструкция:
#   origin=inference, source_ref.kind=unknown (источник НЕ выдумываем — иначе лог наполнится
#   необнаружимой ложью), by=agent. captured_at — из СУЩЕСТВУЮЩЕГО top-level captured_at
#   фичи (реальные проекты его несут), иначе mtime файла. НЕ затираем реальную дату захвата (M3).
#   seq — до какого события запись уже учла журнал (v9.0.2): последнее событие фичи в журнале,
#   у стаба ротации — голова его тела в архиве; нет событий — 0. Раньше всегда ставился 0, и
#   recover переигрывал журнал с начала: поля требования переписывались без нового события
#   (сторож коммитов отвергал чекпоинт), а поля, изменённые позже без значения, откатывались.
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
LOG="$(vibe_path_provenance_log "$ROOT")"
ARCH="$(vibe_path_archive "$ROOT")"
if [ ! -f "$FL" ]; then
  echo "❌ Нет feature_list.json в $ROOT" >&2
  exit 1
fi

python3 - "$FL" "$LOG" "$ARCH" <<'PYEOF'
import json, sys, os, datetime

fl, log, arch_p = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.load(open(fl))
except Exception as e:
    print("❌ feature_list.json не читается как JSON: %s" % e); sys.exit(1)

# mtime файла как честный fallback (когда у фичи нет своего captured_at)
mt = datetime.datetime.fromtimestamp(os.path.getmtime(fl), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# До какого события запись уже учла журнал: последнее событие фичи (битые строки терпим).
logmax = {}
if os.path.exists(log):
    for ln in open(log, encoding="utf-8"):
        try:
            e = json.loads(ln)
        except Exception:
            continue
        if isinstance(e, dict) and isinstance(e.get("seq"), int):
            logmax[e.get("feat")] = max(logmax.get(e.get("feat"), -1), e["seq"])
# У стаба ротации голова уехала в архив вместе с телом — берём её.
bodyseq = {}
try:
    for a in (json.load(open(arch_p, encoding="utf-8")).get("archived") or []):
        s = ((a or {}).get("provenance") or {}).get("seq") if isinstance(a, dict) else None
        if isinstance(s, int):
            bodyseq[a.get("id")] = s
except Exception:
    pass

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
            "seq": max(0, bodyseq.get(f.get('id'), logmax.get(f.get('id'), 0)) if 'evidence_hash' in f
                       else logmax.get(f.get('id'), 0))
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
