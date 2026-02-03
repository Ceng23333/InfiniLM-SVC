#!/usr/bin/env python3
"""
Compare benchmark results to validate cache routing impact.

This script compares results from round-robin and cache-routing benchmarks
to show the benefits of cache-aware routing.
"""

import json
import argparse
import sys
from pathlib import Path


def load_result(file_path: str) -> dict:
    """Load a benchmark result JSON file."""
    with open(file_path, 'r') as f:
        return json.load(f)


def compare_results(roundrobin_file: str, cache_routing_file: str):
    """Compare two benchmark result files and show the differences."""
    rr = load_result(roundrobin_file)
    cr = load_result(cache_routing_file)

    print("=" * 70)
    print("Cache Routing Impact Analysis")
    print("=" * 70)
    print()

    print(f"Round-Robin Results:")
    print(f"  File: {roundrobin_file}")
    print(f"  Date: {rr.get('date', 'N/A')}")
    print(f"  Completed: {rr.get('completed', 0)} requests")
    print(f"  Failed: {rr.get('failed', 0)} requests")
    print()

    print(f"Cache-Routing Results:")
    print(f"  File: {cache_routing_file}")
    print(f"  Date: {cr.get('date', 'N/A')}")
    print(f"  Completed: {cr.get('completed', 0)} requests")
    print(f"  Failed: {cr.get('failed', 0)} requests")
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
        rr_val = rr.get(metric_key)
        cr_val = cr.get(metric_key)

        if rr_val is None or cr_val is None:
            continue

        if better_direction == 'lower':
            change = ((rr_val - cr_val) / rr_val) * 100 if rr_val > 0 else 0
            improvement = cr_val < rr_val
        else:  # higher
            change = ((cr_val - rr_val) / rr_val) * 100 if rr_val > 0 else 0
            improvement = cr_val > rr_val

        status = "✅" if improvement else "⚠️"
        symbol = "↓" if better_direction == 'lower' else "↑"

        print(f"{status} {metric_name}:")
        print(f"   Round-Robin:  {rr_val:.2f}")
        print(f"   Cache-Routing: {cr_val:.2f}")
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
        print("✅ Improvements (cache routing benefits):")
        for metric_name, change in improvements:
            print(f"   • {metric_name}: {change:+.2f}%")
        print()

    if regressions:
        print("⚠️  Regressions:")
        for metric_name, change in regressions:
            print(f"   • {metric_name}: {change:+.2f}%")
        print()

    if not improvements and not regressions:
        print("ℹ️  No significant difference detected.")
        print("   This may indicate:")
        print("   - All requests share the same prefix (no routing benefit)")
        print("   - Cache is not being hit effectively")
        print("   - Consider using multi-prefix dataset to see cache routing impact")
        print()

    # Additional insights
    print("-" * 70)
    print("Insights")
    print("-" * 70)
    print()

    rr_ttft = rr.get('mean_ttft_ms', 0)
    cr_ttft = cr.get('mean_ttft_ms', 0)

    if cr_ttft < rr_ttft:
        improvement_pct = ((rr_ttft - cr_ttft) / rr_ttft) * 100
        print(f"✅ Cache routing shows {improvement_pct:.1f}% improvement in TTFT")
        print("   This indicates cache hits are working effectively.")
    elif cr_ttft > rr_ttft:
        print("⚠️  Cache routing shows higher TTFT than round-robin")
        print("   This may indicate:")
        print("   - All requests share the same prefix (no cache routing benefit)")
        print("   - Cache misses are occurring")
        print("   - Consider using multi-prefix dataset with --num-prefixes > 1")
    else:
        print("ℹ️  Similar performance between round-robin and cache-routing")
        print("   This suggests cache routing is not providing benefits with current dataset.")

    print()


def main():
    parser = argparse.ArgumentParser(
        description="Compare benchmark results to validate cache routing impact"
    )
    parser.add_argument(
        "roundrobin_file",
        help="Path to round-robin benchmark result JSON file"
    )
    parser.add_argument(
        "cache_routing_file",
        help="Path to cache-routing benchmark result JSON file"
    )

    args = parser.parse_args()

    if not Path(args.roundrobin_file).exists():
        print(f"Error: Round-robin result file not found: {args.roundrobin_file}", file=sys.stderr)
        sys.exit(1)

    if not Path(args.cache_routing_file).exists():
        print(f"Error: Cache-routing result file not found: {args.cache_routing_file}", file=sys.stderr)
        sys.exit(1)

    compare_results(args.roundrobin_file, args.cache_routing_file)


if __name__ == "__main__":
    main()
