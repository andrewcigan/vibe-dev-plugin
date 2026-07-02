#!/bin/bash
# Vibe Dev v6.2 — тест на КОРПУСЕ РЕАЛЬНЫХ feature_list (F1; мета-правило real-fixtures).
#
# Урок бага 2026-06-06: юнит-тесты на синтетике (verification всегда словарь) пропустили
# краш на реальной форме (verification строкой) -> молчаливый fail-open флагман-гейта.
# Корпус tests/hooks/fixtures/real/ — обезличенные feature_list из 6 боевых проектов
# (структура и ТИПЫ полей сохранены, контент уничтожен анонимизатором).
#
# На каждой фикстуре:
#   (а) Write всего файла через диспетчер (strict) -> сторож НЕ падает (нет УПАЛ,
#       нет crash-артефакта); вывод пуст или валидный JSON (вердикты по делу допустимы);
#   (б) та же фикстура + контрольная битая UI-фича (passing без user-evidence)
#       -> deny ДОХОДИТ (гейт жив в окружении реальных форм, не только на учебном файле).
#
# Запуск: bash tests/hooks/test-real-fixtures.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
FIXTURES="$PLUGIN_ROOT/tests/hooks/fixtures/real"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "7.0" > "$PROJ/.harness/engine-version"
echo strict > "$PROJ/.harness/profile"

# Контрольная битая фича: UI в passing без layer_4/5 evidence — обязана ловиться всегда.
# Схема feature_list: features = словарь-вёдра по статусам, state в поле "state".
BROKEN='{"id":"feat-broken-control","title":"контрольная битая UI-фича","category":"ui",
"size_estimate":"S","state":"passing","affected_files":["src/App.tsx"],
"verification":{"layer_1_syntax":"ok"},"evidence":{}}'

run_write() { # $1 = content
  jq -cn --arg cwd "$PROJ" --arg fp "$PROJ/feature_list.json" --arg c "$1" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' \
    | bash "$DISPATCH"
}

echo "Корпус реальных feature_list (fail-loud + живость гейта) — фикстуры:"

COUNT=0
for FX in "$FIXTURES"/*.json; do
  NAME="$(basename "$FX" .json)"
  COUNT=$((COUNT+1))
  CONTENT="$(cat "$FX")"
  rm -rf "$PROJ/.harness/hook-crashes"

  # (а) реальный файл целиком: не падает
  OUT="$(run_write "$CONTENT")"
  if printf '%s' "$OUT" | grep -q "УПАЛ"; then
    FAIL=$((FAIL+1)); printf '  FAIL %s(а): сторож УПАЛ на реальной форме\n     %s\n' "$NAME" "$OUT"
  elif [ -d "$PROJ/.harness/hook-crashes" ] && [ -n "$(ls -A "$PROJ/.harness/hook-crashes" 2>/dev/null)" ]; then
    FAIL=$((FAIL+1)); printf '  FAIL %s(а): crash-артефакт при прогоне реальной формы\n' "$NAME"
  elif [ -n "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ! printf '%s' "$OUT" | jq empty 2>/dev/null; then
    FAIL=$((FAIL+1)); printf '  FAIL %s(а): вывод не пустой и не валидный JSON\n     %s\n' "$NAME" "$OUT"
  else
    PASS=$((PASS+1)); printf '  ok   %s(а): реальные формы не роняют сторож\n' "$NAME"
  fi

  # (б) реальный файл + контрольная битая UI-фича: deny доходит
  WITH_BROKEN="$(printf '%s' "$CONTENT" | jq --argjson b "$BROKEN" '
    if (.features? | type) == "object" then .features.passing = ((.features.passing // []) + [$b])
    else . + {features: {passing: [$b]}} end' 2>/dev/null)"
  if [ -z "$WITH_BROKEN" ]; then
    FAIL=$((FAIL+1)); printf '  FAIL %s(б): не удалось встроить контрольную фичу (jq)\n' "$NAME"
    continue
  fi
  OUT="$(run_write "$WITH_BROKEN")"
  if printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; then
    PASS=$((PASS+1)); printf '  ok   %s(б): битая UI-фича ловится в окружении реальных форм\n' "$NAME"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s(б): deny НЕ дошёл (fail-open в окружении реальных форм)\n     %s\n' "$NAME" "$OUT"
  fi
done

if [ "$COUNT" -lt 5 ]; then
  FAIL=$((FAIL+1)); printf '  FAIL корпус: ожидал >=5 фикстур, найдено %s\n' "$COUNT"
else
  PASS=$((PASS+1)); printf '  ok   корпус: %s фикстур\n' "$COUNT"
fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
