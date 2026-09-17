local M = {}
local highlight_namespace = vim.api.nvim_create_namespace("roslyn_overload_highlights")

local state = {
  signatures = {},
  selected = 1,
  buffer = nil,
  window = nil,
  timer = nil,
  request_id = 0,
}

local function close()
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
  end
  state.signatures = {}
  state.selected = 1
  state.buffer = nil
  state.window = nil
  state.request_id = state.request_id + 1
end

local function clean_text(text)
  if type(text) == "table" then
    text = text.value
  end
  if type(text) ~= "string" then
    return ""
  end
  return text:gsub("\r", ""):gsub("`+", ""):gsub("\\([%p])", "%1")
end

local function documentation_lines(signature)
  local text = clean_text(signature.documentation)
  local active_parameter = signature.activeParameter
  local parameter = active_parameter and signature.parameters and signature.parameters[active_parameter + 1]
  local parameter_text = parameter and clean_text(parameter.documentation) or ""
  if parameter_text ~= "" and not text:find(parameter_text, 1, true) then
    text = text == "" and parameter_text or (text .. "\n\n" .. parameter_text)
  end

  local lines = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true, trimempty = true })) do
    line = vim.trim(line)
    if line ~= "" or (#lines > 0 and lines[#lines] ~= "") then
      table.insert(lines, line)
    end
  end
  return lines
end

local function split_parameters(text)
  local parameters = {}
  local start = 1
  local depths = { round = 0, square = 0, curly = 0, angle = 0 }
  local quote
  local escaped = false

  for index = 1, #text do
    local char = text:sub(index, index)
    if quote then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif char == quote then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "(" then
      depths.round = depths.round + 1
    elseif char == ")" then
      depths.round = math.max(0, depths.round - 1)
    elseif char == "[" then
      depths.square = depths.square + 1
    elseif char == "]" then
      depths.square = math.max(0, depths.square - 1)
    elseif char == "{" then
      depths.curly = depths.curly + 1
    elseif char == "}" then
      depths.curly = math.max(0, depths.curly - 1)
    elseif char == "<" then
      depths.angle = depths.angle + 1
    elseif char == ">" then
      depths.angle = math.max(0, depths.angle - 1)
    elseif char == "," and depths.round == 0 and depths.square == 0 and depths.curly == 0 and depths.angle == 0 then
      table.insert(parameters, vim.trim(text:sub(start, index - 1)))
      start = index + 1
    end
  end

  local last = vim.trim(text:sub(start))
  if last ~= "" then
    table.insert(parameters, last)
  end
  return parameters
end

local function format_signature(signature)
  local label = signature.label:gsub("[\r\n]", " ")
  if vim.fn.strdisplaywidth(label) <= 88 then
    return { label }
  end

  local close = label:match(".*()%)")
  if not close then
    return { label }
  end

  local depth = 0
  local open
  for index = close, 1, -1 do
    local char = label:sub(index, index)
    if char == ")" then
      depth = depth + 1
    elseif char == "(" then
      depth = depth - 1
      if depth == 0 then
        open = index
        break
      end
    end
  end
  if not open then
    return { label }
  end

  local parameters = split_parameters(label:sub(open + 1, close - 1))
  if #parameters < 2 then
    return { label }
  end

  local lines = { label:sub(1, open) }
  local active_range
  for index, parameter in ipairs(parameters) do
    local suffix = index < #parameters and "," or ""
    table.insert(lines, "  " .. parameter .. suffix)
    if signature.activeParameter == index - 1 then
      active_range = {
        line = #lines - 1,
        start_col = 2,
        end_col = 2 + #parameter,
      }
    end
  end
  table.insert(lines, label:sub(close))
  return lines, active_range
end

local function format_hover_lines(lines)
  local formatted = {}
  local in_code_block = false

  for _, line in ipairs(lines) do
    if line:match("^%s*`+[%w_+-]*%s*$") then
      in_code_block = not in_code_block
      table.insert(formatted, line)
    elseif in_code_block then
      vim.list_extend(formatted, format_signature({ label = line }))
    else
      table.insert(formatted, line)
    end
  end
  return formatted
end

local function render()
  if #state.signatures == 0 then
    close()
    return
  end

  local signature = state.signatures[state.selected]
  local label = signature.label:gsub("[\r\n]", " ")
  local lines, active_range = format_signature(signature)
  local signature_line_count = #lines
  local docs = documentation_lines(signature)
  if #docs > 0 then
    table.insert(lines, "")
    vim.list_extend(lines, docs)
  end

  local width = 32
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width + 2, math.max(32, vim.o.columns - 4), 88)
  local height = math.min(math.max(#lines, 1), 18)

  if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
    state.buffer = vim.api.nvim_create_buf(false, true)
  end
  vim.bo[state.buffer].filetype = "markdown"
  vim.bo[state.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
  vim.bo[state.buffer].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buffer, highlight_namespace, 0, -1)
  for line = 0, signature_line_count - 1 do
    vim.api.nvim_buf_set_extmark(state.buffer, highlight_namespace, line, 0, {
      end_col = #lines[line + 1],
      hl_group = "BlinkCmpLabel",
    })
  end
  local active_parameter = signature.activeParameter
  local parameter = active_parameter and signature.parameters and signature.parameters[active_parameter + 1]
  if active_range then
    vim.api.nvim_buf_set_extmark(state.buffer, highlight_namespace, active_range.line, active_range.start_col, {
      end_col = active_range.end_col,
      hl_group = "LspSignatureActiveParameter",
      priority = 250,
    })
  elseif parameter and type(parameter.label) == "table" then
    vim.api.nvim_buf_set_extmark(state.buffer, highlight_namespace, 0, parameter.label[1], {
      end_col = parameter.label[2],
      hl_group = "LspSignatureActiveParameter",
      priority = 250,
    })
  elseif parameter and type(parameter.label) == "string" then
    local start_col, end_col = label:find(parameter.label, 1, true)
    if start_col then
      vim.api.nvim_buf_set_extmark(state.buffer, highlight_namespace, 0, start_col - 1, {
        end_col = end_col,
        hl_group = "LspSignatureActiveParameter",
        priority = 250,
      })
    end
  end

  if not state.window or not vim.api.nvim_win_is_valid(state.window) then
    state.window = vim.api.nvim_open_win(state.buffer, false, {
      relative = "cursor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      focusable = false,
      zindex = 210,
      title = (" (%d of %d) "):format(state.selected, #state.signatures),
      title_pos = "center",
    })
    vim.wo[state.window].winhighlight = "NormalFloat:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder"
  else
    vim.api.nvim_win_set_config(state.window, {
      relative = "cursor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      title = (" (%d of %d) "):format(state.selected, #state.signatures),
      title_pos = "center",
    })
  end

  vim.wo[state.window].wrap = true
  vim.wo[state.window].linebreak = true
  vim.api.nvim_win_set_cursor(state.window, { 1, 0 })
end

local function request()
  local buffer = vim.api.nvim_get_current_buf()
  if vim.api.nvim_get_mode().mode ~= "i" then
    close()
    return
  end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    if client:supports_method("textDocument/signatureHelp") then
      state.request_id = state.request_id + 1
      local request_id = state.request_id
      local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
      client:request("textDocument/signatureHelp", params, function(error, result)
        vim.schedule(function()
          if request_id ~= state.request_id or buffer ~= vim.api.nvim_get_current_buf() then
            return
          end
          if error or not result or not result.signatures or #result.signatures == 0 then
            close()
            return
          end
          state.signatures = result.signatures
          state.selected = math.min((result.activeSignature or 0) + 1, #state.signatures)
          local active_parameter = result.activeParameter
          for _, signature in ipairs(state.signatures) do
            signature.activeParameter = signature.activeParameter or active_parameter
          end
          render()
        end)
      end, buffer)
      return
    end
  end
  close()
end

function M.select(delta)
  if not state.window or not vim.api.nvim_win_is_valid(state.window) or #state.signatures == 0 then
    return false
  end
  state.timer:stop()
  state.selected = ((state.selected - 1 + delta) % #state.signatures) + 1
  render()
  return true
end

function M.hover()
  close()
  local buffer = vim.api.nvim_get_current_buf()

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    if client:supports_method("textDocument/hover") then
      state.request_id = state.request_id + 1
      local request_id = state.request_id
      local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
      client:request("textDocument/hover", params, function(error, result)
        vim.schedule(function()
          if request_id ~= state.request_id or buffer ~= vim.api.nvim_get_current_buf() then
            return
          end
          if error then
            vim.notify(error.message or "Failed to load method documentation", vim.log.levels.ERROR)
            return
          end

          local lines = result and vim.lsp.util.convert_input_to_markdown_lines(result.contents) or {}
          lines = vim.lsp.util.trim_empty_lines(lines)
          lines = format_hover_lines(lines)
          if #lines == 0 then
            vim.notify("No documentation available for the symbol under the cursor", vim.log.levels.INFO)
            return
          end

          state.buffer, state.window = vim.lsp.util.open_floating_preview(lines, "markdown", {
            border = "rounded",
            focusable = true,
            max_width = 88,
            max_height = 16,
            title = " Documentation ",
            title_pos = "center",
          })
          vim.wo[state.window].winhighlight = "NormalFloat:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder"
        end)
      end, buffer)
      return
    end
  end

  vim.notify("No language server with documentation support is attached", vim.log.levels.WARN)
end

local function navigate(delta, fallback_key)
  if M.select(delta) then
    return
  end
  local loaded, blink = pcall(require, "blink.cmp")
  if loaded then
    local handled = delta > 0 and blink.select_next() or blink.select_prev()
    if handled then
      return
    end
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback_key, true, false, true), "n", false)
end

local function set_navigation_keys(buffer)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.keymap.set("i", "<C-n>", function()
    navigate(1, "<C-n>")
  end, { buffer = buffer, silent = true, desc = "Next overload or completion" })
  vim.keymap.set("i", "<C-p>", function()
    navigate(-1, "<C-p>")
  end, { buffer = buffer, silent = true, desc = "Previous overload or completion" })
end

function M.setup()
  state.timer = state.timer or vim.uv.new_timer()
  vim.lsp.handlers["textDocument/signatureHelp"] = function() end
  local group = vim.api.nvim_create_augroup("roslyn_overload_picker", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertEnter", "LspAttach" }, {
    group = group,
    callback = function(event)
      vim.schedule(function()
        set_navigation_keys(event.buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChangedI", "CursorMovedI" }, {
    group = group,
    callback = function()
      state.timer:stop()
      state.timer:start(30, 0, vim.schedule_wrap(request))
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    group = group,
    callback = close,
  })
end

return M
