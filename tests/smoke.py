#!/usr/bin/env python3
"""smoke.py — проверка kit-а на одноразовых каталогах.

    python3 tests/smoke.py

Ничего вне временного корня не трогает: каталоги создаются в системном temp
и удаляются в `finally`.
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

KIT_ROOT = pathlib.Path(__file__).resolve().parent.parent
INSTALL = KIT_ROOT / "install.py"

PASS = 0
FAIL = 0


def ok(description: str) -> None:
    global PASS
    PASS += 1
    print(f"  PASS  {description}")


def bad(description: str) -> None:
    global FAIL
    FAIL += 1
    print(f"  FAIL  {description}", file=sys.stderr)


def check(description: str, condition: bool) -> None:
    if condition:
        ok(description)
    else:
        bad(description)


def new_project(work: pathlib.Path, name: str) -> pathlib.Path:
    """Пустой git-проект."""
    directory = work / name
    directory.mkdir(parents=True)
    subprocess.run(
        ["git", "-C", str(directory), "init", "-q"],
        check=True,
        capture_output=True,
    )
    return directory


def kit(work: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(INSTALL), *args],
        capture_output=True,
        text=True,
        cwd=work,
    )


def kit_ext(work: pathlib.Path, name: str) -> pathlib.Path:
    """Копия kit-а с дополнительными группами и новыми типами компонентов.

    `commands/` и `agents/` проверяют расширяемость без правки скрипта.
    """
    directory = work / name
    directory.mkdir(parents=True)
    for item in ("install.py", "bootstrap.sh", "kit", "components", "snippets", "VERSION"):
        source = KIT_ROOT / item
        target = directory / item
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)

    for group, text in (("js", "# JS\n"), ("go", "# Go\n")):
        rules = directory / "components" / group / "rules"
        rules.mkdir(parents=True)
        (rules / f"{group}_rules.md").write_text(text, encoding="utf-8")

    commands = directory / "components" / "base" / "commands"
    commands.mkdir(parents=True, exist_ok=True)
    (commands / "review.md").write_text(
        "---\ndescription: review\n---\nСделай ревью.\n", encoding="utf-8"
    )
    agents = directory / "components" / "base" / "agents"
    agents.mkdir(parents=True, exist_ok=True)
    (agents / "reviewer.md").write_text(
        "---\ndescription: reviewer\n---\nТы ревьюер.\n", encoding="utf-8"
    )
    return directory


def read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run_in(project: pathlib.Path, script: pathlib.Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    command = ["sh", str(script), *args]
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        cwd=project,
        env=env,
    )


def main() -> int:
    work = pathlib.Path(tempfile.mkdtemp(prefix="agent-kit-smoke-"))
    try:
        run_checks(work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"\n== Итог: PASS={PASS} FAIL={FAIL}")
    return 0 if FAIL == 0 else 1


def run_checks(work: pathlib.Path) -> None:  # noqa: C901 — линейный список проверок
    # --- 1. базовая установка ------------------------------------------------
    print("\n== 1. install")
    project = new_project(work, "basic")
    result = kit(work, "--dir", str(project))
    (work / "install.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("установка завершилась успешно", result.returncode == 0)
    check("правило создано с префиксом", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())
    check(
        "скилл создан с префиксом",
        (project / ".agents/skills/alxmrz_kit_spec-authoring/SKILL.md").is_file(),
    )
    check(
        "вспомогательный файл скилла скопирован",
        (project / ".agents/skills/alxmrz_kit_spec-authoring/references/traceability.md").is_file(),
    )
    check("php_rules не попал в base", not (project / ".agents/rules/alxmrz_kit_php_rules.md").exists())
    check("манифеста нет", not (project / ".agents/.alxmrz_kit_manifest.json").exists())
    check("opencode.json создан", (project / "opencode.json").is_file())
    config_ok = False
    try:
        config_ok = isinstance(read_json(project / "opencode.json"), dict)
    except (OSError, json.JSONDecodeError):
        config_ok = False
    check("opencode.json валиден", config_ok)
    instructions = read_json(project / "opencode.json").get("instructions", []) if config_ok else []
    check(
        "instructions[] содержит правило base",
        "./.agents/rules/alxmrz_kit_general_rules.md" in instructions,
    )
    check("instructions[] не содержит неподключённую группу", "php_rules" not in (project / "opencode.json").read_text(encoding="utf-8"))
    agents_text = (project / "AGENTS.md").read_text(encoding="utf-8") if (project / "AGENTS.md").is_file() else ""
    check("AGENTS.md создан", bool(agents_text))
    check("в AGENTS.md нет плейсхолдеров", "{{" not in agents_text)
    check("AGENTS.md ссылается на правило kit-а", "alxmrz_kit_general_rules.md" in agents_text)
    check("AGENTS.md говорит, что правила в opencode.json", "instructions[]" in agents_text)
    check(".gitignore не создан", not (project / ".gitignore").exists())
    check(
        "base не ссылается на php_rules",
        "php_rules" not in (project / ".agents/rules/alxmrz_kit_general_rules.md").read_text(encoding="utf-8"),
    )
    commit_skill = (project / ".agents/skills/alxmrz_kit_conventional-commit/SKILL.md").read_text(encoding="utf-8")
    check("skills не содержат metadata kit-а", "alxmrz-kit:" not in commit_skill)
    check("name: скилла не подменён ID", "name: conventional-commit" in commit_skill.splitlines())

    # --- 2. безусловная перезапись ------------------------------------------
    print("\n== 2. перезапись")
    project = new_project(work, "overwrite")
    kit(work, "--dir", str(project))
    rule = project / ".agents/rules/alxmrz_kit_general_rules.md"
    with rule.open("a", encoding="utf-8") as handle:
        handle.write("\n# моя правка\n")
    kit(work, "--dir", str(project))
    check("правка в файле kit-а исчезает", "# моя правка" not in rule.read_text(encoding="utf-8"))
    check(
        "содержимое совпало с источником",
        rule.read_bytes() == (KIT_ROOT / "components/base/rules/general_rules.md").read_bytes(),
    )

    # --- 3. идемпотентность --------------------------------------------------
    print("\n== 3. повторный запуск")
    project = new_project(work, "idempotent")
    kit(work, "--dir", str(project))
    snapshot = work / "idempotent-snap"
    shutil.copytree(project, snapshot, symlinks=True)
    kit(work, "--dir", str(project))
    check("второй запуск не меняет файлы", not diff_trees(project, snapshot))
    check("повторный запуск не создал .gitignore", not (project / ".gitignore").exists())

    # --- 4. чужие файлы ------------------------------------------------------
    print("\n== 4. чужие файлы")
    project = new_project(work, "foreign")
    (project / ".agents/skills/spec-authoring").mkdir(parents=True)
    (project / ".agents/rules").mkdir(parents=True)
    (project / ".agents/skills/spec-authoring/SKILL.md").write_text(
        "---\nname: my-own-spec\n---\nМОЁ\n", encoding="utf-8"
    )
    (project / ".agents/rules/general_rules.md").write_text("# мои правила\n", encoding="utf-8")
    kit(work, "--dir", str(project))
    check("свой скилл с похожим именем цел", (project / ".agents/skills/spec-authoring/SKILL.md").read_text(encoding="utf-8").strip() == "---\nname: my-own-spec\n---\nМОЁ".strip())
    check("своё правило цело", (project / ".agents/rules/general_rules.md").read_text(encoding="utf-8") == "# мои правила\n")
    check("рядом появился префиксованный скилл", (project / ".agents/skills/alxmrz_kit_spec-authoring/SKILL.md").is_file())
    check("рядом появилось префиксованное правило", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())

    # --- 5. --with -----------------------------------------------------------
    print("\n== 5. --with")
    project = new_project(work, "with-php")
    kit(work, "--dir", str(project), "--with", "php")
    check("--with php ставит php_rules", (project / ".agents/rules/alxmrz_kit_php_rules.md").is_file())
    check("--with php ставит и base", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())
    check(
        "php_rules ссылается на general_rules",
        "alxmrz_kit_general_rules" in (project / ".agents/rules/alxmrz_kit_php_rules.md").read_text(encoding="utf-8"),
    )

    project = new_project(work, "with-spaces")
    kit(work, "--dir", str(project), "--with", " php , ")
    check("пробелы и запятые в --with разбираются", (project / ".agents/rules/alxmrz_kit_php_rules.md").is_file())

    ext = kit_ext(work, "ext-groups")
    project = new_project(work, "with-many")
    subprocess.run(
        [sys.executable, str(ext / "install.py"), "--dir", str(project), "--with", "php,js", "--with", "go"],
        capture_output=True,
        text=True,
    )
    check("повтор --with объединяет группы (php)", (project / ".agents/rules/alxmrz_kit_php_rules.md").is_file())
    check("повтор --with объединяет группы (js)", (project / ".agents/rules/alxmrz_kit_js_rules.md").is_file())
    check("повтор --with объединяет группы (go)", (project / ".agents/rules/alxmrz_kit_go_rules.md").is_file())

    project = new_project(work, "with-unknown")
    result = kit(work, "--dir", str(project), "--with", "nope")
    (work / "unknown.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("неизвестная группа отклонена", result.returncode != 0)
    check("ошибка называет доступные группы", "есть: base php" in (work / "unknown.log").read_text(encoding="utf-8"))
    check(
        "при неизвестной группе ничего не записано",
        not (project / ".agents").exists()
        and not (project / "AGENTS.md").exists()
        and not (project / ".opencode").exists(),
    )

    # --- 6. opencode.json: правила в instructions[] --------------------------
    print("\n== 6. opencode.json")
    project = new_project(work, "own-config")
    (project / "opencode.json").write_text(
        '{\n    "model": "example/model",\n    "instructions": [\n        "./docs/my_rules.md"\n    ]\n}\n',
        encoding="utf-8",
    )
    shutil.copy2(project / "opencode.json", work / "own-config-before")
    result = kit(work, "--dir", str(project), "--with", "php")
    (work / "own-opencode.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    data = read_json(project / "opencode.json")
    check(
        "instructions[] дополнены правилом base",
        "./.agents/rules/alxmrz_kit_general_rules.md" in data.get("instructions", []),
    )
    check(
        "instructions[] дополнены правилом выбранной группы",
        "./.agents/rules/alxmrz_kit_php_rules.md" in data.get("instructions", []),
    )
    check(
        "чужие настройки и запись instructions сохранены",
        data.get("model") == "example/model" and data["instructions"][0] == "./docs/my_rules.md",
    )
    check("чужой отступ 4 пробела сохранён", '    "model": "example/model",' in (project / "opencode.json").read_text(encoding="utf-8"))
    check("лог сообщает о добавленных путях", "added: ./.agents/rules/alxmrz_kit_general_rules.md" in (work / "own-opencode.log").read_text(encoding="utf-8"))

    shutil.copy2(project / "opencode.json", work / "own-config-once")
    kit(work, "--dir", str(project), "--with", "php")
    check("повторный запуск не меняет opencode.json", (project / "opencode.json").read_bytes() == (work / "own-config-once").read_bytes())

    kit(work, "--dir", str(project), "--with", "php")
    text = (project / "opencode.json").read_text(encoding="utf-8")
    check("настройки kit-а переживают повтор", '    "model": "example/model",' in text)
    check("повтор не дублирует пути", text.count("alxmrz_kit_general_rules.md") == 1)

    # CRLF и однострочный JSON не должны переформатироваться.
    project = new_project(work, "crlf-config")
    (project / "opencode.json").write_bytes(b'{\r\n  "instructions": [\r\n    "./docs/own.md"\r\n  ]\r\n}\r\n')
    kit(work, "--dir", str(project))
    raw = (project / "opencode.json").read_bytes()
    check("CRLF сохранён", b"\r\n" in raw)
    check("чужая запись CRLF-конфига цела", b'"./docs/own.md"' in raw)

    project = new_project(work, "compact-config")
    (project / "opencode.json").write_text('{"instructions":["./docs/own.md"]}\n', encoding="utf-8")
    kit(work, "--dir", str(project))
    check("однострочный JSON остался однострочным", len((project / "opencode.json").read_text(encoding="utf-8").splitlines()) == 1)

    # Установка только дополняет конфиг: чужие записи и записи прошлого
    # прогона остаются — kit не удаляет из проекта ни файлы, ни строки конфига.
    project = new_project(work, "append-only")
    kit(work, "--dir", str(project), "--with", "php")
    kit(work, "--dir", str(project))
    check("запись прошлого прогона не удаляется", "alxmrz_kit_php_rules" in (project / "opencode.json").read_text(encoding="utf-8"))
    check("файл правила тоже остался", (project / ".agents/rules/alxmrz_kit_php_rules.md").is_file())

    # JSONC и битый JSON: файл не трогается, печатаются пути для ручной правки.
    project = new_project(work, "jsonc-config")
    (project / "opencode.json").write_text('{\n  // комментарий\n  "instructions": []\n}\n', encoding="utf-8")
    shutil.copy2(project / "opencode.json", work / "jsonc-before")
    result = kit(work, "--dir", str(project))
    (work / "jsonc.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("JSONC не роняет установку", result.returncode == 0)
    check("JSONC не изменён", (project / "opencode.json").read_bytes() == (work / "jsonc-before").read_bytes())
    check("для JSONC печатается подсказка", "instructions[]" in (work / "jsonc.log").read_text(encoding="utf-8"))

    # opencode.jsonc не трогаем: комментарии ломают разбор, а рядом с ним
    # opencode.json не создаём — иначе получится два конфига.
    project = new_project(work, "jsonc-project")
    (project / "opencode.jsonc").write_text('{\n  // комментарий\n}\n', encoding="utf-8")
    result = kit(work, "--dir", str(project))
    (work / "jsonc-project.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("opencode.jsonc не роняет установку", result.returncode == 0)
    check("при opencode.jsonc файл не создан", not (project / "opencode.json").exists())
    check("opencode.jsonc не изменён", "// комментарий" in (project / "opencode.jsonc").read_text(encoding="utf-8"))
    check("для opencode.jsonc печатается подсказка", "instructions[]" in (work / "jsonc-project.log").read_text(encoding="utf-8"))

    # Симлинк opencode.json не трогается, установка не падает.
    project = new_project(work, "link-config")
    victim = work / "victim-config.json"
    victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
    (project / "opencode.json").symlink_to(victim)
    result = kit(work, "--dir", str(project))
    (work / "link-config.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("симлинк opencode.json не роняет установку", result.returncode == 0)
    check("файл по симлинку opencode.json не изменён", victim.read_text(encoding="utf-8").strip() == "НЕ ТРОГАТЬ")
    check("правила поставлены при симлинке opencode.json", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())

    # --- 7. команды и агенты -------------------------------------------------
    print("\n== 7. commands и agents")
    project = new_project(work, "commands")
    subprocess.run(
        [sys.executable, str(ext / "install.py"), "--dir", str(project)],
        capture_output=True,
        text=True,
    )
    check("команда попала в .opencode/commands", (project / ".opencode/commands/alxmrz_kit_review.md").is_file())
    check("агент попал в .opencode/agents", (project / ".opencode/agents/alxmrz_kit_reviewer.md").is_file())
    command_files = sorted(p.name for p in (project / ".opencode/commands").iterdir())
    check("пустые каталоги группы не создают мусора", command_files == ["alxmrz_kit_review.md"])

    # --- 8. AGENTS.md: свой файл и симлинк ----------------------------------
    print("\n== 8. AGENTS.md")
    project = new_project(work, "agents-own")
    (project / "AGENTS.md").write_text("# Мой AGENTS\n", encoding="utf-8")
    kit(work, "--dir", str(project))
    check("свой AGENTS.md не перезаписан", (project / "AGENTS.md").read_text(encoding="utf-8") == "# Мой AGENTS\n")
    check("правила подключены и при своём AGENTS.md", "alxmrz_kit_general_rules.md" in (project / "opencode.json").read_text(encoding="utf-8"))

    project = new_project(work, "agents-created")
    kit(work, "--dir", str(project))
    check(
        "AGENTS.md создан и правила подключены",
        (project / "AGENTS.md").is_file()
        and "alxmrz_kit_general_rules.md" in (project / "opencode.json").read_text(encoding="utf-8"),
    )
    with (project / "AGENTS.md").open("a", encoding="utf-8") as handle:
        handle.write("\nправка\n")
    kit(work, "--dir", str(project))
    check("правка своего AGENTS.md переживает обновление", "правка" in (project / "AGENTS.md").read_text(encoding="utf-8").splitlines())

    project = new_project(work, "agents-link")
    victim = work / "victim-agents.md"
    victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
    (project / "AGENTS.md").symlink_to(victim)
    result = kit(work, "--dir", str(project))
    check("симлинк AGENTS.md не роняет установку", result.returncode == 0)
    check("AGENTS.md остался симлинком", (project / "AGENTS.md").is_symlink())
    check("файл по симлинку не изменён", victim.read_text(encoding="utf-8").strip() == "НЕ ТРОГАТЬ")

    # --- 9. .gitignore не трогается ------------------------------------------
    print("\n== 9. .gitignore")
    project = new_project(work, "gitignore-none")
    kit(work, "--dir", str(project))
    check(".gitignore не создан", not (project / ".gitignore").exists())

    project = new_project(work, "gitignore-own")
    (project / ".gitignore").write_bytes(b"vendor/\r\n")
    shutil.copy2(project / ".gitignore", work / "gi-own-before")
    kit(work, "--dir", str(project))
    check("чужой .gitignore сохранён байт-в-байт", (project / ".gitignore").read_bytes() == (work / "gi-own-before").read_bytes())

    # --- 10. dry-run ---------------------------------------------------------
    print("\n== 10. dry-run")
    project = new_project(work, "dry")
    kit(work, "--dir", str(project), "--dry-run")
    check("dry-run не создал .agents", not (project / ".agents").is_dir())
    check("dry-run не создал AGENTS.md", not (project / "AGENTS.md").exists())

    # --- 11. границы записи --------------------------------------------------
    print("\n== 11. границы")
    home = os.environ.get("HOME", "")
    result = kit(work, "--dir", home)
    check("домашний каталог запрещён", result.returncode != 0)
    result = kit(work, "--dir", "/")
    check("корень файловой системы запрещён", result.returncode != 0)
    check("в домашнем каталоге ничего не создано", not (pathlib.Path(home) / ".agents/rules/alxmrz_kit_general_rules.md").exists())
    env = dict(os.environ)
    env["HOME"] = home + "/"
    check(
        "HOME со слешем не обходит защиту",
        subprocess.run(
            [sys.executable, str(INSTALL), "--dir", home],
            capture_output=True,
            env=env,
        ).returncode != 0,
    )
    env = {key: value for key, value in os.environ.items() if key != "HOME"}
    check(
        "HOME без переменной не роняет запуск",
        subprocess.run(
            [sys.executable, str(INSTALL), "--dir", str(work / "basic")],
            capture_output=True,
            env=env,
        ).returncode == 0,
    )
    result = kit(work, "--dir", str(work / "nope"))
    check("несуществующий каталог — внятная ошибка", result.returncode != 0 and "нет такого каталога" in result.stdout + result.stderr)
    result = kit(work, "--dir", str(KIT_ROOT / "README.md"))
    check("файл вместо каталога отклонён", result.returncode != 0)

    project = new_project(work, "link")
    (project / ".agents/rules").mkdir(parents=True)
    victim = work / "victim.md"
    victim.write_text("НЕ ТРОГАТЬ\n", encoding="utf-8")
    (project / ".agents/rules/alxmrz_kit_general_rules.md").symlink_to(victim)
    result = kit(work, "--dir", str(project))
    check("установка через симлинк отклонена", result.returncode != 0)
    check("файл по симлинку не изменён", victim.read_text(encoding="utf-8").strip() == "НЕ ТРОГАТЬ")

    # --- 12. bootstrap.sh удаляет клон ---------------------------------------
    print("\n== 12. bootstrap")
    # Локальный «origin» из текущих исходников kit-а: сеть тесту не нужна.
    origin = work / "origin"
    origin.mkdir()
    for item in ("install.py", "bootstrap.sh", "kit", "components", "snippets", "VERSION"):
        source = KIT_ROOT / item
        target = origin / item
        if source.is_dir():
            shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy2(source, target)
    subprocess.run(["git", "-C", str(origin), "init", "-q", "-b", "main"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(origin), "add", "-A"], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(origin), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"],
        check=True,
        capture_output=True,
    )

    project = new_project(work, "bootstrap")
    env = dict(os.environ, AGENT_KIT_REPO=str(origin))
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--with", "php", env=env)
    (work / "bootstrap.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("bootstrap поставил файлы", result.returncode == 0)
    check("правила на месте", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())
    check("группа --with дошла до install.py", (project / ".agents/rules/alxmrz_kit_php_rules.md").is_file())
    check("клон .agent-kit удалён", not (project / ".agent-kit").exists())
    check("AGENTS.md создан", (project / "AGENTS.md").is_file())
    log = (work / "bootstrap.log").read_text(encoding="utf-8")
    check("в лог попало удаление клона", "Клон kit-а удалён" in log)
    check("подсказка обновления не ведёт в удалённый клон", ".agent-kit/install.py" not in log)

    # Существующий клон в dry-run не удаляется: установка ничего не пишет, значит
    # и не трогает то, чего не создавала.
    project = new_project(work, "bootstrap-dry")
    subprocess.run(["git", "clone", "-q", "--depth", "1", str(origin), str(project / ".agent-kit")], check=True, capture_output=True)
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--offline", "--dry-run")
    check("bootstrap --dry-run завершился", result.returncode == 0)
    check("dry-run оставил клон на месте", (project / ".agent-kit").is_dir())
    check("dry-run не поставил файлы", not (project / ".agents").exists())

    # Свежий клон в dry-run — временный артефакт самого запуска: проект должен
    # остаться чистым, поэтому он удаляется.
    project = new_project(work, "bootstrap-dry-fresh")
    env = dict(os.environ, AGENT_KIT_REPO=str(origin))
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--dry-run", env=env)
    check("bootstrap --dry-run со свежим клоном завершился", result.returncode == 0)
    check("свежий клон удалён после dry-run", not (project / ".agent-kit").exists())
    check("проект после dry-run пуст", not (project / ".agents").exists() and not (project / "AGENTS.md").exists())

    # Клон снаружи проекта — выбор пользователя (AGENT_KIT_DIR), его не удаляем.
    project = new_project(work, "bootstrap-outside")
    outside = work / "outside-kit"
    subprocess.run(["git", "clone", "-q", "--depth", "1", str(origin), str(outside)], check=True, capture_output=True)
    env = dict(os.environ, AGENT_KIT_DIR=str(outside))
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--offline", env=env)
    (work / "bootstrap-outside.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("bootstrap с внешним клоном завершился", result.returncode == 0)
    check("внешний клон не удалён", (outside / ".git").is_dir())
    check("файлы поставлены", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())

    # Ошибка установки: клон остаётся, чтобы было видно, что сломалось.
    project = new_project(work, "bootstrap-fail")
    env = dict(os.environ, AGENT_KIT_REPO=str(origin))
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--with", "nope", env=env)
    check("bootstrap вернул ошибку установки", result.returncode != 0)
    check("после ошибки клон оставлен", (project / ".agent-kit").is_dir())

    # После неудачного запуска клон остался: следующий запуск использует его и
    # удаляет после успешной установки.
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--offline")
    (work / "bootstrap-retry.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("повторный запуск поверх оставшегося клона", result.returncode == 0)
    check("правила поставлены при повторе", (project / ".agents/rules/alxmrz_kit_general_rules.md").is_file())
    check("оставшийся клон удалён после успеха", not (project / ".agent-kit").exists())

    # Рабочий клон с правками — не временный каталог, его не удаляем.
    project = new_project(work, "bootstrap-dirty")
    subprocess.run(["git", "clone", "-q", "--depth", "1", str(origin), str(project / ".agent-kit")], check=True, capture_output=True)
    with (project / ".agent-kit/install.py").open("a", encoding="utf-8") as handle:
        handle.write("\n# доработка kit-а\n")
    result = run_in(project, KIT_ROOT / "bootstrap.sh", "--offline")
    (work / "bootstrap-dirty.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    check("установка из изменённого клона завершилась", result.returncode == 0)
    check("клон с правками не удалён", (project / ".agent-kit/install.py").is_file())
    check("правка в клоне цела", "# доработка kit-а" in (project / ".agent-kit/install.py").read_text(encoding="utf-8"))
    check("предупреждение о незакоммиченных изменениях", "незакоммиченные изменения" in (work / "bootstrap-dirty.log").read_text(encoding="utf-8"))

    # --- 13. ошибка компонента прерывает установку ---------------------------
    print("\n== 13. битый компонент")
    ext = kit_ext(work, "ext-broken")
    nested = ext / "components/base/rules/nested"
    nested.mkdir(parents=True)
    (nested / "x.md").write_text("# вложенный\n", encoding="utf-8")
    project = new_project(work, "broken")
    result = subprocess.run(
        [sys.executable, str(ext / "install.py"), "--dir", str(project)],
        capture_output=True,
        text=True,
    )
    check("вложенность в rules/ прерывает установку", result.returncode != 0)


def diff_trees(left: pathlib.Path, right: pathlib.Path) -> list[str]:
    """Список различий между каталогами (пусто — содержимое совпадает)."""
    left_files = {
        path.relative_to(left): path
        for path in left.rglob("*")
        if path.is_file() or path.is_symlink()
    }
    right_files = {
        path.relative_to(right): path
        for path in right.rglob("*")
        if path.is_file() or path.is_symlink()
    }
    differences = []
    for rel in sorted(set(left_files) | set(right_files)):
        left_path = left_files.get(rel)
        right_path = right_files.get(rel)
        if left_path is None or right_path is None:
            differences.append(str(rel))
            continue
        if left_path.is_symlink() or right_path.is_symlink():
            if not (left_path.is_symlink() and right_path.is_symlink() and os.readlink(left_path) == os.readlink(right_path)):
                differences.append(str(rel))
            continue
        if left_path.read_bytes() != right_path.read_bytes():
            differences.append(str(rel))
    return differences


if __name__ == "__main__":
    sys.exit(main())
