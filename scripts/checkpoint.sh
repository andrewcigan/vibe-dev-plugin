#!/bin/bash
# Vibe Dev v8 — управляемый чекпоинт вместо рулетки авто-сжатия (L4-F2, c6/c8).
#
# Курс владельца c8: авто-сжатие («компакция») — крайняя мера у самого лимита, НЕ рабочий
# инструмент. Правильно — на естественной границе (конец фичи/волны) самим зафиксировать
# состояние в файлы и разгрузить горячий контекст. Тогда порог 95% почти не достигается, а
# память под нашим управлением, а не «рулетка» движка.
#
# Что делает (механическая часть — синхронизация файлов состояния):
#   1) recovery провенанса: голова отстала от лога после обрыва → пересобрать (record-change --recover).
#   2) ротация завершённых (done/superseded/rejected с evidence) в архив по ссылке (archive-features.sh).
#   3) COLD-START GATE (enforce): состояние ДОЛЖНО быть в файлах, а не только в контексте
#      (механизирует правило 4 «план только через файлы»). Провал → exit 1, /checkpoint НЕ завершён.
#
# Честная граница (тест 3 атрибутов): скрипт НЕ видит контекст агента, поэтому enforce'ит
# СТРУКТУРНУЮ полноту (SESSION.md не шаблонный + провенанс когерентен). Семантическую сверку
# «есть ли решение в голове, которого нет в файлах» несёт чеклист скилла (skills/checkpoint) —
# это discipline, скрипт её физически не может. Мы не приписываем скрипту больше, чем он делает.
#
# Использование: bash scripts/checkpoint.sh [<путь-проекта>]
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh"

ROOT="$(vibe_resolve_root "${1:-$PWD}" strict)" || exit 1
SESSION="$(vibe_path_session "$ROOT")"
FL="$(vibe_path_feature_list "$ROOT")"
LOG="$(vibe_path_provenance_log "$ROOT")"

echo "· checkpoint в $ROOT"

# --- 1. Recovery провенанса (best-effort; голова-позади после обрыва → пересобрать из лога) ---
if [ -f "$LOG" ] && [ -f "$DIR/record-change.sh" ]; then
  REC="$(bash "$DIR/record-change.sh" --recover --project "$ROOT" 2>&1)" && \
    { [ -n "$REC" ] && echo "  провенанс: $REC" || true; } || \
    echo "  ⚠ провенанс recovery не отработал (не блокирует): $REC" >&2
fi

# --- 2. Ротация завершённых в архив по ссылке (разгрузка горячего контекста, c3) ---
if [ -f "$FL" ] && [ -f "$DIR/archive-features.sh" ]; then
  ARC="$(bash "$DIR/archive-features.sh" "$ROOT" 2>&1)" && \
    echo "  архив: $ARC" || echo "  ⚠ ротация архива не отработала (не блокирует): $ARC" >&2
fi

# --- 3. COLD-START GATE (enforce — block завершения /checkpoint) ---
GATE="$(SESSION="$SESSION" FL="$FL" LOG="$LOG" python3 - <<'PY' 2>&1
import json, os, re, sys

session, fl, log = os.environ["SESSION"], os.environ["FL"], os.environ["LOG"]
blocks = []

# (a) SESSION.md существует и Current State не шаблонный
if not os.path.exists(session):
    blocks.append("нет SESSION.md — текущее состояние живёт только в контексте, не в файлах")
else:
    txt = open(session, encoding="utf-8").read()
    if "## Current State" not in txt:
        blocks.append("в SESSION.md нет блока '## Current State' — перезапиши его (c6 overwrite)")
    # литеральные плейсхолдеры шаблона = SESSION.md не обновляли в этой сессии
    def field(name):
        m = re.search(r'\*\*%s\*\*:\s*(.+)' % re.escape(name), txt)
        return (m.group(1).strip() if m else None)
    lu = field("Last Updated")
    if lu is None or "YYYY-MM-DD" in lu:
        blocks.append("'Last Updated' в SESSION.md пустой/шаблонный (YYYY-MM-DD) — проставь дату этой сессии")
    af = field("Active Feature")
    if af is not None and "feat-XXX" in af:
        blocks.append("'Active Feature' в SESSION.md шаблонный ([feat-XXX …]) — впиши реальную фичу или 'нет активной'")

# (b) провенанс когерентен: голова НЕ впереди лога (иначе правка мимо record-change.sh / потеря события)
if os.path.exists(fl):
    try:
        data = json.load(open(fl, encoding="utf-8"))
    except Exception:
        data = None
    if isinstance(data, dict):
        events = []
        if os.path.exists(log):
            for ln in open(log, encoding="utf-8"):
                ln = ln.strip()
                if ln:
                    try: events.append(json.loads(ln))
                    except Exception: pass
        def logmax(feat):
            s = [e.get("seq", -1) for e in events if e.get("feat") == feat and isinstance(e.get("seq"), int)]
            return max(s) if s else -1
        for _b, feats in (data.get("features") or {}).items():
            if not isinstance(feats, list): continue
            for f in feats:
                if not isinstance(f, dict): continue
                prov = f.get("provenance")
                if not isinstance(prov, dict): continue
                hs = prov.get("seq", 0)
                if not isinstance(hs, int): hs = 0
                if hs >= 1 and logmax(f.get("id")) < hs:
                    blocks.append("провенанс %s: голова seq=%d впереди лога — почини record-change.sh --recover" % (f.get("id"), hs))

if blocks:
    print("\n".join("  ✗ " + b for b in blocks))
    sys.exit(1)
sys.exit(0)
PY
)"
GATE_RC=$?

if [ "$GATE_RC" -ne 0 ]; then
  cat >&2 <<EOF

🛑 CHECKPOINT НЕ ЗАВЕРШЁН: состояние ещё не в файлах (v8 L4-F2, правило 4).
$GATE
Чат между сессиями НЕ передаётся. Зафиксируй перечисленное в файлы (SESSION.md Current State,
feature_list.json, docs/decisions/), затем повтори /checkpoint. Иначе следующая сессия
восстановит план НЕ полностью — ровно та боль, ради которой чекпоинт и делается.
EOF
  exit 1
fi

# --- 4. Cold-start self-test (discipline-сверка агентом — скрипт её не заменяет) ---
cat <<'EOF'
  ✓ структура состояния в файлах (SESSION.md заполнен, провенанс когерентен)

Cold-start self-test (СВЕРЬ по ФАЙЛАМ, не по памяти — ответ должен быть в репозитории):
  1. Что это за продукт?                        → CLAUDE.md / docs/PRODUCT.md
  2. Активная фича + verification_command?      → feature_list.json / SESSION.md
  3. Последние 3 решения и почему?              → SESSION.md / docs/decisions/
  4. Что дальше (следующий шаг)?                → SESSION.md → What's Next
  5. Что НЕ делать (anti-patterns)?             → error-journal.md / domain-rules.yaml

⚠ Если хоть один ответ есть только в контексте (не в файлах) — допиши в файл ДО разгрузки.
✓ Если все пять восстановимы из файлов — контекст можно смело сжимать/начинать заново.
EOF
echo "✓ checkpoint готов."
