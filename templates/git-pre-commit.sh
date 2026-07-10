#!/bin/bash
# Vibe Dev — git pre-commit проекта (ставится scripts/install-precommit.sh при bootstrap/upgrade).
#
# Два блока:
#   1) ACTIVATION BACKSTOP (v6.2 F2) — независимый канал: живёт в .git/hooks/, работает даже
#      если плагин Claude Code вообще не загрузился. Профиль строгости без живых хуков =
#      enforcement-театр («харнес не поднялся») — ловим на каждом коммите.
#   2) WIP=1 SCOPE — diff ⊆ active feature.affected_files (копия проверки в .harness/hooks/).
#
# Этот файл самодостаточен по блоку 1 (ноль зависимостей от плагина) — в этом его смысл.

set -u
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
HARNESS="$ROOT_DIR/.harness"
TTL=1800  # 30 мин: heartbeat старше — сессия без живых хуков (или вне Claude Code)

# --- 1. ACTIVATION BACKSTOP ---
if [ -d "$HARNESS" ] && [ ! -f "$HARNESS/hooks-disabled" ]; then
  PROFILE=""
  [ -f "$HARNESS/profile" ] && PROFILE="$(tr -d '[:space:]' < "$HARNESS/profile" 2>/dev/null)"

  fail_activation() {
    cat >&2 <<EOF
🚨 КОММИТ ОСТАНОВЛЕН: enforcement не активен, хотя профиль строгости «${PROFILE}» заявлен.

Причина: $1

Профиль без живых сторожей — это театр строгости: проверки (UI-приёмка, scope, bulk-API)
молча НЕ выполняются. Ровно так выглядел провал «харнес не поднялся» в боевых проектах.

Как починить (по порядку):
  1. Плагин включён?   claude plugin list | grep vibe-dev   (если нет — установи/включи)
  2. Перезапусти сессию Claude Code В ЭТОЙ папке (хуки подхватываются при старте).
  3. После рестарта первое же сообщение активирует профиль (хук подтвердит сам).

Осознанно работаешь БЕЗ плагина (например, правишь руками вне Claude Code):
  touch .harness/hooks-disabled        # выключает этот backstop (журналируется в /audit)

Крайний случай (НЕ рекомендуется): git commit --no-verify — инцидент для error-journal.
EOF
    exit 1
  }

  case "$PROFILE" in
    pending-*)
      fail_activation "профиль «${PROFILE}» так и не подтверждён живым хуком (bootstrap прошёл, плагин — нет)."
      ;;
    standard|strict)
      HB="$HARNESS/hooks-heartbeat"
      if [ ! -f "$HB" ]; then
        fail_activation "нет heartbeat (.harness/hooks-heartbeat) — ни один хук ни разу не отработал в этом проекте."
      else
        HB_TS="$(awk '{print $1; exit}' "$HB" 2>/dev/null)"
        NOW="$(date +%s)"
        case "$HB_TS" in
          ''|*[!0-9]*) fail_activation "heartbeat повреждён (.harness/hooks-heartbeat)." ;;
          *)
            AGE=$((NOW - HB_TS))
            if [ "$AGE" -gt "$TTL" ]; then
              fail_activation "heartbeat устарел (${AGE}с > ${TTL}с) — в текущей сессии хуки не работают."
            fi
            ;;
        esac
      fi
      ;;
    *)
      : # minimal / пусто — backstop не применяется
      ;;
  esac
fi

# --- 2. WIP=1 SCOPE (копия проверки, установлена рядом с проектом) ---
SCOPE_CHECK="$HARNESS/hooks/pre-commit-scope.sh"
if [ -f "$SCOPE_CHECK" ]; then
  bash "$SCOPE_CHECK" || exit 1
fi

# --- 3. PROVENANCE LOG append-only (v8 L3-F2) ---
# .harness/provenance-log.jsonl — источник истины истории требований. Разрешены ТОЛЬКО
# добавленные строки; удаление/правка прошлой строки = фальсификация истории → reject.
# Детерминированно (не зависит от heartbeat/плагина — независимый git-канал). Исключение —
# легитимная компакция/снапшот старых событий: маркер .harness/locks/provenance-snapshot
# (ставит скрипт снапшота, агенту запись в locks/ запрещена) разрешает переписать в этом коммите.
LOG_REL=".harness/provenance-log.jsonl"
if [ ! -f "$HARNESS/locks/provenance-snapshot" ] \
   && git diff --cached --name-only 2>/dev/null | grep -qx "$LOG_REL"; then
  REMOVED="$(git diff --cached --unified=0 -- "$LOG_REL" 2>/dev/null | grep -cE '^-[^-]' || true)"
  if [ "${REMOVED:-0}" -gt 0 ]; then
    cat >&2 <<EOF
🚨 КОММИТ ОСТАНОВЛЕН: .harness/provenance-log.jsonl — append-only (v8 L3-F2).
В staged-диффе ${REMOVED} удалённых/изменённых строк лога. История требований не переписывается —
только добавляется. Верни прошлые строки; новое состояние фиксируй НОВЫМ событием через
scripts/record-change.sh. (Легитимная компакция старых событий — через снапшот-скрипт, он ставит
маркер .harness/locks/provenance-snapshot.)
EOF
    exit 1
  fi
fi

