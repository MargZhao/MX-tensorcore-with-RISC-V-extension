import numpy as np
from sympy.physics.quantum.gate import normalized

import functions
from datetime import datetime
import matplotlib.pyplot as plt
from scipy.stats import t as student_t
from functions import quantize_matrix_e5m2, quantize_matrix_e4m3, quantize_matrix_int8

#################################parameters############################################
# 设置随机数种子（可选，保证结果可复现）
seed = int(datetime.now().timestamp() )
np.random.seed(seed)
matrix_col_dim = 32*16
matrix_row_dim = 32*16
variation_list = [1]
normalized = True
variation = 1
df_list = [4,40,400,4000]
block_size = 16
# ========== 误差计算函数 ==========
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
# 计算相对误差
def mean_rel_err(C):
    abs_err = np.abs(C_fp32 - C)
    rel_err = abs_err / (np.abs(C_fp32))
    return np.mean(rel_err) * 100  # 转成百分比 %
#
results_mae = {}
results_mse = {}
results_mre = {}
results_rmse = {}

#################################logic##################################################
# for variation in variation_list:
#     variance = variation/3
#     A_fp64 = (student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim))).astype(np.float64)
#     B_fp64 = (student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim))).astype(np.float64)
#
#     # A_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim) * variance ).astype(np.float64)
#     # B_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim) * variance ).astype(np.float64)
#     #
#     # A_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)
#     # B_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)
#
#     #fp32
#     A_fp32 = A_fp64.astype(np.float32)
#     B_fp32 = B_fp64.astype(np.float32)
#
#     #fp16
#     A_fp16 = A_fp64.astype(np.float16)
#     B_fp16 = B_fp64.astype(np.float16)
#
#     #E5M2
#     A_E5M2,A_emap = quantize_matrix_e5m2(A_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#     B_E5M2,B_Emap = quantize_matrix_e5m2(B_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#
#     #E4M3
#     A_E4M3,A_emap_E4M3 = quantize_matrix_e4m3(A_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#     B_E4M3,B_Emap_E4M3 = quantize_matrix_e4m3(B_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#
#     A_INT8,A_emap_INT8 = quantize_matrix_int8(A_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#     B_INT8,B_Emap_INT8 = quantize_matrix_int8(B_fp64, block_size=block_size,normalized=normalized,format="E4M3")
#
#     # matrix mult
#     C_fp64 = np.matmul(A_fp64, B_fp64)   # baseline
#     C_fp32 = np.matmul(A_fp32, B_fp32)
#     ##avoid overflow
#     C_fp16 = np.matmul(A_fp16.astype(np.float32), B_fp16.astype(np.float32))
#     C_E5M2 = np.matmul(A_E5M2.astype(np.float32), B_E5M2.astype(np.float32))
#     C_E4M3 = np.matmul(A_E4M3.astype(np.float32), B_E4M3.astype(np.float32))
#     C_INT8 = np.matmul(A_INT8.astype(np.float32), B_INT8.astype(np.float32))
#
#     mae_fp32, mse_fp32, mre_fp32, rmse_fp32 = compute_metrics(C_fp32, C_fp32)
#     mae_fp16, mse_fp16, mre_fp16, rmse_fp16 = compute_metrics(C_fp32, C_fp16)
#     mae_e5m2, mse_e5m2, mre_e5m2, rmse_e5m2 = compute_metrics(C_fp32, C_E5M2)
#     mae_e4m3, mse_e4m3, mre_e4m3, rmse_e4m3 = compute_metrics(C_fp32, C_E4M3)
#     mae_int8, mse_int8, mre_int8, rmse_int8 = compute_metrics(C_fp32, C_INT8)
#
#     # mae_fp32, mse_fp32, mre_fp32, rmse_fp32 = compute_metrics(A_fp32, A_fp32)
#     # mae_fp16, mse_fp16, mre_fp16, rmse_fp16 = compute_metrics(A_fp32, A_fp16)
#     # mae_e5m2, mse_e5m2, mre_e5m2, rmse_e5m2 = compute_metrics(A_fp32, A_E5M2)
#     # mae_e4m3, mse_e4m3, mre_e4m3, rmse_e4m3 = compute_metrics(A_fp32, A_E4M3)
#     # mae_int8, mse_int8, mre_int8, rmse_int8 = compute_metrics(A_fp32, A_INT8)
#
#     # 存储结果
#     results_mae[variation] = {
#         "FP32": mae_fp32, "FP16": mae_fp16, "E5M2": mae_e5m2, "E4M3": mae_e4m3, "INT8": mae_int8
#     }
#     results_mse[variation] = {
#         "FP32": mse_fp32, "FP16": mse_fp16, "E5M2": mse_e5m2, "E4M3": mse_e4m3, "INT8": mse_int8
#     }
#     results_mre[variation] = {
#         "FP32": mre_fp32, "FP16": mre_fp16, "E5M2": mre_e5m2, "E4M3": mre_e4m3, "INT8": mre_int8
#     }
#     results_rmse[variation] = {
#         "FP32": rmse_fp32, "FP16": rmse_fp16, "E5M2": rmse_e5m2, "E4M3": rmse_e4m3, "INT8": rmse_int8
#     }
#     print(f"\n--- Variation = {variation} ---")
#     print(f"{'DataType':<6s} | {'MAE':>12s} | {'MSE':>12s} |{'RMSE':>12s} | {'RelErr(%)':>12s}")
#     print("-" * 50)
#     for dtype in ["FP32", "FP16", "E5M2", "E4M3", "INT8"]:
#         mae_val = results_mae[variation][dtype]
#         mse_val = results_mse[variation][dtype]
#         rmse_val = results_rmse[variation][dtype]
#         mre_val = results_mre[variation][dtype] * 100  # 转为百分比
#         print(f"{dtype:<6s} | {mae_val:12.6e} | {mse_val:12.6e} |{rmse_val:12.6e} | {mre_val:12.4f}")
#
# # ========== 绘图 ==========
# data_types = ["FP16", "INT8", "E4M3", "E5M2"]
# fig, axes = plt.subplots(1, 1, figsize=(8, 8))  # 4 行子图，高度加大以防重叠
# metrics = ["MAE", "MSE", "RMSE", "MRE"]
# #
# # # ---- MAE ----
# # ax = axes[0]
# # for variation in variation_list:
# #     y = [results_mae[variation][dt] for dt in data_types]
# #     ax.plot(data_types, y, marker='o', label=f"variation={variation}")
# # ax.set_title("Mean Absolute Error (MAE) vs. Data Type")
# # ax.set_ylabel("MAE")
# # ax.grid(True, linestyle='--', alpha=0.6)
# # ax.legend(title="Variation", loc="upper left")
# #
# # # ---- MSE ----
# # ax = axes[1]
# # for variation in variation_list:
# #     y = [results_mse[variation][dt] for dt in data_types]
# #     ax.plot(data_types, y, marker='o', label=f"variation={variation}")
# # ax.set_title("Mean Squared Error (MSE) vs. Data Type")
# # ax.set_ylabel("MSE")
# # ax.grid(True, linestyle='--', alpha=0.6)
#
# # ---- RMSE ----
# ax = axes
# for variation in variation_list:
#     y = [results_rmse[variation][dt] for dt in data_types]
#     ax.plot(data_types, y, marker='o', label=f"variation={variation}")
# ax.set_title("Norm Root Mean Squared Error (NRMSE) vs. Data Type")
# ax.set_ylabel("NRMSE")
# ax.grid(True, linestyle='--', alpha=0.6)
# ax.legend(title="Variation", loc="upper left")
# # # ---- MRE ----
# # ax = axes[1]
# # for variation in variation_list:
# #     y = [results_mre[variation][dt] * 100 for dt in data_types]
# #     ax.plot(data_types, y, marker='o', label=f"variation={variation}")
# # ax.set_title("Mean Relative Error (MRE) vs. Data Type")
# # ax.set_xlabel("Data Type")
# # ax.set_ylabel("MRE (%)")
# # ax.grid(True, linestyle='--', alpha=0.6)
#
# plt.tight_layout()
# plt.show()
# # print("Matrix A (fp64):\n", A_fp64)
# # print("\nMatrix B (fp64):\n", B_fp64)
# # print("\nC_fp64:\n", C_fp64)
# # print("\nC_fp32:\n", C_fp32)
# # A_flat = A_fp64.flatten()
# # B_flat = B_fp64.flatten()
# # C_flat = C_fp64.flatten()
# #
# # # ---------- 可视化 ----------
# # plt.figure(figsize=(10, 6))
# #
# # # 输入 A 的分布
# plt.subplot(3, 1, 1)
# plt.hist(A_fp64.flatten(), bins=200, density=True, alpha=0.7, color='royalblue')
# plt.title(f"Input A Distribution (Student-t, ν={df})")
# plt.ylabel("Density")
# plt.grid(True, linestyle='--', alpha=0.5)
# #
# # # 输入 B 的分布
# plt.subplot(3, 1, 2)
# plt.hist(B_fp64.flatten(), bins=200, density=True, alpha=0.7, color='seagreen')
# plt.title(f"Input B Distribution (Student-t, ν={df})")
# plt.ylabel("Density")
# plt.grid(True, linestyle='--', alpha=0.5)
#
# # # 输出 C 的分布
# plt.subplot(3, 1, 3)
# plt.hist(C_fp64.flatten(), bins=200, density=True, alpha=0.7, color='darkorange')
# plt.title("Output C = A × Bᵀ Distribution")
# plt.xlabel("Value")
# plt.ylabel("Density")
# plt.grid(True, linestyle='--', alpha=0.5)
# #
# # # 调整布局
# plt.tight_layout()
# plt.show()

