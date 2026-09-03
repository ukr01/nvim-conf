local function clean_markdown(text)
  if type(text) ~= "string" then
    return text
  end
  return text:gsub("\r", ""):gsub("\\([%p])", "%1")
end

return {
  {
    "folke/noice.nvim",
    opts = {
      lsp = {
        signature = {
          enabled = false,
        },
      },
    },
  },
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      require("overload-picker").setup()
      opts.signature = vim.tbl_deep_extend("force", opts.signature or {}, {
        enabled = false,
      })
      opts.completion = opts.completion or {}
      opts.completion.menu = vim.tbl_deep_extend("force", opts.completion.menu or {}, {
        border = "rounded",
        scrollbar = false,
      })
      opts.completion.documentation = vim.tbl_deep_extend("force", opts.completion.documentation or {}, {
        auto_show = true,
        auto_show_delay_ms = 300,
        draw = function(draw_opts)
          local documentation = draw_opts.item.documentation
          if type(documentation) == "string" then
            documentation = clean_markdown(documentation)
          elseif type(documentation) == "table" and type(documentation.value) == "string" then
            documentation = vim.tbl_extend("force", {}, documentation, {
              value = clean_markdown(documentation.value),
            })
          end

          draw_opts.default_implementation({
            detail = clean_markdown(draw_opts.item.detail),
            documentation = documentation,
          })
        end,
        window = {
          border = "rounded",
          max_width = 72,
          max_height = 16,
          desired_min_width = 44,
          desired_min_height = 6,
          scrollbar = false,
        },
      })
    end,
  },
}