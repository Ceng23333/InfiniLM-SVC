#!/usr/bin/env python3
"""
Generate multi-prefix prompts for cache routing validation.

This script generates prompts with multiple shared prefixes to better
demonstrate cache routing impact. Requests with the same prefix should
route to the same instance and benefit from cache hits.
"""

import json
import argparse
import random
import sys


def generate_multi_prefix_prompts(
    num_prompts: int,
    num_prefixes: int,
    prefix_len: int,
    suffix_len: int,
    output_file: str,
):
    """
    Generate prompts with multiple shared prefixes for cache routing validation.

    Args:
        num_prompts: Number of prompts to generate
        num_prefixes: Number of different shared prefixes to create
        prefix_len: Target length of each shared prefix (in characters)
        suffix_len: Target length of unique suffix (in characters)
        output_file: Output JSONL file path
    """
    # Generate multiple unique prefixes
    prefixes = []
    base_text = (
        "This is a shared prefix for cache routing benchmark. "
        "The following text is identical across requests with the same prefix. "
        "This prefix will be cached to validate routing functionality. "
    )

    for i in range(num_prefixes):
        # Create a unique prefix for each group
        prefix = f"Prefix Group {i}: {base_text}"
        # Repeat to reach target length
        prefix = prefix * (prefix_len // len(prefix) + 1)
        prefix = prefix[:prefix_len]
        prefixes.append(prefix)

    print(f"Generated {num_prefixes} unique prefixes, each ~{len(prefixes[0])} characters")
    print(f"Generating {num_prompts} prompts...")

    # Random seed for reproducibility
    random.seed(42)

    with open(output_file, "w", encoding="utf-8") as f:
        for i in range(num_prompts):
            # Randomly assign a prefix to each request
            # This simulates real-world scenarios where requests with same prefix
            # should route to the same instance
            prefix = random.choice(prefixes)
            prefix_group = prefixes.index(prefix)

            # Create unique suffix for each request
            suffix = f"\n\nQuestion {i} (prefix_group={prefix_group}): Explain the meaning of life in one sentence."
            # Truncate if needed
            if len(suffix) > suffix_len:
                suffix = suffix[:suffix_len]

            prompt = prefix + suffix

            # Format for vLLM custom dataset (needs "prompt" field)
            record = {
                "prompt": prompt
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    # Print statistics
    prefix_distribution = {}
    random.seed(42)  # Reset seed to match generation
    for i in range(num_prompts):
        prefix_idx = random.randint(0, num_prefixes - 1)
        prefix_distribution[prefix_idx] = prefix_distribution.get(prefix_idx, 0) + 1

    print(f"✅ Generated {num_prompts} prompts -> {output_file}")
    print(f"   Number of prefixes: {num_prefixes}")
    print(f"   Prefix length: ~{len(prefixes[0])} chars")
    print(f"   Suffix length: ~{len(suffix)} chars")
    print(f"   Total prompt length: ~{len(prompt)} chars")
    print(f"\n   Prefix distribution:")
    for prefix_idx in sorted(prefix_distribution.keys()):
        count = prefix_distribution[prefix_idx]
        percentage = (count / num_prompts) * 100
        print(f"     Prefix {prefix_idx}: {count} requests ({percentage:.1f}%)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate multi-prefix prompts for cache routing validation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 64 prompts with 4 prefixes (16 requests per prefix on average)
  python gen-multi-prefix.py --num-prompts 64 --num-prefixes 4 --prefix-len 8192 --suffix-len 32

  # Generate prompts for cache routing test with 8 prefixes
  python gen-multi-prefix.py --num-prompts 100 --num-prefixes 8 --prefix-len 4096 --suffix-len 64 --output multi_prefix.jsonl
        """
    )
    parser.add_argument(
        "--output",
        default="multi_prefix.jsonl",
        help="Output JSONL file path (default: multi_prefix.jsonl)"
    )
    parser.add_argument(
        "--num-prompts",
        type=int,
        default=64,
        help="Number of prompts to generate (default: 64)"
    )
    parser.add_argument(
        "--num-prefixes",
        type=int,
        default=4,
        help="Number of different shared prefixes to create (default: 4)"
    )
    parser.add_argument(
        "--prefix-len",
        type=int,
        default=8192,
        help="Target length of each shared prefix in characters (default: 8192)"
    )
    parser.add_argument(
        "--suffix-len",
        type=int,
        default=32,
        help="Target length of unique suffix in characters (default: 32)"
    )

    args = parser.parse_args()

    if args.num_prompts <= 0:
        print("Error: --num-prompts must be positive", file=sys.stderr)
        sys.exit(1)

    if args.num_prefixes <= 0:
        print("Error: --num-prefixes must be positive", file=sys.stderr)
        sys.exit(1)

    if args.prefix_len <= 0:
        print("Error: --prefix-len must be positive", file=sys.stderr)
        sys.exit(1)

    if args.suffix_len <= 0:
        print("Error: --suffix-len must be positive", file=sys.stderr)
        sys.exit(1)

    generate_multi_prefix_prompts(
        num_prompts=args.num_prompts,
        num_prefixes=args.num_prefixes,
        prefix_len=args.prefix_len,
        suffix_len=args.suffix_len,
        output_file=args.output,
    )


if __name__ == "__main__":
    main()
