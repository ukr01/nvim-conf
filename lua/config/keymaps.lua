-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>ch", function()
  require("overload-picker").hover()
end, { desc = "Method Documentation" })

vim.keymap.set("n", "<leader>cN", function()
  require("nuget-browser").open()
end, { desc = "NuGet Packages" })

vim.api.nvim_create_user_command("NuGet", function()
  require("nuget-browser").open()
end, { desc = "Manage NuGet packages" })

vim.keymap.set("n", "<leader>dR", function()
  require("dotnet-runner").run()
end, { desc = "Run .NET Project Externally" })

vim.api.nvim_create_user_command("DotnetRun", function()
  require("dotnet-runner").run()
end, { desc = "Run a .NET project in an external terminal" })
