#!/usr/bin/env python3
"""
Test script to validate InfiniLM service max concurrency configuration.
Sends more concurrent requests than the max_concurrency limit and verifies
that requests are properly queued and processed in a controlled manner.

Example usage:
    # Test with max_concurrency=5, sending 20 concurrent requests
    python test_max_concurrency.py \\
        --url http://localhost:8000 \\
        --requests 20 \\
        --expected-max-concurrency 5 \\
        --model Qwen3-32B \\
        --max-tokens 100

    # Test with streaming requests
    python test_max_concurrency.py \\
        --url http://localhost:8000 \\
        --requests 15 \\
        --expected-max-concurrency 3 \\
        --model 9g_8b_thinking \\
        --max-tokens 50 \\
        --stream
"""

import argparse
import asyncio
import aiohttp
import json
import time
import sys
from typing import List, Dict, Tuple
from datetime import datetime
from collections import defaultdict


async def make_request(
    session: aiohttp.ClientSession,
    url: str,
    request_id: int,
    model: str = "test-model",
    max_tokens: int = 50,
    stream: bool = False
) -> Tuple[int, Dict, float, int, float, float, float]:
    """
    Make a single request to the InfiniLM service.

    Args:
        session: aiohttp session
        url: Request URL
        request_id: Unique request identifier
        model: Model name to use in requests
        max_tokens: Maximum tokens to generate
        stream: Whether to use streaming

    Returns:
        Tuple of (request_id, response_data, elapsed_time, status_code, send_time, first_response_time, end_time)
        first_response_time: When the first response chunk/data arrived (indicates server started processing)
    """
    send_time = time.time()
    first_response_time = None

    # Prepare request payload in OpenAI API format
    payload = {
        "model": model,
        "messages": [
            {"role": "user", "content": f"Test request {request_id}. Please respond with a brief explanation."}
        ],
        "temperature": 0.7,
        "max_tokens": max_tokens,
        "stream": stream
    }

    try:
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=300, connect=10)
        ) as response:
            status_code = response.status
            # First response time: when status code is received (server started processing)
            first_response_time = time.time()

            if stream:
                # Handle streaming response
                content_parts = []
                first_chunk_time = None
                async for line in response.content:
                    if line:
                        if first_chunk_time is None:
                            first_chunk_time = time.time()  # When first chunk actually arrives
                            first_response_time = first_chunk_time
                        line_str = line.decode('utf-8').strip()
                        if line_str.startswith('data: '):
                            data_str = line_str[6:]  # Remove 'data: ' prefix
                            if data_str == '[DONE]':
                                break
                            try:
                                chunk_data = json.loads(data_str)
                                if 'choices' in chunk_data and len(chunk_data['choices']) > 0:
                                    delta = chunk_data['choices'][0].get('delta', {})
                                    if 'content' in delta:
                                        content_parts.append(delta['content'])
                            except json.JSONDecodeError:
                                pass

                response_data = {
                    "content": "".join(content_parts),
                    "stream": True
                }
            else:
                # Handle non-streaming response
                # For non-streaming, we can't reliably detect when server starts processing vs when it accepts connection
                # HTTP status is received immediately on connection, not when processing starts
                # So we'll use a heuristic: assume processing starts when response body arrives
                # We'll update first_response_time when we actually get the data
                body_start_time = time.time()
                response_data = await response.json()
                # Update first_response_time to when body actually arrived (better proxy for processing start)
                # For non-streaming, this is still an estimate, but better than status code time
                first_response_time = body_start_time

            end_time = time.time()
            elapsed_time = end_time - send_time

            # Use first_response_time if set, otherwise use send_time as fallback
            if first_response_time is None:
                first_response_time = send_time

            return (request_id, response_data, elapsed_time, status_code, send_time, first_response_time, end_time)

    except asyncio.TimeoutError:
        end_time = time.time()
        elapsed_time = end_time - send_time
        if first_response_time is None:
            first_response_time = send_time
        return (request_id, {"error": "Request timeout"}, elapsed_time, 0, send_time, first_response_time, end_time)
    except aiohttp.ClientConnectorError as e:
        end_time = time.time()
        elapsed_time = end_time - send_time
        if first_response_time is None:
            first_response_time = send_time
        return (request_id, {"error": f"Connection error: {str(e)}"}, elapsed_time, 0, send_time, first_response_time, end_time)
    except aiohttp.ClientError as e:
        end_time = time.time()
        elapsed_time = end_time - send_time
        if first_response_time is None:
            first_response_time = send_time
        return (request_id, {"error": f"Client error: {str(e)}"}, elapsed_time, 0, send_time, first_response_time, end_time)
    except Exception as e:
        end_time = time.time()
        elapsed_time = end_time - send_time
        if first_response_time is None:
            first_response_time = send_time
        return (request_id, {"error": str(e)}, elapsed_time, 0, send_time, first_response_time, end_time)


