#!/usr/bin/env python3
"""Simple script to test size-based routing"""
import requests
import json
import time

ROUTER_URL = "http://192.168.162.18:8000/v1/chat/completions"
MODEL = "9g_8b_thinking"

print("Testing size-based routing...")
print("=" * 50)

# Test small request (should route to paged cache)
print("\n1. Small request (should route to paged cache):")
small_data = {
    "model": MODEL,
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": False,
    "max_tokens": 5
}
start = time.time()
resp = requests.post(ROUTER_URL, json=small_data, timeout=60)
elapsed = time.time() - start
print(f"   Status: {resp.status_code}")
print(f"   Time: {elapsed:.2f}s")
if resp.status_code == 200:
    print("   ✅ Success")

# Test large request (should route to static cache)
print("\n2. Large request (should route to static cache):")
large_content = "A" * 60000  # ~60KB
large_data = {
    "model": MODEL,
    "messages": [{"role": "user", "content": large_content}],
    "stream": False,
    "max_tokens": 5
}
start = time.time()
resp = requests.post(ROUTER_URL, json=large_data, timeout=120)
elapsed = time.time() - start
print(f"   Status: {resp.status_code}")
print(f"   Time: {elapsed:.2f}s")
if resp.status_code == 200:
    print("   ✅ Success")

print("\n" + "=" * 50)
print("Routing test completed!")
