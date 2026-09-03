local function set_diagnostic_highlights()
  vim.api.nvim_set_hl(0, "DiagnosticUnderlineError", { undercurl = true, sp = "#f44747" })
  vim.api.nvim_set_hl(0, "DiagnosticUnderlineWarn", { undercurl = true, sp = "#007acc" })
  vim.api.nvim_set_hl(0, "DiagnosticUnderlineInfo", { undercurl = true, sp = "#4fc1ff" })
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      set_diagnostic_highlights()
      vim.opt.updatetime = 500

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("visual_studio_diagnostic_highlights", { clear = true }),
        callback = set_diagnostic_highlights,
      })

      vim.api.nvim_create_autocmd("CursorHold", {
        group = vim.api.nvim_create_augroup("diagnostic_line_peek", { clear = true }),
        callback = function()
          vim.diagnostic.open_float(nil, {
            scope = "line",
            focusable = false,
            header = "",
            source = "if_many",
            close_events = { "CursorMoved", "CursorMovedI", "BufHidden", "InsertCharPre" },
          })
        end,
      })
    end,
    opts = {
      diagnostics = {
        virtual_text = false,
        signs = { severity = { min = vim.diagnostic.severity.WARN } },
        underline = { severity = { min = vim.diagnostic.severity.WARN } },
        float = { severity = { min = vim.diagnostic.severity.INFO } },
      },
    },
  },
}