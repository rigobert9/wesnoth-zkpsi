pragma circom 2.1.8;

// Circomlib
include "mux1.circom";
include "mux2.circom";
include "comparators.circom";
// Modules
include "functions.circom";

template Div2() {
  signal input in;
  signal output quotient;
  signal output rest;

  quotient <-- in \ 2;
  rest <-- in % 2;
  // Est-ce que ce check est utile ?
  // Example d'attaque sur modulo 7 : pour 3, on pourrait sortir 1 et 1, ou 4 et 2
  rest * (rest - 1) === 0;
  in === quotient * 2 + rest;
}

template Diff() {
  signal input in1;
  signal input in2;
  signal output out;

  // Devrait suffire, limite l'entrée à un nombre à 32 bits
  component sign = LessThan(32);
  sign.in[0] <-- in1;
  sign.in[1] <-- in2;

  signal diff0;
  diff0 <-- (1 - sign.out) * (in1 - in2);
  signal diff1;
  diff1 <-- sign.out * (in2 - in1);

  out <-- diff0 + diff1;
}

template Distance() {
  signal input in1[2];
  signal input in2[2];
  signal output out;

  component div1 = Div2();
  div1.in <-- in1[0];
  component div2 = Div2();
  div2.in <-- in2[0];

  // Les secondes coordonnées
  component ax1 = Div2();
  ax1.in <-- in1[1] + 2 * div1.quotient;
  component ax2 = Div2();
  ax2.in <-- in2[1] + 2 * div2.quotient;

  component qdiff = Diff();
  qdiff.in1 <-- in1[0];
  qdiff.in2 <-- in2[0];
  component rdiff = Diff();
  rdiff.in1 <-- ax1.quotient;
  rdiff.in2 <-- ax2.quotient;
  component sumdiff = Diff();
  sumdiff.in1 <-- in1[0] + ax1.quotient;
  sumdiff.in2 <-- in2[0] + ax2.quotient;

  component dist = Div2();
  dist.in <-- qdiff.out + sumdiff.out + rdiff.out;
  out <-- dist.quotient;
}

// Impossible de faire mieux ?
// Marche que pour des arrays plus grands que 3
template Extract(array_size, subarray_size) {
  signal input array[array_size][subarray_size];
  signal input index;
  signal inter[array_size - 1][subarray_size];
  signal output out[subarray_size];

  component is_index[array_size];
  is_index[0] = IsZero();
  is_index[0].in <-- index;
  for (var j = 0; j < subarray_size; j++) {
    inter[0][j] <-- array[0][j] * is_index[0].out;
  }
  for (var i = 1; i < array_size - 1; i++) {
    is_index[i] = IsZero();
    is_index[i].in <-- index - i;
    for (var j = 0; j < subarray_size; j++) {
      inter[i][j] <-- inter[i - 1][j] + is_index[i].out * array[i][j];
    }
  }
  is_index[array_size - 1] = IsZero();
  is_index[array_size - 1].in <-- index - array_size + 1;
  for (var j = 0; j < subarray_size; j++) {
    out[j] <-- inter[array_size - 2][j] + is_index[array_size - 1].out * array[array_size - 1][j];
  }
}

// Marche que pour des tableaux de taille 3 ou plus !
template VillagePos(nb_villages, pos_villages) {
  signal input index;
  signal output out;

  signal acc[nb_villages - 2];
  component is_index[nb_villages];

  is_index[0] = IsEqual();
  is_index[0].in[0] <-- 0;
  is_index[0].in[1] <-- index;
  is_index[1] = IsEqual();
  is_index[1].in[0] <-- 1;
  is_index[1].in[1] <-- index;
  acc[0] <-- is_index[0].out * pos_villages[0] + is_index[1].out * pos_villages[1];

  for (var i = 2; i < nb_villages - 1; i++) {
    is_index[i] = IsEqual();
    is_index[i].in[0] <-- i;
    is_index[i].in[1] <-- index;
    acc[i - 1] <-- acc[i - 2] + is_index[i].out * pos_villages[i];
  }

  is_index[nb_villages - 1] = IsEqual();
  is_index[nb_villages - 1].in[0] <-- nb_villages - 1;
  is_index[nb_villages - 1].in[1] <-- index;
  out <-- acc[nb_villages - 3] + is_index[nb_villages - 1].out * pos_villages[nb_villages - 1];
}