#################################main loop############################################
for df in df_list:
    print(f"\n============================== DF = {df} ==============================")
    results_rmse[df] = {}
    results_mre[df] = {}

    for variation in variation_list:
        variance = variation / 3

        # # ---- Student-t distributed matrices ----
        A_fp64 = student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim)).astype(np.float64)
        B_fp64 = student_t(df=df,scale=variance).rvs((matrix_row_dim, matrix_col_dim)).astype(np.float64)
        # A_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)
        # B_fp64 = (np.random.uniform(-variation, variation,(matrix_row_dim, matrix_col_dim))).astype(np.float64)

        # ---- Casts ----
        A_fp32 = A_fp64.astype(np.float32)
        B_fp32 = B_fp64.astype(np.float32)
        A_fp16 = A_fp64.astype(np.float16)
        B_fp16 = B_fp64.astype(np.float16)

        # ---- Quantized ----
        A_E5M2, _ = quantize_matrix_e5m2(A_fp64, block_size=32, normalized=normalized,format="E4M3")
        B_E5M2, _ = quantize_matrix_e5m2(B_fp64, block_size=32, normalized=normalized,format="E4M3")
        A_E4M3, _ = quantize_matrix_e4m3(A_fp64, block_size=32, normalized=normalized,format="E4M3")
        B_E4M3, _ = quantize_matrix_e4m3(B_fp64, block_size=32, normalized=normalized,format="E4M3")
        A_INT8, _ = quantize_matrix_int8(A_fp64, block_size=32, normalized=normalized,format="E4M3")
        B_INT8, _ = quantize_matrix_int8(B_fp64, block_size=32, normalized=normalized,format="E4M3")

        # ---- Matrix Multiplication ----
        C_fp32 = np.matmul(A_fp32, B_fp32)
        C_fp16 = np.matmul(A_fp16.astype(np.float32), B_fp16.astype(np.float32))
        C_E5M2 = np.matmul(A_E5M2.astype(np.float32), B_E5M2.astype(np.float32))
        C_E4M3 = np.matmul(A_E4M3.astype(np.float32), B_E4M3.astype(np.float32))
        C_INT8 = np.matmul(A_INT8.astype(np.float32), B_INT8.astype(np.float32))

        # ---- Metrics ----
        mae_fp16, mse_fp16, mre_fp16, rmse_fp16 = compute_metrics(C_fp32, C_fp16)
        mae_e5m2, mse_e5m2, mre_e5m2, rmse_e5m2 = compute_metrics(C_fp32, C_E5M2)
        mae_e4m3, mse_e4m3, mre_e4m3, rmse_e4m3 = compute_metrics(C_fp32, C_E4M3)
        mae_int8, mse_int8, mre_int8, rmse_int8 = compute_metrics(C_fp32, C_INT8)

        results_rmse[df][variation] = {
            "FP16": rmse_fp16, "E5M2": rmse_e5m2, "E4M3": rmse_e4m3, "INT8": rmse_int8
        }
        results_mre[df][variation] = {
            "FP16": mre_fp16, "E5M2": mre_e5m2, "E4M3": mre_e4m3, "INT8": mre_int8
        }

        print(f"\n--- Variation = {variation}, DF = {df} ---")
        print(f"{'DataType':<6s} | {'NRMSE':>12s} | {'MRE(%)':>12s}")
        print("-" * 35)
        for dtype in ["FP16", "E5M2", "E4M3", "INT8"]:
            print(f"{dtype:<6s} | {results_rmse[df][variation][dtype]:12.6e} | {results_mre[df][variation][dtype]*100:12.4f}")

#################################plot############################################
data_types = ["FP16", "INT8", "E4M3", "E5M2"]

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
