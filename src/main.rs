mod unit;

use std::fs::File;
use std::io::BufWriter;
use std::io::{BufReader, Read, Write};
use std::mem::MaybeUninit;
use std::ops::{Index, IndexMut};
use std::path::PathBuf;
use std::process::Command;
use std::str::FromStr;
use std::{collections::HashMap, env::current_dir, fs, time::Instant};

use crate::unit::{Commander, Unit};
use bincode::{deserialize_from, serialize_into};
use halo2curves::bn256::{Bn256, Fr};
use halo2curves::ff::Field;
use halo2curves::pairing::Engine;
use nova_scotia::circom::circuit::{CircomCircuit, R1CS};
use nova_scotia::circom::reader::load_witness_from_bin_file;
use nova_scotia::{
    circom::reader::load_r1cs, create_public_params, create_recursive_circuit, FileLocation, C1,
    C2, F, S,
};
use nova_snark::provider::bn256_grumpkin::{bn256, grumpkin};
use nova_snark::spartan::direct::DirectSNARK;
use nova_snark::traits::circuit::TrivialTestCircuit;
use nova_snark::{provider, CompressedSNARK, PublicParams, RecursiveSNARK, VerifierKey};
use num_bigint::Sign;
use num_bigint::{BigInt, BigUint, RandBigInt};
use serde::ser::{SerializeMap, SerializeSeq, SerializeStruct, SerializeTuple};
use serde::{Serialize, Serializer};

const BABY_JUBJUB_ORDER: &str =
    "21888242871839275222246405745257275088614511777268538073601725287587578984328";
const MAX_ACTION_COUNT: usize = 10;

type Snark = RecursiveSNARK<
    provider::bn256_grumpkin::bn256::Point,
    provider::bn256_grumpkin::grumpkin::Point,
    C1<provider::bn256_grumpkin::bn256::Point>,
    C2<provider::bn256_grumpkin::grumpkin::Point>,
>;

fn string_to_f1(s: &str) -> Fr {
    let mut out = [0; 32];
    match s.parse::<BigInt>().unwrap().to_bytes_le() {
        (Sign::Plus, v) => {
            for i in 0..v.len() {
                out[v.len() - i - 1] = v[v.len() - i - 1];
            }
        }
        _ => panic!(),
    }
    Fr::from_bytes(&out).unwrap()
}

#[derive(Copy, Clone)]
enum InitialState {
    Nordic((u64, u64), Commander, Commander),
}

// TODO: refactorer pour avoir des cartes distinctes dans des types distincts avec un trat.
impl InitialState {
    // fn circuit(&self) -> R1CS<Fr> {
    //     match self {
    //         InitialState::Nordic(_, _) => {
    //             load_r1cs::<bn256::Point, grumpkin::Point>(&FileLocation::PathBuf("map_circuits/nordic.circuit".into()))
    //         }
    //     }
    // }
    fn circuit_path(&self) -> PathBuf {
        match self {
            InitialState::Nordic(_, _, _) => {
                // "map_circuits/nordic".into()
                "wesnoth-zkpsi/".into()
            }
        }
    }

    fn size(&self) -> (u64, u64) {
        match self {
            InitialState::Nordic(size, _, _) => *size,
        }
    }

    fn village_count(&self) -> u64 {
        match self {
            InitialState::Nordic(_, _, _) => 8,
        }
    }
}

#[derive(Copy, Clone)]
struct Square {
    unit: Unit,
    health_points: u64,
    captured: bool,
    move_credits: u64,
}

type Position = (u64, u64);

#[derive(Copy, Clone)]
enum Transaction {
    None,
    MoveUnit(Position, Position),
    CaptureVillage(u64),
    PurchaseUnit(u64, Unit),
}

impl Transaction {
    fn to_action(&self) -> [i64; 8] {
        let na = -1;
        match self {
            Transaction::None => [0, na, na, na, na, na, na, na],
            Transaction::MoveUnit((orig_x, orig_y), (dest_x, dest_y)) => [
                1,
                *orig_x as i64,
                *orig_y as i64,
                *dest_x as i64,
                *dest_y as i64,
                na,
                na,
                na,
            ],
            Transaction::CaptureVillage(village_id) => {
                [2, na, na, na, na, *village_id as i64, na, na]
            }
            Transaction::PurchaseUnit(castle_id, unit) => {
                let unit_id: u64 = unit.into();
                [3, na, na, na, na, na, *castle_id as i64, unit_id as i64]
            }
        }
    }
}

