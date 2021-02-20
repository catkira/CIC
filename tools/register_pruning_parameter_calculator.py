from calculate_register_pruning import *
import timeit

# example from Hogenauer paper
N=4
R=25
M=1
INP_DW=16
OUT_DW=16

start = timeit.default_timer()
B_j = calculate_register_pruning(R=R, N=N, M=M, INP_DW=INP_DW, OUT_DW=OUT_DW)
end = timeit.default_timer()
print(F"elapsed time {end - start} s")
print(B_j)

ret = 0
for i in range(1,2*N+2):
    print(f"B_j[{i}] = {B_j[i]}")
    ret += int(B_j[i])<<(32*(i))
print(F"pruning parameter = {ret}")
print(F"pruning parameter in hex = {hex(ret)}")
print("Use the hex string to set the PRUNE_BITS parameter of the CIC core")