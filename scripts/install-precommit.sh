#!/bin/bash
# Vibe Dev v6.2 — установка git pre-commit в проект (activation backstop + WIP=1 scope).
#
# Зовут: bootstrap (/new-project) и /upgrade-project. Идемпотентен.
# Раньше pre-commit-scope.sh лежал только в плагине и НИКОГДА не устанавливался в проекты
# (механизм «written-not-active» — ровно класс провала П-A из аудита). Теперь установка —
# обязанность bootstrap, а сам hook несёт ещё и backstop активации (независимый канал:
# работает, даже если плагин Claude Code не загрузился).
#
# Использование: bash install-precommit.sh [<путь-проекта>]

set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ="${1:-$PWD}"

if [ ! -d "$PROJ/.git" ]; then
  echo "⚠️  $PROJ — не git-репозиторий: pre-commit backstop не установлен (сделай git init и повтори)."
  exit 0
fi

mkdir -p "$PROJ/.harness/hooks" "$PROJ/.git/hooks"

# 1) Копия scope-проверки в проект (самодостаточность: плагин может обновиться/исчезнуть).
cp "$PLUGIN_ROOT/hooks/pre-commit-scope.sh" "$PROJ/.harness/hooks/pre-commit-scope.sh"
chmod +x "$PROJ/.harness/hooks/pre-commit-scope.sh"

# 2) Сам pre-commit (backstop + вызов scope). Существующий НЕ-vibe pre-commit не затираем.
TARGET="$PROJ/.git/hooks/pre-commit"
if [ -f "$TARGET" ] && ! grep -q "Vibe Dev" "$TARGET" 2>/dev/null; then
  echo "⚠️  В проекте уже есть посторонний .git/hooks/pre-commit — не трогаю."
  echo "    Чтобы добавить Vibe Dev backstop, объедини вручную с templates/git-pre-commit.sh."
  exit 0
fi
cp "$PLUGIN_ROOT/templates/git-pre-commit.sh" "$TARGET"
chmod +x "$TARGET"

echo "✅ pre-commit установлен: activation backstop + WIP=1 scope (.git/hooks/pre-commit)."
