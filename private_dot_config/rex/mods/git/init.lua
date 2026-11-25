return function(directory, process_directory)
  dofile(directory .. "/rexdiff.lua")(directory, process_directory)
end
