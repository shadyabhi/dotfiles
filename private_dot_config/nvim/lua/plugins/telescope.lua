return {
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "Find Files" },
      { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Find Text" },
      { "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "Find Buffers" },
      { "<leader>fh", function() require("telescope.builtin").help_tags() end, desc = "Find Help" },
      { "<leader>fr", function() require("telescope.builtin").oldfiles() end, desc = "Find Recent Files" },
      { "<leader>fd", function() require("telescope.builtin").diagnostics() end, desc = "Find Diagnostics" },
      { "<leader>fk", function() require("telescope.builtin").keymaps() end, desc = "Find Keymaps" },
      { "<leader>/", function() require("telescope.builtin").current_buffer_fuzzy_find() end, desc = "Search Current Buffer" },
    },
    opts = {
      -- nvim-treesitter `main` branch removed `ft_to_lang`, which telescope's
      -- 0.1.x previewer calls. Fall back to Vim regex highlighting in previews.
      defaults = {
        preview = { treesitter = false },
      },
    },
  },
}
