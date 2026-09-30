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
#   tool отчитался об ошибке» дедупится, а отставший реестр догоняется тут же (v9.0.2).
#   Запись без головы получает голову ДО события — обрыв и на ней даёт «голова позади на 1».
#   Рваный хвост лога (обрыв на середине append) — читатель терпит (игнор+warn), recovery усекает.
#   Self-verify: после записи головы читаем обратно и сверяем seq.
#
# Использование:
#   printf '%s' '<event-json>' | bash "<папка плагина>/scripts/record-change.sh" --project "<папка проекта>"
#   bash "<папка плагина>/scripts/record-change.sh" --recover --project "<папка проекта>"   # догнать отставшие головы
#   Скрипт живёт в плагине, не в проекте: полную команду с путями печатают сторожа (v9.0.3).
#     (голова стаба ротации — большее из своей и головы тела в архиве; запись без головы и стаб
#      без тела не трогаются — сверять не с чем; в стаб переносится только то, чего нет в теле)
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
ARCH="$(vibe_path_archive "$ROOT")"

EVENT_JSON=""
[ "$MODE" = "write" ] && EVENT_JSON="$(cat)"

FL="$FL" LOG="$LOG" ARCH="$ARCH" MODE="$MODE" python3 - "$EVENT_JSON" <<'PYEOF'
import json, sys, os, hashlib, datetime

FL  = os.environ["FL"]
LOG = os.environ["LOG"]
ARCH = os.environ["ARCH"]
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

def load_archived():
    """Тела ротированных записей по id (feature_list.archive.json); нет/битый файл → пусто.
    Повтор id — берётся последний, как у сторожа коммитов (блоки 5 и 6)."""
    try:
        arch = json.load(open(ARCH, encoding="utf-8"))
    except Exception:
        return {}
    out = {}
    for a in (arch.get("archived") or []) if isinstance(arch, dict) else []:
        if isinstance(a, dict):
            out[a.get("id")] = a
    return out

def head_seq_of(fobj, archived):
    """До какого события дошла голова истории записи; None — головы нет нигде.

    Своя голова — provenance записи. У стаба ротации голова уезжает в архив вместе с телом
    (при ротации), поэтому для стаба берётся большее из своей и головы тела: своя бывает
    заниженной (миграция ставила стабам seq 0) или появляется, когда писатель правит уже архивную
    запись. Раньше recover читал отсутствие головы как seq=-1 и переигрывал в стаб ВЕСЬ журнал —
    описание, инвариант, проверки, файлы, — хотя тело в архиве было актуально; сторож коммитов
    видел «правку требования без события» и останавливал каждый второй чекпоинт после ротации
    (30.09.2026)."""
    prov = fobj.get("provenance")
    own = None
    if isinstance(prov, dict):
        s = prov.get("seq", -1)
        own = s if isinstance(s, int) else -1
    if "evidence_hash" not in fobj:
        return own
    bprov = (archived.get(fobj.get("id")) or {}).get("provenance")
    body = bprov.get("seq") if isinstance(bprov, dict) else None
    known = [x for x in (own, body if isinstance(body, int) else None) if x is not None]
    return max(known) if known else None

UNKNOWN = object()

def pending(evs, head_seq):
    """Итог событий после головы по полям: решает последнее событие поля. Изменение без значения
    ({"changed": true} — так проектный писатель пишет технические поля) делает поле неизвестным:
    прежнее «to» в журнале устарело, и перенести его — значит откатить поле к старому."""
    todo, sup = {}, None
    for e in sorted((x for x in evs if isinstance(x.get("seq"), int)), key=lambda x: x["seq"]):
        if e["seq"] <= head_seq:
            continue
        for field, ch in (e.get("changes") or {}).items():
            todo[field] = ch["to"] if isinstance(ch, dict) and "to" in ch else UNKNOWN
        if e.get("op") == "SUPERSEDED" and e.get("superseded_by"):
            sup = e["superseded_by"]
    return {k: v for k, v in todo.items() if v is not UNKNOWN}, sup

