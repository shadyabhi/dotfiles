return {
  "3rd/image.nvim",
  -- Skip the luarock build; use the ImageMagick CLI instead of the `magick` rock.
  build = false,
  ft = { "markdown", "vimwiki" },
  opts = {
    backend = "kitty",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        only_render_image_at_cursor = true,
        filetypes = { "markdown", "vimwiki" },
        -- Resolve Obsidian wikilink embeds: ![[Pasted image ....png|800]].
        -- Strips the |size/|alias suffix and finds the file anywhere in the
        -- vault (Obsidian resolves embeds by basename), since attachments live
        -- in _attachments/ rather than next to the note.
        resolve_image_path = function(document_path, image_path, fallback)
          image_path = image_path:gsub("|.*$", "")
          if image_path:sub(1, 1) == "/" then
            return image_path
          end
          local exists = function(p)
            return p and (vim.uv or vim.loop).fs_stat(p) ~= nil
          end
          local doc_dir = vim.fn.fnamemodify(document_path, ":h")
          local rel = doc_dir .. "/" .. image_path
          if exists(rel) then
            return rel
          end
          local vault = vim.fs.root(doc_dir, ".obsidian") or doc_dir
          local base = vim.fn.fnamemodify(image_path, ":t")
          local hits = vim.fn.globpath(vault, "**/" .. base, false, true)
          if #hits > 0 then
            return hits[1]
          end
          return fallback(document_path, image_path)
        end,
      },
    },
    max_width = 100,
    max_height = 12,
    max_height_window_percentage = 30,
    -- tmux passthrough is required to draw images from inside tmux.
    tmux_show_only_in_active_window = true,
  },
}
