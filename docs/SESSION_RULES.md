# Session rules — token discipline

Loaded every session via `@docs/SESSION_RULES.md` in CLAUDE.md. Keep it short.

## Reading

- Never re-read a file already in context. After an Edit, do not read it back.
- Read a range (`offset`/`limit`, or `sed -n 'a,bp'`), not the whole file,
  when you know where you are going. Grep for the symbol first.
- Do not open: `pubspec.lock`, `*.lock`, `venv/`, `build/`, `.dart_tool/`,
  `docs/test-reports/*` (only `tail -n 20` the newest), PDFs in `docs/`.
- For a migration, read only the one you are touching. `db/migrations/` is
  thirteen files; the schema for one table is `grep -n "CREATE TABLE x" -A 40`.
- Trust CLAUDE.md for project state. Do not re-derive it from git log or
  docs unless the user asks for a status review.

## Running commands

- Filter every command that can be noisy. Default to `| tail -n 30`,
  `| grep -iE "error|fail|passed"`, `--stat`, `-n 10`, `--tail 50`.
  Never run bare: `docker compose logs`, `flutter run`, `flutter pub get`,
  `pip install`, `git log`, `git diff` on more than one file, `cat` of a
  file over 200 lines.
- `git diff --stat` first; full diff only for the file in question.
- Journey suite: run the one script for the feature, not
  `run_all_journeys.sh`, and show only the final summary line and failures.
- `flutter analyze` → `| grep -E "error|warning" | head -n 30`.
- Long-running servers (uvicorn, ai_service, `flutter run`) go to a log file
  in the background; grep the log, do not stream it.
- One Bash call with `&&` beats three calls with three result blocks.
- Do not run a command just to confirm what an Edit already reported.

## Tools and agents

- No subagents (Explore, Plan, general-purpose) unless the user names one.
  A cold agent re-reads what is already in context.
- Do not load deferred tools (ToolSearch) speculatively. Load one when the
  next call needs it.
- Prefer Grep/Read over `find`/`cat` pipelines that echo whole files.
- No Artifact, no browser, no screenshots unless asked. Verify Flutter
  changes with `flutter analyze` and the existing test scripts, not a device
  run, unless the user says to run on device.

## Replying

- Do not paste code back into the reply after editing it. Reference
  `path:line` and say what changed in one line.
- No restating the plan, the diff, or the previous message. No preamble,
  no closing summary that repeats the body.
- Status updates between tool calls: one line or none.
- When a command fails, show only the failing lines, not the whole output.
- Answer the question asked. Do not append unrequested suggestions, "next
  steps," or option surveys unless a real decision is needed from the user.

## Planning

- For a feature with a known shape (new endpoint + repository + screen),
  state the design in five lines and proceed. Ask only when two readings
  lead to materially different work.
- Small doc edits, renames, one-file fixes: no plan mode, just do it.
