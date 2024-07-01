pragma circom 2.1.8;

include "pedersen.circom";
include "escalarmulany.circom";
include "bitify.circom";

/* On calcule ici, après avoir reçu :
- Les tokens Diffie-Hellman
- Les commits de tags
- Les commits de data XOR les données

On doit :
- Calculer la puissance de l'inverse de nos exposants de la phase 1 les tokens
  Diffie-Hellman
- Calculer à partir d'eux les commits de tags pour nous, et les imprimer !
- Imprimer le XOR des commits XOR'd avec des commits de données qu'on calcule

Si on a la correspondance entre les commits de tags, alors ce qui sort des XOR
est bon, sinon, on discard.
Ce tri est effectué par un script python.
*/

// Convertit une valeur binaire (big endian) en un nombre
function bits_to_number(tab) {
  var out = 0;
  var exp = 1;
  for (var i = 0; i < 64; i++) {
    out += tab[i] * exp;
    exp += exp;
  }
  return out;
}

template Final(state_size, enum_tag, enum_data) {
  // Il faut aussi récupérer les hashs des cases, à notre usage personnel
  signal input hashed_idents[state_size][2];
  // Les inverses des exposants modulo l'ordre de la courbe elliptique
  signal input inv_phase1_exponents[state_size][254];

  signal input phase2_dh_output[state_size][2]; // Points
  signal input phase2_hidden_tags[state_size][2]; // Point
  signal input phase2_hidden_data[state_size][3][64]; // 64 Bits chacun

  component unexp[state_size];
  component own_hidden_tags[state_size];
  component own_hashed_data[state_size];
  component own_bin_hashed_data[state_size];
  signal own_hidden_data[state_size][3][64];

  component bin_hashed_ident[state_size];
  component bin_exp[state_size];

  for (var i = 0; i < state_size; i++) {
    unexp[i] = parallel EscalarMulAny(254);
    unexp[i].e <-- inv_phase1_exponents[i];
    unexp[i].p <-- phase2_dh_output[i];

    // Préparation des données binaires à hash dans Pedersen
    // Puisqu'il est difficile de faire une collision en la coordonnée x (c'est
    // l'inverse seulement qui a le même x), on peut s'en tenir à la première
    // coordonnée (hashed_idents sont des résultats de Hash)
    bin_hashed_ident[i] = parallel Num2Bits(254);
    bin_hashed_ident[i].in <-- hashed_idents[i][0];
    bin_exp[i] = parallel Num2Bits(254);
    bin_exp[i].in <-- unexp[i].out[0];

    // Tags
    own_hidden_tags[i] = parallel Pedersen((254 * 2) + 1);
    for (var j = 0; j < 254; j++) {
      own_hidden_tags[i].in[j] <-- bin_hashed_ident[i].out[j];
    }
    for (var j = 0; j < 254; j++) {
      own_hidden_tags[i].in[254 + j] <-- bin_exp[i].out[j];
    }
    own_hidden_tags[i].in[508] <-- enum_tag;
    // Données
    own_hashed_data[i] = parallel Pedersen((254 * 2) + 1);
    for (var j = 0; j < 254; j++) {
      own_hashed_data[i].in[j] <-- bin_hashed_ident[i].out[j];
    }
    for (var j = 0; j < 254; j++) {
      own_hashed_data[i].in[254 + j] <-- bin_exp[i].out[j];
    }
    own_hashed_data[i].in[508] <-- enum_data;
    own_bin_hashed_data[i] = parallel Num2Bits(254);
    own_bin_hashed_data[i].in <-- own_hashed_data[i].out[0];

    for (var slot = 0; slot < 3; slot++) {
      for (var j = 0; j < 64; j++) {
        // Produit un XOR, volé dans gates.circom
        own_hidden_data[i][slot][j] <-- own_bin_hashed_data[i].out[(64 * slot) + j] + phase2_hidden_data[i][slot][j] - 2 * own_bin_hashed_data[i].out[(64 * slot) + j] * phase2_hidden_data[i][slot][j];
      }
    }
  }
  // Hash des tags, à comparer pour voir ceux égaux aux reçus
  for (var i = 0; i < state_size; i++) { log(own_hidden_tags[i].out[0],own_hidden_tags[i].out[1]); }
  // Candidats de sortie
  for (var i = 0; i < state_size; i++) {
    log(
      bits_to_number(own_hidden_data[i][0]),
      bits_to_number(own_hidden_data[i][1]),
      bits_to_number(own_hidden_data[i][2])
     );
  }
}

component main = Final(10 * 10,0,1);
