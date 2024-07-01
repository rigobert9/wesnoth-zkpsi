#!/usr/bin/env bash

pushd phase1
circom --O2 -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
pushd phase2
circom --O2 -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
pushd phase3
circom --O2 -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
