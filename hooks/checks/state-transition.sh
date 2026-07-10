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

# Провенанс-режим (v8 L3-F1): захват-инвариант активен ТОЛЬКО при engine major ≥ 8 (провенанс —
# контракт v8; v6/v7-проекты на старом контракте не обязаны нести provenance). До миграции спит.
# ВАЖНО (критик C1): это BACKSTOP против ручных правок через Write — канонический путь записи
# record-change.sh идёт через Bash, где основной гейт когерентности head↔log — git pre-commit.
PROV_MODE=0
if [ -f "$CWD/.harness/engine-version" ]; then
  EVMAJ="$(tr -d '[:space:]' < "$CWD/.harness/engine-version" 2>/dev/null | cut -d. -f1)"
  case "$EVMAJ" in ''|*[!0-9]*) : ;; *) [ "$EVMAJ" -ge 8 ] 2>/dev/null && PROV_MODE=1 ;; esac
fi

# HOOK_PAYLOAD наследуется из env (выставил dispatcher). python3 видит его через os.environ.
python3 - "$FILE" "$SCHEMA_FILE" "$SOFT_LEVEL" "$TOOL" "$PROV_MODE" <<'PYEOF'
import json, sys, re, os

target, schema_path, soft_level, tool = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
prov_mode = (len(sys.argv) > 5 and sys.argv[5] == '1')
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

# ЧЕСТНОСТЬ ДЕКЛАРАЦИЙ (v8.0.2 dogfooding LinX): валидируем ИМЯ состояния (∈ valid_states) и
# согласованность bucket↔state (выше). Граф schema["allowed_transitions"] загружается
# load_schema_simple, но переход old→new НАМЕРЕННО НЕ enforced — он неполон для ретрофита
# (passing→awaiting_user_acceptance легитимен при установке харнеса на живой проект, но не в графе;
# enforce дал бы ложные блокировки). Граф = справочник для агентов/людей, не механизм.
valid_states = set(schema["states"])
for feat_id, state, f in all_features:
    if state not in valid_states and state not in ('done',):
        errors_soft.append("%s: state '%s' не в schema (разрешены: %s)" % (feat_id, state, sorted(valid_states)))

# --- Surface (v6.2 F5): поверхность фичи определяет ТИП обязательного evidence. ---
# МОНОТОННАЯ СТРОГОСТЬ: файловая эвристика — всегда ПОЛ; заявленное поле (surface, иначе
# category) может только УЖЕСТОЧИТЬ проверку, никогда не смягчить. Иначе declared=lib
# отключал бы существующий UI-gate (регрессия механизма 2).
SURFACE_RANK = {'ui': 3, 'api': 2, 'service': 2, 'job': 2, 'cli': 2,
                'lib': 1, 'logic': 1, 'content': 1, 'data': 1, 'integration': 1, '': 0}

def heuristic_surface(affected):
    best = ''
    for af in affected:
        if not isinstance(af, str):
            continue
        if re.search(r'(components|pages|app/.*\.tsx|app/.*\.jsx|\.vue|\.svelte)', af):
            return 'ui'  # максимум — дальше не смотрим
        if not best and re.search(r'(/api/|^api/|routes?/|controllers?/|endpoints?/)', af, re.I):
            best = 'api'
        if not best and re.search(r'(jobs?/|cron|workers?/|queue)', af, re.I):
            best = 'job'
        if not best and re.search(r'(^|/)(bin|cli)/', af, re.I):
            best = 'cli'
    return best

