#!/bin/bash
# Vibe Dev v8.0.1 — оркестратор перевода всех живых проектов на v8 (мягкое включение).
#
# Скан vibe-проектов в базовой папке → для каждого предпросмотр (реальный сторож) → сводка по
# бакетам. С --apply: безопасные (чистое дерево) переводятся в МЯГКИЙ режим; проекты с жёстким
# UI-долгом, грязным деревом или без фич — НЕ трогаются, попадают в свои бакеты. Идемпотентно.
#
# Критик H3: whitelist — исключаем плагин, бэкапы, _archive, templates, tests, worktree-контейнер.
# H2: linked git-worktree (.git — файл) пропускаем. HIGH-2: грязное дерево → бакет DIRTY (не SAFE,
# иначе --apply молча прерывается на exit 2); пустой-реальный проект → бакет EMPTY (не теряем);
# при --apply проверяем код возврата upgrade и печатаем реальный итог. Кириллица/пробелы — в кавычках.
#
# Использование: bash patch-projects.sh [--apply] [<база, по умолчанию ~/Coding>]
set -u
_SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$_SD/.." && pwd)"
UPG="$_SD/upgrade-project.sh"
BASE="$HOME/Coding"; APPLY=0
for a in "$@"; do case "$a" in --apply) APPLY=1 ;; *) BASE="$a" ;; esac; done

is_excluded() {
  local p="$1"
  case "$p" in
    "$PLUGIN_ROOT"|"$PLUGIN_ROOT"/*) return 0 ;;
    *-backup|*-backups|*-backup/*|*-backups/*|*backup*) return 0 ;;
    *_archive*|*/archive/*|*/templates/*|*/tests/*|*/node_modules/*|*/worktrees/*|*/.config/*) return 0 ;;
  esac
  return 1
}
# Печатает: ok (есть фичи) | empty (валидный JSON, 0 фич) | bad (нет файла/битый JSON)
project_status() {
  local p="$1"
  [ -f "$p/feature_list.json" ] || { echo bad; return; }
  python3 - "$p/feature_list.json" <<'PY' 2>/dev/null || { echo bad; return; }
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(3)
feats=d.get("features") or {}
n=sum(len(v) for v in feats.values() if isinstance(v,list))
print("ok" if n>0 else "empty")
PY
}

echo "🔍 Скан vibe-проектов в: $BASE"
echo ""
SAFE=(); DEBT=(); DIRTY=(); EMPTY=(); SKIP=()
while IFS= read -r fl; do
  proj="$(dirname "$fl")"
  is_excluded "$proj" && continue
  st="$(project_status "$proj")"
  [ "$st" = "bad" ] && continue
  if [ -f "$proj/.git" ]; then SKIP+=("$(basename "$proj") (linked worktree — патчь main)"); continue; fi
  if [ "$st" = "empty" ]; then EMPTY+=("$(basename "$proj")"); continue; fi
  # HIGH-2: грязное дерево → отдельный бакет (upgrade прервётся на exit 2, это не SAFE)
  if [ -d "$proj/.git" ] && [ -n "$(git -C "$proj" status --porcelain 2>/dev/null)" ]; then
    DIRTY+=("$proj")
    echo "📋 $(basename "$proj") — рабочее дерево не чистое: сначала закоммить/спрятать правки, потом перевод."
    echo "   ------------------------------------------------------------"
    continue
  fi
  DRY="$(bash "$UPG" --dry-run "$proj" 2>/dev/null)"
  echo "$DRY"
  echo "   ------------------------------------------------------------"
  if printf '%s' "$DRY" | grep -q "ОСТАНЕТСЯ БЛОК"; then DEBT+=("$proj"); else SAFE+=("$proj"); fi
done < <(find "$BASE" -maxdepth 2 -name feature_list.json 2>/dev/null | sort)

echo ""
echo "════════════════════════════════════════════════════════════"
echo " СВОДКА: готовы к мягкому включению — ${#SAFE[@]}; UI-долг — ${#DEBT[@]}; грязное дерево — ${#DIRTY[@]}; без фич — ${#EMPTY[@]}; пропущено — ${#SKIP[@]}"
echo "════════════════════════════════════════════════════════════"
[ ${#SAFE[@]}  -gt 0 ] && { echo " ✅ Мягкий режим включится чисто:"; for p in "${SAFE[@]}";  do echo "    • $(basename "$p")"; done; }
[ ${#DEBT[@]}  -gt 0 ] && { echo " ⚠️  UI-долг (решить скриншоты ПЕРЕД переводом):"; for p in "${DEBT[@]}";  do echo "    • $(basename "$p")"; done; }
[ ${#DIRTY[@]} -gt 0 ] && { echo " ✋ Грязное дерево (закоммить и повтори):"; for p in "${DIRTY[@]}"; do echo "    • $(basename "$p")"; done; }
[ ${#EMPTY[@]} -gt 0 ] && { echo " ○ Без фич (перевод бессмыслен, пропускаем):"; for p in "${EMPTY[@]}"; do echo "    • $p"; done; }
[ ${#SKIP[@]}  -gt 0 ] && { echo " ↷ Пропущено:"; for p in "${SKIP[@]}"; do echo "    • $p"; done; }
echo ""

if [ "$APPLY" = "0" ]; then
  echo "Это предпросмотр (ничего не изменено). Применить мягкое включение к готовым (${#SAFE[@]}):"
  echo "   bash patch-projects.sh --apply \"$BASE\""
  [ ${#DIRTY[@]} -gt 0 ] && echo "Грязные проекты (${#DIRTY[@]}) сначала закоммить — иначе перевод их пропустит."
  exit 0
fi

if [ ${#SAFE[@]} -eq 0 ]; then
  echo "Нечего применять: безопасных проектов с чистым деревом нет. Разберись с грязными/UI-долгом выше."
  exit 0
fi

echo "▶ ПРИМЕНЯЮ мягкое включение к ${#SAFE[@]} готовым проектам…"
echo ""
MIG=0; ERR=0
for p in "${SAFE[@]}"; do
  echo "── $(basename "$p") ──"
  bash "$UPG" --soft "$p" 2>&1 | sed 's/^/  /'
  rc=${PIPESTATUS[0]}
  if [ "$rc" = 0 ]; then MIG=$((MIG+1)); else ERR=$((ERR+1)); echo "  ⚠️ прервано (код $rc) — не переведён"; fi
  echo ""
done
echo "════════════════════════════════════════════════════════════"
echo " ИТОГ: переведено в мягкий режим — $MIG; прервано — $ERR; UI-долг не тронут — ${#DEBT[@]}; грязных пропущено — ${#DIRTY[@]}"
echo "════════════════════════════════════════════════════════════"
