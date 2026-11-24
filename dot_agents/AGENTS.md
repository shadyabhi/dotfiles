# General

[AGENTS_work.md](./AGENTS_work.md): Read and follow for work-related tasks. Keep organizational tooling, internal URLs, and work-specific procedures here. Keep all other AGENTS files publicly shareable.
[AGENTS_git.md](./AGENTS_git.md): Read and follow before creating or amending a Git commit.
[AGENTS_PR.md](./AGENTS_PR.md): Read and follow before creating or updating a GitHub PR.

- When writing responses, never use Emdash "—"
- When I ask you to give me a command, also copy it to clipboard via pbcopy.
- When making technical decisions, do not give much weight to development cost and timelines.
  - Instead prefer quality code, simplicity, robustness, scalability, and long-term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end use
  - This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  - If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  - If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- When writing tests, ALWAYS follow:
    - NEVER write unit tests after you write code.
    - Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
    - If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.

# Tasks

When doing tasks, always start parallel agents if they can be done independently. Then, you can analyze the agent results and continue with next steps.

## Code Changes

- Design
  - Before writing code:
    - If state machine is applicable, define the finite States, Events, and Context (shared data) and map all valid transitions (State + Event -> Next State) and ensure impossible states are unrepresentable.

  - Implementation rules:
    - Use a clean State pattern, Type-State pattern, or transition table (no nested if/else or sprawling switch blocks).
    - Keep transition logic pure; decouple all side effects (API calls, DB writes, UI updates) into separate handlers/effects. Don't overdo
    - Keep the public interface simple and hide internal state complexity.
    - Code should read such that, we only dig deeper if we need to understand minor details, so each level is like easily readable pseudo-code

  - UI Changes
    - Make sure, components don't overlap each other, making things harder to read, keep it responsive to width.
    - All agent sessions (Claude, Codex) share one Chrome (`~/bin/chrome-devtools-shared`, port 9222), so log in once.
        - Open your own page with `new_page` (`background: true`) and only use that pageId.
        - Right after opening it, run `evaluate_script` to name it: prefix `document.title` with `[<claude|codex> <repo> #<4 random chars>]` and keep it with a MutationObserver on `<title>`. This is how the user knows which session owns which tab.
        - Never `close_page` a page you did not open. Never quit the browser or `bringToFront` another session's page.
        - Background tabs still render (the keeper enables focus emulation), so no need to raise your tab.

- Comments:
  - Don't write comments to justify bad patterns or hacks, fix underlying reasons instead.
  - When reading comments, don't blindly accept claims, always use code to infer the real intent. Fix the root-cause, eliminate comments instead.

# Responding

- When responding in a session, any response, don't just provide the result. Provide how we arrived with the current hypothesis, communicate like a story, how we arrived at the answer. (API calls done, sources used, codepath links etc).

- When providing artifacts, just don't share a "dump" which is unreviewable (JSON/csv etc). If that's what you used, run some commands on top, to analyze what's really needed to validate the output. And share that flow instead.
