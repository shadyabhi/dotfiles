-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.number = true
vim.opt.relativenumber = false

-- ZZ / ZQ exit nvim entirely instead of just the current window.
vim.keymap.set("n", "ZZ", "<cmd>wqall<cr>", { desc = "Write all and quit nvim" })
vim.keymap.set("n", "ZQ", "<cmd>qall!<cr>", { desc = "Quit nvim, discard changes" })

-- Detect uv inline-script shebangs (`#!/usr/bin/env -S uv run --script`) as Python.
vim.filetype.add({
  pattern = {
    [".*"] = {
      function(_, bufnr)
        local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
        if line:match("^#!.*uv run") or line:match("^#!.*python") then
          return "python"
        end
      end,
    },
  },
})

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    -- import your plugins
    { import = "plugins" },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "habamax" } },
  -- Background sync on startup (see autocmd below); no in-editor checker popup.
  checker = { enabled = false },
})

-- Background plugin sync, throttled to once per week.
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local stamp = vim.fn.stdpath("state") .. "/lazy-last-sync"
    local last = (vim.uv or vim.loop).fs_stat(stamp)
    local age = last and (os.time() - last.mtime.sec) or math.huge
    if age < 7 * 24 * 60 * 60 then return end
    vim.defer_fn(function()
      require("lazy").sync({ show = false, wait = false })
      vim.fn.writefile({ tostring(os.time()) }, stamp)
    end, 2000)
  end,
})
