#!/usr/bin/env bash

pushd phase1
circom -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
pushd phase2
circom -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
pushd phase3
circom -l ../../circomlib/circuits/ --c --r1cs --sym circuit.circom && make -C circuit_cpp
popd
