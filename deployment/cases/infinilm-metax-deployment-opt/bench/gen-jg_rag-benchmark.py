#!/usr/bin/env python3
"""
Generate RAG benchmark datasets with accumulated chat context.

Loads modules and documents from a structured YAML/JSON config, generates
multi-turn conversations with round-robin module selection by weight.
Output format is compatible with vLLM CustomDataset and includes
prompt_cache_key for cache routing.
"""

import argparse
import json
import random
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


# Question/content pools per module type (embedded)
RAG_QUESTIONS = [
    "库尔斯克会战的主要过程是什么？",
    "坦克最早诞生于何时？",
    "普罗霍罗夫卡坦克大战的规模有多大？",
    "索姆河战役中英军坦克的表现如何？",
    "虎式坦克和T-34坦克各有什么特点？",
    "法国康布雷坦克大战发生在什么时候？",
    "古德里安对装甲部队的发展有何贡献？",
    "二战中著名的坦克战有哪些？",
    "坦克在阵地突破中的作用是什么？",
    "苏联T-34坦克为什么被称为雪地之王？",
]

TRANSLATE_QUESTIONS = [
    "请将以下内容翻译成英文：人工智能正在改变我们的生活方式。",
    "请将以下内容翻译成英文：机器学习是人工智能的一个重要分支。",
    "请将以下内容翻译成英文：深度学习在图像识别领域取得了显著进展。",
    "请将以下内容翻译成英文：自然语言处理技术发展迅速。",
    "请将以下内容翻译成英文：科技创新推动社会进步。",
]

REVISE_CONTENT = [
    "本通知自发布之日起执行，请各单λ认真做好贯彻落实工作。",
    "根据上级部门的要求，我单位将于下周召开专题会议，研究部署相关工作。",
    "各部门要高度重视，加强协调配合，确保各项工作落到实处。",
    "本次会议的主要议题包括：一是总结上半年工作；二是部署下半年任务。",
    "请于本月25日前将材料报送至办公室，逾期不予受理。",
]

LIGHT_RESEARCH_QUESTIONS = [
    "请对装甲战战术演进进行系统性研判分析。",
    "请梳理二战坦克发展历程的核心技术脉络。",
    "请从军事史视角分析坦克对现代战争的影响。",
    "请研判坦克装甲车辆在未来战场的角色定位。",
    "请对坦克战经典战役进行深度对比分析。",
]


