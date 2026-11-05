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
            
            -- Get the current severity filter (default: "all" = errors + warnings)
            local filter_type = vim.g.trouble_severity_filter or "all"
            
            -- Filter by severity level
            local filtered
            if filter_type == "error" then
              filtered = vim.tbl_filter(function(item)
                return item.severity == vim.diagnostic.severity.ERROR
              end, items)
            elseif filter_type == "warn" then
              filtered = vim.tbl_filter(function(item)
                return item.severity == vim.diagnostic.severity.WARN
              end, items)
            elseif filter_type == "info" then
              filtered = vim.tbl_filter(function(item)
                return item.severity == vim.diagnostic.severity.INFO
              end, items)
            else -- "all" - errors + warnings
              filtered = vim.tbl_filter(function(item)
                return item.severity <= vim.diagnostic.severity.WARN
              end, items)
            end
            
            -- Sort: current buffer first, then by filename, severity, position
            local current_buf = vim.api.nvim_get_current_buf()
            local current_filename = vim.api.nvim_buf_get_name(current_buf)
            
            table.sort(filtered, function(a, b)
              -- Normalize filenames for comparison (handle URI and path formats)
              local a_name = a.filename:gsub("^file://", "")
              local b_name = b.filename:gsub("^file://", "")
              
              local a_current = a_name == current_filename
              local b_current = b_name == current_filename
              
              -- If one is current and the other isn't, current comes first
              if a_current ~= b_current then
                return a_current
              end
              
              -- Both current or both not current: sort by filename, severity, position
              if a_name ~= b_name then
                return a_name < b_name
              end
              if a.severity ~= b.severity then
                return a.severity < b.severity
              end
              if a.lnum ~= b.lnum then
                return a.lnum < b.lnum
              end
              return a.message < b.message
            end)
            
            return filtered
          end,
          groups = {
            { "filename", format = "{file_icon} {basename:Title} {count}" },
          },
          sort = nil,
          format = "{pos} {severity_icon} {message:md} {code:Comment}",
          win = {
            position = "bottom",
            size = 8,
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
      
      -- Set default filter to show errors + warnings
      vim.g.trouble_severity_filter = "all"
      
      -- User commands for filtering (act as "buttons")
      vim.api.nvim_create_user_command("TroubleErrors", function()
        vim.g.trouble_severity_filter = "error"
        trouble.refresh()
        vim.notify("Showing Errors only", vim.log.levels.INFO)
      end, { desc = "Show only errors in Trouble list" })
      
      vim.api.nvim_create_user_command("TroubleWarnings", function()
        vim.g.trouble_severity_filter = "warn"
        trouble.refresh()
        vim.notify("Showing Warnings only", vim.log.levels.INFO)
      end, { desc = "Show only warnings in Trouble list" })
      
      vim.api.nvim_create_user_command("TroubleInfo", function()
        vim.g.trouble_severity_filter = "info"
        trouble.refresh()
        vim.notify("Showing Info only", vim.log.levels.INFO)
      end, { desc = "Show only info in Trouble list" })
      
      vim.api.nvim_create_user_command("TroubleAll", function()
        vim.g.trouble_severity_filter = "all"
        trouble.refresh()
        vim.notify("Showing All (Errors + Warnings)", vim.log.levels.INFO)
      end, { desc = "Show all diagnostics (Errors + Warnings)" })
      
      vim.schedule(function()
        trouble.open({ mode = "error_list", focus = false })
      end)
    end,
    keys = {
      {
        "<leader>xe",
        "<cmd>Trouble error_list toggle<cr>",
        desc = "Toggle Error List",
      },
      -- Visual Studio-style severity filtering
      {
        "<leader>xE",
        function()
          vim.g.trouble_severity_filter = "error"
          require("trouble").refresh()
        end,
        desc = "Show Errors Only",
      },
      {
        "<leader>xW",
        function()
          vim.g.trouble_severity_filter = "warn"
          require("trouble").refresh()
        end,
        desc = "Show Warnings Only",
      },
      {
        "<leader>xI",
        function()
          vim.g.trouble_severity_filter = "info"
          require("trouble").refresh()
        end,
        desc = "Show Info Only",
      },
      {
        "<leader>xA",
        function()
          vim.g.trouble_severity_filter = "all"
          require("trouble").refresh()
        end,
        desc = "Show All (Errors + Warnings)",
      },
    },
  },
}
