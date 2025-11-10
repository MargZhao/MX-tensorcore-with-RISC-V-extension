import numpy as np
import functions
from datetime import datetime
import matplotlib.pyplot as plt
from functions import quantize_matrix_e5m2, quantize_matrix_e4m3, quantize_matrix_int8

#################################parameters############################################
# 设置随机数种子（可选，保证结果可复现）
seed = int(datetime.now().timestamp() )
np.random.seed(seed)
matrix_col_dim = 32*16
matrix_row_dim = 32*16
variation_list = [1, 10, 100, 1000]
# ========== 误差计算函数 ==========
def compute_metrics(C_ref, C_test, eps=1e-12):
    abs_err = np.abs(C_ref - C_test)
    mae = np.mean(abs_err)
    mse = np.mean((C_ref - C_test) ** 2)
    rel_err = abs_err / (np.abs(C_ref) + eps)
    mre = np.mean(rel_err)
    return mae, mse, mre
# 计算相对误差
def mean_rel_err(C):
    abs_err = np.abs(C_fp32 - C)
    rel_err = abs_err / (np.abs(C_fp32))
    return np.mean(rel_err) * 100  # 转成百分比 %

results_mae = {}
results_mse = {}
results_mre = {}

#################################logic##################################################
for variation in variation_list:
    variance = variation/3
    A_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim)*variance+variation).astype(np.float64)
    B_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim)*variance+variation).astype(np.float64)

    #fp32
    A_fp32 = A_fp64.astype(np.float32)
    B_fp32 = B_fp64.astype(np.float32)

    #fp16
    A_fp16 = A_fp64.astype(np.float16)
    B_fp16 = B_fp64.astype(np.float16)

    #E5M2
    A_E5M2,A_emap = quantize_matrix_e5m2(A_fp64, block_size=32)
    B_E5M2,B_Emap = quantize_matrix_e5m2(B_fp64, block_size=32)

    #E4M3
    A_E4M3,A_emap_E4M3 = quantize_matrix_e4m3(A_fp64, block_size=32)
    B_E4M3,B_Emap_E4M3 = quantize_matrix_e4m3(B_fp64, block_size=32)

    A_INT8,A_emap_INT8 = quantize_matrix_int8(A_fp64, block_size=32)
    B_INT8,B_Emap_INT8 = quantize_matrix_int8(B_fp64, block_size=32)

    # matrix mult
    C_fp64 = np.matmul(A_fp64, B_fp64)   # baseline
    C_fp32 = np.matmul(A_fp32, B_fp32)
    ##avoid overflow
    C_fp16 = np.matmul(A_fp16.astype(np.float32), B_fp16.astype(np.float32))
    C_E5M2 = np.matmul(A_E5M2.astype(np.float32), B_E5M2.astype(np.float32))
    C_E4M3 = np.matmul(A_E4M3.astype(np.float32), B_E4M3.astype(np.float32))
    C_INT8 = np.matmul(A_INT8.astype(np.float32), B_INT8.astype(np.float32))

    mae_fp32, mse_fp32, mre_fp32 = compute_metrics(C_fp64, C_fp32)
    mae_fp16, mse_fp16, mre_fp16 = compute_metrics(C_fp64, C_fp16)
    mae_e5m2, mse_e5m2, mre_e5m2 = compute_metrics(C_fp64, C_E5M2)
    mae_e4m3, mse_e4m3, mre_e4m3 = compute_metrics(C_fp64, C_E4M3)
    mae_int8, mse_int8, mre_int8 = compute_metrics(C_fp64, C_INT8)

    # 存储结果
    results_mae[variation] = {
        "FP32": mae_fp32, "FP16": mae_fp16, "E5M2": mae_e5m2, "E4M3": mae_e4m3, "INT8": mae_int8
    }
    results_mse[variation] = {
        "FP32": mse_fp32, "FP16": mse_fp16, "E5M2": mse_e5m2, "E4M3": mse_e4m3, "INT8": mse_int8
    }
    results_mre[variation] = {
        "FP32": mre_fp32, "FP16": mre_fp16, "E5M2": mre_e5m2, "E4M3": mre_e4m3, "INT8": mre_int8
    }
    print(f"\n--- Variation = {variation} ---")
    print(f"{'DataType':<6s} | {'MAE':>12s} | {'MSE':>12s} | {'RelErr(%)':>12s}")
    print("-" * 50)
    for dtype in ["FP32", "FP16", "E5M2", "E4M3", "INT8"]:
        mae_val = results_mae[variation][dtype]
        mse_val = results_mse[variation][dtype]
        mre_val = results_mre[variation][dtype] * 100  # 转为百分比
        print(f"{dtype:<6s} | {mae_val:12.6e} | {mse_val:12.6e} | {mre_val:12.4f}")

# ========== 绘图 ==========
data_types = ["FP32", "FP16", "INT8", "E4M3", "E5M2"]
plt.figure(figsize=(8, 5))
for variation in variation_list:
    y = [results_mae[variation][dt] for dt in data_types]
    plt.plot(data_types, y, marker='o', label=f"variation={variation}")
plt.title("Mean Absolute Error (MAE) vs. Data Type")
plt.xlabel("Data Type")
plt.ylabel("MAE")
plt.grid(True, linestyle='--', alpha=0.6)
plt.legend(title="Variation", loc="upper left")
plt.tight_layout()
plt.show()

plt.figure(figsize=(8, 5))
for variation in variation_list:
    y = [results_mse[variation][dt] for dt in data_types]
    plt.plot(data_types, y, marker='o', label=f"variation={variation}")
plt.title("Mean Squared Error (MSE) vs. Data Type")
plt.xlabel("Data Type")
plt.ylabel("MSE")
plt.grid(True, linestyle='--', alpha=0.6)
plt.legend(title="Variation", loc="upper left")
plt.tight_layout()
plt.show()

# ---- MRE ----
plt.figure(figsize=(8, 5))
for variation in variation_list:
    y = [results_mre[variation][dt] * 100 for dt in data_types]  # 转百分比
    plt.plot(data_types, y, marker='o', label=f"variation={variation}")
plt.title("Mean Relative Error (MRE) vs. Data Type")
plt.xlabel("Data Type")
plt.ylabel("Mean Relative Error (%)")
plt.grid(True, linestyle='--', alpha=0.6)
plt.legend(title="Variation", loc="upper left")
plt.tight_layout()
plt.show()
# print("Matrix A (fp64):\n", A_fp64)
# print("\nMatrix B (fp64):\n", B_fp64)
# print("\nC_fp64:\n", C_fp64)
# print("\nC_fp32:\n", C_fp32)
# A_flat = A_fp64.flatten()
# B_flat = B_fp64.flatten()
#
# # 创建子图
# fig, axes = plt.subplots(1, 2, figsize=(12, 5), sharey=True)
#
# # 绘制 A_fp64 分布
# axes[0].hist(A_flat, bins=100, alpha=0.7, color='steelblue', density=True)
# axes[0].set_title("Distribution of A_fp64")
# axes[0].set_xlabel("Value")
# axes[0].set_ylabel("Density")
# axes[0].grid(True)
#
# # 绘制 B_fp64 分布
# axes[1].hist(B_flat, bins=100, alpha=0.7, color='orange', density=True)
# axes[1].set_title("Distribution of B_fp64")
# axes[1].set_xlabel("Value")
# axes[1].grid(True)
#
# # 调整布局
# plt.tight_layout()
# plt.show()