# --- 4. PROVENANCE head↔log когерентность (v8 L3-F3, критик M1) ---
# ОСНОВНОЙ детерминированный гейт провенанса: голова не должна быть ВПЕРЕДИ лога (seq головы >
# max seq в логе при наличии правок = правка мимо record-change.sh / потеря события). Это
# единственный канал, видящий результат ОБОИХ путей записи (Write и Bash-record-change), и он
# не зависит от heartbeat/профиля. НЕ понижается в learn/legacy (иначе провенанс мягкий на legacy).
if git diff --cached --name-only 2>/dev/null | grep -qx "feature_list.json" && [ -f "$ROOT_DIR/feature_list.json" ]; then
  if ! COH="$(python3 - "$ROOT_DIR/feature_list.json" "$HARNESS/provenance-log.jsonl" 2>&1 <<'PY'
import json, sys, os
fl, log = sys.argv[1], sys.argv[2]
events = []
if os.path.exists(log):
    for ln in open(log, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            try: events.append(json.loads(ln))
            except Exception: pass  # рваный хвост терпим
def logmax(feat):
    s = [e.get("seq", -1) for e in events if e.get("feat") == feat and isinstance(e.get("seq"), int)]
    return max(s) if s else -1
try:
    data = json.load(open(fl, encoding="utf-8"))
except Exception:
    sys.exit(0)  # битый JSON ловит блок state-transition, не этот
bad = []
for b, feats in (data.get("features") or {}).items():
    if not isinstance(feats, list): continue
    for f in feats:
        if not isinstance(f, dict): continue
        prov = f.get("provenance")
        if not isinstance(prov, dict): continue
        hs = prov.get("seq", 0)
        if not isinstance(hs, int): hs = 0
        lm = logmax(f.get("id"))
        if hs >= 1 and lm < hs:
            bad.append("  %s: голова seq=%d впереди лога (max %d)" % (f.get("id"), hs, lm))
if bad:
    print("\n".join(bad)); sys.exit(1)
PY
  )"; then
    echo "🚨 КОММИТ ОСТАНОВЛЕН: провенанс — голова впереди лога (v8 L3-F3):" >&2
    echo "$COH" >&2
    echo "Бизнес-правку требования делай через scripts/record-change.sh (лог+голова синхронно), не руками." >&2
    echo "Расхождение «голова позади лога» после обрыва — почини: scripts/record-change.sh --recover." >&2
    exit 1
  fi
fi

# --- 5. PROVENANCE правка бизнес-поля требует событие лога (v8 L3-F4, критик b/Q9) ---
# Если у СУЩЕСТВУЮЩЕЙ фичи изменилось бизнес-поле (name/description/size_estimate/
# business_invariant/state) — в этом коммите обязано быть новое событие лога для feat,
# покрывающее изменённые поля (set-based: объединение changes-полей + подразумеваемых op→state).
# Ловит тихую правку требования в обход record-change.sh. git pre-commit — единственный, кто
# видит и старую версию (HEAD), и новую, и добавленные строки лога. Технические поля
# (affected_files/verification) — ВНЕ провенанса (не шумим).
if git diff --cached --name-only 2>/dev/null | grep -qx "feature_list.json" && [ -f "$ROOT_DIR/feature_list.json" ]; then
  OLD_FL="$(git show HEAD:feature_list.json 2>/dev/null || echo '')"
  NEW_LOG_ADDED="$(git diff --cached --unified=0 -- "$HARNESS/provenance-log.jsonl" 2>/dev/null | grep -E '^\+[^+]' | sed 's/^+//' || true)"
  if ! BIZ="$(OLD_FL="$OLD_FL" NEW_LOG_ADDED="$NEW_LOG_ADDED" python3 - "$ROOT_DIR/feature_list.json" 2>&1 <<'PY'
import json, sys, os
BIZ = {"name", "description", "size_estimate", "business_invariant", "state"}
STATE_OPS = {"REJECTED": "state", "SUPERSEDED": "state", "REOPENED": "state", "RENAMED": "name"}
def feats(d):
    out = {}
    for b, fs in (d.get("features") or {}).items():
        if isinstance(fs, list):
            for f in fs:
                if isinstance(f, dict) and f.get("id"):
                    out[f["id"]] = f
    return out
try:
    new = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
old_raw = os.environ.get("OLD_FL", "").strip()
if not old_raw:
    sys.exit(0)  # новый файл — все фичи захват, (b) не применяется
try:
    old = json.loads(old_raw)
except Exception:
    sys.exit(0)
nf, ofs = feats(new), feats(old)
cover = {}
for ln in os.environ.get("NEW_LOG_ADDED", "").splitlines():
    ln = ln.strip()
    if not ln:
        continue
    try:
        e = json.loads(ln)
    except Exception:
        continue
    feat = e.get("feat")
    if not feat:
        continue
    s = cover.setdefault(feat, set())
    for k in (e.get("changes") or {}):
        s.add(k)
    if e.get("op") in STATE_OPS:
        s.add(STATE_OPS[e["op"]])
bad = []
for fid, f in nf.items():
    of = ofs.get(fid)
    if not of:
        continue  # новая фича = захват (L3-F1), не правка
    changed = {k for k in BIZ if of.get(k) != f.get(k)}
    uncovered = changed - cover.get(fid, set())
    if uncovered:
        bad.append("  %s: изменены %s без нового события лога" % (fid, ",".join(sorted(uncovered))))
if bad:
    print("\n".join(bad)); sys.exit(1)
PY
  )"; then
    echo "🚨 КОММИТ ОСТАНОВЛЕН: провенанс — правка требования без события истории (v8 L3-F4):" >&2
    echo "$BIZ" >&2
    echo "Бизнес-поля требования (name/description/size/invariant/state) меняй через scripts/record-change.sh — оно фиксирует откуда/когда/факт замены. Технические поля (affected_files/verification) — свободно." >&2
    exit 1
  fi
fi

exit 0
