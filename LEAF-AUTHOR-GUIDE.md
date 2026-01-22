# Leaf Author Guide

This guide documents the minimal contracts ADT uses to govern `_core/*` nodes.

## Where metadata lives

Each node (leaf or index) is a directory under your consuming repo’s `_core/` tree.

Inside that node directory, create a `.core/` folder with one of:

- `.core/leaf.json` for leaf nodes
- `.core/index.json` for index nodes

ADT discovers nodes recursively under `_core/**` by finding these files.

## `.core/leaf.json`

Required fields:

- `kind`: must be `"leaf"`
- `name`: a non-empty string (typically matches the directory name)

Optional fields:

- `type`: leaf classification (recommended)
- `description`: string
- `upgradeVerification.commands`: array of commands ADT can run after a submodule update

### Leaf types (recommended taxonomy)

ADT does not treat these types differently at runtime today, but they are a useful convention for documenting intent and standardizing verification expectations.

- `library`: reusable code intended to be imported/linked by other code
  - Verification: build + tests + lint (language-specific)
- `tool`: invocable capability (CLI/API/MCP/connector) with defined inputs/outputs
  - Verification: `help`/`version` smoke test + a safe dry-run call when possible
- `guide`: integration documentation and Copilot-facing prompts/procedures (may include code examples)
  - Verification: Markdown correctness + copy/paste snippets + optional “example compiles” checks if you ship runnable samples
- `prompt-pack`: curated prompt templates / procedures intended for injection/retrieval as agent context
  - Verification: format/frontmatter linting + basic “prompt contract” checks
- `schema`: contracts that govern other artifacts (e.g., JSON Schemas)
  - Verification: schema validates + sample documents validate against it
- `template`: scaffolding used by reconciliation/bootstrapping
  - Verification: reconcile applies idempotently; generated files match expectations

Example:

```json
{
  "kind": "leaf",
  "type": "tool",
  "name": "adt",
  "description": "AI Development Toolkit",
  "upgradeVerification": {
    "commands": [
      {
        "name": "Dry-run reconcile",
        "shell": "powershell",
        "cwd": "<repoRoot>",
        "command": "& '<repoRoot>\\_core\\adt\\adt.ps1' reconcile -ProjectRoot '<repoRoot>' -DryRun"
      }
    ]
  }
}
```

Command fields:

- `shell`: one of `powershell`, `pwsh`, `cmd`, `bash`
- `cwd`: optional working directory (relative to repo root or absolute)
- `command`: command text

Substitutions ADT applies:

- `<repoRoot>` → absolute path to the consuming repo root
- `<leafPath>` → the git path to the leaf (e.g. `_core/adt`)

## `.core/index.json`

Required fields:

- `kind`: must be `"index"`
- `domain`: a non-empty string (e.g. `core.vr`)

Optional fields:

- `description`: string
- `canonicalLeaves`: array of strings. Each string is expected to match a node id under `_core/`.
- `children`: optional array of strings (informational today; use it to describe intended structure)

Example:

```json
{
  "kind": "index",
  "domain": "core.vr",
  "canonicalLeaves": ["hud", "telemetry"],
  "children": ["devices", "runtime"]
}
```

## Schemas

The authoritative schemas are:

- `schemas/core.leaf.schema.json`
- `schemas/core.index.schema.json`
- `schemas/project.capabilities.schema.json`
- `schemas/project.dependencies.schema.json`

ADT enforces these during `reconcile` according to `.project/_schema/capabilities.json` (`schemaValidation`: `off|warn|error`).