async def run_concurrency_test(
    base_url: str,
    total_requests: int,
    expected_max_concurrency: int,
    model: str = "test-model",
    max_tokens: int = 50,
    stream: bool = False
) -> Tuple[List[Tuple], float]:
    """
    Run concurrent requests to validate max_concurrency behavior.

    Args:
        base_url: Base URL of the service
        total_requests: Total number of requests to send
        expected_max_concurrency: Expected max_concurrency setting on the server
        model: Model name to use in requests
        max_tokens: Maximum tokens to generate per request
        stream: Whether to use streaming requests

    Returns:
        Tuple of (results list, total_test_time)
    """
    url = f"{base_url}/chat/completions"

    print(f"📊 Max Concurrency Validation Test")
    print(f"   Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"   Service URL: {url}")
    print(f"   Model: {model}")
    print(f"   Total requests: {total_requests}")
    print(f"   Expected max concurrency: {expected_max_concurrency}")
    print(f"   Max tokens per request: {max_tokens}")
    print(f"   Streaming: {stream}")
    print()

    # Send all requests concurrently (they should be queued on the server side)
    async def make_request_wrapper(request_id: int):
        async with aiohttp.ClientSession() as session:
            return await make_request(session, url, request_id, model, max_tokens, stream)

    print(f"🚀 Sending {total_requests} requests concurrently...")
    start_time = time.time()

    # Create all tasks at once - they should be queued by the server
    tasks = [make_request_wrapper(i) for i in range(total_requests)]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    total_time = time.time() - start_time

    # Process results - normalize to 7-tuple format
    processed_results = []
    for i, result in enumerate(results):
        if isinstance(result, Exception):
            processed_results.append((i, {"error": str(result)}, 0, 0, 0, 0, 0))
        elif isinstance(result, tuple):
            if len(result) == 7:
                processed_results.append(result)
            elif len(result) == 6:
                # Old format: add first_response_time = start_time
                processed_results.append((*result[:5], result[4], result[5]))
            elif len(result) >= 4:
                # Pad to 7-tuple
                padded = list(result[:4]) + [0, 0, 0]  # send_time, first_response_time, end_time
                processed_results.append(tuple(padded[:7]))
            else:
                processed_results.append((i, {"error": f"Unexpected result: {result}"}, 0, 0, 0, 0, 0))
        else:
            processed_results.append((i, {"error": f"Unexpected result type: {type(result)}"}, 0, 0, 0, 0, 0))

    return processed_results, total_time


def analyze_concurrency(results: List[Tuple], expected_max_concurrency: int):
    """
    Analyze results to validate max concurrency behavior.

    Args:
        results: List of (request_id, response_data, elapsed_time, status_code, start_time, end_time) tuples
        expected_max_concurrency: Expected max concurrency limit
    """
    print("\n" + "="*80)
    print("📈 Server-Side Max Concurrency Analysis")
    print("="*80)

    # Extract timing information: use first_response_time to indicate when server started processing
    active_periods = []  # List of (first_response_time, end_time) tuples for when server was processing each request
    for result in results:
        if len(result) >= 7:
            _, _, elapsed, status, send_time, first_response_time, end_time = result[:7]
            if status == 200 and first_response_time > 0 and end_time > first_response_time:
                active_periods.append((first_response_time, end_time))
        elif len(result) >= 6:
            # Fallback for older format: use start_time as proxy (less accurate)
            _, _, elapsed, status, start_time, end_time = result[:6]
            if status == 200 and start_time > 0 and end_time > start_time:
                active_periods.append((start_time, end_time))

    if not active_periods:
        print("❌ No successful requests to analyze")
        return False

    # Sort by first_response_time (when server started processing)
    active_periods.sort(key=lambda x: x[0])

    # Find maximum concurrent requests being processed by server at any point in time
    # This measures server-side concurrency, not client-side
    max_concurrent_observed = 0
    concurrent_timeline = []

    # Create a timeline of events (server start processing / finish processing)
    events = []
    for server_start, server_end in active_periods:
        events.append((server_start, 1))   # Server started processing this request
        events.append((server_end, -1))    # Server finished processing this request

    # Sort events by time
    events.sort(key=lambda x: x[0])

    # Count concurrent requests being processed by server over time
    current_concurrent = 0
    for timestamp, delta in events:
        current_concurrent += delta
        concurrent_timeline.append((timestamp, current_concurrent))
        max_concurrent_observed = max(max_concurrent_observed, current_concurrent)

    # Calculate max from timeline - this is more accurate as it's based on actual overlaps
    timeline_max = max(concurrent_timeline, key=lambda x: x[1])[1] if concurrent_timeline else 0

    # Calculate statistics
    successful = sum(1 for r in results if len(r) >= 4 and r[3] == 200)
    failed = len(results) - successful

    # Analyze request timing - focus on server-side processing
    successful_results = []
    for r in results:
        if len(r) >= 7 and r[3] == 200:
            successful_results.append(r)
        elif len(r) >= 6 and r[3] == 200:
            # Fallback: pad with first_response_time = start_time
            successful_results.append((*r[:5], r[4], r[5]))  # Duplicate start_time as first_response_time

    if successful_results:
        times = [r[2] for r in successful_results]  # elapsed_time (client perspective)
        send_times = [r[4] for r in successful_results]  # When client sent request
        first_response_times = [r[5] for r in successful_results]  # When server started processing
        end_times = [r[6] for r in successful_results]  # When server finished

        # Calculate server processing times (first_response_time to end_time)
        server_processing_times = [end - first for first, end in zip(first_response_times, end_times)]

        # Calculate how requests are batched by server
        # If max_concurrency is working, requests should start processing in batches
        sorted_by_server_start = sorted(zip(range(len(first_response_times)), first_response_times), key=lambda x: x[1])

        # Calculate time spread of when server starts processing requests
        min_server_start = min(first_response_times)
        max_server_start = max(first_response_times)
        server_start_spread = max_server_start - min_server_start

        # Calculate total server processing window
        min_server_start_all = min(first_response_times)
        max_server_end_all = max(end_times)
        total_server_processing_window = max_server_end_all - min_server_start_all

    print(f"\n📊 Results Summary:")
    print(f"   Total requests: {len(results)}")
    print(f"   Successful (200): {successful} ({successful/len(results)*100:.1f}%)")
    print(f"   Failed: {failed} ({failed/len(results)*100:.1f}%)")

    if successful_results:
        print(f"\n⏱️  Timing Analysis (Server-Side):")
        print(f"   Min client response time: {min(times):.2f}s")
        print(f"   Max client response time: {max(times):.2f}s")
        print(f"   Avg client response time: {sum(times)/len(times):.2f}s")
        print(f"   Min server processing time: {min(server_processing_times):.2f}s")
        print(f"   Max server processing time: {max(server_processing_times):.2f}s")
        print(f"   Avg server processing time: {sum(server_processing_times)/len(server_processing_times):.2f}s")
        print(f"   Server start spread: {server_start_spread:.2f}s (time between first and last request starting on server)")
        print(f"   Total server processing window: {total_server_processing_window:.2f}s")

    print(f"\n🔒 Server-Side Concurrency Analysis:")
    print(f"   Expected max concurrency (server setting): {expected_max_concurrency}")

    # Calculate max from timeline - this is the most accurate measurement
    timeline_max = max(concurrent_timeline, key=lambda x: x[1])[1] if concurrent_timeline else 0

    print(f"   Calculated max concurrent (from overlaps): {max_concurrent_observed}")
    print(f"   Timeline max concurrent (from processing windows): {timeline_max}")
    print(f"   → Using timeline max ({timeline_max}) as it's based on actual server processing periods")

    # Validate concurrency limit using timeline max (most accurate)
    # Allow some margin (e.g., 10% or at least 1) to account for timing measurement precision
    margin = max(1, int(expected_max_concurrency * 0.1))
    if timeline_max <= expected_max_concurrency + margin:
        print(f"   ✅ PASS: Timeline max concurrent requests ({timeline_max}) <= expected limit ({expected_max_concurrency} ± {margin})")
        concurrency_valid = True
    else:
        print(f"   ❌ FAIL: Timeline max concurrent requests ({timeline_max}) > expected limit ({expected_max_concurrency})")
        print(f"      This suggests max_concurrency is not working correctly on the server!")
        concurrency_valid = False

    # Analyze request ordering
    # If max_concurrency is working, requests should be processed in batches
    if len(successful_results) >= expected_max_concurrency * 2:
        # Group requests by start time to identify batches
        sorted_by_start = sorted(successful_results, key=lambda x: x[4])  # Sort by start_time

        # Calculate gaps between request starts
        start_gaps = []
        for i in range(1, len(sorted_by_start)):
            gap = sorted_by_start[i][4] - sorted_by_start[i-1][4]
            if gap > 0.1:  # Ignore very small gaps (same batch)
                start_gaps.append(gap)

        if start_gaps:
            avg_gap = sum(start_gaps) / len(start_gaps)
            print(f"\n📦 Batch Analysis:")
            print(f"   Average gap between batches: {avg_gap:.2f}s")

            # Estimate actual concurrency by looking at overlapping requests
            overlap_analysis = []
            for i, (start1, end1) in enumerate(active_periods):
                concurrent_count = 1
                for start2, end2 in active_periods[i+1:]:
                    # Check if requests overlap
                    if not (end1 < start2 or end2 < start1):
                        concurrent_count += 1
                overlap_analysis.append(concurrent_count)

            if overlap_analysis:
                avg_overlapping = sum(overlap_analysis) / len(overlap_analysis)
                print(f"   Average overlapping requests: {avg_overlapping:.2f}")
                if avg_overlapping <= expected_max_concurrency * 1.2:  # Allow 20% margin
                    print(f"   ✅ Batch processing appears to be working correctly")
                else:
                    print(f"   ⚠️  Average overlap ({avg_overlapping:.1f}) exceeds expected concurrency")

    # Show concurrent requests over time (sample points)
    # The timeline shows actual server-side concurrency - this is the key metric!
    if concurrent_timeline:
        print(f"\n📈 Server Concurrent Requests Timeline (sample):")
        print(f"   (Shows how many requests are being processed by server at each point in time)")
        # Sample every 10% of the timeline
        sample_points = 10
        time_range = concurrent_timeline[-1][0] - concurrent_timeline[0][0]
        if time_range > 0:
            for i in range(sample_points + 1):
                sample_time = concurrent_timeline[0][0] + (time_range * i / sample_points)
                # Find closest point
                closest = min(concurrent_timeline, key=lambda x: abs(x[0] - sample_time))
                # Calculate relative time from start for readability
                relative_time = closest[0] - concurrent_timeline[0][0]
                print(f"   {relative_time:.2f}s: {closest[1]} concurrent requests")
        else:
            # If all requests happen at same time, just show max
            max_point = max(concurrent_timeline, key=lambda x: x[1])
            print(f"   {max_point[1]} concurrent requests at time {concurrent_timeline[0][0]:.2f}s")


    print("\n" + "="*80)

    return concurrency_valid


def print_summary(results: List[Tuple], total_time: float):
    """Print summary statistics of the test results."""
    print("\n" + "="*80)
    print("📈 Test Results Summary")
    print("="*80)

    total_requests = len(results)
    successful = sum(1 for r in results if len(r) >= 4 and r[3] == 200)
    failed = total_requests - successful

    print(f"\nTotal Requests: {total_requests}")
    print(f"Successful (200): {successful} ({successful/total_requests*100:.1f}%)")
    print(f"Failed: {failed} ({failed/total_requests*100:.1f}%)")

    successful_results = [r for r in results if len(r) >= 4 and r[3] == 200]
    if successful_results:
        times = [r[2] for r in successful_results]
        print(f"\nResponse Times (successful requests):")
        print(f"  Min: {min(times):.2f}s")
        print(f"  Max: {max(times):.2f}s")
        print(f"  Avg: {sum(times)/len(times):.2f}s")

    print(f"\nTotal Test Duration: {total_time:.2f}s")
    total_time_safe = total_time if total_time > 0 else 1e-6
    print(f"Requests per second: {total_requests/total_time_safe:.2f}")

    print("\n" + "="*80)


def main():
    parser = argparse.ArgumentParser(
        description="Test InfiniLM service max concurrency configuration"
    )
    parser.add_argument(
        "--url",
        type=str,
        default="http://localhost:8000",
        help="Base URL of the InfiniLM service (default: http://localhost:8000)"
    )
    parser.add_argument(
        "--requests",
        type=int,
        default=20,
        help="Total number of requests to send concurrently (default: 20)"
    )
    parser.add_argument(
        "--expected-max-concurrency",
        type=int,
        required=True,
        help="Expected max_concurrency setting on the server (required)"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="test-model",
        help="Model name to use in requests (default: test-model)"
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=50,
        help="Maximum tokens to generate per request (default: 50)"
    )
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Use streaming requests"
    )

    args = parser.parse_args()

    # Validate arguments
    if args.requests <= 0:
        print("Error: --requests must be positive")
        sys.exit(1)

    if args.expected_max_concurrency <= 0:
        print("Error: --expected-max-concurrency must be positive")
        sys.exit(1)

    if args.max_tokens <= 0:
        print("Error: --max-tokens must be positive")
        sys.exit(1)

    # Run the test
    try:
        results, total_time = asyncio.run(
            run_concurrency_test(
                base_url=args.url,
                total_requests=args.requests,
                expected_max_concurrency=args.expected_max_concurrency,
                model=args.model,
                max_tokens=args.max_tokens,
                stream=args.stream
            )
        )

        # Analyze concurrency behavior
        concurrency_valid = analyze_concurrency(results, args.expected_max_concurrency)

        # Print summary
        print_summary(results, total_time)

        # Exit with error code if concurrency validation failed
        if not concurrency_valid:
            print("\n❌ Max concurrency validation FAILED")
            sys.exit(1)
        else:
            print("\n✅ Max concurrency validation PASSED")
            sys.exit(0)

    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
