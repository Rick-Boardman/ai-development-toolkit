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

Then run the reconciler (applies migrations and updates platform state):

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\adt.ps1 reconcile
```

## Quickstart

### 1) Add a governed leaf

Create a leaf folder under `_core/` (it can be a normal folder or a git submodule). Then add metadata:

- `_core/<leafName>/.core/leaf.json`

Example:

```json
{
	"kind": "leaf",
	"type": "tool",
	"name": "example-leaf",
	"description": "Example governed leaf",
	"upgradeVerification": {
		"commands": [
			{
				"name": "Smoke test",
				"shell": "powershell",
				"cwd": "<repoRoot>",
				"command": "powershell -NoProfile -Command 'Write-Host ok'"
			}
		]
	}
}
```

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\adt.ps1 reconcile
```

### 2) Declare a dependency (optional)

Edit `.project/state/dependencies.json` and add an entry:

```json
{
	"schemaVersion": "20260121T000000Z",
	"dependencies": [
		{
			"leaf": "example-leaf",
			"path": "_core/example-leaf",
			"addedAt": "2026-01-21T00:00:00Z",
			"notes": "Required for feature X"
		}
	]
}
```

Enforcement is controlled by `.project/_schema/capabilities.json` (`dependencyEnforcement`: `off|warn|error`).

## Updating ADT (same protocol as other leaves)

1. Record intent first (in your repo): `.project/record/upgrade-intents/...`
2. Update the submodule pointer:

```bash
git submodule update --remote --merge _core/adt
```

3. Run reconciler (pulls in new template files, runs migrations, updates core catalog):

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\adt.ps1 reconcile
```

4. Run initializer once if needed (upgrade backfill):

If your repo already had `.project/` but does **not** have `.project/state/adt-state.json` yet:

```powershell
powershell -ExecutionPolicy Bypass -File _core\adt\scripts\adt-init.ps1
```

Commit the updated submodule pointer and any new `.project/` state files.

## Docs

- See [INSTRUCTIONS.md](INSTRUCTIONS.md) for the required Copilot/agent protocol.
- See [INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md) for install/update steps.
- See [LEAF-AUTHOR-GUIDE.md](LEAF-AUTHOR-GUIDE.md) for `_core` node metadata contracts.
