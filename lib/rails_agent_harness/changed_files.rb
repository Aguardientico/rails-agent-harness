# frozen_string_literal: true

require "open3"

module RailsAgentHarness
  # Files that differ from the merge base with the base branch: committed on this branch,
  # staged, unstaged and untracked. Paths are root-relative, and only files under the root
  # count (the app can be a subdirectory of a larger repository).
  class ChangedFiles
    # `git hash-object -t tree /dev/null`: diffing against it lists every file in a repo
    # that has no commits yet.
    EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    def initialize(root, base_branch:)
      @root = root.to_s
      @base_branch = base_branch
      git!("rev-parse", "--is-inside-work-tree") do
        raise Error, "#{@root} is not a git repository; bin/agent-check needs git to find changed files"
      end
    end

    # Existing files that were added, copied, modified or renamed since the merge base,
    # plus untracked files (respecting .gitignore).
    def list
      @list ||= existing(git_paths("diff", "--relative", "--name-only", "-z", "--diff-filter=ACMR", merge_base) + untracked)
    end

    # Files newly added since the merge base, plus untracked files.
    def added
      @added ||= existing(git_paths("diff", "--relative", "--name-only", "-z", "--diff-filter=A", merge_base) + untracked)
    end

    # `git merge-base HEAD <base>`, then against `origin/<base>`; HEAD when neither resolves
    # (e.g. on the base branch without a remote), or the empty tree before the first commit.
    def merge_base
      @merge_base ||= begin
        candidates = [@base_branch, "origin/#{@base_branch}"].filter_map do |base|
          git("merge-base", "HEAD", base)&.strip
        end
        candidates.find { |sha| !sha.empty? } || (git("rev-parse", "--verify", "--quiet", "HEAD") ? "HEAD" : EMPTY_TREE)
      end
    end

    private

    def untracked
      git_paths("ls-files", "--others", "--exclude-standard", "-z")
    end

    def existing(paths)
      paths.uniq.select { |path| File.file?(File.join(@root, path)) }.sort
    end

    def git_paths(*args)
      git!(*args) { |output| raise Error, "git #{args.join(" ")} failed: #{output.strip}" }.split("\0")
    end

    # Output of a successful git command, or nil.
    def git(*args)
      output, status = Open3.capture2e("git", "-c", "core.quotepath=false", *args, chdir: @root)
      status.success? ? output : nil
    end

    # Output of a successful git command; otherwise yields the output to the block.
    def git!(*args)
      output, status = Open3.capture2e("git", "-c", "core.quotepath=false", *args, chdir: @root)
      status.success? ? output : yield(output)
    rescue SystemCallError => e
      yield(e.message)
    end
  end
end
