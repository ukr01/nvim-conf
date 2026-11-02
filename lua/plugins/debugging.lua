local dotnet_projects = require("dotnet-projects")

local function get_dotnet_root() return dotnet_projects.root() end

local function remember_debug_project(root, project) if not project then return end

dotnet_projects.remember(root, project) vim.notify( "Selected .NET debug project: " .. (vim.fs.relpath(root, project) or project) ) end

local function choose_debug_project() local root = get_dotnet_root()

dotnet_projects.select_project({ root = root, prompt = "Select .NET debug source", }, function(project) remember_debug_project(root, project) end) end

local function build_debug_target(project, dap_run_co) local dap = require("dap")

vim.notify("Building " .. vim.fs.basename(project) .. "...")

vim.system({ "dotnet", "build", project, "--nologo", }, { text = true }, function(build) if build.code ~= 0 then vim.schedule(function() local message = build.stderr if not message or message == "" then message = build.stdout or "dotnet build failed" end

vim.notify(message, vim.log.levels.ERROR)
end)

coroutine.resume(dap_run_co, dap.ABORT)
return
end

vim.system({
  "dotnet",
  "msbuild",
  project,
  "--nologo",
  "-verbosity:quiet",
  "-getProperty:TargetPath",
}, { text = true }, function(target)
local target_path = target.stdout
and vim.trim(target.stdout)
or ""

if target.code ~= 0 or target_path == "" then
  vim.schedule(function()
  local message = target.stderr
  if not message or message == "" then
    message = "Could not resolve the build output"
    end

    vim.notify(message, vim.log.levels.ERROR)
    end)

  coroutine.resume(dap_run_co, dap.ABORT)
  return
  end

  coroutine.resume(dap_run_co, target_path)
  end)


end) end

