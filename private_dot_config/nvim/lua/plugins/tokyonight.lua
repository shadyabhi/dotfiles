return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = true,
      styles = { sidebars = "transparent", floats = "transparent" },
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")

      vim.opt.fillchars:append({ vert = "┃", vertleft = "┫", vertright = "┣", verthoriz = "╋", horiz = "━", horizup = "┻", horizdown = "┳" })
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#7aa2f7", bold = true })
    end,
  },
}