for feat_id, state, f in all_features:
    if state in ('passing', 'done'):
        # verification/evidence полиморфны по схеме: словарь (layer_1..N) ЛИБО строка
        # ("e2e: проверил руками") ЛИБО список шагов. Нормализуем тип ПЕРЕД .get(),
        # иначе Python падает на строке/списке → пустой stdout → gate молча пропускает всё.
        evidence_raw = f.get('evidence')
        evidence = evidence_raw if isinstance(evidence_raw, dict) else {}
        verification = f.get('verification')
        has_layer1 = isinstance(verification, dict) and bool(verification.get('layer_1_syntax'))
        category = str(f.get('category') or '').strip().lower()
        affected = f.get('affected_files') or []
        if not isinstance(affected, list):
            affected = []

        declared = str(f.get('surface') or '').strip().lower()
        if not declared and category in SURFACE_RANK:
            declared = category
        heur = heuristic_surface(affected)
        if SURFACE_RANK.get(declared, 0) >= SURFACE_RANK.get(heur, 0):
            eff = declared
        else:
            eff = heur
            if declared:
                warnings.append(
                    "%s: surface='%s', но по affected_files похоже на '%s' — заявленное поле может только "
                    "УЖЕСТОЧАТЬ проверку (эвристика остаётся полом); проверь surface или файлы" % (feat_id, declared, heur))

        size_p = str(f.get('size_estimate') or '').upper()
        if eff == 'ui':
            if not (evidence.get('layer_4_user_at') or evidence.get('layer_5_user_at')):
                # UI-evidence — критичный инвариант B2/feat-204: hard BLOCK всегда (не понижается)
                errors_hard.append("%s: UI-фича в passing БЕЗ layer_4/5 user-evidence (скриншот/прогон). Закрывает B2 (feat-204)." % feat_id)
        elif eff in ('api', 'service', 'job', 'cli'):
            # Evidence по типу поверхности (lane-таблица): след РЕАЛЬНОГО вызова, не юнит-тесты.
            # Мягкий ввод v6.2: WARN (не block) — на живых проектах старые passing-фичи без evidence
            # не должны заблокировать исправление файла; ужесточение до SOFT_LEVEL — после обкатки.
            if not evidence_raw:
                warnings.append(
                    "%s: surface=%s в passing БЕЗ evidence. Нужен след реального вызова: api — curl+статус; "
                    "job — лог реального прогона; cli — команда+exit code; service — behavior-probe "
                    "(не pgrep). Заполни evidence." % (feat_id, eff))
        elif eff in ('lib', 'logic'):
            # v8 L5-F2 (c9, монотонная строгость): бизнес-логику typecheck+lint НЕ ловят —
            # разъехавшееся ПОВЕДЕНИЕ ловит только прогон. passing logic-фичи требует след
            # runtime/e2e (layer_2/3/4 timestamp ИЛИ evidence-строка «прогнал X»), НЕ только
            # layer_1_syntax. Это BLOCK (soft_level — понижается в legacy/learn, как структурные).
            has_runtime = bool(evidence.get('layer_2_runtime_at') or evidence.get('layer_3_integration_smoke_at')
                               or evidence.get('layer_4_e2e_at'))
            ev_prose = isinstance(evidence_raw, str) and bool(evidence_raw.strip())
            if not (has_runtime or ev_prose):
                errors_soft.append(
                    "%s: logic-фича в passing без runtime/e2e evidence — typecheck+lint не ловят "
                    "разъехавшееся поведение. Нужен след прогона (layer_2_runtime/e2e timestamp или "
                    "описание реальной проверки), не только layer_1_syntax. (L5-F2)" % feat_id)
        else:
            if not evidence_raw and not has_layer1:
                warnings.append("%s: state=passing, но evidence отсутствует (нужны layer_1..N timestamps)" % feat_id)

        # v8 L5-F2 (c9): negative-gate ОБЯЗАТЕЛЕН на M/L в passing — искусственный баг должен
        # ронять тест (mutation), а expected не должен лежать в одном файле с input (leak). Без
        # него «зелёные тесты лгут». BLOCK (soft_level). S — освобождена (light path).
        if size_p in ('M', 'L'):
            vsc = f.get('verification_self_check')
            vsc = vsc if isinstance(vsc, dict) else {}
            if not (vsc.get('negative_test_at') or vsc.get('leak_check_at')):
                errors_soft.append(
                    "%s: M/L-фича в passing без negative-gate — нет verification_self_check.negative_test_at "
                    "(mutation: искусственный баг → тест падает) или leak_check_at (expected не в одном файле "
                    "с input). Typecheck+lint зелёные ≠ поведение верно. (L5-F2)" % feat_id)

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

def _is_schema_def(af):
    # v7 P7: только ОПРЕДЕЛЕНИЕ схемы (папки/файлы), НЕ любое вхождение слова "schema" в путь —
    # иначе фичи-наполнители реестров цеплялись ложно. Сузили триггер, НО уровень оставили block
    # (правила #1 ревью-модели и #11 vendor-lock действуют независимо от размера фичи).
    if not isinstance(af, str):
        return False
    p = af.lower()
    if 'migrations/' in p or 'prisma/schema' in p or 'drizzle/schema' in p:
        return True
    if p.endswith('.sql'):
        return True
    if re.search(r'(^|/)schema\.(prisma|ts|js|py|sql|rb)$', p):
        return True
    if re.search(r'(^|/)schema/', p):
        return True
    return False

