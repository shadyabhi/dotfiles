return {
  "stevearc/aerial.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  event = "VeryLazy",
  keys = {
    { "<leader>o", "<cmd>AerialToggle!<cr>", desc = "Toggle Aerial outline" },
  },
  opts = {
    layout = {
      default_direction = "right",
      placement = "edge",
      min_width = 30,
    },
    backends = { "treesitter", "lsp", "markdown", "man" },
    attach_mode = "global",
    show_guides = true,
    filter_kind = false,
    open_automatic = true,
    on_attach = function(bufnr)
      vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", { buffer = bufnr })
      vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", { buffer = bufnr })
    end,
  },
}
