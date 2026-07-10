#!/bin/bash
# Vibe Dev — /upgrade-project механика (v8.0.1: +мягкий режим, +провенанс-миграция, +честный dry-run).
#
# Переводит живой проект на актуальный движок. Два режима:
#   (дефолт) СТРОГИЙ  — engine=<major>.0 + pending-strict + снять learn + git pre-commit + миграция
#                        провенанса. Полная строгость: v8-гейты BLOCK.
#   --soft   МЯГКИЙ    — engine=<major>.0 + hook-mode=learn (profile СОХРАНЁН!) + миграция провенанса.
#                        v8-гейты = WARN (подсказки, не блок). Не ставит git-гейты (минимально
#                        инвазивно). Для перевода legacy-проектов без остановки работы.
#   --dry-run ОТЧЁТ    — ничего не пишет; прогоняет реальный сторож на текущем feature_list в обоих
#                        режимах и печатает человекочитаемо, что заблокируется / станет подсказкой.
#
# C1: «мягкий» = hook-mode=learn при СОХРАНЁННОМ profile=strict (profile=learn отключил бы
#     state-transition целиком, сняв и hard UI-block). H4: уже-strict-v8 проект --soft НЕ разжалует.
#     H5: перед записью — бэкап git-tag + предупреждение о грязном дереве.
#
# Использование: bash upgrade-project.sh [--soft|--strict|--dry-run] [<путь-проекта>]
set -u
_SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$_SD/.." && pwd)"
_MAJ="$(jq -r '.version // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | cut -d. -f1)"
case "$_MAJ" in ''|*[!0-9]*) _MAJ=8 ;; esac
ENGINE="${_MAJ}.0"

MODE="strict"; PROJ=""
for a in "$@"; do
  case "$a" in
    --soft) MODE="soft" ;;
    --strict) MODE="strict" ;;
    --dry-run|--dry) MODE="dry-run" ;;
    *) PROJ="$a" ;;
  esac
done
PROJ="${PROJ:-$PWD}"

if [ ! -d "$PROJ/.harness" ] && [ ! -f "$PROJ/feature_list.json" ]; then
  echo "❌ Не похоже на vibe-проект (нет .harness/ и feature_list.json): $PROJ"; exit 1
fi
FL="$PROJ/feature_list.json"

# --- Симуляция реального сторожа на текущем feature_list (для dry-run и предполёта) ---
# Печатает: "<deny_soft> <deny_strict> <ui_hard> <prov> <logic> <neg> <detail>"
simulate() {
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/.harness"
  cp "$FL" "$sb/feature_list.json" 2>/dev/null || { echo "0 0 0 0 0 0 0"; rm -rf "$sb"; return; }
  # MEDIUM-2 (честный предпросмотр): и --soft, и --strict сами проставят провенанс-головы →
  # мигрируем в песочнице ПЕРЕД прогоном, иначе strict-счётчик завышается фантомными «нет головы»
  # (реальны только logic/negative/UI/detail-блокировки).
  bash "$PLUGIN_ROOT/scripts/migrate-provenance.sh" "$sb" >/dev/null 2>&1
  echo "$ENGINE" > "$sb/.harness/engine-version"; echo strict > "$sb/.harness/profile"
  local content payload out_strict out_soft
  content="$(cat "$sb/feature_list.json")"
  payload="$(jq -cn --arg cwd "$sb" --arg fp "$sb/feature_list.json" --arg c "$content" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')"
  out_strict="$(printf '%s' "$payload" | bash "$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh" 2>/dev/null)"
  echo learn > "$sb/.harness/hook-mode"
  out_soft="$(printf '%s' "$payload" | bash "$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh" 2>/dev/null)"
  local ds dso uh pr lo ng dt
  ds=$(printf '%s' "$out_strict"  | grep -c '"permissionDecision":"deny"')
  dso=$(printf '%s' "$out_soft"   | grep -c '"permissionDecision":"deny"')
  uh=$(printf '%s' "$out_strict" | grep -o 'layer_4/5' | wc -l | tr -d ' ')
  pr=$(printf '%s' "$out_strict" | grep -o 'нет provenance-головы' | wc -l | tr -d ' ')
  lo=$(printf '%s' "$out_strict" | grep -o 'logic-фича в passing' | wc -l | tr -d ' ')
  ng=$(printf '%s' "$out_strict" | grep -o 'без negative-gate' | wc -l | tr -d ' ')
  dt=$(printf '%s' "$out_strict" | grep -o 'без детализации' | wc -l | tr -d ' ')
  echo "$dso $ds $uh $pr $lo $ng $dt"
  rm -rf "$sb"
}

PREV_ENGINE="нет (legacy)"; [ -f "$PROJ/.harness/engine-version" ] && PREV_ENGINE="$(tr -d '[:space:]' < "$PROJ/.harness/engine-version")"
PREV_MODE="нет"; [ -f "$PROJ/.harness/hook-mode" ] && PREV_MODE="$(tr -d '[:space:]' < "$PROJ/.harness/hook-mode" 2>/dev/null)"
PREV_PROFILE="нет"; [ -f "$PROJ/.harness/profile" ] && PREV_PROFILE="$(tr -d '[:space:]' < "$PROJ/.harness/profile" 2>/dev/null)"
PREV_MAJ="${PREV_ENGINE%%.*}"; case "$PREV_MAJ" in ''|*[!0-9]*) PREV_MAJ=0 ;; esac

# --- DRY-RUN: только отчёт ---
if [ "$MODE" = "dry-run" ]; then
  read -r DSO DS UH PR LO NG DT <<EOF
