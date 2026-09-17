local M = {}
local selected_projects = {}

function M.root()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "roslyn" })[1]
  return vim.fs.normalize(client and client.root_dir or vim.fn.getcwd())
end

local function is_ignored_path(path)
  local normalized = "/" .. path:gsub("\\", "/"):lower() .. "/"
  return normalized:find("/bin/", 1, true) or normalized:find("/obj/", 1, true) or normalized:find("/.git/", 1, true)
end

function M.is_solution(path)
  local lower = path:lower()
  return lower:match("%.sln$") ~= nil or lower:match("%.slnx$") ~= nil
end

function M.find_targets(root)
  local targets = vim.fs.find(function(name, path)
    return not is_ignored_path(path) and (M.is_solution(name) or name:lower():match("%.csproj$"))
  end, {
    path = root,
    type = "file",
    limit = math.huge,
  })

  table.sort(targets, function(left, right)
    local left_is_solution = M.is_solution(left)
    local right_is_solution = M.is_solution(right)
    if left_is_solution ~= right_is_solution then
      return left_is_solution
    end
    return left:lower() < right:lower()
  end)
  return targets
end

function M.get_selected(root)
  local project = selected_projects[root]
  return project and vim.fn.filereadable(project) == 1 and project or nil
end

function M.remember(root, project)
  if project then
    selected_projects[root] = project
  end
end

function M.nearest()
  local current = vim.api.nvim_buf_get_name(0)
  if current:lower():match("%.csproj$") then
    return vim.fs.normalize(current)
  end
  local start = current ~= "" and vim.fs.dirname(current) or vim.fn.getcwd()
  return vim.fs.find(function(name)
    return name:lower():match("%.csproj$") ~= nil
  end, {
    path = start,
    upward = true,
    type = "file",
    limit = 1,
  })[1]
end

function M.projects_in_solution(solution, callback)
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
      callback(projects)
    end)
  end)
end

---@param opts? { root?: string, prompt?: string, solution_prompt?: string }
---@param callback fun(project?: string)
function M.select_project(opts, callback)
  opts = opts or {}
  local root = opts.root or M.root()
  local targets = M.find_targets(root)
  if #targets == 0 then
    vim.notify("No .sln, .slnx, or .csproj file found under " .. root, vim.log.levels.ERROR)
    callback()
    return
  end

  vim.ui.select(targets, {
    prompt = opts.prompt or "Select .NET project source",
    format_item = function(target)
      local kind = M.is_solution(target) and "Solution" or "Project"
      return ("[%s] %s"):format(kind, vim.fs.relpath(root, target) or target)
    end,
  }, function(target)
    if not target then
      callback()
    elseif not M.is_solution(target) then
      callback(target)
    else
      M.projects_in_solution(target, function(projects)
        if not projects then
          callback()
          return
        end
        vim.ui.select(projects, {
          prompt = opts.solution_prompt or ("Select project from " .. vim.fs.basename(target)),
          format_item = function(project)
            return vim.fs.relpath(vim.fs.dirname(target), project) or project
          end,
        }, callback)
      end)
    end
  end)
end

return M
