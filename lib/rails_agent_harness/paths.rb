# frozen_string_literal: true

require "pathname"

module RailsAgentHarness
  module Paths
    module_function

    # `path` (absolute, or relative to `root`) as a root-relative path with forward slashes,
    # or nil when it is outside `root`. Symlinks are resolved for paths that exist, and
    # Windows backslashes (as Claude Code sends them there) are normalized.
    def relative(path, root)
      absolute = Pathname.new(File.expand_path(path.to_s.tr("\\", "/"), root.to_s))
      base = Pathname.new(root.to_s)
      absolute = Pathname.new(File.realpath(absolute)) if absolute.exist?
      base = Pathname.new(File.realpath(base)) if base.exist?
      relative = absolute.relative_path_from(base).to_s
      (relative == ".." || relative.start_with?("../")) ? nil : relative
    end
  end
end
