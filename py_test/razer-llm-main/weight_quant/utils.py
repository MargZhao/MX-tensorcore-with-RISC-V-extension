import argparse
import numpy as np
import random, torch
from functools import reduce
from transformers import AutoTokenizer, AutoModelForCausalLM, LlamaConfig, MistralConfig

import json
import os
model2path = json.load(open(os.path.join(os.path.dirname(__file__), "model2path.json"), "r"))


def add_common_args(parser: argparse.ArgumentParser):
    parser.add_argument('--model_name', type=str, help="model to load")
    parser.add_argument('--w_bits', type=int, default=16, help="Number of bits for weight quantization.")
    parser.add_argument('--w_dtype', type=str, default="fp16", help="Data Type for weight quantization.")
    parser.add_argument('--w_groupsize', type=int, default=-1, help="Group Size for weight quantization.")
    return parser


# Set seed for reproducibility
def set_seed(seed=0):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


def load_model_and_tokenizer(model_name, device_map="cuda:0"):
    """
    Args:
        model_name: The model to be evaluated.
        quant_config: The quantization configuration. Will be discarded if "use_fp16=True".
        device_map: "cpu" or "cuda".
    Returns:
        `tuple(torch.Tensor)` comprising of the query and key tensors rotated using the Rotary Position Embedding.
    """

    model_path_fp16 = model2path[model_name]

    if 'llama' in model_path_fp16.lower():
        config = LlamaConfig.from_pretrained(model_path_fp16)

        from transformers import LlamaForCausalLM
        model = LlamaForCausalLM.from_pretrained(
            model_path_fp16,
            config=config,
            torch_dtype=torch.float16,
            device_map=device_map
        )
    elif 'mistral' in model_path_fp16.lower():
        config = MistralConfig.from_pretrained(model_path_fp16)

        from transformers import MistralForCausalLM
        model = MistralForCausalLM.from_pretrained(
            model_path_fp16,
            config=config,
            torch_dtype=torch.float16,
            device_map=device_map
        )
    else:
        model = AutoModelForCausalLM.from_pretrained(
            model_path_fp16,
            torch_dtype=torch.float16,
            trust_remote_code=True,
            device_map=device_map
        )
    
    tokenizer = AutoTokenizer.from_pretrained(
        model_path_fp16,
        trust_remote_code=True,
    )

    model.eval() 
    return model, tokenizer
