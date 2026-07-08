# BRIEFING — 2026-07-07T18:57:00Z

## Mission
Coordinate the implementation of the Quick Clinic / Guest Coach workflow in HitRate using the Project Pattern.

## 🔒 My Identity
- Archetype: orchestrator
- Roles: orchestrator, user_liaison, human_reporter, successor
- Working directory: /Users/ianrichardson/Projects/HitRate/.agents/orchestrator/
- Original parent: parent
- Original parent conversation ID: 9c8bf9e0-5de0-4c5d-b655-9ac75c98a385

## 🔒 My Workflow
- **Pattern**: Project Pattern
- **Scope document**: /Users/ianrichardson/Projects/HitRate/PROJECT.md
1. **Decompose**: Decompose the project into milestones: Exploration, Test Suite Design, Implementation of ephemeral logic & UI, E2E Test Verification, Hardening.
2. **Dispatch & Execute**:
   - **Delegate (sub-orchestrator)**: For large milestones.
   - **Direct (iteration loop)**: Spawn Explorer -> Worker -> Reviewer -> Challenger -> Auditor for implementation.
3. **On failure** (in this order):
   - Retry: nudge stuck agent or re-send task
   - Replace: spawn fresh agent with partial progress
   - Skip: proceed without (only if non-critical)
   - Redistribute: split stuck agent's remaining work
   - Redesign: re-partition decomposition
   - Escalate: report to parent (sub-orchestrators only, last resort)
4. **Succession**: Self-succeed at spawn count >= 16. Write handoff.md, spawn successor.
- **Work items**:
  1. Explore current codebase & define architecture [pending]
  2. Setup E2E Test Suite [pending]
  3. Implement Quick Clinic workflow [pending]
  4. Verify and harden implementation [pending]
- **Current phase**: 1
- **Current focus**: Explore current codebase & define architecture

## 🔒 Key Constraints
- Make no technical decisions yourself, delegating research and implementation tasks to specialists.
- Never write, modify, or create source code files directly.
- Never run build/test commands yourself — require workers to do so.
- Never reuse a subagent after it has delivered its handoff — always spawn fresh.
- Zero tolerance for integrity violations.

## Current Parent
- Conversation ID: 9c8bf9e0-5de0-4c5d-b655-9ac75c98a385
- Updated: not yet

## Key Decisions Made
- Initial setup using Project Pattern.

## Team Roster
| Agent | Type | Work Item | Status | Conv ID |
|-------|------|-----------|--------|---------|
| explorer_exploration | teamwork_preview_explorer | Explore codebase & design Quick Clinic | completed | 49ffbaf1-7c15-4a41-b596-1a4d1da55b66 |
| worker_build_verify | teamwork_preview_worker | Verify current project builds | completed | afe471f8-324f-4c66-a240-4436b05dfd2a |
| worker_sim_build_verify | teamwork_preview_worker | Verify project builds on simulator | completed | abfba96e-93b8-4d8d-a360-3aff447d745c |
| worker_test_setup | teamwork_preview_worker | Set up E2E Test Suite and hook | completed | 37a42539-9b2d-4a59-af1e-dd58e39f9e34 |
| worker_feature_implementation | teamwork_preview_worker | Implement Quick Clinic feature | completed | 35d1effe-5c4b-4805-81ea-1ac9ef3c37fc |
| auditor_verification | teamwork_preview_auditor | Run forensic integrity audit | completed | 6b8b2b67-c489-43c5-80bd-0302d7704081 |

## Succession Status
- Succession required: no
- Spawn count: 6 / 16
- Pending subagents: none
- Predecessor: none
- Successor: not yet spawned

## Active Timers
- Heartbeat cron: task-23
- Safety timer: none

## Artifact Index
- /Users/ianrichardson/Projects/HitRate/.agents/orchestrator/ORIGINAL_REQUEST.md — Original request file
- /Users/ianrichardson/Projects/HitRate/.agents/orchestrator/BRIEFING.md — My working memory
