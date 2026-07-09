#!/bin/bash
# Vibe Dev v8 — тест append-only защиты provenance-log.jsonl через git pre-commit (L3-F2).
#
# Контракт: холодный лог — источник истины истории; правка/удаление прошлой строки = reject
# коммита; добавление новой строки — проходит; снапшот-маркер разрешает компакцию.
# Детерминированно (git-канал, не зависит от плагина/heartbeat).
#
# Запуск: bash tests/hooks/test-provenance-append-only.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

REPO="$(mktemp -d)"
cd "$REPO" || exit 1
git init -q
git config user.email t@t.t; git config user.name t
mkdir -p .harness/locks .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
# без profile → activation backstop (блок 1) не применяется; тестируем только блок 3 (append-only)

LOG=".harness/provenance-log.jsonl"
printf '%s\n' '{"at":"2026-07-10T09:00:00Z","feat":"feat-001","op":"ADDED","by":"owner"}' > "$LOG"
git add -A && git commit -q -m "seed log" 2>/dev/null

echo "Provenance append-only (L3-F2) — сценарии:"

# 1. Добавление новой строки → commit проходит
printf '%s\n' '{"at":"2026-07-10T10:00:00Z","feat":"feat-002","op":"ADDED","by":"owner"}' >> "$LOG"
git add "$LOG"
if git commit -q -m "append event" 2>/dev/null; then ok "1. добавление строки → commit проходит"; else bad "1. добавление строки → commit проходит" "коммит отклонён"; fi

# 2. Правка прошлой строки → reject
if command -v perl >/dev/null 2>&1; then
  perl -0pi -e 's/feat-001/feat-XXX/' "$LOG"
  git add "$LOG"
  if git commit -q -m "tamper" 2>/dev/null; then bad "2. правка прошлой строки → reject" "коммит прошёл (должен reject)"; else ok "2. правка прошлой строки → reject"; fi
  git checkout -- "$LOG" 2>/dev/null; git reset -q 2>/dev/null
fi

# 3. Удаление прошлой строки → reject
printf '%s\n' '{"at":"2026-07-10T09:00:00Z","feat":"feat-001","op":"ADDED","by":"owner"}' > "$LOG"  # только 1-я строка, 2-я удалена
git add "$LOG"
if git commit -q -m "delete line" 2>/dev/null; then bad "3. удаление прошлой строки → reject" "коммит прошёл (должен reject)"; else ok "3. удаление прошлой строки → reject"; fi
git checkout -- "$LOG" 2>/dev/null; git reset -q 2>/dev/null

# 4. Снапшот-маркер разрешает переписать (легитимная компакция)
touch .harness/locks/provenance-snapshot
printf '%s\n' '{"at":"2026-07-10T09:00:00Z","feat":"feat-001","op":"ADDED","by":"owner"}' > "$LOG"  # переписан
git add "$LOG"
if git commit -q -m "snapshot compaction" 2>/dev/null; then ok "4. снапшот-маркер → перезапись разрешена"; else bad "4. снапшот-маркер → перезапись разрешена" "reject при снапшоте"; fi
rm -f .harness/locks/provenance-snapshot

cd /; rm -rf "$REPO"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
