#!/bin/bash
# Vibe Dev v6 — тест SessionStart-диспетчера (волна 1, H6 loop-замыкание).
#
# Probe маркера handoff-pending: UserPromptSubmit при сигнале завершения ставит маркер;
# при следующем старте SessionStart сравнивает mtime(SESSION.md) vs mtime(маркер):
#   - SESSION.md новее маркера → handoff обновлён после сигнала → тихо снять маркер, pass;
#   - SESSION.md старше/нет → handoff мог НЕ записаться → inject warn, снять маркер (одноразово).
# Ловит ПРОПУСК handoff постфактум (реальный кейс: 30 мин проработки повисли).
#
# Запуск: bash tests/hooks/test-session-start.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-session-start.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}
assert_absent() { if [ ! -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен отсутствовать: %s)\n' "$1" "$2"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
MARKER="$PROJ/.harness/handoff-pending"
ss_payload() { jq -cn --arg cwd "${1:-$PROJ}" '{hook_event_name:"SessionStart",cwd:$cwd}'; }
mk_marker()  { : > "$MARKER"; touch -t "$1" "$MARKER"; }
mk_session() { echo "# SESSION" > "$PROJ/SESSION.md"; touch -t "$1" "$PROJ/SESSION.md"; }

echo "SessionStart dispatcher (H6 — handoff-pending probe) — сценарии:"

# 1. Маркер новее SESSION.md (handoff НЕ обновлён после сигнала) -> WARN + маркер снят
mk_session 202606031100; mk_marker 202606031200
OUT="$(run "$(ss_payload)")"
assert_contains "1a. handoff не записан -> additionalContext warn" "$OUT" '"additionalContext"'
assert_absent  "1b. маркер снят после probe" "$MARKER"

# 2. SESSION.md новее маркера (handoff сделан после сигнала) -> pass + маркер снят
mk_marker 202606031100; mk_session 202606031200
OUT="$(run "$(ss_payload)")"
assert_empty  "2a. handoff записан -> pass (тихо)" "$OUT"
assert_absent "2b. маркер снят" "$MARKER"

# 3. Маркера нет -> pass
rm -f "$MARKER"
OUT="$(run "$(ss_payload)")"
assert_empty "3. нет маркера -> pass" "$OUT"

# 4. Маркер есть, SESSION.md отсутствует -> WARN (handoff не записан вообще)
rm -f "$PROJ/SESSION.md"; mk_marker 202606031200
OUT="$(run "$(ss_payload)")"
assert_contains "4. маркер + нет SESSION.md -> warn" "$OUT" '"additionalContext"'
rm -f "$MARKER"

# 5. minimal-профиль -> pass (выключен)
mk_session 202606031100; mk_marker 202606031200
echo minimal > "$PROJ/.harness/profile"
OUT="$(run "$(ss_payload)")"
assert_empty "5. minimal -> pass" "$OUT"
rm -f "$PROJ/.harness/profile" "$MARKER"

# 6. Не vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
OUT="$(run "$(ss_payload "$NOPROJ")")"
assert_empty "6. не-vibe -> pass" "$OUT"
rm -rf "$NOPROJ"

# 7. Вывод (warn) — валидный JSON
mk_session 202606031100; mk_marker 202606031200
OUT="$(run "$(ss_payload)")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   7. вывод — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 7. вывод — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
