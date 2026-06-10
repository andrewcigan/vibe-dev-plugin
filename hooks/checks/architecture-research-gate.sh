#!/bin/bash
# Vibe Dev v6.2 — research-гейт архитектуры (F6; прямое распоряжение пользователя 2026-06-10:
# «всегда детальный рисёрч best practices + GitHub-репо архитектуры; пропуск — только если
# пользователь явно скажет; плагин не для программистов — цена архитектурной ошибки высокая»).
#
# Блокирует запись docs/ARCHITECTURE*.md (глоб — вариант имени не обходит chokepoint), пока:
#   - НЕТ ни одного docs/research/*.md (артефакт рисёрча), И
#   - НЕТ маркера .harness/locks/research-skipped (его ставит ТОЛЬКО хук по явной фразе).
# Паттерн идентичен vendor-lock гейту (research перед integration-фичей).
#
# Аргументы: $1=file_path, $2=cwd. Печатает "BLOCK\tmsg", пусто = ОК. exit 0.

set -u
FILE="${1:-}"
CWD="${2:-$PWD}"
TAB="$(printf '\t')"

# Срабатываем только на docs/ARCHITECTURE*.md (любой вариант имени).
case "$FILE" in
  */docs/ARCHITECTURE*.md|docs/ARCHITECTURE*.md) : ;;
  *) exit 0 ;;
esac

# Артефакт рисёрча есть?
if [ -d "$CWD/docs/research" ] && ls "$CWD/docs/research"/*.md >/dev/null 2>&1; then
  exit 0
fi
# Явный пропуск зафиксирован хуком?
if [ -f "$CWD/.harness/locks/research-skipped" ]; then
  exit 0
fi

printf 'BLOCK%sАрхитектура БЕЗ рисёрча: нет docs/research/*.md и нет явного пропуска. Перед docs/ARCHITECTURE*.md запусти ПАРАЛЛЕЛЬНО агентов github-researcher + best-practices-researcher → сведи в docs/research/architecture-research.md (глубина по размеру проекта: S — короткий обзор, M/L — полный). Пропустить можно ТОЛЬКО явной фразой пользователя («пропусти рисёрч») — хук сам поставит маркер. Это правило владельца плагина: цена архитектурной ошибки для непрограммиста выше цены рисёрча.\n' "$TAB"
exit 0
