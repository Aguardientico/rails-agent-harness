# Releasing

Releases are made by the maintainer, by hand. Automation (and agents) must not publish the
gem, push tags or create GitHub releases.

Use the steps below, not `bundle exec rake release`: the Rakefile loads `bundler/gem_tasks`,
whose `release` task tags, pushes and publishes in one go.

Prerequisites: a RubyGems account with MFA enabled, signed in with `gem signin` (the gem sets
`rubygems_mfa_required`, so every push asks for a one-time code).

1. Make sure `main` is green in CI (including the `demo`, `build` and `smoke` jobs).
2. Update `CHANGELOG.md`: move the entries under `## [Unreleased]` into a new
   `## [X.Y.Z] - YYYY-MM-DD` section (for the first release, replace `Unreleased` in
   `## [0.1.0] - Unreleased` with the date), and update the compare links at the bottom.
3. Bump `RailsAgentHarness::VERSION` in `lib/rails_agent_harness/version.rb` if needed.
4. Run everything locally:

   ```bash
   bundle install
   bundle exec rake               # specs + standardrb
   demo/run
   script/smoke_packaged_gem      # builds the .gem, installs it into a fresh Rails app, runs the generator and bin/agent-check
   ```

5. Build and inspect the gem from a clean checkout (`spec.files` globs `lib/**/*`, so stray
   untracked files under `lib/` would be packaged):

   ```bash
   git status --porcelain --ignored lib   # must print nothing
   gem build rails_agent_harness.gemspec
   tar -xOf rails_agent_harness-X.Y.Z.gem data.tar.gz | tar -tz   # lib/**, LICENSE.txt, README.md, CHANGELOG.md
   gem spec rails_agent_harness-X.Y.Z.gem metadata                 # homepage/changelog/bug tracker URIs, rubygems_mfa_required
   ```

6. Commit the CHANGELOG/version changes and push them to `main` (through a PR if `main` is
   protected). Build the gem you publish from that commit.
7. Publish (asks for the MFA code, or pass it with `--otp CODE`):

   ```bash
   gem push rails_agent_harness-X.Y.Z.gem
   ```

8. Tag the released commit and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

9. Create a GitHub release for `vX.Y.Z` with the CHANGELOG section as its notes.
10. Uncomment the gem version badge in `README.md` after the first release.
11. Check the published gem: `gem info rails_agent_harness --remote` shows `X.Y.Z`.