type Turn = Vec<Transaction>;

struct CircuitState {
    squares: Vec<Square>,
    gold_amount: u64,
    captured_village_count: u64,
    current_upkeep_costs: u64,
}

impl Serialize for Square {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut state = serializer.serialize_tuple(4)?;
        state.serialize_element(&self.unit)?;
        state.serialize_element(&self.health_points)?;
        state.serialize_element(&(if self.captured { 1 } else { 0 }))?;
        state.serialize_element(&self.move_credits)?;
        state.end()
    }
}

struct UnencryptedData {
    last_hash: BigUint,
    own_received_damage: Vec<u64>, // carte des dégats subis par chacune des unités au début du tour précédent
    adversary_captures: Vec<u64>, // de taille nombre_village, 1 si capturé au début par l'adversaire, 0 sinon
    allied_captures: Vec<u64>, // de taille nombre_village, 1 si capturé à la fin du tour, 0 sinon
}

impl UnencryptedData {
    fn init(initial_state: InitialState) -> UnencryptedData {
        let (width, height) = initial_state.size();
        let village_count = initial_state.village_count() as usize;

        UnencryptedData {
            last_hash: BigUint::new(vec![]),
            own_received_damage: vec![0u64; (width * height) as usize],
            adversary_captures: vec![0u64; village_count],
            allied_captures: vec![0u64; village_count],
        }
    }
}

struct State {
    circuit_state: CircuitState,
    public_params: PublicParams<
        provider::bn256_grumpkin::bn256::Point,
        provider::bn256_grumpkin::grumpkin::Point,
        C1<provider::bn256_grumpkin::bn256::Point>,
        C2<provider::bn256_grumpkin::grumpkin::Point>,
    >,
    snark: Snark,
    r1cs: R1CS<Fr>,
    initial_hash: Vec<Fr>,
    phase2_circuit: CircomCircuit<Fr>,
    unencrypted_state: UnencryptedData,
    initial_state: InitialState,
    pending_transactions: Vec<Transaction>,
    roll_hash: BigUint,
}

struct Phase1<'a> {
    previous_state: &'a State,
    damages_inflicted: Vec<u64>,
    captures: Vec<u64>,
    exponents: Vec<Vec<u8>>,
}

impl<'a> Serialize for Phase1<'a> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut serializer = serializer.serialize_map(Some(5))?;
        let previous_circuit_state = &self.previous_state.circuit_state;
        serializer.serialize_entry("prev_state", &previous_circuit_state.squares)?;
        serializer.serialize_entry(
            "prev_misc_state",
            &[
                previous_circuit_state.gold_amount,
                previous_circuit_state.captured_village_count,
                previous_circuit_state.current_upkeep_costs,
            ],
        )?;
        serializer.serialize_entry("degats", &self.damages_inflicted)?;
        serializer.serialize_entry("captures", &self.captures)?;
        serializer.serialize_entry("phase1_exponents", &self.exponents)?;
        serializer.end()
    }
}

