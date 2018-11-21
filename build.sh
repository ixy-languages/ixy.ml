#!/bin/bash

# should install and build everything on a clean Debian system
# run as root!

# install ocaml system
apt-get update
apt-get install ocaml opam m4 -y

if [ ! -d "~/.opam" ]; then
  # initialize new opam state
  opam init -y

  # install OCaml 4.07.0
  opam update
  opam switch 4.07.0

  # install ixy
  opam pin add . -y
fi

eval `opam config env`

# build apps (echo, fwd, ...)
make apps

# symlink into current directory
ln -fs _build/default/app/echo.exe echo
ln -fs _build/default/app/fwd.exe fwd
ln -fs _build/default/app/pktgen.exe pktgen
