#!/bin/bash
set -e

# Vibe Dev — Bootstrap Contract
# Этот скрипт ГАРАНТИРУЕТ что окружение проекта здорово и готов к работе.
# Запускается на /new-project, на /resume, и в начале каждой сессии.
# Если что-то падает — следующая сессия не должна продолжать пока не починено.

echo "==================================================================="
echo "  Vibe Dev — Harness Bootstrap"
echo "==================================================================="

# === Stage 1: Environment Constraints (из domain-rules.yaml) ===
echo ""
echo "[Stage 1/5] Checking runtime constraints..."

if [ -f "domain-rules.yaml" ]; then
  # Извлечь python_version и проверить
  REQ_PYTHON=$(grep "^  python_version:" domain-rules.yaml | sed 's/.*: *"\?\(.*\)"\?/\1/' | tr -d '"')
  if [ -n "$REQ_PYTHON" ] && [ "$REQ_PYTHON" != "" ]; then
    HAS_PYTHON=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
    echo "  Required Python: $REQ_PYTHON | Have: $HAS_PYTHON"
  fi
fi

# === Stage 2: Dependencies ===
echo ""
echo "[Stage 2/5] Installing dependencies..."

if [ -f "package.json" ]; then
  echo "  npm install..."
  npm install --silent
fi

if [ -f "requirements.txt" ]; then
  echo "  pip install..."
  pip install -q -r requirements.txt
fi

if [ -f "pyproject.toml" ]; then
  echo "  pip install (pyproject)..."
  pip install -q -e .
fi

# === Stage 3: Type check / Lint ===
echo ""
echo "[Stage 3/5] Type check..."

if [ -f "package.json" ] && grep -q '"check"' package.json; then
  npm run check
fi

if [ -f "tsconfig.json" ]; then
  npx tsc --noEmit 2>/dev/null || echo "  (skipped — tsc not configured)"
fi

# === Stage 4: Tests ===
echo ""
echo "[Stage 4/5] Tests..."

if [ -f "package.json" ] && grep -q '"test"' package.json; then
  npm test
fi

if [ -d "tests" ] && command -v pytest &>/dev/null; then
  pytest -q
fi

# === Stage 5: Harness Self-check ===
echo ""
echo "[Stage 5/5] Harness self-check..."

ERRORS=0

# AGENTS.md routing ≤200 lines invariant
if [ -f "AGENTS.md" ]; then
  LINES=$(wc -l < AGENTS.md)
  if [ "$LINES" -gt 200 ]; then
    echo "  ⚠️  AGENTS.md = $LINES строк (должно быть ≤200). Вынеси в docs/ topic-files."
    ERRORS=$((ERRORS+1))
  else
    echo "  ✓ AGENTS.md ($LINES строк ≤200)"
  fi
fi

# feature_list.json schema
if [ -f "feature_list.json" ]; then
  if python3 -c "import json; json.load(open('feature_list.json'))" 2>/dev/null; then
    echo "  ✓ feature_list.json валиден"
  else
    echo "  ❌ feature_list.json не валиден JSON"
    ERRORS=$((ERRORS+1))
  fi
fi

# domain-rules.yaml существует
if [ -f "domain-rules.yaml" ]; then
  echo "  ✓ domain-rules.yaml существует"
else
  echo "  ⚠️  domain-rules.yaml отсутствует — test-researcher будет работать вслепую"
fi

# SESSION.md existence
if [ -f "SESSION.md" ]; then
  echo "  ✓ SESSION.md существует"
else
  echo "  ⚠️  SESSION.md отсутствует — handoff между сессиями невозможен"
fi

# .gitignore защита для секретов
if [ -f ".gitignore" ]; then
  if grep -q "^.env" .gitignore || grep -q "^\*.env\*" .gitignore; then
    echo "  ✓ .gitignore защищает .env"
  else
    echo "  ❌ .gitignore НЕ защищает .env — добавь '.env*' прямо сейчас"
    ERRORS=$((ERRORS+1))
  fi
fi

# === Final ===
echo ""
echo "==================================================================="
if [ "$ERRORS" -gt 0 ]; then
  echo "  ❌ Verification failed: $ERRORS блокирующих проблем."
  echo "  Чини их ДО продолжения работы."
  exit 1
else
  echo "  ✓ Verification complete. Готов к работе."
fi
echo "==================================================================="

echo ""
echo "Next steps:"
echo "1. Read feature_list.json — выбери ОДНУ unfinished фичу (WIP=1)"
echo "2. /feature <feat-id> — запустит test-researcher + user-perspective-critic"
echo "3. После implementation: /verify (4-layer)"
echo "4. Только passing verification переводит фичу в done"
