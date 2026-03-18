# Iron Tech Forge: AI Participation Rules

These rules apply to any automated or semi-automated AI session (like Anti-Gravity Chat) interacting with this repository.

## Branching Strategy
- **Manual Chores/Features**: Always create a new branch prefixed with `chore/` or `feat/`.
- **Merge Process**: Do NOT push directly to `main`. Open a Pull Request and use the Admin Bypass only if explicitly requested by the user.
- **Automated Fixes**: The internal Forge pipeline uses `ag/issue-###` (historical) or `forge/issue-###` (new standard) branches. 

## Security & Identity
- **Environment Overrides**: Never hardcode emails or API keys in `config.yml`. Always use `AG_BOT_EMAIL` and `AG_BOT_NAME` environment variables (sourced from `.env.local`).
- **Secret Leaks**: Check `.env.local` is in `.gitignore` before every push. 

## Rebranding Guardrails
- **Naming Context**: This project is **Iron Tech Forge** (formerly Anti-Gravity Forge).
- **Control Folder**: Configuration lives in **`.forge-master/`** (formerly `.antigravity/`).
- **Labels**: Use **`forge-`** prefixed labels for triggering the pipeline.

## Grounded Documentation
- Maintain a highly technical, scientific, and representative tone in all README updates and PR descriptions. 
- Avoid hype. Use comparison tables to document architectural trade-offs.
- When finishing a task, update the `walkthrough.md` or `README.md` to ensure context persistence across different workspaces.
