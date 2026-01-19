# InfiniLM Router API Documentation

**Base URL**: `http://{HOST}:8000` (default)

Replace `{HOST}` with your router hostname or IP address (e.g., `localhost`, `192.168.1.100`, `api.example.com`).

The router provides load balancing and automatic routing to backend InfiniLM services.

---

## Quick Start

```bash
# Check router health
curl http://localhost:8000/health

# List available models
curl http://localhost:8000/models

# Chat completion with Qwen3-32B
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-32B",
    "messages": [{"role": "user", "content": "Hello, how are you?"}],
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 50,
    "max_tokens": 100,
    "repetition_penalty": 1.0,
    "chat_template_kwargs": {},
    "stream": false
  }'

# Chat completion with 9g_8b_thinking
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "9g_8b_thinking",
    "messages": [{"role": "user", "content": "What is the capital of France?"}],
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 50,
    "max_tokens": 200,
    "repetition_penalty": 1.0,
    "chat_template_kwargs": {},
    "stream": false
  }'
```

---

## OpenAI-Compatible Endpoints

Most common OpenAI API endpoints are supported and automatically routed to backend services.

### Chat Completions

**Endpoint:** `POST /v1/chat/completions` or `POST /chat/completions`

**Request:**
```json
{
  "model": "Qwen3-32B",
  "messages": [
    {"role": "user", "content": "Hello, how are you?"}
  ],
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 50,
  "max_tokens": 100,
  "repetition_penalty": 1.0,
  "chat_template_kwargs": {},
  "stream": false
}
```

**Sampling Parameters:**
- `temperature` (0.0-2.0): Controls randomness. Lower = more deterministic
- `top_p` (0.0-1.0): Nucleus sampling, considers tokens with cumulative probability
- `top_k` (integer): Limits sampling to top K most likely tokens
- `max_tokens` (integer): Maximum tokens to generate
- `repetition_penalty` (0.0-2.0): Penalizes repetition. Values > 1.0 reduce repetition, < 1.0 encourage repetition
- `chat_template_kwargs` (object): Additional keyword arguments for chat template customization. EOS token is configured in the model.

**Response:**
```json
{
  "id": "chatcmpl-123",
  "model": "Qwen3-32B",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "Hello! I'm doing well."
    }
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 12,
    "total_tokens": 22
  }
}
```

**Streaming:** Set `"stream": true` to receive Server-Sent Events (SSE).

---

### Text Completions

**Endpoint:** `POST /v1/completions` or `POST /completions`

**Request:**
```json
{
  "model": "Qwen3-32B",
  "prompt": "The capital of France is",
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 50,
  "max_tokens": 10,
  "repetition_penalty": 1.0
}
```

---

## Router Status Endpoints

### `GET /health`

Check router and backend services status.

**Response:**
```json
{
  "status": "healthy",
  "router": "running",
  "healthy_services": "2/2",
  "timestamp": "2024-01-15T10:30:00"
}
```

---

### `GET /models`

List all available models from healthy services.

**Response:**
```json
{
  "object": "list",
  "data": [
    {"id": "Qwen3-32B", "object": "model", "created": 1705312200}
  ]
}
```

---

### `GET /services`

List all registered backend services.

**Response:**
```json
{
  "services": [
    {
      "name": "service_9g8b_8100",
      "url": "http://{HOST}:8100",
      "healthy": true,
      "models": ["Qwen3-32B"]
    }
  ],
  "total": 1
}
```

---

### `GET /stats`

Get detailed statistics about all services.

**Response:**
```json
{
  "total_services": 2,
  "healthy_services": 2,
  "services": [
    {
      "name": "service_9g8b_8100",
      "healthy": true,
      "request_count": 150,
      "error_count": 0,
      "response_time": 0.123
    }
  ]
}
```

---


## Error Responses

All errors return JSON:

```json
{
  "error": "Error message"
}
```

**Common Status Codes:**
- `400` - Bad Request (invalid parameters)
- `502` - Bad Gateway (backend communication error)
- `503` - Service Unavailable (no healthy service for model)
- `504` - Gateway Timeout (backend timeout)

---

## Code Examples

### Python (requests)

```python
import requests

ROUTER_URL = "http://{HOST}:8000"  # Replace {HOST} with your router host

# Chat completion with sampling parameters
response = requests.post(
    f"{ROUTER_URL}/v1/chat/completions",
    json={
        "model": "Qwen3-32B",
        "messages": [{"role": "user", "content": "Hello"}],
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 50,
        "max_tokens": 100,
        "repetition_penalty": 1.0,
        "chat_template_kwargs": {}
    }
)
print(response.json()["choices"][0]["message"]["content"])
```

### Python (OpenAI client)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://{HOST}:8000/v1",  # Replace {HOST} with your router host
    api_key="not-needed"
)

completion = client.chat.completions.create(
    model="Qwen3-32B",
    messages=[{"role": "user", "content": "Hello"}],
    temperature=0.7,
    top_p=0.9,
    top_k=50,
    max_tokens=100,
    repetition_penalty=1.0,
    extra_body={"chat_template_kwargs": {}}
)
print(completion.choices[0].message.content)
```

### Streaming (Python)

```python
import requests
import json

response = requests.post(
    "http://{HOST}:8000/v1/chat/completions",  # Replace {HOST} with your router host
    json={
        "model": "Qwen3-32B",
        "messages": [{"role": "user", "content": "Tell me a story"}],
        "temperature": 0.8,
        "top_p": 0.9,
        "max_tokens": 200,
        "chat_template_kwargs": {},
        "stream": True
    },
    stream=True
)

for line in response.iter_lines():
    if line and line.startswith(b'data: '):
        data = line[6:].decode('utf-8')
        if data == '[DONE]':
            break
        try:
            chunk = json.loads(data)
            if 'choices' in chunk:
                delta = chunk['choices'][0].get('delta', {})
                if 'content' in delta:
                    print(delta['content'], end='', flush=True)
        except json.JSONDecodeError:
            pass
```

---

## Notes

- No API key required
- Streaming fully supported (SSE format)
- Models may not appear immediately after service startup
- Request timeout: 5 minutes (configurable)

---

**Router Port**: 8000 (default, configurable)
**Health Check**: Every 30 seconds
