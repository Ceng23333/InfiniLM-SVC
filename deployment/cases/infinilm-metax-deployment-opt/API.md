# 九源-沐曦一体机 API 文档

面向用户的 **infinilm-metax-deployment-opt** 部署（2 台主机：1 主 1 从）API 参考。所有接口均通过 **主节点** 访问。

---

## 基础 URL

| 服务 | 默认 URL | 端口 | 说明 |
|------|----------|------|------|
| **Router（路由）** | `http://<MASTER_IP>:8000` | 8000 | 对话/补全、负载均衡 |
| **Registry（注册中心）** | `http://<MASTER_IP>:18000` | 18000 | 服务发现（内部） |
| **Embeddings（向量）** | `http://<MASTER_IP>:20002` | 20002 | 向量与重排序（可选） |

将 `<MASTER_IP>` 替换为主节点 IP 或主机名（例如 `192.168.163.151`，在本机则为 `localhost`）。

### 本环境示例（MASTER_IP=10.64.3.147）

| 服务 | 实际 URL |
|------|----------|
| **Router** | http://10.64.3.147:8000 |
| **Registry** | http://10.64.3.147:18000 |
| **Embeddings** | http://10.64.3.147:20002 |
| 对话补全 | http://10.64.3.147:8000/v1/chat/completions |
| 文本补全 | http://10.64.3.147:8000/v1/completions |
| 向量 | http://10.64.3.147:20002/v1/embeddings |
| 健康检查 | http://10.64.3.147:8000/health |
| 模型列表 | http://10.64.3.147:8000/models |
| 服务列表 | http://10.64.3.147:8000/services |
| 旧版向量 | http://10.64.3.147:20002/embedding |
| 重排序 MiniCPM | http://10.64.3.147:20002/rerank |
| 重排序 BCE | http://10.64.3.147:20002/rerankbce |

---

## 1. OpenAI 兼容接口

以下接口与 OpenAI API 兼容，可直接使用 OpenAI 客户端或相同请求格式调用。

### 1.1 对话补全

**服务：** Router
**路径：** `POST /v1/chat/completions` 或 `POST /chat/completions`
**Base URL：** `http://<MASTER_IP>:8000`

**请求示例：**

```json
{
  "model": "Qwen3-32B",
  "messages": [{"role": "user", "content": "你好，最近怎么样？"}],
  "temperature": 0.7,
  "top_p": 0.9,
  "top_k": 50,
  "max_tokens": 100,
  "repetition_penalty": 1.0,
  "chat_template_kwargs": {},
  "stream": false
}
```

**curl 示例（MASTER_IP=10.64.3.147）：**

```bash
curl -X POST http://10.64.3.147:8000/v1/chat/completions \
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
```

**流式：** 设置 `"stream": true` 可接收 SSE 流式响应。

### 1.2 文本补全

**服务：** Router
**路径：** `POST /v1/completions` 或 `POST /completions`
**Base URL：** `http://<MASTER_IP>:8000`

**请求示例：**

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

### 1.3 向量（Embeddings）

**服务：** Embedding（需配置 `EMBEDDING_MODEL_DIR` 并启动，见 [README.md](README.md#embedding-server-optional)）
**路径：** `POST /v1/embeddings`
**Base URL：** `http://<MASTER_IP>:20002`

**请求：**

```json
{
  "model": "text-embedding-ada-002",
  "input": "单条文本或句子。",
  "encoding_format": "float"
}
```

- `input`：字符串或字符串数组。
- `encoding_format`：可选，默认 `"float"`。

**响应（OpenAI 风格）：**

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "embedding": [0.01, -0.02, ...],
      "index": 0
    }
  ],
  "model": "text-embedding-ada-002",
  "usage": {
    "prompt_tokens": 10,
    "total_tokens": 10
  }
}
```

**curl 示例（MASTER_IP=10.64.3.147）：**

```bash
curl -X POST http://10.64.3.147:20002/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "text-embedding-ada-002", "input": "你好世界"}'
```

---

## 2. 路由状态与发现（Router）

路由是对话与补全的主入口；以下为状态与发现类接口（非 OpenAI 标准）。
完整 Router API 见项目根目录 [`API_DOCUMENTATION.md`](../../../API_DOCUMENTATION.md)。

**Base URL：** `http://<MASTER_IP>:8000`

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/health` | 路由与后端健康检查 |
| `GET` | `/models` | 列出可用模型 |
| `GET` | `/services` | 列出已注册后端服务 |
| `GET` | `/stats` | 服务统计信息 |

### 可用模型（典型）

- **Qwen3-32B** — 主模型（根据预设使用 paged / static / vLLM 后端）。
- **9g_8b_thinking** — 主节点上的 9g_8b_thinking 模型。

### 按大小路由（可选）

在主节点 `.env` 中设置 `CACHE_TYPE_ROUTING_THRESHOLD` 时：

- **小请求**（body 大小 ≤ 阈值）：转发到 **paged** 缓存。
- **大请求**（body 大小 > 阈值）：转发到 **static** 或 **vLLM** 后端。

默认阈值为 51200（50KB）。RAG 等长上下文场景可适当调低（如 15000）。

---

## 3. 其他接口（Embedding 服务）

仅在主节点设置 `EMBEDDING_MODEL_DIR` 并启动向量服务时可用。
**Base URL：** `http://<MASTER_IP>:20002`

