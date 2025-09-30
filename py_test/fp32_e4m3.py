import numpy as np

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


# 示例数据
data = [0.25, 0.5, 1.0, 2.0, -0.75, -3.2, 4.5, 0.1]
encoded = float_to_mxe4m3_block(data, block_size=4)

print("原始数据:", data)
print("编码结果:")
for block in encoded:
    print(block)
