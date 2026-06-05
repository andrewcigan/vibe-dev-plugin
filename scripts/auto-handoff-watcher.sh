#!/bin/bash
# Vibe Dev — Auto-Handoff Watcher
#
# Реагирует на tmux session-end signal или 4 часа неактивности.
# Запускает /handoff автоматически.

PROJECT_ROOT="${PWD}"
INACTIVITY_HOURS=4

if [ ! -f "$PROJECT_ROOT/SESSION.md" ]; then
    exit 0
fi

# Tmux detach hook — устанавливается через ~/.tmux.conf
# В этом скрипте просто реакция на запуск (вызывается из tmux hook или cron)

LAST_UPDATE=$(stat -f %m "$PROJECT_ROOT/SESSION.md" 2>/dev/null || echo 0)
NOW=$(date +%s)
AGE_HOURS=$(( (NOW - LAST_UPDATE) / 3600 ))

if [ "$AGE_HOURS" -ge "$INACTIVITY_HOURS" ]; then
    # Записать flag — на следующий /resume будет prompt про auto-handoff
    cat >> "$PROJECT_ROOT/SESSION.md" <<EOF

---
## ⏰ Auto-Handoff Triggered ($(date '+%Y-%m-%d %H:%M'))

Сессия неактивна $AGE_HOURS часов. Запускаю авто-handoff.

Проверка 5-dimensions clean-exit (build / tests / progress / artifacts / startup) откладывается до следующего /resume.

EOF
    echo "✓ Auto-handoff flag установлен в SESSION.md"
fi
