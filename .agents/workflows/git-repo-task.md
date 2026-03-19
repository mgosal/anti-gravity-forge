---
description: Standard workflow for completing a task on a Git repository - ensures README is updated and the linked GitHub issue is closed
---

# Git Repo Task Workflow

Use this workflow whenever completing a development task that is linked to a GitHub issue on any Git repository.

## Planning Phase

1. Add the following items to `implementation_plan.md` under the Verification Plan:
   - [ ] Update `README.md` to reflect new features or changes
   - [ ] Close the linked GitHub issue with a summary comment

## Execution Phase

2. Complete all development tasks as planned.

## Verification Phase

3. After all changes are implemented and tested, update `README.md`:
   - Add any new features, commands, or configuration options
   - Update the Roadmap section if applicable (mark items `✅` complete)
   - Ensure Quick Start and Local Dev Setup sections are accurate

// turbo
4. Commit and push the README update:
   ```bash
   git add README.md && git commit -m "docs: update README with latest changes" && git push origin main
   ```

5. Close the linked GitHub issue using the `gh` CLI (or via `docker exec` if running containerized):
   ```bash
   gh issue comment <ISSUE_NUMBER> -R <owner/repo> --body "<summary of what was done>"
   gh issue close <ISSUE_NUMBER> -R <owner/repo>
   ```
   > If `gh` is not available locally, use:
   > ```bash
   > docker exec iron-tech-forge gh issue comment <ISSUE_NUMBER> -R <owner/repo> --body "<summary>"
   > docker exec iron-tech-forge gh issue close <ISSUE_NUMBER> -R <owner/repo>
   > ```
