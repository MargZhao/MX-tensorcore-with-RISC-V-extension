import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime
from scipy.stats import t as student_t

from functions import quantize_matrix_e2m1

#################################parameters############################################
seed = int(datetime.now().timestamp())
np.random.seed(seed)

matrix_col_dim = 32 * 4
matrix_row_dim = 32 * 4

variation_list = [1]
df_list = [4,40,400,4000]
normalized = True

#################################metrics############################################
def compute_metrics(C_ref, C_test, eps=1e-12):
    mse = np.mean((C_ref - C_test) ** 2)
    rmse = np.sqrt(mse)
    sigma_ref = np.std(C_ref)
    nrmse = rmse / sigma_ref
    return  nrmse

#################################containers############################################

results_rmse = {}

#################################main loop############################################
for df in df_list:
    print(f"\n============================== DF = {df} ==============================")
    results_rmse[df] = {}

    for variation in variation_list:
        variance = variation / 3

        # # ---- Student-t distributed matrices ----
        A_fp16 = student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim)).astype(np.float16)
        B_fp16 = student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim)).astype(np.float16)
        # A_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)
        # B_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)

        # ---- Quantized ----
        # A_E4M3, _ = quantize_matrix_e4m3(A_fp64, block_size=32, normalized=normalized)
        # B_E4M3, _ = quantize_matrix_e4m3(B_fp64, block_size=32, normalized=normalized)
        A_MXFP4, _ = quantize_matrix_e2m1(A_fp16, block_size=32, normalized=normalized)
        B_MXFP4, _ = quantize_matrix_e2m1(B_fp16, block_size=32, normalized=normalized)

        A_NVFP4, _ = quantize_matrix_e2m1(A_fp16, block_size=16, normalized=normalized, format="E4M3")
        B_NVFP4, _ = quantize_matrix_e2m1(B_fp16, block_size=16, normalized=normalized, format="E4M3")

        # ---- Matrix Multiplication ----
        C_fp16 = np.matmul(A_fp16, B_fp16)
        # C_E4M3 = np.matmul(A_E4M3.astype(np.float32), B_E4M3.astype(np.float32))
        C_MXFP4 = np.matmul(A_MXFP4.astype(np.float32), B_MXFP4.astype(np.float32))
        C_NVFP4 = np.matmul(A_NVFP4.astype(np.float32), B_NVFP4.astype(np.float32))

        # ---- Metrics ----
        rmse_MXFP4 = compute_metrics(C_fp16, C_MXFP4)
        rmse_NVFP4 = compute_metrics(C_fp16, C_NVFP4)

        results_rmse[df][variation] = {
            "MXFP4": rmse_MXFP4, "NVFP4": rmse_NVFP4
        }

        print(f"\n--- Variation = {variation}, DF = {df} ---")
        print(f"{'DataType':<6s} | {'NRMSE':>12s} ")
        print("-" * 35)
        for dtype in ["MXFP4", "NVFP4"]:
            print(f"{dtype:<6s} | {results_rmse[df][variation][dtype]:12.6e} ")

#################################plot############################################
data_types = ["MXFP4", "NVFP4"]

fig, axes = plt.subplots(1, 1, figsize=(8, 8))
# ---- RMSE ----
ax = axes
for df in df_list:
    y = [results_rmse[df][variation_list[0]][dt] for dt in data_types]
    ax.plot(data_types, y, marker='o', label=f"df={df}")
ax.set_title("Normalized RMSE vs. Data Type (Student-t)")
ax.set_ylabel("NRMSE")
ax.grid(True, linestyle='--', alpha=0.6)
ax.legend(title="Degrees of Freedom (df)", loc="upper left")

# ---- MRE ----
# ax = axes[1]
# for df in df_list:
#     y = [results_mre[df][variation_list[0]][dt] * 100 for dt in data_types]
#     ax.plot(data_types, y, marker='o', label=f"df={df}")
# ax.set_title("Mean Relative Error vs. Data Type (Student-t)")
# ax.set_xlabel("Data Type")
# ax.set_ylabel("MRE (%)")
# ax.grid(True, linestyle='--', alpha=0.6)
# ax.legend(title="Degrees of Freedom (df)", loc="upper left")


plt.tight_layout()
plt.show()
