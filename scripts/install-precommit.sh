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
# Путь к плагину в кавычках оболочки (одинарная кавычка внутри экранируется) — для копии сторожа и
# для советов ниже: пробел, кириллица, $, кавычки и обратная кавычка в пути ничего не ломают.
QUOTED="'$(printf '%s' "$PLUGIN_ROOT" | sed "s/'/'\\\\''/g")'"

# Корень репозитория. Сторож коммитов ищет журнал фич в корне репозитория (git rev-parse
# --show-toplevel), и копия проверки границ ложится туда же. Вызов из подпапки приводится к корню:
# иначе в подпапке появлялся лишний .harness, и поиск корня проекта находил уже его (v9.0.3).
# Рабочая копия (git worktree) — свой корень, .git там файл, а не папка.
TOP="$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$TOP" ]; then
  echo "⚠️  $PROJ — не git-репозиторий: pre-commit backstop не установлен (сделай git init и повтори)."
  exit 0
fi
if [ ! -d "$TOP/.harness" ] && [ ! -f "$TOP/feature_list.json" ]; then
  echo "⚠️  В корне репозитория ($TOP) нет проекта Vibe Dev (.harness/ или feature_list.json): pre-commit backstop не установлен."
  echo "    Сторож коммитов проверяет журнал фич в корне репозитория — проект в подпапке он не охранял бы, а «установлен» было бы неправдой."
  exit 0
fi
PROJ="$TOP"

# Каталог хуков, который git реально вызывает, — и общий каталог репозитория (у рабочих копий он
# один на всех). Не совпали — хуки перенаправлены (husky и т.п., core.hooksPath): сторож в общем
# каталоге не сработал бы ни разу. Явно заданный стандартный каталог перенаправлением не считается.
# Пути — без ключа --path-format (его нет в git старше 2.31): от корня репозитория и физически.
abspath() {
  local p
  case "$1" in /*) p="$1" ;; *) p="$TOP/$1" ;; esac
  if [ -d "$p" ]; then (cd "$p" && pwd -P); else printf '%s' "$p"; fi
}
COMMON_HOOKS="$(abspath "$(git -C "$TOP" rev-parse --git-common-dir)")/hooks"
ACTIVE_HOOKS="$(abspath "$(git -C "$TOP" rev-parse --git-path hooks)")"
if [ "$ACTIVE_HOOKS" != "$COMMON_HOOKS" ]; then
  echo "⚠️  В проекте хуки перенаправлены (git вызывает хуки из $ACTIVE_HOOKS): pre-commit backstop не установлен."
  echo "    Объедини вручную: вызови из своего pre-commit копию $PLUGIN_ROOT/templates/git-pre-commit.sh"
  echo "    (в строке VIBE_PLUGIN_ROOT= метку замени на путь к плагину в кавычках оболочки: $QUOTED)."
  exit 0
fi
HOOKS_DIR="$COMMON_HOOKS"

mkdir -p "$PROJ/.harness/hooks" "$HOOKS_DIR"

# 1) Копия scope-проверки в проект (самодостаточность: плагин может обновиться/исчезнуть).
cp "$PLUGIN_ROOT/hooks/pre-commit-scope.sh" "$PROJ/.harness/hooks/pre-commit-scope.sh"
chmod +x "$PROJ/.harness/hooks/pre-commit-scope.sh"

# 2) Сам pre-commit (backstop + вызов scope). Существующий НЕ-vibe pre-commit не затираем.
TARGET="$HOOKS_DIR/pre-commit"
if [ -f "$TARGET" ] && ! grep -q "Vibe Dev" "$TARGET" 2>/dev/null; then
  echo "⚠️  В проекте уже есть посторонний pre-commit ($TARGET) — не трогаю."
  echo "    Чтобы добавить Vibe Dev backstop, объедини вручную с $PLUGIN_ROOT/templates/git-pre-commit.sh"
  echo "    (в строке VIBE_PLUGIN_ROOT= метку замени на путь к плагину в кавычках оболочки: $QUOTED)."
  exit 0
fi
# Путь к плагину вписывается в копию (v9.0.3). Она лежит в .git/hooks и сама его не знает, а её
# подсказки называют писателя истории и восстановление — скрипты плагина, которых в проекте нет.
# Прежняя подсказка «scripts/record-change.sh» не исполнялась, и проект написал собственного писателя.
# Подстановка — без python3: блок активации в копии — чистый bash и должен ставиться там же, где
# ставился раньше. Запись через временный файл: сорвалась подстановка — прежний сторож на месте.
TEMPLATE="$PLUGIN_ROOT/templates/git-pre-commit.sh"
MARK="__VIBE_PLUGIN_ROOT__"
if [ "$(grep -c "$MARK" "$TEMPLATE" 2>/dev/null)" != "1" ]; then
  echo "❌ pre-commit не установлен: в шаблоне $TEMPLATE нет ровно одной метки пути плагина."
  exit 1
fi
if ! VIBE_QUOTED="$QUOTED" awk -v m="$MARK" '{ i = index($0, m); if (i) $0 = substr($0, 1, i - 1) ENVIRON["VIBE_QUOTED"] substr($0, i + length(m)); print }' \
     "$TEMPLATE" > "$TARGET.vibe-tmp"; then
  rm -f "$TARGET.vibe-tmp"
  echo "❌ pre-commit не установлен: не удалось вписать путь к плагину."
  exit 1
fi
# Прежняя копия отличается — сохраняем её рядом с отметкой времени (держим три последние): после
# ручного слияния в ней могли быть свои строки, а метка «Vibe Dev» в слитом файле не отличает его от
# чистой копии. Одно поколение терялось на второй переустановке.
if [ -f "$TARGET" ] && ! cmp -s "$TARGET" "$TARGET.vibe-tmp"; then
  BAK="$TARGET.vibe-prev-$(date '+%Y%m%d-%H%M%S')-$$"
  cp "$TARGET" "$BAK"
  echo "   прежний pre-commit сохранён: $BAK (если в нём были свои строки — перенеси их)"
  ls -1t "$TARGET".vibe-prev-* 2>/dev/null | tail -n +4 | while IFS= read -r old; do rm -f "$old"; done
fi
mv "$TARGET.vibe-tmp" "$TARGET"
chmod +x "$TARGET"

echo "✅ pre-commit установлен: activation backstop + WIP=1 scope ($TARGET); подсказки ведут в $PLUGIN_ROOT."
