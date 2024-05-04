#!/usr/bin/env bash

pushd phase1
python gen_input.py
./circuit_cpp/circuit start.json witness.wtns
popd
pushd phase2
python gen_input.py
./circuit_cpp/circuit start.json witness.wtns
popd
pushd phase3
python gen_input.py
./circuit_cpp/circuit start.json witness.wtns
popd
