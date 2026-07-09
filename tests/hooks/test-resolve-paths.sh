#!/bin/bash
# Vibe Dev v8 — тест единого резолвера путей (L2-F1).
#
# Контракты:
#   - vibe_find_root поднимается вверх до маркера (.harness/ ИЛИ feature_list.json);
#   - strict вне проекта → hard-error (stderr + ненулевой код), НЕ тихий фолбэк на cwd;
#   - lenient вне проекта → пусто + ненулевой код (тихо);
#   - VIBE_PROJECT_ROOT перебивает поиск; невалидный env в strict → hard-error;
#   - функции vibe_path_* дают единый контракт имён артефактов.
#
# Запуск: bash tests/hooks/test-resolve-paths.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$PLUGIN_ROOT/hooks/lib/resolve-paths.sh"
PASS=0; FAIL=0

unset VIBE_PROJECT_ROOT 2>/dev/null || true
. "$LIB"

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

eq() { # eq <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал: [$2]  получил: [$3]"; fi
}

echo "Resolve-paths (L2-F1) — сценарии:"

# --- Песочница: корень с .harness/ + вложенные папки ---
ROOT="$(mktemp -d)"
mkdir -p "$ROOT/.harness" "$ROOT/a/b/c"
# симлинки /tmp → /private/tmp на macOS: нормализуем эталон тем же cd/pwd
ROOT_REAL="$(cd "$ROOT" && pwd)"

# 1. Поиск корня из глубоко вложенной папки
OUT="$(vibe_find_root "$ROOT/a/b/c")"
eq "1. find_root из вложенной a/b/c → корень" "$ROOT_REAL" "$OUT"

# 2. Поиск корня из самого корня
OUT="$(vibe_find_root "$ROOT")"
eq "2. find_root из корня → корень" "$ROOT_REAL" "$OUT"

# 3. Маркер feature_list.json (без .harness/) тоже находится
ROOT2="$(mktemp -d)"; mkdir -p "$ROOT2/sub"; echo '{}' > "$ROOT2/feature_list.json"
ROOT2_REAL="$(cd "$ROOT2" && pwd)"
OUT="$(vibe_find_root "$ROOT2/sub")"
eq "3. find_root по маркеру feature_list.json" "$ROOT2_REAL" "$OUT"

# 4. resolve_root strict из вложенной → корень, код 0
OUT="$(vibe_resolve_root "$ROOT/a/b/c" strict 2>/dev/null)"; RC=$?
eq "4a. resolve strict → корень" "$ROOT_REAL" "$OUT"
eq "4b. resolve strict → код 0" "0" "$RC"

# 5. strict ВНЕ проекта → hard-error: ненулевой код + непустой stderr, пустой stdout
NOPROJ="$(mktemp -d)"   # без .harness и feature_list.json
ERRF="$(mktemp)"
OUT="$(vibe_resolve_root "$NOPROJ" strict 2>"$ERRF")"; RC=$?
if [ "$RC" -ne 0 ]; then ok "5a. strict вне проекта → ненулевой код"; else bad "5a. strict вне проекта → ненулевой код" "код=$RC"; fi
if [ -s "$ERRF" ]; then ok "5b. strict вне проекта → есть stderr (fail-loud)"; else bad "5b. strict вне проекта → есть stderr" "stderr пуст"; fi
eq "5c. strict вне проекта → пустой stdout (НЕ фолбэк на cwd)" "" "$OUT"

# 6. lenient ВНЕ проекта → тихо: пустой stdout, БЕЗ stderr, ненулевой код
ERRF2="$(mktemp)"
OUT="$(vibe_resolve_root "$NOPROJ" lenient 2>"$ERRF2")"; RC=$?
eq "6a. lenient вне проекта → пустой stdout" "" "$OUT"
if [ ! -s "$ERRF2" ]; then ok "6b. lenient вне проекта → БЕЗ stderr (тихо)"; else bad "6b. lenient вне проекта → без stderr" "stderr: $(cat "$ERRF2")"; fi
if [ "$RC" -ne 0 ]; then ok "6c. lenient вне проекта → ненулевой код"; else bad "6c. lenient вне проекта → ненулевой код" "код=$RC"; fi

# 7. VIBE_PROJECT_ROOT перебивает поиск
OUT="$(VIBE_PROJECT_ROOT="$ROOT" vibe_resolve_root "$NOPROJ" strict 2>/dev/null)"
eq "7. env VIBE_PROJECT_ROOT перебивает" "$ROOT" "$OUT"

# 8. Невалидный VIBE_PROJECT_ROOT в strict → hard-error
ERRF3="$(mktemp)"
OUT="$(VIBE_PROJECT_ROOT="$NOPROJ" vibe_resolve_root "$ROOT" strict 2>"$ERRF3")"; RC=$?
if [ "$RC" -ne 0 ] && [ -s "$ERRF3" ]; then ok "8. невалидный env в strict → hard-error"; else bad "8. невалидный env в strict → hard-error" "код=$RC stderr=$(cat "$ERRF3")"; fi

# --- Контракт имён артефактов ---
echo "Контракт путей артефактов:"
eq "9a. feature_list"      "$ROOT/feature_list.json"                    "$(vibe_path_feature_list "$ROOT")"
eq "9b. archive"           "$ROOT/feature_list.archive.json"            "$(vibe_path_archive "$ROOT")"
eq "9c. session"           "$ROOT/SESSION.md"                           "$(vibe_path_session "$ROOT")"
eq "9d. profile"           "$ROOT/.harness/profile"                     "$(vibe_path_profile "$ROOT")"
eq "9e. hook-mode"         "$ROOT/.harness/hook-mode"                   "$(vibe_path_hook_mode "$ROOT")"
eq "9f. engine-version"    "$ROOT/.harness/engine-version"              "$(vibe_path_engine_version "$ROOT")"
eq "9g. provenance-log"    "$ROOT/.harness/provenance-log.jsonl"        "$(vibe_path_provenance_log "$ROOT")"
eq "9h. test-strategy"     "$ROOT/docs/test-strategy.md"                "$(vibe_path_test_strategy "$ROOT")"
eq "9i. change(slug)"      "$ROOT/docs/changes/feat-012"                "$(vibe_path_change "$ROOT" "feat-012")"

rm -rf "$ROOT" "$ROOT2" "$NOPROJ" "$ERRF" "$ERRF2" "$ERRF3" 2>/dev/null

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
