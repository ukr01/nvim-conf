return {
  {
    "GustavEikaas/easy-dotnet.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "folke/snacks.nvim", "mfussenegger/nvim-dap" },
    config = function()
      require("easy-dotnet").setup({
        debugger = {
          mem_cpu_usage = false,
        },
        diagnostics = {
          default_severity = "error",
          setqflist = false,
        },
      })
    end,
  },
}