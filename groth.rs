use ark_bn254::Bn254;
use ark_circom::{CircomBuilder, CircomConfig};
use ark_crypto_primitives::snark::SNARK;
use ark_groth16::Groth16;
use ark_std::rand::thread_rng;
use color_eyre::Result;
use std::{collections::HashMap, env::current_dir, time::Instant};
use std::io::BufReader;
use std::fs::File;
use std::io::{BufWriter, Write};
use serde_json::json;
use num_bigint::BigInt;
use ark_circom::circom::Inputs;
use std::str::FromStr;

type GrothBn = Groth16<Bn254>;

#[test]
fn groth16_proof() -> Result<()> {
    let mut start = Instant::now();
    let root = current_dir().unwrap();
    println!("Chargement de la config et entrée des inputs.");
    let cfg = CircomConfig::<Bn254>::new(
        root.join("../wesnoth-zkpsi/phase2/circuit_js/circuit.wasm"),
        root.join("../wesnoth-zkpsi/phase2/circuit.r1cs"),
    )?;
    let mut builder = CircomBuilder::new(cfg);

    let input_file = File::open(root.join("../wesnoth-zkpsi/phase2/start.json")).unwrap();
    let input_reader = BufReader::new(input_file);
    let mut inputs : HashMap<String, serde_json::Value> = serde_json::from_reader(input_reader).unwrap();
    let _ = inputs.iter().map(|(key,val)| match val {
        serde_json::Value::String(s) =>
            builder.push_input(key, Inputs::BigInt(BigInt::from_str(s).unwrap())),
        serde_json::Value::Array(a) => match &a[0] {
            serde_json::Value::String(_s) =>
                builder.push_input(key, Inputs::BigIntVec(
                        a.iter().map(|s| BigInt::from_str(s.as_str().unwrap()).unwrap()).collect())),
            serde_json::Value::Array(_a) =>
                builder.push_input(key, Inputs::BigIntVecVec(
                        a.iter().map(|b| b.as_array().unwrap().iter().map(
                            |s| BigInt::from_str(s.as_str().unwrap()).unwrap()
                            ).collect()).collect())),
            _ => panic!("Mal formaté")
        },
        _ => panic!("Mal formaté")
    });

    // create an empty instance for setting it up
    let circom = builder.setup();
    let mut end = Instant::now();
    println!("> Fait en {:?}", end - start);

    start = end;
    println!("Génération des paramètres publics");
    let mut rng = thread_rng();
    let params = GrothBn::generate_random_parameters_with_reduction(circom, &mut rng)?;
    end = Instant::now();
    println!("> Fait en {:?}", end - start);

    let circom = builder.build()?;

    let inputs = circom.get_public_inputs().unwrap();

    start = end;
    println!("Preuve du circuit");
    let proof = GrothBn::prove(&params, circom, &mut rng)?;
    end = Instant::now();
    println!("> Fait en {:?}", end - start);

    start = end;
    println!("Création de la clé de vérification");
    let pvk = GrothBn::process_vk(&params.vk).unwrap();
    end = Instant::now();
    println!("> Fait en {:?}", end - start);

    start = end;
    println!("Vérification de la preuve");
    let verified = GrothBn::verify_with_processed_vk(&pvk, &inputs, &proof)?;
    end = Instant::now();
    println!("> Fait en {:?}", end - start);

    assert!(verified);

    Ok(())
}