return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {},
      },
    },
    keys = {
      {
        "<F5>",
        function()
          local dap = require("dap")
          if dap.session() then
            dap.continue()
          else
            vim.cmd("Dotnet debug profile Debug")
          end
        end,
        desc = "Start/Continue Debug Build",
      },
      { "<F10>", function() require("dap").step_over() end, desc = "Step Over" },
      { "<F11>", function() require("dap").step_into() end, desc = "Step Into" },
      { "<F12>", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>b", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      {
        "<leader>dq",
        function()
          local dap = require("dap")
          dap.terminate()
          dap.clear_breakpoints()
        end,
        desc = "Terminate and Clear Breakpoints",
      },
    },
  },

  {
    "rcarriga/nvim-dap-ui",
    lazy = false,
    dependencies = {
      "nvim-neotest/nvim-nio",
      "GustavEikaas/easy-dotnet.nvim",
    },
    opts = {
      controls = {
        enabled = false,
      },
      layouts = {
        {
          elements = {
            { id = "scopes", size = 0.4 },
            { id = "breakpoints", size = 0.3 },
            { id = "stacks", size = 0.3 },
          },
          size = 40,
          position = "left",
        },
      },
    },
    keys = {
      { "<leader>du", function() require("dapui").toggle({}) end, desc = "DAP UI" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Evaluate", mode = { "n", "x" } },
    },
    config = function(_, opts)
      local dap = require("dap")
      local dapui = require("dapui")
      local explorer_cwd
      local error_list_was_open = false
      local toolbar_buffer
      local toolbar_window

      local function open_toolbar()
        local text = "  Continue F5  |  Over F10  |  Into F11  |  Out F12  |  Stop <leader>dq  "
        local width = math.min(#text, vim.o.columns - 4)

        toolbar_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(toolbar_buffer, 0, -1, false, { text:sub(1, width) })
        vim.bo[toolbar_buffer].modifiable = false
        toolbar_window = vim.api.nvim_open_win(toolbar_buffer, false, {
          relative = "editor",
          row = 0,
          col = math.max(0, math.floor((vim.o.columns - width) / 2)),
          width = width,
          height = 1,
          style = "minimal",
          border = "rounded",
          focusable = false,
          zindex = 250,
        })
        vim.wo[toolbar_window].winhighlight = "NormalFloat:DapUIPlayPause,FloatBorder:DapUIFloatBorder"
      end

      local function close_toolbar()
        if toolbar_window and vim.api.nvim_win_is_valid(toolbar_window) then
          vim.api.nvim_win_close(toolbar_window, true)
        end
        toolbar_window = nil
        toolbar_buffer = nil
      end

      local function hide_explorer()
        local explorers = Snacks.picker.get({ source = "explorer" })
        explorer_cwd = explorers[1] and explorers[1]:cwd() or nil
        for _, explorer in ipairs(explorers) do
          explorer:close()
        end
      end

      local function hide_error_list()
        vim.g.dotnet_debugging = true
        local loaded, trouble_view = pcall(require, "trouble.view")
        if loaded then
          error_list_was_open = false
          for _, entry in ipairs(trouble_view.get({ mode = "error_list" })) do
            if entry.is_open then
              error_list_was_open = true
              entry.view:close()
            end
          end
        end
      end

      local function finish_debugging()
        dapui.close({})
        close_toolbar()
        vim.g.dotnet_debugging = false
        if explorer_cwd then
          local cwd = explorer_cwd
          explorer_cwd = nil
          Snacks.explorer({ cwd = cwd })
        end
        if error_list_was_open then
          error_list_was_open = false
          for _, entry in ipairs(require("trouble.view").get({ mode = "error_list" })) do
            if entry.view.opts.auto_open then
              entry.view:refresh()
              break
            end
          end
        end
      end

      dapui.setup(opts)
      dap.listeners.after.event_initialized["dapui_config"] = function()
        hide_explorer()
        hide_error_list()
        dapui.open({})
        open_toolbar()
      end
      dap.listeners.before.event_terminated["dapui_config"] = finish_debugging
      dap.listeners.before.event_exited["dapui_config"] = finish_debugging
    end,
  },
}