return {
  "tpope/vim-fugitive",
  cmd = { "Git", "G", "Gdiffsplit", "Gblame", "Gread", "Gwrite", "Glog" },
  keys = {
    { "<leader>gs", "<cmd>Git<cr>", desc = "Git status (fugitive)" },
    { "<leader>gb", "<cmd>Git blame<cr>", desc = "Git blame" },
    { "<leader>gd", "<cmd>Gdiffsplit<cr>", desc = "Git diff split" },
  },
}
