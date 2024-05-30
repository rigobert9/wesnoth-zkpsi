pragma circom 2.1.8;

// Hachage initial à mettre dans le premier input

// Modules
include "sponge.circom";

template Main() {
  component hash = AnemoiSponge127((100 * 4) + 3);
  for (var i = 0; i < 100; i++) {
    if (i == 3) {
      hash.in[i * 4 + 0] <== 1;
      hash.in[i * 4 + 1] <== 58;
      hash.in[i * 4 + 2] <== 0;
      hash.in[i * 4 + 3] <== 2;
    } else {
      hash.in[i * 4 + 0] <== 0;
      hash.in[i * 4 + 1] <== 0;
      hash.in[i * 4 + 2] <== 0;
      hash.in[i * 4 + 3] <== 0;
    }
  }
  hash.in[100 * 4 + 0] <== 100;
  hash.in[100 * 4 + 1] <== 0;
  hash.in[100 * 4 + 2] <== 0;

  log(hash.out);
}

component main = Main();
