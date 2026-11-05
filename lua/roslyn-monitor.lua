-- Roslyn file change monitor for Neovim
-- Provides real-time updates and notifications when files change externally

local M = {}

-- Track the last notification time to prevent spam
local last_notify_time = 0
local NOTIFY_MIN_INTERVAL = 500 -- Minimum milliseconds between notifications

-- Track buffers that have pending updates
local pending_updates = {}

-- Track last sync time per buffer to show in notifications
local last_sync_times = {}

-- Configuration options
local config = {
  debounce_ms = 100, -- Debounce interval for rapid changes (ms)
  enabled = true, -- Enable/disable monitoring
  show_notification = true, -- Show text notification
  notification_timeout = 3000, -- How long to show the notification (ms)
}

--- Show a notification in the command area with timestamp and filename
---@param buf number Buffer number to show notification for
---@param message string? Optional custom message
---@param files table? List of filenames that were synced
function M.notify_sync(buf, message, files)
  if not config.enabled or not config.show_notification then
    return
  end

  local now = vim.loop.now()
  -- Rate limiting: don't show notifications more than once every NOTIFY_MIN_INTERVAL ms
  if now - last_notify_time < NOTIFY_MIN_INTERVAL then
    return
  end
  last_notify_time = now

  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Get filename
  local filename = vim.api.nvim_buf_get_name(buf)
  local basename = vim.fn.fnamemodify(filename, ":t")
  local relative_path = vim.fn.fnamemodify(filename, ":.")

  -- Format timestamp
  local timestamp = os.date("%H:%M:%S")

  -- Build the notification message
  local msg_parts = {}
  
  if message then
    table.insert(msg_parts, message)
  else
    table.insert(msg_parts, "Roslyn synced")
  end

  -- Add files if provided
  if files and #files > 0 then
    if #files == 1 then
      table.insert(msg_parts, files[1])
    else
      table.insert(msg_parts, table.concat(files, ", "))
    end
  else
    table.insert(msg_parts, relative_path ~= "" and relative_path or basename)
  end

  -- Add timestamp
  table.insert(msg_parts, "[")
  table.insert(msg_parts, timestamp)
  table.insert(msg_parts, "]")

  local display_msg = table.concat(msg_parts, " ")

  -- Use nvim_echo to show in command area (bottom of screen)
  -- This is less intrusive than vim.notify
  vim.api.nvim_echo({
    { "[Roslyn] ", "Title" },
    { display_msg, "Normal" },
  }, true, {})
end

