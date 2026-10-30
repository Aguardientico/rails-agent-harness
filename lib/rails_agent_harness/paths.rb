# frozen_string_literal: true

require "pathname"

module RailsAgentHarness
  module Paths
    module_function

    # `path` (absolute, or relative to `root`) as a root-relative path with forward slashes,
    # or nil when it is outside `root`. Both are canonicalized through their nearest existing
    # ancestor, so a symlinked root matches a file that doesn't exist yet (a new migration)
    # whichever spelling either side uses. Windows backslashes (as Claude Code sends them
    # there) are normalized.
    def relative(path, root)
      absolute = canonical(Pathname.new(File.expand_path(path.to_s.tr("\\", "/"), root.to_s)))
      relative = absolute.relative_path_from(canonical(Pathname.new(File.expand_path(root.to_s)))).to_s
      (relative == ".." || relative.start_with?("../")) ? nil : relative
    end

    # `path` with its nearest existing ancestor resolved through File.realpath.
    def canonical(path)
      missing = []
      until path.exist? || path.root?
        missing.unshift(path.basename.to_s)
        path = path.parent
      end
      path = Pathname.new(File.realpath(path)) if path.exist?
      missing.empty? ? path : path.join(*missing)
    end
  end
end
