# AI Development Toolkit (Evergreen)

This repository is the **ADT platform governance system**.

It is designed for an AI-first workflow where:

- `/_core/` is the governed platform tree (optional but recommended)
- `.project/` is the project's committed memory + machine contract (required)
- ADT lives as a leaf under `/_core/adt` in consuming repos

## Install into a consuming repo

From your repo root:

```bash
git submodule add https://github.com/Rick-Boardman/ai-development-toolkit.git _core/adt
```

Then run the initializer (creates `.project/`, `.scratchpad/`, `.github/`, `.gitignore` entries):

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt-init.ps1
```

## Updating ADT (same protocol as other leaves)

1. Record intent first (in your repo): `.project/record/upgrade-intents/...`
2. Update the submodule pointer:

```bash
git submodule update --remote --merge _core/adt
```

3. Run initializer once if needed (upgrade backfill):

If your repo already had `.project/` but does **not** have `.project/state/adt-state.json` yet:

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt-init.ps1
```

Commit the updated submodule pointer and any new `.project/` state files.

## Docs

- See [INSTRUCTIONS.md](INSTRUCTIONS.md) for the required Copilot/agent protocol.
- See [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) for install/update steps.
