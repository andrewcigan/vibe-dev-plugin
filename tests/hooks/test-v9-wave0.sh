#!/bin/bash
# Тест механизмов волны 0 (v9): журнал срабатываний, эталонный корпус, правило класса в .gitignore.
# Стережёт сами сторожевые механизмы — иначе они тихо отвалятся при следующей правке обвязки.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "  ❌ $1"; }

S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT; mkdir -p "$S/.harness"

# 1. Журнал пишет вердикт запрета.
( . "$ROOT/hooks/lib/hook-io.sh" 2>/dev/null
  HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"src/c.ts","content":"const k=\"sk-ant-api03-AAAAAAAAAAAAAAAAAAAA\""}}' \
  hook_run_check "$S" "secret-scan-write" verdict "$ROOT/hooks/checks/secret-scan-write.sh" "$S" "src/c.ts" "Write" >/dev/null )
grep -q '"verdict":"BLOCK"' "$S/.harness/guard-stats.jsonl" 2>/dev/null && ok || bad "журнал не записал запрет"

# 2. Журнал отличает падение сторожа от пропуска.
( . "$ROOT/hooks/lib/hook-io.sh" 2>/dev/null
  hook_run_check "$S" "заведомо-битый" verdict "/nonexistent/guard.sh" >/dev/null )
grep -q '"verdict":"CRASH"' "$S/.harness/guard-stats.jsonl" 2>/dev/null && ok || bad "падение сторожа не отмечено как CRASH"

# 3. Журнал не рвёт кириллицу (обрезка по словам, не по байтам).
if python3 -c "
import json,sys
for l in open('$S/.harness/guard-stats.jsonl',encoding='utf-8'):
    json.loads(l)
" 2>/dev/null; then ok; else bad "журнал содержит битые строки (порванная кодировка)"; fi

# 4. Имя события проставляется всеми диспетчерами.
MISSING=""
for f in "$ROOT"/hooks/dispatch-*.sh "$ROOT"/hooks/pre-compact.sh; do
  grep -q "VIBE_HOOK_EVENT" "$f" || MISSING="$MISSING $(basename "$f")"
done
[ -z "$MISSING" ] && ok || bad "диспетчеры без имени события:$MISSING"

# 5. Корпус задаёт ожидание заранее, а не снимком.
# Регистронезависимый поиск по кириллице в этой локали НЕ работает — сверяем точной подстрокой.
grep -q "Ожидание задано ЗАРАНЕЕ" "$ROOT/tests/hooks/baseline-probe.sh" && ok \
  || bad "в корпусе нет фиксации ожидания — снимок может стать эталоном"

# 6. Положительные контроли на месте (без них не отличить «жив» от «мёртв»).
grep -q "positive_control" "$ROOT/tests/hooks/baseline-probe.sh" && ok || bad "в корпусе нет положительных контролей"

# 7. .gitignore прячет рабочий слой классом, а не поимённо.
grep -qE '^\.harness/\*$' "$ROOT/.gitignore" && ok || bad ".gitignore перечисляет рабочие файлы поимённо"

# 8. Провенанс и версия движка при этом остаются в истории.
( cd "$ROOT" && git check-ignore -q .harness/provenance-log.jsonl ) && bad "провенанс попал под игнор" || ok

echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
