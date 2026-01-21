# Copilot Instructions Snippet (Evergreen)

Copy/paste one of these into your repo's `.github/copilot-instructions.md`.

## Option A - Solo / Minimal

```markdown
> **ADT (Required)**:
> 1) Before making changes, read `_core/adt/INSTRUCTIONS.md`.
> 2) Treat `.project/` as the project's committed memory and read it first.
> 3) Check `.project/interrupt.md` at checkpoints; if it contains instructions, stop and ask.
> 4) Log repeated command failures in `.project/attempts.md` and don't repeat the same command without changing something.
> 5) Put temporary scripts/debug helpers in `.scratchpad/` (gitignored).
```

Optional stop condition:

```markdown
> **Stop Condition**: If you have not read `.project/now.md`, stop and read it before proceeding.
```
