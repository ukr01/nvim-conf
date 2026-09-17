return {
  {
    "folke/trouble.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        error_list = {
          desc = "Error List",
          source = "diagnostics",
          events = { "DiagnosticChanged", "BufEnter" },
          auto_open = true,
          auto_close = false,
          open_no_results = true,
          warn_no_results = false,
          auto_preview = false,
          focus = false,
          multiline = false,
          filter = function(items)
            if vim.g.dotnet_debugging then
              return {}
            end
            return vim.tbl_filter(function(item)
              return item.severity <= vim.diagnostic.severity.WARN
            end, items)
          end,
          sort = { "severity", "filename", "pos", "message" },
          format = "{severity_icon} {severity}  {code}  {message:md}  {filename} {pos}",
          win = {
            position = "bottom",
            size = 6,
            wo = {
              winfixheight = true,
              wrap = false,
            },
          },
        },
      },
    },
    config = function(_, opts)
      local trouble = require("trouble")
      trouble.setup(opts)
      vim.schedule(function()
        trouble.open({ mode = "error_list", focus = false })
      end)
    end,
    keys = {
      {
        "<leader>xe",
        "<cmd>Trouble error_list toggle<cr>",
        desc = "Error List",
      },
    },
  },
}
