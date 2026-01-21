# Migrations

Idempotent, re-runnable desired-state transforms.

Migration scripts are PowerShell files named like:

- `YYYYMMDDTHHMMSSZ-<name>.ps1`

Each script must accept `-ProjectRoot` and return a hashtable/object with:

- `id` (string)
- `changed` (bool)
- `notes` (string)
