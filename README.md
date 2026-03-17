# 🔧 Anti Gravity Forge

An AI-powered auto-fix pipeline that monitors GitHub for issues, resolves them through a chain of specialized agents, and submits hardened draft PRs for human review.

Fixes are built in an isolated **Forge** — a dedicated cloned workspace per issue — where agents collaborate sequentially before any code reaches a PR.

---

## Architecture

### High-Level Flow

```
GitHub Issue (ag-fix label or /ag command)
        │
        ▼
┌─────────────────┐
│  Mission Runner  │  Polling daemon (start-mission.sh)
└────────┬────────┘
         │  Polls configured repos every N seconds
         ▼
┌─────────────────┐
│   Issue Triager  │  Agent 1: classify, scope, plan
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Forge Setup   │  Clone target repo → .forge/<owner>-<repo>/issue-<id>/
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Engineer      │  Agent 2: implement the fix
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Test Writer    │  Agent 3: write/update tests
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Security Gate   │  Agent 4: SAST + dependency audit + secrets scan
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Code Reviewer   │  Agent 5: style, correctness, conventions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   PR Assembler   │  Agent 6: create PR with structured description
└────────┬────────┘
         │
         ▼
  GitHub PR (draft, assigned to human reviewer)
```

### Runtime Environment

- **Phase 1 (current):** Local machine, invoked manually or via cron/launchd
- **Phase 2 (planned):** Dedicated VPS with systemd service, webhook-triggered instead of polling
- **AI backbone:** Claude Opus via [OpenRouter](https://openrouter.ai) API
- **Workspace isolation:** Cloned repos in `.forge/` directory, namespaced by `<owner>-<repo>`

### Multi-Repo Design

Anti Gravity Forge is **repo-agnostic**. It runs as a standalone service and operates on any repo — including itself.

```
~/code/anti-gravity-forge/              ← the tool itself (this repo)
├── .agents/                             ← agent brains (shared across all repos)
├── .antigravity/config.yml              ← which repos to watch
├── scripts/                             ← pipeline scripts
└── .forge/                              ← runtime workspaces (gitignored)
    ├── mgosal-anti-gravity-forge/       ← forges for THIS repo (self-referential)
    │   └── issue-1/
    ├── mgosal-CoS/                      ← forges for another repo
    │   └── issue-42/
    └── mgosal-some-project/
        └── issue-7/
```

Agent rules live in `anti-gravity-forge/.agents/` and are **never mixed** with target repo code. The forge clones each target repo fresh, so there's zero cross-contamination between projects.

---

## Quick Start

```bash
# 1. Set your OpenRouter API key
export OPENROUTER_API_KEY="sk-or-..."

# 2. Configure which repos to watch
vim .antigravity/config.yml

# 3. Start the polling daemon
./scripts/start-mission.sh

# 4. Create an issue on any watched repo with label "ag-fix"
#    The forge will pick it up on the next poll cycle.
```

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

## Configuration

**File:** `.antigravity/config.yml`

```yaml
mission:
  poll_interval: 60          # seconds between GitHub polls
  max_concurrent_forges: 3   # parallel issue limit across ALL repos

repos:
  - name: "mgosal/anti-gravity-forge"   # specific repo
  - name: "mgosal/CoS"                  # another specific repo
  # - name: "mgosal/*"                  # wildcard: watch ALL repos for owner

labels:
  trigger: "ag-fix"
  in_progress: "ag-in-progress"
  pr_ready: "ag-pr-ready"
  needs_human: "ag-needs-human"

forge:
  base_dir: ".forge"
  branch_prefix: "ag/"
  cleanup_after_merge: true

agents:
  model: "anthropic/claude-opus"   # via OpenRouter
  provider: "openrouter"
  max_tokens: 8192
  temperature: 0
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENROUTER_API_KEY` | Yes | OpenRouter API key for Claude Opus |
| `AG_POLL_INTERVAL` | No | Override poll interval (default: 60s) |
| `AG_MAX_FORGES` | No | Override max concurrent forges (default: 3) |

### GitHub Labels

| Label | Meaning |
|-------|---------|
| `ag-fix` | **Trigger:** issue needs automated fix |
| `ag-in-progress` | Pipeline is actively working on it |
| `ag-pr-ready` | Draft PR has been submitted |
| `ag-needs-human` | Pipeline halted — manual intervention required |

---

## Pipeline Stages — Detailed Specifications

### Stage 1: Issue Triager

**Agent file:** `.agents/rules/triager.md`

**Input:** Raw GitHub issue (title, body, labels, comments, `/ag` command if present)

**Responsibilities:**
1. Parse the issue to extract the actual problem
2. If `/ag` command has specific instructions, extract and prioritize those
3. Classify severity: `trivial` | `standard` | `complex`
4. Identify likely affected files/modules (using repo structure awareness)
5. Produce a scoped implementation plan
6. Determine if the issue is actionable or needs clarification

**Output contract:** `.forge-meta/triage.json`

```json
{
  "issue_id": 42,
  "issue_title": "Login fails when session token expires",
  "classification": "standard",
  "problem_statement": "The session refresh handler throws a TypeError when the refresh token is null, causing a 500 error on the login endpoint.",
  "affected_files": [
    "src/auth/session.ts",
    "src/auth/middleware.ts"
  ],
  "implementation_plan": [
    "Add null check for refresh token in session.ts refreshSession()",
    "Return 401 with clear error message instead of throwing",
    "Update middleware to handle the 401 case gracefully"
  ],
  "acceptance_criteria": [
    "Expired session with null refresh token returns 401, not 500",
    "Error message is user-friendly",
    "Existing valid refresh flow is unaffected"
  ],
  "actionable": true,
  "clarification_needed": null
}
```

**Gate:** If `actionable: false`, post comment requesting clarification, add `ag-needs-human` label, halt pipeline.

---

### Stage 2: Engineer

**Agent file:** `.agents/rules/engineer.md`

**Input:** `triage.json` + full repo context in forge workspace

**Responsibilities:**
1. Read the implementation plan from triage
2. Explore the codebase to understand existing patterns, conventions, imports
3. Implement the fix following existing code style
4. Make minimal, focused changes — no drive-by refactors
5. Ensure the code compiles/passes linting

**Rules:**
- Follow existing project conventions (detect indentation, naming, patterns)
- Never modify files outside the scope defined in `triage.json` unless strictly necessary
- If scope creep is detected, log it and flag for human review
- Add inline comments only where logic is non-obvious
- Every change must trace back to the implementation plan
- No new dependencies without explicit justification in the triage plan

**Output contract:** `.forge-meta/engineer.json`

```json
{
  "files_modified": [
    {
      "path": "src/auth/session.ts",
      "change_summary": "Added null guard on refreshToken before calling refresh endpoint"
    }
  ],
  "files_created": [],
  "files_deleted": [],
  "scope_creep_flags": [],
  "build_passes": true,
  "lint_passes": true
}
```

**Gate:** If `build_passes: false` or `lint_passes: false`, retry once. If still failing, halt and label `ag-needs-human`.

---

### Stage 3: Test Writer

**Agent file:** `.agents/rules/test-writer.md`

**Input:** `triage.json` + `engineer.json` + the actual diff

**Responsibilities:**
1. Identify existing test files for the modified modules
2. Write tests that cover the specific fix
3. Write at least one test for the "before" state (would have failed) and one for the "after" state (now passes)
4. Follow existing test conventions (framework, patterns, file naming)
5. Run the test suite to verify

**Rules:**
- Match existing test framework and style exactly
- Tests must be meaningful, not just "it doesn't throw"
- Cover edge cases identified in the triage acceptance criteria
- Don't modify existing passing tests unless they test the broken behavior
- If no test infrastructure exists for the module, create it following the closest existing pattern

**Output contract:** `.forge-meta/tests.json`

```json
{
  "test_files_modified": ["src/auth/__tests__/session.test.ts"],
  "test_files_created": [],
  "tests_added": 3,
  "tests_modified": 0,
  "all_tests_pass": true,
  "coverage_delta": "+2.1%"
}
```

**Gate:** If `all_tests_pass: false`, send back to Engineer agent with failure details (max 2 retries). If still failing, halt.

---

### Stage 4: Security Gate

**Agent file:** `.agents/rules/security-gate.md`

**Input:** The full diff (all changes from Engineer + Test Writer)

**Three sub-checks:**

#### 4a. Static Analysis (SAST)
- Scan for common vulnerability patterns in the diff
- Check for: SQL injection, XSS, command injection, path traversal, insecure deserialization, hardcoded credentials, improper error handling that leaks info
- Use pattern matching against OWASP Top 10 categories
- If project has Semgrep/ESLint security rules configured, run those

#### 4b. Dependency Audit
- If any dependencies were added/changed, check for known vulnerabilities
- Run the appropriate audit command: `npm audit`, `cargo audit`, `pip audit`, etc.
- Flag any new dependency that doesn't have a clear justification in the triage plan

#### 4c. Secrets Scan
- Scan the diff for anything that looks like an API key, token, password, or secret
- Check for high-entropy strings, known secret patterns (AWS keys, GitHub tokens, etc.)
- Scan for accidental `.env` file commits

**Output contract:** `.forge-meta/security-report.json`

```json
{
  "sast": {
    "passed": true,
    "findings": [],
    "severity_counts": { "critical": 0, "high": 0, "medium": 0, "low": 0 }
  },
  "dependency_audit": {
    "passed": true,
    "new_dependencies": [],
    "vulnerable_dependencies": []
  },
  "secrets_scan": {
    "passed": true,
    "findings": []
  },
  "overall_passed": true
}
```

**Gate:**
- Any `critical` or `high` SAST finding → halt, label `ag-needs-human`
- Any secret detected → halt immediately, do NOT push the branch
- `medium` findings → include as warnings in the PR description
- Dependency vulnerabilities → halt if critical, warn if moderate

---

### Stage 5: Code Reviewer

**Agent file:** `.agents/rules/code-reviewer.md`

**Input:** Full diff + `triage.json` + `security-report.json`

**Responsibilities:**
1. Review code changes for correctness — does the fix actually solve the problem?
2. Review for maintainability — will future developers understand this?
3. Review for consistency — does it match the project's existing patterns?
4. Check for common mistakes: off-by-one, race conditions, resource leaks, unhandled errors
5. Verify the fix doesn't introduce side effects
6. Validate that changes stay within the scoped plan

**Scoring model:**

| Score | Meaning |
|-------|---------|
| 1.0 | Ship it, no concerns |
| 0.8+ | Minor suggestions, safe to ship |
| 0.5–0.8 | Notable concerns, recommend human review |
| < 0.5 | Significant issues, do not ship |

**Output contract:** `.forge-meta/review.json`

```json
{
  "confidence_score": 0.85,
  "verdict": "approve",
  "comments": [
    {
      "file": "src/auth/session.ts",
      "line": 42,
      "severity": "suggestion",
      "comment": "Consider using optional chaining here for consistency with line 38"
    }
  ],
  "concerns": [],
  "scope_verified": true,
  "tests_adequate": true
}
```

**Gate:**
- `confidence_score >= 0.8` → proceed to PR
- `0.5 <= confidence_score < 0.8` → proceed but flag concerns in PR description
- `confidence_score < 0.5` → halt, label `ag-needs-human`

---

### Stage 6: PR Assembler

**Agent file:** `.agents/rules/pr-assembler.md`

**Input:** All `.forge-meta/*.json` files + PR template

**Responsibilities:**
1. Fill in the PR description template from pipeline outputs
2. Generate a conventional commit message
3. The orchestrator handles `git commit`, `git push`, and `gh pr create`

**PR description structure:**

```markdown
## 🔧 Auto-Fix: [Issue Title]

Resolves #[issue_id]

### Problem
[From triage.json]

### Solution
[From engineer.json]

### Changes
| File | Summary |
|------|---------|
| ... | ... |

### Test Coverage
- [x] N new tests added
- [x] All tests passing
- [x] Coverage delta: +X%

### Security Report
- [x] SAST: Passed/Failed
- [x] Dependency Audit: Passed/Failed
- [x] Secrets Scan: Passed/Failed

### Code Review
- Confidence: 0.85
- Verdict: approve

### Pipeline Warnings
[Any medium-severity items]

---
*Generated by Anti Gravity Forge. Human review required before merge.*
```

---

## Forge Lifecycle

Each issue gets its own cloned workspace — a **Forge**. Forges are disposable. If anything goes wrong, delete and start over.

```
1. forge:create  →  gh repo clone <target> .forge/<slug>/issue-<id>/
                     git checkout -b ag/issue-<id>
2. agents work   →  inside the cloned workspace
3. forge:submit  →  git push, gh pr create (draft)
4. forge:cleanup →  rm -rf the forge dir (after PR merged/closed)
```

**Forge directory structure:**

```
.forge/
└── mgosal-CoS/
    └── issue-42/
        ├── (full cloned repo)
        └── .forge-meta/
            ├── triage.json          # Triager output
            ├── engineer.json        # Engineer output
            ├── tests.json           # Test writer output
            ├── security-report.json # Security scan results
            ├── review.json          # Code review output
            ├── pr-description.md    # Final PR body
            └── pipeline.log         # Full audit trail
```

---

## /ag Command Syntax

These commands are supported in issue comments:

```
/ag fix               — Trigger the full auto-fix pipeline
/ag fix --scope src/  — Limit scope to specific directory
/ag triage            — Run triager only, post analysis as comment
/ag review            — Run code reviewer on the current PR
/ag security          — Run security gate on the current PR
/ag status            — Report current pipeline status
```

**Parsing rule:** Any comment starting with `/ag` is treated as a command. The Mission Runner extracts the command and arguments, then dispatches to the appropriate pipeline stage(s).

---

## Agent Invocation Pattern

Each agent follows the same invocation contract:

1. **System prompt** is built from:
   - Agent rules file (`.agents/rules/<agent>.md`)
   - Shared conventions (`.agents/shared/conventions.md`)
   - Security patterns (`.agents/shared/security-patterns.md`) — for the Security Gate only
2. **User prompt** contains:
   - Prior pipeline outputs (relevant `.forge-meta/*.json` files)
   - Repo context (file tree, relevant source files, diffs)
3. **API call** goes to OpenRouter (Claude Opus), temperature 0
4. **Response** is parsed to extract JSON output contract
5. **Gate check** validates the JSON before proceeding to the next stage

Each agent's `.md` rules file contains:
- **Persona** — who the agent is and what it specializes in
- **Input contract** — what files/data it expects
- **Output contract** — what JSON it must produce
- **Rules** — hard constraints on behavior
- **Examples** — sample inputs and outputs for calibration

---

## Project Structure

```
anti-gravity-forge/
├── .agents/
│   ├── rules/
│   │   ├── triager.md                 # Stage 1: classify & plan
│   │   ├── engineer.md                # Stage 2: implement fix
│   │   ├── test-writer.md             # Stage 3: write tests
│   │   ├── security-gate.md           # Stage 4: SAST + secrets
│   │   ├── code-reviewer.md           # Stage 5: review
│   │   └── pr-assembler.md            # Stage 6: assemble PR
│   └── shared/
│       ├── conventions.md             # Project conventions all agents must follow
│       └── security-patterns.md       # OWASP anti-patterns + secret regexes
│
├── .antigravity/
│   ├── config.yml                     # Pipeline configuration
│   ├── missions/
│   │   └── auto-fix.md                # Mission definition + /ag syntax
│   └── templates/
│       └── pr-description.md          # PR body template with placeholders
│
├── scripts/
│   ├── start-mission.sh               # Start the polling daemon
│   ├── stop-mission.sh                # Graceful shutdown
│   ├── forge-create.sh                # Clone target repo into a forge
│   ├── forge-cleanup.sh               # Remove completed forges
│   └── run-pipeline.sh                # Execute the full 6-stage pipeline
│
├── .forge/                            # Runtime workspaces (gitignored)
│   └── <owner>-<repo>/
│       └── issue-<id>/
│           └── .forge-meta/           # Pipeline artifacts
│
├── .gitignore
└── README.md
```

---

## Design Principles

1. **Every stage is gated.** No stage runs until the prior gate passes. Failures halt the pipeline and notify humans.

2. **Every action is logged.** The `.forge-meta/pipeline.log` is the single source of truth for what happened in a forge.

3. **Agents don't talk to each other.** They communicate only through their JSON output contracts. The pipeline orchestrator passes data between them.

4. **Forges are disposable.** If anything goes wrong, delete the forge and start over. No precious state.

5. **Humans are the final gate.** PRs are always draft. No auto-merge. The pipeline's job is to ensure the PR is worth a human's time.

6. **Scope is sacred.** Agents must not make changes outside the triager's defined scope. Scope creep is flagged, not acted on.

7. **Security is not optional.** The security gate runs on every fix, regardless of severity classification. There are no "trivial" bypasses.

---

## Roadmap

### Phase 1 — Core Pipeline ✅ (Built)
- [x] Mission Runner (polling daemon)
- [x] Forge lifecycle (create/cleanup via repo clone)
- [x] Triager Agent
- [x] Engineer Agent
- [x] Test Writer Agent
- [x] PR Assembler
- [x] Basic pipeline gating
- [x] `ag-fix` label detection
- [x] Multi-repo support with wildcards
- [ ] `/ag` comment command parsing (basic structure exists)

### Phase 2 — Security Hardening
- [ ] SAST Agent (pattern-based scanning)
- [ ] Dependency Auditor
- [ ] Secrets Scanner
- [ ] Code Reviewer Agent
- [ ] Pipeline audit logging (`.forge-meta/pipeline.log`)

### Phase 3 — Compliance & Governance
- [ ] Compliance Auditor (basic OWASP checklist)
- [ ] Immutable audit trail (log to external store)
- [ ] Cost tracking (token usage per forge)
- [ ] Metrics dashboard (issues resolved, avg time, failure rate)

### Phase 4 — Production Infrastructure
- [ ] Move to VPS with systemd service
- [ ] Replace polling with GitHub webhooks
- [ ] Observability Agent (post-merge monitoring)
- [ ] Auto-rollback on error rate spike
- [ ] Multi-owner support (beyond single GitHub account)

---

## Pipeline Execution — How `run-pipeline.sh` Works

```
1. Verify forge exists and OPENROUTER_API_KEY is set
2. Fetch issue data from GitHub via `gh issue view -R <repo>`
3. Build repo file tree from the cloned forge workspace
4. For each stage:
   a. Build system prompt (agent rules + conventions)
   b. Build user prompt (prior outputs + repo context)
   c. POST to OpenRouter API (Claude Opus, temperature 0)
   d. Extract JSON from response (handles markdown-wrapped JSON)
   e. Gate check: validate required fields
   f. If gate fails: label issue ag-needs-human, post comment, exit
5. On success:
   a. git add + commit with conventional commit message
   b. git push to ag/issue-<id> branch on target repo
   c. gh pr create --draft on target repo
   d. Label issue ag-pr-ready
```

---

## Known Limitations & TODOs

- **Engineer file writes:** The engineer agent returns file contents in its response, but the pipeline doesn't yet parse and write those files to disk. This needs a response parser that extracts labeled code blocks and writes them to the forge workspace. (Marked as TODO in `run-pipeline.sh`)
- **`/ag` command parsing:** The daemon structure supports it but the comment scanning loop is not yet implemented.
- **Retry logic:** The plan specifies retries (Engineer retry once on build fail, Test Writer → Engineer feedback loop max 2 retries). Currently the pipeline halts on first failure.
- **Concurrent forges:** The daemon enforces `max_concurrent_forges` but runs issues sequentially within a poll cycle. True parallelism would require backgrounding each pipeline run.

---

*Built with Anti Gravity. PRs are always draft. Humans are the final gate.*
