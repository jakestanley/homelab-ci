# AGENTS.md

Canonical agent behavior is defined in `imported/AGENTS.md`.

Additional local rule for this repository:
- Agents must not create, edit, delete, overwrite, replace, or symlink `.env`.
- Agents must not use in-place test fixtures for `.env`.
- If `.env` values are needed for validation or examples, agents must use `.env.example`, a separate temporary file under `/tmp`, or ask the user.
- Agents must never remove or overwrite an existing `.env`, even temporarily for testing.
