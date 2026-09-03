#!/bin/bash
# Свод журнала срабатываний сторожей (v9 F0.1). Вызывается из /audit и вручную.
#
# ЧТО ЭТО ОТВЕЧАЕТ. Правило владельца «двух починок» требует до третьего ремонта письменно
# ответить: сколько раз механизм предотвратил беду и сколько раз помешал нормальной работе.
# До этого журнала оба числа были неизвестны для всех механизмов сразу.
#
# ЧЕСТНАЯ ГРАНИЦА. Скрипт считает СРАБАТЫВАНИЯ, а не пользу: запрет мог быть и ложным.
# Различить помогает соседний столбец «обойдено» — сколько раз после запрета шёл обход
# (--no-verify рядом по времени). Оценку «полезен/вреден» выносит человек, не скрипт.
#
# Использование: bash scripts/guard-stats.sh [путь-проекта] [--days N]
set -u
PROJ="${1:-$PWD}"; [ "${PROJ#--}" != "$PROJ" ] && PROJ="$PWD"
LOG="$PROJ/.harness/guard-stats.jsonl"
if [ ! -f "$LOG" ]; then
  echo "Журнала срабатываний нет: $LOG"
  echo "Он появится после первого запуска сторожей в этом проекте (нужен движок с плагином v9)."
  exit 0
fi
python3 - "$LOG" <<'PY'
import json,sys,collections,datetime
rows=[]
for line in open(sys.argv[1], encoding='utf-8'):
    line=line.strip()
    if not line: continue
    try: rows.append(json.loads(line))
    except Exception: continue
if not rows:
    print("Журнал пуст."); raise SystemExit
c=collections.defaultdict(lambda: collections.Counter())
for r in rows: c[r.get("guard","?")][r.get("verdict","?")]+=1
first=min(r.get("t","") for r in rows); last=max(r.get("t","") for r in rows)
tot=collections.Counter()
for g,v in c.items(): tot.update(v)
print(f'Журнал сторожей: {len(rows)} записей, с {first} по {last}')
print(f'Итого: запретов {tot["BLOCK"]}, предупреждений {tot["WARN"]}, пропусков {tot["pass"]}, ПАДЕНИЙ {tot["CRASH"]}')
print()
print(f'{"сторож":34}{"запретил":>10}{"предупредил":>13}{"пропустил":>11}{"УПАЛ":>7}')
print('-'*75)
for g in sorted(c, key=lambda x:(-c[x]["BLOCK"]-c[x]["WARN"], x)):
    v=c[g]
    print(f'{g:34}{v["BLOCK"]:>10}{v["WARN"]:>13}{v["pass"]:>11}{v["CRASH"]:>7}')
silent=[g for g,v in c.items() if v["BLOCK"]==0 and v["WARN"]==0]
if silent:
    print()
    print(f'НИ РАЗУ не сработали ({len(silent)}): ' + ', '.join(sorted(silent)))
    print('Это кандидаты на вопрос правила двух починок: механизм, который ни разу не')
    print('предотвратил беду, ради которой построен, чинить в третий раз нельзя — его сносят.')
crashed=[g for g,v in c.items() if v["CRASH"]]
if crashed:
    print()
    print(f'ПАДАЛИ ({len(crashed)}): ' + ', '.join(sorted(crashed)) + ' — их проверки тогда НЕ выполнялись.')
PY
