return {
    "seblyng/roslyn.nvim",
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {

    choose_target = function(target)
        return vim.iter(target):find(function(item)
            if string.match(item, "Foo.sln") then
                return item
            end
        end)
    end


        -- your configuration comes here; leave empty for default settings
    },
}