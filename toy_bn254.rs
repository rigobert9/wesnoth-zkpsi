use std::{collections::HashMap, env::current_dir, time::Instant};
use std::io::BufReader;
use std::fs::File;
use std::io::{BufWriter, Write};
use halo2curves::bn256::Fr;
use num_bigint::{ToBigInt, Sign};
use num_bigint::BigInt;

use nova_scotia::{
    circom::reader::load_r1cs, continue_recursive_circuit, create_public_params,
    create_recursive_circuit, FileLocation, F, S,
};
use nova_snark::{provider, CompressedSNARK, PublicParams};
use nova_snark::traits::Group;
use serde_json::json;
use bincode::{deserialize_from, serialize_into};

fn string_to_f1(s : &String) -> Fr {
    let mut out = [0;32];
    match s.parse::<BigInt>().unwrap().to_bytes_le() {
        (Sign::Plus, v) => { for i in 0..v.len() { out[v.len() - i - 1] = v[v.len() - i - 1]; } },
        _ => panic!()
    }
    Fr::from_bytes(&out).unwrap()
}

fn run_test(circuit_filepath: String, witness_gen_filepath: String) {
    type G1 = provider::bn256_grumpkin::bn256::Point;
    type F1 = provider::bn256_grumpkin::bn256::Scalar;
    type G2 = provider::bn256_grumpkin::grumpkin::Point;

    println!(
        "Running test with witness generator: {} and group: {}",
        witness_gen_filepath,
        std::any::type_name::<G1>()
    );
    let iteration_count = 1;
    let root = current_dir().unwrap();

    println!("Génération des objets de circuit.");

    let circuit_file = root.join(circuit_filepath);
    let r1cs = load_r1cs::<G1, G2>(&FileLocation::PathBuf(circuit_file));
    let witness_generator_file = root.join(witness_gen_filepath);

    println!("Entrée des inputs.");

    let input_file = File::open(root.join("../wesnoth-zkpsi/phase2nova/start.json")).unwrap();
    let input_reader = BufReader::new(input_file);
    let mut inputs : HashMap<String, serde_json::Value> = serde_json::from_reader(input_reader).unwrap();
    let public_input: Vec<_> = match inputs.get("step_in").unwrap() {
        serde_json::Value::Array(a) => a.iter().map(|u| match u {
            serde_json::Value::String(s) => string_to_f1(s),
            _ => panic!(),
        }).collect(),
        _ => panic!()
    };
    inputs.remove("step_in");
    let mut private_inputs = inputs;
    
    let pp: PublicParams<G1, G2, _, _>;

    let start = Instant::now();
    let key_path = root.join("../public_parameters");
    if key_path.exists() {
        println!("Lecture des paramètres publics.");
        let parameters_file = File::open(key_path).unwrap();
        let parameters_writer = BufReader::new(parameters_file);
        pp = deserialize_from(parameters_writer).unwrap();
    } else {
        println!("Génération des paramètres publics.");
        pp = create_public_params(r1cs.clone());
        // Écrire dans un fichier les paramètres une fois calculés.
        let parameters_file = File::create(key_path).unwrap();
        let parameters_writer = BufWriter::new(parameters_file);
        serialize_into(parameters_writer, &pp).unwrap();
    }

    println!("Paramètres publics obtenus en {:?}", start.elapsed());

    println!(
        "Number of constraints per step (primary circuit): {}",
        pp.num_constraints().0
    );
    println!(
        "Number of constraints per step (secondary circuit): {}",
        pp.num_constraints().1
    );

    println!(
        "Number of variables per step (primary circuit): {}",
        pp.num_variables().0
    );
    println!(
        "Number of variables per step (secondary circuit): {}",
        pp.num_variables().1
    );

    println!("Creating a RecursiveSNARK...");
    let start = Instant::now();
    let mut recursive_snark = create_recursive_circuit(
        FileLocation::PathBuf(witness_generator_file),
        r1cs, // .clone(),
        vec![private_inputs],
        public_input.clone(),
        &pp,
    )
    .unwrap();
    println!("RecursiveSNARK creation took {:?}", start.elapsed());

    // TODO: empty?
    let z0_secondary = [F::<G2>::from(0)];

    // verify the recursive SNARK
    println!("Verifying a RecursiveSNARK...");
    let start = Instant::now();
    let res = recursive_snark.verify(&pp, iteration_count, &public_input, &z0_secondary);
    println!(
        "RecursiveSNARK::verify: {:?}, took {:?}",
        res,
        start.elapsed()
    );
    assert!(res.is_ok());

    /*
    // produce a compressed SNARK
    println!("Generating a CompressedSNARK using Spartan with IPA-PC...");
    let start = Instant::now();
    let (pk, vk) = CompressedSNARK::<_, _, _, _, S<G1>, S<G2>>::setup(&pp).unwrap();
    let res = CompressedSNARK::<_, _, _, _, S<G1>, S<G2>>::prove(&pp, &pk, &recursive_snark);
    println!(
        "CompressedSNARK::prove: {:?}, took {:?}",
        res.is_ok(),
        start.elapsed()
    );
    assert!(res.is_ok());
    let compressed_snark = res.unwrap();

    // verify the compressed SNARK
    println!("Verifying a CompressedSNARK...");
    let start = Instant::now();
    let res = compressed_snark.verify(
        &vk,
        iteration_count,
        public_input,
        z0_secondary.to_vec(),
    );
    println!(
        "CompressedSNARK::verify: {:?}, took {:?}",
        res.is_ok(),
        start.elapsed()
    );
    assert!(res.is_ok());
    */

    /*
    // continue recursive circuit by adding 2 further steps
    println!("Adding steps to our RecursiveSNARK...");
    let start = Instant::now();

    let iteration_count_continue = 2;

    let mut private_inputs_continue = Vec::new();
    for i in 0..iteration_count_continue {
        let mut private_input = HashMap::new();
        private_input.insert("adder".to_string(), json!(5 + i));
        private_inputs_continue.push(private_input);
    }

    let res = continue_recursive_circuit(
        &mut recursive_snark,
        z_last,
        FileLocation::PathBuf(witness_generator_file),
        r1cs,
        private_inputs_continue,
        public_input,
        &pp,
    );
    assert!(res.is_ok());
    println!(
        "Adding 2 steps to our RecursiveSNARK took {:?}",
        start.elapsed()
    );

    // verify the recursive SNARK with the added steps
    println!("Verifying a RecursiveSNARK...");
    let start = Instant::now();
    let res = recursive_snark.verify(&pp, iteration_count + iteration_count_continue, &public_input, &z0_secondary);
    println!(
        "RecursiveSNARK::verify: {:?}, took {:?}",
        res,
        start.elapsed()
    );
    assert!(res.is_ok());

    assert_eq!(res.clone().unwrap().0[0], F::<G1>::from(31));
    assert_eq!(res.unwrap().0[1], F::<G1>::from(115));
    */
}

fn main() {
    // let group_name = "bn254";

    let circuit_filepath = "../wesnoth-zkpsi/phase2nova/circuit.r1cs";
    for witness_gen_filepath in [
        "../wesnoth-zkpsi/phase2nova/circuit_cpp/circuit",
        "../wesnoth-zkpsi/phase2nova/circuit_js/circuit.wasm",
    ] {
        run_test(circuit_filepath.to_string(), witness_gen_filepath.to_string());
    }
}
