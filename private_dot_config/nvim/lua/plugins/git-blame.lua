return {
  "f-person/git-blame.nvim",
  event = "BufReadPre",
  opts = {
    enabled = true,
    message_template = " <summary> • <date> • <author>",
    date_format = "%Y-%m-%d",
    virtual_text_column = 1,
  },
}
