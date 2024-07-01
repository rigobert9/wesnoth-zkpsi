pragma circom 2.1.8;

// Circomlib
include "pedersen.circom";
include "mux1.circom";
include "mux2.circom";
include "escalarmulany.circom";
include "comparators.circom";
include "bitify.circom";
// Modules
include "functions.circom";

template XorTabTab(tab_size, subtab_size) {
  signal input in1[tab_size][subtab_size];
  signal input in2[tab_size][subtab_size];
  signal output out[tab_size][subtab_size];

  for (var slot = 0; slot < tab_size; slot++) {
    for (var j = 0; j < subtab_size; j++) { // XOR
        out[slot][j] <== in1[slot][j] + in2[slot][j] - 2 * in1[slot][j] * in2[slot][j];
    }
  }
}

// // Les troupes peuvent voir aussi loin qu'elles peuvent se déplacer de jour
// template CanSee(state_size, state_height, state_width, hex, seer) {
//     signal input seer_val;
//     signal output out;
//
//     // Devrait suffir
//     component is_seer = LessThan(32);
//     is_seer.in[0] <== dist_ax(hex,seer);
//     is_seer.in[1] <== seer_val;
//     out <== is_seer.out;
// }

template Vision(state_size, state_height, state_width, max_radius) {
  signal input in[state_size];
  signal output out[state_size];

  var total_neighbours = 0;
  for (var x = 0; x < state_height; x++) {
    for (var y = 0; y < state_width; y++) {
      total_neighbours += nb_neighbours(state_height, state_width, x, y, max_radius);
    }
  }

  signal interm_or[total_neighbours];
  component can_sees[total_neighbours];
  var current_or = 0;
  var first_flag = 1;

  // Pour l'instant, on vérifie pour chaque case de out un gros OR sur les cases
  // autour pour chaque rayon possible
  // On ne vérifie pas sur la case même, il ne peut y avoir qu'une seule unité
  for (var x = 0; x < state_height; x++) {
    for (var y = 0; y < state_width; y++) {
      var ax_coord[2] = rect_to_ax([x,y]);
      for (var rayon = 1; rayon <= max_radius; rayon++){
        // On commence par la case en-dessous
        var cur_coord[2] = [ax_coord[0], ax_coord[1] + rayon];
        var cur_coord_rect[2] = [x, y + rayon];
        for (var orientation = 0; orientation < 6; orientation++) {
          for (var cote = 0; cote < rayon; cote++) {
            if (cur_coord_rect[0] < state_height
              && 0 <= cur_coord_rect [0]
              && cur_coord_rect[1] < state_width
              && 0 <= cur_coord_rect[1]) {
                can_sees[current_or] = parallel LessEqThan(32);
                can_sees[current_or].in[0] <-- rayon;
                can_sees[current_or].in[1] <-- in[cur_coord_rect[0] * state_height + cur_coord_rect[1]];
                if (first_flag == 1) {
                  interm_or[current_or] <== can_sees[current_or].out;
                  first_flag = 0;
                } else {
                  // Effectue un or, volé dans gates.circom
                  interm_or[current_or] <== can_sees[current_or].out + interm_or[current_or - 1]
                                            - (can_sees[current_or].out * interm_or[current_or - 1]);
                }
                current_or++;
            }
            // Passage à la case suivante
            cur_coord = neighbour_ax(cur_coord, orientation);
            cur_coord_rect = neighbour_rect(cur_coord_rect, orientation);
          }
        }
      }
      // Résultat final du or dans out
      out[(x * state_height) + y] <== interm_or[current_or - 1];
      first_flag = 1;
    }
  }
}

template Phase1(state_size, state_height, state_width, max_radius) {
  signal input sightrange[state_size];
  signal input hashed_idents[state_size][2];
  signal input phase1_exponents[state_size][254];
  signal output phase1_output[state_size][2]; // Points

  /* Calcul des cases visibles */
  component can_see = Vision(state_size, state_height, state_width, max_radius);
  can_see.in <== sightrange;

  /* Calculs pour les sorties de phases 1 et 2 */
  // Précalculé comme le Pedersen de [-1]
  var chaff_hash[2] =
    [21662927615494759978582090955465695271172563139602648503605918901430020463067,
    18439437317645054740275210704556178717405886457041116987341402241973661831421];
  component exp_phase1[state_size];
  component exp_chaff_phase1[state_size];
  component choose_phase1[state_size];

  for (var i = 0; i < state_size; i++) {
    exp_phase1[i] = parallel EscalarMulAny(254);
    exp_phase1[i].e <== phase1_exponents[i];
    exp_phase1[i].p <== hashed_idents[i];
    exp_chaff_phase1[i] = parallel EscalarMulAny(254);
    exp_chaff_phase1[i].e <== phase1_exponents[i];
    exp_chaff_phase1[i].p <== chaff_hash;
    // Choix entre le chaff avec cet exposant ou la case si on peut voir
    choose_phase1[i] = parallel Multiplexor2();
    choose_phase1[i].in[0] <== exp_chaff_phase1[i].out;
    choose_phase1[i].in[1] <== exp_phase1[i].out;
    choose_phase1[i].sel <== can_see.out[i];
    phase1_output[i] <== choose_phase1[i].out;
  }
}

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

