local projects = require("dotnet-projects")
local M = {}

local function executable(name)
  local path = vim.fn.exepath(name)
  return path ~= "" and path or nil
end

local function terminal_command(project)
  local title = "dotnet run: " .. vim.fs.basename(project)

  if vim.fn.has("win32") == 1 then
    local found = vim.system({ "where.exe", "wt.exe" }, { text = true }):wait()
    if found.code == 0 then
      local shell = executable("pwsh.exe") or executable("powershell.exe") or "powershell.exe"
      local escaped_project = project:gsub("'", "''")
      return {
        vim.env.ComSpec or "cmd.exe",
        "/d",
        "/c",
        "start",
        "",
        "wt.exe",
        "new-tab",
        "--title",
        title,
        shell,
        "-NoLogo",
        "-NoExit",
        "-Command",
        ("& dotnet run --project '%s'"):format(escaped_project),
      }
    end
    return nil, "Windows Terminal (wt.exe) was not found"
  end

  local shell = executable(vim.env.SHELL or "") or executable("sh") or "/bin/sh"
  local run = {
    shell,
    "-lc",
    'dotnet run --project "$1"; status=$?; printf "\\nProcess exited with code %s. Press Enter to close...\\n" "$status"; read -r _; exit "$status"',
    "dotnet-run",
    project,
  }
  local terminals = {
    {
      names = { "wezterm" },
      args = function(command)
        return vim.list_extend({ "start", "--" }, command)
      end,
    },
    {
      names = { "kitty" },
      args = function(command)
        return vim.list_extend({ "--title", title }, command)
      end,
    },
    {
      names = { "alacritty" },
      args = function(command)
        return vim.list_extend({ "--title", title, "-e" }, command)
      end,
    },
    {
      names = { "foot", "footclient" },
      args = function(command)
        return vim.list_extend({ "--title=" .. title }, command)
      end,
    },
    {
      names = { "konsole" },
      args = function(command)
        return vim.list_extend({ "--new-tab", "-p", "tabtitle=" .. title, "-e" }, command)
      end,
    },
    {
      names = { "gnome-terminal" },
      args = function(command)
        return vim.list_extend({ "--title", title, "--" }, command)
      end,
    },
    {
      names = { "xterm" },
      args = function(command)
        return vim.list_extend({ "-T", title, "-e" }, command)
      end,
    },
  }

  for _, candidate in ipairs(terminals) do
    for _, name in ipairs(candidate.names) do
      local terminal = executable(name)
      if terminal then
        return vim.list_extend({ terminal }, candidate.args(run))
      end
    end
  end
  return nil, "No supported terminal found (wezterm, kitty, alacritty, foot, konsole, gnome-terminal, or xterm)"
end

local function launch(project)
  local command, error_message = terminal_command(project)
  if not command then
    vim.notify(error_message, vim.log.levels.ERROR)
    return
  end

  vim.system(command, {
    cwd = vim.fs.dirname(project),
    detach = true,
  }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify(("External terminal exited with code %d"):format(result.code), vim.log.levels.ERROR)
      end)
    end
  end)
  vim.notify("Running " .. vim.fs.basename(project) .. " in an external terminal")
end

function M.run()
  local root = projects.root()
  local project = projects.get_selected(root) or projects.nearest()
  if project then
    projects.remember(root, project)
    launch(project)
    return
  end

  projects.select_project({
    root = root,
    prompt = "Select .NET project to run",
  }, function(selected)
    if selected then
      projects.remember(root, selected)
      launch(selected)
    end
  end)
end

function M.command_for(project)
  return terminal_command(project)
end

return M
