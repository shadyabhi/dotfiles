local directory = os.getenv("HOME") .. "/.config/rex/mods"

dofile(directory .. "/pane.lua")
dofile(directory .. "/prompt/init.lua")(directory .. "/prompt")
dofile(directory .. "/git/init.lua")(directory .. "/git")
