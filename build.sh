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
  opam switch 4.07.0 # Debian still uses opam 1.2.2
fi

opam install ppx_cstruct -y

eval `opam config env`

# build apps (echo, fwd, pktgen)
make
# install apps as ixy-{echo,fwd,pktgen}
make install
