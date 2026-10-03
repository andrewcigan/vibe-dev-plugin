#!/bin/bash
# Vibe Dev — Pre-Commit Scope Hook
#
# Устанавливается как .git/hooks/pre-commit в проекте.
# Проверяет: diff ⊆ active feature.affected_files
#
# Closes WIP=1 / surgical changes scope leak.

set -e

PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# Skip if not Vibe Dev project
if [ ! -f "$PROJECT_ROOT/feature_list.json" ]; then
    exit 0
fi

# Активная фича = запись со state "active" (v9.0.4). Единственный источник — состояние самой
# записи: его ведут переходы, которые проверяет сторож состояния и писатель реестра проекта.
# Раньше сторож читал верхнее поле «active», а его не ставил и не снимал ни один писатель
# состояния: на живом проекте 02.10.2026 работа стояла в active, поле было пустым, и сторож
# выходил на первой строке, ничего не проверив. Обратный случай — поле осталось от закрытой
# работы, и сторож блокировал коммит по фиче, которой уже нет (08.07.2026). Поле больше не читается.
# Нет поля state — состояние по разделу active_list (старая форма журнала).
# Код Python — в одинарных кавычках, путь — аргументом: кавычка в пути проекта ничего не ломает,
# и без heredoc внутри $( ) (его не разбирает системный bash 3.2).
SCAN=$(python3 -c '
import json, sys, glob
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("__UNREADABLE__ %s" % e)
    sys.exit(0)
feats = d.get("features") or {}
buckets = feats.items() if isinstance(feats, dict) else [("", feats)]
active = []
for bucket, lst in buckets:
    if not isinstance(lst, list):
        continue
    for f in lst:
        if not isinstance(f, dict):
            continue
        state = f.get("state") or ("active" if bucket == "active_list" else "")
        if state == "active":
            active.append(f)
try:
    limit = max(1, int(d.get("wip_limit") or 1))
except (TypeError, ValueError):
    limit = 1
if not active:
    sys.exit(0)
print("__ACTIVE__ " + " ".join(str(f.get("id") or "?") for f in active))
if len(active) > limit:
    print("__WIP__ %d" % limit)
seen = set()
def emit(line):
    if line not in seen:
        seen.add(line)
        print(line)
for f in active:
    files = f.get("affected_files") or []
    if not files:
        print("__NO_AFFECTED_FILES__ %s" % (f.get("id") or "?"))
    for p in files:
        emit("__DECLARED__ " + p)
        for matched in glob.glob(p, recursive=True):
            emit(matched)
        if "*" not in p and "?" not in p:
            emit(p)
' "$PROJECT_ROOT/feature_list.json" 2>/dev/null) || SCAN="__UNREADABLE__ python3 не запустился"

# Не смог проверить — говорит вслух, а не пропускает молча.
UNREADABLE=$(printf '%s\n' "$SCAN" | sed -n 's/^__UNREADABLE__ //p')
if [ -n "$UNREADABLE" ]; then
    echo "⚠️  WIP=1 scope НЕ проверен: feature_list.json не читается ($UNREADABLE). Коммит пропущен без сверки рамок фичи." >&2
    exit 0
fi

ACTIVE=$(printf '%s\n' "$SCAN" | sed -n 's/^__ACTIVE__ //p')
if [ -z "$ACTIVE" ]; then
    # Ни одна запись не в active — allow commit (bootstrap, handoff, работа между фичами)
    exit 0
fi

# Несколько фич в active сверх предела — предупреждение, а не остановка: сверяем по объединению
# их рамок. Замер истории живого проекта (июль–октябрь 2026): 26 из 199 коммитов при активной
# работе шли в волнах с несколькими фичами в active; беды от этого не измерено, а остановка
# заморозила бы весь режим волн. Выход за рамки ВСЕХ активных фич по-прежнему блокируется.
WIP_LIMIT=$(printf '%s\n' "$SCAN" | sed -n 's/^__WIP__ //p')
if [ -n "$WIP_LIMIT" ]; then
    echo "⚠️  WIP: в active сразу несколько фич ($ACTIVE) при пределе wip_limit=$WIP_LIMIT — рамки коммита сверяются по объединению их affected_files." >&2
fi

NO_AFFECTED=$(printf '%s\n' "$SCAN" | sed -n 's/^__NO_AFFECTED_FILES__ //p')
# Рамки — как записаны в журнале (для отказа); раскрытые маски — для сверки.
DECLARED=$(printf '%s\n' "$SCAN" | sed -n 's/^__DECLARED__ //p')
AFFECTED=$(printf '%s\n' "$SCAN" | sed -e '/^__/d')

if [ -n "$NO_AFFECTED" ]; then
    cat >&2 <<EOF
⚠️  Active feature "$NO_AFFECTED" не имеет affected_files в feature_list.json.

WIP=1 invariant требует явных affected_files для surgical changes.

Добавь поле:
"affected_files": ["src/api/...", "tests/..."]

Commit allowed (warning only), но добавь — иначе следующий /audit понизит Scope score.
EOF
    exit 0
fi

# Файлы, которые пишет сам процесс харнеса при любой активной фиче (v9.0.4). Пока сторож молчал,
# этот список не проверялся жизнью; замер истории живого проекта показал, что без него каждый
# третий коммит при активной работе остановился бы на служебных файлах: журнал истории реестра
# (.harness/provenance-log.jsonl — обязан идти в одном коммите с реестром), передача сессии
# (.session-state/), архивы ротации, стратегия проверки и детальный план самой активной фичи.
# Свои постоянные исключения проект перечисляет в .harness/scope-allow (маска на строку, # — комментарий).
always_allowed() {
    case "$1" in
        SESSION.md|feature_list.json|error-journal.md|implementation-notes.md|README.md|.gitignore) return 0 ;;
        docs/decisions/*.md) return 0 ;;
        CLAUDE.md|restart-here.sh|docs/test-strategy.md|*.archive.json|*.archive.md) return 0 ;;
        .harness/*|.session-state/*) return 0 ;;
    esac
    local id pat
    for id in $ACTIVE; do
        case "$1" in docs/changes/"$id"/*) return 0 ;; esac
    done
    if [ -f "$PROJECT_ROOT/.harness/scope-allow" ]; then
        while IFS= read -r pat || [ -n "$pat" ]; do
            case "$pat" in ''|'#'*) continue ;; esac
            # shellcheck disable=SC2254 — маска из файла намеренно без кавычек
            case "$1" in $pat) return 0 ;; esac
        done < "$PROJECT_ROOT/.harness/scope-allow"
    fi
    return 1
}

# Пути — по одному, без экранирования git (-z): пробел и кириллица в имени не ломают сверку.
# Папка файла рамок — разбором строки, без отдельного процесса на каждую пару.
VIOLATIONS=()
while IFS= read -r -d '' file; do
    MATCHED=0
    while IFS= read -r affected; do
        [ -n "$affected" ] || continue
        # Match exact or by pattern (если affected с *)
        if [ "$file" = "$affected" ]; then
            MATCHED=1
            break
        fi
        # Рамка — папка (записана с «/» или раскрыта из маски «папка/**»): разрешено только её
        # содержимое. Прежде правило «та же папка» брало её РОДИТЕЛЯ: docs/changes/feat-528/**
        # пускало планы всех фич, supabase/migrations/ — всю supabase/ (v9.0.4).
        case "$affected" in
            */) if [[ "$file" == "$affected"* ]]; then MATCHED=1; break; fi; continue ;;
        esac
        # Match если в той же папке (parent dir of affected)
        affected_dir="${affected%/*}"; [ "$affected_dir" = "$affected" ] && affected_dir="."
        if [[ "$file" == "$affected_dir"/* ]]; then
            MATCHED=1
            break
        fi
    done <<< "$AFFECTED"
    if [ "$MATCHED" -eq 0 ] && ! always_allowed "$file"; then
        VIOLATIONS+=("$file")
    fi
done < <(git diff --cached --name-only -z)

if [ ${#VIOLATIONS[@]} -gt 0 ]; then
    cat >&2 <<EOF
🚨 SCOPE LEAK BLOCKED.

Active feature: $ACTIVE

Файлы вне scope активной фичи:
$(printf '  ❌ %s\n' "${VIOLATIONS[@]}")

Affected files declared:
$(printf '%s\n' "$DECLARED" | sed 's/^/  - /')

WIP=1 / surgical changes invariant: diff ⊆ feature.affected_files.

Что делать:
1. Если эти файлы должны быть частью текущей фичи — добавь их в feature.affected_files
2. ЕСЛИ нет — выноси в отдельную фичу (/feature add ...) и работай WIP=1
3. Не делай drive-by changes (anti-pattern AP-1)
4. Файл служебный и нужен проекту при любой фиче — впиши маску в .harness/scope-allow

Чтобы СРОЧНО override (на свой страх): git commit --no-verify
(это инцидент: сам занеси его в error-journal.md как scope_leak — автоматически обход нигде не записывается)
EOF
    exit 1
fi

exit 0
