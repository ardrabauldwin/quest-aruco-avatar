#!/usr/bin/env bash
# Run as root in the authorised Ubuntu WSL distribution.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
timeout 300 apt-get update
timeout 900 apt-get install -y build-essential ghc cabal-install happy libgmp-dev zlib1g-dev curl git python3 ca-certificates
SOURCE=/mnt/c/Users/bauld/Overlay/quest-aruco-avatar/builds/ccbm-public
DEST=/opt/naret-ccbm
mkdir -p "$DEST"
cp -a "$SOURCE/." "$DEST/"
cd "$DEST"
# Windows checkout line endings must not reach Linux shell interpreters.
sed -i 's/\r$//' rc
chmod +x rc
find src -name '*.sh' -exec sed -i 's/\r$//' {} +
find src -name '*.sh' -exec chmod +x {} +
mkdir -p src/lib
if [ ! -f src/lib/boost/boost/version.hpp ]; then
  timeout 300 curl --fail --location --retry 2 https://archives.boost.io/release/1.64.0/source/boost_1_64_0.tar.bz2 -o /tmp/naret-boost-1.64.tar.bz2
  tar -xjf /tmp/naret-boost-1.64.tar.bz2 -C src/lib
  mv src/lib/boost_1_64_0 src/lib/boost
fi
if [ ! -f src/lib/fann/src/floatfann.c ]; then
  timeout 120 git clone --depth 1 https://github.com/libfann/fann.git src/lib/fann
fi
cd RCGen
# Newer mtl no longer re-exports when through Control.Monad.State.
if ! grep -q '^import Control.Monad (when)' Main.hs; then
  sed -i '/^import Control.Monad.State/a import Control.Monad (when)' Main.hs
fi
# All Haskell dependencies are bundled with the distro compiler. Avoid a
# separate global cabal install and record any compatibility failures verbatim.
timeout 60 happy RCParser.y
timeout 600 ghc --make -O2 -XTypeSynonymInstances -XFlexibleInstances -XMultiParamTypeClasses -XCPP Main.hs -o rcg
printf '\nCCBM generator ready at %s/RCGen/rcg\n' "$DEST"
