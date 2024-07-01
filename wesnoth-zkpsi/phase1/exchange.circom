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
        out[slot][j] <-- in1[slot][j] + in2[slot][j] - 2 * in1[slot][j] * in2[slot][j];
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
//     is_seer.in[0] <-- dist_ax(hex,seer);
//     is_seer.in[1] <-- seer_val;
//     out <-- is_seer.out;
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
              && 0 <= cur_coord_rect[0]
              && cur_coord_rect[1] < state_width
              && 0 <= cur_coord_rect[1]) {
                can_sees[current_or] = parallel LessEqThan(32);
                can_sees[current_or].in[0] <-- rayon;
                can_sees[current_or].in[1] <-- in[cur_coord_rect[0] * state_height + cur_coord_rect[1]];
                if (first_flag == 1) {
                  interm_or[current_or] <-- can_sees[current_or].out;
                  first_flag = 0;
                } else {
                  // Effectue un or, volé dans gates.circom
                  interm_or[current_or] <-- can_sees[current_or].out + interm_or[current_or - 1]
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
      out[(x * state_width) + y] <-- interm_or[current_or - 1];
      first_flag = 1;
    }
  }
}


/* Cette version imprime les hashed_idents (pour usage personnel) puis les outputs de la phase 1
On imprime seulement, à chaque ligne, d'abord les hashed_idents dans l'ordre,
puis l'output de la phase 1, avec les deux coordonnées séparées par un espace,
sur state_size lignes à chaque fois.
Par exemple:
12151 223154
*/
template Phase1(state_size, state_height, state_width, max_radius) {
  signal input sightrange[state_size];
  signal input hashed_idents[state_size][2];
  signal input phase1_exponents[state_size][254];
  signal output phase1_output[state_size][2]; // Points

  /* Calcul des cases visibles */
  component can_see = Vision(state_size, state_height, state_width, max_radius);
  can_see.in <-- sightrange;

  /* Calculs pour les sorties de phases 1 et 2 */
  // Précalculé comme le Pedersen de [-1]
  var chaff_hash[2] =
    [21662927615494759978582090955465695271172563139602648503605918901430020463067,
    18439437317645054740275210704556178717405886457041116987341402241973661831421];
  component exp_phase1[state_size];
  component exp_chaff_phase1[state_size];
  component choose_phase1[state_size];
  component checks[state_size];

  for (var i = 0; i < state_size; i++) {
    exp_phase1[i] = parallel EscalarMulAny(254);
    exp_phase1[i].e <-- phase1_exponents[i];
    exp_phase1[i].p <-- hashed_idents[i];
    exp_chaff_phase1[i] = parallel EscalarMulAny(254);
    exp_chaff_phase1[i].e <-- phase1_exponents[i];
    exp_chaff_phase1[i].p <-- chaff_hash;
    // Choix entre le chaff avec cet exposant ou la case si on peut voir
    choose_phase1[i] = parallel Multiplexor2();
    choose_phase1[i].in[0] <-- exp_chaff_phase1[i].out;
    choose_phase1[i].in[1] <-- exp_phase1[i].out;
    choose_phase1[i].sel <-- can_see.out[i];
    phase1_output[i] <-- choose_phase1[i].out;
  }
  // Hash de chaque case
  for (var i = 0; i < state_size; i++) { log(hashed_idents[i][0],hashed_idents[i][1]); }
  // Sortie
  for (var i = 0; i < state_size; i++) { log(phase1_output[i][0],phase1_output[i][1]); }
}
