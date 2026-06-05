#!/bin/bash
# Vibe Dev v6 — PreToolUse dispatcher (единая точка входа на событие PreToolUse).
#
# Поток: stdin JSON -> разбор полей -> guard (vibe-проект?) -> профиль -> роутинг по tool_name
#        -> сбор вердиктов проверок -> ОДИН stdout JSON (block | warn) или тихий pass.
#
# Проверки (hooks/checks/*.sh) печатают строки "<VERDICT><TAB><msg>" (BLOCK|WARN), пусто = OK.
# Диспетчер — единственное место, которое реально эмитит ответ Claude Code.
#
# Контракт: docs/hooks-contract-verified-2026-06-03.md

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
TOOL="$(hook_field '.tool_name')"
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"
FILE="$(hook_field '.tool_input.file_path')"

# Guard: трогаем только vibe-target-проекты (есть .harness/ или feature_list.json).
hook_is_vibe_project "$CWD" || hook_emit_pass

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"
TAB="$(printf '\t')"

BLOCKS=""
WARNS=""

# add_verdict <multiline-output-проверки> — раскладывает строки по аккумуляторам.
# Используется heredoc (не pipe) чтобы переменные остались в текущем shell (bash 3.2).
add_verdict() {
  local _v _m
  while IFS="$TAB" read -r _v _m; do
    [ -z "$_v" ] && continue
    case "$_v" in
      BLOCK) BLOCKS="${BLOCKS}- ${_m}
" ;;
      WARN)  WARNS="${WARNS}- ${_m}
" ;;
    esac
  done <<EOF
$1
EOF
}

# --- Роутинг ---
case "$TOOL" in
  Write|Edit|MultiEdit)
    case "$FILE" in
      *feature_list.json)
        if profile_in "standard,strict" "$PROFILE"; then
          # HOOK_PAYLOAD прокидывает намерение (tool_input.content/old_string/edits) в проверку,
          # чтобы валидировать то, что записывается, а не старое состояние диска.
          add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/state-transition.sh" "$FILE" "$CWD" "$ROOT" "$TOOL" 2>/dev/null)"
        fi
        ;;
    esac
    # concurrent-write advisory для shared-форматов (json/csv/jsonl/yaml), standard/strict
    if profile_in "standard,strict" "$PROFILE"; then
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/concurrent-write.sh" "$FILE" "$CWD" 2>/dev/null)"
      # model-swap-guard: правка вносит модель/настройку, влияющую на каждый вывод -> warn (smoke).
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/model-swap-guard.sh" "$CWD" 2>/dev/null)"
    fi
    ;;
  Bash)
    # bulk-API gate активен во ВСЕХ профилях (про деньги/safety, learn-режим не понижает).
    add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/bulk-api.sh" "$CWD" "$ROOT" 2>/dev/null)"
    ;;
esac

# user-rules (hookify R6/H9): правила пользователя «больше не делай X». standard/strict;
# проверка сама фильтрует по tool (Bash->command, Write/Edit/MultiEdit->file_path).
if profile_in "standard,strict" "$PROFILE"; then
  add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/user-rules.sh" "$CWD" 2>/dev/null)"
fi

# --- Единый вывод. Block приоритетнее warn. ---
if [ -n "$BLOCKS" ]; then
  hook_emit_block "Vibe Dev заблокировал действие (профиль строгости: ${PROFILE}):
${BLOCKS}
Если блок ошибочен: для state-machine — осознанная миграция legacy через 'echo learn > .harness/hook-mode'; для bulk-API — пройди .harness/pre-launch-checklist.yaml (decision.status: approved)."
fi
if [ -n "$WARNS" ]; then
  hook_emit_warn "Vibe Dev — предупреждения (действие разрешено):
${WARNS}"
fi
hook_emit_pass
