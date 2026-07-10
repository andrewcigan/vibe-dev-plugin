#!/bin/bash
# Vibe Dev v7 (Волна 5, P6) — wave-continue + v8 (L4-F5) нудж на /checkpoint.
#
# Две независимые ветки на событии Stop:
#
# (A) НУДЖ /checkpoint (v8 L4-F5, ЧЕСТНО discipline, НЕ в enforcement-счёт). Длинная сессия
#     тяжелит контекст; надёжного хука на РАЗМЕР окна в Claude Code пока нет → прокси = число
#     ассистентских ходов в транскрипте. Каждые THRESH ходов (веха в .harness/checkpoint-nudge-at,
#     НЕ модуло — модуло отклонён в v7) — мягкое напоминание «сделай /checkpoint ДО авто-сжатия».
#     warn/inject, никогда не block. Работает НЕЗАВИСИМО от go-режима.
#
# (B) go-режим кончился ВОПРОСОМ (P6). Пользователь явной фразой попросил не тормозить (маркер
#     .harness/locks/go-mode ставит go-mode-listener). Если ПОСЛЕДНИЙ ход кончился «?» — это боль
#     P6 («завершил ход вопросом, когда сказали идти»). Inject: тех-переспрос не задавай —
#     продолжай; БИЗНЕС-развилку оставь (её давить нельзя — риск проскока перевешивает).
#
# warn/inject, НЕ block: «лишний вопрос vs развилка» механически неразрешим — не подавляем вопрос,
# а напоминаем судить по существу. Честный предел (см. workflow/enforcement-philosophy.md, класс 2).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.transcript_path). Печатает "WARN\t<msg>" или пусто. exit 0.
set -u
CWD="${1:-$PWD}"; TAB="$(printf '\t')"
CHECKPOINT_NUDGE_EVERY=50   # ходов между нуджами (прокси длины сессии; discipline-порог)

TP="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.transcript_path // empty' 2>/dev/null)"
HAVE_TP=0; { [ -n "$TP" ] && [ -f "$TP" ]; } && HAVE_TP=1

# --- (A) Нудж /checkpoint по числу ходов (независимо от go-режима) ---
if [ "$HAVE_TP" = "1" ]; then
  NTURNS="$(jq -rs '[ .[] | select(.type=="assistant") ] | length' "$TP" 2>/dev/null)"
  case "$NTURNS" in ''|*[!0-9]*) NTURNS=0 ;; esac
  NUDGE_AT="$CWD/.harness/checkpoint-nudge-at"
  LAST=0
  [ -f "$NUDGE_AT" ] && LAST="$(tr -dc '0-9' < "$NUDGE_AT" 2>/dev/null)" && LAST="${LAST:-0}"
  if [ "$NTURNS" -ge "$CHECKPOINT_NUDGE_EVERY" ] && [ "$((NTURNS - LAST))" -ge "$CHECKPOINT_NUDGE_EVERY" ]; then
    mkdir -p "$CWD/.harness" 2>/dev/null && printf '%s\n' "$NTURNS" > "$NUDGE_AT" 2>/dev/null
    printf 'WARN%sСессия длинная (%s ходов) — контекст тяжелеет. Сделай /checkpoint: зафиксируй состояние в файлы (SESSION.md → Current State, статусы+evidence в feature_list, ротация завершённого в архив) ДО того как движок сам сожмёт контекст. Управляемое сжатие надёжнее авто-порога («рулетки»); состояние останется под контролем в файлах.\n' "$TAB" "$NTURNS"
    exit 0
  fi
fi

# --- (B) go-режим + последний ход кончился вопросом ---
[ -f "$CWD/.harness/locks/go-mode" ] || exit 0
[ "$HAVE_TP" = "1" ] || exit 0

# Текст ПОСЛЕДНЕГО ассистентского хода (склейка text-блоков) кончается на "?" после трима?
LAST_TURN="$(jq -rs '
  [ .[] | select(.type=="assistant") ] | last
  | (.message.content // []) | map(select(.type=="text") | .text) | join("\n")
' "$TP" 2>/dev/null)"
[ -n "$LAST_TURN" ] || exit 0
ENDQ="$(printf '%s' "$LAST_TURN" | python3 -c 'import sys; t=sys.stdin.read().strip(); print("Y" if t.endswith("?") else "N")' 2>/dev/null)"
[ "$ENDQ" = "Y" ] || exit 0

printf 'WARN%sПользователь просил не тормозить (режим «до конца»), а ход завершился вопросом. Если это ТЕХНИЧЕСКИЙ переспрос («продолжать ли?», «правильно ли иду?», «делать дальше?») — не спрашивай, продолжай следующий шаг сам. Если это БИЗНЕС-развилка (модель / цена / ICP / доступ / данные / удаление) — вопрос оставь, его давить нельзя.\n' "$TAB"
exit 0
