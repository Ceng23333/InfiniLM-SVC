#!/usr/bin/env python3
"""
Compare benchmark results between paged and static cache instances.

This script compares results from size-based routing benchmarks to show
the performance differences between paged and static cache types.
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Optional, List, Tuple


def load_result(file_path: str) -> dict:
    """Load a benchmark result JSON file."""
    with open(file_path, 'r') as f:
        return json.load(f)


def find_result_files(pattern: str, results_dir: str = "results") -> List[str]:
    """Find result files matching a pattern."""
    results_path = Path(results_dir)
    if not results_path.exists():
        return []

    # Simple pattern matching - look for files containing the pattern
    matching_files = []
    for file_path in results_path.glob("*.json"):
        if pattern in file_path.name:
            matching_files.append(str(file_path))

    return sorted(matching_files)


def analyze_routing_accuracy(result: dict) -> dict:
    """Analyze routing accuracy based on request sizes."""
    # This is a placeholder - actual routing accuracy would need to be
    # determined from router logs or request metadata
    return {
        "total_requests": result.get("completed", 0),
        "routing_accuracy": "N/A (requires router logs)",
    }


def compare_cache_types(
    paged_results: List[dict],
    static_results: List[dict],
    paged_name: str = "Paged Cache",
    static_name: str = "Static Cache",
):
    """Compare performance between paged and static cache results."""
    print("=" * 70)
    print("Cache Type Performance Comparison")
    print("=" * 70)
    print()

    if not paged_results:
        print(f"❌ No {paged_name} results found")
        return

    if not static_results:
        print(f"❌ No {static_name} results found")
        return

    # Use the most recent result from each type
    paged_result = paged_results[-1]
    static_result = static_results[-1]

    print(f"{paged_name} Results:")
    print(f"  File: {paged_result.get('_file_path', 'N/A')}")
    print(f"  Date: {paged_result.get('date', 'N/A')}")
    print(f"  Completed: {paged_result.get('completed', 0)} requests")
    print(f"  Failed: {paged_result.get('failed', 0)} requests")
    print()

    print(f"{static_name} Results:")
    print(f"  File: {static_result.get('_file_path', 'N/A')}")
    print(f"  Date: {static_result.get('date', 'N/A')}")
    print(f"  Completed: {static_result.get('completed', 0)} requests")
    print(f"  Failed: {static_result.get('failed', 0)} requests")
    print()

    print("-" * 70)
    print("Performance Comparison")
    print("-" * 70)
    print()

    # Compare key metrics
    metrics = [
        ('mean_ttft_ms', 'Mean TTFT (ms)', 'lower'),
        ('median_ttft_ms', 'Median TTFT (ms)', 'lower'),
        ('p99_ttft_ms', 'P99 TTFT (ms)', 'lower'),
        ('mean_tpot_ms', 'Mean TPOT (ms)', 'lower'),
        ('median_tpot_ms', 'Median TPOT (ms)', 'lower'),
        ('p99_tpot_ms', 'P99 TPOT (ms)', 'lower'),
        ('output_throughput', 'Output Throughput (tok/s)', 'higher'),
        ('total_token_throughput', 'Total Token Throughput (tok/s)', 'higher'),
        ('request_throughput', 'Request Throughput (req/s)', 'higher'),
    ]

    improvements = []
    regressions = []

    for metric_key, metric_name, better_direction in metrics:
        paged_val = paged_result.get(metric_key)
        static_val = static_result.get(metric_key)

        if paged_val is None or static_val is None:
            continue

        if better_direction == 'lower':
            # For latency metrics, lower is better
            # Compare static vs paged (static should be better for large requests)
            change = ((paged_val - static_val) / paged_val) * 100 if paged_val > 0 else 0
            improvement = static_val < paged_val
        else:  # higher
            # For throughput metrics, higher is better
            change = ((static_val - paged_val) / paged_val) * 100 if paged_val > 0 else 0
            improvement = static_val > paged_val

        status = "✅" if improvement else "⚠️"
        symbol = "↓" if better_direction == 'lower' else "↑"

        print(f"{status} {metric_name}:")
        print(f"   {paged_name}:  {paged_val:.2f}")
        print(f"   {static_name}: {static_val:.2f}")
        print(f"   Difference: {change:+.2f}% {symbol}")
        print()

        if improvement and abs(change) > 1.0:  # At least 1% improvement
            improvements.append((metric_name, change))
        elif not improvement and abs(change) > 1.0:
            regressions.append((metric_name, change))

    print("-" * 70)
    print("Summary")
    print("-" * 70)
    print()

    if improvements:
        print(f"✅ {static_name} advantages:")
        for metric_name, change in improvements:
            print(f"   - {metric_name}: {change:+.2f}%")
        print()

    if regressions:
        print(f"⚠️  {paged_name} advantages:")
        for metric_name, change in regressions:
            print(f"   - {metric_name}: {abs(change):+.2f}%")
        print()

    print("Note: This comparison shows overall performance differences.")
    print("      For accurate routing validation, check router logs to verify")
    print("      that small requests route to paged cache and large requests")
    print("      route to static cache.")


def main():
    parser = argparse.ArgumentParser(
        description="Compare benchmark results between paged and static cache instances",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compare using file patterns
  python compare-cache-types.py --paged results/paged-*.json --static results/static-*.json

  # Compare specific files
  python compare-cache-types.py --paged results/paged-20240101_120000.json --static results/static-20240101_120000.json

  # Auto-detect from results directory
  python compare-cache-types.py --auto-detect
        """
    )

    parser.add_argument(
        "--paged",
        nargs="+",
        help="Paged cache result files (supports glob patterns)"
    )
    parser.add_argument(
        "--static",
        nargs="+",
        help="Static cache result files (supports glob patterns)"
    )
    parser.add_argument(
        "--auto-detect",
        action="store_true",
        help="Auto-detect result files from results directory"
    )
    parser.add_argument(
        "--results-dir",
        default="results",
        help="Results directory for auto-detection (default: results)"
    )

    args = parser.parse_args()

    paged_results = []
    static_results = []

    if args.auto_detect:
        # Auto-detect from results directory
        import glob
        results_dir = Path(args.results_dir)
        if results_dir.exists():
            paged_files = list(results_dir.glob("*paged*.json"))
            static_files = list(results_dir.glob("*static*.json"))

            if not paged_files and not static_files:
                # Try size-based-routing results (these contain mixed routing)
                size_based_files = list(results_dir.glob("*size-based-routing*.json"))
                if size_based_files:
                    print("Note: Found size-based-routing results.")
                    print("      These contain mixed routing (both paged and static).")
                    print("      For accurate comparison, you may need separate benchmarks.")
                    print()

            for file_path in paged_files:
                try:
                    result = load_result(str(file_path))
                    result["_file_path"] = str(file_path)
                    paged_results.append(result)
                except Exception as e:
                    print(f"Warning: Failed to load {file_path}: {e}", file=sys.stderr)

            for file_path in static_files:
                try:
                    result = load_result(str(file_path))
                    result["_file_path"] = str(file_path)
                    static_results.append(result)
                except Exception as e:
                    print(f"Warning: Failed to load {file_path}: {e}", file=sys.stderr)
        else:
            print(f"Error: Results directory does not exist: {args.results_dir}")
            sys.exit(1)
    else:
        if not args.paged or not args.static:
            print("Error: --paged and --static are required (or use --auto-detect)")
            sys.exit(1)

        # Load paged cache results
        import glob
        for pattern in args.paged:
            for file_path in glob.glob(pattern):
                try:
                    result = load_result(file_path)
                    result["_file_path"] = file_path
                    paged_results.append(result)
                except Exception as e:
                    print(f"Warning: Failed to load {file_path}: {e}", file=sys.stderr)

        # Load static cache results
        for pattern in args.static:
            for file_path in glob.glob(pattern):
                try:
                    result = load_result(file_path)
                    result["_file_path"] = file_path
                    static_results.append(result)
                except Exception as e:
                    print(f"Warning: Failed to load {file_path}: {e}", file=sys.stderr)

    if not paged_results and not static_results:
        print("Error: No results found")
        print("  Use --paged and --static to specify files, or --auto-detect to find them")
        sys.exit(1)

    compare_cache_types(paged_results, static_results)


if __name__ == "__main__":
    main()
