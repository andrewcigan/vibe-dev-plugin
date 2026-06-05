#!/bin/bash
# Vibe Dev v6.1 — Gate обезличенности (no-personal-data).
#
# Shipped-файлы публичного плагина НЕ должны содержать ПРИВАТНЫХ данных: username/личная почта
# автора, внутренний хост, имена реальных проектов, личные абсолютные пути, ссылки на личный портрет.
# Публичное ИМЯ автора в манифесте (осознанная атрибуция) — разрешено, НЕ блокируется.
#
# Тест 3 атрибутов:
#   ГДЕ зафиксирован: этот скрипт + tests/hooks/test-no-personal-data.sh
#   ЧЕМ enforce:      grep по shipped-набору; вызывается из scripts/check-plugin-self.sh (раздел 17)
#   ЧТО при обходе:   личное в shipped → exit 1 → self-check падает → релиз/коммит с личным блокируется (block)
#
# CHECK_ROOT (env) переопределяет корень — для теста на песочнице. По умолчанию = корень плагина.
#
# ГРАНИЦА (честно): gate ловит НАСТОЯЩИЕ утечки личности. Внутренние коды B-XX и предположение
# о папке ~/Coding — стилевая полировка, НЕ личность, в gate НЕ входят (иначе ложные срабатывания
# на легитимных упоминаниях). dev-доки (docs/, SESSION.md, .session-state/) не публикуются → не проверяются.
set -u

ROOT="${CHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" 2>/dev/null || { echo "❌ no-personal-data: корень не найден: $ROOT"; exit 1; }

# Приватные маркеры: username (gypsy), личная почта (andrew.cigan / любой @gmail), внутренний хост
# (tsyhan-llm), имена реальных проектов, личный путь, личный портрет.
# Публичное имя «Andrei Tsyhan» и публичный github-хэндл — НЕ блокируем (это публичная атрибуция).
PATTERN='gypsy|andrew\.cigan|@gmail|tsyhan-llm|DocAItech|blogger-crm|cert-finder|romul|life-agent|BabkaVitalika|korpopushka|Sensei-tsy|PortraitMD|USER_PORTRAIT|/Users/gypsy'

# Shipped-набор (что попадает в публичный плагин). docs/, SESSION.md, .session-state/ исключены (не публикуются).
# docs/ целиком НЕ публикуется (личная история), КРОМЕ traceability.md — он функциональный механизм.
SHIPPED="agents hooks rules schemas skills templates workflow .claude-plugin scripts tests docs/traceability.md CLAUDE.md AGENTS.md README.md CHANGELOG.md"

# Берём только существующие пути (чтобы grep не падал на песочнице теста с неполной структурой).
PATHS=""
for p in $SHIPPED; do [ -e "$p" ] && PATHS="$PATHS $p"; done
[ -z "$PATHS" ] && { echo "❌ no-personal-data: нет shipped-путей в $ROOT"; exit 1; }

# Сам gate и его тест легитимно содержат PATTERN (регэксп-строка / фикстуры) → исключаем по имени.
# shellcheck disable=SC2086
HITS="$(grep -rnIE "$PATTERN" $PATHS 2>/dev/null \
  | grep -vE '(check-no-personal-data\.sh|test-no-personal-data\.sh)')"

if [ -n "$HITS" ]; then
  echo "❌ no-personal-data: найдены личные данные в shipped-файлах (публичный релиз заблокирован):"
  echo "$HITS" | head -20
  CNT="$(printf '%s\n' "$HITS" | grep -c .)"
  [ "$CNT" -gt 20 ] && echo "  ... и ещё $((CNT - 20)) (показаны первые 20)"
  exit 1
fi

echo "✓ no-personal-data: shipped-файлы обезличены"
exit 0
