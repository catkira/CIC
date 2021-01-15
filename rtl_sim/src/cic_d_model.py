from fixedpoint import FixedPoint
from bitstring import BitArray

class Model:
    def __init__(self, R, M, N , INP_DW, OUT_DW, register_pruning=0):
        self.R = R
        self.M = M
        self.N = N
        self.INP_DW = INP_DW
        self.OUT_DW = OUT_DW
        self.register_pruning = register_pruning
    