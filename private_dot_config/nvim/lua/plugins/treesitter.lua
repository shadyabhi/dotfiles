return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  lazy = false,
  config = function()
    local parsers = {
      "python", "lua", "vim", "vimdoc", "bash", "json", "yaml",
      "markdown", "markdown_inline", "go", "javascript", "typescript",
      "tsx", "html", "css", "java", "kotlin", "rust", "c", "cpp",
    }

    require("nvim-treesitter").setup()
    require("nvim-treesitter").install(parsers)

    vim.api.nvim_create_autocmd("FileType", {
      pattern = {
        "python", "lua", "vim", "help", "bash", "sh", "json", "yaml",
        "markdown", "go", "javascript", "typescript", "typescriptreact",
        "javascriptreact", "html", "css", "java", "kotlin", "rust", "c", "cpp",
      },
      callback = function()
        pcall(vim.treesitter.start)
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
