#!/usr/bin/env python3
"""
Generate shared-prefix prompts for cache routing validation.

This script generates prompts where all requests share a long common prefix,
with only a short suffix that differs between requests. This is ideal for
validating that cache routing is working correctly - requests with the same
prompt_cache_key should hit the cache and have much lower TTFT.
"""

import json
import argparse
import sys


def generate_shared_prefix_prompts(
    num_prompts: int,
    prefix_len: int,
    suffix_len: int,
    output_file: str,
):
    """
    Generate prompts with shared prefix for cache routing validation.

    Args:
        num_prompts: Number of prompts to generate
        prefix_len: Target length of shared prefix (in characters)
        suffix_len: Target length of unique suffix (in characters)
        output_file: Output JSONL file path
    """
    # Construct a stable, token-friendly prefix
    # Using simple English text that tokenizes consistently
    base_prefix = (
        "This is a shared prefix for cache routing benchmark. "
        "The following text is identical across all requests. "
        "This prefix will be cached to validate routing functionality. "
    )

    # Repeat to reach target length
    prefix = base_prefix * (prefix_len // len(base_prefix) + 1)
    prefix = prefix[:prefix_len]

    print(f"Generated shared prefix: {len(prefix)} characters")
    print(f"Generating {num_prompts} prompts...")

    with open(output_file, "w", encoding="utf-8") as f:
        for i in range(num_prompts):
            # Create unique suffix for each request
            suffix = f"\n\nQuestion {i}: Explain the meaning of life in one sentence."
            # Truncate if needed
            if len(suffix) > suffix_len:
                suffix = suffix[:suffix_len]

            prompt = prefix + suffix

            # Format for vLLM custom dataset (needs "prompt" field)
            # The prompt will be automatically wrapped in chat template if needed
            record = {
                "prompt": prompt
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"✅ Generated {num_prompts} prompts -> {output_file}")
    print(f"   Prefix length: ~{len(prefix)} chars")
    print(f"   Suffix length: ~{len(suffix)} chars")
    print(f"   Total prompt length: ~{len(prompt)} chars")


def main():
    parser = argparse.ArgumentParser(
        description="Generate shared-prefix prompts for cache routing validation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 64 prompts with 8k prefix and 32 char suffix
  python gen-shared-prefix.py --num-prompts 64 --prefix-len 8192 --suffix-len 32

  # Generate prompts for cache routing test
  python gen-shared-prefix.py --num-prompts 100 --prefix-len 4096 --suffix-len 64 --output cache-routing-prompts.jsonl
        """
    )
    parser.add_argument(
        "--output",
        default="shared_prefix.jsonl",
        help="Output JSONL file path (default: shared_prefix.jsonl)"
    )
    parser.add_argument(
        "--num-prompts",
        type=int,
        default=32,
        help="Number of prompts to generate (default: 32)"
    )
    parser.add_argument(
        "--prefix-len",
        type=int,
        default=8192,
        help="Target length of shared prefix in characters (default: 8192)"
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

    if args.prefix_len <= 0:
        print("Error: --prefix-len must be positive", file=sys.stderr)
        sys.exit(1)

    if args.suffix_len <= 0:
        print("Error: --suffix-len must be positive", file=sys.stderr)
        sys.exit(1)

    generate_shared_prefix_prompts(
        num_prompts=args.num_prompts,
        prefix_len=args.prefix_len,
        suffix_len=args.suffix_len,
        output_file=args.output,
    )


if __name__ == "__main__":
    main()
