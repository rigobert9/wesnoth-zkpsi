import json
import random

"""
/*
* Chaque case contient les informations suivantes :
* [type_unite, HP, état_village, range_restante]
* Le tableau supplémentaire contient les informations suivantes :
* [argent_possede, villages_possédés, upkeep_accumulé] */
signal input prev_state[state_size][4];
signal input prev_misc_state[3];
// Actions adverses
signal input degats[state_size];
signal input captures[nb_villages];
// 10 actions avec l'encodage
// Le batching d'actions est fait dans ce prototype, à voir s'il est conservé
// dans l'un ou l'autre des jeux
signal input actions[actions_size][8];
/* On peut faire confiance aux joueurs pour énoncer les villages possédés par
* l'adversaire qu'ils capturent : en effet, s'ils l'énoncent alors que
* l'adversaire ne l'a pas, il font fuir de l'information; s'ils ne l'énoncent
* pas alors que l'adversaire l'a, celui-ci continue à toucher de l'argent sur
* ce village.*/
// On doit donc vérifier que les éléments de ce tableau sont bien capturés
signal input actions_captures[nb_villages];
signal input phase1_exponents[state_size];
signal input phase2_exponent;

/* Entrées adverses publiques */
signal input phase1_received[state_size][2]; // Points
"""

# Les valeurs sont celles de la carte spéciale, qui ne se joue qu'avec les
# nordiques pour les deux joueurs, avec un guerrier orc comme commandant,
# et les troupes après 1 qui sont dans l'ordre proposé par le jeu
# On commence à 100 d'or chacun, et aucun village

# Le modulo du corps fini
modulo_corps = 21888242871839275222246405745257275088548364400416034343698204186575808495617
# L'ordre de la courbe Baby Jubjub
modulo_courbe = 21888242871839275222246405745257275088614511777268538073601725287587578984328
state_size = 100
nb_villages = 8
nb_actions = 10

# Transforme un nombre en sa représentation binaire, big endian
# 254 chiffres utilisés (le log des modulos)
def num2bits(num):
    return [(num >> i) % 2 for i in range(0,254)]

# Permet de prendre un nombre inversible dans le modulo de l'ordre de la courbe
# (donc un impair)
# Agit sur les représentations binaires
def impairer(elt):
    elt[0] = 1
    return elt

# Le hash de la position de départ et des misc, suivie de sa copie pour remplacer le contenu
# de l'accumulateur
initial_hash = ["12396517484807485029748036342867896936797751961982885378204088006561136216347"] * 2


def write_input(filename, expfilename, prev_state, prev_misc_state, actions, degats,
                captures, actions_captures) :
    phase2_exponent = impairer(num2bits(random.randint(0,modulo_courbe - 1)))
    phase1_received_file = open('../phase1/output.txt')
    phase1_received = [i.split() for i in phase1_received_file.readlines()][state_size:]
    phase1_received_file.close()
    input_dict = {
            "step_in": initial_hash,
            "prev_state": prev_state,
            "prev_misc_state": prev_misc_state,
            "actions": actions,
            "degats": degats,
            "captures": captures,
            "actions_captures": actions_captures,
            "phase1_exponents": [impairer(num2bits(random.randint(0,modulo_courbe-1))) for _ in
                                  range(state_size)],
            "phase2_exponent": phase2_exponent,
            "phase1_received": phase1_received
            }

    input_json = json.dumps(input_dict)
    file = open(filename, "w")
    file.write(input_json)
    file.close()
    # exp_json = json.dumps(phase2_exponent)
    # file = open(expfilename, "w")
    # file.write(exp_json)
    # file.close()


prev_state = [[0,0,0,0] for i in range(state_size)]
prev_state[3] = [1,58,0,2] # S'est déjà déplacé de moitié, sur 5 de range
prev_misc_state = [100, 0, 0]
"""
[type, origine_move_x, origine_move_y, destination_move_x, destination_move_y, num_village,
  chateau_apparition, unite_appelée]
"""
actions = [[0,-1,-1,-1,-1,-1,-1,-1] for i in range(nb_actions)]
degats = [0 for i in range(state_size)]
captures = [0 for i in range(nb_villages)]
actions_captures = [0 for i in range(nb_villages)]

write_input("start.json", "expstart.json", prev_state, prev_misc_state, actions, degats, captures, actions_captures)
