pragma circom 2.1.8;

// Modules
include "functions.circom";
include "regles.circom";
include "exchange.circom";
include "sponge.circom";

// Commande finale : compilation
// Penser à utiliser le flag -l pour aller chercher circomlib !
// Tout V :
// circom -l ../circomlib/circuits circuit.circom --r1cs --wasm --sym --c
// Actuelle V :
// circom -l ../circomlib/circuits circuit.circom --r1cs --sym --c
// Commande finale : calcul de témoin et passage vers json
// snarkjs wc circuit_js/circuit.wasm input.json witness.wtns && snarkjs wej witness.wtns witness.json
// Commande finale : vérification de témoin
// snarkjs wchk circuit.r1cs witness.wtns
// Ce témoin nous permet de réaliser les calculs

// Pour le setup, les trusted strings sont ici
// https://github.com/iden3/snarkjs?tab=readme-ov-file#7-prepare-phase-2
// J'en utilise un pour 1M contraintes max puisqu'on en a pour l'instant 725282
// Ensuite on run
// snarkjs plonk setup circuit.r1cs [trusted_setup].ptau circuit_final.zkey
// snarkjs zkey export verificationkey circuit_final.zkey verification_key.json

// ^ Bon, ça marche pas, fallback vers Groth, pour lequel il faut un setup
// supplémentaire sur la clé, le setup a pris 30 minutes damn.

// Et enfin on fait la preuve
// snarkjs plonk prove circuit_final.zkey witness.wtns proof.json public.json
// Et on la vérifie
// snarkjs plonk verify verification_key.json public.json proof.json

// Pour la mise à jour de la vision à chaque mouvement, il faudrait faire du
// mouvement-par-mouvement...
// En attendant, il convient de jouer avec l'option "différer la mise à jour du
// voile"

/* Système de règles
Chaque case contient les informations suivantes :
[type_unite, HP, etat_village, déplacement_restant]
Le type_unite d'une case vide est 0, le chef a un type séparé
etat_village correspond à si le village en dessous est possédé
EN ENTREE PAS DE DÉPLACEMENT_RESTANT, on l'ajoute en première passe
N'entre pas non plus dans le hash de sortie, puisqu'on a déjà l'assurance qu'on
a respecté les règles
Le tableau supplémentaire contient les informations suivantes :
[argent_possede, villages_possédés, upkeep_accumulé]

Chaque unité a des points de mouvement, et peut se déplacer d'autant de cases
(ou bien moins dans des terrains accidentés, à voir). Une seule troupe par case.
Une troupe ne peut attaquer qu'une troupe voisine, une fois par tour. Le combat
tient alors sur de la randomness qu'on va pour l'instant éliminer (plein de
choses intéressantes à raconter dessus).
Il faut aussi prouver la prise en compte des actions adverses, et qui sont
souvent des trucs publics... On peut ajouter un masque public / des actions
publiques qu'on prouve être exécutées. On va pour l'instant utiliser le système
d'actions adverses à exécuter en début de tour.
La monnaie est obtenue en début de tour pour chaque village occupé (système un
peu étrange par rapport aux RTS, mais bon)

Actions contiennent donc un type, et des informations supplémentaires :
- 0 : pass
- 1 : move, avec la case d'origine, et la case d'arrivée (pas besoin de plus
  pour l'instant semble-t-il) (doivent être non vides)
- 2 : prendre le village (besoin d'être explicité, comme ça c'est plus pratique)
  En première position, la case sur laquelle est le village, et en deuxième
  position, son numéro de village dans le tableau des villages
- 3 : recruter une unité, depuis un chateau, à une case vide du chateau, d'un certain
  type, et payer son prix pour la faire apparaître

Comme on est obligés de capturer en bougeant sur le village, l'action 2 fait les
deux à la fois alors que l'action 1 ne fait que bouger.
De plus, l'action 2 force le personnage à s'arrêter.
[type, origine_move_x, origine_move_y, destination_move_x, destination_move_y, num_village,
  chateau_apparition, unite_appelée]
Quand une valeur n'est pas remplie, elle doit être à une valeur par défaut,
suivant les valeurs suivantes :
[0, -1, -1, -1, -1, -1, -1, -1]
TODO : on ignore pour l'instant l'impossibilité de s'arrêter dans un village
sans le capturer

Attaquer les troupes peut se faire en clair dans ce jeu, puisque toutes les
troupes voient autour d'elles ! (sauf si blinded existe, auquel cas il faut le
traiter séparément avec une "attaque aveugle").

Ainsi, la liste des actions adverses contient les attaques reçues en clair au
dernier tour (dommage, c'est sur des unités visibles ...) et l'enlèvement des
villages pris par l'adversaire.

COMMENT BIEN ENVOYER LES VILLAGES PRÉCÉDEMMENT ADVERSES PRIS ?
On doit envoyer dans la vision les villages qu'on a, et on met la notification
si le village qu'on prend était l'un de ceux de l'adversaire. (On peut mettre ça
dans l'état, à des cases supplémentaires, qu'on ne voit que si on a déjà vu la
case).

Pour gérer les unités visibles, on peut faire l'optimisation de "ce qu'on sait
qui est vu"
*/

