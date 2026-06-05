#!/bin/bash
# Vibe Dev v6 — self-check полноты таблицы трассировки (тест 3 атрибутов как механизм).
#
# Парсит docs/traceability.md (таблицу механизмов) и ПАДАЕТ (exit 1) если:
#   - строка не из 4 колонок или с пустым атрибутом (нет одного из 3 атрибутов);
#   - в «Где зафиксирован» нет реально существующего пути-файла (мёртвая ссылка = декларация);
#   - в «Что при обходе» нет слова-исхода (block/warn/log/ask/safe).
#
# Запуск: bash scripts/check-traceability.sh   (часть self-check плагина)

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${1:-$ROOT/docs/traceability.md}"   # опц. аргумент — путь к таблице (для negative-теста)
[ -f "$DOC" ] || { echo "❌ check-traceability: нет $DOC"; exit 1; }

python3 - "$ROOT" "$DOC" <<'PYEOF'
import sys, os, re

root, doc = sys.argv[1], sys.argv[2]
with open(doc) as f:
    lines = f.read().split('\n')

# Найти таблицу механизмов по заголовку
hdr = None
for i, l in enumerate(lines):
    if l.strip().startswith('|') and 'Где зафиксирован' in l and 'Что при обходе' in l:
        hdr = i
        break
if hdr is None:
    print("❌ check-traceability: не найдена таблица механизмов (нужен заголовок с 'Где зафиксирован' и 'Что при обходе')")
    sys.exit(1)

rows = []
for l in lines[hdr + 2:]:          # +1 заголовок, +2 строка-разделитель |---|
    if not l.strip().startswith('|'):
        break
    rows.append(l)

PATH_RE = re.compile(r'[A-Za-z0-9_./-]+\.(?:sh|json|yaml|yml|md|py|ts|js)')
OUTCOME_RE = re.compile(r'(block|warn|log|ask|safe)', re.I)

errors = []
n = 0
for l in rows:
    cells = [c.strip() for c in l.strip().strip('|').split('|')]
    if len(cells) != 4:
        errors.append("строка не из 4 колонок (%d): %s" % (len(cells), l.strip()[:80]))
        continue
    mech, where, how, outcome = cells
    n += 1
    if not (mech and where and how and outcome):
        errors.append("пустой атрибут: %s" % (mech or l.strip()[:60]))
        continue
    paths = PATH_RE.findall(where)
    if not paths:
        errors.append("«%s»: в 'Где зафиксирован' нет пути-файла — декларация без механизма" % mech)
    elif not any(os.path.exists(os.path.join(root, p)) for p in paths):
        errors.append("«%s»: ни один файл из 'Где зафиксирован' не существует: %s" % (mech, paths))
    if not OUTCOME_RE.search(outcome):
        errors.append("«%s»: 'Что при обходе' без слова-исхода (block/warn/log/ask/safe)" % mech)

if errors:
    print("❌ check-traceability: %d проблем(ы) полноты:" % len(errors))
    for e in errors:
        print("   • " + e)
    sys.exit(1)

print("✓ check-traceability: %d механизмов — у каждого 3 атрибута и живые ссылки" % n)
PYEOF
