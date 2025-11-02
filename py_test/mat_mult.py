import numpy as np
import functions
from datetime import datetime
# 设置随机数种子（可选，保证结果可复现）
seed = int(datetime.now().timestamp() )
np.random.seed(seed)

# 8*8 matrix with variance of 10
matrix_col_dim = 32
matrix_row_dim = 32
A_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim)*10).astype(np.float64)
B_fp64 = (np.random.randn(matrix_row_dim, matrix_col_dim)*10).astype(np.float64)

#fp32
A_fp32 = A_fp64.astype(np.float32)
B_fp32 = B_fp64.astype(np.float32)

#fp16
A_fp16 = A_fp64.astype(np.float16)
B_fp16 = B_fp64.astype(np.float16)

# matrix mult
C_fp64 = np.matmul(A_fp64, B_fp64)   # baseline
C_fp32 = np.matmul(A_fp32, B_fp32)
C_fp16 = np.matmul(A_fp16, B_fp16 )

abs_err_32 = np.abs(C_fp64 - C_fp32)
rel_err_32 = abs_err_32 / (np.abs(C_fp64) + 1e-12)  # 避免除以零
mse_32 = np.mean((C_fp64 - C_fp32)**2)
mae_32 = np.mean(abs_err_32)
max_err_32 = np.max(abs_err_32)
mre_32 = np.mean(rel_err_32)

abs_err_16 = np.abs(C_fp64 - C_fp16)
rel_err_16 = abs_err_16 / (np.abs(C_fp64) + 1e-12)  # 避免除以零
mse_16 = np.mean((C_fp64 - C_fp16)**2)
mae_16 = np.mean(abs_err_16)
max_err_16 = np.max(abs_err_16)
mre_16 = np.mean(rel_err_16)
# cosine_sim = np.sum(C_fp64 * C_fp32) / (
#     np.sqrt(np.sum(C_fp64**2)) * np.sqrt(np.sum(C_fp32**2))
# )

# 5️⃣ 打印结果
# print("Matrix A (fp64):\n", A_fp64)
# print("\nMatrix B (fp64):\n", B_fp64)
# print("\nC_fp64:\n", C_fp64)
# print("\nC_fp32:\n", C_fp32)

print("\n--- 精度统计 ---")
print(f"fp32 Mean Absolute Error (MAE): {mae_32:.6e}")
print(f"fp32 Mean Squared Error (MSE):  {mse_32:.6e}")
print(f"fp32 Max Absolute Error:         {max_err_32:.6e}")
print(f"fp32 Mean Relative Error:         {mre_32:.6e}")
print(f"fp16 Mean Absolute Error (MAE): {mae_16:.6e}")
print(f"fp16 Mean Squared Error (MSE):  {mse_16:.6e}")
print(f"fp16 Max Absolute Error:         {max_err_16:.6e}")
print(f"fp16 Mean Relative Error:         {mre_16:.6e}")
