---
name: eap-agent-workflow
description: Operate EAP multi-agent workflows safely and practically. Use when the user asks to use multiple agents, fix agent workflow, create BMAD-like roles, coordinate Architect/Performance/Implementation/QA/Reviewer agents, or avoid subagent hangs.
---

# EAP Agent Workflow

Use this skill to coordinate role-separated EAP work without turning subagents into uncontrolled long-running tasks.

## Core rules

- The main agent owns the final answer and all file edits unless explicitly delegated.
- Prefer one or two subagents only. More agents are allowed only when tasks are independent.
- Do not pass full conversation history to subagents by default.
- Subagents must not spawn child agents unless the user explicitly requests nested delegation.
- Read-only review agents do not modify files.
- Implementation agents modify files only after Architect/Performance scope is accepted.
- If a subagent times out once, send one finalize request. If it times out again, continue locally and report the failure.

## Default role map

- Product: scope, MVP, resume value.
- Architect: DDD boundaries, ownership, event flow, consistency. No code.
- Performance: TPS, DB, MQ, JVM, measurement correctness. No business redesign unless needed.
- Implementation: code only accepted scope.
- QA: tests, failure modes, acceptance criteria.
- Reviewer: production-style review.

## Subagent prompt template

```text
Role: <Architect|Performance|QA|Reviewer|Implementation>
Forbidden: do not spawn subagents; do not modify files; do not browse unrelated context.
Task: <one exact question>
Context: <short facts only>
Allowed files: <paths or "none">
Output: max 10 bullets. Include recommendation, risks, and next task.
Deadline: return best effort with assumptions; do not wait for perfect information.
```

## Recommended fork policy

- Use no or minimal forked context.
- Include only:
  - latest benchmark numbers;
  - relevant file paths;
  - current decision question;
  - constraints.
- Avoid `fork_turns="all"` unless the task is summarization of conversation history.

## Practical workflow

1. Main agent writes a compact ticket brief.
2. Spawn Architect and Performance only if both can review independently.
3. Wait once.
4. If both return, merge findings into a decision.
5. If one hangs, send finalize once, then proceed locally.
6. Implementation starts only after the decision is explicit.
7. QA/Reviewer validate after implementation.
