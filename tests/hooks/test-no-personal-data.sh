#!/bin/bash
# TDD-тест gate обезличенности (scripts/check-no-personal-data.sh) — v6.1.
#
# Воспроизводит РЕАЛЬНЫЙ триггер: личная строка в реальном shipped-ПУТИ (песочница через CHECK_ROOT),
# а не суррогат на диске. Урок hook-test-must-replay-real-trigger: тест бьёт по тому же входу,
# что и боевой механизм (содержимое файла в shipped-директории), иначе зелёный тест маскирует дыру.
#
# Внутри тестовых строк НАМЕРЕННО присутствуют личные маркеры — это фикстуры; сам файл теста
# исключён из боевого grep по имени (см. check-no-personal-data.sh).
set -u

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$PLUGIN_ROOT/scripts/check-no-personal-data.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() { # desc, expected_exit, actual_exit
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; PASS=$((PASS+1));
  else echo "  ✗ $1 (ожидал exit $2, получил $3)"; FAIL=$((FAIL+1)); fi
}

# --- Сценарий 1: имя/токен автора в shipped → gate ловит (exit 1) ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/rules"
printf 'Источник: память проекта gypsy\n' > "$TMP/rules/x.md"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "ловит токен автора 'gypsy' в rules/" 1 $?

# --- Сценарий 2: имя реального проекта → ловит ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/templates"
printf '# пример из DocAItechConstruct\n' > "$TMP/templates/y.yaml"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "ловит имя проекта 'DocAItechConstruct' в templates/" 1 $?

# --- Сценарий 3: личный абсолютный путь → ловит ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/skills/foo"
printf 'claude --plugin-dir /Users/gypsy/x\n' > "$TMP/skills/foo/SKILL.md"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "ловит личный путь '/Users/gypsy' в skills/" 1 $?

# --- Сценарий 4: ссылка на личный портрет → ловит ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/agents"
printf 'см. ~/PortraitMD/USER_PORTRAIT.md\n' > "$TMP/agents/a.md"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "ловит ссылку на личный портрет в agents/" 1 $?

# --- Сценарий 5: чистый shipped → проходит (exit 0) ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/rules" "$TMP/agents"
printf 'Источник: реальный CRM-проект. Урок: проверяй инфраструктуру сам.\n' > "$TMP/rules/clean.md"
printf 'Нейтральный агент-ревьюер.\n' > "$TMP/agents/clean.md"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "пропускает обезличенный shipped" 0 $?

# --- Сценарий 6: dev-доки вне shipped игнорируются (личное в docs/ НЕ валит gate) ---
rm -rf "${TMP:?}"/*; mkdir -p "$TMP/rules" "$TMP/docs"
printf 'чисто\n' > "$TMP/rules/ok.md"
printf 'история: blogger-crm, cert-finder, /Users/gypsy\n' > "$TMP/docs/internal.md"
CHECK_ROOT="$TMP" bash "$GATE" >/dev/null 2>&1; check "игнорирует личное в dev-доках (docs/ не публикуется)" 0 $?

# --- Сценарий 7: РЕАЛЬНЫЙ плагин обезличен (живой запуск без CHECK_ROOT) ---
bash "$GATE" >/dev/null 2>&1; check "реальный плагин обезличен (живой запуск)" 0 $?

echo ""
echo "no-personal-data: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
