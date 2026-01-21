# GitHub Copilot / Agent Protocol (Evergreen ADT)

This system uses `.project/` as the committed source of truth during a session.

## Required reads (before changes)

1. `.project/interrupt.md`
2. `.project/README.md`
3. `.project/now.md`
4. `.project/common-pitfalls.md`
5. `.project/reminders.md`

If `.project/interrupt.md` contains a non-empty instruction: stop and ask.

## Bootstrap (first run or after upgrade)

If `.project/` or `.project/state/adt-state.json` is missing, bootstrap once:

- Windows PowerShell (from repo root): `powershell -ExecutionPolicy Bypass -File _core/adt/scripts/adt-init.ps1`

Bootstrap must:

- Create `.project/` and fill missing files from the template (do not overwrite existing project-specific content)
- Create `.scratchpad/`
- Ensure `.scratchpad/` is in `.gitignore`
- Ensure `.github/copilot-instructions.md` exists and includes the ADT block
- Detect legacy `.adt-context/` and migrate/copy content into `.project/` safely
- Write `.project/state/adt-state.json`

## During work

- Keep `.project/now.md` to 1-5 items.
- Record repeated failures in `.project/attempts.md`.
- Record decisions in `.project/record/decisions.md`.
- Put temporary scripts in `.scratchpad/`.

## End of session

If work is in-flight, write a detailed dump to `.project/handoff.md`.
