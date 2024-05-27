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
initial_hash = [
"21075775164453997497910471957584006879942840417903408448414759038956585331751",
"18010956042710280151493865441476438782243272380302248451607721915847853828222",
"1253525464144558484794626136960994205846448464228654633850717149019059898898",
"7378510493249722178907142410494127029556700808242426025167163467625662118794",
"16153429091501301536230448772120265302498386663691126362332119580846024331952",
"11378139108127225424870384180896403270400234190993763275746330961203953328364",
"9563264281848123680161357244120264858783968864458203531384872550866101082541",
"18672171576630210773724750819708241001406530782944634598525438141215898804012",
"17987298981040638359974673551430018319042557673315312906404826070536102797663",
"2463596387040220201959276372787098277244279174914404675653763931453346196228",
"10237071733035331774473622063606953990971810811687645819754467036868717429031",
"10871728966418268594682272280082096526584755819970740745908974713683772362628",
"4745887284099831382752352694940078070857687281447830038233410161605487682399",
"19460947303639701897713364387920775941150530475502503377016920529064901333774",
"17733744207814358921462140917614033601024398493815525092981964239843937695245",
"9865013637754959830241417304773622679956432803341936630659451719583109630617",
"7294620454880741241825447868508412572045154208031851715406688440200828154914",
"12667352300182426908243790534392078640752112743866379931581531853983766263129",
"7869494266689496495238434701178113868017380838882804130783459271054191665989",
"12168715939025744476121839670003009937727741815302052232442042134494921534294",
"12761979121752259905747479330074339595587970994356174510215541001166892696673",
"760346000902400640527584558157335827155330619607023750024585242075848102131",
"7629395857656579588806831870006129923686361798746781678438161817732906283592",
"19421338484628102035326552449829062812009798424378441575306327887540436875661",
"18789747780459606947142665393526673280282028894556426339626734098696767118715",
"14760132755621895793441551618755738834980512453858660632231652749793800763582",
"5210448901950589616984033021024969384899166231434390443041447599527632546908",
"11092273429548221304283115940719689497395443361204945219534796121264268164306",
"17388890045070013011720169680640627654923861218876205220460293737798256879117",
"1962495008175139394805783454956637573270694699600443457225133459317551228281",
"9559479896167780217171969207289564710913948686597516095068372391839228199995",
"17630747690882958909810702481148514882439726006646427853536543789586197177836",
"18541253213007712113038384803885750935560841217732415454421004380657189237593",
"11882345563490537578720672014091576552079422048988061353727627835589855885244",
"4969016326140494163026196284492557314037166838859647333381493330996382376975",
"10570439125667336950892253433877924713051225260731237008727634737181566383519",
"19777194811645831945846452876454879703749717816511913965246087949850109577704",
"15276209640269209407199696550158440469907836691411588030556965945320648358770",
"11151823593233720400197390811208850168080327543364414183796711332848575713572",
"17750707637534351378593747110873191083052220855001752937016852798119297492385",
"17621290757131482425668571868093026790820623784063670636481517144384972642650",
"19223693895104211109355689118644684738611584274975871527951169992322800438705",
"10144526647168297640330677597773759735710162023557389502660367786643909134386",
"16716055448056993013417337559392404792782921818067116019652159595194760715942",
"18278697560035300450405635439220888684239772666396266167324498290243535824759",
"17586112205529803360158038027038948018689232238072942451980571250967332871932",
"14933056052166683695261726009025813156494534037211493167749773817356372399905",
"17889206461579577209419062915366323401657060263815941678378175005266971630836",
"5188281591576744808134347991529752655277287385850124174040085204813374624141",
"15730504378668621498004970931615573626842033183195310075169653607051627928430",
"3280404530865680041831346825597980458513598280128471892324592543282505968792",
"13839905632377426912304618121049719550787062480082870337789465697469169438830",
"10163630758959799244364785673549457608558634610408242136143292970224577032",
"12782041921593759884720112666696998022897126450030296151913195282644446638369",
"9571972534721234246018342537925186439057943508582606781130355725119723692505",
"6967032983286014152356696573066585638310182349937933312710095351994016294077",
"11757988246755575715856372626614297720522165629640114638586391980474445474937",
"2944481653132962529800438099313845774861688606633581534584742543202740043961",
"3406211987646912832960137616287236273073240424074364064422059267479660313100",
"18827621567188225101592996823882792891466481161918730500334103498926694516742",
"3686459211976236645170192460814697138476482719980197230981761864816915782692",
"5730360928032783951754649585201427021326195288313549821951295856763027526392",
"5933192977146924750037838196394141483639091105687303117041322459352787453216",
"5464946258212058924834261788297773429029889191831394406993421406747596729737",
] * 2


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