$(simulate)
EOF
  echo "📋 Предпросмотр перевода на v$ENGINE — $(basename "$PROJ")"
  echo "   Сейчас: движок=$PREV_ENGINE, режим=$PREV_MODE"
  echo ""
  echo "   При СТРОГОМ режиме первая запись feature_list.json:"
  if [ "${DS:-0}" -gt 0 ]; then
    echo "     ⛔ ЗАБЛОКИРУЕТСЯ. Причины: UI-без-скриншота=$UH, logic-без-прогона=$LO, без-negative-теста=$NG, без-детализации=$DT"
    echo "        (провенанс-этикетки проставятся автоматически при переводе — в блок не входят)"
  else
    echo "     ✅ пройдёт чисто (провенанс мигрируется автоматически)"
  fi
  echo "   При МЯГКОМ режиме (подсказки вместо блокировок):"
  if [ "${DSO:-0}" -gt 0 ]; then
    echo "     ⚠️  ОСТАНЕТСЯ БЛОК: UI-задачи в «готово» без скриншота ($UH) — жёсткий контроль, мягкий режим их НЕ понижает. Нужно решить отдельно (скриншот/прогон)."
  else
    echo "     ✅ пройдёт (провенанс/logic/negative станут подсказками; миграция наклеит этикетки)"
  fi
  echo ""
  echo "   Рекомендация: $([ "${DSO:-0}" -gt 0 ] && echo "СНАЧАЛА решить UI-долг ($UH шт), затем мягкий режим" || echo "мягкий режим безопасен — bash upgrade-project.sh --soft \"$PROJ\"")"
  exit 0
fi

# --- H4 + MEDIUM-1: уже-строгий проект (major≥6 + profile=strict + без learn) НЕ понижаем молча ---
if [ "$MODE" = "soft" ] && [ "$PREV_MAJ" -ge 6 ] 2>/dev/null && [ "$PREV_PROFILE" = "strict" ] && [ "$PREV_MODE" = "нет" ]; then
  if [ "$PREV_MAJ" -ge "$_MAJ" ] 2>/dev/null; then
    echo "ℹ️  $(basename "$PROJ") уже на строгом v$PREV_ENGINE (движок≥$_MAJ, без learn). Ничего не менял (H4)."
    exit 0
  fi
  # v6/v7-strict: честный предпросмотр — пройдёт ли v$ENGINE-strict чисто (провенанс мигрируется)?
  read -r _DSO _DS _rest <<EOF
$(simulate)
EOF
  if [ "${_DS:-1}" -eq 0 ] 2>/dev/null; then
    echo "ℹ️  $(basename "$PROJ") уже строгий (v$PREV_ENGINE) и проходит v$ENGINE-strict чисто → веду в СТРОГИЙ v$ENGINE (не понижаю в подсказки — прежние замки сохранены)."
    MODE="strict"
  else
    echo "⚠️  $(basename "$PROJ") уже строгий (v$PREV_ENGINE), но имеет v8-долг (${_DS} блокировок). Мягкий режим ВРЕМЕННО понизит и ПРЕЖНИЕ строгие проверки до подсказок."
    echo "    Верни полную строгость: bash upgrade-project.sh --strict \"$PROJ\" — когда приведёшь долг в порядок."
  fi
fi

# --- H5: бэкап + предупреждение о грязном дереве перед записью ---
if [ -d "$PROJ/.git" ]; then
  if [ -n "$(git -C "$PROJ" status --porcelain 2>/dev/null)" ]; then
    echo "⚠️  Рабочее дерево $(basename "$PROJ") не чистое — миграция провенанса смешается с текущими правками."
    echo "    Закоммить/спрячь изменения и повтори. (Прерываю, чтобы не запутать историю.)"
    exit 2
  fi
  BACKUP_TAG="pre-v${_MAJ}-$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null)"
  git -C "$PROJ" tag -f "$BACKUP_TAG" >/dev/null 2>&1 && echo "🔖 Бэкап-точка: тег $BACKUP_TAG (откат: git reset --hard $BACKUP_TAG)"
fi

mkdir -p "$PROJ/.harness"

# --- Миграция провенанса (наклеить этикетки истории существующим фичам) ---
echo "→ миграция провенанса…"
bash "$PLUGIN_ROOT/scripts/migrate-provenance.sh" "$PROJ" 2>&1 | sed 's/^/   /'

# --- Установка движка + режима ---
echo "$ENGINE" > "$PROJ/.harness/engine-version"

if [ "$MODE" = "soft" ]; then
  # C1: profile СОХРАНЯЕМ (strict), понижаем через hook-mode=learn → v8-гейты = warn.
  [ -f "$PROJ/.harness/profile" ] || echo "strict" > "$PROJ/.harness/profile"
  echo "learn" > "$PROJ/.harness/hook-mode"
  echo "✅ $(basename "$PROJ") → v$ENGINE, МЯГКИЙ режим (было: $PREV_ENGINE/$PREV_MODE)."
  echo "   v8-проверки работают как ПОДСКАЗКИ (warn), не блокируют. Жёсткими остаются только"
  echo "   UI-скриншоты и массовый внешний API. git-гейты провенанса НЕ ставились (минимально)."
  echo "   Готов к строгости? bash upgrade-project.sh --strict \"$PROJ\""
else
  echo "pending-strict" > "$PROJ/.harness/profile"
  rm -f "$PROJ/.harness/hook-mode"
  bash "$_SD/install-precommit.sh" "$PROJ"
  echo "✅ $(basename "$PROJ") → v$ENGINE, СТРОГИЙ режим (было: $PREV_ENGINE/$PREV_MODE)."
  echo "   Профиль pending-strict → боевым strict станет при первом живом хуке в сессии."
  echo "   Активны как BLOCK: UI без скриншота, невалидные переходы/JSON, logic без прогона,"
  echo "   M/L без negative-gate, массовый API без checklist, правка требования без истории."
fi
