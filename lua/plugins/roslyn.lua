return {
  "seblyng/roslyn.nvim",
  ---@module "roslyn.config"
  ---@type RoslynNvimConfig
  opts = {
    -- Roslyn's native watcher reliably handles external NuGet and project-file changes.
    filewatching = "roslyn",
  },
}
