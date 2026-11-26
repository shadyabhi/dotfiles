local directory = os.getenv("HOME") .. "/.config/rex/mods"
package.path = directory .. "/?.lua;" .. package.path

local process_directory = dofile(directory .. "/process-directory.lua")(directory)
require("pane")(process_directory)
dofile(directory .. "/prompt/init.lua")(directory .. "/prompt")
dofile(directory .. "/git/init.lua")(directory .. "/git", process_directory)
