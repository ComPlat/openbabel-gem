# Build/verification image for the openbabel gem.
# Compiles OpenBabel + Ruby SWIG bindings via ext/openbabel/extconf.rb, then runs the test.
# Uses a modern base (bookworm / GCC 12, Ruby 3.3) to prove the gem builds on a current
# toolchain — close to production (chemotion-builder runs Ubuntu 24.04 / GCC 13, Ruby 3.3).
# extconf.rb injects the missing `#include <ctime>` into OpenBabel 3.1.1's obutil.h, so the
# old bullseye/GCC-10 pin that worked around that build failure is no longer needed.
FROM ruby:3.3-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      cmake git make g++ swig \
      libxml2-dev zlib1g-dev libeigen3-dev libcairo2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN gem install rake test-unit

WORKDIR /gem
COPY . .

# Run the native extension build via a bare `ruby extconf.rb` — exactly how RubyGems/Bundler
# invoke it (no -Ilib, no pre-required version). extconf.rb loads OpenBabel::VERSION itself.
# Do NOT add -ropenbabel/version here: pre-loading it would mask a real install-time failure
# (extconf referencing the constant without requiring it), which is how that bug once escaped.
# It git-clones OpenBabel at the version-derived tag, cmake/make-builds it with SWIG Ruby
# bindings, and installs into the gem's local ./openbabel tree.
RUN cd ext/openbabel && ruby extconf.rb

# Verify the compiled bindings load and behave (loads ./lib/openbabel.rb).
CMD ["ruby", "-Ilib", "-e", "require 'openbabel'; include OpenBabel; c=OBConversion.new; c.set_in_format('smi'); m=OBMol.new; c.read_string(m,'CC(C)CCCC(C)C1CCC2C1(CCC3C2CC=C4C3(CCC(C4)O)C)C'); m.add_hydrogens; raise 'formula '+m.get_formula unless m.get_formula=='C27H46O'; raise 'atoms '+m.num_atoms.to_s unless m.num_atoms==74; puts 'OK formula='+m.get_formula+' atoms='+m.num_atoms.to_s"]
