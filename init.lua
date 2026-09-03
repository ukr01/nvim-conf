-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("lualine").setup({
  sections = {
    lualine_c = {
      {
        "filename",
        symbols = {
          modified = " ●",  -- dirty buffer
          readonly = " 🔒",
          unnamed = "[No Name]",
        },
      },
    },
  },
})

vim.api.nvim_set_hl(0, "LspCodeLens", { fg = "#717171", italic = true })