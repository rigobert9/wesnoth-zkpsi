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

# Inverse modulaire de n pour mod, sous réserve d'existence
def mod_inv(n, mod):
    def aux(a,b,s,z):
        if b == 0:
            return s
        else:
            q = a // b
            return aux(b, a - (q * b), z, s - (q * z))
    return aux(mod, n, 0, 1) % mod

def num2bits(num):
    return [str(0 if (int(num) & 2**i) == 0 else 1) for i in range(64)]

def bits2num(bits):
    exp = 1
    out = 0
    for i in range(254):
        out += exp * int(bits[i])
        exp += exp
    return out

def yeet(num):
    return [(0 if (int(num) & 2**i) == 0 else 1) for i in range(254)]

def write_input(filename) :
    hashed_idents_file = open('../phase1/output.txt')
    hashed_idents = [i.split() for i in hashed_idents_file.readlines()][:100]
    hashed_idents_file.close()
    phase2_file = open('../../psi-wesnoth/output.txt')
    phase2 = phase2_file.readlines()
    phase2_raw = [[num2bits(j) for j in i.split()] for i in phase2[200:]]
    """
    phase1_exponents_file = open('../phase1/expstart.json')
    print([bits2num(i) for i in json.load(phase1_exponents_file)])
    phase1_exponents_file.close()
    phase1_exponents_file = open('../phase1/expstart.json')
    print([mod_inv(bits2num(i), modulo_courbe) for i in json.load(phase1_exponents_file)])
    phase1_exponents_file.close()
    phase1_exponents_file = open('../phase1/expstart.json')
    print([bits2num(i) * mod_inv(bits2num(i), modulo_courbe) % modulo_courbe for i in json.load(phase1_exponents_file)])
    phase1_exponents_file.close()
    """
    phase1_exponents_file = open('../phase1/expstart.json')
    input_dict = {
            "hashed_idents" : hashed_idents,
            "inv_phase1_exponents": [yeet(mod_inv(bits2num(i), modulo_courbe)) for i in json.load(phase1_exponents_file)],
            "phase2_dh_output": [i.split() for i in phase2[:100]],
            "phase2_hidden_tags": [i.split() for i in phase2[100:200]],
            "phase2_hidden_data": phase2_raw
            }

    phase1_exponents_file.close()
    phase2_file.close()
    input_json = json.dumps(input_dict)
    file = open(filename, "w")
    file.write(input_json)
    file.close()

write_input("start.json")
