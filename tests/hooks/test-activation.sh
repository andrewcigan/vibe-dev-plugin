#!/bin/bash
# Vibe Dev v6.2 — тест активации enforcement (F2; главный провал аудита «харнес не поднялся»).
#
# Механика: (1) heartbeat — SessionStart/UserPromptSubmit пишут .harness/hooks-heartbeat;
# (2) двухфазный профиль — bootstrap пишет pending-strict, в strict переводит ТОЛЬКО живой хук
# (факт перевода = доказательство активации); (3) git pre-commit backstop — НЕЗАВИСИМЫЙ канал
# (работает без плагина): pending-профиль или мёртвый heartbeat при standard/strict = block коммита.
#
# Запуск: bash tests/hooks/test-activation.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_file() { if [ -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен существовать: %s)\n' "$1" "$2"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "6.0" > "$PROJ/.harness/engine-version"

echo "Активация enforcement (F2) — сценарии:"

# --- 1. hook_profile нормализует pending для самих хуков ---
P="$( ( . "$PLUGIN_ROOT/hooks/lib/hook-io.sh"; echo "pending-strict" > "$PROJ/.harness/profile"; hook_profile "$PROJ" ) )"
assert_eq "1. hook_profile: pending-strict читается хуками как strict" "$P" "strict"

# --- 2. SessionStart: heartbeat + перевод pending -> strict + сообщение ---
echo "pending-strict" > "$PROJ/.harness/profile"; rm -f "$PROJ/.harness/hooks-heartbeat"
SS="$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"SessionStart",cwd:$cwd}')"
OUT="$(printf '%s' "$SS" | bash "$PLUGIN_ROOT/hooks/dispatch-session-start.sh")"
assert_file     "2a. SessionStart пишет heartbeat" "$PROJ/.harness/hooks-heartbeat"
assert_eq       "2b. pending-strict переведён в strict живым хуком" "$(cat "$PROJ/.harness/profile")" "strict"
assert_contains "2c. inject сообщает об активации" "$OUT" "активирован"

# --- 3. UserPromptSubmit: то же без рестарта (bootstrap в текущей сессии) ---
echo "pending-standard" > "$PROJ/.harness/profile"; rm -f "$PROJ/.harness/hooks-heartbeat"
UP="$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"продолжаем"}')"
OUT="$(printf '%s' "$UP" | bash "$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh")"
assert_file     "3a. UserPromptSubmit пишет heartbeat" "$PROJ/.harness/hooks-heartbeat"
assert_eq       "3b. pending-standard -> standard" "$(cat "$PROJ/.harness/profile")" "standard"
assert_contains "3c. inject сообщает об активации" "$OUT" "активирован"

# heartbeat содержит unix-ts первым полем
HB_TS="$(awk '{print $1; exit}' "$PROJ/.harness/hooks-heartbeat")"
case "$HB_TS" in
  ''|*[!0-9]*) FAIL=$((FAIL+1)); printf '  FAIL 3d. heartbeat: первое поле не unix-ts (%s)\n' "$HB_TS" ;;
  *) PASS=$((PASS+1)); printf '  ok   3d. heartbeat: unix-ts первым полем\n' ;;
esac

# --- 4. Git pre-commit backstop (независимый канал) ---
REPO="$(mktemp -d)"; ( cd "$REPO" && git init -q )
mkdir -p "$REPO/.harness"
bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$REPO" >/dev/null
assert_file "4a. install: .git/hooks/pre-commit установлен" "$REPO/.git/hooks/pre-commit"
assert_file "4b. install: scope-копия в .harness/hooks/" "$REPO/.harness/hooks/pre-commit-scope.sh"

run_precommit() { ( cd "$REPO" && bash .git/hooks/pre-commit 2>&1 ); }

echo "pending-strict" > "$REPO/.harness/profile"
OUT="$(run_precommit)"; RC=$?
assert_eq       "4c. pending-профиль -> блок коммита" "$RC" "1"
assert_contains "4d. block-текст: диагностика активации" "$OUT" "не активен"

echo "strict" > "$REPO/.harness/profile"; rm -f "$REPO/.harness/hooks-heartbeat"
OUT="$(run_precommit)"; RC=$?
assert_eq "4e. strict без heartbeat -> блок" "$RC" "1"

printf '%s plugin=test\n' "$(date +%s)" > "$REPO/.harness/hooks-heartbeat"
OUT="$(run_precommit)"; RC=$?
assert_eq "4f. strict + свежий heartbeat -> коммит разрешён" "$RC" "0"

printf '%s plugin=test\n' "$(( $(date +%s) - 3600 ))" > "$REPO/.harness/hooks-heartbeat"
OUT="$(run_precommit)"; RC=$?
assert_eq       "4g. strict + heartbeat 1ч -> блок (TTL 30 мин)" "$RC" "1"
assert_contains "4h. block-текст: про устаревший heartbeat" "$OUT" "устарел"

: > "$REPO/.harness/hooks-disabled"
OUT="$(run_precommit)"; RC=$?
assert_eq "4i. hooks-disabled (осознанно) -> pass" "$RC" "0"
rm -f "$REPO/.harness/hooks-disabled"

echo "minimal" > "$REPO/.harness/profile"
OUT="$(run_precommit)"; RC=$?
assert_eq "4j. minimal -> backstop не применяется" "$RC" "0"

# --- 5. Установка не затирает чужой pre-commit ---
REPO2="$(mktemp -d)"; ( cd "$REPO2" && git init -q ); mkdir -p "$REPO2/.harness"
printf '#!/bin/bash\necho чужой\n' > "$REPO2/.git/hooks/pre-commit"
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$REPO2")"
assert_contains "5a. чужой pre-commit не затёрт (предупреждение)" "$OUT" "посторонний"
assert_eq       "5b. содержимое чужого хука цело" "$(grep -c "чужой" "$REPO2/.git/hooks/pre-commit")" "1"

# --- 6. Backstop + scope работают вместе: файл вне scope активной фичи блокируется ---
echo "strict" > "$REPO/.harness/profile"
printf '%s plugin=test\n' "$(date +%s)" > "$REPO/.harness/hooks-heartbeat"
cat > "$REPO/feature_list.json" <<'EOF'
{"active":"feat-001","features":{"active":[{"id":"feat-001","state":"active","affected_files":["src/a.txt"]}]}}
EOF
mkdir -p "$REPO/src"; echo x > "$REPO/src/a.txt"; echo y > "$REPO/outside.txt"
( cd "$REPO" && git add src/a.txt outside.txt feature_list.json 2>/dev/null )
OUT="$( cd "$REPO" && bash .git/hooks/pre-commit 2>&1 )"; RC=$?
assert_eq       "6a. файл вне affected_files -> блок (scope-слой жив)" "$RC" "1"
assert_contains "6b. scope block-текст" "$OUT" "SCOPE"

rm -rf "$PROJ" "$REPO" "$REPO2"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
