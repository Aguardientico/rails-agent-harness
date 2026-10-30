# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased

### Added

- Gem skeleton: `RailsAgentHarness::Configuration` for `config/agent_harness.yml` (defaults,
  deep merge, type checks, warnings for unknown keys), a Railtie, and CI for Ruby 3.3/3.4/4.0
  on Rails 8.1 plus Rails `main`.
- `bin/rails g agent_harness:install`: detects the app's stack (Rails version, RSpec or
  Minitest, database, RuboCop/Standard, Brakeman, schema format) and writes `AGENTS.md` and
  `config/agent_harness.yml`. It doesn't create a `CLAUDE.md` (Claude Code 2.1.277+ reads
  `AGENTS.md` directly); an existing `CLAUDE.md` or `.claude/CLAUDE.md` gets an `@AGENTS.md`
  import. Re-runs only refresh the marked block and keep user content.
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
