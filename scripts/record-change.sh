#!/bin/bash
# Vibe Dev v8 — record-change.sh: ЕДИНСТВЕННЫЙ путь записи провенанса (L3-F3, ревизия критика M2).
#
# Атомарно (насколько позволяет ФС) дописывает событие в холодный лог И синхронизирует
# провенанс-голову фичи в feature_list.json. Агент НЕ правит лог/голову руками.
#
# КРЭШ-БЕЗОПАСНОСТЬ (критик C2: 51 задокументированный обрыв инструмента mid-execution):
#   Порядок НЕСУЩИЙ — (1) СНАЧАЛА append события в лог одной строкой (O_APPEND атомарен для
#   строки на локальной ФС), (2) ПОТОМ голова через temp + os.replace (атомарный rename).
#   Единственно возможное расхождение при обрыве между шагами = «голова на 1 seq позади лога»
#   = ВОССТАНОВИМО реплеем лога (см. --recover). Обратный порядок дал бы «голова впереди» =
#   невосстановимую потерю from_hash → ЗАПРЕЩЁН.
#   Идемпотентность: change_id (или детерминированный hash) — повтор после «append прошёл,
#   tool отчитался об ошибке» дедупится. Рваный хвост лога (обрыв на середине append) —
#   читатель терпит (игнор+warn), recovery усекает.
#   Self-verify: после записи головы читаем обратно и сверяем seq.
#
# Использование:
#   printf '<event-json>' | bash scripts/record-change.sh --project <path>
#   bash scripts/record-change.sh --recover --project <path>     # пересбор голов из лога
#
# event-json (минимум): {"feat":"feat-012","op":"MODIFIED","by":"owner",
#   "origin":"dialog","source_ref":{"kind":"session","ref":"s:1"},
#   "changes":{"description":{"to":"новый текст"}}, "change_id":"опц"}
# op ∈ ADDED|MODIFIED|REMOVED|RENAMED|SUPERSEDED|REJECTED|REOPENED
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh"

MODE="write"; PROJ_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recover) MODE="recover" ;;
    --project) shift; PROJ_ARG="$1" ;;
    *) ;;
  esac
  shift
done

ROOT="$(vibe_resolve_root "${PROJ_ARG:-$PWD}" strict)" || exit 1
FL="$(vibe_path_feature_list "$ROOT")"
LOG="$(vibe_path_provenance_log "$ROOT")"

EVENT_JSON=""
[ "$MODE" = "write" ] && EVENT_JSON="$(cat)"

FL="$FL" LOG="$LOG" MODE="$MODE" python3 - "$EVENT_JSON" <<'PYEOF'
import json, sys, os, hashlib, datetime

FL  = os.environ["FL"]
LOG = os.environ["LOG"]
MODE = os.environ["MODE"]
event_in = sys.argv[1] if len(sys.argv) > 1 else ""

def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def sha(s):
    return "sha256:" + hashlib.sha256(str(s).encode("utf-8")).hexdigest()[:32]

def read_log_events():
    """Читает лог, терпит рваный хвост (обрыв на append): битые строки → пропуск."""
    events, broken = [], 0
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except Exception:
                    broken += 1  # незавершённая последняя строка — терпим
    return events, broken

def max_seq(events, feat):
    s = [e.get("seq", -1) for e in events if e.get("feat") == feat and isinstance(e.get("seq"), int)]
    return max(s) if s else -1

def load_fl():
    with open(FL, encoding="utf-8") as f:
        return json.load(f)

def find_feature(data, feat):
    for bucket, feats in (data.get("features") or {}).items():
        if isinstance(feats, list):
            for fobj in feats:
                if isinstance(fobj, dict) and fobj.get("id") == feat:
                    return fobj
    return None

def atomic_write_fl(data):
    tmp = FL + ".rc.tmp"
    with open(tmp, "w", encoding="utf-8") as w:
        json.dump(data, w, ensure_ascii=False, indent=2)
        w.write("\n")
        w.flush()
        os.fsync(w.fileno())
    os.replace(tmp, FL)  # атомарный rename

