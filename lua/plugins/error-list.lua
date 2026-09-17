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
          follow = false,
          indent_guides = false,
          multiline = false,
          filter = function(items)
            if vim.g.dotnet_debugging then
              return {}
            end
            return vim.tbl_filter(function(item)
              return item.severity <= vim.diagnostic.severity.WARN
            end, items)
          end,
          groups = {
            { "filename", format = "{file_icon} {basename:Title} {count}" },
          },
          sort = { "filename", "severity", "pos", "message" },
          format = "{severity_icon} {message:md} {code:Comment} {pos}",
          win = {
            position = "bottom",
            size = 6,
            wo = {
              cursorline = true,
              foldcolumn = "0",
              list = false,
              number = false,
              relativenumber = false,
              signcolumn = "no",
              spell = false,
              winbar = "  Problems",
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
