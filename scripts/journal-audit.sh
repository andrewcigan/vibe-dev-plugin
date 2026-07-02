#!/bin/bash
# Vibe Dev v7 (Волна 4, G5 + дешёвый дедуп G2) — READ-ONLY аудит журнала ошибок.
# Только ДОКЛАДЫВАЕТ, ничего НЕ правит (обнаружение отделено от правки — критики велели).
# Зовётся из /doctor и /end-session. Дедуп «дёшево-перед-дорого»: bash-нормализация + sort/uniq,
# 0 токенов, без субагента (субагент из хука/скрипта не зовём — проверенный блокер v7).
# Аргумент: $1=cwd (default .).
set -u
CWD="${1:-.}"
J="$CWD/error-journal.md"
[ -f "$J" ] || { echo "— Журнал ошибок: нет файла (норма, если «не работает» ещё не было)"; exit 0; }

TOTAL=$(grep -c '^## err-' "$J" 2>/dev/null || echo 0)
ACTIVE=$(grep -cE '^\*\*status\*\*:[[:space:]]*active' "$J" 2>/dev/null || echo 0)
STAMPED=$(grep -cE '^\*\*status\*\*:' "$J" 2>/dev/null || echo 0)
echo "— Журнал ошибок: записей $TOTAL, active $ACTIVE, без штампа устаревания $((TOTAL-STAMPED))"

# Рекуррент: повтор КЛАССА ошибки.
DUPCLASS=$(grep -oE 'Класс ошибки\*\*:[^|]*' "$J" 2>/dev/null | sed 's/.*: *//' \
  | tr 'A-Z' 'a-z' | sed 's/^ *//;s/ *$//' | sort | uniq -d | head -3 | tr '\n' ';')
[ -n "$DUPCLASS" ] && echo "— ⚠️ Повтор классов ошибок (возможен рекуррент, перепроверь): $DUPCLASS"

# Дешёвый дедуп: одинаковые problem-строки формы C2 — нормализация + uniq.
# Лоуэркейс через python (tr не трогает кириллицу — Cyrillic-регистр остался бы дублем-мимо).
DUPPROB=$(grep -iE '^- *problem:' "$J" 2>/dev/null | sed 's/^- *[Pp]roblem: *//' \
  | python3 -c 'import sys,re
for l in sys.stdin:
    s=re.sub(r"[^0-9a-zа-яё ]"," ",l.lower())
    print(re.sub(r"\s+"," ",s).strip())' 2>/dev/null \
  | sort | uniq -d | head -3 | tr '\n' ';')
[ -n "$DUPPROB" ] && echo "— ⚠️ Похожие/повторные problem-записи (возможен дубль, перепроверь): $DUPPROB"
exit 0
