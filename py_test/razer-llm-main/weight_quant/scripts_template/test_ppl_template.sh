#!/bin/bash

########## Modify the path according to your HOME directory ##########
HOME_DIR=~/razer-llm/weight_quant
######################################################################
cd $HOME_DIR

model_list=("qwen-2.5-3b-ins" "qwen-2.5-7b-ins" "qwen-2.5-14b-ins" "llama-3.1-8b-ins" "llama-3.2-3b-ins" "qwen-2.5-3b" "qwen-2.5-7b" "qwen-2.5-14b" "llama-3.1-8b" "llama-3.2-3b" "llama-2-7b" "llama-2-13b" "mistral-7b-v3" "mistral-7b-v3-ins")
dataset_list="wikitext,c4"
seq_len=2048

OUTPUT_DIR=${HOME_DIR}/results/ppl_${seq_len}

w_bits_list=(4)
w_groupsize_list=(128)
w_dtype_list=("int4" "fp4" "fp4_razer" "mxfp4" "mxfp4_razer" "nvfp4" "nvfp4_razer")


for model_name in "${model_list[@]}"
do
    ####################  All FP16  ####################
    python run_ppl.py --model_name ${model_name} \
        --datasets ${dataset_list} --seq_len ${seq_len} \
        --output_dir ${OUTPUT_DIR} 

    for w_bits in "${w_bits_list[@]}"
    do
        for w_groupsize in "${w_groupsize_list[@]}"
        do
            for w_dtype in "${w_dtype_list[@]}"
            do

                python run_ppl.py --model_name ${model_name} \
                --datasets ${dataset_list} --seq_len ${seq_len} --output_dir ${OUTPUT_DIR} \
                --w_bits ${w_bits} --w_groupsize ${w_groupsize} --w_dtype ${w_dtype}

            done
        done
    done
done