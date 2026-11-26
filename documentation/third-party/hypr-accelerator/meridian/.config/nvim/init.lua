vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },
  
  -- Terminal background color
  --{
  --  "typicode/bg.nvim",
  --  lazy = false,
  --},
  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"

vim.schedule(function()
  require "mappings"
end)

-- Auto-reload theme when chadrc.lua changes
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      local chadrc_path = vim.fn.stdpath("config") .. "/lua/chadrc.lua"
      local last_modified = vim.fn.getftime(chadrc_path)
      
      local timer = vim.loop.new_timer()
      timer:start(1000, 2000, vim.schedule_wrap(function()
        local current_modified = vim.fn.getftime(chadrc_path)
        if current_modified > last_modified then
          last_modified = current_modified
          -- Reload NvChad theme
          require("nvchad.utils").reload()
          vim.notify("Theme reloaded automatically", vim.log.levels.INFO)
        end
      end))
    end, 1000)
  end,
})
