pragma circom 2.1.8;

// Hachage initial à mettre dans le premier input

// Modules
include "sponge.circom";

template Main(n) {
  signal input to_hash[n];
  component hash = AnemoiSponge127(n);
  for (var i = 0; i < n; i++) {
    hash.in[i] <== to_hash[i];
  }
  log(hash.out);
}

component main = Main((10 * 10) * 4 + 3);
