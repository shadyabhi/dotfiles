return {
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    build = ":MasonUpdate",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = {
        "pyright",
        "gopls",
        "rust_analyzer",
        "perlnavigator",
      },
      automatic_installation = true,
    },
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      vim.lsp.config("perlnavigator", {
        settings = {
          perlnavigator = {
            enableWarnings = false,
            perltidyEnabled = true,
            perlcriticEnabled = true,
            includePaths = {
              vim.fn.expand("~/perl5/lib/perl5"),
              "$workspaceFolder/Files/usr/local/ccsc/lib",
              "$workspaceFolder/lib",
            },
          },
        },
        -- Drop compile-check diagnostics: this codebase pulls in CPAN XS
        -- modules (Net::Curl::Easy, etc.) that only exist on the appliance,
        -- so `perl -c` always fails locally. Keep nav features (gd, K, gr).
        handlers = {
          ["textDocument/publishDiagnostics"] = function(_, result, ctx, config)
            if result and result.diagnostics then
              local filtered = {}
              for _, d in ipairs(result.diagnostics) do
                local msg = d.message or ""
                if not (msg:match("Can't locate")
                    or msg:match("BEGIN failed")
                    or msg:match("compilation aborted")) then
                  table.insert(filtered, d)
                end
              end
              result.diagnostics = filtered
            end
            vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
          end,
        },
      })

      -- PEP 723 inline scripts (`#!/usr/bin/env -S uv run --script`) declare their
      -- deps in a `# /// script` block. `uv run` installs those into an ephemeral
      -- env under ~/.cache/uv/environments-v2, which Pyright can't see, so imports
      -- like `fastavro` show as unresolved. Point Pyright at that env's interpreter.
      local function set_uv_script_interp(client, bufnr)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == "" or vim.bo[bufnr].buftype ~= "" then
          return
        end
        local head = vim.api.nvim_buf_get_lines(bufnr, 0, 30, false)
        if not vim.tbl_contains(head, "# /// script") then
          return
        end
        vim.system({ "uv", "python", "find", "--script", name }, { text = true }, function(out)
          local interp = vim.trim(out.stdout or "")
          if out.code ~= 0 or interp == "" then
            return
          end
          vim.schedule(function()
            client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
              python = { pythonPath = interp },
            })
            client:notify("workspace/didChangeConfiguration", { settings = client.settings })
          end)
        end)
      end

      vim.lsp.config("pyright", {
        on_attach = function(client, bufnr)
          set_uv_script_interp(client, bufnr)
        end,
      })

      vim.lsp.enable({ "pyright", "gopls", "rust_analyzer", "perlnavigator" })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          map("n", "gd", vim.lsp.buf.definition, "Go to definition")
          map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
          map("n", "gr", vim.lsp.buf.references, "References")
          map("n", "gi", vim.lsp.buf.implementation, "Implementation")
          map("n", "K", vim.lsp.buf.hover, "Hover")
          map("n", "<leader>rn", vim.lsp.buf.rename, "Rename")
          map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("n", "[d", vim.diagnostic.goto_prev, "Prev diagnostic")
          map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
        end,
      })
    end,
  },
}
