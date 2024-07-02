/*
MIT License

Copyright (c) 2024 MBelegris

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

pragma circom 2.0.0;

// Anemoi Hash Function
// Steps:
// For each round:
// 1. Constant Addition
// 2. Linear Layer
// 3. PHT
// 4. S-box layer H (flystel network)
// Final step:
// Linear Layer

template constantAddition(nInputs){
    // x and y are added by the the round constants for that specific round
    signal input c[nInputs];
    signal input d[nInputs];

    signal input X[nInputs];
    signal input Y[nInputs];

    signal output outX[nInputs];
    signal output outY[nInputs];
    
    for (var i=0; i < nInputs; i++){
        outX[i] <== X[i] + c[i];
        outY[i] <== Y[i] + d[i];    
    }
}

template wordPermutation(nInputs){
    signal input vector[nInputs];

    signal output out[nInputs];

    for (var i = 1; i < nInputs; i++){
        out[i-1] <== vector[i];
    }
    out[nInputs-1] <== vector[0];
}

template diffusionLayer(nInputs){
    // The diffusion layer M: M(X,Y) = (Mx(X), My(Y))
    // Mx(X) = 
    // My(Y) = Mx o ρ(Y)
    // ρ(Y) = (y_1,...,y_l-1, y_0)
    signal input X[nInputs];
    signal input Y[nInputs]; 
    signal input g; // generator

    component wordPermutation = wordPermutation(nInputs);
    wordPermutation.vector <== Y;

    signal output outX[nInputs];
    signal output outY[nInputs];

    var matrix[nInputs][nInputs];

    if (nInputs == 1){
        outX <== X;
        outY <== wordPermutation.out;
    }
    else{
        signal g_squared <== g*g;
        if (nInputs == 2){
            outX[0] <== X[0] + (X[1]*g);
            signal inter_x[3];
            inter_x[0] <== g_squared + 1;
            inter_x[1] <== X[1] * inter_x[0];
            inter_x[2] <== (X[0] * g) + inter_x[1];
            outX[1] <== inter_x[2];

            signal inter_y[3];
            inter_y[0] <== g_squared + 1;
            inter_y[1] <== wordPermutation.out[1] * inter_y[0];
            inter_y[2] <== (wordPermutation.out[0]*g) + inter_y[1];
            outY[0] <== wordPermutation.out[0] + (wordPermutation.out[1]*g);
            outY[1] <== inter_y[2];
        }
        if (nInputs == 3){
            signal inter_x0[3];
            inter_x0[0] <== X[0] * (g+1);
            inter_x0[1] <== X[1] + inter_x0[0];
            inter_x0[2] <== (X[2] * (g+1)) + inter_x0[1];

            signal inter_x1[3];
            inter_x1[0] <== X[0];
            inter_x1[1] <== X[1] + inter_x1[0];
            inter_x1[2] <== (X[2] * g) + inter_x1[1];

            signal inter_x2[3];
            inter_x2[0] <== X[0] * g;
            inter_x2[1] <== X[1] + inter_x2[0];
            inter_x2[2] <== X[2] + inter_x2[1];

            outX[0] <== inter_x0[2];
            outX[1] <== inter_x1[2];
            outX[2] <== inter_x2[2];

            
            signal inter_y0[3];
            inter_y0[0] <== wordPermutation.out[0] * (g+1);
            inter_y0[1] <== wordPermutation.out[1] + inter_y0[0];
            inter_y0[2] <== (wordPermutation.out[2] * (g+1)) + inter_y0[1];

            signal inter_y1[3];
            inter_y1[0] <== wordPermutation.out[0];
            inter_y1[1] <== wordPermutation.out[1] + inter_y1[0];
            inter_y1[2] <== (wordPermutation.out[2] * g) + inter_y1[1];
            
            signal inter_y2[3];
            inter_y2[0] <== wordPermutation.out[0] * g;
            inter_y2[1] <== wordPermutation.out[1] + inter_y2[0];
            inter_y2[2] <== wordPermutation.out[2] + inter_y2[1];

            outY[0] <== inter_y0[2];
            outY[1] <== inter_y1[2];
            outY[2] <== inter_y2[2];
        }
        if (nInputs == 4){
            signal inter_x0[4];
            inter_x0[0] <== X[0];
            inter_x0[1] <== X[1]*(1+g);
            inter_x0[2] <== X[2]*g;
            inter_x0[3] <== X[3]*g;
            
            signal inter_x1[4];
            inter_x1[0] <== X[0]*g_squared;
            inter_x1[1] <== X[1]*(g+g_squared);
            inter_x1[2] <== X[2]*(1+g);
            inter_x1[3] <== X[3]*(1+(2*g));

            signal inter_x2[4];
            inter_x2[0] <== X[0]*g_squared;
            inter_x2[1] <== X[1]*g_squared;
            inter_x2[2] <== X[2];
            inter_x2[3] <== X[3]*(1+g);
            
            signal inter_x3[4];
            inter_x3[0] <== X[0]*(1+g);
            inter_x3[1] <== X[1]*(1+(2*g));
            inter_x3[2] <== X[2]*g;
            inter_x3[3] <== X[3]*(1+g);

            outX[0] <== inter_x0[3] + inter_x0[2] + inter_x0[1] + inter_x0[0];
            outX[1] <== inter_x1[3] + inter_x1[2] + inter_x1[1] + inter_x1[0];
            outX[2] <== inter_x2[3] + inter_x2[2] + inter_x2[1] + inter_x2[0];
            outX[3] <== inter_x3[3] + inter_x3[2] + inter_x3[1] + inter_x3[0];

            signal inter_y0[4];
            inter_y0[0] <== wordPermutation.out[0];
            inter_y0[1] <== wordPermutation.out[1]*(1+g);
            inter_y0[2] <== wordPermutation.out[2]*g;
            inter_y0[3] <== wordPermutation.out[3]*g;
            
            signal inter_y1[4];
            inter_y1[0] <== wordPermutation.out[0]*g_squared;
            inter_y1[1] <== wordPermutation.out[1]*(g+g_squared);
            inter_y1[2] <== wordPermutation.out[2]*(1+g);
            inter_y1[3] <== wordPermutation.out[3]*(1+(2*g));

            signal inter_y2[4];
            inter_y2[0] <== wordPermutation.out[0]*g_squared;
            inter_y2[1] <== wordPermutation.out[1]*g_squared;
            inter_y2[2] <== wordPermutation.out[2];
            inter_y2[3] <== wordPermutation.out[3]*(1+g);
            
            signal inter_y3[4];
            inter_y3[0] <== wordPermutation.out[0]*(1+g);
            inter_y3[1] <== wordPermutation.out[1]*(1+(2*g));
            inter_y3[2] <== wordPermutation.out[2]*g;
            inter_y3[3] <== wordPermutation.out[3]*(1+g);

            outY[0] <== inter_y0[3] + inter_y0[2] + inter_y0[1] + inter_y0[0];
            outY[1] <== inter_y1[3] + inter_y1[2] + inter_y1[1] + inter_y1[0];
            outY[2] <== inter_y2[3] + inter_y2[2] + inter_y2[1] + inter_y2[0];
            outY[3] <== inter_y3[3] + inter_y3[2] + inter_y3[1] + inter_y3[0];
        }
        if (nInputs > 4){
            // TODO: Implement circulant mds matrix
        }
    }
}

template PHT(nInputs){
    // PHT P does the following
    // Y <- Y + X
    // X <- X + Y
    signal input X[nInputs];
    signal input Y[nInputs];

    signal output outX[nInputs];
    signal output outY[nInputs];

    for (var i = 0; i < nInputs; i++){
        outY[i] <== Y[i] + X[i];
        outX[i] <== X[i] + outY[i];
    }
}

template exponentiate(exponent){
    signal input in;
    signal output out;

    signal stor[exponent+1];

    for (var i = 0; i < exponent; i++){
        if (i == 0){
            stor[i] <== in;
        }
        else{
            stor[i] <== stor[i-1] * in;
        }
    }
    out <== stor[exponent-1];
}

function fast_exp(base, exponent) {
    var result = 1;
    while (exponent > 0){
        if (exponent % 2 == 1){
            result = result*base;
            exponent = exponent - 1;
        }
        base = base*base;
        exponent = exponent / 2;
    }
    return result;
}

template openFlystel(alpha){
    // Open Flystel network H maps (x,y) to (u,v)
    // 1. x <- x - Qγ(y)
    // 2. y <- y - E^-1(x)
    // 3. x <- x + Qγ(y)
    // 4. y <- x, v <- y

    // Qγ = β(x^a) + γ
    // Qδ = β(x^a) + δ
    // E^-1 = x^1/a

    signal input x;
    signal input y;
    signal input beta;
    signal input gamma;
    signal input delta;

    signal output u;
    signal output v;

    signal t; // as taken from the paper

    signal y_square <== y*y;

    t <== x - (beta*y_square) - gamma;
    
    var t_power_inv = fast_exp(t, alpha);
    signal t_power_inv_a <-- t_power_inv;

    v <== y - t_power_inv_a;

    signal v_squared <== v*v;

    u <== t + (beta*v_squared) + delta;
}

template closedFlystel(nInputs, alpha){
    // Closed Flystel verifies that (x,u) = V(y,v)
    // Equivalent to checking if (u,v) = H(x,y)
    // x = Qγ(y) + E(y-v)
    // v = Qδ(v) + E(y-v)

    signal input y;
    signal input v;

    signal input beta;
    signal input gamma;
    signal input delta;

    signal output x;
    signal output u;

    signal y_squared <== y*y;
    signal v_squared <== v*v;
    signal sub <== y-v;

    var t = fast_exp(sub, alpha);
    x <== beta*y_squared + gamma + t;
    u <== beta*v_squared + t;
}

template sBox(nInputs, alpha){
    // Let H be an open Flystel operating on Fq. Then Sbox S:
    // S(X, Y) = H(x0,y1),...,H(xl-1,yl-1)
    signal input X[nInputs];
    signal input Y[nInputs];
    signal input beta;
    signal input gamma;
    signal input delta;

    signal output outX[nInputs];
    signal output outY[nInputs];

    component flystel[nInputs];

    for (var i = 0; i < nInputs; i++){       
        flystel[i] = openFlystel(alpha);
        flystel[i].x <== X[i];
        flystel[i].y <== Y[i];
        flystel[i].beta <== beta;
        flystel[i].gamma <== gamma;
        flystel[i].delta <== delta;
            
        outX[i] <== flystel[i].u;
        outY[i] <== flystel[i].v;
    }
}

template sBoxVerify(nInputs, alpha){
    // TODO: add verification algorithm to 
    // Let H be an closed Flystel operating on Fq. Then Sbox S:
    // S(X, Y) = H(x0,y1),...,H(xl-1,yl-1)
    signal input Y[nInputs];
    signal input V[nInputs];
    signal input beta;
    signal input gamma;
    signal input delta;

    signal output outX[nInputs];
    signal output outU[nInputs];

    component flystel[nInputs];

    for (var i = 0; i < nInputs; i++){       
        flystel[i] = closedFlystel(nInputs, alpha);
        flystel[i].y <== Y[i];
        flystel[i].v <== V[i];
        flystel[i].beta <== beta;
        flystel[i].gamma <== gamma;
        flystel[i].delta <== delta;
            
        outX[i] <== flystel[i].x;
        outU[i] <== flystel[i].u;
    }
}

template Anemoi(nInputs, numRounds, exp, inv_exp){
    // State of Anemoi is a 2 row matrix:
    // X[x_0,...,x_l-1]
    // Y[y_0,...,y_l-1]

    // Constantes de round jusqu'à 19 constantes, pour le cas d'utilisation
    // préconisé par le papier
    var c[19][1] = [[37],
    [13352247125433170118601974521234241686699252132838635793584252509352796067497],
    [8959866518978803666083663798535154543742217570455117599799616562379347639707],
    [3222831896788299315979047232033900743869692917288857580060845801753443388885],
    [11437915391085696126542499325791687418764799800375359697173212755436799377493],
    [14725846076402186085242174266911981167870784841637418717042290211288365715997],
    [3625896738440557179745980526949999799504652863693655156640745358188128872126],
    [463291105983501380924034618222275689104775247665779333141206049632645736639],
    [17443852951621246980363565040958781632244400021738903729528591709655537559937],
    [10761214205488034344706216213805155745482379858424137060372633423069634639664],
    [1555059412520168878870894914371762771431462665764010129192912372490340449901],
    [7985258549919592662769781896447490440621354347569971700598437766156081995625],
    [9570976950823929161626934660575939683401710897903342799921775980893943353035],
    [17962366505931708682321542383646032762931774796150042922562707170594807376009],
    [12386136552538719544323156650508108618627836659179619225468319506857645902649],
    [21184636178578575123799189548464293431630680704815247777768147599366857217074],
    [3021529450787050964585040537124323203563336821758666690160233275817988779052],
    [7005374570978576078843482270548485551486006385990713926354381743200520456088],
    [3870834761329466217812893622834770840278912371521351591476987639109753753261]];
    var d[19][1] =
    [[8755297148735710088898562298102910035419345760166413737479281674630323398284],
    [5240474505904316858775051800099222288270827863409873986701694203345984265770],
    [9012679925958717565787111885188464538194947839997341443807348023221726055342],
    [21855834035835287540286238525800162342051591799629360593177152465113152235615],
    [11227229470941648605622822052481187204980748641142847464327016901091886692935],
    [8277823808153992786803029269162651355418392229624501612473854822154276610437],
    [20904607884889140694334069064199005451741168419308859136555043894134683701950],
    [1902748146936068574869616392736208205391158973416079524055965306829204527070],
    [14452570815461138929654743535323908350592751448372202277464697056225242868484],
    [10548134661912479705005015677785100436776982856523954428067830720054853946467],
    [17068729307795998980462158858164249718900656779672000551618940554342475266265],
    [16199718037005378969178070485166950928725365516399196926532630556982133691321],
    [19148564379197615165212957504107910110246052442686857059768087896511716255278],
    [5497141763311860520411283868772341077137612389285480008601414949457218086902],
    [18379046272821041930426853913114663808750865563081998867954732461233335541378],
    [7696001730141875853127759241422464241772355903155684178131833937483164915734],
    [963844642109550260189938374814031216012862679737123536423540607519656220143],
    [12412434690468911461310698766576920805270445399824272791985598210955534611003],
    [6971318955459107915662273112161635903624047034354567202210253298398705502050]];

    // Racine primitive modulo 21888242871839275222246405745257275088548364400416034343698204186575808495617
    // Calculée avec SageMath en évaluant primitive_root(n)
    var g = 5;
    var inv_g = 1/5;

    signal input X[nInputs];
    signal input Y[nInputs];
    signal output outX[nInputs];
    signal output outY[nInputs];

    signal roundX[(4*numRounds) + 1][nInputs];
    signal roundY[(4*numRounds) + 1][nInputs];

    signal verifyX[numRounds][nInputs];
    signal verifyU[numRounds][nInputs];

    // Stores round constants for each round
    // signal c[nInputs]; 
    // signal d[nInputs];

    // for (var i = 0; i < nInputs; i++){
    //     c[i] <== roundConstantC;
    //     d[i] <== roundConstantD;
    // }

    roundX[0] <== X;
    roundY[0] <== Y;

    component constantAddition[numRounds];
    component diffusionLayer[numRounds + 1];
    component phtLayer[numRounds + 1];
    component sBox[numRounds];

    component verify[numRounds];

    for (var i = 0; i < numRounds; i++){
        // Constant Addition A
        constantAddition[i] = constantAddition(nInputs);
        constantAddition[i].c <== c[i];
        constantAddition[i].d <== d[i];
        constantAddition[i].X <== roundX[4*i]; 
        constantAddition[i].Y <== roundY[4*i]; 
        roundX[(4*i)+1] <== constantAddition[i].outX;
        roundY[(4*i)+1] <== constantAddition[i].outY;

        // Linear Layer M
        diffusionLayer[i] = diffusionLayer(nInputs);
        diffusionLayer[i].X <== roundX[(4*i)+1];
        diffusionLayer[i].Y <== roundY[(4*i)+1];
        diffusionLayer[i].g <== g;
        roundX[(4*i)+2] <== diffusionLayer[i].outX;
        roundY[(4*i)+2] <== diffusionLayer[i].outY;

        // PHT P
        phtLayer[i] = PHT(nInputs);
        phtLayer[i].X <== roundX[(4*i) + 2];
        phtLayer[i].Y <== roundY[(4*i) + 2];
        roundX[(4*i) + 3] <== phtLayer[i].outX;
        roundY[(4*i) + 3] <== phtLayer[i].outY;

        // S-box Layer H
        // Implementing Qγ(x) = gx^a + g^-1
        // Implementing Qδ(x) = gx^a
        // Implementing E^-1 = x^1/a
        sBox[i] = sBox(nInputs, inv_exp);
        sBox[i].X <== roundX[(4*i) + 3];
        sBox[i].Y <== roundY[(4*i) + 3];
        sBox[i].beta <== g;
        sBox[i].gamma <== inv_g;
        sBox[i].delta <== 0;
        roundX[(4*i) + 4] <== sBox[i].outX;
        roundY[(4*i) + 4] <== sBox[i].outY;

        // Verifying the output of the sBox
        // verify[i] = sBoxVerify(nInputs, exp);
        // verify[i].Y <== roundY[(4*i) + 3]; // original y
        // verify[i].V <== roundY[(4*i) + 4]; // new y
        // verify[i].beta <== g;
        // verify[i].gamma <== inv_g;
        // verify[i].delta <== 0;

        // verify[i].outX === roundX[(4*i) + 3];
        // verify[i].outU === roundX[(4*i) + 4];
    }
    // One final diffusion before returning the Anemoi permutation
    diffusionLayer[numRounds] = diffusionLayer(nInputs);
    diffusionLayer[numRounds].X <== roundX[4*numRounds];
    diffusionLayer[numRounds].Y <== roundY[4*numRounds];
    diffusionLayer[numRounds].g <== g;

    phtLayer[numRounds] = PHT(nInputs);
    phtLayer[numRounds].X <== diffusionLayer[numRounds].outX;
    phtLayer[numRounds].Y <== diffusionLayer[numRounds].outY;

    outX <== phtLayer[numRounds].outX;
    outY <== phtLayer[numRounds].outY;
}
