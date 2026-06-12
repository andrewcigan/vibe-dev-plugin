#!/bin/bash
# Vibe Dev v6.2.1 — interrupt-recovery (вызывается hooks/dispatch-user-prompt.sh на UserPromptSubmit).
#
# Боль (диагностика 2026-06-12, 51 interrupt-событие в боевых журналах): обрыв клиентского
# канала (закрытая крышка ноутбука при Desktop/удалённой сессии) и доставка входящего
# сообщения (вопрос «готово?», Telegram-канал, task-notification) помечают выполняющийся
# инструмент «The user doesn't want to proceed…» / «…doesn't want to take this action…»
# (+ «[Request interrupted by user]»). Агент читает «STOP and wait» и стоит ЧАСАМИ
# (зафиксировано 7ч17м простоя), хотя пользователь ничего не запрещал. Github issue
# anthropics/claude-code#49790 (сессия не переживает разрыв клиента) — открыт.
#
# Логика: новый промпт пользователя -> если хвост ПОСЛЕДНЕГО хода в transcript содержит
# interrupt/reject-маркер, после ПОСЛЕДНЕГО маркера не было ни одного tool_use (работа не
# возобновлялась), и в новом промпте НЕТ стоп-слов (сознательная остановка) -> inject:
# «прерывание было техническим, не запретом — продолжай план». warn/inject, НЕ block:
# настоящий «стоп» пользователя всегда главнее (стоп-словарь выключает напоминание).
#
# Честная граница: если прерыватель — доставленное сообщение-строка (Telegram/notification),
# оно само становится границей хода, и на СЛЕДУЮЩЕМ промпте маркер уже вне хвоста — ловим
# в момент самого сообщения-прерывателя (запись reject обычно успевает в transcript на
# десятки мс раньше). Гонку записи не гарантируем — это напоминание, не гейт.
#
# Реальные формы записей (2.1.170): промпт = content-СТРОКА; reject = tool_result-блок
# («doesn't want to proceed/take this action») + toolUseResult="User rejected tool use";
# interrupt-маркер = text-блок "[Request interrupted by user…]".
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает текст inject или пусто. exit 0.

set -u
CWD="${1:-$PWD}"

PROMPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.prompt // .user_prompt // .message // .content // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

# Стоп-слова = сознательная остановка/смена курса: пользователь главнее — молчим.
STOPWORDS='[Сс]топ([!.,:; ]|$)|[Оо]станов|[Нн]е продолжа|[Нн]е надо|[Нн]е дела[йт]|[Оо]тмен[иа]|[Пп]одожд[иё]|[Пп]огоди|[Хх]ватит|[Дд]руг(ая|ую) задач|[Нн]е то (делаем|делаешь)|[Нн]е туда'
printf '%s' "$PROMPT" | grep -qE "$STOPWORDS" && exit 0

TRANSCRIPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Хвост последнего хода: всё после последнего НАСТОЯЩЕГО промпта (type=user, без
# toolUseResult, content-СТРОКА — interrupt-маркеры и tool_result'ы идут массивом блоков).
# В хвосте: irq = есть interrupt/reject-маркер; resumed = был tool_use ПОСЛЕ последнего маркера.
VERDICT="$(jq -s '
  . as $all
  | ([ range(0; ($all|length)) as $i
       | select($all[$i].type=="user"
                and ($all[$i].toolUseResult == null)
                and (($all[$i].message.content // null) | type == "string"))
       | $i ] | last) as $b
  | ($all[ (($b // -1) + 1) : ]) as $turn
  | ([ range(0; ($turn|length)) as $j
       | select(
           ($turn[$j].toolUseResult == "User rejected tool use")
           or ( ($turn[$j].message.content // null) | type=="array" and
                ( any(.[]?; .type=="tool_result"
                      and ((.content | tostring) | test("doesn.t want to (proceed|take this action)")))
                  or any(.[]?; .type=="text"
                      and ((.text // "") | startswith("[Request interrupted by user"))) ) )
         )
       | $j ] | last) as $m
  | if $m == null then "clean"
    elif ([ $turn[ ($m + 1) : ][] | select(.type=="assistant"
             and ((.message.content // []) | any(.[]?; .type=="tool_use"))) ] | length) > 0
    then "resumed"
    else "interrupted"
    end
' "$TRANSCRIPT" 2>/dev/null | tr -d '"')"

[ "$VERDICT" = "interrupted" ] || exit 0

cat <<'TXT'
⚠️ Перед этим сообщением ход был оборван ТЕХНИЧЕСКИМ прерыванием (обрыв связи с клиентом — например, закрытая крышка ноутбука — или доставка входящего сообщения убила выполнявшийся инструмент). Пометка «The user doesn't want to proceed…» в последнем ходе — артефакт обрыва, НЕ запрет пользователя: он ничего не отклонял. Если текущее сообщение не задаёт другую задачу — немедленно продолжай прерванный план: перезапусти убитый вызов и доведи работу до конца, не спрашивая «продолжать ли». [interrupt-recovery]
TXT
exit 0
