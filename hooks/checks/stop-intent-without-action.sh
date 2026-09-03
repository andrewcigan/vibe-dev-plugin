#!/bin/bash
# Vibe Dev v6 — Stop-intent gate (вызывается hooks/dispatch-stop.sh на событии Stop). H19.
#
# Ловит «end-of-turn collapse»: агент завершил ход заявленным намерением действия
# («сейчас запущу / стартую / приступаю»), но НЕ выполнил ни одного tool_use в этом ходе.
# Закрывает паттерн «намерение голосом без действия» (агент объявляет шаг, но не выполняет tool_use).
#
# Читает транскрипт (HOOK_PAYLOAD.transcript_path) в verified-формате:
#   - граница текущего хода = последняя запись настоящего промпта пользователя
#     (type=user, нет toolUseResult). ВАЖНО: реальный Claude Code пишет content промпта
#     СТРОКОЙ (не массивом text-блоков) — поэтому не требуем any(.type=="text");
#   - было действие = в ходе есть assistant с tool_use ИЛИ user с toolUseResult;
#   - текст намерения = конкатенация text-блоков assistant в этом ходе.
#
# Печатает на stdout "BLOCK<TAB>msg". Пусто = OK. Всегда guard_done.
# Fail-safe: нет транскрипта/не парсится → пусто (не блокируем вслепую).

set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"
guard_require_tools jq

CWD="${1:-$PWD}"
TAB="$(printf '\t')"

TRANSCRIPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -z "$TRANSCRIPT" ] && guard_done
[ ! -f "$TRANSCRIPT" ] && guard_done

# Текущий ход: had (было ли действие) + text (текст намерения ассистента).
META="$(jq -s '
  . as $all
  | ( [ range(0; ($all|length)) as $i
        | select($all[$i].type=="user"
                 and ($all[$i].toolUseResult == null)) | $i ] | last ) as $b
  | ( $all[ (($b // -1) + 1) : ] ) as $turn
  | { had: ($turn | any(
            (.type=="assistant" and ((.message.content // []) | any(.type=="tool_use")))
            or (.type=="user" and (.toolUseResult != null)) )),
      text: ( [ $turn[] | select(.type=="assistant")
                | (.message.content // [])[] | select(.type=="text") | .text ] | join("\n") ) }
' "$TRANSCRIPT" 2>/dev/null)"
[ -z "$META" ] && guard_done

HAD="$(printf '%s' "$META" | jq -r '.had' 2>/dev/null)"
[ "$HAD" = "true" ] && guard_done   # действие было — не collapse

TEXT="$(printf '%s' "$META" | jq -r '.text' 2>/dev/null)"
[ -z "$TEXT" ] && guard_done

# Словарь маркеров-намерения (обещание НЕМЕДЛЕННОГО действия 1-м лицом).
# Явные классы регистра вместо -i (надёжнее для кириллицы на macOS grep).
INTENT='[Зз]апущу|[Зз]апускаю|[Сс]тартую|[Пп]риступаю|[Бб]еру feat|[Сс]ейчас (сделаю|проверю|запущу|создам|напишу|исправлю|поправлю|реализую)|[Пп]ерехожу к реализации|[Нн]ачинаю реализаци|[Сс]делаю это сейчас'

if printf '%s' "$TEXT" | grep -qE "$INTENT"; then
  printf 'BLOCK%sТы завершаешь ход заявленным намерением действия, но в этом ходе не было ни одного tool_use. Выполни обещанное действие сейчас, либо (если это был ответ/вопрос/варианты) переформулируй без обещания. [H19]\n' "$TAB"
fi
guard_done
