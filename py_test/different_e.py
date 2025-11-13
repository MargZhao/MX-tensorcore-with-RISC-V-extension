import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import t as student_t

# --------------------------
# 定义：不同量化格式的简单模拟
# --------------------------

def quantize_uniform(x, n_bits=8):
    """定点量化 (INT)"""
    qmax = 2**(n_bits - 1) - 1
    x_clipped = np.clip(x, -1, 1)
    q = np.round(x_clipped * qmax) / qmax
    return q

def quantize_exponent(x, e_bits, m_bits):
    """简化浮点量化模拟 (E2, E3, E4, E5)"""
    x = np.clip(x, -1e6, 1e6)
    sign = np.sign(x)
    x_abs = np.abs(x) + 1e-30
    exp = np.floor(np.log2(x_abs))
    frac = x_abs / (2 ** exp) - 1.0
    exp_q = np.clip(np.round(exp), -(2 ** (e_bits - 1)), 2 ** (e_bits - 1) - 1)
    frac_q = np.round(frac * (2 ** m_bits)) / (2 ** m_bits)
    x_q = sign * (2 ** exp_q) * (1.0 + frac_q)
    x_q[np.isnan(x_q)] = 0
    return x_q

# --------------------------
# 定义：计算指标
# --------------------------

def quantization_accuracy(x, x_q):
    sigma = np.std(x)
    rmse = np.sqrt(np.mean((x - x_q) ** 2))
    return np.log2(sigma / rmse)

# --------------------------
# 生成三种分布的样本
# --------------------------

N = 200000
distributions = {
    "Uniform": np.random.uniform(-1, 1, N),
    "Normal": np.random.randn(N),
    "Student-T (ν=3)": student_t(df=3).rvs(N)
}

# --------------------------
# 定义格式并计算精度
# --------------------------

formats = {
    "INT": lambda x: quantize_uniform(x, n_bits=8),
    "E2": lambda x: quantize_exponent(x, 2, 5),
    "E3": lambda x: quantize_exponent(x, 3, 4),
    "E4": lambda x: quantize_exponent(x, 4, 3),
    "E5": lambda x: quantize_exponent(x, 5, 2),
}

results = {dist: [] for dist in distributions}

for dist_name, data in distributions.items():
    for fmt_name, qfunc in formats.items():
        x_q = qfunc(data)
        acc = quantization_accuracy(data, x_q)
        results[dist_name].append(acc)

# --------------------------
# 绘图
# --------------------------

plt.style.use('dark_background')
fig, axes = plt.subplots(2, 3, figsize=(12, 6))
axes = axes.reshape(2, 3)

# 上排：分布图
for i, (name, data) in enumerate(distributions.items()):
    ax = axes[0, i]
    ax.hist(data, bins=100, density=True, color='royalblue', alpha=0.7)
    ax.set_title(name)
    ax.set_yticks([])

# 下排：accuracy 条形图
for i, (name, accs) in enumerate(results.items()):
    ax = axes[1, i]
    ax.bar(formats.keys(), accs, color=['#88aaff', '#5f7ee0', '#2ca5a9', '#2e6c6d', '#9fa9b5'])
    ax.axhline(8, linestyle=':', color='white', linewidth=1.0, label='Optimal quantizer (Lloyd–Max)')
    ax.set_ylim(0, 9)
    ax.set_ylabel("accuracy = log₂(σ/RMSE)" if i == 0 else "")
    ax.legend(loc="upper right", fontsize=8)

plt.tight_layout()
plt.show()
