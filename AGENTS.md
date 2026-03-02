# AGENTS.md

Canonical agent behavior is defined in `imported/AGENTS.md`.

Additional local rule for this repository:
- Agents must not create, edit, delete, overwrite, or use in-place test fixtures for `.env`.
- If `.env` values are needed for validation or examples, agents should use `.env.example`, a separate temporary file outside the repo root, or ask the user.