def load_config(config_path: str) -> dict:
    """Load config from YAML or JSON file."""
    path = Path(config_path)
    if not path.exists():
        # If YAML requested but missing, try .json fallback
        if path.suffix.lower() in (".yaml", ".yml"):
            json_path = path.with_suffix(".json")
            if json_path.exists():
                path = json_path
            else:
                raise FileNotFoundError(f"Config file not found: {config_path}")
        else:
            raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    suffix = path.suffix.lower()
    if suffix in (".yaml", ".yml"):
        if yaml is None:
            # Fallback to .json in same directory
            json_path = path.with_suffix(".json")
            if json_path.exists():
                with open(json_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            raise ImportError(
                "PyYAML is required for YAML config. Install with: pip install pyyaml, "
                "or use a .json config (e.g. jg_rag.json)"
            )
        return yaml.safe_load(content)
    elif suffix == ".json":
        return json.loads(content)
    else:
        raise ValueError(f"Unsupported config format: {suffix}. Use .yaml or .json")


def get_documents(doc_list: list, count: int) -> str:
    """
    Return formatted '[1] content\\n[2] content\\n...', duplicating when count > len(doc_list).
    Citation IDs are sequential 1..count; content cycles through doc_list.
    """
    if not doc_list:
        return ""
    parts = []
    for i in range(count):
        doc = doc_list[i % len(doc_list)]
        citation_id = i + 1  # Sequential 1-based citation [1], [2], ...
        content = doc.get("content", "").strip()
        parts.append(f"[{citation_id}]{content}")
    return "\n\n".join(parts)


def build_round_robin_cycle(modules: list, weights: dict[str, int]) -> list:
    """
    Build round-robin cycle from weights. E.g. {rag:2, translate:1} -> [rag, rag, translate].
    """
    module_ids = [m["id"] for m in modules]
    cycle = []
    for mid in module_ids:
        w = weights.get(mid, 1)
        if w < 1:
            w = 1
        cycle.extend([mid] * w)
    return cycle


def render_user_message(module: dict, question: str, documents_str: str) -> str:
    """Render user prompt with placeholders replaced."""
    template = module.get("user_prompt", "")
    # Normalize placeholders (handle {{question }} with space)
    msg = template.replace("{{documents}}", documents_str)
    msg = msg.replace("{{question }}", question).replace("{{question}}", question)
    return msg.strip()


def generate_rag_benchmark(
    config_path: str,
    output_file: str,
    num_conversations: int,
    messages_per_conv: int,
    weights: dict[str, int],
    num_documents: int,
    num_documents_max: int | None,
    seed: int,
    shuffle_conversations: bool = True,
) -> None:
    """Generate RAG benchmark dataset with accumulated chat context."""
    config = load_config(config_path)
    modules = config.get("modules", [])
    documents = config.get("documents", [])

    if not modules:
        raise ValueError("Config must contain at least one module")
    if not documents:
        raise ValueError("Config must contain at least one document")

    # Build round-robin cycle
    cycle = build_round_robin_cycle(modules, weights)
    module_by_id = {m["id"]: m for m in modules}

    random.seed(seed)

    # Ensure question pools have enough items
    def _expand_pool(pool: list, min_size: int) -> list:
        while len(pool) < min_size:
            pool = pool + pool
        return pool

    rag_pool = _expand_pool(RAG_QUESTIONS, num_conversations * messages_per_conv)
    translate_pool = _expand_pool(TRANSLATE_QUESTIONS, num_conversations * messages_per_conv)
    revise_pool = _expand_pool(REVISE_CONTENT, num_conversations * messages_per_conv)
    light_pool = _expand_pool(LIGHT_RESEARCH_QUESTIONS, num_conversations * messages_per_conv)

    # Shuffle pools for variety (seed already set)
    random.shuffle(rag_pool)
    random.shuffle(translate_pool)
    random.shuffle(revise_pool)
    random.shuffle(light_pool)

    pool_idx: dict[str, int] = {}

    def get_question(module_id: str) -> str:
        if module_id not in pool_idx:
            pool_idx[module_id] = 0
        if module_id in ("rag", "chat_and_rag", "policies"):
            q = rag_pool[pool_idx[module_id] % len(rag_pool)]
            pool_idx[module_id] += 1
            return q
        elif module_id == "translate":
            q = translate_pool[pool_idx[module_id] % len(translate_pool)]
            pool_idx[module_id] += 1
            return q
        elif module_id == "revise":
            q = revise_pool[pool_idx[module_id] % len(revise_pool)]
            pool_idx[module_id] += 1
            return q
        elif module_id == "LightResearch_test":
            q = light_pool[pool_idx[module_id] % len(light_pool)]
            pool_idx[module_id] += 1
            return q
        else:
            # Fallback for unknown modules: use RAG pool
            q = rag_pool[pool_idx[module_id] % len(rag_pool)]
            pool_idx[module_id] += 1
            return q

    doc_range = f"{num_documents}-{num_documents_max}" if num_documents_max else str(num_documents)
    print(f"Generating {num_conversations} conversations with {messages_per_conv} messages each...")
    print(f"  Round-robin cycle: {cycle}")
    print(f"  Documents per RAG request: {doc_range} (duplicate when > {len(documents)})")
    print(f"  Session ID format: session_{{conv_idx}}")

    all_conversations = []

    for conv_idx in range(num_conversations):
        session_id = f"session_{conv_idx}"
        conversation_records = []
        conversation_history = []

        # Assign one module per conversation (round-robin); same module for all turns
        module_id = cycle[conv_idx % len(cycle)]
        module = module_by_id[module_id]

        for msg_idx in range(messages_per_conv):

            question = get_question(module_id)

            if module.get("requires_documents", False):
                n_docs = (
                    random.randint(num_documents, num_documents_max)
                    if num_documents_max is not None and num_documents_max > num_documents
                    else num_documents
                )
                documents_str = get_documents(documents, n_docs)
            else:
                documents_str = ""

            user_content = render_user_message(module, question, documents_str)

            # Prepend system prompt to first user message in conversation
            if msg_idx == 0:
                system_prompt = module.get("system_prompt", "").strip()
                if system_prompt:
                    # Combine system + user for the first message
                    user_content = f"{system_prompt}\n\n{user_content}"

            conversation_history.append({"role": "user", "content": user_content})

            # Module-specific simulated assistant response for context accumulation
            _assistant_stubs = {
                "rag": "好的，我已根据参考文档进行分析，结论如上。",
                "chat_and_rag": "根据参考文档，我已完成回答。",
                "translate": "翻译已完成，请查阅上文。",
                "revise": "审校意见已生成，请参考上述修改建议。",
                "policies": "依据参考文件，政策要点已梳理完毕。",
                "LightResearch_test": "研判分析已完成，核心结论见上文。",
            }
            assistant_response = _assistant_stubs.get(
                module_id, "好的，我理解了。我会根据您的要求进行处理。"
            )
            conversation_history.append({"role": "assistant", "content": assistant_response})

            prompt_messages = conversation_history.copy()
            prompt_text = "\n".join([f"{m['role']}: {m['content']}" for m in prompt_messages])

            record = {
                "prompt": prompt_text,
                "messages": prompt_messages,
                "conversation_id": conv_idx,
                "message_index": msg_idx,
                "module": module_id,
                "prompt_cache_key": session_id,
            }
            conversation_records.append(record)

        all_conversations.append(conversation_records)

    # Shuffle conversation order (turns within each conversation stay in order)
    if shuffle_conversations:
        random.shuffle(all_conversations)

    with open(output_file, "w", encoding="utf-8") as f:
        for conversation_records in all_conversations:
            for record in conversation_records:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

    # Statistics
    all_records = [r for conv in all_conversations for r in conv]
    char_counts = [sum(len(m["content"]) for m in r.get("messages", [])) for r in all_records]
    max_chars = max(char_counts) if char_counts else 0
    avg_chars = sum(char_counts) / len(char_counts) if char_counts else 0

    module_counts = {}
    for r in all_records:
        m = r.get("module", "unknown")
        module_counts[m] = module_counts.get(m, 0) + 1

    print(f"\nGenerated -> {output_file}")
    print(f"  Conversations: {num_conversations}")
    print(f"  Messages per conversation: {messages_per_conv}")
    print(f"  Total records: {len(all_records)}")
    print(f"  Module distribution: {module_counts}")
    print(f"  Character stats (approx tokens = chars/4):")
    print(f"    Max input chars: {max_chars} (~{max_chars // 4} tokens)")
    print(f"    Avg input chars: {avg_chars:.1f} (~{int(avg_chars) // 4} tokens)")


def parse_weights(weights_str: str) -> dict[str, int]:
    """Parse weights from 'key1:val1,key2:val2' format."""
    if not weights_str or weights_str.lower() == "equal":
        return {}
    result = {}
    for part in weights_str.split(","):
        part = part.strip()
        if ":" in part:
            k, v = part.split(":", 1)
            try:
                result[k.strip()] = int(v.strip())
            except ValueError:
                result[k.strip()] = 1
    return result


def main():
    script_dir = Path(__file__).parent
    default_config = script_dir / "jg_rag.yaml"

    parser = argparse.ArgumentParser(
        description="Generate RAG benchmark dataset with accumulated chat context",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python gen-jg_rag-benchmark.py --num-conversations 4 --messages-per-conv 8
  python gen-jg_rag-benchmark.py --weights "rag:2,translate:1,revise:1" --output jg_rag_bench.jsonl
        """,
    )
    parser.add_argument(
        "--config",
        default=str(default_config),
        help=f"Path to YAML/JSON config (default: {default_config})",
    )
    parser.add_argument(
        "--output",
        default="jg_rag_benchmark.jsonl",
        help="Output JSONL file path (default: jg_rag_benchmark.jsonl)",
    )
    parser.add_argument(
        "--num-conversations",
        type=int,
        default=10,
        help="Number of conversations (default: 10)",
    )
    parser.add_argument(
        "--messages-per-conv",
        type=int,
        default=4,
        help="Messages per conversation (default: 4)",
    )
    parser.add_argument(
        "--weights",
        default="chat_and_rag:2,rag:3,translate:1,revise:1,policies:2,LightResearch_test:1",
        help="Module weights as key:value pairs (default: chat_and_rag:2,rag:3,...)",
    )
    parser.add_argument(
        "--num-documents",
        type=int,
        default=20,
        help="Documents per RAG request; duplicate when > 20 (default: 20)",
    )
    parser.add_argument(
        "--num-documents-max",
        type=int,
        default=None,
        help="Max documents per RAG request; if set, randomly sample in [num-documents, num-documents-max]",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for question sampling and output shuffle (default: 42)",
    )
    parser.add_argument(
        "--no-shuffle",
        action="store_true",
        help="Do not shuffle conversation order in output (deterministic ordering)",
    )

    args = parser.parse_args()

    if args.num_conversations <= 0:
        print("Error: --num-conversations must be positive", file=sys.stderr)
        sys.exit(1)
    if args.messages_per_conv <= 0:
        print("Error: --messages-per-conv must be positive", file=sys.stderr)
        sys.exit(1)
    if args.num_documents <= 0:
        print("Error: --num-documents must be positive", file=sys.stderr)
        sys.exit(1)
    if args.num_documents_max is not None and args.num_documents_max < args.num_documents:
        print("Error: --num-documents-max must be >= --num-documents", file=sys.stderr)
        sys.exit(1)

    weights = parse_weights(args.weights)

    try:
        generate_rag_benchmark(
            config_path=args.config,
            output_file=args.output,
            num_conversations=args.num_conversations,
            messages_per_conv=args.messages_per_conv,
            weights=weights,
            num_documents=args.num_documents,
            num_documents_max=args.num_documents_max,
            seed=args.seed,
            shuffle_conversations=not args.no_shuffle,
        )
    except (FileNotFoundError, ValueError, ImportError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
