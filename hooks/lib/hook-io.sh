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

# Единый резолвер путей артефактов проекта (v8 L2-F1). Sourced здесь → функции vibe_path_*
# и vibe_resolve_root доступны всем диспетчерам и checks, которые подключают hook-io.
. "$(dirname "$_hook_io_self")/resolve-paths.sh"

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
# Двухфазная активация (v6.2 F2): bootstrap пишет "pending-<профиль>"; в боевой профиль
# переводит ТОЛЬКО живой хук (hook_activate_pending_profile) — факт перевода = доказательство
# активации. Для САМИХ хуков pending-X читается как X (хук работает, раз читает — окна
# слабости нет); внешние читатели (git pre-commit backstop, /doctor, скиллы) трактуют
# pending как «активация НЕ подтверждена» и кричат.
hook_profile() {
  local cwd="${1:-}" p="${VIBE_DEV_PROFILE:-}" pf
  if [ -z "$p" ] && [ -n "$cwd" ]; then
    pf="$(vibe_path_profile "$cwd")"
    if [ -f "$pf" ]; then
      p="$(tr -d '[:space:]' < "$pf" 2>/dev/null)"
    fi
  fi
  p="${p:-standard}"
  case "$p" in pending-*) p="${p#pending-}" ;; esac
  printf '%s' "$p"
}

# Версия плагина из манифеста (для heartbeat/диагностики). Пусто недопустимо -> "?".
hook_plugin_version() {
  local pj="$(hook_plugin_root)/.claude-plugin/plugin.json" v=""
  [ -f "$pj" ] && v="$(jq -r '.version // empty' "$pj" 2>/dev/null)"
  printf '%s' "${v:-?}"
}

# Канал доставки правок (v7): нудит /upgrade-project ТОЛЬКО функционально-МЯГКИЕ (legacy) проекты —
# нет .harness/engine-version ЛИБО его major < 6. Пин 6.x/7.x уже строгий (legacy-порог — major≥6),
# его НЕ нудим (анти-шум: бамп версии плагина не должен трогать уже-строгие проекты).
# ВАЖНО: новые механизмы v7 применяются НЕЗАВИСИМО от пина (хуки грузятся из CLAUDE_PLUGIN_ROOT);
# пин гейтит ТОЛЬКО строгость state-machine (legacy=warn vs strict=block). Fail-safe: нечитаемо → молчим.
hook_upgrade_nudge() {
  local cwd="${1:-}" ev pin pin_major
  [ -n "$cwd" ] || return 0
  ev="$(vibe_path_engine_version "$cwd")"
  if [ -f "$ev" ]; then
    pin="$(tr -d '[:space:]' < "$ev" 2>/dev/null)"
    pin_major="${pin%%.*}"
    case "$pin_major" in ''|*[!0-9]*) return 0 ;; esac   # нечитаемый пин — молчим (fail-safe)
    [ "$pin_major" -ge 6 ] 2>/dev/null && return 0        # major≥6 = уже строгий → тишина
    # major < 6 → legacy, нудим ниже
  fi
  # нет файла ЛИБО major<6 → мягкий режим
  printf '⚠️ Vibe Dev: проект в МЯГКОМ режиме (движок не закреплён или устарел) — структурные проверки только предупреждают, не блокируют. Прогони /upgrade-project, чтобы включить полную строгость (dry-run проверит, что текущее состояние пройдёт).'
}