impl State {
    fn initial_states(initial_state: InitialState) -> (State, State) {
        let none = Unit::None.default_square();

        let circuit_file = initial_state.circuit_path().join("phase2nova/circuit.r1cs");

        let begin = Instant::now();

        let key_path = initial_state
            .circuit_path()
            .join("phase2nova/public_parameters");

        println!("Lecture du 2e circuit.");
        let r1cs = load_r1cs::<bn256::Point, grumpkin::Point>(&FileLocation::PathBuf(circuit_file));
        println!("Circuit lu en {:?}", begin.elapsed());

        let begin = Instant::now();
        let pp1: PublicParams<bn256::Point, grumpkin::Point, _, _>;

        if key_path.exists() {
            println!("Lecture des paramètres publics.");
            let parameters_file = File::open(key_path.clone()).unwrap();
            let parameters_writer = BufReader::new(parameters_file);
            pp1 = deserialize_from(parameters_writer).unwrap();
        } else {
            println!("Génération des paramètres publics.");
            pp1 = create_public_params(r1cs.clone());
            // Écrire dans un fichier les paramètres une fois calculés.
            let parameters_file = File::create(key_path.clone()).unwrap();
            let parameters_writer = BufWriter::new(parameters_file);
            serialize_into(parameters_writer, &pp1).unwrap();
        }
        let parameters_file = File::open(key_path.clone()).unwrap();
        let parameters_writer = BufReader::new(parameters_file);
        let pp2: PublicParams<bn256::Point, grumpkin::Point, _, _> =
            deserialize_from(parameters_writer).unwrap();

        let parameters_file = File::open(key_path).unwrap();
        let parameters_writer = BufReader::new(parameters_file);
        let pp: PublicParams<bn256::Point, grumpkin::Point, _, _> =
            deserialize_from(parameters_writer).unwrap();
        println!("Paramètres publics obtenus en {:?}", begin.elapsed());

        let circuit = CircomCircuit {
            r1cs: load_r1cs::<bn256::Point, grumpkin::Point>(&FileLocation::PathBuf(
                initial_state.circuit_path().join("phase2nova/circuit.r1cs"),
            )),
            witness: None,
        };

        let circuit_secondary = TrivialTestCircuit::default();
        let z0_secondary =
            vec![<halo2curves::grumpkin::G1 as halo2curves::group::Group>::Scalar::ZERO];

        match initial_state {
            InitialState::Nordic((w, h), a, b) => {
                let a: Unit = a.into();
                let b: Unit = b.into();

                let default_map = vec![none; (w * h) as usize];
                let mut map_a = default_map.clone();
                let mut map_b = default_map.clone();

                map_a[0] = a.default_square();
                map_b[(w * h) as usize - 1] = b.default_square();

                let (mut sa, mut sb) = (
                    State {
                        circuit_state: CircuitState {
                            squares: map_a,
                            gold_amount: 100,
                            captured_village_count: 0,
                            current_upkeep_costs: 0,
                        },
                        public_params: pp1,
                        snark: unsafe { MaybeUninit::zeroed().assume_init() },
                        initial_hash: unsafe { MaybeUninit::zeroed().assume_init() },
                        r1cs: r1cs.clone(),
                        phase2_circuit: circuit.clone(),
                        unencrypted_state: UnencryptedData::init(initial_state),
                        initial_state,
                        pending_transactions: Vec::new(),
                        roll_hash: BigUint::new(vec![]),
                    },
                    State {
                        circuit_state: CircuitState {
                            squares: map_b,
                            gold_amount: 100,
                            captured_village_count: 0,
                            current_upkeep_costs: 0,
                        },
                        public_params: pp2,
                        snark: unsafe { MaybeUninit::zeroed().assume_init() },
                        initial_hash: unsafe { MaybeUninit::zeroed().assume_init() },
                        r1cs: r1cs.clone(),
                        phase2_circuit: circuit,
                        unencrypted_state: UnencryptedData::init(initial_state),
                        initial_state,
                        pending_transactions: Vec::new(),
                        roll_hash: BigUint::new(vec![]),
                    },
                );

                let in_a = vec![
                    Fr::from_bytes(&sa.hash().to_bytes_le().try_into().unwrap()).unwrap(),
                    0.into(),
                ];
                let in_b = vec![
                    Fr::from_bytes(&sb.hash().to_bytes_le().try_into().unwrap()).unwrap(),
                    0.into(),
                ];
                let snark_a = Snark::new(
                    &pp,
                    &sa.phase2_circuit,
                    &circuit_secondary,
                    in_a.clone(),
                    z0_secondary.clone(),
                );
                let snark_b = Snark::new(
                    &pp,
                    &sb.phase2_circuit,
                    &circuit_secondary,
                    in_b.clone(),
                    z0_secondary,
                );
                sa.snark = snark_a;
                sb.snark = snark_b;
                sa.initial_hash = in_a;
                sb.initial_hash = in_b;

                (sa, sb)
            }
        }
    }

    fn append_transaction(&mut self, transaction: Transaction) {
        self.pending_transactions.push(transaction);
    }