// TODO : plus de vision sur les tours de garde ?

// À cause de la difficulté "d'accéder" à une position inconnue d'un tableau
// (qui est nécessairement avec des contraintes linéaires en le tableau, ce qui
// donnerait un algorithme de vérification avec les viewers donnés en
// state_size ** 2), la meilleure solution est, en donnant la taille maximale de
// la vision d'une unité, de construire des contraintes sur chaque case de
// can_see pour vérifier que quelqu'un puisse voir autour, donnant un nombre de
// contraintes en state_size * (max_vision ** 2).
// Donner en entrée le tableau final de vision accélère le calcul du témoin (en
// enlevant un calcul), mais guère quoi que ce soit d'autre, donc son utilité
// est remise en cause en tant qu'entrée

/* Chateaux et donjons pour le recrutement
donjons contient les positions de chaque donjon, les endroits depuis lesquels on
peut mettre son commandant pour faire le recrutement, et contiennent chacun la
position
chateaux contient à chaque case, indexée par un numéro qui identifie la case de
chateau :
[donjon_attaché, position]

Pour recruter, il est donc nécessaire d'avoir son chef dans le donjon
correspondant au chateau où on fait le recrutement, et on peut alors payer le
prix de la troupe pour la faire apparaître sur la case, à full health et qui ne
peut pas bouger.
*/

