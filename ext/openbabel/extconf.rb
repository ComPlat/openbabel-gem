require 'fileutils'
require 'rbconfig'
require 'mkmf'

main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))

# Supplies OpenBabel::VERSION (used below to derive the OpenBabel git tag). RubyGems/Bundler
# run this extconf via a bare `ruby extconf.rb` without the gem's lib/ on the load path, so we
# must load the version file ourselves rather than relying on the caller to pre-require it.
require File.join(main_dir, 'lib', 'openbabel', 'version')

# install OpenBabel

openbabel_dir = File.join main_dir, "openbabel_src"
src_dir = openbabel_dir
build_dir = File.join src_dir, "build"
install_dir = File.join main_dir, "openbabel"
install_lib_dir = File.join install_dir, "lib"
ruby_src_dir = File.join src_dir, "scripts", "ruby"

begin
  nr_processors = `getconf _NPROCESSORS_ONLN`.to_i # should be POSIX compatible
rescue
  nr_processors = 1
end

FileUtils.mkdir_p openbabel_dir
# Ref to clone from upstream OpenBabel. Defaults to the release tag derived from
# OpenBabel::VERSION (e.g. '3.1.1' -> 'openbabel-3-1-1'); override with the OPENBABEL env var.
version = ENV.fetch('OPENBABEL', 'openbabel-' + OpenBabel::VERSION.gsub(/\./,"-"))
Dir.chdir main_dir do
  FileUtils.rm_rf src_dir
  puts "Downloading OpenBabel sources (#{version})"
  unless system "git clone --depth 1 https://github.com/openbabel/openbabel.git --branch #{version} #{src_dir}"
    abort "Failed to clone OpenBabel #{version} — aborting build"
  end
end

# Patch: release tags up to and including openbabel-3-1-1 predate upstream PR #2533 and are
# missing `#include <ctime>` in obutil.h, so they fail to compile on GCC 11+ (clock /
# CLOCKS_PER_SEC not declared). Inject the include idempotently right after the header guard
# so those refs build on a modern toolchain. The default ref (openbabel-3-2-0) and any newer
# ref already carry the include, so this is a no-op for them — it only matters when building
# an older ref via the OPENBABEL override.
obutil_h = File.join(src_dir, "include", "openbabel", "obutil.h")
if File.exist?(obutil_h)
  contents = File.read(obutil_h)
  unless contents.include?("#include <ctime>")
    patched = contents.sub(/(#define\s+OB_UTIL_H\b.*\n)/, "\\1#include <ctime>\n")
    if patched == contents
      abort "Failed to apply <ctime> patch to #{obutil_h} (header guard not found)"
    end
    File.write(obutil_h, patched)
    puts "Patched #{obutil_h}: added #include <ctime>"
  end
else
  abort "Expected #{obutil_h} after clone, but it is missing — aborting build"
end

FileUtils.mkdir_p build_dir
FileUtils.mkdir_p install_dir
Dir.chdir build_dir do
  puts "Configuring OpenBabel"
  cmake = "cmake #{src_dir} -DCMAKE_INSTALL_PREFIX=#{install_dir} -DBUILD_GUI=OFF -DENABLE_TESTS=OFF -DRUN_SWIG=ON -DRUBY_BINDINGS=ON"
  # set rpath for local installations
  # http://www.cmake.org/Wiki/CMake_RPATH_handling
  # http://vtk.1045678.n5.nabble.com/How-to-force-cmake-not-to-remove-install-rpath-td5721193.html
  cmake += " -DCMAKE_INSTALL_RPATH:STRING=\"#{install_lib_dir}\"" 
  system cmake
end

# local installation in gem directory
Dir.chdir build_dir do
  puts "Compiling OpenBabel sources."
  system "make -j#{nr_processors}"
  system "make install"
  ENV["PKG_CONFIG_PATH"] = File.dirname(File.expand_path(Dir["#{install_dir}/**/openbabel*pc"].first))
end

FileUtils.remove_dir(openbabel_dir)

# create a fake Makefile
File.open(File.join(File.dirname(__FILE__),"Makefile"),"w+") do |makefile|
  makefile.puts "all:\n\ttrue\n\ninstall:\n\ttrue\n"
end

$makefile_created = true
