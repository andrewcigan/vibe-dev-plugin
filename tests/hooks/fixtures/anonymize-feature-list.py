#!/usr/bin/env python3
"""Анонимизатор реальных feature_list.json для корпуса fixtures/real/ (v6.2 F1).

Зачем: баг 2026-06-06 показал, что юнит-тесты на «удобных» синтетических данных
пропускают реальные ФОРМЫ полей (verification строкой/списком, не словарём).
Корпус реальных файлов закрывает это — но контент проектов личный.

Принцип: сохранить СТРУКТУРУ и ТИПЫ (формы полей, статусы, размеры, вложенность),
конструктивно уничтожить контент: любые строки вне enum-whitelist -> синтетика.
После этого в файле физически нет личных данных (имён, путей, доменов).

Использование: python3 anonymize-feature-list.py <вход.json> <выход.json>
"""
import json
import sys

# Значения-enum, которые безопасно сохранять (нужны механизмам: статусы, размеры, категории).
ENUM_WHITELIST = {
    # статусы фич
    "passing", "active", "up_next", "backlog", "blocked", "paused", "failing",
    "superseded", "deferred", "done", "todo", "in_progress", "awaiting_reviewer",
    "awaiting_user_acceptance", "review", "merged",
    # размеры / приоритеты / волны
    "S", "M", "L", "XL", "P0", "P1", "P2", "P3",
    # категории / поверхности
    "ui", "data", "api", "cli", "job", "service", "lib", "content", "infra",
    "integration", "bugfix", "feature", "research", "docs",
    # булевы как строки и прочая мелочь
    "true", "false", "yes", "no", "none", "null", "n/a", "-", "",
}

_id_map = {}


def _anon_id(value: str) -> str:
    """Детерминированная замена id с сохранением уникальности и кросс-ссылок."""
    if value not in _id_map:
        _id_map[value] = f"feat-{len(_id_map) + 1:03d}"
    return _id_map[value]


def _anon_string(key: str, value: str) -> str:
    if value in ENUM_WHITELIST:
        return value
    if key in ("id", "feature_id", "feature", "active_feature", "depends_on"):
        return _anon_id(value)
    # Форма сохраняется грубо: короткая строка / длинный текст / путь-подобное.
    if "/" in value and " " not in value.strip():
        return "src/anon/path.txt"
    if len(value) > 120:
        return "обезличенный длинный текст: " + "x" * 80
    return "обезличенный текст"


def anonymize(node, key=""):
    if isinstance(node, dict):
        return {k: anonymize(v, k) for k, v in node.items()}
    if isinstance(node, list):
        return [anonymize(v, key) for v in node]
    if isinstance(node, str):
        return _anon_string(key, node)
    return node  # числа, bool, null — не личное


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(anonymize(data), f, ensure_ascii=False, indent=2)
    print(f"ok: {sys.argv[2]} (id переименовано: {len(_id_map)})")


if __name__ == "__main__":
    main()
