local selected_projects = {}

local function get_dotnet_root()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "roslyn" })[1]
  return vim.fs.normalize(client and client.root_dir or vim.fn.getcwd())
end

local function is_ignored_path(path)
  local normalized = "/" .. path:gsub("\\", "/"):lower() .. "/"
  return normalized:find("/bin/", 1, true) or normalized:find("/obj/", 1, true) or normalized:find("/.git/", 1, true)
end

local function is_solution(path)
  local lower = path:lower()
  return lower:match("%.sln$") ~= nil or lower:match("%.slnx$") ~= nil
end

local function find_dotnet_targets(root)
  local targets = vim.fs.find(function(name, path)
    return not is_ignored_path(path) and (is_solution(name) or name:lower():match("%.csproj$"))
  end, {
    path = root,
    type = "file",
    limit = math.huge,
  })

  table.sort(targets, function(left, right)
    local left_is_solution = is_solution(left)
    local right_is_solution = is_solution(right)
    if left_is_solution ~= right_is_solution then
      return left_is_solution
    end
    return left:lower() < right:lower()
  end)
  return targets
end

local function select_solution_project(solution, callback)
  vim.system({ "dotnet", "sln", solution, "list" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(result.stderr ~= "" and result.stderr or "Could not read " .. solution, vim.log.levels.ERROR)
        callback()
        return
      end

      local projects = {}
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local relative_path = vim.trim(line):gsub('^"(.*)"$', "%1")
        if relative_path:lower():match("%.csproj$") then
          table.insert(projects, vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(solution), relative_path)))
        end
      end
      table.sort(projects)

      if #projects == 0 then
        vim.notify("The selected solution contains no C# projects", vim.log.levels.ERROR)
        callback()
        return
      end

      vim.ui.select(projects, {
        prompt = "Select project from " .. vim.fs.basename(solution),
        format_item = function(project)
          return vim.fs.relpath(vim.fs.dirname(solution), project) or project
        end,
      }, callback)
    end)
  end)
end

local function select_debug_project(root, callback)
  local targets = find_dotnet_targets(root)
  if #targets == 0 then
    vim.notify("No .sln, .slnx, or .csproj file found under " .. root, vim.log.levels.ERROR)
    callback()
    return
  end

  vim.ui.select(targets, {
    prompt = "Select .NET debug source",
    format_item = function(target)
      local kind = is_solution(target) and "Solution" or "Project"
      return ("[%s] %s"):format(kind, vim.fs.relpath(root, target) or target)
    end,
  }, function(target)
    if not target then
      callback()
    elseif is_solution(target) then
      select_solution_project(target, callback)
    else
      callback(target)
    end
  end)
end

local function remember_debug_project(root, project)
  if not project then
    return
  end
  selected_projects[root] = project
  vim.notify("Selected .NET debug project: " .. (vim.fs.relpath(root, project) or project))
end

local function choose_debug_project()
  local root = get_dotnet_root()
  select_debug_project(root, function(project)
    remember_debug_project(root, project)
  end)
end

local function build_debug_target(project, dap_run_co)
  local dap = require("dap")
  vim.notify("Building " .. vim.fs.basename(project) .. "...")
  vim.system({ "dotnet", "build", project, "--nologo" }, { text = true }, function(build)
    if build.code ~= 0 then
      vim.schedule(function()
        vim.notify(build.stderr ~= "" and build.stderr or build.stdout, vim.log.levels.ERROR)
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
      local target_path = target.stdout and vim.trim(target.stdout) or ""
      if target.code ~= 0 or target_path == "" then
        vim.schedule(function()
          vim.notify(
            target.stderr ~= "" and target.stderr or "Could not resolve the build output",
            vim.log.levels.ERROR
          )
        end)
        coroutine.resume(dap_run_co, dap.ABORT)
        return
      end
      coroutine.resume(dap_run_co, target_path)
    end)
  end)
end

local function resolve_debug_target()
  return coroutine.create(function(dap_run_co)
    local root = get_dotnet_root()
    local project = selected_projects[root]
    if project and vim.fn.filereadable(project) == 1 then
      build_debug_target(project, dap_run_co)
      return
    end

    select_debug_project(root, function(selected)
      if not selected then
        coroutine.resume(dap_run_co, require("dap").ABORT)
        return
      end
      remember_debug_project(root, selected)
      build_debug_target(selected, dap_run_co)
    end)
  end)
end

return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "netcoredbg" } },
  },
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
          require("dap").continue()
        end,
        desc = "Start/Continue Debug Build",
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
          netcoredbg =
            vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "netcoredbg", "netcoredbg", "netcoredbg.exe")
        else
          netcoredbg = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "netcoredbg")
        end
      end
      dap.adapters.coreclr = {
        type = "executable",
        command = netcoredbg,
        args = { "--interpreter=vscode" },
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
        },
      }
    end,
  },

  {
    "rcarriga/nvim-dap-ui",
    lazy = false,
    dependencies = {
      "nvim-neotest/nvim-nio",
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
      {
        "<leader>du",
        function()
          require("dapui").toggle({})
        end,
        desc = "DAP UI",
      },
      {
        "<leader>de",
        function()
          require("dapui").eval()
        end,
        desc = "Evaluate",
        mode = { "n", "x" },
      },
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
