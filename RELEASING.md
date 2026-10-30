# Releasing

Releases are made by the maintainer, by hand. Automation (and agents) must not publish the
gem, push tags or create GitHub releases.

1. Make sure `main` is green in CI (including the `demo` and `build` jobs).
2. Update `CHANGELOG.md`: move the entries under `## [Unreleased]` into a new
   `## [X.Y.Z] - YYYY-MM-DD` section (for the first release, replace `Unreleased` in
   `## [0.1.0] - Unreleased` with the date), and update the compare links at the bottom.
3. Bump `RailsAgentHarness::VERSION` in `lib/rails_agent_harness/version.rb` if needed.
4. Run everything locally:

   ```bash
   bundle install
   bundle exec rake          # specs + standardrb
   demo/run
   ```

5. Build and inspect the gem:

   ```bash
   gem build rails_agent_harness.gemspec
   tar -xOf rails_agent_harness-X.Y.Z.gem data.tar.gz | tar -tz   # lib/**, LICENSE.txt, README.md, CHANGELOG.md
   ```

6. Commit the CHANGELOG/version changes and push them to `main`.
7. Publish (RubyGems requires MFA for this gem, `rubygems_mfa_required`):

   ```bash
   gem push rails_agent_harness-X.Y.Z.gem
   ```

8. Tag and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

9. Create a GitHub release for `vX.Y.Z` with the CHANGELOG section as its notes.
10. Uncomment the gem version badge in `README.md` after the first release.
