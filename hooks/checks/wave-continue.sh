#!/bin/bash
# Vibe Dev v7 (Волна 5, P6) — wave-continue: в go-режиме ход завершился ВОПРОСОМ.
#
# Пользователь явной фразой попросил не тормозить (маркер .harness/locks/go-mode ставит
# go-mode-listener). Если ПОСЛЕДНИЙ ход агента кончился «?» — это ровно боль P6 («завершил ход
# вопросом, когда сказали идти»). Inject: тех-переспрос не задавай — продолжай; БИЗНЕС-развилку
# оставь (её давить нельзя — риск проскока важной развилки перевешивает).
#
# warn/inject, НЕ block: «лишний вопрос vs развилка» механически неразрешим — не подавляем вопрос,
# а напоминаем судить по существу. Честный предел (см. workflow/enforcement-philosophy.md, класс 2).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.transcript_path). Печатает "WARN\t<msg>" или пусто. exit 0.
set -u
CWD="${1:-$PWD}"; TAB="$(printf '\t')"

[ -f "$CWD/.harness/locks/go-mode" ] || exit 0

TP="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.transcript_path // empty' 2>/dev/null)"
{ [ -n "$TP" ] && [ -f "$TP" ]; } || exit 0

# Текст ПОСЛЕДНЕГО ассистентского хода (склейка text-блоков) кончается на "?" после трима?
LAST="$(jq -rs '
  [ .[] | select(.type=="assistant") ] | last
  | (.message.content // []) | map(select(.type=="text") | .text) | join("\n")
' "$TP" 2>/dev/null)"
[ -n "$LAST" ] || exit 0
ENDQ="$(printf '%s' "$LAST" | python3 -c 'import sys; t=sys.stdin.read().strip(); print("Y" if t.endswith("?") else "N")' 2>/dev/null)"
[ "$ENDQ" = "Y" ] || exit 0

printf 'WARN%sПользователь просил не тормозить (режим «до конца»), а ход завершился вопросом. Если это ТЕХНИЧЕСКИЙ переспрос («продолжать ли?», «правильно ли иду?», «делать дальше?») — не спрашивай, продолжай следующий шаг сам. Если это БИЗНЕС-развилка (модель / цена / ICP / доступ / данные / удаление) — вопрос оставь, его давить нельзя.\n' "$TAB"
exit 0
