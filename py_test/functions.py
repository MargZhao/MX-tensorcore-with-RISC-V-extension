import numpy as np
from scipy.stats import t as student_t
from typing import Optional
import torch
import matplotlib.pyplot as plt

FP4_E2M1 = [-6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]
def quant_nvfp4(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        NVFP4 quantization.
    """
    quant_value = FP4_E2M1
    mid_value = [(quant_value[i] + quant_value[i + 1]) / 2 for i in range(len(quant_value) - 1)]

    orig_shape = w_fp.shape
    w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)

    qmax = max([abs(x) for x in quant_value])
    rmax = torch.amax(w_fp_new.abs(), dim=-1, keepdim=True)
    scale_fp = rmax / qmax
    x = w_fp_new / scale_fp

    w_q = torch.zeros_like(x)
    for i in range(len(quant_value)):
        data = quant_value[i]
        if i == 0:
            w_q += torch.where(x <= mid_value[i], data, 0)
        elif i == len(quant_value) - 1:
            w_q += torch.where(x > mid_value[i - 1], data, 0)
        else:
            w_q += torch.where((mid_value[i - 1] < x) & (x <= mid_value[i]), data, 0)

    ########## Doule Quantization Scaling Factor to FP8-E4M3 ##########
    scale_qmax     = 448
    scale_exp_bits = 4
    scale_max_bits = 3
    scale_exp_min  = -2**(scale_exp_bits-1) + 2

    rmax           = torch.amax(scale_fp.abs())
    scale_scale    = (rmax / scale_qmax).clamp_(min=1e-7)
    scale_tmp      = (scale_fp / scale_scale).abs()
    scale_dq_sign  = torch.sign(scale_fp)
    scale_dq_exp   = (scale_tmp + (scale_tmp == 0).type(scale_tmp.dtype)).log2().floor().clamp_(min=scale_exp_min)
    scale_dq_man   = torch.round(scale_tmp / 2**scale_dq_exp * 2**scale_max_bits) / (2**scale_max_bits)

    scale_dq       = scale_dq_sign * 2**scale_dq_exp * scale_dq_man * scale_scale
    ####################################################################

    w_dq = w_q * scale_dq

    return w_dq.view(orig_shape).to(torch.float16)

def find_share(values,format = "E8M0",E_bits=2):
    if E_bits == 0:
        EMAX =0
    elif E_bits == 5:
        EMAX = 15
    else:
        EMAX = 2 ** (E_bits - 1)
    max_val = np.max(np.abs(values))
    if format == "E8M0":
        share_max = 127  #from -127 to 127
        share_min = -127
        share = np.floor(np.log2(max_val+ 1e-30))
    else:
        share_max = 448 # from -127 to 127
        share_min = -448
        share = np.log2(max_val+ 1e-30)
        share = E4M3().quantize(share)
        share = share.to_float()
    share = share - EMAX
    if share > share_max:
        share = share_max
    elif share < share_min:
        share = share_min
    return share

def normalize(matrix,share,normalized=True):
    if normalized:
        return matrix/2**share
    else: return matrix

def quantize_matrix_e5m2(matrix,block_size = 32,normalized=True,format = "E8M0"):
    m,n = matrix.shape
    m_pad = int(np.ceil(m / block_size) * block_size)
    n_pad = int(np.ceil(n / block_size) * block_size)
    matrix_padded = np.zeros((m_pad, n_pad), dtype=np.float64)
    matrix_padded[:m, :n] = matrix
    q_matrix = np.zeros_like(matrix_padded, dtype=np.float32)
    exp_map = np.zeros((m_pad, n_pad // block_size), dtype=np.float32)#// means divide and take the integer
    for i in range(0, m, 1):
        for j in range(0, n, block_size):
            block = matrix_padded[i, j:j+block_size]
            share = find_share(block,format,5)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = E5M2().quantize(norm_block[k])
                if normalized:
                    e = (e.to_float()) * 2 ** share
                else:
                    e = (e.to_float())
                q_matrix[i, j + k] = e

    return q_matrix, exp_map

def quantize_matrix_e4m3(matrix,block_size = 32,normalized=True,format = "E8M0"):
    m,n = matrix.shape
    m_pad = int(np.ceil(m / block_size) * block_size)
    n_pad = int(np.ceil(n / block_size) * block_size)
    matrix_padded = np.zeros((m_pad, n_pad), dtype=np.float64)
    matrix_padded[:m, :n] = matrix
    q_matrix = np.zeros_like(matrix_padded, dtype=np.float32)
    exp_map = np.zeros((m_pad, n_pad // block_size), dtype=np.float32)#// means divide and take the integer
    for i in range(0, m, 1):
        for j in range(0, n, block_size):
            block = matrix_padded[i, j:j+block_size]
            share = find_share(block,format,4)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = E4M3().quantize(norm_block[k])
                if normalized:
                    e = (e.to_float()) * 2 ** share
                else:
                    e = (e.to_float())
                q_matrix[i, j + k] = e

    return q_matrix, exp_map

def quantize_matrix_int8(matrix,block_size = 32,normalized=True,format = "E8M0"):
    m,n = matrix.shape
    m_pad = int(np.ceil(m / block_size) * block_size)
    n_pad = int(np.ceil(n / block_size) * block_size)
    matrix_padded = np.zeros((m_pad, n_pad), dtype=np.float64)
    matrix_padded[:m, :n] = matrix
    q_matrix = np.zeros_like(matrix_padded, dtype=np.float32)
    exp_map = np.zeros((m_pad, n_pad // block_size), dtype=np.float32)#// means divide and take the integer
    for i in range(0, m, 1):
        for j in range(0, n, block_size):
            block = matrix_padded[i, j:j+block_size]
            share = find_share(block,format,0)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = MXINT8().quantize(norm_block[k])
                if normalized:
                    e = (e.to_float())*2**share
                else:
                    e = (e.to_float())
                q_matrix[i, j + k] = e

    return q_matrix, exp_map

def quantize_matrix_e2m1(matrix,block_size = 32,normalized=True,format = "E8M0"):
    m,n = matrix.shape
    m_pad = int(np.ceil(m / block_size) * block_size)
    n_pad = int(np.ceil(n / block_size) * block_size)
    matrix_padded = np.zeros((m_pad, n_pad), dtype=np.float64)
    matrix_padded[:m, :n] = matrix
    q_matrix = np.zeros_like(matrix_padded, dtype=np.float32)
    exp_map = np.zeros((m_pad, n_pad // block_size), dtype=np.float32)#// means divide and take the integer
    for i in range(0, m, 1):
        for j in range(0, n, block_size):
            block = matrix_padded[i, j:j+block_size]
            share = find_share(block,format,2)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = E2M1().quantize(norm_block[k])
                if normalized:
                    e = (e.to_float())*2**share
                else:
                    e = (e.to_float())
                q_matrix[i, j + k] = e

    return q_matrix, exp_map

class E5M2:
    def __init__(self, sign=0, exponent=0, mantissa=0,share= 0):
        self.sign = int(sign)          # 1 bit
        self.exponent = int(exponent)  # 5 bits
        self.mantissa = int(mantissa)  # 2 bits
        self.share    = int(share)

    def pack(self):
        """将 sign, exponent, mantissa 打包成 uint8"""
        bits = (self.sign << 7) | (self.exponent << 2) | self.mantissa
        return np.uint8(bits)

    def unpack(self, value):
        """
        从一个 uint8 数值解包到 E5M2 各字段
        """
        self.sign = (value >> 7) & 0x1
        self.exponent = (value >> 2) & 0x1F
        self.mantissa = value & 0x3
        return self

    def to_float(self):
        bias = 15
        if self.exponent == 0:
            # 次正规数（subnormal）
            exp_val = 1 - bias
            frac = self.mantissa / 4.0
            val = (2 ** exp_val) * frac
        else:
            # 正规数
            exp_val = self.exponent - bias
            frac = 1.0 + self.mantissa / 4.0
            val = (2 ** exp_val) * frac
        if self.sign:
            val = -val
        return val

    def quantize(self, x):
        bias = 15
        if x == 0:
            self.sign, self.exponent, self.mantissa = 0, 0, 0
            return self

        if x >57344 or x <-57344:
            self.sign, self.exponent, self.mantissa = int(x<0), 30, 3 # S 11110 11 max
            return self

        sign = int(x < 0)
        x = abs(x)
        exp = np.floor(np.log2(x))
        exp_enc = int(exp + bias)

        if exp_enc == 0:
            # ---- 次正规数（subnormal） ----
            exp_enc = 0
            mant = x / (2 ** (1 - bias)) * 4
            mant = int(np.round(mant))
            mant = max(0, min(3, mant))
        elif exp_enc<0:
            exp_enc = 0
            mant = 0
        else:
            # ---- 正规数 ----
            mant = (x / (2 ** exp)) - 1.0
            mant = int(np.round(mant * 4))
            exp_enc = max(0, min(31, exp_enc))
            mant = max(0, min(3, mant))

        self.sign = sign
        self.exponent = exp_enc
        self.mantissa = mant
        return self

class E4M3:
    def __init__(self, sign=0, exponent=0, mantissa=0,share= 0):
        self.sign = int(sign)          # 1 bit
        self.exponent = int(exponent)  # 5 bits
        self.mantissa = int(mantissa)  # 2 bits
        self.share    = int(share)

    def pack(self):
        """将 sign, exponent, mantissa 打包成 uint8"""
        bits = (self.sign << 7) | (self.exponent << 3) | self.mantissa
        return np.uint8(bits)

    def unpack(self, value):
        """
        从一个 uint8 数值解包到 E5M2 各字段
        """
        self.sign = (value >> 7) & 0x1
        self.exponent = (value >> 3) & 0x1F
        self.mantissa = value & 0x3
        return self

    def to_float(self):
        bias = 7
        if self.exponent == 0:
            # 次正规数（subnormal）
            exp_val = 1 - bias
            frac = self.mantissa / 8.0
            val = (2 ** exp_val) * frac
        else:
            # 正规数
            exp_val = self.exponent - bias
            frac = 1.0 + self.mantissa / 8.0
            val = (2 ** exp_val) * frac
        if self.sign:
            val = -val
        return val

    def quantize(self, x):
        bias = 7
        if x == 0:
            self.sign, self.exponent, self.mantissa = 0, 0, 0
            return self

        if x >448 or x <-448:
            self.sign, self.exponent, self.mantissa = int(x<0), 15, 3 # S 11110 11 max
            return self

        sign = int(x < 0)
        x = abs(x)
        exp = np.floor(np.log2(x))
        exp_enc = int(exp + bias)

        if exp_enc == 0:
            # ---- 次正规数（subnormal） ----
            exp_enc = 0
            mant = x / (2 ** (1 - bias)) * 8
            mant = int(np.round(mant))
            mant = max(0, min(7, mant))
        elif exp_enc<0:
            exp_enc = 0
            mant = 0
        else:
            # ---- 正规数 ----
            mant = (x / (2 ** exp)) - 1.0
            mant = int(np.round(mant * 8))
            exp_enc = max(0, min(15, exp_enc))
            mant = max(0, min(7, mant))

        self.sign = sign
        self.exponent = exp_enc
        self.mantissa = mant
        return self

class MXINT8:
    def __init__(self, sign=0, exponent=0, mantissa=0,share= 0):
        self.sign = int(sign)          # 1 bit
        self.exponent = int(exponent)  # 7 bits
        self.share    = int(share)

    def pack(self):
        """将 sign, exponent, mantissa 打包成 uint8"""
        bits = (self.sign << 7) | self.exponent
        return np.uint8(bits)

    def unpack(self, value):
        """
        从一个 uint8 数值解包到 E5M2 各字段
        """
        self.sign = (value >> 7) & 0x1
        self.exponent = value  & 0x7F
        return self

    def to_float(self):
        val = self.exponent/ 64 # implicit scale 2^6
        if self.sign:
            val = -val
        return val

    def quantize(self, x):
        if x == 0:
            self.sign, self.exponent= 0, 0
            return self
        self.sign = int(x < 0)
        if x >=2 or x <=-2:
            self.exponent = 127
            return self

        x = np.round(abs(x)*64)
        self.exponent = x
        return self

class E2M1:
    def __init__(self, sign=0, exponent=0, mantissa=0,share= 0):
        self.sign = int(sign)          # 1 bit
        self.exponent = int(exponent)  # 2 bits
        self.mantissa = int(mantissa)  # 1 bits
        self.share    = int(share)

    def pack(self):
        """将 sign, exponent, mantissa 打包成 uint8"""
        bits = (self.sign << 3) | (self.exponent << 1) | self.mantissa
        return np.uint8(bits)

    def unpack(self, value):
        """
        从一个 uint8 数值解包到 E5M2 各字段
        """
        self.sign = (value >> 3) & 0x1
        self.exponent = (value >> 1) & 0x3
        self.mantissa = value & 0x1
        return self

    def to_float(self):
        bias = 1
        if self.exponent == 0:
            # 次正规数（subnormal）
            exp_val = 1 - bias
            frac = self.mantissa / 2.0
            val = (2 ** exp_val) * frac
        else:
            # 正规数
            exp_val = self.exponent - bias
            frac = 1.0 + self.mantissa / 2.0
            val = (2 ** exp_val) * frac
        if self.sign:
            val = -val
        return val

    def quantize(self, x):
        bias = 1
        if x == 0:
            self.sign, self.exponent, self.mantissa = 0, 0, 0
            return self

        if x >6 or x <-6:
            self.sign, self.exponent, self.mantissa = int(x<0), 3, 1 # S 11 1 max
            return self

        sign = int(x < 0)
        x = abs(x)
        exp = np.round(np.log2(x))
        exp_enc = int(exp + bias)

        if exp_enc == 0:
            # ---- 次正规数（subnormal） ----
            exp_enc = 0
            mant = x / (2 ** (1 - bias)) * 2
            mant = int(np.round(mant))
            mant = max(0, min(1, mant))
        elif exp_enc<0:
            exp_enc = 0
            mant = 0
        else:
            # ---- 正规数 ----
            mant = (x / (2 ** exp)) - 1.0
            mant = int(np.round(mant * 1))
            exp_enc = max(0, min(3, exp_enc))
            mant = max(0, min(1, mant))

        self.sign = sign
        self.exponent = exp_enc
        self.mantissa = mant
        return self


def main():
    # 设置随机种子以便复现
    torch.manual_seed(42)

    print("=" * 60)
    print("NVFP4 (Double Quantization) Analysis Tool")
    print("=" * 60)

    # --- 参数设置 ---
    N, K = 512, 512  # 权重矩阵大小
    groupsize = 32  # NVIDIA 常见的 Block Size

    # --- 1. 生成模拟权重数据 ---
    # 使用正态分布模拟神经网络权重
    w_orig = torch.randn(N, K, dtype=torch.float32)

    # 添加一些离群值 (Outliers) 来测试量化的鲁棒性
    w_orig[0, :10] = w_orig[0, :10] * 5.0

    print(f"Shape: {w_orig.shape}, Group Size: {groupsize}")
    print(f"Data Range: [{w_orig.min():.4f}, {w_orig.max():.4f}]")

    # --- 2. 执行 NVFP4 量化 ---
    print("\nRunning Quantization...", end="")
    w_quant = quant_nvfp4(w_orig, groupsize=groupsize)
    print(" Done.")

    # 转回 float32 进行计算比较
    w_quant = w_quant.float()

    # --- 3. 计算误差指标 ---
    diff = w_orig - w_quant
    mse = torch.mean(diff ** 2).item()
    mae = torch.mean(torch.abs(diff)).item()

    # 信噪比 SNR (Signal-to-Noise Ratio)
    signal_power = torch.mean(w_orig ** 2).item()
    noise_power = mse
    snr = 10 * torch.log10(torch.tensor(signal_power / noise_power)).item()

    print("\n--- Error Metrics ---")
    print(f"MSE (均方误差):       {mse:.6f}")
    print(f"MAE (平均绝对误差):   {mae:.6f}")
    print(f"SNR (信噪比, dB):     {snr:.2f} dB (越大约好)")

    # --- 4. 逐个样本观察 (前 10 个数) ---
    print("\n--- Sample Comparison (First 10 elements) ---")
    print(f"{'Index':<6} | {'Original':<10} | {'Quantized':<10} | {'Diff':<10}")
    print("-" * 45)
    for i in range(10):
        val_o = w_orig[0, i].item()
        val_q = w_quant[0, i].item()
        val_d = val_o - val_q
        print(f"{i:<6} | {val_o:8.4f}   | {val_q:8.4f}   | {val_d:8.4f}")

    # --- 5. 可视化分析 (如果有 matplotlib) ---
    try:

        plt.figure(figsize=(12, 5))

        # 子图 1: 原始值分布
        plt.subplot(1, 2, 1)
        plt.hist(w_orig.view(-1).numpy(), bins=100, alpha=0.5, label='Original', color='blue')
        plt.hist(w_quant.view(-1).numpy(), bins=100, alpha=0.5, label='NVFP4', color='orange')
        plt.legend()
        plt.title(f'Weight Distribution (GroupSize={groupsize})')
        plt.xlabel('Value')
        plt.ylabel('Count')

        # 子图 2: 误差分布
        plt.subplot(1, 2, 2)
        plt.hist(diff.view(-1).numpy(), bins=100, color='red', alpha=0.7)
        plt.title('Quantization Error Distribution')
        plt.xlabel('Error (Original - Quantized)')
        plt.ylabel('Count')

        plt.tight_layout()
        plt.show()
        print("\nVisualization generated.")

    except ImportError:
        print("\nMatplotlib not found, skipping visualization.")
if __name__ == "__main__":
    # matrix_col_dim = 4
    # matrix_row_dim = 4
    # df = 4000
    # A = (np.random.randn(matrix_row_dim, matrix_col_dim)*1).astype(np.float64)
    # A = student_t(df=df, scale=3).rvs(
    #     (matrix_row_dim, matrix_col_dim)
    # ).astype(np.float64)
    #
    # # A = np.array([
    # #     [-0.44043609, -0.86577136, 0.13157700, 0.21752759],
    # #     [0.83372595, -0.28422645, 0.00267505, -0.65931995],
    # #     [-0.41173249, 0.32445009, -0.27792746, 0.40200163],
    # #     [0.64749107, 0.29383548, -1.02255926, -1.13099681]
    # # ], dtype=np.float64)
    #
    # # A = np.array([
    # #     [0.15860881 , 0.90884989,  0.50057054 ,- 0.33868162],
    # #     [-0.3491128 ,  0.01596548,  0.23818992, - 0.4317222],
    # #     [-0.11432842, - 0.61568987, 0.09182887, - 0.06498599],
    # #     [-0.1590846 ,- 0.29740375 , 0.04206297, - 0.00547728]
    # # ], dtype=np.float64)
    #
    #
    # qA, exp_map = quantize_matrix_e5m2(A, block_size=4,normalized=True,format="E8M0")#,format="E4M3"
    #
    # print("原矩阵:\n", A)
    # print("\n量化结果 :\n", qA)
    # print("\n共享指数表:\n", exp_map)
    main()