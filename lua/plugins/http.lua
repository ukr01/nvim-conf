local function jq_executable()
  local executable = vim.fn.exepath("jq")
  if executable ~= "" and not executable:lower():match("%.cmd$") then
    return executable
  end
  if vim.fn.has("win32") == 1 then
    return vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "jq", "jq-windows-amd64.exe")
  end
  return vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "jq")
end

local function format_http_json()
  local buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local bodies = {}
  local request_start = 1

  local function collect_body(request_end)
    local content_type
    local body_start
    for line = request_start, request_end do
      local name, value = lines[line]:match("^%s*([^:]+):%s*(.-)%s*$")
      if name and name:lower() == "content-type" then
        content_type = value:lower()
      elseif lines[line]:match("^%s*$") and content_type then
        body_start = line + 1
        break
      end
    end

    if not body_start or not content_type:match("application/[%w.+-]*json") then
      return
    end

    local body_end = request_end
    while body_end >= body_start and lines[body_end]:match("^%s*$") do
      body_end = body_end - 1
    end
    if body_end >= body_start then
      table.insert(bodies, { first = body_start, last = body_end })
    end
  end

  for line = 1, #lines + 1 do
    if line > #lines or lines[line]:match("^%s*###") then
      collect_body(line - 1)
      request_start = line + 1
    end
  end

  if #bodies == 0 then
    vim.notify("No JSON request bodies found in this .http file", vim.log.levels.INFO)
    return
  end

  local jq = jq_executable()
  if vim.fn.executable(jq) ~= 1 then
    vim.notify("jq is unavailable. Install it with :Mason", vim.log.levels.ERROR)
    return
  end

  local replacements = {}
  for _, body in ipairs(bodies) do
    local input = table.concat(vim.list_slice(lines, body.first, body.last), "\n")
    local result = vim.system({ jq, "--indent", "2", "." }, { stdin = input, text = true }):wait()
    if result.code ~= 0 then
      vim.notify(
        ("Could not format JSON body at line %d:\n%s"):format(body.first, vim.trim(result.stderr or "")),
        vim.log.levels.ERROR
      )
      return
    end
    table.insert(replacements, {
      first = body.first,
      last = body.last,
      lines = vim.split(vim.trim(result.stdout), "\n", { plain = true }),
    })
  end

  for index = #replacements, 1, -1 do
    local replacement = replacements[index]
    vim.api.nvim_buf_set_lines(buffer, replacement.first - 1, replacement.last, false, replacement.lines)
  end
end

return {
  {
    "mistweaverco/kulala.nvim",
    keys = {
      {
        "<C-CR>",
        function()
          require("kulala").run()
        end,
        desc = "Send HTTP Request",
        ft = "http",
      },
      {
        "<leader>cf",
        format_http_json,
        desc = "Format HTTP Bodies",
        ft = "http",
      },
    },
    opts = {
      global_keymaps = false,
      treesitter = {
        enable = true,
      },
      ui = {
        display_mode = "split",
        split_direction = "vertical",
        show_icons = "on_request",
        syntax_hl = {
          ["@request_separator.kulala_http"] = "Title",
          ["@method.kulala_http"] = "Keyword",
          ["@url.kulala_http"] = "Underlined",
          ["@header.name.kulala_http"] = "Type",
          ["@variable.kulala_http"] = "Identifier",
          ["@operator.kulala_http"] = "Operator",
        },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "jq" },
    },
  },
}
