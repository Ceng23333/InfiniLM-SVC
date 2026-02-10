#!/usr/bin/env python3
"""
Compare benchmark results between size-based routing and 2-paged round-robin.

This script compares results from:
1. Size-based routing: paged cache (small requests) + static cache (large requests)
2. 2-paged round-robin: 2 paged cache instances with round-robin routing

This helps validate the benefits of size-based routing.
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Optional, List, Tuple
import glob


def load_result(file_path: str) -> dict:
    """Load a benchmark result JSON file."""
    with open(file_path, 'r') as f:
        data = json.load(f)
        data['_file_path'] = file_path
        return data


def find_latest_result(pattern: str, results_dir: str = "results") -> Optional[dict]:
    """Find the most recent result file matching a pattern."""
    results_path = Path(results_dir)
    if not results_path.exists():
        return None

    matching_files = []
    for file_path in results_path.glob("*.json"):
        if pattern in file_path.name:
            matching_files.append(file_path)

    if not matching_files:
        return None

    # Sort by modification time, most recent first
    matching_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return load_result(str(matching_files[0]))


def compare_routing_strategies(
    size_based_result: dict,
    paged_2_result: dict,
):
    """Compare performance between size-based routing and 2-paged round-robin."""
    print("=" * 70)
    print("Routing Strategy Comparison")
    print("=" * 70)
    print()
    print("Strategy 1: Size-Based Routing")
    print("  - Paged cache (GPU 0) for small requests (≤50KB)")
    print("  - Static cache (GPU 2) for large requests (>50KB)")
    print()
    print("Strategy 2: 2 Paged Cache Round-Robin")
    print("  - Two paged cache instances (GPU 0, GPU 3)")
    print("  - Round-robin routing (no size-based selection)")
    print()
    print("=" * 70)
    print()

    print("Size-Based Routing Results:")
    print(f"  File: {size_based_result.get('_file_path', 'N/A')}")
    print(f"  Date: {size_based_result.get('date', 'N/A')}")
    print(f"  Completed: {size_based_result.get('completed', 0)} requests")
    print(f"  Failed: {size_based_result.get('failed', 0)} requests")
    print()

    print("2 Paged Round-Robin Results:")
    print(f"  File: {paged_2_result.get('_file_path', 'N/A')}")
    print(f"  Date: {paged_2_result.get('date', 'N/A')}")
    print(f"  Completed: {paged_2_result.get('completed', 0)} requests")
    print(f"  Failed: {paged_2_result.get('failed', 0)} requests")
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

    print(f"{'Metric':<35} {'Size-Based':<15} {'2-Paged RR':<15} {'Winner':<10}")
    print("-" * 70)

    size_based_wins = 0
    paged_2_wins = 0
    ties = 0

    for metric_key, metric_name, better_direction in metrics:
        size_val = size_based_result.get(metric_key, 0)
        paged_2_val = paged_2_result.get(metric_key, 0)

        if size_val == 0 and paged_2_val == 0:
            continue

        size_str = f"{size_val:.2f}" if size_val else "N/A"
        paged_2_str = f"{paged_2_val:.2f}" if paged_2_val else "N/A"

        if better_direction == 'lower':
            if size_val > 0 and paged_2_val > 0:
                if size_val < paged_2_val:
                    winner = "Size-Based"
                    size_based_wins += 1
                elif paged_2_val < size_val:
                    winner = "2-Paged RR"
                    paged_2_wins += 1
                else:
                    winner = "Tie"
                    ties += 1
            elif size_val > 0:
                winner = "Size-Based"
                size_based_wins += 1
            elif paged_2_val > 0:
                winner = "2-Paged RR"
                paged_2_wins += 1
            else:
                winner = "N/A"
        else:  # higher is better
            if size_val > 0 and paged_2_val > 0:
                if size_val > paged_2_val:
                    winner = "Size-Based"
                    size_based_wins += 1
                elif paged_2_val > size_val:
                    winner = "2-Paged RR"
                    paged_2_wins += 1
                else:
                    winner = "Tie"
                    ties += 1
            elif size_val > 0:
                winner = "Size-Based"
                size_based_wins += 1
            elif paged_2_val > 0:
                winner = "2-Paged RR"
                paged_2_wins += 1
            else:
                winner = "N/A"

        print(f"{metric_name:<35} {size_str:<15} {paged_2_str:<15} {winner:<10}")

    print()
    print("-" * 70)
    print("Summary")
    print("-" * 70)
    print(f"Size-Based Routing wins: {size_based_wins}")
    print(f"2-Paged Round-Robin wins: {paged_2_wins}")
    print(f"Ties: {ties}")
    print()

    # Calculate improvement percentages
    print("Improvement Analysis:")
    print()
    for metric_key, metric_name, better_direction in metrics:
        size_val = size_based_result.get(metric_key, 0)
        paged_2_val = paged_2_result.get(metric_key, 0)

        if size_val > 0 and paged_2_val > 0:
            if better_direction == 'lower':
                improvement = ((paged_2_val - size_val) / paged_2_val) * 100
                if improvement > 0:
                    print(f"  {metric_name}: Size-Based is {improvement:.1f}% better (lower)")
                elif improvement < 0:
                    print(f"  {metric_name}: 2-Paged RR is {abs(improvement):.1f}% better (lower)")
            else:  # higher is better
                improvement = ((size_val - paged_2_val) / paged_2_val) * 100
                if improvement > 0:
                    print(f"  {metric_name}: Size-Based is {improvement:.1f}% better (higher)")
                elif improvement < 0:
                    print(f"  {metric_name}: 2-Paged RR is {abs(improvement):.1f}% better (higher)")

    print()
    print("=" * 70)
    print("Conclusion")
    print("=" * 70)
    if size_based_wins > paged_2_wins:
        print("✅ Size-Based Routing shows better overall performance")
        print("   Benefits: Better cache utilization, optimized routing for request sizes")
    elif paged_2_wins > size_based_wins:
        print("✅ 2-Paged Round-Robin shows better overall performance")
        print("   Note: This may indicate that size-based routing needs tuning")
    else:
        print("⚠️  Results are mixed - both strategies have trade-offs")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Compare routing strategies: size-based vs 2-paged round-robin",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect latest results
  python compare-routing-strategies.py --auto-detect

  # Specify result files explicitly
  python compare-routing-strategies.py \\
    --size-based results/size-based-routing-*.json \\
    --2paged results/2paged-round-robin-*.json
        """,
    )

    parser.add_argument(
        "--size-based",
        type=str,
        help="Path to size-based routing result file (supports glob patterns)",
    )
    parser.add_argument(
        "--2paged",
        dest="paged_2",
        type=str,
        help="Path to 2-paged round-robin result file (supports glob patterns)",
    )
    parser.add_argument(
        "--results-dir",
        type=str,
        default="results",
        help="Directory containing result files (default: results)",
    )
    parser.add_argument(
        "--auto-detect",
        action="store_true",
        help="Auto-detect latest result files from results directory",
    )

    args = parser.parse_args()

    # Auto-detect if requested
    if args.auto_detect:
        size_based_result = find_latest_result("size-based-routing", args.results_dir)
        paged_2_result = find_latest_result("2paged-round-robin", args.results_dir)

        if not size_based_result:
            print("❌ Error: Could not find size-based routing result file")
            print(f"   Searched in: {args.results_dir}/")
            print("   Pattern: *size-based-routing*.json")
            sys.exit(1)

        if not paged_2_result:
            print("❌ Error: Could not find 2-paged round-robin result file")
            print(f"   Searched in: {args.results_dir}/")
            print("   Pattern: *2paged-round-robin*.json")
            sys.exit(1)
    else:
        # Use provided paths
        if not args.size_based:
            print("❌ Error: --size-based is required (or use --auto-detect)")
            sys.exit(1)

        # argparse converts --2paged to an attribute, try different possible names
        paged_2_arg = None
        for attr_name in ['paged_2', '_2paged', 'two_paged']:
            if hasattr(args, attr_name):
                paged_2_arg = getattr(args, attr_name)
                break

        if not paged_2_arg:
            print("❌ Error: --2paged is required (or use --auto-detect)")
            sys.exit(1)

        # Handle glob patterns
        size_based_files = glob.glob(args.size_based) if isinstance(args.size_based, str) else args.size_based
        paged_2_files = glob.glob(paged_2_arg) if isinstance(paged_2_arg, str) else paged_2_arg

        if not size_based_files:
            print(f"❌ Error: No files found matching: {args.size_based}")
            sys.exit(1)

        if not paged_2_files:
            print(f"❌ Error: No files found matching: {args.paged_2}")
            sys.exit(1)

        # Use most recent file
        size_based_result = load_result(max(size_based_files, key=lambda p: Path(p).stat().st_mtime))
        paged_2_result = load_result(max(paged_2_files, key=lambda p: Path(p).stat().st_mtime))

    compare_routing_strategies(size_based_result, paged_2_result)


if __name__ == "__main__":
    main()
