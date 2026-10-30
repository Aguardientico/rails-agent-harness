# Release checklist: rails_agent_harness 0.1.0

The exact commands for publishing 0.1.0, following [RELEASING.md](../RELEASING.md), and the
results of a dry run made on 2026-10-30. The dry run did **not** publish, tag or bump anything.

`lib/rails_agent_harness/version.rb` already says `0.1.0`, so no version bump is needed.

## Commands

Run from a clean checkout of `main` after this PR and any other release PRs are merged, with
CI green (`lint`, `test`, `demo`, `build`, `smoke`). Replace `YYYY-MM-DD` with the release date.

```bash
# 0. Once: a RubyGems account with MFA enabled
gem signin

# 1. Up to date and clean
git checkout main && git pull origin main
git status --porcelain --ignored lib      # must print nothing (spec.files globs lib/**/*)

# 2. Set the CHANGELOG date (the compare links at the bottom are already right for 0.1.0)
sed -i 's/^## \[0.1.0\] - Unreleased$/## [0.1.0] - YYYY-MM-DD/' CHANGELOG.md   # macOS: sed -i ''
grep -n '^## \[' CHANGELOG.md             # [Unreleased] stays, empty, above [0.1.0] - YYYY-MM-DD

# 3. Everything passes locally
bundle install
bundle exec rake                          # rspec + standardrb
demo/run
script/smoke_packaged_gem                 # packaged gem in a fresh Rails 8.1 app

# 4. Commit the date (push to main, or merge it through a PR if main is protected)
git commit -am "Release 0.1.0"
git push origin main

# 5. Build from that commit and inspect
gem build rails_agent_harness.gemspec
tar -xOf rails_agent_harness-0.1.0.gem data.tar.gz | tar -tz
gem spec rails_agent_harness-0.1.0.gem metadata

# 6. Publish (prompts for the MFA one-time code; or add --otp 123456)
gem push rails_agent_harness-0.1.0.gem

# 7. Tag the released commit
git tag v0.1.0
git push origin v0.1.0

# 8. GitHub release v0.1.0 with the 0.1.0 CHANGELOG section as notes (web UI, or:)
gh release create v0.1.0 --title v0.1.0 --notes "$(sed -n '/^## \[0.1.0\]/,/^\[Unreleased\]:/p' CHANGELOG.md | sed '1d;$d')"

# 9. After publishing
gem info rails_agent_harness --remote     # shows 0.1.0
# Uncomment the Gem Version badge at the top of README.md, commit, push.
rm rails_agent_harness-0.1.0.gem
```

Don't use `bundle exec rake release`: `bundler/gem_tasks` would tag, push and publish in one
step, in a different order from the above.

## Dry run results (2026-10-30)

Environment: Ruby 3.3.6, Bundler 4.0.18, Rails 8.1.4, Linux. Commit `af59568` plus this PR.

| Step | Result |
|---|---|
| `bundle exec rake` | Pass: 301 examples, 0 failures; standardrb clean |
| `demo/run` | Pass: all steps exited as expected |
| `gem build rails_agent_harness.gemspec` | Pass: built `rails_agent_harness-0.1.0.gem` (34 KB), no warnings |
| File list | 37 files: `lib/**` (code, the install generator, `USAGE` and all 15 templates), `LICENSE.txt`, `README.md`, `CHANGELOG.md`. No specs, `spec/dummy`, `demo/`, `docs/`, `script/` or CI files |
| Gemspec metadata | `homepage`, `source_code_uri` = `https://github.com/Aguardientico/rails-agent-harness`; `changelog_uri` = `.../blob/main/CHANGELOG.md`; `bug_tracker_uri` = `.../issues`; `rubygems_mfa_required` = `"true"`; license MIT; `required_ruby_version >= 3.3`; one runtime dependency, `railties >= 8.1, < 9` |
| Gem name | `rails_agent_harness` is not taken on rubygems.org (API returned 404) |
| Packaged gem in a fresh app | Pass, see below |

