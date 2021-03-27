from calculate_register_pruning import *
import numpy as np
from matplotlib import pyplot as plt

N = 6
M = 1
INP_DW = 16
fig = plt.figure(figsize=(16,9))
axs = []
axs.append(plt.subplot(3,2,1))
axs.append(plt.subplot(3,2,3, sharex = axs[0]))
axs.append(plt.subplot(3,2,2, sharex = axs[0], sharey = axs[0]))
axs.append(plt.subplot(3,2,4, sharex = axs[0], sharey = axs[1]))
axs.append(plt.subplot(3,1,3))
R = [4096,64]
for OUT_DW in np.arange(16,36,2):
    for i in range(len(R)):
        B_j = calculate_register_pruning(R=R[i],N=N,M=M,INP_DW=INP_DW,OUT_DW=OUT_DW, clip_Bj=False)  
        CIC_Filter_Gain = (R[i]*M)**N        
        Num_of_Bits_Growth = np.ceil(math.log2(CIC_Filter_Gain))
        B_max = Num_of_Bits_Growth + INP_DW 
        out_bits = B_max - B_j
        axs[0 + 2*i].plot(out_bits)
        axs[1 + 2*i].plot(B_j, label=str(OUT_DW))
fig.suptitle("Finding the best number of output bits when using register pruning")
axs[0].set_title("R = " + str(R[0]) + ",  N = " + str(N) + ",  M = " + str(M))
axs[0].text((axs[0].get_xlim())[1]*0.6,(axs[0].get_ylim())[1]*0.9, F"out ENOB={INP_DW + np.log(R[0])/np.log(4)}")
axs[0].set_ylabel("bits in stage")
axs[2].set_title("R = " + str(R[1]) + ",  N = " + str(N) + ",  M = " + str(M))
axs[1].set_xlabel("stage")
axs[1].set_ylabel("pruned bits")
axs[2].text((axs[2].get_xlim())[1]*0.6,(axs[2].get_ylim())[1]*0.9, F"out ENOB={INP_DW + np.log(R[1])/np.log(4)}")
axs[3].set_xlabel("stage")
box = axs[4].get_position()
axs[4].set_position([box.x0, box.y0 + box.height * 0.5, box.width, box.height * 0.5])
h,l = axs[1].get_legend_handles_labels()
axs[4].legend(h,l, borderaxespad=0, ncol=5, loc="upper center")
axs[4].axis("off")
plt.tight_layout()
plt.show()
