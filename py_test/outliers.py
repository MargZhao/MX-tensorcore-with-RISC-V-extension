import numpy as np
import matplotlib.pyplot as plt


def quantize_fp8_per_tensor(x, mantissa_bits=3, max_val=448):
    """模拟 Per-Tensor FP8 (E4M3): 全局最大值决定 Scale"""
    global_max = np.max(np.abs(x))
    if global_max == 0: return x

    # Scale 使得最大值映射到 FP8 的最大表示范围
    scale = max_val / global_max

    # 量化过程 (简化版，仅演示精度丢失)
    x_scaled = x * scale
    # 模拟低精度截断 (这里简单取整模拟有限尾数带来的精度损失)
    # 实际上应该更严谨地模拟 E4M3 的 grid，但为了演示 Scale 效应，取整足够说明问题
    x_q = np.round(x_scaled)

    # 反量化
    x_recon = x_q / scale
    return x_recon


def quantize_mxfp8(x, block_size=32, mantissa_bits=3, max_val=448):
    """模拟 MXFP8: 每个 Block 都有自己的 Scale"""
    x_recon = np.zeros_like(x)
    num_blocks = len(x) // block_size

    for i in range(num_blocks):
        start = i * block_size
        end = start + block_size
        block = x[start:end]

        # --- Local Scale (关键区别) ---
        block_max = np.max(np.abs(block))
        if block_max == 0:
            scale = 1
        else:
            scale = max_val / block_max

        block_scaled = block * scale
        block_q = np.round(block_scaled)
        x_recon[start:end] = block_q / scale

    return x_recon


# ================= 构造测试数据 =================
# 64个数据：前32个是很小的正常信号，后32个包含一个巨大的离群值
N = 64
possible_values = np.arange(0, 1.0 + 0.001, 0.125)

# 2. 从中随机抽取
data = np.random.choice(possible_values, size=N)
data[40] = 1000.0  # 在第二个 Block 插入一个巨大的离群值

# ================= 运行量化 =================
rec_tensor = quantize_fp8_per_tensor(data)
rec_mx = quantize_mxfp8(data, block_size=32)

# ================= 绘图对比 =================
plt.figure(figsize=(10, 8))

# 只画前 32 个点 (正常信号区域)，看看谁受了后面离群值的影响
plt.plot(data[:32], 'k-', label='Original Signal (Small)', linewidth=2)
plt.plot(rec_tensor[:32], 'r--o', label='Per-Tensor FP8 (Ruined by Outlier)', alpha=0.7)
plt.plot(rec_mx[:32], 'g-x', label='MXFP8 (Protected)', alpha=0.7)

plt.title(f"Effect of an Outlier (at index 40) on the First Block (index 0-31)")
plt.xlabel("Index")
plt.ylabel("Value")
plt.legend()
plt.grid(True)
plt.show()