local function resolve_debug_target() return coroutine.create(function(dap_run_co) local root = get_dotnet_root() local project = dotnet_projects.get_selected(root)

if project then
  build_debug_target(project, dap_run_co)
  return
  end

  dotnet_projects.select_project({
    root = root,
    prompt = "Select .NET debug source",
  }, function(selected)
  if not selected then
    coroutine.resume(dap_run_co, require("dap").ABORT)
    return
    end

    remember_debug_project(root, selected)
    build_debug_target(selected, dap_run_co)
    end)


  end) end

  return { { "mason-org/mason.nvim", opts = { ensure_installed = { "netcoredbg", }, }, },

  { "mfussenegger/nvim-dap", dependencies = { { "theHamsta/nvim-dap-virtual-text", opts = {}, }, },

  keys = {
    {
      "<F5>",
      function()
      require("dap").continue()
      end,
      desc = "Start / Continue Debugging",
    },
    {
      "<F6>",
      function()
      require("dap").terminate()
      end,
      desc = "Stop Debugging",
    },
    {
      "<F10>",
      function()
      require("dap").step_over()
      end,
      desc = "Step Over",
    },
    {
      "<F11>",
      function()
      require("dap").step_into()
      end,
      desc = "Step Into",
    },
    {
      "<F12>",
      function()
      require("dap").step_out()
      end,
      desc = "Step Out",
    },
    {
      "<leader>b",
      function()
      require("dap").toggle_breakpoint()
      end,
      desc = "Toggle Breakpoint",
    },
    {
      "<leader>dq",
      function()
      local dap = require("dap")
      dap.terminate()
      dap.clear_breakpoints()
      end,
      desc = "Terminate and Clear Breakpoints",
    },
    {
      "<leader>dS",
      choose_debug_project,
      desc = "Select .NET Debug Project",
    },
  },

  config = function()
  local dap = require("dap")

  local netcoredbg = vim.fn.exepath("netcoredbg")

  if netcoredbg == "" then
    if vim.fn.has("win32") == 1 then
      netcoredbg = vim.fs.joinpath(
        vim.fn.stdpath("data"),
                                   "mason",
                                   "packages",
                                   "netcoredbg",
                                   "netcoredbg",
                                   "netcoredbg.exe"
      )
      else
        netcoredbg = vim.fs.joinpath(
          vim.fn.stdpath("data"),
                                     "mason",
                                     "bin",
                                     "netcoredbg"
        )
        end
        end

        dap.adapters.coreclr = {
          type = "executable",
          command = netcoredbg,
          args = {
            "--interpreter=vscode",
          },
          options = {
            detached = false,
          },
        }

        dap.configurations.cs = {
          {
            type = "coreclr",
            name = "Build and launch .NET project",
            request = "launch",
            program = resolve_debug_target,
            cwd = "${workspaceFolder}",
            stopAtEntry = false,
            justMyCode = true,
          },
        }
        end,


  },

  { "rcarriga/nvim-dap-ui", lazy = false,

    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
    },

    opts = {
      controls = {
        enabled = false,
      },

      layouts = {
        {
          elements = {
            {
              id = "scopes",
              size = 0.50,
            },
            {
              id = "watches",
              size = 0.20,
            },
            {
              id = "breakpoints",
              size = 0.15,
            },
            {
              id = "stacks",
              size = 0.15,
            },
          },
          size = 45,
          position = "left",
        },
        {
          elements = {
            {
              id = "repl",
              size = 0.50,
            },
            {
              id = "console",
              size = 0.50,
            },
          },
          size = 10,
          position = "bottom",
        },
      },
    },

    keys = {
      {
        "<leader>du",
        function()
        require("dapui").toggle({})
        end,
        desc = "Toggle DAP UI",
      },
      {
        "<leader>de",
        function()
        require("dapui").eval()
        end,
        desc = "Evaluate Expression",
        mode = {
          "n",
          "x",
        },
      },
      {
        "<leader>dr",
        function()
        require("dap").repl.toggle()
        end,
        desc = "Toggle DAP REPL",
      },
    },

    config = function(_, opts)
    local dap = require("dap")
    local dapui = require("dapui")

    local explorer_cwd
    local error_list_was_open = false
    local toolbar_buffer
    local toolbar_window
    local debugging_ui_open = false

    local function update_toolbar(state)
    if not toolbar_buffer
      or not vim.api.nvim_buf_is_valid(toolbar_buffer)
      then
      return
      end

      local text = "  "
      .. state
      .. "  |  Continue F5  |  Stop F6"
      .. "  |  Over F10  |  Into F11"
      .. "  |  Out F12  |  "

      local width = math.max(
        1,
        math.min(#text, vim.o.columns - 4)
      )

      vim.bo[toolbar_buffer].modifiable = true

      vim.api.nvim_buf_set_lines(
        toolbar_buffer,
        0,
        -1,
        false,
        { text:sub(1, width) }
      )

      vim.bo[toolbar_buffer].modifiable = false

      if toolbar_window
        and vim.api.nvim_win_is_valid(toolbar_window)
        then
        vim.api.nvim_win_set_config(toolbar_window, {
          relative = "editor",
          row = 0,
          col = math.max(
            0,
            math.floor((vim.o.columns - width) / 2)
          ),
          width = width,
          height = 1,
        })
        end
        end

        local function open_toolbar()
        if toolbar_window
          and vim.api.nvim_win_is_valid(toolbar_window)
          then
          update_toolbar("RUNNING")
          return
          end

          local text = "  RUNNING  |  Continue F5  |  Stop F6"
          .. "  |  Over F10  |  Into F11  |  Out F12  "

          local width = math.max(
            1,
            math.min(#text, vim.o.columns - 4)
          )

          toolbar_buffer = vim.api.nvim_create_buf(false, true)

          vim.api.nvim_buf_set_lines(
            toolbar_buffer,
            0,
            -1,
            false,
            { text:sub(1, width) }
          )

          vim.bo[toolbar_buffer].modifiable = false

          toolbar_window = vim.api.nvim_open_win(
            toolbar_buffer,
            false,
            {
              relative = "editor",
              row = 0,
              col = math.max(
                0,
                math.floor((vim.o.columns - width) / 2)
              ),
              width = width,
              height = 1,
              style = "minimal",
              border = "rounded",
              focusable = false,
              zindex = 250,
            }
          )

          vim.wo[toolbar_window].winhighlight =
          "NormalFloat:DapUIPlayPause,FloatBorder:DapUIFloatBorder"

          update_toolbar("RUNNING")
          end

          local function close_toolbar()
          if toolbar_window
            and vim.api.nvim_win_is_valid(toolbar_window)
            then
            vim.api.nvim_win_close(toolbar_window, true)
            end

            if toolbar_buffer
              and vim.api.nvim_buf_is_valid(toolbar_buffer)
              then
              pcall(vim.api.nvim_buf_delete, toolbar_buffer, {
                force = true,
              })
              end

              toolbar_window = nil
              toolbar_buffer = nil
              end

              local function hide_explorer()
              local ok, snacks = pcall(require, "snacks")
              if not ok or not snacks.picker then
                return
                end

                local success, explorers = pcall(
                  snacks.picker.get,
                  { source = "explorer" }
                )

                if not success or not explorers then
                  return
                  end

                  explorer_cwd = explorers[1]
                  and explorers[1]:cwd()
                  or nil

                  for _, explorer in ipairs(explorers) do
                    explorer:close()
                    end
                    end

                    local function hide_error_list()
                    vim.g.dotnet_debugging = true

                    local loaded, trouble_view = pcall(require, "trouble.view")
                    if not loaded then
                      return
                      end

                      error_list_was_open = false

                      local ok, entries = pcall(
                        trouble_view.get,
                        { mode = "error_list" }
                      )

                      if not ok or not entries then
                        return
                        end

                        for _, entry in ipairs(entries) do
                          if entry.is_open then
                            error_list_was_open = true
                            entry.view:close()
                            end
                            end
                            end

                            local function finish_debugging()
                            if not debugging_ui_open then
                              close_toolbar()
                              vim.g.dotnet_debugging = false
                              return
                              end

                              debugging_ui_open = false

                              dapui.close({})
                              close_toolbar()

                              vim.g.dotnet_debugging = false

                              if explorer_cwd then
                                local cwd = explorer_cwd
                                explorer_cwd = nil

                                local ok, snacks = pcall(require, "snacks")
                                if ok and snacks.explorer then
                                  snacks.explorer({ cwd = cwd })
                                  end
                                  end

                                  if error_list_was_open then
                                    error_list_was_open = false

                                    local ok, trouble_view = pcall(
                                      require,
                                      "trouble.view"
                                    )

                                    if ok then
                                      local success, entries = pcall(
                                        trouble_view.get,
                                        { mode = "error_list" }
                                      )

                                      if success and entries then
                                        for _, entry in ipairs(entries) do
                                          if entry.view.opts.auto_open then
                                            entry.view:refresh()
                                            break
                                            end
                                            end
                                            end
                                            end
                                            end
                                            end

                                            dapui.setup(opts)

                                            dap.listeners.after.event_initialized["dapui_config"] =
                                            function()
                                            debugging_ui_open = true

                                            hide_explorer()
                                            hide_error_list()

                                            dapui.open({})
                                            open_toolbar()
                                            end

                                            dap.listeners.after.event_stopped["dapui_toolbar"] =
                                            function()
                                            update_toolbar("PAUSED")
                                            end

                                            dap.listeners.after.event_continued["dapui_toolbar"] =
                                            function()
                                            update_toolbar("RUNNING")
                                            end

                                            dap.listeners.before.event_terminated["dapui_config"] =
                                            function()
                                            finish_debugging()
                                            end

                                            dap.listeners.before.event_exited["dapui_config"] =
                                            function()
                                            finish_debugging()
                                            end

                                            dap.listeners.before.disconnect["dapui_config"] =
                                            function()
                                            finish_debugging()
                                            end
                                            end,


  }, }
