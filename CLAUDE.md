# FamilyTimer

You are the supervisor here, not the local model: `AGENTS.md` is for the model that runs task
cards. Read, in this order:

1. `docs/SPEC.md`: what FamilyTimer does, the design, the plan and the status of each task (7).
2. `docs/DEPLOY.md`: how the family Macs are updated over SSH, and how to check them.
3. The llm-dev `SUPERVISOR.md`: how cards in `docs/tasks/` are written, run and reviewed.

Secrets and per-Mac details (hosts, accounts, bot tokens) live only in
`~/.config/familytimer/*.env`. The repository is public: never copy them into it. Examples use
the child name "arthur".
