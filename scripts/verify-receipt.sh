#!/bin/bash
# Квитанция прогона проверки (v9 F4.1) — доказательство пишет машина, не агент прозой.
#
# ЗАЧЕМ. Поле evidence заполнялось текстом: «прогнал тесты, всё зелёное». Такой текст ничем не
# отличается от текста, написанного не глядя, — и именно так проходили «готово на бумаге»:
# в одном живом проекте нашлось 156 записей, помеченных завершёнными без доказательства, а
# инцидент с дублями в CRM месяц выглядел закрытой фичей. Квитанцию нельзя написать прозой:
# её содержимое порождается запуском.
#
# ЧТО ПИШЕТ. .harness/receipts/<id>-<время>.json: команда, код возврата, длительность, отпечаток
# вывода, первые и последние строки вывода, версия движка, отпечаток рабочего дерева.
# Отпечаток дерева нужен, чтобы отличить «проверено на этом коде» от «проверено когда-то давно».
#
# Использование: bash scripts/verify-receipt.sh <feature-id> [<путь-проекта>]
#   Команда берётся из feature_list.json (поле verification_command этой фичи).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh" 2>/dev/null || true

# --live — прогон против НАСТОЯЩЕЙ внешней системы, а не против подмены (v9 F4.3).
# Зачем отдельный признак: в прошлом инциденте команда проверки была формально валидна, но
# юнит-тесты подменяли ровно ту границу, которую доказывали — поиск в чужой системе. Тест
# был зелёным месяц, а механизм не срабатывал ни разу. Обычная квитанция доказывает, что
# команда отработала; живая — что она разговаривала с внешней системой.
LIVE=no
ARGS=()
for a in "$@"; do
  case "$a" in --live) LIVE=yes ;; *) ARGS+=("$a") ;; esac
done
set -- "${ARGS[@]:-}"

FEAT="${1:-}"
[ -n "$FEAT" ] || { echo "Нужен id фичи: bash scripts/verify-receipt.sh <feature-id> [путь] [--live]" >&2; exit 2; }
ROOT="${2:-$PWD}"
if command -v vibe_resolve_root >/dev/null 2>&1; then
  ROOT="$(vibe_resolve_root "$ROOT" strict)" || exit 1
fi
FL="$ROOT/feature_list.json"
[ -f "$FL" ] || { echo "Нет журнала фич в $ROOT" >&2; exit 1; }

CMD="$(python3 - "$FL" "$FEAT" <<'PYEOF'
import json,sys
data=json.load(open(sys.argv[1],encoding='utf-8'))
want=sys.argv[2]
for bucket,lst in (data.get('features') or {}).items():
    if isinstance(lst,list):
        for f in lst:
            if isinstance(f,dict) and str(f.get('id'))==want:
                print(str(f.get('verification_command') or '').strip()); sys.exit(0)
sys.exit(3)
PYEOF
)" || { echo "Фича $FEAT не найдена в журнале" >&2; exit 3; }

if [ -z "$CMD" ]; then
  echo "У фичи $FEAT нет verification_command — нечего запускать. Впиши команду, которая краснеет," >&2
  echo "пока фича не сделана, и зеленеет, когда сделана." >&2
  exit 4
fi

mkdir -p "$ROOT/.harness/receipts"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
OUTF="$(mktemp)"; trap 'rm -f "$OUTF"' EXIT
START="$(date +%s)"
( cd "$ROOT" && eval "$CMD" ) >"$OUTF" 2>&1
RC=$?
DUR=$(( $(date +%s) - START ))
TREE="$( (cd "$ROOT" && git rev-parse HEAD 2>/dev/null && git status --porcelain 2>/dev/null | shasum -a 256 | awk '{print $1}') | tr '\n' ' ')"
RECEIPT="$ROOT/.harness/receipts/${FEAT}-${STAMP}.json"

python3 - "$RECEIPT" "$FEAT" "$CMD" "$RC" "$DUR" "$OUTF" "$TREE" "$LIVE" <<'PYEOF'
import json,sys,hashlib,subprocess
receipt,feat,cmd,rc,dur,outf,tree,live=sys.argv[1:9]
raw=open(outf,encoding='utf-8',errors='replace').read()
lines=raw.splitlines()
try: engine=subprocess.run(['claude','--version'],capture_output=True,text=True).stdout.strip()
except Exception: engine=''
json.dump({
 "feature": feat,
 "command": cmd,
 "exit_code": int(rc),
 "verdict": "passed" if int(rc)==0 else "failed",
 "duration_sec": int(dur),
 "output_sha256": hashlib.sha256(raw.encode('utf-8','replace')).hexdigest(),
 "output_lines": len(lines),
 "output_head": lines[:12],
 "output_tail": lines[-8:] if len(lines)>12 else [],
 "tree_state": tree.strip(),
 "engine": engine,
 "live": live == "yes",
}, open(receipt,'w',encoding='utf-8'), ensure_ascii=False, indent=1)
PYEOF

if [ "$RC" -eq 0 ]; then
  echo "✓ Проверка прошла. Квитанция: .harness/receipts/${FEAT}-${STAMP}.json"
  echo "  В evidence фичи впиши эту ссылку — доказательство порождено запуском, не написано прозой."
else
  echo "✗ Проверка НЕ прошла (код $RC). Квитанция: .harness/receipts/${FEAT}-${STAMP}.json"
  echo "  Фича не готова. Смотри вывод в квитанции — там первые и последние строки прогона."
fi
exit "$RC"