/* Cette version imprime les outputs de la phase 2
Dans l'ordre, on imprime :
- Le Diffie-Hellman de chaque case (sur state_size lignes, avec un espace
  séparant les coordonnées)
- Les hashs des tags (même présentation)
- Les hashs des données (3 valeurs séparées par des espaces, state_size fois)
*/
template Phase2(state_size, enum_tag, enum_data) {
  signal input state[state_size][3];
  signal input hashed_idents[state_size][2]; //Points
  signal input phase2_exponent[254];
  /* Entrée adverses publique */
  signal input phase1_received[state_size][2]; // Points

  signal output phase2_dh_output[state_size][2]; // Points
  signal output phase2_hidden_tags[state_size][2]; // Points
  signal output phase2_hidden_data[state_size][3][64]; // 64 Bits chacun

  // Composants
  component dh_phase2[state_size];
  component exp_phase2[state_size];
  // Versions binaires pour Pedersen
  component bin_hashed_ident[state_size];
  component bin_exp[state_size];

  component hash_tag_phase2[state_size];
  component hash_data_phase2[state_size];
  // Matériel pour le xor
  component bin_hashed_data[state_size];
  component bin_data[state_size][3];

  for (var i = 0; i < state_size; i++) {
    // Précalcul de la phase 2 : exponentiation par l'exposant de la phase 2 des
    // hachages
    exp_phase2[i] = parallel EscalarMulAny(254);
    exp_phase2[i].e <== phase2_exponent;
    exp_phase2[i].p <== hashed_idents[i];
    // Calculs de la phase 2
    dh_phase2[i] = parallel EscalarMulAny(254);
    dh_phase2[i].e <== phase2_exponent;
    dh_phase2[i].p <== phase1_received[i];
    phase2_dh_output[i] <== dh_phase2[i].out;

    // Préparation des données binaires à hash dans Pedersen
    // Puisqu'il est difficile de faire une collision en la coordonnée x (c'est
    // l'inverse seulement qui a le même x), on peut s'en tenir à la première
    // coordonnée (hashed_idents sont des résultats de Hash)
    bin_hashed_ident[i] = parallel Num2Bits(254);
    bin_hashed_ident[i].in <== hashed_idents[i][0];
    bin_exp[i] = parallel Num2Bits(254);
    bin_exp[i].in <== exp_phase2[i].out[0];

    // Tags
    hash_tag_phase2[i] = parallel Pedersen((254 * 2) + 1);
    for (var j = 0; j < 254; j++) {
      hash_tag_phase2[i].in[j] <== bin_hashed_ident[i].out[j];
    }
    for (var j = 0; j < 254; j++) {
      hash_tag_phase2[i].in[254 + j] <== bin_exp[i].out[j];
    }
    hash_tag_phase2[i].in[508] <== enum_tag;
    phase2_hidden_tags[i] <== hash_tag_phase2[i].out;

    // Données
    hash_data_phase2[i] = parallel Pedersen((254 * 2) + 1);
    for (var j = 0; j < 254; j++) {
      hash_data_phase2[i].in[j] <== bin_hashed_ident[i].out[j];
    }
    for (var j = 0; j < 254; j++) {
      hash_data_phase2[i].in[254 + j] <== bin_exp[i].out[j];
    }
    hash_data_phase2[i].in[508] <== enum_data;
    // La coordonnée x suffit à un hachage, car la seule collision possible est
    // avec l'inverse du point
    bin_hashed_data[i] = parallel Num2Bits(254);
    bin_hashed_data[i].in <== hash_data_phase2[i].out[0];

    // IMPORTANT : réutiliser 3 fois un nombre en binaire pour cacher les
    // données est une faille de sécurité grave, surtout vu les nombre de fois
    // que l'une des cases est 0, permettant d'ouvrir les autres cases.
    // Il faut donc répartir le résultat sur les trois cases. Ici, on représente
    // chaque donnée avec 64 bits (ce qui devrait suffire en conditions
    // normales), et on recouvre avec les 254 bits de notre hash.
    for (var slot = 0; slot < 3; slot++) {
      // Mettre les données dans le xor
      bin_data[i][slot] = parallel Num2Bits(64);
      bin_data[i][slot].in <== state[i][slot];
      for (var j = 0; j < 64; j++) {
        // Produit un XOR, volé dans gates.circom
        phase2_hidden_data[i][slot][j] <== bin_hashed_data[i].out[(64 * slot) + j] + bin_data[i][slot].out[j] - 2 * bin_hashed_data[i].out[(64 * slot) + j] * bin_data[i][slot].out[j];
      }
    }
  }
  for (var i = 0; i < state_size; i++) { log(phase2_dh_output[i][0],phase2_dh_output[i][1]); }
  for (var i = 0; i < state_size; i++) { log(phase2_hidden_tags[i][0],phase2_hidden_tags[i][1]); }
  for (var i = 0; i < state_size; i++) {
    log(
      bits_to_number(phase2_hidden_data[i][0]),
      bits_to_number(phase2_hidden_data[i][1]),
      bits_to_number(phase2_hidden_data[i][2])
     );
  }
}
