#!/bin/bash
# Vibe Dev v6 — handoff-pending probe (вызывается hooks/dispatch-session-start.sh на SessionStart). H6.
#
# Замыкает loop H6: UserPromptSubmit при сигнале завершения ставит маркер .harness/handoff-pending;
# при следующем старте сессии этот probe сравнивает mtime(SESSION.md) vs mtime(маркер):
#   - SESSION.md новее маркера -> handoff обновлён ПОСЛЕ сигнала -> тихо снять маркер (OK);
#   - SESSION.md старше/нет     -> handoff мог НЕ записаться -> WARN.
# Маркер снимается в любом случае (одноразовое напоминание). Закрывает паттерн «handoff через слова вместо файлов» — детекция постфактум.
#
# Печатает на stdout "WARN<TAB>msg" или пусто. Всегда guard_done.

set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"

CWD="${1:-$PWD}"
TAB="$(printf '\t')"

MARKER="$CWD/.harness/handoff-pending"
[ ! -f "$MARKER" ] && guard_done

SESSION="$CWD/SESSION.md"
if [ -f "$SESSION" ] && [ "$SESSION" -nt "$MARKER" ]; then
  rm -f "$MARKER"   # SESSION.md обновлён после сигнала закрытия — handoff сделан, тихо снять
  guard_done
fi

rm -f "$MARKER"     # одноразовое напоминание (не зацикливаем на каждый старт)
printf 'WARN%sПрошлая сессия сигналила завершение, но SESSION.md не обновлялся после этого — handoff мог не записаться (план рискует жить только в чате прошлой сессии). Перед работой проверь актуальность SESSION.md (раздел NEXT), feature_list.json и memory; если план пропущен — восстанови его в файлы прежде чем продолжать.\n' "$TAB"
guard_done
