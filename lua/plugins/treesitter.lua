return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate", -- Opdaterer automatisk parsere, når pluginnet opdateres
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = { "c_sharp", "lua", "vim", "vimdoc", "markdown" },

      auto_install = true,

      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    })
  end,
}
