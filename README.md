# Wesnoth-ZKPSI
Sécurisation du jeu de stratégie [Battle for Wesnoth](https://www.wesnoth.org/)
pour jouer en pair à pair à l'aide d'une intersection privée d'ensembles
([Private Set Intersection, PSI](https://en.wikipedia.org/wiki/Private_set_intersection)) et de preuves à divulgation nulle de connaissance
([Zero-knowledge proofs, ZKP](https://fr.wikipedia.org/wiki/Preuve_%C3%A0_divulgation_nulle_de_connaissance)) codées avec [Circom](https://github.com/iden3/circom).

## Dépendances
- [Circom](https://github.com/iden3/circom)
- [circomlib](https://github.com/iden3/circomlib) (à placer dans le dossier au-dessus)
- Rust (version 1.70+ pour la version Nova, 1.67 pour le prototype Groth16)

## Protocole
Le protocole hybride des PSI (qui permettent d'obtenir la vision des troupes) et
une ZKP qui vérifie le respect des règles et le bon déroulement de la PSI. Pour
pouvoir tout programmer sur un circuit Circom, la PSI est construite avec la
courbe elliptique Baby Jubjub.

Afin d'éviter de générer des preuves à chaque tour, les joueurs peuvent à la
place les accumuler grâce à Nova, et envoient une preuve qui fait foi pour toute
la partie lorsque l'adversaire la demande.

TODO: Description du protocole (préciser qu'on update le fog of war seulement au
début du tour !!!)

IMAGE

## Structure de l'implémentation
Afin d'assurer la cohérence des calculs sans avoir à réécrire le programme, les
résultats de chaque étape du protocole sont calculés à partir de l'outil de
déboguage `log` de Circom, permettant d'utiliser les circuits pour calculer les
sorties en plus du témoin de ZKP.

Chaque dossier de la racine correspond à une étape du protocole, prenant les
entrées des joueurs et leur état précédent et calculant le suivant en :
- Générant l'entrée du joueur à l'aide des scripts python `gen_input.py`
- Puis en utilisant les calculateurs de témoin sur cette entrée :
  `./phaseX_cpp/phaseX start.json witness.wtns > output.txt`

Le simulateur d'échange en Rust utilise un procédé similaire et réalise les preuves avec
Nova via [Nova-Scotia](https://github.com/nalinbhardwaj/Nova-Scotia).

## Implémentations utilisées
- PSI : [Fast secure computation of set intersection (Stanisław Jarecki,
  Xiaomin Liu)](https://dl.acm.org/doi/10.5555/1885535.1885573)
- ZKP (Nova) : [Nova: Recursive Zero-Knowledge Arguments from Folding Schemes
  (Abhiram Kothapalli, Srinath Setty, Ioanna Tzialla)](https://eprint.iacr.org/2021/370)
- Hachages : [New Design Techniques for Efficient Arithmetization-Oriented Hash Functions:Anemoi Permutations and Jive Compression Mode](https://eprint.iacr.org/2022/840) en reprenant le code de [AnemoiCircom](https://github.com/MBelegris/AnemoiCircom/)

## État actuel
CE LOGICIEL EST ENCORE EXPÉRIMENTAL ET N'EST PAS PRÊT À CERTIFIER DES PARTIES DE
BATTLE FOR WESNOTH.

Bien que l'implémentation laisse déjà tester l'efficacité du programme, les
circuits n'ont pas encore été testés et comparés au fonctionnement de Battle for
Wesnoth. De plus, les preuves réalisées sont refusées par Nova, bogue encore en
cours d'investigation.

## Prouveurs alternatifs
En l'état de l'implémentation avec Nova, il est plus rapide d'utiliser une
chaîne de preuves réalisées à chaque tour avec Groth16. Un prototype utilisant
une fourchette de [circom-compat](https://github.com/arkworks-rs/circom-compat),
dont la branche utilisée est [ici](https://github.com/Yiheng-Liu/circom-compat/tree/feat/multi-dimension-input
), est disponible avec le dossier `wesnoth-zkpsi/phase2` (attention, celui-ci ne
marche qu'avec Rust version 1.67, les versions plus récentes sont
incompatibles).

Pour lancer le prototype, il faut placer ce dépôt dans le dossier au-dessus, et
y remplacer `tests/groth16.rs` par le fichier du même nom disponible ici à la
racine. Lancer le test lance le prototype.
