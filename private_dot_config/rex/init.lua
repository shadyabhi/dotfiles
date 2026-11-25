local directory = os.getenv("HOME") .. "/.config/rex/mods"

local process_directory = dofile(directory .. "/process-directory.lua")(directory)
dofile(directory .. "/pane.lua")(process_directory)
dofile(directory .. "/prompt/init.lua")(directory .. "/prompt")
dofile(directory .. "/git/init.lua")(directory .. "/git", process_directory)
