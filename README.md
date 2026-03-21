# Iron Tech Forge

*A platform-independent and self-documenting agentic framework.*

An experimental auto-fix pipeline that monitors GitHub for issues, attempts to resolve them through a chain of specialized agents, and submits draft PRs for human review.

> [!NOTE]
> This project is **platform-independent** and has zero dependencies on any specific AI platform. It was built *on* and *with* Anti-Gravity, but operates as a standalone Unix-native tool.

Fixes are built in an isolated **Forge** — a dedicated cloned workspace per issue — where agents process the code sequentially before any code reaches a PR.

---

## Architecture

Iron Tech Forge is a **zero-dependency, Unix-native agent framework**. Unlike modern "heavy" frameworks (LangChain, CrewAI), it relies entirely on standard Bash scripts, `curl`, and `jq` to orchestrate multi-agent workflows.

### Why Bash?
- **Zero-Dependency**: No `npm install`, no `pip install`. If you have `bash`, `curl`, and `jq`, you have a forge.
- **Transparent**: Every prompt and response is a discrete file in `.forge-meta/`. No hidden internal logic or complex abstractions.
- **Composable**: Easily wraps existing CLI tools (like `gh`, `git`, or `docker`) without specialized "integrations."

### Framework Comparison

| Feature | Iron Tech Forge | Devin / OpenHands | LangChain / CrewAI |
|---------|---------------------|-------------------|-------------------|
| **Language** | Bash / Unix Shell | Python / JS | Python / JS |
| **Logic** | Agentic Loops | Re-entrant Loops | Graph / Sequential |
| **Sandbox** | `git clone` (Shallow) | Docker / VM | Local / Varied |
| **Primary Tool** | `curl` + `jq` | Persistent OS Shell | Library-specific SDKs |
| **Complexity** | Medium | High | High |

---

## High-Level Flow (v2 Agentic Loop)

```
GitHub Issue (forge-fix label or /forge command)
        │
        ▼
┌─────────────────┐
│     IronTech     │  Polling daemon (start-irontech.sh)
└────────┬────────┘
         │  Polls configured repos every N seconds
         ▼
┌─────────────────┐
│ [0] Index        │  Auto-detect language, build & test commands
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [1] Architect*   │  If blank repo or complex change: Plan in GitHub issue
└────────┬────────┘   Pauses, waits for human to re-add forge-fix
         │
         ▼
┌─────────────────┐
│ [2] Triager Loop │  Reads files, scopes work. Asks human if ambiguous.
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [3] Engineer Loop│  Writes real code. Runs build. Retries up to 3x on err.
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [4] Test Loop    │  Writes tests. Runs tests. Retries up to 3x on err.
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [5] Review Loop  │  Reads full files. Asks human if confidence < 0.7.
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [6] PR Assembler │  Synthesises PR description.
└────────┬────────┘
         │
         ▼
  GitHub PR (draft, assigned to human reviewer)

[Any Exhaustion] → Escalation Agent posts GitHub comment & exits cleanly.
```

### Runtime Environment

- **Phase 1:** Local machine, invoked manually via `start-irontech.sh`
- **Phase 2:** Production-ready Docker container for VPS (Hostinger, etc.)
- **Phase 3 (planned):** Webhook-triggered instead of polling

