# Loaded by CMakeLists.txt through `rake --rakelibdir` at configure time.
# Writes the directory of every gem the build config enables (dependencies
# included) to GEM_DIRS_OUT, one per line, so CMake can pick up their
# ports/esp32 and ports/common sources. libmruby.a is not built, though
# loading the Rakefile still runs the gems' load-time steps (mrubyc autogen).
desc "write the gem directories of GEM_DIRS_TARGET to GEM_DIRS_OUT"
task :gem_dirs do
  target = ENV.fetch('GEM_DIRS_TARGET')
  out = ENV.fetch('GEM_DIRS_OUT')
  build = MRuby.targets[target] or abort "gem_dirs: no build target named #{target}"
  File.write(out, build.gems.map { |g| "#{g.dir}\n" }.join)
end
