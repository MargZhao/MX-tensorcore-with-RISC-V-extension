import torch
from typing import Optional
from .utils import quant_datatype, DATATYPE_MAPPING_4_BIT


@torch.no_grad()
def quant_int(w_fp, wq_bits:int=4, groupsize: Optional[int]=None):
    """
        Asymmetric INT quantization.
    """
    orig_shape = w_fp.shape 

    if (groupsize is None) or (groupsize <= 0):
        w_fp_new = w_fp.to(torch.float32)
    else:
        w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)
    
    rmin = torch.amin(w_fp_new, dim=-1, keepdim=True)
    rmax = torch.amax(w_fp_new, dim=-1, keepdim=True)
    qmin = -(2 ** (wq_bits - 1))
    qmax = 2 ** (wq_bits - 1) - 1
    scale_fp = (rmax - rmin) / (qmax - qmin)
    zeropoint = torch.round(-rmin / scale_fp).to(torch.int8)

    w_q = torch.clamp(torch.round(w_fp_new / scale_fp) + zeropoint, min=0, max=2**(wq_bits)-1)

    w_dq = (w_q - zeropoint) * scale_fp
    if (groupsize is None) or (groupsize <= 0):
        return w_dq
    else:
        return w_dq.view(orig_shape).to(torch.float16)


@torch.no_grad()
def quant_fp4(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        FP4-E2M1 quantization.
    """
    orig_shape = w_fp.shape 

    quant_value = DATATYPE_MAPPING_4_BIT["fp4"]
    mid_value = [(quant_value[i] + quant_value[i + 1]) / 2 for i in range(len(quant_value) - 1)]

    if (groupsize is None) or (groupsize <= 0):
        w_fp_new = w_fp.to(torch.float32)
    else:
        w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)

    rmax = torch.amax(w_fp_new.abs(), dim=-1, keepdim=True)
    qmax = max([abs(x) for x in quant_value])
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

    w_dq = w_q * scale_fp 
    if (groupsize is None) or (groupsize <= 0):
        return w_dq
    else:
        return w_dq.view(orig_shape).to(torch.float16)


@torch.no_grad()
def quant_fp4_razer(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):    
    """
        FP4-RaZeR quantization.
    """
    assert wq_bits == 4, f"Currently only support 4-bit quantization, not {wq_bits}-bit"

    datatype_list = ['fp4_sm_pos', 'fp4_sm_neg', 'fp4_sr_pos', 'fp4_sr_neg']
    
    orig_shape = w_fp.shape
    if (groupsize is None) or (groupsize <= 0):
        w_fp_new = w_fp.to(torch.float32)
    else:
        w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)
    
    ########## Search for the Optimal RaZeR-FP4 Data Type ##########
    w_dq = torch.zeros_like(w_fp_new)
    num_group = w_dq.shape[0]
    error = torch.full([num_group], 1e4, dtype=w_dq.dtype, device=w_dq.device)
    for datatype in datatype_list:
        quant_value = DATATYPE_MAPPING_4_BIT[datatype]
        w_dq_tmp, _, _ = quant_datatype(w_fp_new, quant_value=quant_value)
        quant_error = (w_dq_tmp - w_fp_new).pow(2).mean(-1)
        mask_update = torch.lt(quant_error, error)

        error[mask_update] = quant_error[mask_update]
        w_dq[mask_update]  = w_dq_tmp[mask_update]

        del w_dq_tmp, quant_error, mask_update
    ##################################################################
    
    return w_dq.view(orig_shape).to(torch.float16)


@torch.no_grad()
def quant_mxfp4(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        MXFP4 quantization.
    """
    FP32_EXPONENT_BIAS = 127
    FP32_MIN_NORMAL = 2 ** (-FP32_EXPONENT_BIAS + 1)

    EXP_BITS = 2
    MAN_BITS = 1
    EMAX = 2**(EXP_BITS - 1)
    MAX_NORM = 2**EMAX * float(2**(MAN_BITS+1) - 1) / 2**MAN_BITS

    orig_shape = w_fp.shape 
    w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)
    
    shared_exp, _ = torch.max(w_fp_new.abs(), dim=-1, keepdim=True)
    shared_exp = torch.floor(
        torch.log2(
            shared_exp + FP32_MIN_NORMAL * (shared_exp == 0).type(shared_exp.dtype)
        )
    )

    # Offset the max exponent by the largest representable exponent
    # in the element data format
    shared_exp = shared_exp - EMAX
    scale_emax = 2**7 - 1
    shared_exp[shared_exp > scale_emax] = float("NaN")
    shared_exp[shared_exp < -scale_emax] = -scale_emax

    w_q = w_fp_new / (2**shared_exp)
    private_exp = torch.floor(
        torch.log2(
            torch.abs(w_q) + (w_q == 0).type(w_q.dtype)
        )
    )
    min_exp = -(2**(EXP_BITS-1)) + 2
    private_exp = private_exp.clip(min=min_exp)
    
    w_q = w_q / (2**private_exp) * (2**MAN_BITS)
    w_q = torch.sign(w_q) * torch.floor(torch.abs(w_q) + 0.5)
    w_q = w_q * (2**private_exp) / (2**MAN_BITS)
    w_q = torch.clamp(w_q, min=-MAX_NORM, max=MAX_NORM)

    w_dq = w_q * (2**shared_exp)

    return w_dq.view(orig_shape).to(torch.float16)


