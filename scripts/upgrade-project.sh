#!/bin/bash
# Vibe Dev v6 — /upgrade-project механика.
# Переводит живой (legacy) vibe-проект на актуальный движок: ставит engine-version,
# strict-профиль, снимает learn-mode. Идемпотентен. Закрывает H2 (живые проекты не
# ломаются автоматически — апгрейд только по явной команде пользователя).
#
# Использование: bash upgrade-project.sh [<путь-проекта>]   (по умолчанию — текущая папка)

set -u
# Пин на АКТУАЛЬНЫЙ мажор плагина (динамически из манифеста рядом со скриптом).
_SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_MAJ="$(jq -r '.version // empty' "$_SD/../.claude-plugin/plugin.json" 2>/dev/null | cut -d. -f1)"
case "$_MAJ" in ''|*[!0-9]*) _MAJ=7 ;; esac
ENGINE="${_MAJ}.0"
PROJ="${1:-$PWD}"

if [ ! -d "$PROJ/.harness" ] && [ ! -f "$PROJ/feature_list.json" ]; then
  echo "❌ Не похоже на vibe-проект (нет .harness/ и feature_list.json): $PROJ"
  exit 1
fi

mkdir -p "$PROJ/.harness"
PREV="нет (legacy/pre-v6)"
[ -f "$PROJ/.harness/engine-version" ] && PREV="$(tr -d '[:space:]' < "$PROJ/.harness/engine-version")"

echo "$ENGINE" > "$PROJ/.harness/engine-version"
# Двухфазная активация (v6.2 F2): пишем pending-strict; в боевой strict переведёт ТОЛЬКО
# живой хук (SessionStart/UserPromptSubmit) — факт перевода = доказательство, что хуки
# физически работают. Профиль «strict» без активных хуков больше невозможен по построению.
echo "pending-strict" > "$PROJ/.harness/profile"
rm -f "$PROJ/.harness/hook-mode"

# Независимый backstop: git pre-commit (activation + WIP=1 scope) — работает даже без плагина.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install-precommit.sh" "$PROJ"

echo "✅ Проект переведён на движок $ENGINE (было: $PREV)."
echo "   Профиль: pending-strict — боевым strict станет при первом срабатывании живого хука"
echo "   (первое сообщение в сессии Claude Code в этой папке). Если профиль остаётся pending —"
echo "   хуки НЕ работают: pre-commit backstop заблокирует коммиты с диагностикой. learn-mode снят."
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