# C1 (v7 Волна 2, автопамять): бриф возврата на SessionStart. Собирает активные фичи +
# наличие недавних ошибок + наличие слепка сжатия в компактный блок и ОБЯЗАТЕЛЬНО завершает
# recall-фразой (без неё агент инъекцию игнорирует — verified-паттерн basic-memory).
# Пишет ФАКТЫ + «перепроверь по живому», НЕ статус «готово» (иначе размножит ложь о готовности).
# Пусто, если возвращать нечего (чистый старт). Fail-safe: любая ошибка → меньше текста.
hook_cold_start_brief() {
  local cwd="${1:-}" fl active errj ckpt body=""
  [ -n "$cwd" ] || return 0
  fl="$(vibe_path_feature_list "$cwd")"
  if [ -f "$fl" ]; then
    active="$(jq -r '
      (.features // {}) | to_entries[]? | .value | if type=="array" then .[] else empty end
      | select((.state // "") == "active")
      | "  • " + ((.id // "?")|tostring) + ": " + (((.title // .name // .goal // .behavior // .description // "") | tostring)[0:80])
    ' "$fl" 2>/dev/null | head -8)"
  fi
  errj=""; [ -f "$(vibe_path_error_journal "$cwd")" ] && errj="yes"
  ckpt=""; [ -f "$(vibe_path_checkpoint "$cwd")" ] && ckpt="yes"
  [ -n "$active" ] || [ -n "$errj" ] || [ -n "$ckpt" ] || return 0

  body="🧭 Vibe Dev — бриф возврата (ФАКТЫ; статус «готово» перепроверь по живому, не по памяти):"
  if [ -n "$active" ]; then
    body="$body
В работе сейчас (feature_list.json, state=active):
$active"
  fi
  [ -n "$ckpt" ] && body="$body
• Есть слепок последнего сжатия контекста: .harness/last-checkpoint.md — что просили до компакции."
  [ -n "$errj" ] && body="$body
• Недавние тупики — в error-journal.md: прочти, чтобы не повторить отвергнутые попытки."
  body="$body

Прежде чем продолжать — открой и сверься: feature_list.json (что в работе), SESSION.md (состояние), error-journal.md (тупики). Не доверяй памяти о готовности: «сделано» = evidence-гейт прошёл и поведение проверено вживую."
  printf '%s' "$body"
}

# Heartbeat активации (v6.2 F2): каждый вызов пишущего события подтверждает «хуки физически
# работают». Пишут SessionStart и UserPromptSubmit (раз в ход достаточно). Формат строки:
# "<unix-ts> plugin=<версия>". Читатели сравнивают ts с now (TTL), а не mtime — надёжнее.
hook_write_heartbeat() {
  local cwd="${1:-}"
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  mkdir -p "$(vibe_path_harness_dir "$cwd")" 2>/dev/null || return 0
  printf '%s plugin=%s\n' "$(date +%s)" "$(hook_plugin_version)" > "$(vibe_path_heartbeat "$cwd")" 2>/dev/null || true
}

# Перевод pending-профиля в боевой. Возвращает (stdout) активированный профиль, если перевод
# случился, иначе пусто. Вызывается из SessionStart и UserPromptSubmit диспетчеров.
hook_activate_pending_profile() {
  local cwd="${1:-}" pf p
  pf="$(vibe_path_profile "$cwd")"
  [ -f "$pf" ] || return 0
  p="$(tr -d '[:space:]' < "$pf" 2>/dev/null)"
  case "$p" in
    pending-*)
      printf '%s\n' "${p#pending-}" > "$pf" 2>/dev/null || return 0
      printf '%s' "${p#pending-}"
      ;;
  esac
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

# Stop additionalContext (мягкий канал, движок >= 2.1.163): фидбек модели без block и без
# пометки hook-error. На старых движках поле молча игнорируется (безопасная деградация).
# hook_emit_stop_context <text>
hook_emit_stop_context() {
  jq -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$c}}'
  exit 0
}

# --- Fail-loud запуск дочерней проверки (v6.2 F1; урок бага 2026-06-06). ---
# Раньше диспетчеры звали проверки `$(bash check.sh ... 2>/dev/null)`: краш проверки давал
# пустой stdout -> «возражений нет» -> молчаливый fail-open ФЛАГМАНСКОГО гейта.
# Теперь: exit != 0 у проверки -> (1) crash-артефакт .harness/hook-crashes/<label>.log
# (последний краш каждой проверки; виден SessionStart-probe и /doctor), (2) к выводу
# добавляется громкое предупреждение — в формате канала.
#
# hook_run_check <cwd> <label> <format: verdict|text> <script> [args...]
#   verdict — каналы строк "VERDICT\tmsg" (PreToolUse/Stop/SessionStart-probe): добавляет WARN-строку.
#   text    — inject-каналы (UserPromptSubmit/PostToolUse/MessageDisplay): добавляет абзац.
# stdout проверки возвращается как раньше (прозрачно для здоровых проверок).
hook_run_check() {
  local _cwd="$1" _label="$2" _format="$3"; shift 3
  local _out _rc _errfile _err
  _errfile="$(mktemp 2>/dev/null || printf '/tmp/vibe-hook-err.%s' "$$")"
  _out="$(bash "$@" 2>"$_errfile")"; _rc=$?
  if [ "$_rc" -ne 0 ]; then
    _err="$(head -c 300 "$_errfile" 2>/dev/null | tr '\n\t' '  ')"
    if [ -n "$_cwd" ] && [ -d "$_cwd" ]; then
      mkdir -p "$_cwd/.harness/hook-crashes" 2>/dev/null
      {
        printf 'when: %s\ncheck: %s\nexit: %s\nstderr:\n' \
          "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')" "$_label" "$_rc"
        cat "$_errfile" 2>/dev/null
      } > "$_cwd/.harness/hook-crashes/${_label}.log" 2>/dev/null
    fi
    local _msg="сторож «${_label}» УПАЛ (exit ${_rc}: ${_err:-нет stderr}) и НЕ выполнил проверку — действие им не проверено. Проверь вручную то, что он сторожит. Диагностика: .harness/hook-crashes/${_label}.log; почини причину или сообщи о баге плагина."
    if [ "$_format" = "text" ]; then
      if [ -n "$_out" ]; then _out="${_out}

⚠️ ${_msg}"; else _out="⚠️ ${_msg}"; fi
    else
      _out="${_out}
WARN	${_msg}"
    fi
  fi
  rm -f "$_errfile" 2>/dev/null
  printf '%s' "$_out"
}
