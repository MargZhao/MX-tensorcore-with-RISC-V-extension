import numpy as np
import matplotlib.pyplot as plt

# -------------------------------
# 1. 定义 FP8 / MXFP8 编码与解码函数
# -------------------------------
def fp8_e4m3_to_float(x):
    s = (x >> 7) & 1
    e = (x >> 3) & 0xF
    m = x & 0x7
    if e == 0:
        val = (m / 8.0) * 2.0 ** (-6)
    else:
        val = (1 + m / 8.0) * 2.0 ** (e - 7)
    return (-1)**s * val

def float_to_fp8_e4m3(x):
    # 仅用于仿真，简化版
    s = 0 if x >= 0 else 1
    x = abs(x)
    e = int(np.floor(np.log2(x))) + 7
    m = int((x / (2.0 ** (e - 7)) - 1) * 8)
    e = max(0, min(e, 15))
    m = max(0, min(m, 7))
    return (s << 7) | (e << 3) | m

def float_to_mxe4m3_block(values, block_size=4):
    """
    将一组浮点数转成 MXE4M3 格式
    - values: 输入浮点数组
    - block_size: 每个 block 的大小
    """
    values = np.array(values, dtype=np.float32)
    n = len(values)
    result = []

    for i in range(0, n, block_size):
        block = values[i:i+block_size]
        if len(block) == 0:
            continue

        # 1. 找到 block 最大绝对值
        max_val = np.max(np.abs(block))
        if max_val == 0:
            result.append([(0, 0, 0)] * len(block))
            continue

        # 2. 求 block exponent（以2为底）
        block_exp = int(np.floor(np.log2(max_val)))

        # 限制在 E4 的范围 (-8 ~ +7)
        block_exp = max(-8, min(7, block_exp))

        block_encoded = []
        for v in block:
            # 3. 归一化到 mantissa 区间
            mant = v / (2**block_exp)

            # 4. microscaling: 找到最接近的3-bit量化
            # mantissa ∈ [-1, 1)，用 3 bit 表示 (含符号)
            quant_levels = np.linspace(-1, 1, 2**3)  # 8 个量化点
            mant_q = quant_levels[np.argmin(np.abs(quant_levels - mant))]

            # 保存 (sign, exponent, mantissa)
            sign = 0 if v >= 0 else 1
            block_encoded.append((sign, block_exp, mant_q))

        result.append(block_encoded)

    return result

def bit_slice(x, high, low):
    """提取x的[high:low]字段（闭区间）"""
    width = high - low + 1
    return (x >> low) & ((1 << width) - 1)

# -------------------------------
# 2. 实验参数
# -------------------------------
N = 1000
a = np.random.uniform(-2, 2, N)
b = np.random.uniform(-2, 2, N)

# 转换为 FP8 仿真值
a_fp8 = np.array([float_to_fp8_e4m3(v) for v in a])
b_fp8 = np.array([float_to_fp8_e4m3(v) for v in b])

a_dec = np.array([fp8_e4m3_to_float(v) for v in a_fp8])
b_dec = np.array([fp8_e4m3_to_float(v) for v in b_fp8])

# -------------------------------
# 3. 不同累加位宽仿真
# -------------------------------
bitwidths = [8, 12, 16, 20, 24, 32]
errors = []

golden = np.sum(a * b)  # FP32 reference

for bw in bitwidths:
    # 模拟有限精度累加
    acc = 0.0
    for i in range(N):
        prod = a_dec[i] * b_dec[i]
        # 模拟截断：限制为 bw-bit 定点
        scale = 2 ** (bw - 1)
        acc = np.round(acc * scale) / scale
        acc += prod
    err = abs((acc - golden) / golden)
    errors.append(err)

# -------------------------------
# 4. 绘制结果
# -------------------------------
plt.plot(bitwidths, np.array(errors)*100)
plt.xlabel("Accumulator bit width (bits)")
plt.ylabel("Relative Error (%)")
plt.title("Effect of Accumulator Bitwidth on MXFP8 Precision")
plt.grid(True)
plt.show()
print(bin(bit_slice(0b11010110, 7, 5)))  # 0b110