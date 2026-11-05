-- Roslyn-specific configuration and setup
-- This file centralizes all Roslyn LSP setup and monitoring

local M = {}

function M.setup()
  -- Setup Roslyn monitoring
  local roslyn_monitor = require("roslyn-monitor")
  
  roslyn_monitor.setup({
    debounce_ms = 100,
    enabled = true,
    show_notification = true,
  })
  
  -- Add user commands
  vim.api.nvim_create_user_command("RoslynMonitorToggle", function()
    require("roslyn-monitor").toggle()
  end, { desc = "Toggle Roslyn file monitoring" })
  
  vim.api.nvim_create_user_command("RoslynRefresh", function()
    local buf = vim.api.nvim_get_current_buf()
    require("roslyn-monitor").refresh_buffer(buf, false) -- Show notification
  end, { desc = "Force refresh Roslyn state for current buffer" })
  
  -- Refresh all Roslyn buffers in workspace
  vim.api.nvim_create_user_command("RoslynRefreshAll", function()
    local roslyn_monitor = require("roslyn-monitor")
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "cs" then
        roslyn_monitor.refresh_buffer(buf, true) -- Silent since we show our own notification
      end
    end
    vim.notify("Refreshed all Roslyn buffers", vim.log.levels.INFO)
  end, { desc = "Force refresh all Roslyn buffers in workspace" })
  
  -- Check Roslyn monitoring status
  vim.api.nvim_create_user_command("RoslynMonitorStatus", function()
    local status = require("roslyn-monitor").is_enabled() and "enabled" or "disabled"
    vim.notify("Roslyn monitoring: " .. status, vim.log.levels.INFO)
  end, { desc = "Check Roslyn monitoring status" })
end

return M
