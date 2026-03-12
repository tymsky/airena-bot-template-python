# AiRENA Bot Template (Python)

[![PyPI](https://img.shields.io/pypi/v/airena-sdk?label=airena-sdk)](https://pypi.org/project/airena-sdk/)

Starter template for building an AiRENA / OpenRA RA bot in Python.

## Prerequisites

- Python 3.10+
- Docker Desktop (Linux containers) — for smoke tests and bot-vs-bot matches

## Project layout

```text
AiRENA-bot-template-python/
├── main.py                  # Your bot strategy (edit this)
├── airena.runtime.json      # Smoke test runtime config
├── requirements.txt         # Python dependencies (SDK + your own)
├── artifacts/               # Smoke test output (gitignored)
├── docs/                    # Reference documentation
│   ├── action-reference.md
│   ├── observation-reference.md
│   ├── protocol-lifecycle.md
│   └── building-lifecycle.md
└── scripts/
    ├── smoke.ps1            # Run headless smoke test via Docker
    ├── match.ps1            # Bot-vs-bot match via Docker
    └── build.ps1            # Package bot into a single binary (Nuitka/Docker)
```

## Quick start

1. Clone this repo and rename it for your bot.

2. (Optional) Create a local Python environment for IDE support and local testing:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

3. Run a smoke test:

```powershell
.\scripts\smoke.ps1
```

This pulls the runtime image (first run only), mounts your bot into a container,
installs dependencies, runs a full headless match, and writes artifacts to `artifacts/`.

4. Inspect results in `artifacts/smoke-<timestamp>/`.

## Writing your bot

Edit `main.py` — implement your strategy in `handle_tick()`.

The SDK (`airena-sdk`) is pre-installed in the runtime Docker image.
If your bot needs additional Python packages, add them to `requirements.txt` —
the runtime installs them automatically at container startup.

## Documentation

Detailed reference documentation is in the `docs/` folder:

- **[Action Reference](docs/action-reference.md)** — all actions with fields, preconditions, error cases, and SDK examples
- **[Observation Reference](docs/observation-reference.md)** — observation fields, production queues, resources, faction info
- **[Protocol Lifecycle](docs/protocol-lifecycle.md)** — message flow, timeouts, limits, error handling
- **[Building Lifecycle](docs/building-lifecycle.md)** — step-by-step building guide with complete code example

## Scripts

### `smoke.ps1` — Headless smoke test (Docker)

Runs your bot against a built-in AI opponent in a headless Docker container.

```powershell
.\scripts\smoke.ps1                        # defaults from airena.runtime.json
.\scripts\smoke.ps1 -Ticks 1500            # override settings
.\scripts\smoke.ps1 -Faction soviet        # play as Soviet
```

### `build.ps1` — Package bot into a single binary

Compiles your bot into a single Linux binary using Nuitka (built inside Docker).
The output is a single file that can be shared without exposing source code.

```powershell
.\scripts\build.ps1                         # produces dist/bot
.\scripts\build.ps1 -Script my_bot.py -OutputName my_bot
```

### `match.ps1` — Bot-vs-bot match (Docker)

Pits two pre-built bot binaries against each other in a headless 1v1 match.

```powershell
.\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot
.\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot -Ticks 6000
```

## Configuration

Runtime settings live in `airena.runtime.json`:

| Field             | Default                                              | Description                           |
|-------------------|------------------------------------------------------|---------------------------------------|
| `image`           | `ghcr.io/tymsky/airena-openra-headless:latest`      | Docker image for the runner           |
| `map`             | `a-nuclear-winter`                                   | Map name                              |
| `ticks`           | `6000`                                               | Engine tick limit                     |
| `opponent_ai`     | `normal`                                             | Opponent AI type                      |
| `timeout_seconds` | `300`                                                | Container timeout                     |

## Development loop

1. Edit `main.py`
2. Run `.\scripts\smoke.ps1` (quick iteration via Docker)
3. Check `artifacts/` for results, logs, and replay
4. Build: `.\scripts\build.ps1` (produces `dist/bot`)
5. Test against other bots: `.\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot`
6. Repeat
