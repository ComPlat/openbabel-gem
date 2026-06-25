module OpenBabel
  # Upstream OpenBabel version — drives the git tag cloned at build time (see extconf.rb).
  VERSION = '3.2.0'
  # Published gem version: <OpenBabel version>.<gem revision>. Must be a valid Gem::Version.
  GEMVERSION = VERSION + '.1'
end
