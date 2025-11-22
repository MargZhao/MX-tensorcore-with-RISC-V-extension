import numpy as np
from scipy.stats import t as student_t
def find_share(values,format):
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
            share = find_share(block,format)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = E5M2().quantize(norm_block[k])
                e = (e.to_float())*2**share
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
            share = find_share(block,format)
            exp_map[i, j // block_size] = share
            norm_block = normalize(block,share,normalized)
            for k in range(block_size):
                e = E4M3().quantize(norm_block[k])
                e = (e.to_float())*2**share
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
            share = find_share(block,format)
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

if __name__ == "__main__":
    matrix_col_dim = 4
    matrix_row_dim = 4
    df = 4
    A = (np.random.randn(matrix_row_dim, matrix_col_dim)*10).astype(np.float64)
    A = student_t(df=df, scale=1/3).rvs(
        (matrix_row_dim, matrix_col_dim)
    ).astype(np.float64)

    # A = np.array([
    #     [-0.44043609, -0.86577136, 0.13157700, 0.21752759],
    #     [0.83372595, -0.28422645, 0.00267505, -0.65931995],
    #     [-0.41173249, 0.32445009, -0.27792746, 0.40200163],
    #     [0.64749107, 0.29383548, -1.02255926, -1.13099681]
    # ], dtype=np.float64)


    qA, exp_map = quantize_matrix_e5m2(A, block_size=4,normalized=True,format="E4M3")

    print("原矩阵:\n", A)
    print("\n量化结果 :\n", qA)
    print("\n共享指数表:\n", exp_map)
