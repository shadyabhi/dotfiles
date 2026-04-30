return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  main = "nvim-treesitter.configs",
  opts = {
    ensure_installed = {
      "python", "lua", "vim", "vimdoc", "bash", "json", "yaml",
      "markdown", "markdown_inline", "go", "javascript", "typescript",
      "tsx", "html", "css", "java", "kotlin", "rust", "c", "cpp",
    },
    auto_install = true,
    highlight = { enable = true },
    indent = { enable = true },
  },
}
