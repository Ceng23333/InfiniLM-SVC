# InfiniLM 路由服务 API 文档

**基础 URL**: `http://{HOST}:8000` (默认)

将 `{HOST}` 替换为您的路由服务主机名或 IP 地址（例如：`localhost`、`192.168.1.100`、`api.example.com`）。

路由服务提供负载均衡和自动路由到后端 InfiniLM 服务。

---

## 快速开始

```bash
# 检查路由服务健康状态
curl http://localhost:8000/health

# 列出可用模型
curl http://localhost:8000/models

# 使用 Qwen3-32B 进行聊天补全
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-32B",
    "messages": [{"role": "user", "content": "你好，最近怎么样？"}],
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 50,
    "max_tokens": 100,
    "repetition_penalty": 1.0,
    "chat_template_kwargs": {},
    "stream": false
  }'

# 使用 9g_8b_thinking 进行聊天补全
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "9g_8b_thinking",
    "messages": [{"role": "user", "content": "山东最高的山是？"}],
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

## OpenAI 兼容接口

支持大多数常见的 OpenAI API 接口，并自动路由到后端服务。

### 聊天补全

**接口:** `POST /v1/chat/completions` 或 `POST /chat/completions`

**请求:**
```json
{
  "model": "Qwen3-32B",
  "messages": [
    {"role": "user", "content": "你好，最近怎么样？"}
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

**采样参数:**
- `temperature` (0.0-2.0): 控制随机性。值越低越确定性
- `top_p` (0.0-1.0): 核采样，考虑累积概率的 token
- `top_k` (整数): 限制采样到前 K 个最可能的 token
- `max_tokens` (整数): 生成的最大 token 数
- `repetition_penalty` (0.0-2.0): 惩罚重复。值 > 1.0 减少重复，< 1.0 鼓励重复
- `chat_template_kwargs` (对象): 用于聊天模板自定义的额外关键字参数。EOS token 已在模型中配置。

**响应:**
```json
{
  "id": "chatcmpl-123",
  "model": "Qwen3-32B",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "你好！我很好，谢谢。"
    }
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 12,
    "total_tokens": 22
  }
}
```

**流式传输:** 设置 `"stream": true` 以接收服务器发送事件 (SSE)。

---

### 文本补全

**接口:** `POST /v1/completions` 或 `POST /completions`

**请求:**
```json
{
  "model": "Qwen3-32B",
  "prompt": "法国的首都是",
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 50,
  "max_tokens": 10,
  "repetition_penalty": 1.0
}
```

---

## 路由状态接口

### `GET /health`

检查路由服务和后端服务状态。

**响应:**
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

列出所有健康服务中的可用模型。

**响应:**
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

列出所有已注册的后端服务。

**响应:**
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

获取所有服务的详细统计信息。

**响应:**
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

## 错误响应

所有错误返回 JSON：

```json
{
  "error": "错误信息"
}
```

**常见状态码:**
- `400` - 错误请求（参数无效）
- `502` - 网关错误（后端通信错误）
- `503` - 服务不可用（没有支持该模型的健康服务）
- `504` - 网关超时（后端超时）

---

## 代码示例

### Python (requests)

```python
import requests

ROUTER_URL = "http://{HOST}:8000"  # 将 {HOST} 替换为您的路由服务主机

# 聊天补全（带采样参数）
response = requests.post(
    f"{ROUTER_URL}/v1/chat/completions",
    json={
        "model": "Qwen3-32B",
        "messages": [{"role": "user", "content": "你好"}],
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

### Python (OpenAI 客户端)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://{HOST}:8000/v1",  # 将 {HOST} 替换为您的路由服务主机
    api_key="not-needed"
)

completion = client.chat.completions.create(
    model="Qwen3-32B",
    messages=[{"role": "user", "content": "你好"}],
    temperature=0.7,
    top_p=0.9,
    top_k=50,
    max_tokens=100,
    repetition_penalty=1.0,
    extra_body={"chat_template_kwargs": {}}
)
print(completion.choices[0].message.content)
```

### 流式传输 (Python)

```python
import requests
import json

response = requests.post(
    "http://{HOST}:8000/v1/chat/completions",  # 将 {HOST} 替换为您的路由服务主机
    json={
        "model": "Qwen3-32B",
        "messages": [{"role": "user", "content": "给我讲个故事"}],
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

## 注意事项

- 不需要 API 密钥
- 完全支持流式传输（SSE 格式）
- 服务启动后模型可能不会立即出现
- 请求超时：5 分钟（可配置）

---

**路由端口**: 8000 (默认，可配置)
**健康检查**: 每 30 秒