- **AI backbone:** Claude Opus via [OpenRouter](https://openrouter.ai) API
- **Workspace isolation:** Cloned repos in `.forge/` directory, namespaced by `<owner>-<repo>`

### Multi-Repo Design

Iron Tech Forge is **repo-agnostic**. It runs as a standalone service and operates on any repo — including itself.

```
~/code/iron-tech-forge/                  ← the tool itself (this repo)
├── .agents/                             ← agent brains (shared across all repos)
├── .forge-master/config.yml             ← which repos to watch
├── scripts/                             ← pipeline scripts
└── .forge/                              ← runtime workspaces (gitignored)
    ├── mgosal-iron-tech-forge/          ← forges for THIS repo (self-referential)
    │   └── issue-1/
    ├── mgosal-CoS/                      ← forges for another repo
    │   └── issue-42/
    └── mgosal-some-project/
        └── issue-7/
```

Agent rules live in `.agents/` and are **never mixed** with target repo code. The forge clones each target repo fresh, so there's zero cross-contamination between projects.

---

## Quick Start

```bash
# 1. Set your OpenRouter API key in .env.local
echo "OPENROUTER_API_KEY=sk-or-..." >> .env.local

# 2. Configure which repos to watch
vim .forge-master/config.yml

# 3. Start the IronTech daemon
./scripts/start-irontech.sh

# 4. Initialize a new repository
#    Create a new issue in any watched repository with the title: /forge-init
#    The forge will automatically set up the required labels.

# 5. Create an issue on any watched repo with label "forge-fix"
#    The forge will pick it up on the next poll cycle.

```

---

## Local Dev Setup

If you are setting up a fresh workspace (e.g., after a new `git clone`), follow these steps:

### 1. Re-create `.env.local`
This project relies on environment variables for sensitive access. Create a `.env.local` file in the root:

```bash
# Required: Your OpenRouter API Key
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxx

# Recommended: Your GitHub Personal Access Token (for the 'gh' CLI)
GH_TOKEN=github_pat_xxxxxxxxxxxx

# Optional: Configuration Overrides (Docker Best Practices)
AG_REPOS=mgosal/*
AG_BOT_EMAIL="your-bot-email@example.com"
AG_BOT_NAME="ForgeMaster"

```

### 2. Configure Repositories
Edit `.forge-master/config.yml` to include the repositories you want to monitor.

### 3. Verify Remote
If you renamed the repository on GitHub, ensure your local remote is updated:
```bash
git remote set-url origin https://github.com/mgosal/iron-tech-forge.git
```

---

## Secure Machine User Setup (Recommended)

For production use or to strictly separate bot activity from your personal account, follow these steps to set up a **Machine User**:

1.  **Create a Dedicated Bot Account**: Register a new, free GitHub account (e.g., `forge-bot-[yourname]`).
2.  **Invite to Repos**: On GitHub, go to your repository **Settings > Collaborators** and invite the bot account with **Write** access.
3.  **Generate a PAT**: Log in as the bot and create a **Fine-grained Personal Access Token (PAT)** with:
    - Repository permissions: `Contents` (read/write), `Pull Requests` (read/write), `Metadata` (read-only).
4.  **Update `.env.local`**:
    ```bash
    # Use the bot's PAT instead of your personal token for gh CLI
    GH_TOKEN=github_pat_xxxxxxxxxxxx
    
    # Match the bot's GitHub profile
    AG_BOT_EMAIL="bot-account-email@example.com"
    AG_BOT_NAME="ForgeMaster Bot"
    ```
5.  **GitHub CLI**: If running the daemon, ensure the environment has the `GH_TOKEN` variable available so the `gh` commands use the bot's identity instead of yours.

---

### Manual Run (Single Issue)

```bash
# Fix a specific issue without the daemon
./scripts/forge-create.sh mgosal/CoS 42
./scripts/run-pipeline.sh mgosal/CoS 42

# Clean up after PR is merged
./scripts/forge-cleanup.sh mgosal/CoS 42

# Clean up ALL forges
./scripts/forge-cleanup.sh --all
```

---

## Docker Deployment

Iron Tech Forge is production-ready for VPS deployment (e.g., Hostinger).

```bash
# 1. Build and start the background daemon
docker compose up -d --build

# 2. View live logs
docker logs -f iron-tech-forge
```

See the [Deployment Guide](file:///Users/mandip/.gemini/antigravity/brain/9283c0d9-95f1-485a-a194-c9b7c211fd2f/deployment_guide.md) for full instructions on setting up your VPS.


---

## Configuration

**File:** `.forge-master/config.yml`

```yaml
mission:
  poll_interval: 60          # seconds between GitHub polls
  max_concurrent_forges: 3   # parallel issue limit across ALL repos
  bot:
    name: "ForgeMaster"
    email: "bot@example.com"

repos:
  - name: "mgosal/iron-tech-forge"      # specific repo
  - name: "mgosal/CoS"                  # another specific repo

labels:
  trigger: "forge-fix"
  in_progress: "forge-in-progress"
  pr_ready: "forge-pr-ready"
  needs_human: "forge-needs-human"

forge:
  base_dir: ".forge"
  base_branch: "main"
  branch_prefix: "forge/issue-"
  cleanup_after_merge: true

agents:
  # Model for tool-calling inner loop (must support OpenAI tools schema)
  model: "anthropic/claude-3.5-sonnet"
  # Model for code-reviewer and final gate only (higher quality, slower)
  reviewer_model: "anthropic/claude-opus-4.6"
  # Model for architect persona (blank repo onboarding)
  architect_model: "anthropic/claude-3.5-sonnet"
  max_tool_rounds: 10      # max tool call rounds per agent invocation
  max_retries: 3           # retry limit for engineer loop and test loop independently

execution:
  # Leave blank to auto-detect from package.json/Makefile/Cargo.toml/etc.
  build_cmd: ""
  test_cmd: ""
  cmd_timeout: 120   # seconds per shell command execution
  allowed_cmds:      # allowlist for run_shell — only these commands may be executed
    - "npm test"
    - "npm run build"
    - "cargo test"
    - "cargo build"
    - "pytest"
    - "make test"
```

---

## Pipeline Stages — Detailed Specifications

### Stage 0: Codebase Indexer

**Script:** `scripts/lib/codebase-index.sh`
**Responsibilities:** Detects language, project type, and specific build/test commands.

---

### Stage 1: Architect (Conditional)

**Agent file:** `.agents/rules/architect.md`
**Responsibilities:** Kicks in for empty repos or massive changes. Formulates high-level plan as a GitHub issue comment, pauses pipeline for human approval.

---

### Stage 2: Issue Triager

**Agent file:** `.agents/rules/triager.md`
**Responsibilities:** Parses the issue, uses `search_codebase` tools to confirm affected files, and produces a scoped implementation plan. Loop: Asks human if ambiguous.

---

### Stage 3: Engineer Loop

**Agent file:** `.agents/rules/engineer.md`
**Responsibilities:** Implements the fix using `write_file`, `apply_diff`, `sed_replace`. Shells out to the actual repository build command. If it fails, error output is fed back for a retry (max 3).

---

### Stage 4: Test Loop

**Agent file:** `.agents/rules/test-writer.md`
**Responsibilities:** Writes tests and runs the actual repository test suite. If it fails, error output is fed back for a retry (max 3).

---

### Stage 5: Code Reviewer

**Agent file:** `.agents/rules/code-reviewer.md`
**Responsibilities:** Uses `read_file` to review full files in context. Ensures code matches conventions, assigns confidence score. Halts if score is low.

---

### Stage 6: PR Assembler

**Agent file:** `.agents/rules/pr-assembler.md`
**Responsibilities:** Synthesizes the run into a perfect PR description. Auto-closes issues via "Closes #ID".

---

### Escalation: Retry Escalator

**Agent file:** `.agents/rules/retry-escalation.md`
**Responsibilities:** Steps in when Engineer or Test loops hit max retries. Posts a blameless summary of what was tried and what failed to GitHub.

## Forge Lifecycle

Each issue gets its own cloned workspace — a **Forge**.

```
1. forge:create  →  gh repo clone <target> .forge/<slug>/issue-<id>/
                     git checkout -b forge/issue-<id>
2. agents work   →  inside the cloned workspace
3. forge:submit  →  git push, gh pr create (draft)
4. forge:cleanup →  rm -rf the forge dir
```

---

## Project Structure

```
iron-tech-forge/
├── .forge-master/
│   ├── config.yml                     # Pipeline configuration
│   ├── missions/
│   │   └── auto-fix.md                # Mission definition
│   └── templates/
│       └── pr-description.md          # PR body template
├── .agents/
│   ├── rules/                         # Agent "brains"
│   └── shared/                        # Shared conventions
├── scripts/
│   ├── start-irontech.sh              # Polling daemon
│   ├── forge-create.sh                # Setup forge
│   ├── run-pipeline.sh                # Main orchestration
│   └── forge-cleanup.sh               # Cleanup script
├── .forge/                            # Runtime workspaces (gitignored)
├── .gitignore
└── README.md
```

---

## Design Principles

1. **Every stage is gated.** No stage runs until the prior gate passes.
2. **Every action is logged.** `.forge-meta/pipeline.log` is the source of truth.
3. **Humans are the final gate.** PRs are always draft. No auto-merge.

---

## Roadmap

### Phase 1 — Core Pipeline ✅ (Built)
- [x] IronTech (polling daemon)
- [x] Forge lifecycle (create/cleanup)
- [x] Zero-dependency Unix-native architecture
- [x] Auto-closing issue logic

### Phase 2 — V2 Agentic Loop ✅ (Built)
- [x] **Real Code Application**: Diffs pushed to disk.
- [x] **Real Test/Build Execution**: Shelling out to actual repo scripts.
- [x] **Retry Loops**: Engineer & Test auto-recover from failures.
- [x] **Human-in-the-Loop**: Architect & Triage interact over GitHub comments.

### Phase 3 — Future Roadmap
- [ ] **Web Search**: Give Architect tool access to research APIs/Frameworks online.
- [ ] **Webhook Triggering**: Move from polling to real-time events.

---

*PRs are always draft. Human review is required before merging.*
