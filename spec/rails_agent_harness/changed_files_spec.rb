# frozen_string_literal: true

require "rails_agent_harness/changed_files"

RSpec.describe RailsAgentHarness::ChangedFiles do
  def changed(root, base: "main")
    described_class.new(root, base_branch: base)
  end

  it "lists committed, staged, unstaged and untracked changes since the merge base" do
    with_git_repo("app/a.rb" => "a\n", "app/b.rb" => "b\n", "app/c.rb" => "c\n") do |root|
      git(root, "checkout", "-q", "-b", "feature")
      touch(root, "app/committed.rb", "x\n")
      git(root, "add", "-A")
      git(root, "commit", "-q", "-m", "on branch")
      touch(root, "app/a.rb", "staged\n")
      git(root, "add", "app/a.rb")
      touch(root, "app/b.rb", "unstaged\n")
      touch(root, "app/untracked.rb", "new\n")

      expect(changed(root).list).to eq(%w[app/a.rb app/b.rb app/committed.rb app/untracked.rb])
    end
  end

  it "excludes deleted files and ignored files" do
    with_git_repo("app/a.rb" => "a\n", ".gitignore" => "tmp/\n") do |root|
      FileUtils.rm(File.join(root, "app/a.rb"))
      touch(root, "tmp/cache.rb", "x\n")

      expect(changed(root).list).to eq([])
    end
  end

  it "includes the new name of a renamed file" do
    with_git_repo("app/old.rb" => "same content\n" * 5) do |root|
      git(root, "mv", "app/old.rb", "app/new.rb")

      expect(changed(root).list).to eq(%w[app/new.rb])
    end
  end

  it "lists only the app's files, relative to it, when the app is a subdirectory of the repository" do
    with_git_repo("web/app/a.rb" => "a\n", "web/app/b.rb" => "b\n", "other/x.rb" => "x\n") do |repo|
      git(repo, "checkout", "-q", "-b", "feature")
      touch(repo, "web/app/a.rb", "changed\n")
      git(repo, "commit", "-q", "-am", "change a")
      touch(repo, "web/app/b.rb", "unstaged\n")
      touch(repo, "web/app/new.rb", "new\n")
      touch(repo, "other/x.rb", "changed\n")
      touch(repo, "other/new.rb", "new\n")

      files = changed(File.join(repo, "web"))
      expect(files.list).to eq(%w[app/a.rb app/b.rb app/new.rb])
      expect(files.added).to eq(%w[app/new.rb])
    end
  end

  it "lists only added files in #added" do
    with_git_repo("app/a.rb" => "a\n") do |root|
      git(root, "checkout", "-q", "-b", "feature")
      touch(root, "db/migrate/20261030000000_create_x.rb", "x\n")
      git(root, "add", "-A")
      git(root, "commit", "-q", "-m", "add migration")
      touch(root, "app/a.rb", "changed\n")
      touch(root, "app/untracked.rb", "new\n")

      expect(changed(root).added).to eq(%w[app/untracked.rb db/migrate/20261030000000_create_x.rb])
    end
  end

  describe "#merge_base" do
    it "uses the merge base with the base branch" do
      with_git_repo do |root|
        base = git(root, "rev-parse", "HEAD").strip
        git(root, "checkout", "-q", "-b", "feature")
        git(root, "commit", "-q", "--allow-empty", "-m", "on branch")

        expect(changed(root).merge_base).to eq(base)
      end
    end

    it "falls back to origin/<base>" do
      with_git_repo do |root|
        base = git(root, "rev-parse", "HEAD").strip
        git(root, "update-ref", "refs/remotes/origin/trunk", base)
        git(root, "checkout", "-q", "-b", "feature")
        git(root, "commit", "-q", "--allow-empty", "-m", "on branch")

        expect(changed(root, base: "trunk").merge_base).to eq(base)
      end
    end

    it "falls back to HEAD when the base branch doesn't resolve" do
      with_git_repo do |root|
        touch(root, "app/x.rb", "x\n")

        files = changed(root, base: "nope")
        expect(files.merge_base).to eq("HEAD")
        expect(files.base_found?).to be(false)
        expect(files.list).to eq(%w[app/x.rb])
        expect(changed(root).base_found?).to be(true)
      end
    end

    it "works in a repository without commits" do
      Dir.mktmpdir do |root|
        git(root, "init", "-q", "-b", "main")
        touch(root, "app/x.rb", "x\n")

        expect(changed(root).list).to eq(%w[app/x.rb])
      end
    end
  end

  it "raises a clear error outside a git repository" do
    Dir.mktmpdir do |root|
      expect { changed(root) }.to raise_error(RailsAgentHarness::Error, /not a git repository/)
    end
  end
end