template Final(state_size, state_height, state_width, actions_size, enum_tag, enum_data,
  nb_villages, pos_villages, nb_troupes, hp_troupes, range_troupes, prix_troupes,
  nb_donjons, donjons, nb_chateaux, chateaux) {
  assert(state_size == state_height * state_width);
  var max_radius = tabmax(nb_troupes, range_troupes);
  // La troupe 1 correspond au chef

  // Les deux entrées sont
  // - le hash de l'état actuel
  // - la chaîne actuelle
  // Le hash est seulement long de un
  signal input step_in[2];
  signal output step_out[2];

  /* Entrées qui seront privées
  * Chaque case contient les informations suivantes :
  * [type_unite, HP, état_village, range_restante]
  * Le tableau supplémentaire contient les informations suivantes :
  * [argent_possede, villages_possédés, upkeep_accumulé] */
  signal input prev_state[state_size][4];
  signal input prev_misc_state[3];
  // 10 actions avec l'encodage
  // Le batching d'actions est fait dans ce prototype, à voir s'il est conservé
  // dans l'un ou l'autre des jeux
  signal input actions[actions_size][8];
  // En binaire, inversibles de l'ordre de la courbe
  signal input phase1_exponents[state_size][254];
  signal input phase2_exponent[254];

  // TODO: Prendre en entrée captures et actions_captures comme des entiers afin
  // de baisser le nombre d'entrées ?
  /* Entrées publiques, qui sont accumulées dans la chaîne */
  // Actions adverses
  signal input degats[state_size];
  signal input captures[nb_villages];
  /* Entrées adverses publiques */
  signal input phase1_received[state_size][2]; // Points
  /* On peut faire confiance aux joueurs pour énoncer les villages possédés par
   * l'adversaire qu'ils capturent : en effet, s'ils l'énoncent alors que
   * l'adversaire ne l'a pas, il font fuir de l'information; s'ils ne l'énoncent
   * pas alors que l'adversaire l'a, celui-ci continue à toucher de l'argent sur
   * ce village.*/
   // On doit donc vérifier que les éléments de ce tableau sont bien capturés
  signal input actions_captures[nb_villages];
  /* Sorties, qu'on accumule de même dans la chaîne
     On vérifie par des contraintes qu'il s'agit bien du résultat produit */
  signal phase1_output[state_size][2]; // Points
  signal phase2_dh_output[state_size][2]; // Points
  signal phase2_hidden_tags[state_size][2]; // Points
  // ^ Addition des points
  signal phase2_hidden_data[state_size][3][64]; // 64 Bits chacun
  // ^ XOR des data

  var chain_len = 1 // Le hash précédent
    + state_size // Les dégâts reçus
    + nb_villages // Les captures reçues (booléens)
    + state_size * 2 // DH de phase 1 reçu par phase1_received
    + nb_villages // Les villages qu'on capture (booléens)
    + state_size * 2 // DH de phase 1 envoyé
    + state_size * 2 // DH de phase 2 répondu
    + state_size * 2 // Tags de la PSI
    + state_size * 3 * 64 // Data de la PSI (booléens)
    ;

  // Version compressée en passant des booléen aux entiers
  var chain_len_compr = 1 // Le hash précédent
    + state_size // Les dégâts reçus
    + 1 // Les captures reçues (booléens)
    + state_size * 2 // DH de phase 1 reçu par phase1_received
    + 1 // Les villages qu'on capture (booléens)
    + state_size * 2 // DH de phase 1 envoyé
    + state_size * 2 // DH de phase 2 répondu
    + state_size * 2 // Tags de la PSI
    + state_size * 1 // Data de la PSI (booléens)
    ;

  /* Vérifications de cohérence de l'état précédent */
  component hash_prev = AnemoiSponge127((state_size * 4) + 3);
  for (var i = 0; i < state_size; i++) {
    hash_prev.in[i * 4 + 0] <== prev_state[i][0];
    hash_prev.in[i * 4 + 1] <== prev_state[i][1];
    hash_prev.in[i * 4 + 2] <== prev_state[i][2];
    hash_prev.in[i * 4 + 3] <== prev_state[i][3];
  }
  hash_prev.in[state_size * 4 + 0] <== prev_misc_state[0];
  hash_prev.in[state_size * 4 + 1] <== prev_misc_state[1];
  hash_prev.in[state_size * 4 + 2] <== prev_misc_state[2];
  step_in[0] === hash_prev.out;

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
    nokill[i].in[0] <== prev_state[i][1];
    nokill[i].in[1] <== degats[i];
    degats_state[i][0] <== prev_state[i][0] * nokill[i].out;
    degats_state[i][1] <== nokill[i].out * (prev_state[i][1] - degats[i]);
    var ind = indexof(i, nb_villages, pos_villages);
    if (ind != -1) {
      degats_state[i][2] <== (1 - captures[ind]) * prev_state[i][2];
    } else {
      degats_state[i][2] <== 0;
    }
    degats_state[i][3] <== nokill[i].out * prev_state[i][3];
    // On vérifie si la troupe morte faisait payer de l'upkeep
    // TODO: On admet ici que la seule troupe loyale est le commandant
    // Les troupes loyales sont celles qui ne paient pas d'upkeep, qui est de 1
    // pour toutes les troupes puisqu'elles sont toutes de niveau 1
    // TODO: Niveau des unités
    if (i == 0) {
      loyal[0] = IsZero();
      // 1 si la troupe est loyale ou s'il n'y a pas de troupes
      loyal[0].in <== degats_state[0][0] * (1 - degats_state[0][0]);
      // degats_state_upkeep[0] <== prev_misc_state[2] - (1 - nokill[0]) * (1 - loyal[0].out);
      degats_state_upkeep[0] <== prev_misc_state[2] - (1 - loyal[0].out) + nokill[0].out * (1 - loyal[0].out);
    } else {
      loyal[i] = IsZero();
      loyal[i].in <== degats_state[i][0] * (1 - degats_state[i][0]);
      degats_state_upkeep[i] <== degats_state_upkeep[i - 1] - (1 - loyal[i].out) + nokill[i].out * (1 - loyal[i].out);
    }
  }

  // Pertes de villages dans le compte
  signal pertes_villages[nb_villages];
  pertes_villages[0] <== captures[0];
  for (var vill = 1; vill < nb_villages; vill++) {
    pertes_villages[vill] <== pertes_villages[vill - 1] + captures[vill];
  }

  /* Obtention dès maintenant du déplacement de chaque case */
  component range_unit[state_size];
  for (var i = 0; i < state_size; i++) {
    range_unit[i] = VillagePos(nb_troupes,range_troupes);
    range_unit[i].index <== degats_state[i][0];
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
    au_repos[i].in[0] <== degats_state[i][3];
    au_repos[i].in[1] <== range_unit[i].out;

    full_heal[i] = LessThan(64);
    max_health[i] = VillagePos(nb_troupes, hp_troupes);
    max_health[i].index <== degats_state[i][0];
    if (est_village) {
      full_heal[i].in[0] <== degats_state[i][1] + 8 + au_repos[i].out * 2;
      full_heal[i].in[1] <== max_health[i].out;

      final_state[i] <== max_health[i].out +
        full_heal[i].out * (degats_state[i][1] + 8 + (au_repos[i].out * 2) - max_health[i].out);
    } else {
      full_heal[i].in[0] <== degats_state[i][1] + au_repos[i].out * 2;
      full_heal[i].in[1] <== max_health[i].out;

      final_state[i] <== max_health[i].out +
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
  pay_upkeep.in[0] <== prev_misc_state[1] - pertes_villages[nb_villages - 1];
  pay_upkeep.in[1] <== degats_state_upkeep[state_size - 1];
  // TODO : ON PEUT AVOIR DES DETTES, CETTE VERSION TE FERA MOURIR SI TU PAIES
  // PAS TES DETTES POUR L'INSTANT ET C'EST TOUT
  // Gérer avec un flag ?
  component floor_zero = LessThan(64); // 1 si on peut payer sans tomber dans le rouge
  floor_zero.in[0] <== pay_upkeep.out * (degats_state_upkeep[state_size - 1] - (prev_misc_state[1] - pertes_villages[nb_villages - 1]));
  floor_zero.in[1] <== prev_misc_state[0] + 2 + prev_misc_state[1] - pertes_villages[nb_villages - 1];
  degats_money <== prev_misc_state[0] + 2 + prev_misc_state[1] - pertes_villages[nb_villages - 1] - pay_upkeep.out * (degats_state_upkeep[state_size - 1] - (prev_misc_state[1] - pertes_villages[nb_villages - 1]));
  final_money <== floor_zero.out * degats_money;

  /* Hachage des cases
  Tableau statique, que j'espère voir optimisé dans le produit final
  TODO: rendre statique ?
  -> Peut être inlined en réutilisant ceux déjà calculés
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
  for (var i = 0; i < state_size; i++) { phase1.hashed_idents[i] <== hashed_idents[i].out; }
  phase1.phase1_exponents <== phase1_exponents;

  /* Application des actions */
  // On enregistre ici les valeurs qui seront entrées pour les calculs après le
  // prétraitement.
  // Pour un TRPG, il est nécessaire d'utiliser des tableaux successifs pour les
  // actions qui ne sont pas parallèles et sont en dépendance temporelle
  // V Première action
  component application0 = Regles(state_size, state_height, state_width, nb_villages, pos_villages, nb_troupes, hp_troupes, prix_troupes, nb_donjons, donjons, nb_chateaux, chateaux);
  for (var i = 0; i < state_size; i++) {
    // Type de l'unité
    application0.prev_state[i][0] <== degats_state[i][0];
    // HP de l'unité
    application0.prev_state[i][1] <== final_state[i];
    // État du village
    application0.prev_state[i][2] <== degats_state[i][2];
    // Range de l'unité (remise à son maximum)
    application0.prev_state[i][3] <== range_unit[i].out;
    phase1.sightrange[i] <== range_unit[i].out;
  }
  // En ajoutant l'argent gagné avec les villages
  application0.prev_misc_state[0] <== final_money;
  // En retirant les villages perdus
  application0.prev_misc_state[1] <== prev_misc_state[1] - pertes_villages[nb_villages - 1];
  // Upkeep actuel
  application0.prev_misc_state[2] <== degats_state_upkeep[state_size - 1];
  application0.action <== actions[0];
  /* États successifs par application des actions, dont l'état final */
  signal etapes[actions_size][state_size][4];
  signal etapes_misc[actions_size][3];
  etapes[0] <== application0.next_state;
  etapes_misc[0] <== application0.next_misc_state;

  // On termine la phase 1 de l'échange
  phase1_output <== phase1.phase1_output;

  // Suite des actions
  component applications[actions_size - 1];
  for (var j = 1; j < actions_size; j++) {
    applications[j - 1] = Regles(state_size, state_height, state_width, nb_villages, pos_villages, nb_troupes, hp_troupes, prix_troupes, nb_donjons, donjons, nb_chateaux, chateaux);
    applications[j - 1].prev_state <== etapes[j - 1];
    applications[j - 1].prev_misc_state <== etapes_misc[j - 1];
    applications[j - 1].action <== actions[j];
    etapes[j] <== applications[j - 1].next_state;
    etapes_misc[j] <== applications[j - 1].next_misc_state;
  }

  // Vérification que les villages annoncés sont bien possédés
  for (var vill = 0; vill < nb_villages; vill++) {
    // Contrainte de "actions_captures[vill] => village possédé"
    // C'est un "non a ou b"
    (1 - actions_captures[vill]) + etapes[actions_size - 1][pos_villages[vill]][2] - (1 - actions_captures[vill]) * etapes[actions_size - 1][pos_villages[vill]][2] === 1;
  }

  /* Vérifications de cohérence du nouvel état */
  component hash_next = AnemoiSponge127((state_size * 4) + 3);
  for (var i = 0; i < state_size; i++) {
    hash_next.in[i * 4 + 0] <== etapes[actions_size - 1][i][0];
    hash_next.in[i * 4 + 1] <== etapes[actions_size - 1][i][1];
    hash_next.in[i * 4 + 2] <== etapes[actions_size - 1][i][2];
    hash_next.in[i * 4 + 3] <== etapes[actions_size - 1][i][3];
  }
  hash_next.in[state_size * 4 + 0] <== etapes_misc[actions_size - 1][0];
  hash_next.in[state_size * 4 + 1] <== etapes_misc[actions_size - 1][1];
  hash_next.in[state_size * 4 + 2] <== etapes_misc[actions_size - 1][2];
  step_out[0] <== hash_next.out;

  /* Phase 2 de l´échange
  Une fois que l'adversaire nous a envoyé sa phase 1 au tour suivant, on termine
  la preuve en prouvant notre réponse à sa phase 1.
  */
  component phase2 = Phase2(state_size, enum_tag, enum_data);
  for (var i = 0; i < state_size; i++) {
    phase2.hashed_idents[i] <== hashed_idents[i].out;
    phase2.state[i][0] <== etapes[actions_size - 1][i][0];
    phase2.state[i][1] <== etapes[actions_size - 1][i][1];
    phase2.state[i][2] <== etapes[actions_size - 1][i][2];
  }
  phase2.phase2_exponent <== phase2_exponent;
  phase2.phase1_received <== phase1_received;
  phase2_dh_output <== phase2.phase2_dh_output;
  phase2_hidden_tags <== phase2.phase2_hidden_tags;
  phase2_hidden_data <== phase2.phase2_hidden_data;

  // TODO: Attention, ces compressions sont valides uniquement pour nb_villages
  // < 254
  component captures_compr = Bits2Num(nb_villages);
  captures_compr.in <== captures;
  component actions_captures_compr = Bits2Num(nb_villages);
  actions_captures_compr.in <== actions_captures;

  /* Construction de la chaîne
  Un peu simplifiée, si des optimisations sont faites devrait être comme voulu */
  component chain = AnemoiSponge127(chain_len_compr);
  var offset = 0;
  chain.in[offset] <== step_in[1];
  offset++;
  for (var i = 0; i < state_size; i++) {
    chain.in[offset] <== degats[i];
    offset++;
  }
  chain.in[offset] <== captures_compr.out;
  offset++;
  for (var i = 0; i < state_size; i++) {
    chain.in[offset] <== phase1_received[i][0];
    offset++;
    chain.in[offset] <== phase1_received[i][1];
    offset++;
  }
  chain.in[offset] <== actions_captures_compr.out;
  offset++;
  for (var i = 0; i < state_size; i++) {
    chain.in[offset] <== phase1_output[i][0];
    offset++;
    chain.in[offset] <== phase1_output[i][1];
    offset++;
  }
  for (var i = 0; i < state_size; i++) {
    chain.in[offset] <== phase2_dh_output[i][0];
    offset++;
    chain.in[offset] <== phase2_dh_output[i][1];
    offset++;
  }
  for (var i = 0; i < state_size; i++) {
    chain.in[offset] <== phase2_hidden_tags[i][0];
    offset++;
    chain.in[offset] <== phase2_hidden_tags[i][1];
    offset++;
  }
  component phase2_hidden_data_compr[state_size];
  for (var i = 0; i < state_size; i++) {
    phase2_hidden_data_compr[i] = Bits2Num(64 * 3);
    for (var j = 0; j < 3; j++) {
      for (var k = 0; k < 64; k++) {
        phase2_hidden_data_compr[i].in[(j * 64) + k] <== phase2_hidden_data[i][j][k];
      }
    }
    chain.in[offset] <== phase2_hidden_data_compr[i].out;
    offset++;
  }

  step_out[1] <== chain.out;
}

// Plateau 10 x 10 avec 10 actions
// La fonction de hash est Anemoi-sponge avec 127 bits de sécurité (voir le
// fichier)

// Les valeurs sont celles de la carte spéciale, qui ne se joue qu'avec les
// nordiques pour les deux joueurs, avec un guerrier orc comme commandant,
// et les troupes après 1 qui sont dans l'ordre proposé par le jeu
component main {public [step_in]} =
  Final(100, 10, 10, 10, 0, 1,
  8, [50,90,5,45,54,94,9,49], // Villages
  9, // Troupes
    [0,58,32,26,33,38,42,32,18], // HP
    [0,5,5,6,7,5,4,8,5], // Range
    [0,-1,14,17,14,12,13,17,9], // Prix
  2, [0, 99], // Donjons
  6, [[0,1], [0,10], [0,20], [1,89], [1,98], [1,79]]); // Chateaux
// template Final(state_size, state_height, state_width, actions_size, enum_tag, enum_data,
//   nb_villages, pos_villages, nb_troupes, hp_troupes, range_troupes, prix_troupes,
//   nb_donjons, donjons, nb_chateaux, chateaux) {

// TODO: Adapter à Wesnoth, en faisant une map moddée, et avec des actions
// intelligentes et une vision conforme
// TODO: Optimisations : PSI updatable, NOVA, Meilleurs hashs, gestion des
// "actions publiques" ...
// TODO: Version MPC !
// TODO: Réutiliser les calculs dans le witness final ?
