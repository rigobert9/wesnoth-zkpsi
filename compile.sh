# $1 height, $2 width

function change_last_line () {
  pushd $1;
    sed -i '$ d' $2;
    echo "$4" >> $2;
    circom -l ~/Téléchargements/zkpsi/circomlib/circuits/ --c --r1cs --O2 --prime bn128 $2;
    make -j12 -C $3;
  popd;
}

pushd wesnoth-zkpsi
  change_last_line hash hash_state.circom hash_state_cpp $"component main = Main(($1 "'*'" $2) "'*'" 4 + 3);"
  change_last_line phase1 circuit.circom circuit_cpp $"component main {public [degats, captures]} = Final($1 "'*'" $2, $1, $2 , 10, 0, 1, 64, 8, [50,90,5,45,54,94,9,49], 9, [0,58,32,26,33,38,42,32,18], [0,5,5,6,7,5,4,8,5], [0,-1,14,17,14,12,13,17,9], 2, [0, 99], 6, [[0,1], [0,10], [0,20], [1,89], [1,98], [1,79]]);"
  change_last_line phase2nova circuit.circom circuit_cpp $"component main {public [step_in]} = Final($1 "'*'" $2, $1, $2, 10, 0, 1, 8, [50,90,5,45,54,94,9,49], 9, [0,58,32,26,33,38,42,32,18], [0,5,5,6,7,5,4,8,5], [0,-1,14,17,14,12,13,17,9], 2, [0, 99], 6, [[0,1], [0,10], [0,20], [1,89], [1,98], [1,79]]);"
  change_last_line phase3 circuit.circom circuit_cpp $"component main = Final($1 "'*'" $2,0,1);"
popd