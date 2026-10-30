# rails-agent-harness

Rails Agent Harness (`rails_agent_harness`) makes AI coding agents (Claude Code, Codex, Cursor) safe and productive in Rails apps: an install generator that writes `AGENTS.md` / `CLAUDE.md` tuned to your app, a fast `bin/agent-check` wired into agent hooks, a guard against hand-written migrations and hand-edited `db/schema.rb`, and a Rails code-review skill.

> **Status: under construction.** Nothing is released yet; the API and generated files will change.

## Development

```bash
bundle install
bundle exec rspec
bundle exec standardrb

# Run against Rails main (the default is the latest 8.1.x)
RAILS_VERSION=main bundle update --all
RAILS_VERSION=main bundle exec rspec
```

Requires Ruby >= 3.3 and Rails >= 8.1. CI runs Ruby 3.3, 3.4 and 4.0 against Rails 8.1, plus an allowed-to-fail job against Rails `main`.

## License

MIT, see [LICENSE.txt](LICENSE.txt).
