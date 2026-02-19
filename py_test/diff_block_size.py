import numpy as np
from sympy.physics.quantum.gate import normalized

import functions
from datetime import datetime
import matplotlib.pyplot as plt
from scipy.stats import t as student_t
from functions import quantize_matrix_e5m2, quantize_matrix_e4m3, quantize_matrix_int8

#################################parameters############################################
np.random.seed(int(datetime.now().timestamp()))

matrix_col_dim = 32*16
matrix_row_dim = 32*16

variation = 10
variance = variation / 3
df = 3000
normalized = True

block_size_list = [ 8, 16, 32, 64]

# 保存按 block_size 分类的误差
results_mre = {}
results_rmse = {}

#################################metric functions######################################
def compute_metrics(C_ref, C_test, eps=1e-12):
    abs_err = np.abs(C_ref - C_test)
    mae = np.mean(abs_err)
    mse = np.mean((C_ref - C_test) ** 2)
    rel_err = abs_err / (np.abs(C_ref) + eps)
    mre = np.mean(rel_err)
    rmse = np.sqrt(mse)
    sigma_ref = np.std(C_ref)
    nrmse = rmse / (sigma_ref)
    return mae, mse, mre, nrmse

#################################main loop#############################################
for block_size in block_size_list:

    print(f"\n======= Block Size = {block_size} =======")

    A_fp64 = student_t(df=df, scale=variance).rvs(
        (matrix_row_dim, matrix_col_dim)
    ).astype(np.float64)

    B_fp64 = student_t(df=df, scale=variance).rvs(
        (matrix_row_dim, matrix_col_dim)
    ).astype(np.float64)

    # fp32 baseline
    A_fp32 = A_fp64.astype(np.float32)
    B_fp32 = B_fp64.astype(np.float32)

    # fp16
    A_fp16 = A_fp64.astype(np.float16)
    B_fp16 = B_fp64.astype(np.float16)

    # E5M2
    A_E5M2, _ = quantize_matrix_e5m2(A_fp64, block_size=block_size, normalized=normalized)
    B_E5M2, _ = quantize_matrix_e5m2(B_fp64, block_size=block_size, normalized=normalized)

    # E4M3
    A_E4M3, _ = quantize_matrix_e4m3(A_fp64, block_size=block_size, normalized=normalized)
    B_E4M3, _ = quantize_matrix_e4m3(B_fp64, block_size=block_size, normalized=normalized)

    # INT8
    A_INT8, _ = quantize_matrix_int8(A_fp64, block_size=block_size, normalized=normalized)
    B_INT8, _ = quantize_matrix_int8(B_fp64, block_size=block_size, normalized=normalized)

    # matrix multiplication
    C_fp32 = np.matmul(A_fp32, B_fp32)
    C_fp16 = np.matmul(A_fp16.astype(np.float32), B_fp16.astype(np.float32))
    C_E5M2 = np.matmul(A_E5M2.astype(np.float32), B_E5M2.astype(np.float32))
    C_E4M3 = np.matmul(A_E4M3.astype(np.float32), B_E4M3.astype(np.float32))
    C_INT8 = np.matmul(A_INT8.astype(np.float32), B_INT8.astype(np.float32))

    # calculate metrics
    mae_fp16, mse_fp16, mre_fp16, rmse_fp16 = compute_metrics(C_fp32, C_fp16)
    mae_e5m2, mse_e5m2, mre_e5m2, rmse_e5m2 = compute_metrics(C_fp32, C_E5M2)
    mae_e4m3, mse_e4m3, mre_e4m3, rmse_e4m3 = compute_metrics(C_fp32, C_E4M3)
    mae_int8, mse_int8, mre_int8, rmse_int8 = compute_metrics(C_fp32, C_INT8)

    results_mre[block_size] = {"FP16": mre_fp16, "E5M2": mre_e5m2, "E4M3": mre_e4m3, "INT8": mre_int8}
    results_rmse[block_size] = {"FP16": rmse_fp16, "E5M2": rmse_e5m2, "E4M3": rmse_e4m3, "INT8": rmse_int8}

    print(f"\n--- Variation = {variation}, block_size = {block_size} ---")
    print(f"{'DataType':<6s} | {'NRMSE':>12s} | {'MRE(%)':>12s}")
    print("-" * 35)
    for dtype in ["FP16", "E5M2", "E4M3", "INT8"]:
        print(
            f"{dtype:<6s} | {results_rmse[block_size][dtype]:12.6e} | {results_mre[block_size][dtype] * 100:12.4f}")

#################################plotting###############################################

data_types = ["FP16", "INT8", "E4M3", "E5M2"]
fig, axes = plt.subplots(1, 1, figsize=(8, 8))

# ---- NRMSE ----
ax = axes
for block_size in block_size_list:
    y = [results_rmse[block_size][dt] for dt in data_types]
    ax.plot(data_types, y, marker='o', label=f"block={block_size}")
ax.set_title("NRMSE vs Data Type")
ax.set_ylabel("NRMSE")
ax.grid(True, linestyle='--', alpha=0.6)
ax.legend(title="Block Size", loc="upper left")

# # ---- MRE ----
# ax = axes[1]
# for block_size in block_size_list:
#     y = [results_mre[block_size][dt] * 100 for dt in data_types]
#     ax.plot(data_types, y, marker='o', label=f"block={block_size}")
# ax.set_title("MRE (%) vs Data Type")
# ax.set_xlabel("Data Type")
# ax.set_ylabel("MRE (%)")
# ax.grid(True, linestyle='--', alpha=0.6)

plt.tight_layout()
plt.show()