template ChateauPos(nb_donjons, donjons, nb_chateaux, chateaux) {
  signal input index;
  signal output pos_donjon;
  signal output pos_chateau;

  component is_index[nb_chateaux];
  signal acc_chateau[nb_chateaux - 1];
  signal acc_donjon[nb_chateaux - 1];
  is_index[0] = IsEqual();
  is_index[0].in[0] <-- index;
  is_index[0].in[1] <-- 0;
  acc_chateau[0] <-- is_index[0].out * chateaux[0][1];
  acc_donjon[0] <-- is_index[0].out * donjons[chateaux[0][0]];

  for (var i = 1; i < nb_chateaux - 1; i++) {
    is_index[i] = IsEqual();
    is_index[i].in[0] <-- index;
    is_index[i].in[1] <-- i;
    acc_chateau[i] <-- acc_chateau[i - 1] + is_index[i].out * chateaux[i][1];
    acc_donjon[i] <-- acc_donjon[i - 1] + is_index[i].out * donjons[chateaux[i][0]];
  }

  is_index[nb_chateaux - 1] = IsEqual();
  is_index[nb_chateaux - 1].in[0] <-- index;
  is_index[nb_chateaux - 1].in[1] <-- nb_chateaux - 1;
  pos_chateau <-- acc_chateau[nb_chateaux - 2] + is_index[nb_chateaux - 1].out * chateaux[nb_chateaux - 1][1];
  pos_donjon <-- acc_donjon[nb_chateaux - 2] + is_index[nb_chateaux - 1].out * donjons[chateaux[nb_chateaux - 1][0]];
}

template TroupeInfos(nb_troupes, hp_troupes, prix_troupes) {
  signal input index;
  signal output hp_troupe;
  signal output prix_troupe;

  component is_index[nb_troupes];
  signal acc_hp[nb_troupes - 1];
  signal acc_prix[nb_troupes - 1];
  is_index[0] = IsEqual();
  is_index[0].in[0] <-- index;
  is_index[0].in[1] <-- 0;
  acc_hp[0] <-- is_index[0].out * hp_troupes[0];
  acc_prix[0] <-- is_index[0].out * prix_troupes[0];

  for (var i = 1; i < nb_troupes - 1; i++) {
    is_index[i] = IsEqual();
    is_index[i].in[0] <-- index;
    is_index[i].in[1] <-- i;
    acc_hp[i] <-- acc_hp[i - 1] + is_index[i].out * hp_troupes[i];
    acc_prix[i] <-- acc_prix[i - 1] + is_index[i].out * prix_troupes[i];
  }

  is_index[nb_troupes - 1] = IsEqual();
  is_index[nb_troupes - 1].in[0] <-- index;
  is_index[nb_troupes - 1].in[1] <-- nb_troupes - 1;
  hp_troupe <-- acc_hp[nb_troupes - 2] + is_index[nb_troupes - 1].out * hp_troupes[nb_troupes - 1];
  prix_troupe <-- acc_prix[nb_troupes - 2] + is_index[nb_troupes - 1].out * prix_troupes[nb_troupes - 1];
}