for feat_id, state, f in all_features:
    if state != 'active':
        continue
    size = str(f.get('size_estimate') or '').upper()
    if size in ('M', 'L') and feat_id not in ts_content:
        errors_soft.append(
            "%s: фича размера %s переходит в active без критики — нет docs/test-strategy.md с её id. "
            "Запусти dual critique (test-researcher + user-perspective-critic) → synthesizer, ПОТОМ active. Закрывает H7." % (feat_id, size))
    affected = f.get('affected_files') or []
    if not isinstance(affected, list):
        affected = []
    # Escape: явный маркер «модель предопределена» (внешний стандарт) снимает data-gate —
    # правило reviewer-data-model «не применять для модели по внешнему стандарту».
    data_predefined = bool(f.get('data_model_predefined'))
    is_data = (not data_predefined) and ((f.get('category', '') == 'data') or any(_is_schema_def(af) for af in affected))
    if is_data and feat_id not in dm_content:
        errors_soft.append(
            "%s: data-фича в active без ревью модели — нет docs/data-model-review.md с её id. "
            "Запусти data-model-reviewer ПЕРЕД реализацией схемы (или пометь data_model_predefined: true, если модель по внешнему стандарту)." % feat_id)
    is_integration = (f.get('category', '') == 'integration') or any(
        isinstance(af, str) and re.search(r'(scraper|fetcher|/providers?/|external)', af, re.I) for af in affected)
    if is_integration and feat_id not in research_content:
        errors_soft.append(
            "%s: integration-фича в active без research поставщика — нет docs/research/*.md с её id. "
            "Архитектура держит АБСТРАКЦИЮ (интерфейс), конкретный поставщик выбирается отдельной "
            "research-фазой (5-7 вариантов + матрица сравнения) ПЕРЕД реализацией. Закрывает vendor-lock (~/CLAUDE.md)." % feat_id)

    # --- Стадия детализации (v8 L2-F2/F3, OpenSpec change + spec-kit US). ---
    # M/L-фича (или явный detail_required) не входит в active без детального плана
    # docs/changes/<id>/{proposal|design|spec}.md, содержащего хотя бы одну приоритизированную
    # P1 user story в Given/When/Then (основа verification_command). S — light path (без детали),
    # пока не помечена detail_required. Крупную фичу нельзя протаскивать без разложенного плана (c2).
    detail_required = bool(f.get('detail_required')) or size in ('M', 'L')
    if detail_required:
        change_dir = os.path.join(proj_root, 'docs', 'changes', str(feat_id))
        detail_txt = ''
        for cand in ('proposal.md', 'design.md', 'spec.md'):
            dp = os.path.join(change_dir, cand)
            if os.path.exists(dp):
                try:
                    detail_txt += open(dp).read() + '\n'
                except Exception:
                    pass
        if not detail_txt.strip():
            errors_soft.append(
                "%s: фича размера %s в active без детализации — нет docs/changes/%s/proposal.md. "
                "Стадия детализации (OpenSpec): разложи proposal + tasks + user stories ПЕРЕД работой. "
                "Крупную фичу нельзя протаскивать без плана (c2). S-фича — освобождена (light path); "
                "чтобы форсить деталь на S, ставь detail_required: true. (L2-F2)" % (feat_id, size or '?', feat_id))
        else:
            has_p1 = re.search(r'\bP1\b', detail_txt) is not None
            has_given = re.search(r'(given|дано)', detail_txt, re.I) is not None
            has_then = re.search(r'(then|тогда)', detail_txt, re.I) is not None
            if not (has_p1 and has_given and has_then):
                errors_soft.append(
                    "%s: детализация есть, но без приоритизированной P1 user story в Given/When/Then. "
                    "Нужна ≥1 independently-testable P1-US с Acceptance (Given/When/Then) — это основа "
                    "verification_command и «готово=проверенное поведение». (L2-F3)" % feat_id)

# --- Провенанс-захват (v8 L3-F1). Backstop против ручных Write без provenance. Клапан честности:
# origin=inference / source_ref.kind=unknown — легитимны (не заставляем выдумывать источник —
# иначе лог наполнится необнаружимой ложью, отказ высшего порядка). ---
if prov_mode:
    ORIGIN_ENUM = {"meeting","call","dialog","owner-msg","user-feedback","incident","competitor","regulatory","research","critic","inference"}
    KIND_ENUM = {"transcript","session","file","url","recording","unknown"}
    BY_ENUM = {"owner","agent","critic"}
    NONLIVE = {"meeting","call","incident","competitor","regulatory","user-feedback"}
    for feat_id, state, f in all_features:
        prov = f.get('provenance')
        if not isinstance(prov, dict):
            errors_soft.append("%s: нет provenance-головы (v8 обязательна: origin+source_ref+captured_at+by). Пиши через record-change.sh; честный клапан — origin=inference, source_ref.kind=unknown." % feat_id)
            continue
        origin = prov.get('origin')
        if origin not in ORIGIN_ENUM:
            errors_soft.append("%s: provenance.origin '%s' не из словаря (meeting/call/dialog/owner-msg/user-feedback/incident/competitor/regulatory/research/critic/inference)." % (feat_id, origin))
        sr = prov.get('source_ref')
        if not isinstance(sr, dict) or sr.get('kind') not in KIND_ENUM:
            errors_soft.append("%s: provenance.source_ref должен быть {kind: …} из словаря (transcript/session/file/url/recording/unknown). unknown — честный клапан «не помню откуда»." % feat_id)
        if not str(prov.get('captured_at') or '').strip():
            errors_soft.append("%s: provenance.captured_at пуст (ISO — когда требование занесено)." % feat_id)
        if prov.get('by') not in BY_ENUM:
            errors_soft.append("%s: provenance.by обязателен (owner/agent/critic)." % feat_id)
        if origin in NONLIVE and not str(prov.get('occurred_at') or '').strip():
            warnings.append("%s: origin=%s (не-live) без occurred_at — фиксируй, когда требование ВОЗНИКЛО, не только когда занесено." % (feat_id, origin))

for e in errors_hard:
    emit("BLOCK", e)
for e in errors_soft:
    emit(soft_level, e)
for w in warnings:
    emit("WARN", w)
PYEOF
exit 0
