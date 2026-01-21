# Integration Guide (Evergreen)

This guide explains how to add ADT to a consuming repository.

## Assumptions

- ADT is installed as a git submodule at `/_core/adt`
- `.project/` is the committed project memory + machine contract
- `.scratchpad/` is a gitignored scratch area for temporary scripts/debug

## Install

From the consuming repo root:

```bash
git submodule add https://github.com/Rick-Boardman/ai-development-toolkit.git _core/adt
```

Initialize `.project/` and required files:

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt-init.ps1
```

Commit:

- `/_core/adt` submodule pointer
- `.project/`
- `.github/copilot-instructions.md`
- `.gitignore` changes

## Updating ADT

Record intent first:

- `.project/record/upgrade-intents/YYYY-MM-DD-adt.md`

Then update the submodule pointer:

```bash
git submodule update --remote --merge _core/adt
```

Then run initializer (safe, idempotent):

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt-init.ps1
```

Finally, record outcome:

- `.project/record/upgrade-results/YYYY-MM-DD-adt.md`

### Upgrade note: initialization state

If your repo already had `.project/` but did **not** have `.project/state/adt-state.json` yet, the initializer will create it. Commit it.
