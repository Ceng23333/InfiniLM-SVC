#!/usr/bin/env python3
"""
Test script for InfiniLM service timeout recovery mechanism.
Makes parallel requests to the service, including some with test_hang_seconds parameter.

Example usage:
    # Test with 20% hang frequency, 35s hang duration, 20 total requests
    python test_timeout_recovery.py \\
        --url http://localhost:8000 \\
        --requests 20 \\
        --hang-frequency 0.2 \\
        --test-hang-seconds 35 \\
        --concurrency 10

    # Test with streaming requests
    python test_timeout_recovery.py \\
        --url http://localhost:8000 \\
        --requests 50 \\
        --hang-frequency 0.1 \\
        --test-hang-seconds 40 \\
        --stream

Note: The test_hang_seconds should exceed the --request-timeout value set when starting
      the service (e.g., if --request-timeout 30, use --test-hang-seconds 35 or higher).
"""

import argparse
import asyncio
import aiohttp
import json
import time
import sys
from typing import List, Dict, Tuple
from datetime import datetime


async def make_request(
    session: aiohttp.ClientSession,
    url: str,
    request_id: int,
    test_hang_seconds: int = 0,
    stream: bool = False,
    is_retry: bool = False
) -> Tuple[int, Dict, float, int]:
    """
    Make a single request to the InfiniLM service.

    Args:
        session: aiohttp session
        url: Request URL
        request_id: Unique request identifier
        test_hang_seconds: Seconds to hang (only used on first attempt, not retries)
        stream: Whether to use streaming
        is_retry: Whether this is a retry attempt (test_hang_seconds will be ignored)

    Returns:
        Tuple of (request_id, response_data, elapsed_time, status_code)
    """
    start_time = time.time()

    # Prepare request payload in OpenAI API format
    payload = {
        "model": "test-model",
        "messages": [
            {"role": "user", "content": f"Test request {request_id}. Say hello."}
        ],
        "temperature": 0.7,
        "max_tokens": 50,
        "stream": stream
    }

    # Add test_hang_seconds only on first attempt (not retries)
    if test_hang_seconds > 0 and not is_retry:
        payload["test_hang_seconds"] = test_hang_seconds

    try:
        # Use shorter connection timeout to fail fast when service is down/restarting
        # Total timeout is very long - we rely on retries for connection errors, not timeouts
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(total=60, connect=10)  # 1 min total, 10s connection timeout
        ) as response:
            status_code = response.status

            if stream:
                # Handle streaming response
                content_parts = []
                async for line in response.content:
                    if line:
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
                response_data = await response.json()

            elapsed_time = time.time() - start_time

            return (request_id, response_data, elapsed_time, status_code)

    except asyncio.TimeoutError:
        elapsed_time = time.time() - start_time
        return (request_id, {"error": "Request timeout"}, elapsed_time, 0)
    except aiohttp.ClientConnectorError as e:
        # Connection error - service is down or restarting
        elapsed_time = time.time() - start_time
        return (request_id, {"error": f"Connection error: {str(e)}"}, elapsed_time, 0)
    except aiohttp.ClientError as e:
        # Other client errors
        elapsed_time = time.time() - start_time
        return (request_id, {"error": f"Client error: {str(e)}"}, elapsed_time, 0)
    except Exception as e:
        elapsed_time = time.time() - start_time
        return (request_id, {"error": str(e)}, elapsed_time, 0)


