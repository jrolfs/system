-- Move a running neovim from one worktree to another, parking the buffers,
-- window layout and jumplist of the worktree it leaves so that coming back
-- lands where it left off.
--
-- Loaded through `loadfile()` from switch.py rather than required as a module.
-- The neovim config is a separate repo consumed here as a flake input, so
-- living there would put a lock bump and a neovim restart between an edit and
-- trying it; this way a `nix-switch` is enough, and nothing has to be wired
-- into init.lua for the switcher to reach it.

-- Outside ~/.config/nvim, so .luarc.json's neovim runtime path does not reach
-- here and lua_ls has no declaration for `vim`.
---@diagnostic disable: undefined-global

local M = {}

-- Sessions are keyed by worktree path, not branch. A worktree outlives the
-- branch checked out in it, and with stacked branches the checked-out branch
-- moves while the directory, and the buffers that were open in it, stay put.
-- This is the same reasoning as wt-handoff's refs/wip/<directory> keys.
local directory = vim.fn.stdpath('state') .. '/worktree-sessions'

local function session_for(path)
  return directory .. '/' .. (path:gsub('/', '%%')) .. '.vim'
end

local function normalize(path)
  return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1'))
end

--- Count buffers holding unwritten changes to a real file.
---
--- Terminal and quickfix buffers are excluded: they report `modified` as a
--- matter of course and `mksession` records how to recreate them, so wiping
--- one loses nothing a switch should refuse over.
local function unsaved()
  return #vim.tbl_filter(function(buffer)
    return vim.api.nvim_buf_is_loaded(buffer)
      and vim.bo[buffer].modified
      and vim.bo[buffer].buftype == ''
  end, vim.api.nvim_list_bufs())
end

--- Point this neovim at `target`, saving the current worktree's session first.
---
--- @param target string Absolute path to the worktree to move to.
--- @return string A one-word result: `already`, `unsaved:<n>`, `restored`, or `fresh`.
function M.switch(target)
  target = normalize(target)
  local current = normalize(vim.fn.getcwd())

  if current == target then
    return 'already'
  end

  -- Nothing below writes a file, so an unwritten buffer would be wiped with
  -- its changes. Refuse rather than guess whether they were wanted.
  --
  -- Notified here as well as returned, because the caller is a worktrunk
  -- post-switch hook running detached in the background and whatever it
  -- prints may well go nowhere, while this lands in front of the person who
  -- has the unsaved buffer open.
  local dirty = unsaved()
  if dirty > 0 then
    vim.notify(
      ('worktree: staying in %s, %d buffer(s) unsaved'):format(
        vim.fn.fnamemodify(current, ':t'),
        dirty
      ),
      vim.log.levels.WARN
    )
    return 'unsaved:' .. dirty
  end

  vim.fn.mkdir(directory, 'p')
  vim.cmd('mksession! ' .. vim.fn.fnameescape(session_for(current)))

  -- Clients outlive the buffers that spawned them and would keep indexing a
  -- tree nothing is looking at any more. Stopping them here also means the
  -- restored session attaches fresh clients rooted in the new worktree.
  pcall(function()
    for _, client in ipairs(vim.lsp.get_clients()) do
      client:stop(true)
    end
  end)

  vim.cmd('silent! %bwipeout!')
  vim.cmd('cd ' .. vim.fn.fnameescape(target))

  -- A whole-editor `cd` rather than `lcd`, because there is one neovim per
  -- kitty tab and the tab as a whole is what moved. Telescope, the LSP root
  -- and :terminal all read the global cwd, so an `lcd` would leave them
  -- pointed at the worktree that was left behind.
  local session = session_for(target)
  if vim.fn.filereadable(session) == 1 then
    vim.cmd('source ' .. vim.fn.fnameescape(session))
    return 'restored'
  end

  -- Matches how the seed sessions in ~/.config/nvim/sessions end, so a
  -- worktree opened for the first time looks like a freshly opened tab.
  pcall(vim.cmd, 'Telescope git_files')
  return 'fresh'
end

return M
