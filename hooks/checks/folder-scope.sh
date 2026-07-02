#!/bin/bash
# Vibe Dev v7 (Волна 3, P9) — folder-scope: запись ВНЕ корня проекта.
#
# СТАРТ в режиме ТОЛЬКО-ЛОГ (собрать корпус реальных внешних путей записи ПЕРЕД включением warn —
# главный нетто-риск P9). Только структурный tool_input.file_path (НЕ греп пути из тела Bash:
# критик вживую словил ложный блок на echo с путём в кавычках). READ вне корня НЕ трогаем
# (гнев пользователя был только про ЗАПИСЬ прототипов не туда).
#
# Whitelist: корень проекта; ВСЕ git-worktree проекта; системный scratchpad/tmp; ~/.vibe-dev; ~/.claude.
# Аргументы: $1=cwd, $2=file_path. WARN печатает ТОЛЬКО при маркере .harness/folder-scope-warn;
# иначе тихо пишет в .harness/folder-scope.log. Всегда exit 0.
set -u
CWD="${1:-$PWD}"; FILE="${2:-}"; TAB="$(printf '\t')"
[ -n "$FILE" ] || exit 0

case "$FILE" in
  /*) ABS="$FILE" ;;
  *)  ABS="$CWD/$FILE" ;;
esac

# Быстрый путь: внутри корня проекта — ок (самый частый случай, дешёвый выход).
case "$ABS" in
  "$CWD"/*|"$CWD") exit 0 ;;
esac

# Whitelist системных зон записи.
case "$ABS" in
  /tmp/*|/private/tmp/*|/var/folders/*) exit 0 ;;
  "$HOME"/.vibe-dev/*|"$HOME"/.claude/*) exit 0 ;;
esac

# Whitelist ВСЕХ git-worktree проекта (не только основного).
if command -v git >/dev/null 2>&1; then
  WT="$(git -C "$CWD" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')"
  if [ -n "$WT" ]; then
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      case "$ABS" in "$w"/*|"$w") exit 0 ;; esac
    done <<EOF
$WT
EOF
  fi
fi

# Вне корня и вне whitelist → лог (корпус). Warn — только по явному маркеру (после обкатки).
mkdir -p "$CWD/.harness" 2>/dev/null
printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$ABS" >> "$CWD/.harness/folder-scope.log" 2>/dev/null || true
if [ -f "$CWD/.harness/folder-scope-warn" ]; then
  printf 'WARN%sЗапись ВНЕ корня проекта: %s. Прототипы/выгрузки/отчёты держи в корне проекта (worktree и системный /tmp — исключения). Если это намеренно — продолжай.\n' "$TAB" "$ABS"
fi
exit 0