async def run_parallel_requests(
    base_url: str,
    total_requests: int,
    hang_frequency: float,
    test_hang_seconds: int,
    stream: bool = False,
    concurrency: int = 10,
    max_retries: int = 3,
    retry_delay: float = 1.0
) -> List[Tuple[int, Dict, float, int]]:
    """
    Run parallel requests to the service with retry logic.

    Args:
        base_url: Base URL of the service (e.g., "http://localhost:8000")
        total_requests: Total number of requests to make
        hang_frequency: Frequency of hang requests (0.0 to 1.0, e.g., 0.1 means 10%)
        test_hang_seconds: Number of seconds to hang for test requests
        stream: Whether to use streaming requests
        concurrency: Maximum number of concurrent requests
        max_retries: Maximum number of retry attempts for failed requests
        retry_delay: Delay in seconds between retries

    Returns:
        List of (request_id, response_data, elapsed_time, status_code) tuples
    """
    url = f"{base_url}/chat/completions"

    # Create semaphore to limit concurrency
    semaphore = asyncio.Semaphore(concurrency)

    async def make_request_with_retry(request_id: int, use_hang: bool):
        """Make request with retry logic, removing test_hang_seconds on retries"""
        hang_seconds = test_hang_seconds if use_hang else 0
        last_result = None
        start_time_overall = time.time()

        for attempt in range(max_retries + 1):
            async with semaphore:
                async with aiohttp.ClientSession() as session:
                    is_retry = attempt > 0
                    result = await make_request(
                        session, url, request_id, hang_seconds, stream, is_retry
                    )
                    _, _, attempt_elapsed, status_code = result
                    last_result = result

                    total_elapsed = time.time() - start_time_overall

                    # Log intermediate status
                    attempt_type = "RETRY" if is_retry else "INITIAL"
                    hang_info = f" (hang={hang_seconds}s)" if hang_seconds > 0 and not is_retry else ""
                    print(f"[{attempt_type}] Request {request_id}, Attempt {attempt + 1}/{max_retries + 1}: "
                          f"Status {status_code}, Attempt time {attempt_elapsed:.2f}s, "
                          f"Total elapsed {total_elapsed:.2f}s{hang_info}")

                    # If successful, return immediately
                    if status_code == 200:
                        return (
                            result[0],
                            result[1],
                            total_elapsed,
                            status_code,
                            attempt + 1,
                        )

                    # Retry on connection errors (status 0) and 503 (Service Unavailable)
                    # 503 indicates temporary unavailability (e.g., service restarting)
                    # Other HTTP errors (4xx, 5xx) are actual errors, retrying usually won't help
                    # Timeouts mean service is slow, retrying won't help
                    if status_code == 0 or status_code == 503:
                        # Connection error or service unavailable - retry if attempts remain
                        if attempt >= max_retries:
                            return (
                                result[0],
                                result[1],
                                total_elapsed,
                                status_code,
                                attempt + 1,
                            )
                    else:
                        # Not a retryable error, don't retry
                        return (
                            result[0],
                            result[1],
                            total_elapsed,
                            status_code,
                            attempt + 1,
                        )

            # Wait before retry (except on last attempt) - release semaphore during wait
            if attempt < max_retries:
                print(f"[RETRY] Request {request_id}: Waiting {retry_delay}s before retry...")
                await asyncio.sleep(retry_delay)

        # Fallback return with total elapsed and attempts
        total_elapsed = time.time() - start_time_overall
        return (
            last_result[0],
            last_result[1],
            total_elapsed,
            last_result[3],
            max_retries + 1,
        )

    # Determine which requests should hang
    hang_requests = set()
    num_hang_requests = int(total_requests * hang_frequency)
    import random
    random.seed(42)  # For reproducibility
    hang_requests = set(random.sample(range(total_requests), num_hang_requests))

    print(f"📊 Test Configuration:")
    print(f"   Total requests: {total_requests}")
    print(f"   Hang frequency: {hang_frequency:.1%} ({num_hang_requests} requests)")
    print(f"   Test hang duration: {test_hang_seconds}s")
    print(f"   Concurrency: {concurrency}")
    print(f"   Streaming: {stream}")
    print(f"   Max retries: {max_retries}")
    print(f"   Retry delay: {retry_delay}s")
    print(f"   Service URL: {url}")
    print()

    # Create tasks
    tasks = []
    for i in range(total_requests):
        use_hang = i in hang_requests
        task = make_request_with_retry(i, use_hang)
        tasks.append(task)

    # Run all tasks
    print(f"🚀 Sending {total_requests} parallel requests...")
    start_time = time.time()
    results = await asyncio.gather(*tasks, return_exceptions=True)
    total_time = time.time() - start_time

    # Process results and normalize shape to 5-tuple (id, data, elapsed, status, attempts)
    processed_results = []
    for i, result in enumerate(results):
        try:
            if isinstance(result, Exception):
                processed_results.append((i, {"error": str(result)}, 0, 0, 1))
                continue

            if isinstance(result, tuple):
                if len(result) == 5:
                    processed_results.append(result)
                elif len(result) == 4:
                    processed_results.append((*result, 1))
                elif len(result) == 3:
                    # Pad missing status code with 0, attempts=1
                    processed_results.append((result[0], result[1], result[2], 0, 1))
                else:
                    processed_results.append((i, {"error": f"Unexpected result shape: {len(result)}"}, 0, 0, 1))
            else:
                processed_results.append((i, {"error": f"Unexpected result type: {type(result).__name__}"}, 0, 0, 1))
        except Exception as e:
            processed_results.append((i, {"error": f"Normalization error: {e}"}, 0, 0, 1))

    return processed_results, total_time


