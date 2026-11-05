---@type vim.lsp.Config
return {
  settings = {
    ["csharp|background_analysis"] = {
      dotnet_analyzer_diagnostics_scope = "fullSolution",
      dotnet_compiler_diagnostics_scope = "fullSolution",
    },
    ["csharp|file_watching"] = {
      enabled = true,
      -- More aggressive polling for external changes
      poll_interval_ms = 100,
    },
    ["csharp|diagnostics"] = {
      -- Ensure we get all diagnostics
      enable = true,
      severity = "Info",
    },
  },
  handlers = {
    -- Ensure we handle document changes properly
    ["textDocument/publishDiagnostics"] = function(err, method, params, client_id, bufnr, config_opts)
      -- Pass through to default handler
      vim.lsp.handlers["textDocument/publishDiagnostics"](err, method, params, client_id, bufnr, config_opts)
      -- Trigger a notification
      if params and params.uri then
        local buf = vim.uri_to_bufnr(params.uri)
        if buf and vim.api.nvim_buf_is_loaded(buf) then
          local filename = vim.api.nvim_buf_get_name(buf)
          pcall(function()
            require("roslyn-monitor").notify_sync(buf, "Diagnostics", { vim.fn.fnamemodify(filename, ":.") })
          end)
        end
      end
    end,
  },
  on_attach = function(client, bufnr)
    -- Ensure roslyn-monitor is loaded and setup
    pcall(function()
      require("roslyn-monitor")
    end)
    
    -- Setup buffer-local refresh on cursor hold (silent to avoid notifications)
    vim.api.nvim_create_autocmd("CursorHold", {
      buffer = bufnr,
      callback = function()
        require("roslyn-monitor").refresh_buffer(bufnr, true)
      end,
    })
    
    -- Initial notification to show monitoring is active
    vim.defer_fn(function()
      if vim.bo[bufnr].filetype == "cs" then
        local filename = vim.api.nvim_buf_get_name(bufnr)
        require("roslyn-monitor").notify_sync(bufnr, "Roslyn monitoring active", { vim.fn.fnamemodify(filename, ":.") })
      end
    end, 500)
  end,
  capabilities = {
    -- Ensure we have all the capabilities Roslyn needs
    textDocument = {
      documentSymbol = { dynamicRegistration = true },
      publishDiagnostics = { dynamicRegistration = true },
    },
  },
}
