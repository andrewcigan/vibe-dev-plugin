#!/bin/bash
# Vibe Dev v5.1 — Stuck Watcher (Background Daemon)
#
# Запускается в фоне init.sh при /new-project и при каждом /resume.
# Мониторит: время без commit и без test-pass.
# При срабатывании пишет alert в SESSION.md.
#
# Закрывает паттерн залипания: 3+ часа без commit/test-pass на одной задаче.

PROJECT_ROOT="${PWD}"
THRESHOLD_MIN_PROMPT=30   # 30 мин — мягкий prompt в SESSION.md
THRESHOLD_MIN_STUCK=45    # 45 мин — auto-trigger /stuck
CHECK_INTERVAL_SEC=300    # каждые 5 минут

# Skip if outside Vibe Dev project
if [ ! -f "$PROJECT_ROOT/feature_list.json" ]; then
    exit 0
fi

# PID file
PIDFILE="$PROJECT_ROOT/.harness/stuck-watcher.pid"
mkdir -p "$(dirname "$PIDFILE")"

# Check if already running
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "stuck-watcher уже работает PID=$OLD_PID"
        exit 0
    fi
fi

# Daemonize
(
    echo $$ > "$PIDFILE"

    LAST_PROGRESS=$(date +%s)
    PROMPT_SENT=0

    while true; do
        sleep "$CHECK_INTERVAL_SEC"

        # Detect progress: new commit OR test pass
        LAST_COMMIT=$(git -C "$PROJECT_ROOT" log -1 --format=%at 2>/dev/null || echo 0)

        # Check for test-pass marker in SESSION.md (last_test_pass timestamp)
        LAST_TEST_PASS=$(grep "Last test pass:" "$PROJECT_ROOT/SESSION.md" 2>/dev/null | tail -1 | grep -oE "[0-9]{10,}" || echo 0)

        # Latest progress timestamp
        LATEST=$LAST_COMMIT
        if [ "$LAST_TEST_PASS" -gt "$LATEST" ]; then
            LATEST=$LAST_TEST_PASS
        fi

        NOW=$(date +%s)
        AGE_SEC=$(( NOW - LATEST ))
        AGE_MIN=$(( AGE_SEC / 60 ))

        # Soft prompt at 30 min
        if [ "$AGE_MIN" -ge "$THRESHOLD_MIN_PROMPT" ] && [ "$PROMPT_SENT" -eq 0 ]; then
            cat >> "$PROJECT_ROOT/SESSION.md" <<EOF

---
## 🟡 Stuck Watcher Alert ($(date '+%Y-%m-%d %H:%M'))

$AGE_MIN мин без commit/test-pass на активной фиче.

Похоже на залипание? Если 2+ ретраи одного подхода — запусти /stuck (LLM-кворум).
Если нет — проигнорируй, я подожду ещё 15 мин.

EOF
            PROMPT_SENT=1
        fi

        # Hard trigger at 45 min — auto /stuck
        if [ "$AGE_MIN" -ge "$THRESHOLD_MIN_STUCK" ]; then
            cat >> "$PROJECT_ROOT/SESSION.md" <<EOF

---
## 🚨 Auto-trigger /stuck ($(date '+%Y-%m-%d %H:%M'))

$AGE_MIN мин без progress (порог: $THRESHOLD_MIN_STUCK мин).

Stuck-protocol activated. Создан docs/stuck-statements/auto-$(date +%s).md (нужно заполнить через subagent stuck-protocol-handler).

EOF
            # Записать триггер в error-journal если он существует
            if [ -f "$PROJECT_ROOT/error-journal.md" ]; then
                cat >> "$PROJECT_ROOT/error-journal.md" <<EOF

## err-AUTO-$(date +%s) | $(date '+%Y-%m-%d %H:%M') | stuck-auto
**Триггер**: stuck-watcher auto ($AGE_MIN мин без progress)
**Класс ошибки**: stuck_timeout
**Status**: ожидает stuck-protocol-handler subagent
EOF
            fi

            # Reset для следующего цикла
            PROMPT_SENT=0
            LAST_PROGRESS=$NOW
        fi

        # Если был commit / test-pass → reset
        if [ "$LATEST" -gt "$LAST_PROGRESS" ]; then
            LAST_PROGRESS=$LATEST
            PROMPT_SENT=0
        fi
    done
) &

# Disown so it survives script exit
disown
echo "✓ stuck-watcher запущен (PID=$!) — alerts через $THRESHOLD_MIN_PROMPT мин, auto-trigger через $THRESHOLD_MIN_STUCK мин"
