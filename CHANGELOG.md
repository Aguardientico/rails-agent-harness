# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Hooks and `bin/agent-check` no longer crash under a non-UTF-8 locale (`LC_ALL=C`) on
  non-ASCII hook input, file names, project paths, file contents or tool output: these are read
  as UTF-8. Before, `hook pre-tool-use` exited 1, which Claude Code treats as non-blocking, so
  the guarded Write/Edit went through.
- The migrations check accepts the migration numbers Rails generates when several migrations
  are created in the same second (e.g. `20261101123460`, seconds past 59); it now checks for a
  valid date at most 24 hours in the future instead of a strict time round-trip.

## [0.1.0] - Unreleased

### Added

- Gem skeleton: `RailsAgentHarness::Configuration` for `config/agent_harness.yml` (defaults,
  deep merge, type checks, warnings for unknown keys), a Railtie, and CI for Ruby 3.3/3.4/4.0
  on Rails 8.1 plus Rails `main`.
- `bin/rails g agent_harness:install`: detects the app's stack (Rails version, RSpec or
  Minitest, database, RuboCop/Standard, Brakeman, schema format) and writes `AGENTS.md`,
  `CLAUDE.md` (importing `AGENTS.md`) and `config/agent_harness.yml`. Re-runs only refresh the
  marked block and keep user content.
- `bin/agent-check`: checks the change set since the merge base with RuboCop on changed files,
  Brakeman and the tests mapped to the changed files; plain-text, truncated output; exit
  status 0/1. Claude Code hooks (`PostToolUse` RuboCop on the edited file, `Stop` full check)
  merged into `.claude/settings.json`, and a "Verify your work" section in `AGENTS.md`.
- `rails-review` Claude Code skill (`.claude/skills/rails-review/SKILL.md`) and a matching
  "Rails code review" section in `AGENTS.md`, rendered from one shared checklist (N+1 queries,
  missing indexes, strong parameters, callbacks, transactions, security, tests).
- Migration/schema guard: a `PreToolUse` hook that blocks hand-written migration files and
  hand edits to `db/schema.rb`/`db/structure.sql`, a `migrations` check in `bin/agent-check`
  for every agent, and a "Database changes" section in `AGENTS.md`.
- README, a reproducible before/after demo (`demo/run`, run in CI) and release notes.

[Unreleased]: https://github.com/Aguardientico/rails-agent-harness/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Aguardientico/rails-agent-harness/releases/tag/v0.1.0
