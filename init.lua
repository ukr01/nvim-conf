-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("lualine").setup({
  sections = {
    lualine_c = {
      {
        "filename",
        symbols = {
          modified = " ●", -- dirty buffer
          readonly = " 🔒",
          unnamed = "[No Name]",
        },
      },
    },
  },
})

require("catppuccin").setup({
  flavour = "mocha", -- Vælg mellem: latte, frappe, macchiato, mocha
  transparent_background = false,
  integrations = {
    cmp = true,
    gitsigns = true,
    nvimtree = true,
    treesitter = true,
  },
})

-- Aktivér selve farvetemaet i Neovim
vim.cmd.colorscheme("catppuccin-nvim")

vim.api.nvim_set_hl(0, "LspCodeLens", { fg = "#717171", italic = true })

vim.opt.clipboard = "unnamedplus"