def print_summary(results: List[Tuple[int, Dict, float, int]], total_time: float):
    """Print summary statistics of the test results."""
    print("\n" + "="*80)
    print("📈 Test Results Summary")
    print("="*80)

    # Filter only well-formed entries (length 4 or 5)
    normalized_results = []
    for entry in results:
        if isinstance(entry, tuple) and len(entry) == 5:
            normalized_results.append(entry)
        elif isinstance(entry, tuple) and len(entry) == 4:
            rid, data, elapsed, status = entry
            normalized_results.append((rid, data, elapsed, status, 1))
        elif isinstance(entry, tuple) and len(entry) == 3:
            rid, data, elapsed = entry
            normalized_results.append((rid, data, elapsed, 0, 1))
        else:
            continue

    total_requests = len(normalized_results)
    denom = total_requests if total_requests else 1
    successful = sum(1 for *_, status, _attempts in normalized_results if status == 200)
    timeout_errors = sum(1 for *_, status, _attempts in normalized_results if status == 504)
    internal_errors = sum(1 for *_, status, _attempts in normalized_results if status == 500)
    other_errors = sum(1 for *_, status, _attempts in normalized_results if status not in [200, 504, 500] and status != 0)
    failed = sum(1 for *_, status, _attempts in normalized_results if status == 0)
    retried = sum(1 for *_, status, attempts in normalized_results if attempts > 1)
    total_attempts = sum(attempts for *_, attempts in normalized_results)

    print(f"\nTotal Requests: {total_requests}")
    print(f"Successful (200): {successful} ({successful/denom*100:.1f}%)")
    print(f"Timeout Errors (504): {timeout_errors} ({timeout_errors/denom*100:.1f}%)")
    print(f"Internal Errors (500): {internal_errors} ({internal_errors/denom*100:.1f}%)")
    print(f"Other Errors: {other_errors} ({other_errors/denom*100:.1f}%)")
    print(f"Failed/Timeout: {failed} ({failed/denom*100:.1f}%)")
    print(f"Retried Requests (>1 attempt): {retried} ({retried/denom*100:.1f}%)")
    print(f"Total Attempts (including retries): {total_attempts}")

    if successful > 0:
        successful_results = [(r, t, s, a) for _, r, t, s, a in normalized_results if s == 200]
        times = [t for _, t, _, _ in successful_results]
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
        description="Test InfiniLM service timeout recovery with parallel requests"
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
        help="Total number of requests to make (default: 20)"
    )
    parser.add_argument(
        "--hang-frequency",
        type=float,
        default=0.0,
        help="Frequency of hang requests (0.0 to 1.0, default: 0.0 = 0%%)"
    )
    parser.add_argument(
        "--test-hang-seconds",
        type=int,
        default=35,
        help="Number of seconds to hang for test requests (default: 35, should exceed request-timeout)"
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=10,
        help="Maximum number of concurrent requests (default: 10)"
    )
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Use streaming requests"
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=10,
        help="Maximum number of retry attempts for failed requests (default: 10)"
    )
    parser.add_argument(
        "--retry-delay",
        type=float,
        default=10.0,
        help="Delay in seconds between retries (default: 10.0)"
    )

    args = parser.parse_args()

    # Validate arguments
    if not 0.0 <= args.hang_frequency <= 1.0:
        print("Error: --hang-frequency must be between 0.0 and 1.0")
        sys.exit(1)

    if args.test_hang_seconds <= 0:
        print("Error: --test-hang-seconds must be positive")
        sys.exit(1)

    print(f"🧪 InfiniLM Timeout Recovery Test")
    print(f"   Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Run the test
    try:
        results, total_time = asyncio.run(
            run_parallel_requests(
                base_url=args.url,
                total_requests=args.requests,
                hang_frequency=args.hang_frequency,
                test_hang_seconds=args.test_hang_seconds,
                stream=args.stream,
                concurrency=args.concurrency,
                max_retries=args.max_retries,
                retry_delay=args.retry_delay
            )
        )

        # Print summary
        print_summary(results, total_time)

        # Exit with error code if there were failures (use status field even for 5-tuples)
        failed_count = 0
        for entry in results:
            if not isinstance(entry, tuple):
                failed_count += 1
                continue
            if len(entry) >= 4:
                status = entry[3]
                if status not in [200, 500, 504]:
                    failed_count += 1
            else:
                failed_count += 1
        if failed_count > 0:
            sys.exit(1)

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
