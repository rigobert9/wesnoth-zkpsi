pragma circom 2.1.8;

// Coordonnées du jeu sont en y oscillant et x droit, avec les colonnes impaires
// descendues d'une demi-case : le système odd-q ici de coordonnées
// rectangulaires [x,y]. Les hexagones ont un haut plat.
// Les calculs seront fait avec des coordonnées axiales [q,r].
// Les fonctions de voisinages permettent d'obtenir, dans l'ordre, le voisin
// haut-droit, haut, haut-gauche, bas-gauche, bas, bas-droite

function max(x,y) { return x > y ? x : y; }
function min(x,y) { return x > y ? y : x; }
function abs(x) { return x > 0 ? x : -x; }
function ax_to_rect(c) { return [c[0], (c[1] + (c[0] - (c[0] % 2))) \ 2]; }
function rect_to_ax(c) { return [c[0], (c[1] - (c[0] - (c[0] % 2))) \ 2]; }
function dist_ax(one,two) {
  var qdiff = (one[0] - two[0]);
  var rdiff = (one[1] - two[1]);
  return (abs(qdiff) + abs(qdiff + rdiff) + abs(rdiff)) \ 2;
}

function neighbour_ax(coord, dir) {
  var ax_dirs[6][2] = [
      [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1], [1, 0]
  ];
  return [coord[0] + ax_dirs[dir][0], coord[1] + ax_dirs[dir][1]];
}
function neighbour_rect(coord, dir){
  var rect_dirs[2][6][2] = [
      // even cols
      [[1,-1], [0,-1], [-1,-1], [-1,0], [0,1], [1,0]],
      // odd cols
      [[1,0], [0,-1], [-1,0], [-1,1], [0,1], [1,1]]
  ];
  var is_odd = coord[0] % 2;
  return [coord[0] + rect_dirs[is_odd][dir][0], coord[1] + rect_dirs[is_odd][dir][1]];
}

function nb_neighbours(state_height, state_width, x, y, radius) {
  if (min(x, state_height - x) <= radius && min(y, state_width - y) <= radius) {
    // Formule pour un hexagone complet
    return 1 + (3 * radius * (radius + 1));
  } else {
    // Sinon, il faut bourriner ...
    var count = 0;
    for (var rayon = 1; rayon <= radius; rayon++){
      // On commence par la case en-dessous
      var cur_coord_rect[2] = [x, y + rayon];
      for (var orientation = 0; orientation < 6; orientation++) {
        for (var cote = 0; cote < rayon; cote++) {
          if (cur_coord_rect[0] < state_height
            && 0 <= cur_coord_rect [0]
            && cur_coord_rect[1] < state_width
            && 0 <= cur_coord_rect[1]) {
              count++;
          }
          // Passage à la case suivante
          cur_coord_rect = neighbour_rect(cur_coord_rect, orientation);
        }
      }
    }
    return count;
  }
}

function tabmax(len, tab) {
  var out = 0;
  for (var i = 0; i < len; i++) {
    if (out < tab[i]) {
      out = tab[i];
    }
  }
  return out;
}

function indexof(elt, len, tab) {
  var out = -1;
  for (var i = 0; i < len; i++) {
    if (elt == tab[i]) {
      out = i;
    }
  }
  return out;
}
