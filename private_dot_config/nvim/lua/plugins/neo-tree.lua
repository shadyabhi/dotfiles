return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  cmd = "Neotree",
  keys = {
    { "<leader>e", "<cmd>Neotree toggle reveal=false<cr>", desc = "Toggle file explorer" },
    { "<leader>o", "<cmd>Neotree focus reveal=false<cr>", desc = "Focus file explorer" },
  },
  opts = {
    close_if_last_window = true,
    filesystem = {
      follow_current_file = { enabled = true },
      hijack_netrw_behavior = "open_default",
      bind_to_cwd = false,
      cwd_target = {
        sidebar = "none",
        current = "none",
      },
    },
    window = {
      width = 32,
    },
  },
  init = function()
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function()
        if vim.fn.argc() == 0 then
          vim.cmd("Neotree show reveal=false")
        else
          local arg = vim.fn.argv(0)
          if vim.fn.isdirectory(arg) == 1 then
            vim.cmd("Neotree show reveal=false dir=" .. vim.fn.fnameescape(arg))
          else
            vim.cmd("Neotree show reveal=false")
            vim.cmd("wincmd p")
          end
        end
      end,
    })
  end,
}
