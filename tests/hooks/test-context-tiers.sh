#!/bin/bash
# Vibe Dev v8 — тест трёхуровневой модели контекста (L4-F1, c3):
# git pre-commit блок 7 предупреждает (warn, НЕ block), если тело завершённой (архивной) фичи
# осталось в горячем CLAUDE.md/SESSION.md вместо строки-индекса.
# Запуск: bash tests/hooks/test-context-tiers.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
ARCHSH="$PLUGIN_ROOT/scripts/archive-features.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал [$2] получил [$3]"; fi; }

echo "Контекст L4-F1 — warn на тело архивной фичи в горячем (git pre-commit блок 7)"
REPO="$(mktemp -d)"; cd "$REPO" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
mkdir -p .harness .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

# baseline: feat-001 (done+evidence → станет архивным стабом) + feat-002 (passing, остаётся)
cat > feature_list.json <<'JSON'
{"version":"8.0","features":{
 "done":[{"id":"feat-001","name":"Экспорт","state":"done","description":"D",
   "evidence":{"layer_1_syntax_at":"2026-07-10T00:00:00Z"},
   "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}],
 "active_list":[{"id":"feat-002","name":"Импорт","state":"passing","description":"D2",
   "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}]}}
JSON
bash "$ARCHSH" "$REPO" >/dev/null 2>&1   # feat-001 → стаб + archive.json
git add -A && git commit -q -m "baseline" 2>/dev/null
eq "0. baseline закоммичен (feat-001 архивирован)" "True" \
   "$(python3 -c "import json;d=json.load(open('feature_list.json'));f=[x for x in d['features']['done'] if x['id']=='feat-001'][0];print('evidence_hash' in f)")"

# --- Сценарий 1: тело АРХИВНОЙ feat-001 в SESSION.md → warn, но коммит проходит ---
cat > SESSION.md <<'MD'
# Session

## feat-001 — Экспорт (готово)
Реализован экспорт в PDF и XLSX через библиотеку.
Тестировали на 3 форматах, все прошли.
Evidence: layer_1..4 зелёные, user подтвердил.
Заняло полторы сессии, были грабли с кодировкой.
MD
git add SESSION.md
ERR1="$(git commit -m "session with archived body" 2>&1)"; RC1=$?
eq "1. warn НЕ блокирует коммит (exit 0)" "0" "$RC1"
if printf '%s' "$ERR1" | grep -q "L4-F1"; then ok "2. warn про раздутый контекст показан"; else bad "2. warn показан" "нет L4-F1 в выводе: $ERR1"; fi
if printf '%s' "$ERR1" | grep -q "feat-001"; then ok "3. warn называет архивную фичу feat-001"; else bad "3. называет feat-001" "$ERR1"; fi

# --- Сценарий 2: та же feat-001, но одна строка-ссылка → тихо (нет warn) ---
cat > SESSION.md <<'MD'
# Session

## Архив (индекс)
- feat-001 → archive#feat-001 (done)
MD
git add SESSION.md
ERR2="$(git commit -m "session with stub link" 2>&1)"; RC2=$?
eq "4. строка-ссылка → коммит проходит" "0" "$RC2"
if printf '%s' "$ERR2" | grep -q "L4-F1"; then bad "5. строка-ссылка → БЕЗ warn" "warn ложно сработал: $ERR2"; else ok "5. строка-ссылка → warn молчит"; fi

# --- Сценарий 3: тело PASSING feat-002 (не архивной) → тихо (легитимно до ротации) ---
cat > SESSION.md <<'MD'
# Session

## feat-002 — Импорт (в работе)
Пишем импорт из CSV, три слоя проверки.
Пока сделан парсер и валидация.
Осталось e2e и обработка ошибок кодировки.
MD
git add SESSION.md
ERR3="$(git commit -m "session with passing body" 2>&1)"; RC3=$?
eq "6. тело passing-фичи → коммит проходит" "0" "$RC3"
if printf '%s' "$ERR3" | grep -q "L4-F1"; then bad "7. passing-фича → БЕЗ warn" "warn ложно сработал на passing: $ERR3"; else ok "7. passing-фича (не архив) → warn молчит"; fi

cd /; rm -rf "$REPO"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
