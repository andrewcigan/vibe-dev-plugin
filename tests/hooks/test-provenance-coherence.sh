#!/bin/bash
# Vibe Dev v8 — тест когерентности head↔log через git pre-commit (L3-F3, критик M1).
# Голова впереди лога (правка мимо record-change.sh) → reject; захват и синхронное состояние → pass.
# Запуск: bash tests/hooks/test-provenance-coherence.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

REPO="$(mktemp -d)"; cd "$REPO" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
mkdir -p .harness .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
LOG=".harness/provenance-log.jsonl"

mkfl() {  # $1 = seq головы
  cat > feature_list.json <<JSON
{"version":"8.0","features":{"active_list":[{"id":"feat-001","name":"X","state":"active","provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":$1}}]}}
JSON
}

echo "Провенанс head↔log когерентность (L3-F3 M1) — сценарии:"

# 1. Захват: голова seq=0, лог пуст → commit проходит (захват не логирует ADDED)
mkfl 0; git add -A
if git commit -q -m "capture" 2>/dev/null; then ok "1. захват (seq=0, лог пуст) → pass"; else bad "1. захват → pass" "reject легитимного захвата"; fi

# 2. Голова seq=1 + лог имеет событие seq=1 → когерентно → pass
printf '%s\n' '{"v":1,"at":"2026-07-10T01:00:00Z","feat":"feat-001","seq":1,"op":"MODIFIED","by":"owner"}' > "$LOG"
mkfl 1; git add -A
if git commit -q -m "coherent edit" 2>/dev/null; then ok "2. голова seq=1 = лог seq=1 → pass"; else bad "2. когерентно → pass" "reject синхронного"; fi

# 3. Голова seq=2 (правка мимо record-change), лог max seq=1 → reject
mkfl 2; git add feature_list.json
if git commit -q -m "manual tamper" 2>/dev/null; then bad "3. голова впереди лога → reject" "коммит прошёл (должен reject)"; else ok "3. голова seq=2 впереди лога (max 1) → reject"; fi
git reset -q 2>/dev/null; git checkout -- feature_list.json 2>/dev/null

# 4. Голова позади лога (после обрыва): голова seq=1, лог до seq=3 → это НЕ reject (восстановимо, warn)
printf '%s\n' '{"v":1,"at":"2026-07-10T02:00:00Z","feat":"feat-001","seq":2,"op":"MODIFIED","by":"owner"}' >> "$LOG"
printf '%s\n' '{"v":1,"at":"2026-07-10T03:00:00Z","feat":"feat-001","seq":3,"op":"MODIFIED","by":"owner"}' >> "$LOG"
mkfl 1; git add -A
if git commit -q -m "head behind" 2>/dev/null; then ok "4. голова позади лога → pass (восстановимо, не reject)"; else bad "4. голова позади → pass" "reject восстановимого состояния"; fi

cd /; rm -rf "$REPO"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
