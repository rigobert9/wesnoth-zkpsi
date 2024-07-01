pragma circom 2.1.8;

// Modules
include "functions.circom";
include "regles.circom";
include "exchange.circom";

template Final(state_size, state_height, state_width, actions_size, enum_tag, enum_data, mimc_hash_size,
  nb_villages, pos_villages, nb_troupes, hp_troupes, range_troupes, prix_troupes,
  nb_donjons, donjons, nb_chateaux, chateaux) {
  assert(state_size == state_height * state_width);
  var max_radius = tabmax(nb_troupes, range_troupes);
  // La troupe 1 correspond au chef

  /* Entrées qui seront privées
  * Chaque case contient les informations suivantes :
  * [type_unite, HP, état_village, range_restante]
  * Le tableau supplémentaire contient les informations suivantes :
  * [argent_possede, villages_possédés, upkeep_accumulé] */
  signal input prev_state[state_size][4];
  signal input prev_misc_state[3];
  // Actions adverses
  signal input degats[state_size];
  signal input captures[nb_villages];
  signal input phase1_exponents[state_size][254]; // En binaire
  signal output phase1_output[state_size][2]; // Points

  /* Application des actions adverses */
  /* L'adversaire envoie des actions qui sont les contrats à ajouter.
  On considère que ces sont des actions déjà valides, et pas besoin de les faire
  séquentiellement.
  Il s'agit donc d'un tableau de state_size, avec un nombre positif pour des
  dégâts reçus*/
  signal degats_state[state_size][4];
  component nokill[state_size];
  component loyal[state_size];
  signal degats_state_upkeep[state_size]; // L'upkeep restant
  for (var i = 0; i < state_size; i++) {
    nokill[i] = GreaterThan(64); // 1 si la troupe ne meurt pas
    nokill[i].in[0] <-- prev_state[i][1];
    nokill[i].in[1] <-- degats[i];
    degats_state[i][0] <-- prev_state[i][0] * nokill[i].out;
    degats_state[i][1] <-- nokill[i].out * (prev_state[i][0] - degats[i]);
    var ind = indexof(i, nb_villages, pos_villages);
    if (ind != -1) {
      degats_state[i][2] <-- (1 - captures[ind]) * prev_state[i][2];
    } else {
      degats_state[i][2] <-- 0;
    }
    degats_state[i][3] <-- nokill[i].out * prev_state[i][3];
    // On vérifie si la troupe morte faisait payer de l'upkeep
    // TODO: On admet ici que la seule troupe loyale est le commandant
    // Les troupes loyales sont celles qui ne paient pas d'upkeep, qui est de 1
    // pour toutes les troupes puisqu'elles sont toutes de niveau 1
    // TODO: Niveau des unités
    if (i == 0) {
      loyal[0] = IsZero();
      // 1 si la troupe est loyale ou s'il n'y a pas de troupes
      loyal[0].in <-- degats_state[0][0] * (1 - degats_state[0][0]);
      // degats_state_upkeep[0] <-- prev_misc_state[2] - (1 - nokill[0]) * (1 - loyal[0].out);
      degats_state_upkeep[0] <-- prev_misc_state[2] - (1 - loyal[0].out) + nokill[0].out * (1 - loyal[0].out);
    } else {
      loyal[i] = IsZero();
      loyal[i].in <-- degats_state[i][0] * (1 - degats_state[i][0]);
      degats_state_upkeep[i] <-- degats_state_upkeep[i - 1] - (1 - loyal[i].out) + nokill[i].out * (1 - loyal[i].out);
    }
  }

  // Pertes de villages dans le compte
  signal pertes_villages[nb_villages];
  pertes_villages[0] <-- captures[0];
  for (var vill = 1; vill < nb_villages; vill++) {
    pertes_villages[vill] <-- pertes_villages[vill - 1] + captures[vill];
  }

  /* Obtention dès maintenant du déplacement de chaque case */
  component range_unit[state_size];
  for (var i = 0; i < state_size; i++) {
    range_unit[i] = VillagePos(nb_troupes,range_troupes);
    range_unit[i].index <-- degats_state[i][0];
  }

  /* Soin dans les villages en début de tour
  Une unité est soignée passivement de :
  - 8 points de vie en début de tour si elle est dans un village
  - 2 points de vie en début de tour si elle n'a pas bougé pendant le dernier
    tour
  */
  signal final_state[state_size];
  component au_repos[state_size];
  component max_health[state_size];
  component full_heal[state_size];
  for (var i = 0; i < state_size; i++) {
    // L'unité est dans un village
    var vill = indexof(i,nb_villages,pos_villages);
    var est_village = vill != -1 ? 1 : 0;
    // L'unité n'a pas bougé au dernier au dernier tour
    au_repos[i] = IsEqual();
    au_repos[i].in[0] <-- degats_state[i][3];
    au_repos[i].in[1] <-- range_unit[i].out;

    full_heal[i] = LessThan(64);
    max_health[i] = VillagePos(nb_troupes, hp_troupes);
    max_health[i].index <-- degats_state[i][0];
    if (est_village) {
      full_heal[i].in[0] <-- degats_state[i][1] + 8 + au_repos[i].out * 2;
      full_heal[i].in[1] <-- max_health[i].out;

      final_state[i] <-- max_health[i].out +
        full_heal[i].out * (degats_state[i][1] + 8 + (au_repos[i].out * 2) - max_health[i].out);
    } else {
      full_heal[i].in[0] <-- degats_state[i][1] + au_repos[i].out * 2;
      full_heal[i].in[1] <-- max_health[i].out;

      final_state[i] <-- max_health[i].out +
        full_heal[i].out * (degats_state[i][1] +  (au_repos[i].out * 2) - max_health[i].out);
    }
  }

  /* Gain de monnaie (villages) et pertes (entretien)
     """
     So, the formula for determining the income per turn is

     2 + villages − maximum(0, upkeep − villages) where upkeep is equal to the
     sum of the levels of all your non-loyal units.

     If the upkeep cost is greater than the number of villages+2 then the side
     starts losing gold, if it is equal, no income is gained or lost.
     """
  */
  signal final_money;
  signal degats_money;
  component pay_upkeep = LessThan(64); // 1 si on paie l'upkeep
  pay_upkeep.in[0] <-- prev_misc_state[1] - pertes_villages[nb_villages - 1];
  pay_upkeep.in[1] <-- degats_state_upkeep[state_size - 1];
  // TODO : ON PEUT AVOIR DES DETTES, CETTE VERSION TE FERA MOURIR SI TU PAIES
  // PAS TES DETTES POUR L'INSTANT ET C'EST TOUT
  // Gérer avec un flag ?
  component floor_zero = LessThan(64); // 1 si on peut payer sans tomber dans le rouge
  floor_zero.in[0] <-- pay_upkeep.out * (degats_state_upkeep[state_size - 1] - (prev_misc_state[1] - pertes_villages[nb_villages - 1]));
  floor_zero.in[1] <-- prev_misc_state[0] + 2 + prev_misc_state[1] - pertes_villages[nb_villages - 1];
  degats_money <-- prev_misc_state[0] + 2 + prev_misc_state[1] - pertes_villages[nb_villages - 1] - pay_upkeep.out * (degats_state_upkeep[state_size - 1] - (prev_misc_state[1] - pertes_villages[nb_villages - 1]));
  final_money <-- floor_zero.out * degats_money;

  /* Hachage des cases
  Tableau statique, que j'espère voir optimisé dans le produit final
  TODO: rendre statique !
  */
  component bin_idents[state_size]; // version binaire
  component hashed_idents[state_size]; // Points
  for (var i = 0; i < state_size; i++) {
    bin_idents[i] = parallel Num2Bits(254);
    bin_idents[i].in <== i;
    hashed_idents[i] = parallel Pedersen(254);
    hashed_idents[i].in <== bin_idents[i].out;
  }

  /* Phase 1
  On recalcule ici ce qu'on a envoyé en phase 1 pour le revérifier
  */
  component phase1 = Phase1(state_size, state_height, state_width, max_radius);
  for (var i = 0; i < state_size; i++) { phase1.hashed_idents[i] <-- hashed_idents[i].out; }
  phase1.phase1_exponents <-- phase1_exponents;
  for (var i = 0; i < state_size; i++) {
    phase1.sightrange[i] <-- range_unit[i].out;
  }
  phase1_output <-- phase1.phase1_output;
}

// template Final(state_size, state_height, state_width, actions_size, enum_tag, enum_data, mimc_hash_size,
//   nb_villages, pos_villages, nb_troupes, hp_troupes, range_troupes, prix_troupes,
//   nb_donjons, donjons, nb_chateaux, chateaux) {

component main {public [degats, captures]} = Final(10 * 10, 10, 10 , 10, 0, 1, 64, 8, [50,90,5,45,54,94,9,49], 9, [0,58,32,26,33,38,42,32,18], [0,5,5,6,7,5,4,8,5], [0,-1,14,17,14,12,13,17,9], 2, [0, 99], 6, [[0,1], [0,10], [0,20], [1,89], [1,98], [1,79]]);
