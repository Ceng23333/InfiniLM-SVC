#!/usr/bin/env python3
"""
Helper script to run vLLM benchmarks directly.
This is used by the benchmark shell scripts to call the benchmark function.
"""

import sys
import asyncio
import argparse

# Add vLLM to path
vllm_dir = sys.argv[1]
sys.path.insert(0, vllm_dir)

from vllm.benchmarks.serve import main_async, add_cli_args

def main():
    parser = argparse.ArgumentParser()
    add_cli_args(parser)

    # Parse remaining arguments
    args = parser.parse_args(sys.argv[2:])

    # Run the benchmark
    result = asyncio.run(main_async(args))
    return result

if __name__ == "__main__":
    main()
