import math
import numpy as np



def binom(n, k):
    # using factorial is very slow
    #return math.factorial(n) // math.factorial(k) // math.factorial(n - k)
    return math.comb(n,k)

# this function is not needed for the model
# TODO: outsource it to a separate file
def calculate_register_pruning(R, N, M, INP_DW, OUT_DW, clip_Bj=True):
    # calculate register pruning as described in Hogenauer, 1981
    CIC_Filter_Gain = (R*M)**N        
    Num_of_Bits_Growth = np.ceil(math.log2(CIC_Filter_Gain))
    B_max = Num_of_Bits_Growth + INP_DW   
    
    F_j = np.zeros(2*N + 2)
    for j in np.arange(2*N,0,-1):
        h_j = np.zeros((R*M-1)*N + 2*N)
        if j <= N:
            for k in np.arange((R*M-1)*N + j - 1):
                for L in range(int(np.floor(k/(R*M))) + 1):
                    h_j[k] += (-1)**L*binom(N, L)*binom(N - j + k - R*M*L, k - R*M*L)
        else:
            for k in np.arange(2*N + 1 - j + 1):
                h_j[k] = (-1)**k*binom(2*N + 1 - j, k)

        F_j[j] = np.sqrt(np.dot(h_j,h_j))

    F_j[2*N + 1]=1

    Num_of_Output_Bits_Truncated = B_max - OUT_DW
    sigma = np.sqrt((2**Num_of_Output_Bits_Truncated)**2/12)

    B_j = np.floor(-np.log2(F_j) + np.log2(sigma) + 0.5*math.log2(6/N));      
    if clip_Bj:
        B_j = np.clip(B_j, 0, None)
    out_bits = B_max - B_j

    # last items need some special treatment
    B_j[2*N+1] = B_max - OUT_DW
    out_bits[2*N+1] = OUT_DW

    for j in np.arange(1, 2*N+2):
        print(f"F_{j} = {F_j[j]:.6f}  \t -log_2(F_j) = {-np.log2(F_j[j]):.6f} \t B_j = {B_j[j]} \t bits = {out_bits[j]}")            
    return B_j