template Regles(state_size, state_height, state_width, nb_villages, pos_villages,
  nb_troupes, hp_troupes, prix_troupes, nb_donjons, donjons, nb_chateaux, chateaux) {
  signal input prev_state[state_size][4];
  signal input prev_misc_state[3];
  signal input action[8];
  signal output next_state[state_size][4];
  signal output next_misc_state[3];

  // Bounds des mouvements
  component bounds_depart = LessThan(252);
  bounds_depart.in[0] <-- action[1] * state_width + action[2];
  bounds_depart.in[1] <-- state_size;
  component bounds_arrivee = LessThan(252);
  bounds_arrivee.in[0] <-- action[3] * state_width + action[4];
  bounds_arrivee.in[1] <-- state_size;
  // Accrochage des bounds
  component action_type1 = IsEqual();
  action_type1.in[0] <-- 1;
  action_type1.in[1] <-- action[0];
  action_type1.out * (2 - bounds_depart.out - bounds_arrivee.out) === 0;

  // Bounds des villages (accrochée plus bas)
  component bounds_capture = LessThan(252);
  bounds_capture.in[0] <-- action[5];
  bounds_capture.in[1] <-- nb_villages;

  component dist = Distance();
  dist.in1[0] <-- action[1];
  dist.in1[1] <-- action[2];
  dist.in2[0] <-- action[3];
  dist.in2[1] <-- action[4];

  // On obtient la case concernée avec les deux coordonnées
  signal position_depart;
  position_depart <-- action[1] * state_width + action[2];
  signal position_arrivee;
  position_arrivee <-- action[3] * state_width + action[4];
  component position_capture = VillagePos(nb_villages, pos_villages);
  position_capture.index <-- action[5];

  component unite_action = Extract(state_size, 3);
  for (var i = 0; i < state_size; i++) {
    unite_action.array[i][0] <-- prev_state[i][0];
    unite_action.array[i][1] <-- prev_state[i][1];
    unite_action.array[i][2] <-- prev_state[i][3];
  }
  unite_action.index <-- position_depart;

  // Le paramètre est le nombre de bits des arguments
  // 64 devrait être OK pour ce qui est à l'intérieur des cases de l'état
  component contrainte_move = LessThan(64);
  // Vérification de la distance de mouvement
  contrainte_move.in[0] <-- dist.out;
  contrainte_move.in[1] <-- unite_action.out[2]; // Déplacement restant

  // Flags, suffisants ici pour faire les switchings
  // entre les codes d'action
  // En réalité, les checks suivants suffisent comme flag pour identifier les
  // moves
  component action_type2 = IsEqual();
  action_type2.in[0] <-- 2;
  action_type2.in[1] <-- action[0];
  // Accrochage de la bound sur les villages
  action_type2.out * (1 - bounds_capture.out) === 0;

  /* Changements si on n'appelle pas une nouvelle unité */
  signal next_state_if_not_depart[state_size][3];
  // Ne contient pas les villages, ni le déplacement, qui ne sont pas affectés
  // par un appel
  signal next_state_if_no_summon[state_size][2];
  component est_depart[state_size];
  component est_destination[state_size];
  component est_capture[state_size];
  for (var i = 0; i < state_size; i++) {
    // Concerné par un move ?
    est_depart[i] = parallel IsEqual();
    est_depart[i].in[0] <-- i;
    est_depart[i].in[1] <-- position_depart;
    est_destination[i] = parallel IsEqual();
    est_destination[i].in[0] <-- i;
    est_destination[i].in[1] <-- position_arrivee;
    // Les mouvements doivent être non nuls
    // Si la case est la destination, elle doit être vide (on vérifie via le
    // type)
    // N'est pas triggered si on ne fait pas un déplacement, car ces cases
    // devront être à -1
    est_destination[i].out * prev_state[i][0] === 0;
    // Concerné par une capture ?
    est_capture[i] = parallel IsEqual();
    est_capture[i].in[0] <-- i;
    est_capture[i].in[1] <-- position_capture.out;

    // Type de la case, changé uniquement par un mouvement
    next_state_if_not_depart[i][0] <--
    /* Les expression de cette forme ne sont pas quadratique
    // Mais on peut les transformer comme ci-dessous
      (1 - est_destination[i].out) * prev_state[i][0]
      + est_destination[i].out * unite_action.out[0];
    */
      prev_state[i][0] + est_destination[i].out * (unite_action.out[0] - prev_state[i][0]);
    next_state_if_no_summon[i][0] <-- (1 - est_depart[i].out) * next_state_if_not_depart[i][0];

    // HP de la case, changé uniquement par un mouvement
    next_state_if_not_depart[i][1] <--
      prev_state[i][1] + est_destination[i].out * (unite_action.out[0] - prev_state[i][1]);
    next_state_if_no_summon[i][1] <-- (1 - est_depart[i].out) * next_state_if_not_depart[i][1];

    // État du village sur la case : à changer selon le village pris s'il y en a un
    /* Non quadratique !
    next_state_if_no_summon[i][3] <-- (1 - est_capture[i].out) * prev_state[i][3] + est_capture[i].out * action_type2.out;
    */
    next_state[i][2] <-- prev_state[i][2] + est_capture[i].out * (action_type2.out - prev_state[i][2]);

    // Mouvement de la case, changé uniquement par un mouvement, retire les
    // points de fatigue
    /*
      (1 - est_destination[i].out) * prev_state[i][2]
      + est_destination[i].out * (unite_action.out[0] - dist.out);
    */
    next_state_if_not_depart[i][2] <--
      prev_state[i][3] + est_destination[i].out * (unite_action.out[0] - dist.out - prev_state[i][3]);
    next_state[i][3] <-- (1 - est_depart[i].out) * next_state_if_not_depart[i][2];
  }

  // Changement sur le misc : ajout de villages possédés
  next_misc_state[1] <-- prev_misc_state[1] + action_type2.out * 1;

  /* Appel d'une unité
  On obtient le prix et les HP de l'unité après avoir vérifié que le chef est
  présent dans le donjon */

  // Bounds des chateaux et unités (accrochées plus bas)
  component bounds_chateau = LessThan(252);
  bounds_chateau.in[0] <-- action[6];
  bounds_chateau.in[1] <-- nb_chateaux;
  component bounds_troupe = LessThan(252);
  bounds_troupe.in[0] <-- action[7];
  bounds_troupe.in[1] <-- nb_troupes;
  component action_type3 = IsEqual();
  action_type3.in[0] <-- action[0];
  action_type3.in[1] <-- 3;
  // Accrochage des bounds
  action_type3.out * (2 - bounds_chateau.out - bounds_troupe.out) === 0;

  component chateau_pos = ChateauPos(nb_donjons, donjons, nb_chateaux, chateaux);
  chateau_pos.index <-- action[6];
  component troupe_infos = TroupeInfos(nb_troupes, hp_troupes, prix_troupes);
  troupe_infos.index <-- action[7];

  component est_donjon[state_size];
  component est_chateau[state_size];
  signal donjon_concerne[state_size];
  signal chateau_concerne[state_size];
  for (var i = 0; i < state_size; i++) {
    est_donjon[i] = IsEqual();
    est_donjon[i].in[0] <-- chateau_pos.pos_donjon;
    est_donjon[i].in[1] <-- i;
    est_chateau[i] = IsEqual();
    est_chateau[i].in[0] <-- chateau_pos.pos_chateau;
    est_chateau[i].in[1] <-- i;

    // Vérification que le chef soit bien sur le donjon si on fait un appel
    donjon_concerne[i] <-- action_type3.out * est_donjon[i].out;
    donjon_concerne[i] * (1 - next_state_if_no_summon[i][0]) === 0;
    // Vérification que le chateau d'arrivée est vide, 1 s'il y a un problème
    chateau_concerne[i] <-- action_type3.out * est_chateau[i].out;
    chateau_concerne[i] * next_state_if_no_summon[i][0] === 0;

    // Type de la case
    next_state[i][0] <-- next_state_if_no_summon[i][0] + chateau_concerne[i] * action[7];

    // HP de la case
    next_state[i][1] <-- next_state_if_no_summon[i][1] + chateau_concerne[i] * troupe_infos.hp_troupe;
  }

  // Changements dans le misc
  // Il faut assez d'argent pour acheter !
  component can_afford = LessEqThan(64);
  can_afford.in[0] <-- action_type3.out * troupe_infos.prix_troupe;
  can_afford.in[1] <-- prev_misc_state[0];
  can_afford.out === 1;
  next_misc_state[0] <-- prev_misc_state[0] - troupe_infos.prix_troupe;
  // TODO: Aucune troupe à part le chef n'est loyale, donc on ajoute toujours
  // à l'upkeep
  next_misc_state[2] <-- prev_misc_state[2] + action_type3.out;
}
