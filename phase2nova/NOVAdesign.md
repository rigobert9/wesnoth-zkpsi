## Difficultés de traduction
Un folding NOVA ne permet que d'enchaîner des états successifs avec des entrées
privées qui les font transitionner.
Le problème avec ce dont on a besoin pour ce jeu est que le jeu nécessite
d'avoir des sorties (en l'occurrence la PSI) à chaque tour.

NOVA peut être conceptualisé comme des preuves successives avec un output unique
qui pipe dans l'input public de la preuve suivante, avec une entrée activatrice
en plus.

Pour nos besoin, l'une des entrées/sorties publiques est le hash de l'état du
joueur. Parmi les entrées privées est le vrai état qui permet d'ouvrir ce hash,
qui est une sorte de "clé" d'entrée.

Pour gérer les vraies sorties, ça se corse, mais heureusement les plus vieilles
techniques fonctionnent. Toutes les entrées et sorties publiques d'une étape
sont accumulées dans une hash chain, qui est calculée par le
prouveur comme le vérifieur.
Par difficulté de création de collisions, on peut donc assurer le vérifieur que
la machine a bien utilisé les inputs publics promis et output les résultats
donnés.

## Design final
L'entrée publique et sortie publique du circuit à utiliser avec NOVA est
composée de deux hashes :
- Le premier est celui de l'état actuel du prouveur
- Le second est un hash qui accumule les entrées et sorties publiques (échanges
  DH, dégâts, captures ...)

CEUX-CI DOIVENT ÊTRE MIS À LA SUITE L'UN DE L'AUTRE CAR NOVA-SCOTIA LE VEUT
COMME ÇA

Et le prouveur ajoute à chaque état les entrées privées :
- L'état actuel (cases et metadata)
- Les actions
- Les exposants de la phase 1
- L'exposant de la phase 2

Un petit programme (comme celui des phases précédentes) devra calculer l'output
à envoyer à l'adversaire

## Considérations de hash
Encore la même emmerde choisir le hash et de le mettre en pratique.
Je vais peut-être en choisir un nouveau qui soit pas trop compliqué et
l'implémenter comme ça ce sera fait.

Ya des implémentations in Circom et hors de Circom de Anemoi, the coolest kid on
the block. Il pourra remplacer MiMC qui donne des résultats énormes.
-> L'implémentation est pas hyper concluante

Ya aussi des implémentations de Poseidon I guess...

PRENDRE DES DONNÉES DE LA RÉDUCTION DE TAILLE, ET DE LA COMPLEXITÉ DE LA
MACHINERIE (en contraintes linéaires et non linéaires, en taille de r1cs) !

Garder les anciennes versions serait donc pour le mieux, au moins faire des
branches / des tags pour retenir.

## La chaîne de hash
On peut réduire la taille du hash par différentes techniques d'accumulation de
ces tableaux, mais j'imagine qu'il est plus facile de faire la preuve pour des
trucs bien alignés

Dans chaque étape de la chaîne de hash, qui commencera à 0, on met, dans l'ordre
et dans cet arrangement :
- Le hash précédent (hash_size)
- Les degats reçus (state_size)
- Les captures reçues (nb_villages booléens)
- Le DH de phase 1 reçu (state_size * 2)
- Les villages qu'on capture (nb_village booléens)
- L'output de phase 1 de notre DH (state_size * 2)
- L'output de notre réponse de phase 2 au DH (state_size * 2)
- Les tags cachés pour la PSI (state_size * 2)
- La data cachée pour la PSI (state_size * 3 * 64 booléens)

Voir code.
