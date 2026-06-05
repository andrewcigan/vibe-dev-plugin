#!/bin/bash
# Vibe Dev v6 — state-transition check (вызывается hooks/dispatch-pre-tool-use.sh).
#
# Валидирует ИТОГОВОЕ содержимое feature_list.json ПОСЛЕ применения инструмента
# (намерение из tool_input), а НЕ текущее состояние диска. Это семантика PreToolUse:
# проверяем то, что агент СОБИРАЕТСЯ записать, ДО записи.
#   - Write      → tool_input.content (полное новое содержимое)
#   - Edit       → диск + замена old_string→new_string
#   - MultiEdit  → диск + последовательные замены
# Payload приходит через env HOOK_PAYLOAD (ставит dispatcher из stdin).
#
# VERSION-AWARENESS (H2): уровень СТРУКТУРНЫХ ошибок (невалидный state, битый JSON) —
# BLOCK для актуального проекта, но WARN для legacy (нет .harness/engine-version или major<6)
# и для learn-mode. UI-evidence (UI→passing без user-evidence) — ВСЕГДА hard BLOCK
# (критичный инвариант B2/feat-204, не понижается ни legacy, ни learn). Живые проекты
# переводятся на strict командой /upgrade-project (ставит engine-version + strict).
#
# Печатает на stdout строки "<VERDICT><TAB><msg>": BLOCK или WARN. Пусто = OK. Всегда exit 0.

set -u
FILE="${1:-}"
CWD="${2:-$PWD}"
ROOT="${3:-}"
TOOL="${4:-Write}"

SCHEMA_FILE="$ROOT/schemas/feature-state-transitions.yaml"
[ -f "$SCHEMA_FILE" ] || exit 0   # нет схемы — fail-open

# Уровень для СТРУКТУРНЫХ ошибок: BLOCK, понижается до WARN в learn-mode ИЛИ legacy-проекте.
SOFT_LEVEL="BLOCK"
if [ -f "$CWD/.harness/hook-mode" ] && [ "$(tr -d '[:space:]' < "$CWD/.harness/hook-mode" 2>/dev/null)" = "learn" ]; then
  SOFT_LEVEL="WARN"
fi
# legacy = нет .harness/engine-version или major-версия < 6 (актуальный движок — 6.x)
IS_LEGACY=1
if [ -f "$CWD/.harness/engine-version" ]; then
  EV="$(tr -d '[:space:]' < "$CWD/.harness/engine-version" 2>/dev/null)"
  case "$EV" in 6.*|6|7.*|7|8.*|8|9.*|9) IS_LEGACY=0 ;; esac
fi
[ "$IS_LEGACY" = "1" ] && SOFT_LEVEL="WARN"

# HOOK_PAYLOAD наследуется из env (выставил dispatcher). python3 видит его через os.environ.
python3 - "$FILE" "$SCHEMA_FILE" "$SOFT_LEVEL" "$TOOL" <<'PYEOF'
import json, sys, re, os

target, schema_path, soft_level, tool = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
TAB = "\t"

def emit(verdict, msg):
    # одна строка на вердикт; переводы строк в msg схлопываем (формат "VERDICT\tmsg")
    print(verdict + TAB + " ".join(str(msg).split()))

