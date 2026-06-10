#!/bin/bash
# Vibe Dev v6.2 — ЕДИНЫЙ Stop dispatcher (F3). На событии Stop живёт несколько сторожей —
# без единой точки они каскадят блоки и зацикливают ход. Здесь: приоритеты + общий cap.
#
# Приоритеты (один block за раз; после доделки Stop сработает снова и проверит заново):
#   1. stop-intent (H19): обещал действие, не сделал -> заставить ДОДЕЛАТЬ (block).
#   2. clarity-gate (F4): сообщение непонятно пользователю -> короткий аддендум (block).
#   3. (v6.3, слот) wave-continue: прогон утверждённого блока фич. Пререквизит — passthrough
#      вопросов: ход с вопросом пользователю wave НЕ продолжает (HALT, не давим вопрос).
#
# Общий cap: ≤3 block на цепочку хода (свой, ниже системного cap 8). Цепочка = от промпта
# пользователя до промпта (UserPromptSubmit-диспетчер сбрасывает счётчик). При переполнении —
# pass с записью в .harness/stop-cap-log (видно /audit), НЕ бесконечная переписка.
#
# Активен standard,strict. Контракт Stop: decision:block / additionalContext (>=2.1.163).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

# Guard: только vibe-target-проекты.
hook_is_vibe_project "$CWD" || hook_emit_pass

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
profile_in "standard,strict" "$PROFILE" || hook_emit_pass

# --- Общий cap цепочки Stop-блоков ---
CHAIN_FILE="$CWD/.harness/stop-chain-count"
CHAIN=0
if [ -f "$CHAIN_FILE" ]; then
  CHAIN="$(tr -dc '0-9' < "$CHAIN_FILE" 2>/dev/null)"
  CHAIN="${CHAIN:-0}"
fi

# emit_capped_block <reason> — block с учётом общего cap (3 на цепочку хода).
emit_capped_block() {
  if [ "$CHAIN" -ge 3 ]; then
    mkdir -p "$CWD/.harness" 2>/dev/null
    printf '%s\tcap-pass\t%s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$1" \
      >> "$CWD/.harness/stop-cap-log" 2>/dev/null
    hook_emit_pass
  fi
  mkdir -p "$CWD/.harness" 2>/dev/null
  printf '%s\n' "$((CHAIN + 1))" > "$CHAIN_FILE" 2>/dev/null
  hook_emit_stop_block "$1"
}

WARNS=""

# --- Приоритет 1: stop-intent (H19) — обещание действия без tool_use ---
# hook_run_check (fail-loud): краш проверки -> WARN-строка + crash-артефакт.
VERDICT="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "stop-intent" verdict "$ROOT/hooks/checks/stop-intent-without-action.sh" "$CWD")"
BLOCK_MSG="$(printf '%s' "$VERDICT" | awk -F'\t' '$1=="BLOCK"{print $2; exit}')"
if [ -n "$BLOCK_MSG" ]; then
  emit_capped_block "Vibe Dev (профиль ${PROFILE}): ${BLOCK_MSG}"
fi
W="$(printf '%s' "$VERDICT" | awk -F'\t' '$1=="WARN"{print $2; exit}')"
[ -n "$W" ] && WARNS="$W"

# --- Приоритет 2: clarity-gate (F4) — ясность финального сообщения ---
# Боль №1 аудита: жаргон / развилки без рекомендации / человеко-дни доходили до пользователя.
# BLOCK -> агент дописывает короткий аддендум (не переписывает всё). Tiered по precision.
CL_VERDICT="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "clarity-gate" verdict "$ROOT/hooks/checks/clarity-stop-gate.sh" "$CWD" "$PROFILE")"
CL_BLOCK="$(printf '%s' "$CL_VERDICT" | awk -F'\t' '$1=="BLOCK"{print $2; exit}')"
if [ -n "$CL_BLOCK" ]; then
  emit_capped_block "Vibe Dev (clarity-gate, профиль ${PROFILE}): ${CL_BLOCK}"
fi
CW="$(printf '%s' "$CL_VERDICT" | awk -F'\t' '$1=="WARN"{print $2; exit}')"
if [ -n "$CW" ]; then
  if [ -n "$WARNS" ]; then WARNS="$WARNS
$CW"; else WARNS="$CW"; fi
fi

# --- Приоритет 3 (v6.3): wave-continue — слот. Пререквизит: passthrough вопросов. ---

# WARN'ы (например, краш проверки) -> мягкий additionalContext (>=2.1.163; старые движки игнорируют).
if [ -n "$WARNS" ]; then
  hook_emit_stop_context "Vibe Dev: ${WARNS}"
fi
hook_emit_pass
