import numpy as np
import struct

# FP8 E5M2 format
FP8_EXP_BITS = 5
FP8_MAN_BITS = 2
FP8_EXP_BIAS = 15

def float32_to_hex(f):
    return hex(struct.unpack('<I', struct.pack('<f', f))[0])

def encode_fp8_e5m2(x: float):
    """ Encode a float into a raw FP8 E5M2 8-bit number """
    if x == 0.0:
        return 0

    sign = 0 if x >= 0 else 1
    x = abs(x)

    exp = int(np.floor(np.log2(x)))
    man_real = x / (2 ** exp) - 1.0

    exp_fp8 = exp + FP8_EXP_BIAS
    man_fp8 = int(man_real * (2 ** FP8_MAN_BITS))

    exp_fp8 = np.clip(exp_fp8, 0, 31)
    man_fp8 = np.clip(man_fp8, 0, 3)

    return (sign << 7) | (exp_fp8 << FP8_MAN_BITS) | man_fp8


def decode_fp8_e5m2(raw: int) -> float:
    sign = -1.0 if (raw >> 7) & 1 else 1.0
    exp = (raw >> FP8_MAN_BITS) & 0x1F
    man = raw & 0x03

    if exp == 0:
        return sign * (man / 4.0) * (2 ** (-FP8_EXP_BIAS))

    return sign * (1.0 + man / 4.0) * (2 ** (exp - FP8_EXP_BIAS))


def generate_dotp_test(VectorSize=32):
    # 生成随机 FP8 数组
    a_fp8 = np.array([encode_fp8_e5m2(np.random.uniform(-2, 2)) for _ in range(VectorSize)], dtype=np.uint8)
    b_fp8 = np.array([encode_fp8_e5m2(np.random.uniform(-2, 2)) for _ in range(VectorSize)], dtype=np.uint8)

    # 计算 golden dot-product
    total = 0.0
    for i in range(VectorSize):
        total += decode_fp8_e5m2(a_fp8[i]) * decode_fp8_e5m2(b_fp8[i])

    result_hex = float32_to_hex(total)

    # 生成 .svh 字符串
    def fmt_hex_list(arr):
        return ", ".join([f"8'h{v:02X}" for v in arr])

    sv = []
    sv.append("// Auto-generated MXFP8 dot-product test vectors\n")
    sv.append(f"localparam int VectorSize = {VectorSize};\n")
    sv.append(f"operands_a_i = '{{{fmt_hex_list(a_fp8)}}};\n")
    sv.append(f"operands_b_i = '{{{fmt_hex_list(b_fp8)}}};\n")
    sv.append("scale_i = '{8'd127, 8'd127};\n")
    sv.append(f"localparam logic [31:0] expected_result = 32'h{result_hex[2:]};\n")

    return "\n".join(sv)


if __name__ == "__main__":
    print("Gen dot vectors")
    text = generate_dotp_test(32)
    with open("dotp_test_vectors.svh", "w") as f:
        f.write(text)
    print("Generated dotp_test_vectors.svh")