### 3.1 旧版向量接口（query / doc）

**路径：** `POST /embedding`

**请求：**

```json
{
  "embedding_type": "query",
  "texts": ["查询文本 1", "查询文本 2"]
}
```

- `embedding_type`：`"query"` 或 `"doc"`。
- `texts`：字符串数组。

**响应：**

```json
{
  "dense_embeddings": [[...], [...]],
  "sparse_embeddings": ...
}
```

### 3.2 重排序（MiniCPM）

**路径：** `POST /rerank`

**请求：**

```json
{
  "query": "用户问题",
  "passages": ["段落 1", "段落 2", "段落 3"]
}
```

**响应：** 与 `passages` 顺序一致的相关性分数数组。

```json
[0.95, 0.12, 0.08]
```

### 3.3 重排序（BCE）

**路径：** `POST /rerankbce`

**请求：** 与 `/rerank` 相同（`query`、`passages`）。

**响应：** 分数数组（浮点数），顺序与 `passages` 一致。

```json
[0.82, 0.31]
```

### Embedding 服务错误

- `400`：请求体缺失或非法（如缺少 `input` 或 `embedding_type`/`texts`）。
- `500`：服务端错误；响应体为 `{"error": {"message": "...", "type": "server_error"}}` 或 `{"error": "..."}`。

---

## 4. 运维脚本

### 校验部署

```bash
./validate.sh <MASTER_IP> [SLAVE_IP] [SLAVE_PRESET] [MASTER_PRESET]
```

- 检查 Registry `/health`、Router `/health`、服务发现、模型列表及各模型对话补全。
- 带从节点时：传入 `SLAVE_IP`，可选 `SLAVE_PRESET`（`2static`、`1static1vllm`、`3vllm`、`1paged2vllm`）。
- 3vllm 预设：`./validate.sh <MASTER_IP> <SLAVE_IP> 3vllm 3vllm`。

### 运行压测

对已运行部署进行压测（默认路由 `192.168.163.151:8000`）：

```bash
export QWEN3_32B_DIR=/path/to/Qwen3-32B
./run-benchmark.sh [ROUTER_HOST]
# 或：ROUTER_HOST=10.0.0.1 ROUTER_PORT=8000 ./run-benchmark.sh
```

结果输出到 `results/metax-opt-*.json`。

### 停止全部

```bash
./stop-all.sh
```

停止主、从容器（`infinilm-svc-master-opt`、`infinilm-svc-slave-opt`）。需在能访问两个容器的机器上执行，否则在各主机上分别停止。

---

## 5. 环境与端口汇总

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ROUTER_PORT` | 8000 | 路由 HTTP 端口 |
| `REGISTRY_PORT` | 18000 | 注册中心端口 |
| `EMBEDDING_PORT` | 20002 | 向量服务端口 |
| `CACHE_TYPE_ROUTING_THRESHOLD` | 51200 | 请求体大小（字节），超过则走 static/vLLM |

可在主节点 `.env` 或执行脚本时覆盖（如 `ROUTER_PORT=8000 ./validate.sh <MASTER_IP>`）。

---

## 6. 参考

- [README.md](README.md) — 架构、预设、快速开始、向量服务配置。
- [API_DOCUMENTATION.md](../../../API_DOCUMENTATION.md) — 完整 Router API（对话、补全、流式、错误码、代码示例）。