--- Refresh LSP state for a buffer
---@param buf number Buffer number
---@param silent boolean? If true, don't show notification (default: false)
function M.refresh_buffer(buf, silent)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Only process C# buffers with Roslyn attached
  if vim.bo[buf].filetype ~= "cs" then
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = buf })
  local roslyn_client = nil
  for _, client in ipairs(clients) do
    if client.name == "roslyn" then
      roslyn_client = client
      break
    end
  end

  if not roslyn_client then
    return
  end

  -- Request document symbols to force re-sync
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
  }

  roslyn_client:request("textDocument/documentSymbol", params, function(err, result)
    if err then
      -- Try again with textDocument/didChange for full sync
      local change_params = {
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        contentChanges = { { text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") } },
      }
      pcall(function()
        roslyn_client:request("textDocument/didChange", change_params)
      end)
    end
    
    -- Record sync time
    last_sync_times[buf] = vim.loop.now()
    
    -- Show notification with timestamp (unless silent mode)
    if not silent then
      local filename = vim.api.nvim_buf_get_name(buf)
      M.notify_sync(buf, nil, { vim.fn.fnamemodify(filename, ":.") })
    end
  end, buf)

  -- Refresh diagnostics for this buffer
  vim.diagnostic.show(nil, buf, nil, { severity = { min = vim.diagnostic.severity.HINT } })
  
  -- Refresh code lenses
  pcall(vim.lsp.codelens.refresh, { bufnr = buf })
  
  -- Refresh semantic tokens
  pcall(vim.lsp.buf.document_highlight, buf)
end

--- Check if a file is part of the current Roslyn workspace
---@param filepath string Absolute file path
---@return boolean
function M.is_in_roslyn_workspace(filepath)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.name == "roslyn" and client.root_dir then
      local root = vim.fs.normalize(client.root_dir)
      local file = vim.fs.normalize(filepath)
      if file:find(root, 1, true) == 1 then
        return true
      end
    end
  end
  return false
end

--- Handle buffer enter event
---@param args table Autocmd args
function M.on_buf_enter(args)
  if not config.enabled then
    return
  end

  local buf = args.buf
  
  -- Only process C# buffers
  if vim.bo[buf].filetype ~= "cs" then
    return
  end

  -- Debounce: if we've already processed this buffer recently, skip
  local now = vim.loop.now()
  if pending_updates[buf] and now - pending_updates[buf] < config.debounce_ms then
    return
  end
  pending_updates[buf] = now

  -- Track which files are being synced
  local files_synced = {}
  
  -- Schedule the refresh to allow other autocmds to finish
  vim.schedule(function()
    local filename = vim.api.nvim_buf_get_name(buf)
    table.insert(files_synced, vim.fn.fnamemodify(filename, ":."))
    M.refresh_buffer(buf, false) -- Don't pass silent, so notification shows
    -- Show notification with all synced files
    if config.show_notification then
      M.notify_sync(buf, "Synced", files_synced)
    end
  end)
end

--- Handle focus gained event
---@param args table Autocmd args
function M.on_focus_gained(args)
  if not config.enabled then
    return
  end

  -- Track all synced files
  local files_synced = {}
  
  -- Refresh all visible C# buffers (silently to avoid multiple notifications)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "cs" then
      local filename = vim.api.nvim_buf_get_name(buf)
      table.insert(files_synced, vim.fn.fnamemodify(filename, ":."))
      M.refresh_buffer(buf, true) -- Silent refresh
    end
  end
  
  -- Show notification with all synced files
  if config.show_notification and #files_synced > 0 then
    local current_buf = vim.api.nvim_get_current_buf()
    M.notify_sync(current_buf, "Synced on focus", files_synced)
  end
end

--- Handle cursor hold event (optional: refresh on idle)
---@param args table Autocmd args
function M.on_cursor_hold(args)
  if not config.enabled then
    return
  end

  local buf = args.buf
  if vim.bo[buf].filetype == "cs" then
    local now = vim.loop.now()
    -- Only refresh if we haven't done so recently
    if not pending_updates[buf] or now - pending_updates[buf] > 2000 then
      pending_updates[buf] = now
      M.refresh_buffer(buf, true) -- Silent refresh for cursor hold
    end
  end
end

--- Check if a buffer is a C# buffer with Roslyn attached
---@param buf number Buffer number
---@return boolean
local function is_roslyn_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  if vim.bo[buf].filetype ~= "cs" then
    return false
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.name == "roslyn" then
      return true
    end
  end
  return false
end

--- Setup the monitoring system
---@param user_config table? Optional configuration overrides
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end

  -- Create autocmd group
  local group = vim.api.nvim_create_augroup("RoslynMonitor", { clear = true })

  -- Monitor buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = M.on_buf_enter,
    desc = "Refresh Roslyn state on buffer enter",
  })

  -- Monitor focus gained
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = M.on_focus_gained,
    desc = "Refresh Roslyn state when window regains focus",
  })

  -- Optional: monitor on cursor hold (for idle updates)
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = M.on_cursor_hold,
    desc = "Refresh Roslyn state on cursor hold",
  })

  -- Listen for LSP progress notifications (Roslyn might send these)
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LspProgress",
    callback = function(args)
      if args.data.client_id and vim.lsp.get_client_by_id(args.data.client_id) then
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client.name == "roslyn" then
          -- Check if this is a file update progress
          if args.data.token and args.data.token:find("file") then
            local files_synced = {}
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local buf = vim.api.nvim_win_get_buf(win)
              if is_roslyn_buffer(buf) then
                local filename = vim.api.nvim_buf_get_name(buf)
                table.insert(files_synced, vim.fn.fnamemodify(filename, ":."))
              end
            end
            if #files_synced > 0 then
              M.notify_sync(vim.api.nvim_get_current_buf(), "Roslyn processing", files_synced)
            end
          end
        end
      end
    end,
    desc = "Notify on Roslyn LSP progress",
  })

  -- Listen for Roslyn-specific file change events
  -- The roslyn.nvim plugin may emit these
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "RoslynFileChanged",
    callback = function(args)
      if not config.enabled then
        return
      end
      
      local filepath = args.data and args.data.filepath
      if filepath then
        local buf = vim.fn.bufadd(filepath)
        if buf and vim.api.nvim_buf_is_loaded(buf) and is_roslyn_buffer(buf) then
          M.refresh_buffer(buf, true) -- Silent since we'll show custom notification
          M.notify_sync(buf, "File changed", { vim.fn.fnamemodify(filepath, ":.") })
        end
      end
    end,
    desc = "Notify on Roslyn file change",
  })

  -- Listen for file write events (external changes)
  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    callback = function(args)
      if not config.enabled then
        return
      end
      
      local buf = args.buf
      if is_roslyn_buffer(buf) then
        local filename = vim.api.nvim_buf_get_name(buf)
        -- Small delay to let the file watcher process the change
        vim.defer_fn(function()
          M.refresh_buffer(buf, true) -- Silent since we'll show custom notification
          M.notify_sync(buf, "File saved", { vim.fn.fnamemodify(filename, ":.") })
        end, 50)
      end
    end,
    desc = "Notify on external file write",
  })

  -- Also listen for diagnostic updates
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DiagnosticChanged",
    callback = function(args)
      if not config.enabled then
        return
      end
      
      local buf = args.buf
      if buf and is_roslyn_buffer(buf) then
        -- Check if diagnostics changed
        local diagnostics = vim.diagnostic.get(buf)
        if #diagnostics > 0 then
          local filename = vim.api.nvim_buf_get_name(buf)
          M.notify_sync(buf, "Diagnostics updated", { vim.fn.fnamemodify(filename, ":.") })
        end
      end
    end,
    desc = "Notify on diagnostic changes",
  })

  M.enabled = true
end

--- Enable monitoring
function M.enable()
  config.enabled = true
  M.enabled = true
end

--- Disable monitoring
function M.disable()
  config.enabled = false
  M.enabled = false
end

--- Toggle monitoring
function M.toggle()
  if M.enabled then
    M.disable()
    vim.notify("Roslyn monitoring disabled", vim.log.levels.INFO)
  else
    M.enable()
    vim.notify("Roslyn monitoring enabled", vim.log.levels.INFO)
  end
end

--- Check if monitoring is enabled
function M.is_enabled()
  return config.enabled and M.enabled
end

return M
