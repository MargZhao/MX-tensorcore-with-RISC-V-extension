import torch

#################################  4-bit Datatypes  #################################
FP4_E2M1 = [-6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]

FP4_SP_POS = [-6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 6.0]
FP4_SP_NEG = [-6.0, -4.0, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]

FP4_SM_POS = [-6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0]
FP4_SM_NEG = [-6.0, -5.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]

FP4_SR_POS = [-6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
FP4_SR_NEG = [-8.0, -6.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]


DATATYPE_MAPPING_4_BIT = {
    'fp4': FP4_E2M1,
    'fp4_sp_pos': FP4_SP_POS, 'fp4_sp_neg': FP4_SP_NEG, 
    'fp4_sm_pos': FP4_SM_POS, 'fp4_sm_neg': FP4_SM_NEG, 
    'fp4_sr_pos': FP4_SR_POS, 'fp4_sr_neg': FP4_SR_NEG, 
}


def quant_datatype(w_fp, quant_value: list=None):
    mid_value = [(quant_value[i] + quant_value[i + 1]) / 2 for i in range(len(quant_value) - 1)]

    qmax = max([abs(x) for x in quant_value])
    rmax = torch.amax(w_fp.abs(), dim=-1, keepdim=True)
    scale_fp = rmax / qmax
    x = w_fp / scale_fp

    w_q = torch.zeros_like(x)
    for i in range(len(quant_value)):
        data = quant_value[i]
        if i == 0:
            w_q += torch.where(x <= mid_value[i], data, 0)
        elif i == len(quant_value) - 1:
            w_q += torch.where(x > mid_value[i - 1], data, 0)
        else:
            w_q += torch.where((mid_value[i - 1] < x) & (x <= mid_value[i]), data, 0)

    w_dq = w_q * scale_fp 

    return w_dq, w_q, scale_fp