@torch.no_grad()
def quant_mxfp4_razer(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        MXFP4-RaZeR quantization.
    """
    datatype_list = ['fp4_sm_pos', 'fp4_sm_neg', 'fp4_sr_pos', 'fp4_sr_neg']

    FP32_EXPONENT_BIAS = 127
    FP32_MIN_NORMAL = 2 ** (-FP32_EXPONENT_BIAS + 1)

    EXP_BITS = 2
    EMAX = 2**(EXP_BITS - 1)

    orig_shape = w_fp.shape 
    w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)
    
    shared_exp, _ = torch.max(w_fp_new.abs(), dim=-1, keepdim=True)
    shared_exp = torch.floor(
        torch.log2(
            shared_exp + FP32_MIN_NORMAL * (shared_exp == 0).type(shared_exp.dtype)
        )
    )

    # Offset the max exponent by the largest representable exponent
    # in the element data format
    shared_exp = shared_exp - EMAX
    scale_emax = 2**7 - 1
    shared_exp[shared_exp > scale_emax] = float("NaN")
    shared_exp[shared_exp < -scale_emax] = -scale_emax

    w_scaled = w_fp_new / (2**shared_exp)

    ########## Search for the Optimal RaZeR-FP4 Data Type ##########
    w_q = torch.zeros_like(w_scaled)
    num_group = w_q.shape[0]
    error = torch.full([num_group], 1e4, dtype=w_q.dtype, device=w_q.device)
    for datatype in datatype_list:
        quant_value = DATATYPE_MAPPING_4_BIT[datatype]
        mid_value   = [(quant_value[i] + quant_value[i + 1]) / 2 for i in range(len(quant_value) - 1)]
        w_q_tmp     = torch.zeros_like(w_q)
        for i in range(len(quant_value)):
            data = quant_value[i]
            if i == 0:
                w_q_tmp += torch.where(w_scaled <= mid_value[i], data, 0)
            elif i == len(quant_value) - 1:
                w_q_tmp += torch.where(w_scaled > mid_value[i - 1], data, 0)
            else:
                w_q_tmp += torch.where((mid_value[i - 1] < w_scaled) & (w_scaled <= mid_value[i]), data, 0)

        quant_error = (w_scaled - w_q_tmp).pow(2).mean(-1)
        mask_update = torch.lt(quant_error, error)
        error[mask_update] = quant_error[mask_update]
        w_q[mask_update]   = w_q_tmp[mask_update]

        del w_q_tmp, quant_error, mask_update
    ##################################################################

    w_dq = w_q * (2**shared_exp)

    return w_dq.view(orig_shape).to(torch.float16)


def quant_nvfp4(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        NVFP4 quantization.
    """
    quant_value = DATATYPE_MAPPING_4_BIT["fp4"]
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


def quant_nvfp4_razer(w_fp, wq_bits: int=4, groupsize: Optional[int]=None):
    """
        NVFP4-RaZeR quantization.
    """
    datatype_list = ['fp4_sm_pos', 'fp4_sm_neg', 'fp4_sr_pos', 'fp4_sr_neg']
    
    orig_shape = w_fp.shape
    w_fp_new = w_fp.view(-1, groupsize).to(torch.float32)

    ########## Search for the Optimal RaZeR-FP4 Data Type ##########
    w_q       = torch.zeros_like(w_fp_new)
    num_group = w_fp_new.shape[0]
    scale_fp  = torch.zeros(num_group, 1, dtype=w_q.dtype, device=w_q.device)
    error = torch.full([num_group], 1e4, dtype=w_q.dtype, device=w_q.device)
    for datatype in datatype_list:
        quant_value = DATATYPE_MAPPING_4_BIT[datatype]
        w_dq_tmp, w_q_tmp, scale_tmp = quant_datatype(w_fp_new, quant_value=quant_value)
        quant_error = (w_dq_tmp - w_fp_new).pow(2).mean(-1)
        mask_update = torch.lt(quant_error, error)

        error[mask_update]    = quant_error[mask_update]
        w_q[mask_update]      = w_q_tmp[mask_update]
        scale_fp[mask_update] = scale_tmp[mask_update]

        del w_dq_tmp, w_q_tmp, scale_tmp, quant_error, mask_update
    ##################################################################
    
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



def quant_model(model, wq_bits: Optional[int]=None, wq_datatype: Optional[str]=None, wq_groupsize: Optional[int]=None):
    wq_datatype = wq_datatype.lower()

    if (wq_bits >= 16) or (wq_datatype is None) or (wq_datatype in ["fp16", "fp32"]):
        return

    quant_func = None
    if ("int" in wq_datatype):
        quant_func   = quant_int
        wq_bits      = wq_bits
        wq_groupsize = wq_groupsize
    elif (wq_datatype == "fp4"):
        quant_func   = quant_fp4
        wq_bits      = 4
        wq_groupsize = wq_groupsize
    elif (wq_datatype == "mxfp4"):
        quant_func   = quant_mxfp4
        wq_bits      = 4
        wq_groupsize = 32
    elif (wq_datatype == "nvfp4"):
        quant_func   = quant_nvfp4
        wq_bits      = 4
        wq_groupsize = 16
    elif (wq_datatype == "fp4_razer"):
        quant_func   = quant_fp4_razer
        wq_bits      = 4
        wq_groupsize = wq_groupsize
    elif (wq_datatype == "mxfp4_razer"):
        quant_func   = quant_mxfp4_razer
        wq_bits      = 4
        wq_groupsize = 32
    elif (wq_datatype == "nvfp4_razer"):
        quant_func   = quant_nvfp4_razer
        wq_bits      = 4
        wq_groupsize = 16
    
    print(f"==================================================")
    print(f"Quantization Data Type:  {wq_datatype}")
    print(f"Quantization Bits:       {wq_bits}")
    print(f"Quantization Group Size: {wq_groupsize}")
    print(f"==================================================")

    for n, m in model.named_modules():
        if isinstance(m, torch.nn.Linear) and ('head' not in n):
            m.weight.data = quant_func(m.weight.data, wq_bits=wq_bits, groupsize=wq_groupsize)