    fn phase1(
        &self,
    ) -> (
        Vec<BigUint>,
        Vec<(BigUint, BigUint)>,
        Vec<(BigUint, BigUint)>,
    ) {
        let map_size = self.circuit_state.squares.len();
        let exponents = random_exponents(map_size);
        let phase1 = Phase1 {
            previous_state: self,
            damages_inflicted: vec![0; map_size],
            captures: vec![0; self.initial_state.village_count() as usize],
            exponents: to_exponent_bits(&exponents),
        };
        let phase1_input =
            serde_json::to_string(&phase1).expect("Échec de l'initialisation de la phase 1 !");

        let mut phase1_input_file =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        let phase1_witness =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        phase1_input_file
            .write_all(phase1_input.as_bytes())
            .expect("Impossible d'écrire dans le fichier les entrées de la phase 1");

        // let circuit1 = self.initial_state.circuit_path().join("phase1/circuit");
        let circuit1 = self
            .initial_state
            .circuit_path()
            .join("phase1/circuit_cpp/circuit");
        println!("Fichier entrée: {:?}", phase1_input_file.path());
        println!("Fichier témoin: {:?}", phase1_witness.path());

        let phase1_cmd = Command::new(circuit1)
            .arg(phase1_input_file.path())
            .arg(phase1_witness.path())
            .output()
            .expect("Le circuit de la phase 1 a échoué !");
        assert!(phase1_cmd.status.success(), "{:?}", phase1_cmd);
        let phase1_out: String =
            String::from_utf8(phase1_cmd.stdout).expect("La phase 1 a donné du non-UTF-8 ??");

        let couples = phase1_out
            .lines()
            .map(|x| {
                let x: Vec<&str> = x.split_whitespace().collect();
                (
                    BigUint::from_str(x[0]).unwrap(),
                    BigUint::from_str(x[1]).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(couples.len(), map_size * 2);
        (
            exponents.to_vec(),
            couples[0..map_size].to_vec(),
            couples[map_size..map_size * 2].to_vec(),
        )
    }

    fn hash(&self) -> BigUint {
        // assert_eq!(self.circuit_state.squares.len(), )
        let mut hash_input: Vec<u64> = self
            .circuit_state
            .squares
            .iter()
            .flat_map(|x| {
                let unit: u64 = (&x.unit).into();
                [unit, x.health_points, x.captured as u64, x.move_credits]
            })
            .collect();
        hash_input.push(self.circuit_state.gold_amount);
        hash_input.push(self.circuit_state.captured_village_count);
        hash_input.push(self.circuit_state.current_upkeep_costs);

        let json = serde_json::to_string(&HashObject {
            to_hash: &hash_input,
        })
        .unwrap();

        let mut input =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        let output =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        input
            .write_all(json.as_bytes())
            .expect("Impossible d'écrire dans le fichier les entrées du hash d'état");

        // let phase_cmd = Command::new(self.initial_state.circuit_path().join("hash/hash_state"))
        let phase_cmd = Command::new(
            self.initial_state
                .circuit_path()
                .join("hash/hash_state_cpp/hash_state"),
        )
        .arg(input.path())
        .arg(output.path())
        .output()
        .expect("Le circuit de hachagé a échoué !");
        assert!(phase_cmd.status.success(), "{:?}", phase_cmd);
        let mut hash_output: String =
            String::from_utf8(phase_cmd.stdout).expect("Le hash n'est pas en UTF-8 ??");
        hash_output.pop();
        BigUint::from_str(hash_output.as_str()).unwrap()
    }

    fn roll_hash(&mut self) -> BigUint {
        /*
        let hash_input: Vec<u64> = self.circuit_state.squares.iter().flat_map(|x| {
            let unit: u64 = (&x.unit).into();
            [
                unit,
                x.health_points,
                x.captured as u64,
                x.move_credits
            ]
        }).collect();

        let mut hash_input = Vec::<u64>::with_capacity((width * height) as usize * 10 + 3);
        hash_input.push(self.roll_hash);

        hash_input = vec![
            vec![],
            vec![0; self.]
            vec!hash_input
        ].concat();
        hash_input.push(self.circuit_state.gold_amount);
        hash_input.push(self.circuit_state.captured_village_count);
        hash_input.push(self.circuit_state.current_upkeep_costs);

        let json = serde_json::to_string(&HashObject {
            to_hash: &hash_input
        }).unwrap();

        let mut input = tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        let output = tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        input.write_all(json.as_bytes()).expect("Impossible d'écrire dans le fichier les entrées du hash d'état");

        let phase_cmd = Command::new("map_circuits/hash/hash_state")
            .arg(input.path())
            .arg(output.path())
            .output().expect("Le circuit de hachagé a échoué !");
        assert!(phase_cmd.status.success(), "{:?}", phase_cmd);
        let mut hash_output: String =
            String::from_utf8(phase_cmd.stdout).expect("Le hash n'est pas en UTF-8 ??");
        println!("{:?}", hash_output);
        hash_output.pop();
        BigUint::from_str(hash_output.as_str()).unwrap()*/
        BigUint::new(vec![]) // TODO: hache chainé
    }

    fn phase2(
        &mut self,
        diffie_hellmann_phase_1: Vec<(BigUint, BigUint)>,
    ) -> (
        Vec<(BigUint, BigUint)>,
        Vec<(BigUint, BigUint)>,
        Vec<(BigUint, BigUint, BigUint)>,
    ) {
        let mut random = rand::thread_rng();
        let baby_jubjub_curve_order = BigUint::from_str(BABY_JUBJUB_ORDER).unwrap();
        let exponent = random.gen_biguint_below(&baby_jubjub_curve_order);
        let (width, height) = self.initial_state.size();
        let map_size = width * height;
        let own_exponents = random_exponents(map_size as usize);

        let squares = &mut self.circuit_state.squares;
        for transaction in &self.pending_transactions {
            match transaction {
                // TODO implement all of that
                Transaction::None => {}
                Transaction::MoveUnit((x, y), (x_, y_)) => {
                    squares[(width * y_ + x_) as usize] = squares[(width * y + x) as usize];
                    squares[(width * y + x) as usize] = Square {
                        unit: Unit::None,
                        health_points: 0,
                        captured: false,
                        move_credits: 0,
                    };
                }
                Transaction::CaptureVillage(_) => {}
                Transaction::PurchaseUnit(_, _) => {}
            }
        }

        let phase2 = Phase2 {
            rolling_hash: self.roll_hash(),
            state: self,
            damages_inflicted: vec![0; map_size as usize], // FIXME damages
            exponent,
            own_exponents,
            received_data: diffie_hellmann_phase_1,
        };
        let phase2_input =
            serde_json::to_string(&phase2).expect("Échec de l'initialisation de la phase 2 !");

        let mut phase2_input_file =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        let mut phase2_witness =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        phase2_input_file
            .write_all(phase2_input.as_bytes())
            .expect("Impossible d'écrire dans le fichier les entrées de la phase 2");

        // let circuit2 = self.initial_state.circuit_path().join("phase2nova/circuit");
        let circuit2 = self
            .initial_state
            .circuit_path()
            .join("phase2nova/circuit_cpp/circuit");
        println!("Fichier entrée: {:?}", phase2_input_file.path());
        println!("Fichier témoin: {:?}", phase2_witness.path());

        let phase2_cmd = Command::new(circuit2)
            .arg(phase2_input_file.path())
            .arg(phase2_witness.path())
            .output()
            .expect("Le circuit de la phase 2 a échoué !");
        assert!(phase2_cmd.status.success(), "{:?}", phase2_cmd);
        let phase2_out: String =
            String::from_utf8(phase2_cmd.stdout).expect("La phase 2 a donné du non-UTF-8 ??");

        let mut lines = phase2_out.lines().collect::<Vec<_>>();
        assert_eq!(lines.len(), 3 * map_size as usize);
        let diffie_hellman = lines
            .drain(0..map_size as usize)
            .map(|x| {
                let x: Vec<&str> = x.split_whitespace().collect();
                (
                    BigUint::from_str(x[0]).unwrap(),
                    BigUint::from_str(x[1]).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        let hidden_tags = lines
            .drain(0..map_size as usize)
            .map(|x| {
                let x: Vec<&str> = x.split_whitespace().collect();
                (
                    BigUint::from_str(x[0]).unwrap(),
                    BigUint::from_str(x[1]).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        let hidden_data = lines
            .drain(0..map_size as usize)
            .map(|x| {
                let x: Vec<&str> = x.split_whitespace().collect();
                (
                    BigUint::from_str(x[0]).unwrap(),
                    BigUint::from_str(x[1]).unwrap(),
                    BigUint::from_str(x[2]).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            lines.len(),
            0,
            "Des lignes en plus données par le circuit 2 ?"
        );

        let circuit = CircomCircuit {
            r1cs: self.r1cs.clone(),
            witness: Some(load_witness_from_bin_file(phase2_witness.path())),
        };

        let circuit_secondary = TrivialTestCircuit::default();
        let z0_secondary =
            vec![<halo2curves::grumpkin::G1 as halo2curves::group::Group>::Scalar::ZERO];

        self.snark
            .prove_step(
                &self.public_params,
                &circuit,
                &circuit_secondary,
                self.initial_hash.clone(),
                z0_secondary.clone(),
            )
            .unwrap();

        (diffie_hellman, hidden_tags, hidden_data)
    }

    fn prove(
        &self,
    ) -> (
        CompressedSNARK<
            bn256::Point,
            grumpkin::Point,
            C1<bn256::Point>,
            C2<grumpkin::Point>,
            S<bn256::Point>,
            S<grumpkin::Point>,
        >,
        VerifierKey<
            bn256::Point,
            grumpkin::Point,
            C1<bn256::Point>,
            C2<grumpkin::Point>,
            S<bn256::Point>,
            S<grumpkin::Point>,
        >,
    ) {
        let (pk, vk) = CompressedSNARK::<_, _, _, _, S<bn256::Point>, S<grumpkin::Point>>::setup(
            &self.public_params,
        )
        .unwrap();
        (
            CompressedSNARK::prove(&self.public_params, &pk, &self.snark).unwrap(),
            vk,
        )
    }

    fn phase3(
        &self,
        exponents_a: Vec<BigUint>,
        part3_stuff: Vec<(BigUint, BigUint)>,
        dh_output: Vec<(BigUint, BigUint)>,
        hidden_tags: Vec<(BigUint, BigUint)>,
        hidden_data: Vec<(BigUint, BigUint, BigUint)>,
    ) {
        let baby_jubjub_curve_order = BigUint::from_str(BABY_JUBJUB_ORDER).unwrap();
        let inv_a = exponents_a
            .iter()
            .map(|x| {
                x.modinv(&baby_jubjub_curve_order).unwrap_or_else(|| {
                    panic!("Les impairs n'étaient pas inversibles (notamment {}).", x)
                })
            })
            .collect::<Vec<_>>();

        let phase3_input = serde_json::to_string(&Phase3 {
            hashed_idents: part3_stuff,
            exponents_a: inv_a,
            dh_output: dh_output,
            hidden_tags: hidden_tags,
            hidden_data: hidden_data,
        })
        .expect("Impossible de convertir en JSON.");
        // println!("{}", phase3_input);

        let mut phase3_input_file =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        let phase3_witness =
            tempfile::NamedTempFile::new().expect("Impossible de créer un fichier temporaire");
        phase3_input_file
            .write_all(phase3_input.as_bytes())
            .expect("Impossible d'écrire dans le fichier les entrées de la phase 3");

        // let circuit3 = self.initial_state.circuit_path().join("phase3/circuit");
        let circuit3 = self
            .initial_state
            .circuit_path()
            .join("phase3/circuit_cpp/circuit");
        println!("Fichier entrée: {:?}", phase3_input_file.path());
        println!("Fichier témoin: {:?}", phase3_witness.path());

        let phase3_cmd = Command::new(circuit3)
            .arg(phase3_input_file.path())
            .arg(phase3_witness.path())
            .output()
            .expect("Le circuit de la phase 3 a échoué !");
        assert!(phase3_cmd.status.success(), "{:?}", phase3_cmd);
        let phase3_out: String =
            String::from_utf8(phase3_cmd.stdout).expect("La phase 3 a donné du non-UTF-8 ??");
        // println!("{}", phase3_out);
    }
}

struct Phase3 {
    hashed_idents: Vec<(BigUint, BigUint)>,
    exponents_a: Vec<BigUint>,
    dh_output: Vec<(BigUint, BigUint)>,
    hidden_tags: Vec<(BigUint, BigUint)>,
    hidden_data: Vec<(BigUint, BigUint, BigUint)>,
}

impl Serialize for Phase3 {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut serializer = serializer.serialize_map(Some(5))?;
        serializer.serialize_entry(
            "hashed_idents",
            &self
                .hashed_idents
                .iter()
                .map(|(a, b)| (a.to_string(), b.to_string()))
                .collect::<Vec<_>>(),
        )?;
        serializer.serialize_entry("inv_phase1_exponents", &to_exponent_bits(&self.exponents_a))?;
        serializer.serialize_entry(
            "phase2_dh_output",
            &self
                .dh_output
                .iter()
                .map(|(a, b)| (a.to_string(), b.to_string()))
                .collect::<Vec<_>>(),
        )?;
        serializer.serialize_entry(
            "phase2_hidden_tags",
            &self
                .hidden_tags
                .iter()
                .map(|(a, b)| (a.to_string(), b.to_string()))
                .collect::<Vec<_>>(),
        )?;

        fn to_bits(big_uint: &BigUint) -> Vec<u8> {
            let mut x: Vec<u8> = big_uint.to_bytes_le().iter().flat_map(u8_to_bits).collect();
            x.resize(64, 0);
            x
        }

        serializer.serialize_entry(
            "phase2_hidden_data",
            &self
                .hidden_data
                .iter()
                .map(|(a, b, c)| (to_bits(a), to_bits(b), to_bits(c)))
                .collect::<Vec<_>>(),
        )?;
        serializer.end()
    }
}

#[derive(Serialize)]
struct HashObject<'a> {
    to_hash: &'a Vec<u64>,
}

struct Phase2<'a> {
    rolling_hash: BigUint,
    state: &'a State,
    damages_inflicted: Vec<u64>,
    exponent: BigUint,
    own_exponents: Vec<BigUint>,
    received_data: Vec<(BigUint, BigUint)>,
}

fn u8_to_bits(val: &u8) -> [u8; 8] {
    [
        (val >> 0) & 1u8,
        (val >> 1) & 1u8,
        (val >> 2) & 1u8,
        (val >> 3) & 1u8,
        (val >> 4) & 1u8,
        (val >> 5) & 1u8,
        (val >> 6) & 1u8,
        (val >> 7) & 1u8,
    ]
}

impl Serialize for Transaction {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.to_action().serialize(serializer)
    }
}

impl<'a> Serialize for Phase2<'a> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut serializer = serializer.serialize_map(Some(5))?;
        let previous_circuit_state = &self.state.circuit_state;
        let (width, height) = self.state.initial_state.size(); // , "0"]
        serializer.serialize_entry(
            "step_in",
            &[self.state.hash().to_string(), self.rolling_hash.to_string()],
        )?;
        serializer.serialize_entry("prev_state", &previous_circuit_state.squares)?;
        serializer.serialize_entry(
            "prev_misc_state",
            &[
                previous_circuit_state.gold_amount,
                previous_circuit_state.captured_village_count,
                previous_circuit_state.current_upkeep_costs,
            ],
        )?;

        let mut actions = self.state.pending_transactions.clone();
        assert!(
            actions.len() <= MAX_ACTION_COUNT,
            "Trop d'actions en un seul tour !!!!"
        );
        actions.resize(MAX_ACTION_COUNT, Transaction::None);
        serializer.serialize_entry("actions", &actions)?;
        serializer.serialize_entry("degats", &self.damages_inflicted)?;
        let mut captures = vec![0; self.state.initial_state.village_count() as usize];
        for action in actions {
            if let Transaction::CaptureVillage(village_id) = action {
                captures[village_id as usize] = 1;
            }
        }
        serializer.serialize_entry("captures", &captures)?;
        serializer.serialize_entry("actions_captures", &vec![0; captures.len()])?; // TODO demander à françois ce que veut dire "action_captures" dans son circuit
        serializer.serialize_entry("phase1_exponents", &to_exponent_bits(&self.own_exponents))?;
        serializer.serialize_entry("phase2_exponent", &to_bits(&self.exponent))?;
        serializer.serialize_entry(
            "phase1_received",
            &self
                .received_data
                .iter()
                .map(|(x, y)| (x.to_string(), y.to_string()))
                .collect::<Vec<_>>(),
        )?;
        serializer.end()
    }
}

fn random_exponents(count: usize) -> Vec<BigUint> {
    let mut random = rand::thread_rng();
    let baby_jubjub_curve_order = BigUint::from_str(BABY_JUBJUB_ORDER).unwrap();
    let p: BigUint = &baby_jubjub_curve_order / BigUint::new(vec![8]);
    let mut exps: Vec<BigUint> = vec![0; count]
        .iter()
        .map(|_| random.gen_biguint_below(&baby_jubjub_curve_order))
        .collect();
    exps.iter_mut().for_each(|nbr| {
        nbr.set_bit(0, true);
        let reborrow = &*nbr;
        let two: BigUint = BigUint::new(vec![2]);
        if reborrow % &p == BigUint::ZERO {
            *nbr = (reborrow + two) % &baby_jubjub_curve_order
        };
    });
    exps
}

fn to_bits(big_uint: &BigUint) -> Vec<u8> {
    let mut x: Vec<u8> = big_uint.to_bytes_le().iter().flat_map(u8_to_bits).collect();
    x.resize(254, 0);
    x
}

fn to_exponent_bits(exponents: &[BigUint]) -> Vec<Vec<u8>> {
    exponents.iter().map(|x| to_bits(x)).collect()
}

fn main() {
    // On choisit la carte et les commandants
    let selected_config = InitialState::Nordic((10, 10), Commander::Orc, Commander::Orc);

    // On récupère le circuit et les états initiaux.
    let (mut state_joueur_a, mut state_joueur_b) = State::initial_states(selected_config);

    // (Décision qui est le joueur A et qui est le joueur B, et chacun ne fera que sa partie)
    
    // state_joueur_a.circuit_state.squares[9] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[8] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[7] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[6] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[5] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[4] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[3] = state_joueur_a.circuit_state.squares[0];
    // state_joueur_a.circuit_state.squares[2] = state_joueur_a.circuit_state.squares[0];

    // state_joueur_a.circuit_state.squares[0] = Square {
    //     unit: Unit::None,
    //     health_points: 0,
    //     captured: false,
    //     move_credits: 0,
    // };

    // state_joueur_a.append_transaction(Transaction::MoveUnit((100, 0), (2, 2)));
    // state_joueur_a.append_transaction(Transaction::MoveUnit((0, 0), (8, 8)));
    // state_joueur_a.append_transaction(Transaction::MoveUnit((2, 2), (4, 4)));
    // state_joueur_a.append_transaction(Transaction::MoveUnit((4, 4), (6, 6)));
    // state_joueur_a.append_transaction(Transaction::MoveUnit((6, 6), (8, 8)));
    println!("Au tour d'Ashley.");
    let begin = Instant::now();
    {
        // state_joueur_a.append_transaction(Transaction::MoveUnit((0, 0), (2, 2)));
        // state_joueur_a.circuit_state.squares[2] = state_joueur_a.circuit_state.squares[0];
        // state_joueur_a.circuit_state.squares[0] = Square {
        //     unit: Unit::None,
        //     health_points: 0,
        //     captured: false,
        //     move_credits: 0,
        // };
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        println!("Brandon veut une preuve !");
        // println!("Il n'aura qu'à se faire foutre.");
        let (proof, vk) = state_joueur_a.prove();
        let proof_res = proof.verify(
            &vk,
            2,
            state_joueur_a.initial_hash.clone(),
            vec![<halo2curves::grumpkin::G1 as halo2curves::group::Group>::Scalar::ZERO],
        );
        println!(
            "Brandon a trouvé la preuve d'Ashley de taille {} {:?}",
            serde_json::to_string(&proof).unwrap().len(),
            proof_res
        );
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_b.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_a.phase2(diffie_hellmann);
        state_joueur_b.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions d'Ashley. Au tour de Brandon.",
        begin.elapsed()
    );
    let begin = Instant::now();
    {
        let (exponents_a, part3_stuff, diffie_hellmann) = state_joueur_a.phase1();
        let (dh_output, hidden_tags, hidden_data) = state_joueur_b.phase2(diffie_hellmann);
        state_joueur_a.phase3(
            exponents_a,
            part3_stuff,
            dh_output,
            hidden_tags,
            hidden_data,
        );
    }
    println!(
        "{:?} pour valider les actions de Brandon. Au tour d'Ashley.",
        begin.elapsed()
    );
    let begin = Instant::now();
}
