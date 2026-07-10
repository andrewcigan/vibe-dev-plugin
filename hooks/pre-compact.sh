#!/bin/bash
# Vibe Dev v7 (Волна 2, механизм M2) — слепок перед сжатием контекста.
#
# Событие PreCompact подтверждено ЖИВЫМ прогоном 2026-07-02 на движке 2.1.170: payload несёт
# transcript_path, файл JSONL существует, хук приходит и на manual (/compact), и на auto.
# Extractive, БЕЗ LLM/субагента (субагент из хука не зовётся): парсит транскрипт, берёт первую
# просьбу пользователя + последние просьбы + хвост хода → перезаписывает .harness/last-checkpoint.md.
# SessionStart-бриф (C1) читает этот файл и восстанавливает контекст после компакции.
#
# РАНГ (v8 L4-F3, честность деклараций c8): это СТРАХОВКА (insurance-tier) — второй эшелон под
# управляемым /checkpoint (L4-F2), а НЕ основной носитель памяти. Основной путь — файлы состояния
# через /checkpoint на естественной границе; этот слепок ловит лишь последний ход, если авто-сжатие
# («рулетка») случилось ДО чекпоинта. Логика ниже намеренно НЕ менялась (extractive, fail-open).
#
# КРИТИЧНО (поправка критики v7): пишем ФАКТЫ (что просил пользователь), НЕ статус «готово/passing» —
# статус остаётся за evidence-гейтом, иначе автопамять размножит ложь о готовности в cold-start.
#
# Фильтр шума — по ФЛАГАМ записи (type/isMeta/toolUseResult/content-тип), не по префиксу текста.
# Всегда exit 0; любая ошибка → тихий пропуск (слепок — подстраховка, не гейт; fail-open).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh" 2>/dev/null || true

IN="$(cat)"
CWD="$(printf '%s' "$IN" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$CWD" ] && CWD="$PWD"

# только vibe-проекты (как все хуки плагина)
if command -v hook_is_vibe_project >/dev/null 2>&1; then
  hook_is_vibe_project "$CWD" || exit 0
else
  { [ -d "$CWD/.harness" ] || [ -f "$CWD/feature_list.json" ]; } || exit 0
fi

TP="$(printf '%s' "$IN" | jq -r '.transcript_path // empty' 2>/dev/null)"
{ [ -n "$TP" ] && [ -f "$TP" ]; } || exit 0
TRIGGER="$(printf '%s' "$IN" | jq -r '.trigger // "?"' 2>/dev/null)"

mkdir -p "$CWD/.harness" 2>/dev/null || exit 0
OUT="$CWD/.harness/last-checkpoint.md"

python3 - "$TP" "$TRIGGER" > "$OUT.tmp" 2>/dev/null <<'PY'
import json, sys, time

tp, trigger = sys.argv[1], sys.argv[2]

def is_real_user(d):
    # реальная просьба пользователя: type=user, не meta, не результат инструмента, content — строка,
    # не служебный блок (<command-name>, <local-command-caveat>, ...).
    if d.get("type") != "user":
        return False
    if d.get("isMeta") is True:
        return False
    if d.get("toolUseResult") is not None:
        return False
    c = (d.get("message") or {}).get("content")
    if not isinstance(c, str):
        return False
    s = c.strip()
    if not s or s.startswith("<"):
        return False
    return True

def assistant_text(d):
    if d.get("type") != "assistant":
        return None
    c = (d.get("message") or {}).get("content")
    if isinstance(c, list):
        parts = [b.get("text", "") for b in c
                 if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip()]
        if parts:
            return "\n".join(parts).strip()
    return None

users, last_assist = [], None
try:
    with open(tp) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if is_real_user(d):
                users.append((d.get("message") or {}).get("content").strip())
            a = assistant_text(d)
            if a:
                last_assist = a
except Exception:
    sys.exit(0)

def trunc(s, n):
    s = " ".join(s.split())
    return s if len(s) <= n else s[:n] + "…"

ts = int(time.time())
print("<!-- vibe-dev auto-checkpoint (M2) — перезаписывается на каждом сжатии контекста -->")
print("# Слепок перед сжатием контекста — ts=%d (%s), trigger=%s"
      % (ts, time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)), trigger))
print()
print("> ФАКТЫ о ходе сессии (что просили), НЕ подтверждение готовности. "
      "Статус «сделано» — только по evidence-гейту и живой проверке.")
print()
if users:
    print("**С чего началась сессия (первая просьба):**")
    print("- " + trunc(users[0], 600))
    print()
    tail = users[1:][-4:]
    if tail:
        print("**Последние просьбы пользователя:**")
        for u in tail:
            print("- " + trunc(u, 300))
        print()
    print("_Всего реальных просьб пользователя в сессии: %d._" % len(users))
else:
    print("_Реальных просьб пользователя в транскрипте не найдено (короткая/служебная сессия)._")
if last_assist:
    print()
    print("**Последнее, что писал агент** (НЕ сверенный статус — перепроверь по живому состоянию):")
    print("> " + trunc(last_assist, 400))
PY

if [ -s "$OUT.tmp" ]; then
  mv "$OUT.tmp" "$OUT" 2>/dev/null || rm -f "$OUT.tmp"
else
  rm -f "$OUT.tmp" 2>/dev/null
fi
exit 0
