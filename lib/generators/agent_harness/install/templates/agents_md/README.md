# AGENTS.md partials

`bin/rails g agent_harness:install` builds the rails_agent_harness block of `AGENTS.md`
from every `*.md.tt` file in this directory, **sorted by filename**, rendered with ERB
(`trim_mode: "-"`) in the generator's binding (so partials can use `profile`,
`test_command`, `lint_command`, `security_command` and `app_file?`), and joined with a
blank line. This README is not rendered.

| Prefix | Section | Owner |
|---|---|---|
| `00_` | Header and detected stack | install generator |
| `10_` | Commands | install generator |
| `20_` | Rails conventions | install generator |
| `30_` | Verify your work (`bin/agent-check`) | agent-check |
| `40_` | Migrations and schema guard | migration guard |
| `50_` | Code review (`rails-review` skill) | review skill |

To add a section, add a partial with the next free prefix. Don't edit other features'
partials.

Content that must appear in more than one generated file lives in `../shared/`
(e.g. `_rails_review_checklist.md.tt`, rendered into both the `50_` section and
`.claude/skills/rails-review/SKILL.md` via `review_partial`), so the copies can't drift.
