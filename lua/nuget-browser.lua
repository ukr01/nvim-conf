local projects = require("dotnet-projects")
local M = {}

local function decode_json(result, operation, callback)
  if result.code ~= 0 then
    vim.notify(
      ("%s failed:\n%s"):format(operation, vim.trim(result.stderr ~= "" and result.stderr or result.stdout)),
      vim.log.levels.ERROR
    )
    callback()
    return
  end

  local ok, decoded = pcall(vim.json.decode, result.stdout)
  if not ok then
    vim.notify(("%s returned invalid JSON:\n%s"):format(operation, decoded), vim.log.levels.ERROR)
    callback()
    return
  end
  callback(decoded)
end

local function run_json(command, cwd, operation, callback)
  vim.system(command, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      decode_json(result, operation, callback)
    end)
  end)
end

local function version_is_newer(left, right)
  local left_version = vim.version.parse(left)
  local right_version = vim.version.parse(right)
  if left_version and right_version then
    return vim.version.lt(right_version, left_version)
  end
  return left > right
end

local function package_results(response)
  local packages = {}
  local by_id = {}
  for _, source in ipairs(response.searchResult or {}) do
    for _, package in ipairs(source.packages or {}) do
      local key = package.id and package.id:lower()
      local current = key and by_id[key]
      local version = package.version or package.latestVersion
      if key and version and (not current or version_is_newer(version, current.version)) then
        local item = {
          id = package.id,
          version = version,
          source = source.sourceName,
        }
        by_id[key] = item
      end
    end
  end
  for _, package in pairs(by_id) do
    table.insert(packages, package)
  end
  table.sort(packages, function(left, right)
    return left.id:lower() < right.id:lower()
  end)
  return packages
end

local function version_results(response)
  local versions = {}
  local seen = {}
  for _, source in ipairs(response.searchResult or {}) do
    for _, package in ipairs(source.packages or {}) do
      local version = package.version or package.latestVersion
      if version and not seen[version] then
        seen[version] = true
        table.insert(versions, {
          version = version,
          source = source.sourceName,
        })
      end
    end
  end
  table.sort(versions, function(left, right)
    return version_is_newer(left.version, right.version)
  end)
  return versions
end

local function installed_results(response)
  local installed = {}
  local seen = {}
  for _, project in ipairs(response.projects or {}) do
    for _, framework in ipairs(project.frameworks or {}) do
      for _, package in ipairs(framework.topLevelPackages or {}) do
        local key = package.id:lower()
        if not seen[key] then
          seen[key] = true
          table.insert(installed, {
            id = package.id,
            requested = package.requestedVersion,
            resolved = package.resolvedVersion,
          })
        end
      end
    end
  end
  table.sort(installed, function(left, right)
    return left.id:lower() < right.id:lower()
  end)
  return installed
end

local function refresh_project(project)
  local buffer = vim.fn.bufnr(project)
  if buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) then
    vim.api.nvim_buf_call(buffer, function()
      vim.cmd.checktime()
    end)
  end
end

local function mutate_project(project, command, success)
  vim.notify(success .. "...")
  vim.system(command, { cwd = vim.fs.dirname(project), text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr ~= "" and result.stderr or result.stdout), vim.log.levels.ERROR)
        return
      end
      refresh_project(project)
      vim.notify(success, vim.log.levels.INFO)
    end)
  end)
end

local function select_version(project, package_id, current_version, callback)
  run_json(
    {
      "dotnet",
      "package",
      "search",
      package_id,
      "--exact-match",
      "--format",
      "json",
      "--verbosity",
      "quiet",
    },
    vim.fs.dirname(project),
    "NuGet version search",
    function(response)
      if not response then
        return
      end
      local versions = version_results(response)
      if #versions == 0 then
        vim.notify("No versions found for " .. package_id, vim.log.levels.WARN)
        return
      end
      vim.ui.select(versions, {
        prompt = ("Select %s version"):format(package_id),
        format_item = function(item)
          local current = item.version == current_version and " (current)" or ""
          return ("%s%s  [%s]"):format(item.version, current, item.source)
        end,
      }, function(item)
        callback(item and item.version or nil)
      end)
    end
  )
end

function M.search(project, callback)
  vim.ui.input({ prompt = "Search NuGet packages: " }, function(query)
    if query == nil then
      return
    end
    query = vim.trim(query)
    if query == "" then
      vim.notify("Enter a package name or search term", vim.log.levels.WARN)
      return
    end

    run_json(
      {
        "dotnet",
        "package",
        "search",
        query,
        "--take",
        "30",
        "--format",
        "json",
        "--verbosity",
        "quiet",
      },
      vim.fs.dirname(project),
      "NuGet package search",
      function(response)
        if not response then
          return
        end
        local packages = package_results(response)
        if #packages == 0 then
          vim.notify("No NuGet packages matched " .. query, vim.log.levels.INFO)
          return
        end
        vim.ui.select(packages, {
          prompt = "Select NuGet package",
          format_item = function(package)
            return ("%s  %s  [%s]"):format(package.id, package.version, package.source)
          end,
        }, callback)
      end
    )
  end)
end

function M.list_installed(project, callback)
  run_json(
    {
      "dotnet",
      "list",
      project,
      "package",
      "--format",
      "json",
      "--output-version",
      "1",
    },
    vim.fs.dirname(project),
    "Reading installed packages",
    function(response)
      if not response then
        return
      end
      callback(installed_results(response))
    end
  )
end

local function add_package(project)
  M.search(project, function(package)
    if not package then
      return
    end
    select_version(project, package.id, nil, function(version)
      if version then
        mutate_project(
          project,
          { "dotnet", "add", project, "package", package.id, "--version", version },
          ("Added %s %s"):format(package.id, version)
        )
      end
    end)
  end)
end

local function update_package(project)
  M.list_installed(project, function(installed)
    if #installed == 0 then
      vim.notify("The selected project has no top-level NuGet packages", vim.log.levels.INFO)
      return
    end
    vim.ui.select(installed, {
      prompt = "Select package to update",
      format_item = function(package)
        return ("%s  %s"):format(package.id, package.resolved or package.requested)
      end,
    }, function(package)
      if not package then
        return
      end
      select_version(project, package.id, package.resolved, function(version)
        if version and version ~= package.resolved then
          mutate_project(
            project,
            { "dotnet", "add", project, "package", package.id, "--version", version },
            ("Updated %s to %s"):format(package.id, version)
          )
        elseif version then
          vim.notify(package.id .. " is already using " .. version, vim.log.levels.INFO)
        end
      end)
    end)
  end)
end

local function remove_package(project)
  M.list_installed(project, function(installed)
    if #installed == 0 then
      vim.notify("The selected project has no top-level NuGet packages", vim.log.levels.INFO)
      return
    end
    vim.ui.select(installed, {
      prompt = "Select package to remove",
      format_item = function(package)
        return ("%s  %s"):format(package.id, package.resolved or package.requested)
      end,
    }, function(package)
      if package then
        mutate_project(project, { "dotnet", "remove", project, "package", package.id }, "Removed " .. package.id)
      end
    end)
  end)
end

function M.open()
  projects.select_project({
    prompt = "Select .NET project for NuGet",
  }, function(project)
    if not project then
      return
    end
    vim.ui.select({
      { name = "Add", run = add_package },
      { name = "Update", run = update_package },
      { name = "Remove", run = remove_package },
    }, {
      prompt = "NuGet action for " .. vim.fs.basename(project),
      format_item = function(action)
        return action.name
      end,
    }, function(action)
      if action then
        action.run(project)
      end
    end)
  end)
end

return M