def read_disk(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return None

def resolve_intended(tool, target):
    """Итоговое содержимое файла ПОСЛЕ применения инструмента (намерение, не диск)."""
    raw = os.environ.get('HOOK_PAYLOAD', '')
    tool_input = {}
    try:
        if raw:
            tool_input = (json.loads(raw).get('tool_input') or {})
    except Exception:
        tool_input = {}

    if tool == 'Write':
        return tool_input.get('content')
    if tool == 'Edit':
        base = read_disk(target)
        base = '' if base is None else base
        old = tool_input.get('old_string', '')
        new = tool_input.get('new_string', '')
        if old == '' and base == '':
            return new  # создание нового файла через Edit (редкий путь)
        if tool_input.get('replace_all'):
            return base.replace(old, new)
        return base.replace(old, new, 1)
    if tool == 'MultiEdit':
        base = read_disk(target)
        base = '' if base is None else base
        for e in (tool_input.get('edits') or []):
            old = e.get('old_string', '')
            new = e.get('new_string', '')
            if e.get('replace_all'):
                base = base.replace(old, new)
            else:
                base = base.replace(old, new, 1)
        return base
    # неизвестный инструмент — fallback на диск (как раньше), безопасно
    return read_disk(target)

def load_schema_simple(path):
    """Минимальная загрузка YAML без модуля yaml (regex по базовым полям)."""
    schema = {"states": [], "allowed_transitions": {}, "categories": []}
    with open(path) as f:
        content = f.read()
    in_states = in_transitions = in_categories = False
    current_from = None
    for line in content.split('\n'):
        stripped = line.strip()
        if stripped.startswith('states:'):
            in_states, in_transitions, in_categories = True, False, False
            continue
        if stripped.startswith('allowed_transitions:'):
            in_states, in_transitions, in_categories = False, True, False
            continue
        if stripped.startswith('categories:'):
            in_states, in_transitions, in_categories = False, False, True
            continue
        if (stripped.startswith('evidence_required:') or stripped.startswith('category_patterns:')
                or stripped.startswith('hook_modes:')):
            in_states = in_transitions = in_categories = False
            continue
        if in_states and stripped.startswith('-'):
            state = stripped.split('#')[0].replace('-', '').strip()
            if state:
                schema["states"].append(state)
        if in_categories and stripped.startswith('-'):
            cat = stripped.split('#')[0].replace('-', '').strip()
            if cat:
                schema["categories"].append(cat)
        if in_transitions:
            if re.match(r'^\s{2}\w+:', line):
                current_from = stripped.rstrip(':').strip()
                schema["allowed_transitions"][current_from] = []
            elif current_from and stripped.startswith('-'):
                ts = stripped.split('#')[0].replace('-', '').strip()
                if ts:
                    schema["allowed_transitions"][current_from].append(ts)
    return schema

content = resolve_intended(tool, target)
if content is None:
    sys.exit(0)  # нет намерения и нет диска — нечего проверять (fail-open)

try:
    schema = load_schema_simple(schema_path)
except Exception:
    sys.exit(0)  # схему не прочитали — fail-open

try:
    data = json.loads(content)
except Exception as e:
    # битый JSON — структурная ошибка (soft): block в актуальном, warn в legacy/learn
    emit(soft_level, "feature_list.json станет невалидным JSON после правки: %s" % e)
    sys.exit(0)

errors_hard, errors_soft, warnings = [], [], []
features = data.get('features', {})

all_features = []
for state_bucket, feats in features.items():
    if not isinstance(feats, list):
        continue
    for f in feats:
        if not isinstance(f, dict):
            continue
        feat_id = f.get('id', '???')
        feat_state = f.get('state', state_bucket)
        expected = state_bucket.replace('_list', '').rstrip('s') if state_bucket != 'active_list' else 'active'
        if feat_state != expected and expected != 'active' and feat_state != 'active':
            if not (expected == 'done' and feat_state == 'passing'):
                warnings.append("%s: bucket=%s но state=%s — рассогласование" % (feat_id, state_bucket, feat_state))
        all_features.append((feat_id, feat_state, f))

valid_states = set(schema["states"])
for feat_id, state, f in all_features:
    if state not in valid_states and state not in ('done',):
        errors_soft.append("%s: state '%s' не в schema (разрешены: %s)" % (feat_id, state, sorted(valid_states)))

for feat_id, state, f in all_features:
    if state in ('passing', 'done'):
        evidence = f.get('evidence', {}) or {}
        if not evidence and not f.get('verification', {}).get('layer_1_syntax'):
            warnings.append("%s: state=passing, но evidence отсутствует (нужны layer_1..N timestamps)" % feat_id)
        category = f.get('category', '')
        affected = f.get('affected_files', []) or []
        is_ui = (category == 'ui') or any(
            isinstance(af, str) and re.search(r'(components|pages|app/.*\.tsx|app/.*\.jsx|\.vue|\.svelte)', af)
            for af in affected
        )
        if is_ui:
            if not (evidence.get('layer_4_user_at') or evidence.get('layer_5_user_at')):
                # UI-evidence — критичный инвариант B2/feat-204: hard BLOCK всегда (не понижается)
                errors_hard.append("%s: UI-фича в passing БЕЗ layer_4/5 user-evidence (скриншот/прогон). Закрывает B2 (feat-204)." % feat_id)

# Active-gate: фича в active требует артефакты, которые должны родиться ДО реализации.
# Нет артефакта = этап пропущен = нельзя в active. Закрывает H7 (критику/ревью просили
# «по-доброму» — и пропускали). S-фичи (light path) не требуют test-strategy.
#   - M/L-фича → docs/test-strategy.md с её id (dual critique → synthesizer)
#   - data-фича (category=data или schema/migrations в affected) → docs/data-model-review.md с её id
proj_root = os.path.dirname(os.path.abspath(target))

def _read_rel(rel):
    p = os.path.join(proj_root, rel)
    try:
        return open(p).read() if os.path.exists(p) else ''
    except Exception:
        return ''

def _read_dir(reldir):
    """Конкатенация всех *.md в каталоге (для docs/research/<domain>.md — их может быть много)."""
    d = os.path.join(proj_root, reldir)
    out = ''
    try:
        if os.path.isdir(d):
            for fn in sorted(os.listdir(d)):
                if fn.endswith('.md'):
                    try:
                        out += open(os.path.join(d, fn)).read() + '\n'
                    except Exception:
                        pass
    except Exception:
        pass
    return out

ts_content = _read_rel(os.path.join('docs', 'test-strategy.md'))
dm_content = _read_rel(os.path.join('docs', 'data-model-review.md'))
research_content = _read_dir(os.path.join('docs', 'research'))

for feat_id, state, f in all_features:
    if state != 'active':
        continue
    size = (f.get('size_estimate') or '').upper()
    if size in ('M', 'L') and feat_id not in ts_content:
        errors_soft.append(
            "%s: фича размера %s переходит в active без критики — нет docs/test-strategy.md с её id. "
            "Запусти dual critique (test-researcher + user-perspective-critic) → synthesizer, ПОТОМ active. Закрывает H7." % (feat_id, size))
    affected = f.get('affected_files', []) or []
    is_data = (f.get('category', '') == 'data') or any(
        isinstance(af, str) and re.search(r'(schema|migrations|prisma|drizzle)', af) for af in affected)
    if is_data and feat_id not in dm_content:
        errors_soft.append(
            "%s: data-фича в active без ревью модели — нет docs/data-model-review.md с её id. "
            "Запусти data-model-reviewer ПЕРЕД реализацией схемы (глобальное правило ~/CLAUDE.md)." % feat_id)
    is_integration = (f.get('category', '') == 'integration') or any(
        isinstance(af, str) and re.search(r'(scraper|fetcher|/providers?/|external)', af, re.I) for af in affected)
    if is_integration and feat_id not in research_content:
        errors_soft.append(
            "%s: integration-фича в active без research поставщика — нет docs/research/*.md с её id. "
            "Архитектура держит АБСТРАКЦИЮ (интерфейс), конкретный поставщик выбирается отдельной "
            "research-фазой (5-7 вариантов + матрица сравнения) ПЕРЕД реализацией. Закрывает vendor-lock (~/CLAUDE.md)." % feat_id)

for e in errors_hard:
    emit("BLOCK", e)
for e in errors_soft:
    emit(soft_level, e)
for w in warnings:
    emit("WARN", w)
PYEOF
exit 0
