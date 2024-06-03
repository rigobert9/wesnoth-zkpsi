pragma circom 2.1.8;
include "anemoi.circom";

// Les constantes de round ont été calculées à partir du programme Sage des
// concepteurs, et sont écrites de façon statique avec de quoi faire 19 rounds,
// le nombre préconisé pour 127 bits de sécurité par le papier.

// Apporte, selon le cas d'exemple du papier, 127 bits de sécurité, ce qui est
// largement suffisant pour notre cas d'usage.
// Il suffit d'utiliser un rate et une capacité de 1, avec 19 rounds.
// TODO : expérimenter avec d'autres tailles de 1 à 4 pour améliorer la taille
// On sort un hachage de taille 1
template AnemoiSponge127(ninput) {
  signal input in[ninput];
  signal output out;
  // Pour un tel rate de 1, pas besoin de padding

  component permutations[ninput];
  signal states[ninput];

  for (var i = 0; i < ninput; i++) {
    // Exposant : 11, suivi de son inverse dans le corps fini de bn128
    // (recommandé par le papier pour 19 rounds)
    // Le générateur choisi est 5, qui est une racine primitive
    // modulo 21888242871839275222246405745257275088548364400416034343698204186575808495617
    // Calculée avec SageMath en évaluant primitive_root(n)
    permutations[i] =
    Anemoi(1,19,11,7959361044305190989907783907366281850381223418333103397708437886027566725679);
    if (i == 0) {
      permutations[0].X[0] <== in[0];
      permutations[0].Y[0] <== 0;
    } else {
      permutations[i].X[0] <== permutations[i - 1].outX[0] + in[i];
      permutations[i].Y[0] <== permutations[i - 1].outY[0];
    }
  }
  out <== permutations[ninput - 1].outX[0];
}

// Pour tenir 24h face à Frontier, il suffit de 77 bits de sécurité, donnant
// dans notre cas 13 rounds.
template AnemoiSponge77(ninput) {
  signal input in[ninput];
  signal output out;

  component permutations[ninput];
  signal states[ninput];

  for (var i = 0; i < ninput; i++) {
    permutations[i] =
    Anemoi(1,13,11,7959361044305190989907783907366281850381223418333103397708437886027566725679);
    if (i == 0) {
      permutations[0].X[0] <== in[0];
      permutations[0].Y[0] <== 0;
    } else {
      permutations[i].X[0] <== permutations[i - 1].outX[0] + in[i];
      permutations[i].Y[0] <== permutations[i - 1].outY[0];
    }
  }
  out <== permutations[ninput - 1].outX[0];
}
