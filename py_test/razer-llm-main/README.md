# razer-llm

The Redundant Zero Remapping (RaZeR) extends the standard FP4 format by repurposing its negative zero as an additional, meaningful quantization value. The idea was originally published in our [BitMoD paper](https://arxiv.org/abs/2411.11745) at HPCA 2025. Check our latest [blog](https://abdelfattah-lab.github.io/blogs/razer_blog/) for more details.

## Running weight-only quantization with RaZeR
Go to the following directory and install the conda environment. 
```bash
cd weight_quant
conda env create -f env.yaml 
conda activate razer
```

Run perplexity experiments.
```bash
bash scripts_template/test_ppl_template.sh
```
The perplexity results will be saved in the folder `results` under this directory. The model_name_path of different LLMs is specified in `model2path.json`. If you want to try new models, simply add new entries in that json file.
