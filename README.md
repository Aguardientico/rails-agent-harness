# rails-agent-harness

Rails Agent Harness (`rails_agent_harness`) makes AI coding agents (Claude Code, Codex, Cursor) safe and productive in Rails apps: an install generator that writes `AGENTS.md` / `CLAUDE.md` tuned to your app, a fast `bin/agent-check` wired into agent hooks, a guard against hand-written migrations and hand-edited `db/schema.rb`, and a Rails code-review skill.

> **Status: under construction.** Nothing is released yet; the API and generated files will change.

## Development

```bash
bundle install
bundle exec rspec
bundle exec standardrb

# Run against another Rails version (7.1, 7.2 or 8.0; default 8.0)
RAILS_VERSION=7.1 bundle update
RAILS_VERSION=7.1 bundle exec rspec
```

## License

MIT, see [LICENSE.txt](LICENSE.txt).