# --- RECOVERY: голова отстала от лога (обрыв между append и mv) → пересобрать провенанс-голову ---
if MODE == "recover":
    events, broken = read_log_events()
    data = load_fl()
    fixed = 0
    seen = {}
    for e in events:
        seen.setdefault(e.get("feat"), []).append(e)
    for feat, evs in seen.items():
        fobj = find_feature(data, feat)
        if not fobj:
            continue
        ms = max_seq(events, feat)
        prov = fobj.get("provenance")
        head_seq = (prov or {}).get("seq", -1) if isinstance(prov, dict) else -1
        if head_seq < ms:
            # реплей: применить события с head_seq+1 по ms к бизнес-полям + провенансу
            for e in sorted(evs, key=lambda x: x.get("seq", -1)):
                if e.get("seq", -1) <= head_seq:
                    continue
                for field, ch in (e.get("changes") or {}).items():
                    if "to" in ch:
                        fobj[field] = ch["to"]
                if e.get("op") == "SUPERSEDED" and e.get("superseded_by"):
                    fobj.setdefault("provenance", {})["superseded_by"] = e["superseded_by"]
            prov = fobj.setdefault("provenance", {})
            prov["seq"] = ms
            last = max(evs, key=lambda x: x.get("seq", -1))
            prov["rev_cache"] = {"seq": ms, "at": last.get("at")}
            fixed += 1
    if fixed:
        atomic_write_fl(data)
    print("recover: восстановлено голов %d, битых строк лога %d" % (fixed, broken))
    sys.exit(0)

# --- WRITE ---
try:
    ev = json.loads(event_in) if event_in.strip() else {}
except Exception as e:
    print("record-change: событие не JSON: %s" % e, file=sys.stderr); sys.exit(1)

feat = ev.get("feat"); op = ev.get("op"); by = ev.get("by")
if not feat or not op or not by:
    print("record-change: обязательны feat, op, by", file=sys.stderr); sys.exit(1)

data = load_fl()
fobj = find_feature(data, feat)
if fobj is None:
    print("record-change: фича %s не найдена в feature_list.json" % feat, file=sys.stderr); sys.exit(1)

events, broken = read_log_events()

# Идемпотентность: change_id уже в логе для feat → уже записано (ретрай после обрыва) → выход 0.
change_id = ev.get("change_id") or sha(json.dumps({"feat": feat, "op": op, "changes": ev.get("changes")}, sort_keys=True, ensure_ascii=False))
for e in events:
    if e.get("feat") == feat and e.get("change_id") == change_id:
        print("record-change: событие change_id=%s уже в логе (идемпотентно, пропуск)" % change_id[:16])
        sys.exit(0)

# seq = max(голова, лог) + 1: захват (L3-F1) ставит seq=0 в голове через Write БЕЗ ADDED-события
# в логе, поэтому один лог недосчитывает. Голова тоже участвует в определении следующего seq.
head_seq0 = (fobj.get("provenance") or {}).get("seq", -1)
if not isinstance(head_seq0, int):
    head_seq0 = -1
seq = max(max_seq(events, feat), head_seq0) + 1
at = now_iso()

# from_hash для каждого изменяемого поля (текущее значение фичи ДО применения)
changes_out = {}
for field, ch in (ev.get("changes") or {}).items():
    cur = fobj.get(field)
    entry = {"to": ch.get("to"), "from_hash": sha(cur)}
    if "from_summary" in ch:
        entry["from_summary"] = ch["from_summary"]
    changes_out[field] = entry

event = {
    "v": 1, "at": at, "feat": feat, "seq": seq, "op": op, "change_id": change_id,
    "by": by,
}
for k in ("origin", "source_ref", "occurred_at", "superseded_by"):
    if ev.get(k) is not None:
        event[k] = ev[k]
if changes_out:
    event["changes"] = changes_out

# (1) СНАЧАЛА append лога — атомарная строка, fsync.
os.makedirs(os.path.dirname(LOG), exist_ok=True)
with open(LOG, "a", encoding="utf-8") as w:
    w.write(json.dumps(event, ensure_ascii=False) + "\n")
    w.flush()
    os.fsync(w.fileno())

# (2) ПОТОМ голова — применяем бизнес-поля + провенанс, temp+replace.
for field, ch in (ev.get("changes") or {}).items():
    if "to" in ch:
        fobj[field] = ch["to"]
prov = fobj.setdefault("provenance", {})
if op == "ADDED":
    for k in ("origin", "source_ref", "occurred_at", "by"):
        if ev.get(k) is not None:
            prov[k] = ev[k]
    prov.setdefault("captured_at", at)
if op == "SUPERSEDED" and ev.get("superseded_by"):
    prov["superseded_by"] = ev["superseded_by"]
prov["seq"] = seq
prov["rev_cache"] = {"seq": seq, "at": at}
atomic_write_fl(data)

# (3) Self-verify: read-back, seq головы == seq события.
check = find_feature(load_fl(), feat)
if not check or (check.get("provenance") or {}).get("seq") != seq:
    print("record-change: SELF-VERIFY FAIL — голова не сошлась с логом (seq %s); запусти --recover" % seq, file=sys.stderr)
    sys.exit(2)

print("record-change: %s %s seq=%d записано (лог+голова синхронны)" % (op, feat, seq))
PYEOF
