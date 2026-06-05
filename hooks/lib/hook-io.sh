#!/bin/bash
# Vibe Dev v6 — Hook I/O library (sourced диспетчерами хуков)
#
# Контракт хуков Claude Code: docs/hooks-contract-verified-2026-06-03.md
#   - Вход хука = stdin JSON (НЕ argv).
#   - Warn до модели = stdout JSON additionalContext + exit 0 (stderr на exit 0 ТЕРЯЕТСЯ).
#   - Block PreToolUse = stdout JSON permissionDecision:deny + exit 0.
#
# Совместимо с bash 3.2 (macOS): без `declare -A`, без `${var^^}`.

# Корень плагина: переменная CLAUDE_PLUGIN_ROOT (выставляет Claude Code в hook-контексте),
# иначе вычисляем от расположения этой библиотеки (hooks/lib/hook-io.sh -> корень).
_hook_io_self="${BASH_SOURCE[0]}"   # .../hooks/lib/hook-io.sh -> поднимаемся на 2 уровня до корня плагина
HOOK_IO_PLUGIN_ROOT="$(cd "$(dirname "$_hook_io_self")/../.." && pwd)"

hook_plugin_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf '%s' "$CLAUDE_PLUGIN_ROOT"
  else
    printf '%s' "$HOOK_IO_PLUGIN_ROOT"
  fi
}

# Читает весь stdin в HOOK_INPUT (вызывать один раз в начале диспетчера).
hook_read_stdin() {
  HOOK_INPUT="$(cat)"
}

# hook_field '.tool_input.file_path' -> значение поля из HOOK_INPUT (пусто если нет/ошибка).
hook_field() {
  printf '%s' "${HOOK_INPUT:-}" | jq -r "${1} // empty" 2>/dev/null
}

# Текущий профиль строгости: VIBE_DEV_PROFILE > <cwd>/.harness/profile > "standard".
hook_profile() {
  local cwd="${1:-}" p="${VIBE_DEV_PROFILE:-}"
  if [ -z "$p" ] && [ -n "$cwd" ] && [ -f "$cwd/.harness/profile" ]; then
    p="$(tr -d '[:space:]' < "$cwd/.harness/profile" 2>/dev/null)"
  fi
  printf '%s' "${p:-standard}"
}

# profile_in "minimal,standard,strict" "standard" -> 0 если профиль в списке, иначе 1.
profile_in() {
  case ",$1," in
    *",$2,"*) return 0 ;;
    *)        return 1 ;;
  esac
}

# vibe-target-проект? (есть .harness/ ИЛИ feature_list.json). Наш собственный репозиторий
# плагина под это НЕ попадает (нет .harness/ и feature_list.json) — хуки его не трогают.
hook_is_vibe_project() {
  local cwd="${1:-}"
  [ -n "$cwd" ] && { [ -d "$cwd/.harness" ] || [ -f "$cwd/feature_list.json" ]; }
}

# --- Выводы. Все завершают процесс с exit 0; полезная нагрузка — JSON на stdout. ---
# PreToolUse-функции (block/warn/pass) и Stop-функция (stop_block) разделены НАМЕРЕННО:
# формат вывода разный (permissionDecision vs decision:block), а PreToolUse-путь уже
# верифицирован на живом — не параметризуем его, чтобы не задеть. При добавлении
# UserPromptSubmit/SessionEnd — добавлять отдельную emit-функцию по их контракту.

hook_emit_block() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

hook_emit_warn() {
  jq -cn --arg c "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
  exit 0
}

hook_emit_pass() {
  exit 0
}

# Stop-блокировка (контракт §5: простой формат decision:block, НЕ permissionDecision).
# Заставляет Claude Code продолжить ход. Cap 8 (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP) — не зациклит.
hook_emit_stop_block() {
  jq -cn --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

# Inject контекста модели для событий, где stdout идёт как контекст (контракт §4:
# UserPromptSubmit / UserPromptExpansion / SessionStart). Не блокирует — добавляет текст.
# hook_emit_context <hookEventName> <text>
hook_emit_context() {
  jq -cn --arg e "$1" --arg c "$2" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
  exit 0
}

# MessageDisplay: подмена ТЕКСТА НА ЭКРАНЕ пользователя (контракт code.claude.com/docs/en/hooks:
# displayContent — только экран; оригинал сохраняется в transcript и его читает Claude).
# Честно НЕ enforcement поведения модели — только показ (флаг ловца виден пользователю).
# hook_emit_display <displayContent>
hook_emit_display() {
  jq -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"MessageDisplay", displayContent:$c}}'
  exit 0
}