def catch_up(fobj, evs, archived):
    """Догнать голову записи до её событий в журнале.
    "fixed" — запись изменена; "current" — догонять нечего; "headless" — головы нет нигде
    (сверять не с чем); "nobody" — стаб, тела которого нет в архиве (сверять не с чем)."""
    stub = "evidence_hash" in fobj
    body = archived.get(fobj.get("id")) if stub else None
    if stub and body is None:
        return "nobody"
    head = head_seq_of(fobj, archived)
    if head is None:
        # Унаследованная запись; запись писателя, который голову не ведёт. Переигрыш всего журнала
        # поверх неё — догадка: переписывает поля требования без нового события и откатывает
        # позднейшие правки.
        return "headless"
    seqs = [e["seq"] for e in evs if isinstance(e.get("seq"), int)]
    if not seqs or head >= max(seqs):
        return "current"
    todo, sup = pending(evs, head)
    if stub:
        # Стаб: переносим только то, чего нет ни в нём, ни в теле архива. Голова тела бывает
        # отставшей лишь по счёту (писатель дописал событие, а голову не сдвинул) — тогда данные
        # уже в теле, и перенос раздул бы стаб полями требования, которые сторож коммитов прочтёт
        # как правку без события.
        todo = {k: v for k, v in todo.items() if (fobj[k] if k in fobj else body.get(k)) != v}
        had = fobj["provenance"] if isinstance(fobj.get("provenance"), dict) else body.get("provenance")
        if sup is not None and isinstance(had, dict) and had.get("superseded_by") == sup:
            sup = None
        if not todo and sup is None:
            return "current"
    fobj.update(todo)
    if not isinstance(fobj.get("provenance"), dict):
        fobj["provenance"] = {}
    prov = fobj["provenance"]
    if sup is not None:
        prov["superseded_by"] = sup
    last = max((e for e in evs if isinstance(e.get("seq"), int)), key=lambda x: x["seq"])
    prov["seq"] = last["seq"]
    prov["rev_cache"] = {"seq": last["seq"], "at": last.get("at")}
    return "fixed"

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
    archived = load_archived()
    count = {"fixed": 0, "current": 0, "headless": 0, "nobody": 0}
    seen = {}
    for e in events:
        seen.setdefault(e.get("feat"), []).append(e)
    for feat, evs in seen.items():
        fobj = find_feature(data, feat)
        if fobj:
            count[catch_up(fobj, evs, archived)] += 1
    if count["fixed"]:
        atomic_write_fl(data)
    msg = "recover: восстановлено голов %d" % count["fixed"]
    if count["headless"]:
        msg += ", без головы истории %d (сверять не с чем — не трогаю)" % count["headless"]
    if count["nobody"]:
        msg += ", стабов без тела в архиве %d (не трогаю — архив проверит сторож коммитов)" % count["nobody"]
    print(msg + ", битых строк лога %d" % broken)
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
        # Повтор после обрыва: событие уже в журнале, но обрыв мог случиться между журналом и
        # реестром — тогда реестр догоняется здесь же. Раньше «пропуск» с кодом 0 оставлял реестр
        # позади: коммит проходил, а следующий чекпоинт применял уже закоммиченное событие, и
        # сторож коммитов его не засчитывал — событие не новое.
        st = catch_up(fobj, [x for x in events if x.get("feat") == feat], load_archived())
        if st == "fixed":
            atomic_write_fl(data)
            print("record-change: событие change_id=%s уже в логе; реестр отставал — догнан до seq %s"
                  % (change_id[:16], fobj["provenance"]["seq"]))
        else:
            print("record-change: событие change_id=%s уже в логе (идемпотентно, пропуск)" % change_id[:16])
            if st in ("headless", "nobody"):
                print("record-change: ⚠ у %s сверять журнал не с чем — дошло ли событие до реестра, "
                      "проверь поле глазами" % feat, file=sys.stderr)
        sys.exit(0)

# Голова заводится ДО события, если у записи её нет (стаб ротации, унаследованная запись, запись
# другого писателя). Иначе обрыв между журналом и реестром оставил бы журнал впереди безголовой
# записи, а безголовую запись не догонят ни recover, ни повтор события — сверять не с чем, — и
# правка терялась бы молча. С головой обрыв даёт штатное «голова позади на одно событие», которое
# догоняют и чекпоинт, и повтор. Своя атомарная запись: голова = то, что уже учтено в записи.
if not isinstance(fobj.get("provenance"), dict):
    base = head_seq_of(fobj, load_archived())   # стаб: голова тела в архиве
    if base is None:
        base = max_seq(events, feat)            # иначе журнал до сих пор считается учтённым
    fobj["provenance"] = {"seq": base} if base >= 0 else {}
    atomic_write_fl(data)

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
