import os
import shutil
import json
import math
import re
import torch
from safetensors import safe_open
from safetensors.torch import save_file
import torch
from safetensors.torch import save_file
import os

def bin_to_safetensors(input_folder):
    '''
    需要内存足够
    '''
    path = os.path.join(input_folder, "pytorch_model.bin")

    if not os.path.exists(path):
        print(f"文件不存在: {path}")
        return

    output_folder = input_folder

    state_dict = torch.load(path, map_location="cpu")
    save_file(state_dict, os.path.join(output_folder, "model.safetensors")) # 转换为 safetensors 格式

    exit(-1)


def func1(input_path,output_path):
    '''
    # 这些文件不需要修改，直接拷贝
    '''
    for item in os.listdir(input_path):
        print(f"item: {item}")

        if (
            item.endswith(".safetensors")
            or item.startswith("config.json")
            or item.endswith(".py")
        ):
            continue

        source = os.path.join(input_path, item)
        destination = os.path.join(output_path, item)
        print(f"source: {source}, destination: {destination}")

        if not os.path.isdir(source):
            # 如果是文件，直接拷贝
            print(f"拷贝文件：{source} 到 {destination}")
            shutil.copy2(source, destination)

    print(f"文件拷贝完成：从 {input_path} 到 {output_path}")


def func2(input_path,output_path):
    '''
    # 修改json代码
    '''
    config_path = os.path.join(input_path, "config.json")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    config_llama_dict = {
        "architectures": ["LlamaForCausalLM"],
        "attention_bias": False,
        "bos_token_id": 1,
        "eos_token_id": [2],
        "hidden_act": "silu",
        "hidden_size": 2048,
        "initializer_range": 0.02,
        "intermediate_size": 5632,
        "max_position_embeddings": 2048,
        "model_type": "llama",
        "num_attention_heads": 32,
        "num_hidden_layers": 22,
        "num_key_value_heads": 4,
        "pretraining_tp": 1,
        "rms_norm_eps": 1e-05,
        "rope_scaling": None,
        "rope_theta": 10000.0,
        "tie_word_embeddings": False,
        "torch_dtype": "bfloat16",
        "transformers_version": "4.35.0",
        "use_cache": True,
        "vocab_size": 32000,
    }

    # 从 input_path 的 config.json 中读取值，覆盖 config_llama_dict 的默认值
    for key in config_llama_dict.keys():

        if key == "architectures" or key == "model_type":
            continue

        if key in config:
            value = config[key]
            # 特殊处理 eos_token_id：确保始终是列表
            if key == "eos_token_id":
                if isinstance(value, list):
                    config_llama_dict[key] = value
                else:
                    # 如果是单个值，转换为列表
                    config_llama_dict[key] = [value]
            else:
                config_llama_dict[key] = value
            print(f"更新 {key}: {config_llama_dict[key]}")

    # 保存 config_llama_dict 到 output_path 的 config.json
    output_config_path = os.path.join(output_path, "config.json")
    with open(output_config_path, "w", encoding="utf-8") as f:
        json.dump(config_llama_dict, f, indent=2, ensure_ascii=False)

    print(f"配置文件已保存到: {output_config_path}")

def func3(input_path,output_path):
    '''
    # 修改权重
    '''

    config_path = os.path.join(input_path, "config.json")
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    scale_depth = config.get("scale_depth", 1.0)
    num_hidden_layers = config.get("num_hidden_layers", 1)
    scale_emb = config.get("scale_emb", 1.0)
    hidden_size = config.get("hidden_size", 2560)
    dim_model_base = config.get("dim_model_base", 256)

    # 计算 scale
    proj_weight_scale = scale_depth / math.sqrt(num_hidden_layers)
    embed_tokens_scale = scale_emb
    lm_head_scale = 1.0 / (hidden_size / dim_model_base)

    print(f"scale_depth: {scale_depth}")
    print(f"num_hidden_layers: {num_hidden_layers}")
    print(f"scale_emb: {scale_emb}")
    print(f"hidden_size: {hidden_size}")
    print(f"dim_model_base: {dim_model_base}")
    print(f"proj_weight_scale: {proj_weight_scale}")
    print(f"embed_tokens_scale: {embed_tokens_scale}")
    print(f"lm_head_scale: {lm_head_scale}")

    # 权重名字模式（使用正则表达式）
    proj_weight_patterns = [
        r"model\.layers\.\d+\.mlp\.down_proj\.weight",
        r"model\.layers\.\d+\.self_attn\.o_proj\.weight"
    ]
    embed_tokens_pattern = r"model\.embed_tokens\.weight"
    lm_head_pattern = r"lm_head\.weight"

    # 获取所有 safetensors 文件
    safetensors_files = [
        item for item in os.listdir(input_path)
        if item.endswith(".safetensors")
    ]

    # safetensors_files = [safetensors_files[4]]
    # print(sorted(safetensors_files))
    # exit(-1)
    # 处理每个 safetensors 文件
    for safetensors_file in sorted(safetensors_files):
        input_file_path = os.path.join(input_path, safetensors_file)
        output_file_path = os.path.join(output_path, safetensors_file)

        print(f"\n处理文件: {safetensors_file}")
        print("-" * 80)

        try:
            # 读取所有权重
            tensors = {}
            metadata = None

            with safe_open(input_file_path, framework="pt") as f:
                metadata = f.metadata()
                keys = list(f.keys())

                print(f"权重数量: {len(keys)}")

                # 处理每个权重
                for key in keys:
                    tensor = f.get_tensor(key)
                    modified = False

                    # 检查是否匹配 proj_weight 模式
                    for pattern in proj_weight_patterns:
                        if re.match(pattern, key):
                            tensor = tensor * proj_weight_scale
                            modified = True
                            print(f"  [PROJ] {key} * {proj_weight_scale}")
                            break

                    # 检查是否匹配 embed_tokens 模式
                    if not modified and re.match(embed_tokens_pattern, key):
                        # 然后对 embed_tokens.weight 应用 embed_tokens_scale
                        tensor = tensor * embed_tokens_scale
                        modified = True
                        print(f"  [EMBED] {key} * {embed_tokens_scale}")
                    elif not modified and re.match(lm_head_pattern, key):
                        tensor = tensor * lm_head_scale
                        modified = True
                        print(f"  [LM_HEAD] {key} * {lm_head_scale}")


                    # 保存权重（无论是否修改）
                    if not modified:
                        print(f"  [KEEP] {key}")
                    tensors[key] = tensor

            # 保存修改后的权重到输出文件
            save_file(tensors, output_file_path, metadata=metadata)
            print(f"\n已保存到: {output_file_path}")

        except Exception as e:
            print(f"处理文件时出错: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Convert 9g_8b_thinking (FM9G) to 9g_8b_thinking_llama (Llama format) for InfiniLM"
    )
    parser.add_argument(
        "input_path",
        help="Path to 9g_8b_thinking model directory",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help="Output path (default: input_path + '_llama')",
    )
    args = parser.parse_args()

    input_path = os.path.abspath(args.input_path.rstrip(os.sep))
    output_path = os.path.abspath(args.output) if args.output else (input_path + "_llama")

    print(f"输入路径: {input_path}")
    print(f"输出路径: {output_path}")
    if not os.path.exists(output_path):
        os.makedirs(output_path)
        print(f"已创建输出目录: {output_path}")

    func1(input_path, output_path)
    func2(input_path, output_path)
    func3(input_path, output_path)
