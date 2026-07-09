#!/bin/bash
# Vibe Dev v8 — Единый резолвер путей харнеса (L2-F1, spec-kit common.sh паттерн).
#
# ЕДИНСТВЕННЫЙ источник имён и путей артефактов проекта. Раньше имена файлов были
# разбросаны по хукам и скриптам (`$cwd/feature_list.json`, `$cwd/.harness/profile`, …) —
# хрупко: переименование или новый артефакт требовал правки в N местах, а неоднозначный
# корень тихо фолбэчил на cwd → запись в чужой проект (боль folder-scope).
#
# Здесь: (1) поиск корня проекта ВВЕРХ по дереву до маркера (`.harness/` или feature_list.json),
# (2) FAIL-LOUD в strict-режиме — при неоднозначном/ненайденном корне hard-error в stderr и
# ненулевой код, а НЕ тихая запись в cwd, (3) плоский контракт имён артефактов одной функцией
# на артефакт (в т.ч. новые v8: provenance-log, archive, docs/changes/<slug>).
#
# Совместимо с bash 3.2 (macOS): без `declare -A`, без `${var^^}`.
#
# Sourced из hooks/lib/hook-io.sh (доступно всем диспетчерам и checks) и напрямую из
# scripts/ (record-change.sh, checkpoint.sh) — им нужен STRICT-резолв (пишут состояние).
#
# Контракт использования:
#   root="$(vibe_resolve_root "$start_dir" strict)" || exit 1   # скрипты, пишущие состояние
#   root="$(vibe_resolve_root "$start_dir" lenient)"            # хуки (пусто → guard решает)
#   fl="$(vibe_path_feature_list "$root")"

# --- Поиск корня -----------------------------------------------------------------

# vibe_find_root <start_dir> → печатает корень (маркер .harness/ ИЛИ feature_list.json),
# поднимаясь вверх от start_dir. Возврат 1, если не найден до «/». Пусто на пустой вход.
vibe_find_root() {
  local d="${1:-}"
  [ -n "$d" ] || return 1
  # нормализуем к абсолютному пути; несуществующий каталог — не корень
  d="$(cd "$d" 2>/dev/null && pwd)" || return 1
  while [ -n "$d" ]; do
    if [ -d "$d/.harness" ] || [ -f "$d/feature_list.json" ]; then
      printf '%s' "$d"
      return 0
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  return 1
}

# vibe_resolve_root <start_dir> [strict|lenient(=default)] → печатает корень.
# Порядок разрешения (spec-kit): env VIBE_PROJECT_ROOT → поиск вверх от start → отказ.
#   strict  — не нашли ИЛИ env невалиден → hard-error в stderr + return 1 (НЕ фолбэк на cwd).
#   lenient — не нашли → пусто + return 1 (тихо; для хуков, где guard решает сам).
vibe_resolve_root() {
  local start="${1:-}" mode="${2:-lenient}" root
  if [ -n "${VIBE_PROJECT_ROOT:-}" ]; then
    if [ -d "$VIBE_PROJECT_ROOT/.harness" ] || [ -f "$VIBE_PROJECT_ROOT/feature_list.json" ]; then
      printf '%s' "$VIBE_PROJECT_ROOT"
      return 0
    fi
    if [ "$mode" = "strict" ]; then
      printf 'vibe-dev resolve-paths: VIBE_PROJECT_ROOT=«%s» не похож на vibe-проект (нет .harness/ и feature_list.json). Отказ вместо записи в неизвестное место.\n' "$VIBE_PROJECT_ROOT" >&2
      return 1
    fi
    # lenient: заданный, но невалидный env игнорируем и пробуем поиск
  fi
  root="$(vibe_find_root "$start")"
  if [ -n "$root" ]; then
    printf '%s' "$root"
    return 0
  fi
  if [ "$mode" = "strict" ]; then
    printf 'vibe-dev resolve-paths: не найден корень vibe-проекта (маркер .harness/ или feature_list.json) от «%s». Отказ вместо записи в неизвестное место — задай VIBE_PROJECT_ROOT или запусти из папки проекта.\n' "${start:-<пусто>}" >&2
    return 1
  fi
  return 1
}

# vibe_root_or_die <start_dir> → корень или процесс завершается (для скриптов состояния).
vibe_root_or_die() {
  local root
  root="$(vibe_resolve_root "${1:-$PWD}" strict)" || exit 1
  printf '%s' "$root"
}

# --- Контракт имён артефактов (единый источник) ----------------------------------
# Все принимают <root>. Плоские, без вложенности — при переименовании правим ЗДЕСЬ.

# Горячее состояние (корень проекта)
vibe_path_feature_list()      { printf '%s/feature_list.json' "$1"; }
vibe_path_archive()           { printf '%s/feature_list.archive.json' "$1"; }   # v8 L3-F5
vibe_path_session()           { printf '%s/SESSION.md' "$1"; }
vibe_path_error_journal()     { printf '%s/error-journal.md' "$1"; }
vibe_path_claude_md()         { printf '%s/CLAUDE.md' "$1"; }
vibe_path_domain_rules()      { printf '%s/domain-rules.yaml' "$1"; }

# .harness/ (служебное состояние харнеса)
vibe_path_harness_dir()       { printf '%s/.harness' "$1"; }
vibe_path_profile()           { printf '%s/.harness/profile' "$1"; }
vibe_path_hook_mode()         { printf '%s/.harness/hook-mode' "$1"; }
vibe_path_engine_version()    { printf '%s/.harness/engine-version' "$1"; }
vibe_path_heartbeat()         { printf '%s/.harness/hooks-heartbeat' "$1"; }
vibe_path_hooks_disabled()    { printf '%s/.harness/hooks-disabled' "$1"; }
vibe_path_locks_dir()         { printf '%s/.harness/locks' "$1"; }
vibe_path_checkpoint()        { printf '%s/.harness/last-checkpoint.md' "$1"; }   # v7 автопамять
vibe_path_provenance_log()    { printf '%s/.harness/provenance-log.jsonl' "$1"; } # v8 L3-F2
vibe_path_provenance_archive(){ printf '%s/.harness/provenance-log.archive.jsonl' "$1"; } # v8 снапшот лога

# docs/ (артефакты этапов; каталоги/файлы)
vibe_path_docs_dir()          { printf '%s/docs' "$1"; }
vibe_path_architecture()      { printf '%s/docs/ARCHITECTURE.md' "$1"; }
vibe_path_test_strategy()     { printf '%s/docs/test-strategy.md' "$1"; }
vibe_path_data_model_review() { printf '%s/docs/data-model-review.md' "$1"; }
vibe_path_research_dir()      { printf '%s/docs/research' "$1"; }
vibe_path_decisions_dir()     { printf '%s/docs/decisions' "$1"; }
vibe_path_changes_dir()       { printf '%s/docs/changes' "$1"; }                 # v8 L2-F2 (OpenSpec)
# vibe_path_change <root> <slug> → папка детализации конкретной фичи (docs/changes/<slug>/)
vibe_path_change()            { printf '%s/docs/changes/%s' "$1" "$2"; }
