#!/bin/bash
# Vibe Dev v7 (Волна 3, P9) — folder-scope: запись ВНЕ корня проекта.
#
# v8 L5-F3: промоушн ТОЛЬКО-ЛОГ → WARN (средний шаг). Корпус реальных внешних путей набран в
# режиме лога; теперь запись вне корня даёт видимое предупреждение (не блок). Полный block
# ОТЛОЖЕН до замера % ложных на корпусе .harness/folder-scope.log (риск заблокировать легитимную
# запись, в т.ч. ротацию архива L3-F5). Только структурный tool_input.file_path (НЕ греп пути из
# тела Bash: критик вживую словил ложный блок на echo с путём в кавычках). READ вне корня НЕ
# трогаем (гнев пользователя был только про ЗАПИСЬ прототипов не туда).
#
# Whitelist: корень проекта; ВСЕ git-worktree проекта; системный scratchpad/tmp; ~/.vibe-dev; ~/.claude.
# Аргументы: $1=cwd, $2=file_path. WARN по умолчанию при записи вне корня/whitelist + лог в
# .harness/folder-scope.log (корпус для будущего промоушна до block). Всегда exit 0.
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

# Вне корня и вне whitelist → WARN + лог (корпус остаётся — база для будущего промоушна до block).
# v8 L5-F3: промоушн log-only → WARN (средний шаг). block ОТЛОЖЕН до замера % ложных на
# накопленном .harness/folder-scope.log; warn безопасен (не рвёт поток), но виден и собирает данные.
mkdir -p "$CWD/.harness" 2>/dev/null
printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$ABS" >> "$CWD/.harness/folder-scope.log" 2>/dev/null || true
printf 'WARN%sЗапись ВНЕ корня проекта: %s. Прототипы/выгрузки/отчёты держи в корне проекта (git-worktree и системный /tmp — исключения). Если намеренно — продолжай (это предупреждение, не блок).\n' "$TAB" "$ABS"
exit 0
