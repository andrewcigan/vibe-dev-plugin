#!/bin/bash
# Vibe Dev v6 — /upgrade-project механика.
# Переводит живой (legacy) vibe-проект на актуальный движок: ставит engine-version,
# strict-профиль, снимает learn-mode. Идемпотентен. Закрывает H2 (живые проекты не
# ломаются автоматически — апгрейд только по явной команде пользователя).
#
# Использование: bash upgrade-project.sh [<путь-проекта>]   (по умолчанию — текущая папка)

set -u
ENGINE="6.0"
PROJ="${1:-$PWD}"

if [ ! -d "$PROJ/.harness" ] && [ ! -f "$PROJ/feature_list.json" ]; then
  echo "❌ Не похоже на vibe-проект (нет .harness/ и feature_list.json): $PROJ"
  exit 1
fi

mkdir -p "$PROJ/.harness"
PREV="нет (legacy/pre-v6)"
[ -f "$PROJ/.harness/engine-version" ] && PREV="$(tr -d '[:space:]' < "$PROJ/.harness/engine-version")"

echo "$ENGINE" > "$PROJ/.harness/engine-version"
echo "strict"  > "$PROJ/.harness/profile"
rm -f "$PROJ/.harness/hook-mode"

echo "✅ Проект переведён на движок $ENGINE (было: $PREV)."
echo "   Профиль: strict. learn-mode снят."
echo ""
echo "Теперь активны как BLOCK:"
echo "  • UI-фича → passing без user-evidence (скриншот/прогон) — был и раньше hard"
echo "  • невалидные переходы state / битый JSON feature_list.json (раньше для legacy были warn)"
echo "  • массовый внешний API без pre-launch-checklist (всегда)"
echo "Advisory (WARN):"
echo "  • возможная параллельная запись в shared-файл (json/csv/jsonl/yaml)"
echo ""
echo "⚠️  Перед апгрейдом убедись, что текущий feature_list.json проходит валидатор —"
echo "    запусти dry-run: открой feature_list.json и проверь, что нет passing-фич без evidence."
