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
    { "<leader>nt", "<cmd>Neotree toggle reveal=false<cr>", desc = "Toggle file explorer" },
    { "<leader>ntf", "<cmd>Neotree focus reveal=false<cr>", desc = "Focus file explorer" },
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
}
