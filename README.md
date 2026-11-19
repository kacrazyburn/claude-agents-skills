# claude-agents-skills

Скилы и агенты Claude Code для подключения к SDLC-пулу: сторона кастомера (постановщик задач) и сторона воркера (исполнитель).

Базовый адрес сервера пула: `https://92-63-110-49.sslip.io`.

| Сторона | MCP-сервер (имя → путь) | Файлы из этого репо | Куда положить |
|---|---|---|---|
| Кастомер | `sdlc-submit` → `/mcp-submit` | `customer/.claude/agents/sdlc-proxy.md`, `customer/.claude/skills/sdlc-customer/SKILL.md` | `.claude/` своего проекта |
| Воркер | `sdlc` → `/mcp`, `sdlc-relay` → `/mcp-relay` | `worker/.claude/skills/pool-worker/SKILL.md` | `.claude/` пустого рабочего каталога |

## Ключ доступа (обе стороны)

- Ключ выдаёт администратор пула через админку: ключ кастомера (`submitter`) или ключ воркера (`worker`). Своего ключа нет — обратитесь к администратору пула.
- В командах ниже вместо `<token>` подставьте свой ключ. Ключ — секрет: не коммитьте его и не публикуйте.
- Токены и учётные данные админки и доски в этом репо не публикуются и не нужны: кастомеру и воркеру достаточно ключа.

## Кастомер (постановщик задач)

1. Подключите MCP-сервер пула `sdlc-submit` (один раз):

```sh
claude mcp add --transport http sdlc-submit https://92-63-110-49.sslip.io/mcp-submit --header "Authorization: Bearer <token>"
```

2. Скопируйте в свой проект содержимое каталога `customer/.claude/`:
   - агент `sdlc-proxy` → `.claude/agents/sdlc-proxy.md`;
   - скил `sdlc-customer` → `.claude/skills/sdlc-customer/SKILL.md` (с ним сессия отдаёт задачи, на которые нужен ответ, прокси пула, а не локальным сабагентам).
3. В сессии Claude Code напишите: `delegate to sdlc-proxy: <задача>`.

Скил `sdlc-customer` упоминает бандл-прокси `<agent>-pool` для ваших агентов из `.claude/agents/`. Такой прокси собирает CLI `sdlc proxy <agent>`, которого в публичном доступе нет; без него используйте `sdlc-proxy`.

## Воркер (исполнитель)

1. Подключите MCP-сервер пула `sdlc` (один раз):

```sh
claude mcp add --transport http sdlc https://92-63-110-49.sslip.io/mcp --header "Authorization: Bearer <token>"
```

2. Подключите ретранслятор MCP `sdlc-relay` для шагов агента с MCP (один раз, тот же ключ):

```sh
claude mcp add --transport http sdlc-relay https://92-63-110-49.sslip.io/mcp-relay --header "Authorization: Bearer <token>"
```

3. Положите скил `pool-worker` в пустой рабочий каталог как `.claude/skills/pool-worker/SKILL.md` (файл — `worker/.claude/skills/pool-worker/SKILL.md`).
4. Запустите `claude` в этом каталоге и выполните `/pool-worker`.

Скил `pool-worker` одинаков для всех ключей: протокол под ваш ключ он получает у сервера пула. Альтернатива без файла скила — промпт MCP-сервера пула:

```text
/mcp__sdlc__worker
```

Скил `sdlc-worker`, собранный под профиль вашего ключа, в этом репо не публикуется — его можно скачать на странице ключа в админке пула.

## Мейнтейнеру

Источник истины для файлов в `customer/` и `worker/` и для команд подключения в этом README — движок пула на коммите `ENGINE_REF` (см. `Makefile`; это коммит, выложенный на сервер пула). Файлы — побайтные копии рендера движка: руками не правятся.

- `make sync ENGINE_GIT=<путь или URL репо движка>` — перезаписать копии рендером на `ENGINE_REF`.
- `make parity ENGINE_GIT=<…>` — сверить копии с рендером и проверить, что README дословно содержит команды подключения и строку промпта воркера из движка; при расхождении — ненулевой код и diff.
- Смена `ENGINE_REF` (новый релиз на сервере) → `make sync`, правка README при необходимости, `make parity`.

`ENGINE_GIT` задаётся только окружением или аргументом make: репо движка закрытое, дефолта нет. Движок клонируется и собирается в `.tools/engine` (`ENGINE_DIR`), рендер идёт в docker-образе Node; свой checkout движка не трогается. Остальные цели: `make lint`, `make format`, `make init` (pre-commit-хуки).
