#!/usr/bin/env python3
"""
Compare benchmark results to validate cache routing impact.

This script compares results from single-instance, round-robin, and cache-routing benchmarks
to show the benefits of cache-aware routing and load balancing.
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Optional


def load_result(file_path: str) -> dict:
    """Load a benchmark result JSON file."""
    with open(file_path, 'r') as f:
        return json.load(f)


def compare_two_results(result1: dict, result1_name: str, result1_file: str,
                        result2: dict, result2_name: str, result2_file: str,
                        comparison_name: str = "Performance Comparison"):
    """Compare two benchmark result files and show the differences."""
    print("=" * 70)
    print(comparison_name)
    print("=" * 70)
    print()

    print(f"{result1_name} Results:")
    print(f"  File: {result1_file}")
    print(f"  Date: {result1.get('date', 'N/A')}")
    print(f"  Completed: {result1.get('completed', 0)} requests")
    print(f"  Failed: {result1.get('failed', 0)} requests")
    print()

    print(f"{result2_name} Results:")
    print(f"  File: {result2_file}")
    print(f"  Date: {result2.get('date', 'N/A')}")
    print(f"  Completed: {result2.get('completed', 0)} requests")
    print(f"  Failed: {result2.get('failed', 0)} requests")
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
        val1 = result1.get(metric_key)
        val2 = result2.get(metric_key)

        if val1 is None or val2 is None:
            continue

        if better_direction == 'lower':
            change = ((val1 - val2) / val1) * 100 if val1 > 0 else 0
            improvement = val2 < val1
        else:  # higher
            change = ((val2 - val1) / val1) * 100 if val1 > 0 else 0
            improvement = val2 > val1

        status = "✅" if improvement else "⚠️"
        symbol = "↓" if better_direction == 'lower' else "↑"

        print(f"{status} {metric_name}:")
        print(f"   {result1_name}:  {val1:.2f}")
        print(f"   {result2_name}: {val2:.2f}")
        print(f"   Change: {change:+.2f}% {symbol}")
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
        print(f"✅ Improvements ({result2_name} benefits):")
        for metric_name, change in improvements:
            print(f"   • {metric_name}: {change:+.2f}%")
        print()

    if regressions:
        print(f"⚠️  Regressions ({result2_name} worse):")
        for metric_name, change in regressions:
            print(f"   • {metric_name}: {change:+.2f}%")
        print()

    if not improvements and not regressions:
        print("ℹ️  No significant difference detected.")
        print()

    # Additional insights
    print("-" * 70)
    print("Insights")
    print("-" * 70)
    print()

    val1_ttft = result1.get('mean_ttft_ms', 0)
    val2_ttft = result2.get('mean_ttft_ms', 0)

    if val2_ttft < val1_ttft:
        improvement_pct = ((val1_ttft - val2_ttft) / val1_ttft) * 100
        print(f"✅ {result2_name} shows {improvement_pct:.1f}% improvement in TTFT")
        if "cache-routing" in result2_name.lower():
            print("   This indicates cache hits are working effectively.")
        elif "round-robin" in result2_name.lower():
            print("   This indicates load balancing is distributing load effectively.")
    elif val2_ttft > val1_ttft:
        print(f"⚠️  {result2_name} shows higher TTFT than {result1_name}")
    else:
        print(f"ℹ️  Similar performance between {result1_name} and {result2_name}")

    print()


def compare_results(roundrobin_file: Optional[str] = None,
                    cache_routing_file: Optional[str] = None,
                    single_instance_file: Optional[str] = None):
    """Compare benchmark result files. Supports 2-way or 3-way comparisons."""

    # Load available results
    results = {}
    if single_instance_file:
        results['single'] = load_result(single_instance_file)
    if roundrobin_file:
        results['roundrobin'] = load_result(roundrobin_file)
    if cache_routing_file:
        results['cache-routing'] = load_result(cache_routing_file)

    if len(results) < 2:
        print("Error: At least 2 result files are required for comparison", file=sys.stderr)
        sys.exit(1)

    # If all three are provided, do comprehensive comparison
    if len(results) == 3:
        print("=" * 70)
        print("Comprehensive Benchmark Comparison")
        print("=" * 70)
        print()

        print("Single-Instance Results:")
        print(f"  File: {single_instance_file}")
        print(f"  Date: {results['single'].get('date', 'N/A')}")
        print(f"  Completed: {results['single'].get('completed', 0)} requests")
        print(f"  Failed: {results['single'].get('failed', 0)} requests")
        print()

        print("Round-Robin Results:")
        print(f"  File: {roundrobin_file}")
        print(f"  Date: {results['roundrobin'].get('date', 'N/A')}")
        print(f"  Completed: {results['roundrobin'].get('completed', 0)} requests")
        print(f"  Failed: {results['roundrobin'].get('failed', 0)} requests")
        print()

        print("Cache-Routing Results:")
        print(f"  File: {cache_routing_file}")
        print(f"  Date: {results['cache-routing'].get('date', 'N/A')}")
        print(f"  Completed: {results['cache-routing'].get('completed', 0)} requests")
        print(f"  Failed: {results['cache-routing'].get('failed', 0)} requests")
        print()

        print("-" * 70)
        print("Performance Comparison (All Configurations)")
        print("-" * 70)
        print()

        # Compare all metrics across all three
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

        for metric_key, metric_name, better_direction in metrics:
            single_val = results['single'].get(metric_key)
            rr_val = results['roundrobin'].get(metric_key)
            cr_val = results['cache-routing'].get(metric_key)

            if single_val is None or rr_val is None or cr_val is None:
                continue

            print(f"{metric_name}:")
            print(f"   Single-Instance:  {single_val:.2f}")
            print(f"   Round-Robin:      {rr_val:.2f}")
            print(f"   Cache-Routing:    {cr_val:.2f}")

            # Calculate improvements
            if better_direction == 'lower':
                rr_vs_single = ((single_val - rr_val) / single_val) * 100 if single_val > 0 else 0
                cr_vs_single = ((single_val - cr_val) / single_val) * 100 if single_val > 0 else 0
                cr_vs_rr = ((rr_val - cr_val) / rr_val) * 100 if rr_val > 0 else 0
            else:
                rr_vs_single = ((rr_val - single_val) / single_val) * 100 if single_val > 0 else 0
                cr_vs_single = ((cr_val - single_val) / single_val) * 100 if single_val > 0 else 0
                cr_vs_rr = ((cr_val - rr_val) / rr_val) * 100 if rr_val > 0 else 0

            print(f"   Round-Robin vs Single: {rr_vs_single:+.2f}%")
            print(f"   Cache-Routing vs Single: {cr_vs_single:+.2f}%")
            print(f"   Cache-Routing vs Round-Robin: {cr_vs_rr:+.2f}%")
            print()

        print("-" * 70)
        print("Summary")
        print("-" * 70)
        print()

        single_ttft = results['single'].get('mean_ttft_ms', 0)
        rr_ttft = results['roundrobin'].get('mean_ttft_ms', 0)
        cr_ttft = results['cache-routing'].get('mean_ttft_ms', 0)

        if cr_ttft < rr_ttft and cr_ttft < single_ttft:
            improvement_vs_rr = ((rr_ttft - cr_ttft) / rr_ttft) * 100
            improvement_vs_single = ((single_ttft - cr_ttft) / single_ttft) * 100
            print(f"✅ Cache-Routing shows best performance:")
            print(f"   • {improvement_vs_rr:.1f}% improvement vs Round-Robin")
            print(f"   • {improvement_vs_single:.1f}% improvement vs Single-Instance")
            print("   This indicates cache hits are working effectively.")
        elif rr_ttft < single_ttft:
            improvement = ((single_ttft - rr_ttft) / single_ttft) * 100
            print(f"✅ Round-Robin shows {improvement:.1f}% improvement vs Single-Instance")
            print("   This indicates load balancing is distributing load effectively.")
        else:
            print("ℹ️  Single-Instance shows best performance")
            print("   This may indicate overhead from routing/load balancing.")
        print()

    else:
        # Two-way comparison
        if single_instance_file and roundrobin_file:
            compare_two_results(
                results['single'], 'Single-Instance', single_instance_file,
                results['roundrobin'], 'Round-Robin', roundrobin_file,
                "Single-Instance vs Round-Robin Comparison"
            )
        elif single_instance_file and cache_routing_file:
            compare_two_results(
                results['single'], 'Single-Instance', single_instance_file,
                results['cache-routing'], 'Cache-Routing', cache_routing_file,
                "Single-Instance vs Cache-Routing Comparison"
            )
        elif roundrobin_file and cache_routing_file:
            compare_two_results(
                results['roundrobin'], 'Round-Robin', roundrobin_file,
                results['cache-routing'], 'Cache-Routing', cache_routing_file,
                "Cache Routing Impact Analysis"
            )


def main():
    parser = argparse.ArgumentParser(
        description="Compare benchmark results to validate cache routing impact",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compare round-robin vs cache-routing
  python compare-results.py results/round-robin-*.json results/cache-routing-*.json

  # Compare single-instance vs round-robin
  python compare-results.py --single results/single-instance-*.json --roundrobin results/round-robin-*.json

  # Compare single-instance vs cache-routing
  python compare-results.py --single results/single-instance-*.json --cache-routing results/cache-routing-*.json

  # Compare all three configurations
  python compare-results.py --single results/single-instance-*.json --roundrobin results/round-robin-*.json --cache-routing results/cache-routing-*.json
        """
    )
    parser.add_argument(
        "--single",
        dest="single_instance_file",
        help="Path to single-instance benchmark result JSON file"
    )
    parser.add_argument(
        "--roundrobin",
        dest="roundrobin_file",
        help="Path to round-robin benchmark result JSON file"
    )
    parser.add_argument(
        "--cache-routing",
        dest="cache_routing_file",
        help="Path to cache-routing benchmark result JSON file"
    )

    # Backward compatibility: support positional arguments
    parser.add_argument(
        "positional_files",
        nargs="*",
        help="Positional arguments for backward compatibility (roundrobin, cache-routing)"
    )

    args = parser.parse_args()

    # Handle backward compatibility with positional arguments
    if args.positional_files:
        if len(args.positional_files) == 2:
            args.roundrobin_file = args.positional_files[0]
            args.cache_routing_file = args.positional_files[1]
        else:
            print("Error: Positional arguments require exactly 2 files (roundrobin, cache-routing)", file=sys.stderr)
            sys.exit(1)

    # Validate file existence
    if args.single_instance_file and not Path(args.single_instance_file).exists():
        print(f"Error: Single-instance result file not found: {args.single_instance_file}", file=sys.stderr)
        sys.exit(1)

    if args.roundrobin_file and not Path(args.roundrobin_file).exists():
        print(f"Error: Round-robin result file not found: {args.roundrobin_file}", file=sys.stderr)
        sys.exit(1)

    if args.cache_routing_file and not Path(args.cache_routing_file).exists():
        print(f"Error: Cache-routing result file not found: {args.cache_routing_file}", file=sys.stderr)
        sys.exit(1)

    compare_results(
        roundrobin_file=args.roundrobin_file,
        cache_routing_file=args.cache_routing_file,
        single_instance_file=args.single_instance_file
    )


if __name__ == "__main__":
    main()
