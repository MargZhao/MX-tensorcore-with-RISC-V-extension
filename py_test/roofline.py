import matplotlib.pyplot as plt
import numpy as np

# ================= 配置区域 =================
# Baseline (64 PEs)
num_MAC_base = 64
PEAK_OPS_BASE = num_MAC_base * 2  # 128 Ops/cycle
PEAK_BW_BASE = 96  # 96 Bytes/cycle
parforN= 4
parforM = 4

# Scaled (256 PEs)
num_MAC_scaled = 256
PEAK_OPS_SCALED = num_MAC_scaled * 2  # 512 Ops/cycle
M = 8
N =4
K = 8
PEAK_BW_SCALED = M*K+K*N + M*N*4  # 假设带宽也提升了 (根据你的变量)
parforM1 = 8
parforN1= 8

cases = [
    # --- Baseline (64 PE) ---
    {"name": "Case 1", "M": 4, "N": 16, "K": 64, "cycles": 64, "offset": (-30, -20)},
    {"name": "Case 2", "M": 16, "N": 4, "K": 64, "cycles": 64, "offset": (30, -20)},
    {"name": "Case 3", "M": 32, "N": 32, "K": 32, "cycles": 512, "offset": (0, -40)},

    # --- Scaled (256 PE) ---
    {"name": "Case 1 ", "M": 4, "N": 16, "K": 64, "cycles": 32, "offset": (-50, 20)},
    {"name": "Case 2 ", "M": 16, "N": 4, "K": 64, "cycles": 32, "offset": (30, 20)},
    {"name": "Case 3 ", "M": 32, "N": 32, "K": 32, "cycles": 128, "offset": (0, 20)}
]
# ===========================================

fig, ax = plt.subplots(figsize=(12, 10))

# X轴范围
x = np.logspace(-1, 2, 100)

# --- 1. 绘制两条 Roofline ---
# Baseline (黑色实线)
y_base = np.minimum(PEAK_OPS_BASE, PEAK_BW_BASE * x)
ax.loglog(x, y_base, 'k-', linewidth=2, label='Baseline Roofline (64 PEs)')

# Scaled (红色虚线)
y_scaled = np.minimum(PEAK_OPS_SCALED, PEAK_BW_SCALED * x)
ax.loglog(x, y_scaled, 'r--', linewidth=2, label='Scaled Roofline (256 PEs)')

# --- 2. 绘制工作点 ---
colors = ['#1f77b4', '#ff7f0e', '#2ca02c']  # 蓝、橙、绿 (对应 Case 1, 2, 3)

# 绘制 Legend 用的 Dummy 点
ax.plot([], [], 'o', color='gray', label='4x4x4 (64 PE)')
ax.plot([], [], 's', color='gray', label='4x16 (64 PE)')
ax.plot([], [], '*', markersize=15, color='gray', label='Scaled (256 PE)')

for i, case in enumerate(cases):
    # 确定颜色 (Case 1/4用蓝, 2/5用橙, 3/6用绿)
    c = colors[i % 3]

    total_ops = 2 * case['M'] * case['N'] * case['K']

    # AI 计算 (Baseline 4x4x4 逻辑)
    bytes_3d = (case['M'] * case['K']) * (case['N'] / 4) + \
               (case['K'] * case['N']) * (case['M'] / 4) + \
               (case['M'] * case['N'] * 4)

    # AI 计算 (Baseline 4x16 逻辑) - 仅用于前三个点
    bytes_2d = (case['M'] * case['K']) * (case['N'] / 4) + \
               (case['K'] * case['N']) * (case['M']) + \
               (case['M'] * case['N'] * 4)

    ai_3d = total_ops / bytes_3d
    ai_2d = total_ops / bytes_2d
    perf = total_ops / case['cycles']

    # --- 视觉抖动 (防止重叠) ---
    jitter = 1.0
    # Case 1 (Baseline & Scaled) 往左移
    # if "Case 1" in case['name']: jitter = 0.94
    # # Case 2 (Baseline & Scaled) 往右移
    # if "Case 2" in case['name']: jitter = 1.06

    plot_ai_ 3d = ai_3d * jitter
    plot_ai_2d = ai_2d * jitter

    # --- 分类绘制 ---
    if i < 3:
        # === Baseline Cases (0, 1, 2) ===
        # 画圆点 (4x4x4)
        ax.plot(plot_ai_3d, perf, 'o', markersize=12, color=c, alpha=0.7, markeredgecolor='white')
        # 画方块 (4x16)
        ax.plot(plot_ai_2d, perf, 's', markersize=10, color=c, alpha=0.5, markeredgecolor='white')
        # 连线
        ax.plot([plot_ai_3d, plot_ai_2d], [perf, perf], '-', color=c, alpha=0.3)

        # 标注
        ax.annotate(f"{case['name']}", (plot_ai_3d, perf),
                    xytext=case['offset'], textcoords="offset points",
                    arrowprops=dict(arrowstyle="-", color=c),
                    ha='center', fontsize=9, fontweight='bold', color=c)

    else:
        # === Scaled Cases (3, 4, 5) ===
        # 假设 Scaled 架构沿用了 4x4x4 的数据复用策略 (即 AI 不变，Performance 提升)
        # 画五角星
        ax.plot(plot_ai_3d, perf, '*', markersize=18, color=c, alpha=0.9, markeredgecolor='white')

        # 标注
        ax.annotate(f"{case['name']}", (plot_ai_3d, perf),
                    xytext=case['offset'], textcoords="offset points",
                    arrowprops=dict(arrowstyle="-", color=c),
                    ha='center', fontsize=9, fontweight='bold', color=c)

        # (可选) 画一条箭头从 Baseline 指向 Scaled，展示性能飞跃
        # 找到对应的 Baseline 坐标 (index - 3)
        base_perf = total_ops / cases[i - 3]['cycles']
        ax.annotate("", xy=(plot_ai_3d, perf), xytext=(plot_ai_3d, base_perf),
                    arrowprops=dict(arrowstyle="->", color=c, linestyle="--"))

# 设置坐标轴
ax.set_ylim(bottom=1, top=PEAK_OPS_SCALED * 2.5)  # 留足空间
ax.set_xlim(left=0.1, right=100)
ax.set_xlabel('Arithmetic Intensity (Ops/Byte)')
ax.set_ylabel('Performance (Ops/cycle)')
ax.set_title('Roofline Scaling: 64 PEs vs 256 PEs')
ax.grid(True, which="both", ls="-", alpha=0.3)

plt.legend(loc='lower right', ncol=2)
plt.show()