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
          # hook_run_check (fail-loud): краш проверки -> WARN + crash-артефакт, не молчаливый pass.
          add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "state-transition" verdict "$ROOT/hooks/checks/state-transition.sh" "$FILE" "$CWD" "$ROOT" "$TOOL")"
        fi
        ;;
    esac
    # secret-scan (v7 P14): хардкод ЖИВОГО ключа в src -> block. Все профили (safety, как bulk-api).
    # Escape: цель .env-семейство ИЛИ маркер secret-scan-off (фраза «ключ тестовый/забей»).
    add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "secret-scan" verdict "$ROOT/hooks/checks/secret-scan-write.sh" "$CWD" "$FILE" "$TOOL")"
    # folder-scope (v7 P9): запись ВНЕ корня -> ТОЛЬКО-ЛОГ (warn лишь при маркере folder-scope-warn).
    # Все профили, безвредно: собирает корпус реальных внешних путей перед включением warn.
    add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "folder-scope" verdict "$ROOT/hooks/checks/folder-scope.sh" "$CWD" "$FILE")"
    # concurrent-write advisory для shared-форматов (json/csv/jsonl/yaml), standard/strict
    if profile_in "standard,strict" "$PROFILE"; then
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "concurrent-write" verdict "$ROOT/hooks/checks/concurrent-write.sh" "$FILE" "$CWD")"
      # model-swap-guard: правка вносит модель/настройку, влияющую на каждый вывод -> warn (smoke).
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "model-swap-guard" verdict "$ROOT/hooks/checks/model-swap-guard.sh" "$CWD")"
      # research-гейт архитектуры (F6): docs/ARCHITECTURE*.md без docs/research/*.md и без
      # хук-маркера research-skipped -> block (распоряжение пользователя 2026-06-10).
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "architecture-research" verdict "$ROOT/hooks/checks/architecture-research-gate.sh" "$FILE" "$CWD")"
    fi
    ;;
  Bash)
    # bulk-API gate активен во ВСЕХ профилях (про деньги/safety, learn-режим не понижает).
    add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "bulk-api" verdict "$ROOT/hooks/checks/bulk-api.sh" "$CWD" "$ROOT")"
    # bash-repeat (анти-залипание №2): инкремент счётчика класса команды ЗДЕСЬ — PreToolUse
    # приходит на каждый запуск; PostToolUse приходит только на успехе и сбрасывает (живая
    # модель событий 2.1.170, проверка 2026-06-10). На пороге (3-й запуск без успеха) -> warn.
    if profile_in "standard,strict" "$PROFILE"; then
      add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "bash-repeat" verdict "$ROOT/hooks/checks/bash-repeat-counter.sh" "$CWD")"
    fi
    ;;
esac

# lock-protect (F6, lock-паттерн): .harness/locks/* пишут только хуки — запись агентом
# (Write/Edit/Bash-redirect) блокируется во ВСЕХ профилях (это инфраструктура согласий).
add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "locks-protect" verdict "$ROOT/hooks/checks/locks-protect.sh" "$CWD")"

# closing-mode (F7, П6): во время закрытия сессии — деградация прав: запись только в
# state-файлы, Bash только git/read-only/скрипты плагина. standard/strict.
if profile_in "standard,strict" "$PROFILE"; then
  add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "closing-mode" verdict "$ROOT/hooks/checks/closing-mode-gate.sh" "$CWD")"
fi

# enforcement-config-protect (F9, R3): агент не ослабляет собственные гейты — правка
# profile (не-pending) / heartbeat / hooks-disabled блокируется во ВСЕХ профилях.
add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "config-protect" verdict "$ROOT/hooks/checks/enforcement-config-protect.sh" "$CWD")"

# user-rules (hookify R6/H9): правила пользователя «больше не делай X». standard/strict;
# проверка сама фильтрует по tool (Bash->command, Write/Edit/MultiEdit->file_path).
if profile_in "standard,strict" "$PROFILE"; then
  add_verdict "$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "user-rules" verdict "$ROOT/hooks/checks/user-rules.sh" "$CWD")"
fi

# --- Единый вывод. Block приоритетнее warn. ---
if [ -n "$BLOCKS" ]; then
  hook_emit_block "Vibe Dev заблокировал действие (профиль строгости: ${PROFILE}):
${BLOCKS}
Если блок ошибочен: для state-machine — это структурный инвариант (переход/JSON/UI-evidence); почини намерение, а если проект действительно legacy — переведи его на актуальный движок командой /upgrade-project. Для bulk-API — пройди .harness/pre-launch-checklist.yaml (decision.status: approved)."
fi
if [ -n "$WARNS" ]; then
  hook_emit_warn "Vibe Dev — предупреждения (действие разрешено):
${WARNS}"
fi
hook_emit_pass