### The packaged gem in a fresh Rails 8.1 app

Done by hand and then with `script/smoke_packaged_gem`, which repeats it:

1. `gem install --local rails_agent_harness-0.1.0.gem`, then `rails _8.1.4_ new app` (defaults:
   Minitest, SQLite, RuboCop omakase, Brakeman), `bundle add rails_agent_harness --version 0.1.0
   --group development --skip-install` and `bundle install --prefer-local`. Bundler loaded the gem
   from the installed gem directory (`.../gems/rails_agent_harness-0.1.0`), not from the checkout.
2. `bin/rails g agent_harness:install`: exit 0. Wrote `config/agent_harness.yml`, `AGENTS.md`,
   `CLAUDE.md`, `bin/agent-check` (executable), `.claude/settings.json` and
   `.claude/skills/rails-review/SKILL.md`. Detected Rails 8.1.4, minitest, sqlite, RuboCop yes,
   Standard no, Brakeman yes, schema format ruby.
3. `bin/agent-check --version`: `agent-check 0.1.0`.
4. `bin/agent-check` with no changes: `PASS` (every check skipped, nothing changed), exit 0.
5. `bin/rails g model Post title:string && bin/rails db:migrate`, then `bin/agent-check`:
   `PASS (migrations, rubocop, brakeman, tests) - 5 files checked`, exit 0.
6. A hand-written migration plus `where("title = '#{t}'")` in the model, then `bin/agent-check`:
   `FAIL`, exit 1. migrations reported the non-generated file name and the stale `db/schema.rb`,
   brakeman reported `SQL Injection` at `app/models/post.rb:3`, and tests failed (pending migration).
7. `bin/agent-check hook pre-tool-use` with a `Write` to `db/migrate/...`: blocked with the
   "Do not hand-write migration files" message, exit 2.

`script/smoke_packaged_gem` runs steps 1 to 4, a hand-written migration (`--only migrations`,
exit 1) and step 7. It passed in about 20 s. CI now runs it as the `smoke` job.

## Gaps found and fixed in this PR

- **No test of the packaged gem.** CI built the gem and rejected unexpected files, but nothing
  installed the `.gem` into an app. Added `script/smoke_packaged_gem` and a `smoke` CI job (Ruby
  3.3, Rails 8.1). The `build` job now also fails if the generator, its templates, `LICENSE.txt`,
  `README.md` or `CHANGELOG.md` go missing from the gem.
- **RELEASING.md:** added the `gem signin`/MFA prerequisite and `--otp`, the smoke test in
  step 4, the clean-tree check before `gem build` (`spec.files` globs the filesystem, so
  untracked files under `lib/` would be packaged), `gem spec ... metadata`, a warning not to use
  `rake release`, a note on protected `main`, and a post-publish check.

Checked and already right: gemspec metadata, `spec.files`, and the CI matrix. Ruby 3.3, 3.4 and
4.0 on Rails 8.1, plus Rails `main` allowed to fail, matches `required_ruby_version >= 3.3`,
`railties >= 8.1, < 9` and the README's Compatibility section.

## Notes and follow-ups (not blocking 0.1.0)

- When a test run crashes before reporting failures (e.g. pending migrations), the `[tests]`
  section shows the last `max_output_lines` lines of output, which is backtrace. The actual error
  (`ActiveRecord::PendingMigrationError`) is above it and gets cut off. Showing the first error
  line as well would help agents.
- The CHANGELOG is left as `## [0.1.0] - Unreleased` on purpose. The date is set at release time
  (step 2 above).
- Another open PR changes the install generator so `CLAUDE.md` is only touched when the app
  already has one. After it merges, step 2 of the fresh-app run will not create `CLAUDE.md`. The
  smoke script does not check for `CLAUDE.md`, so it works with either behavior.
