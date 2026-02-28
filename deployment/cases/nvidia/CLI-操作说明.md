# InfiniLM-SVC NVIDIA 部署 - 命令行操作说明

本文档说明在无外网环境下使用镜像 tar 包和模型进行离线部署的 CLI 操作。

---

## 一、离线部署包准备

在有网络环境中准备以下文件：

### 1.1 导出 Docker 镜像

```bash
# 拉取或构建镜像后，导出为 tar 包
docker save infinilm-svc:nvidia -o infinilm-svc-nvidia.tar
```

### 1.2 准备模型目录

模型需为 **9g_8b_thinking_llama**（Llama 格式）或 **9g_8b_thinking**（FM9G 格式，启动时会自动转换）。

目录应包含例如：`config.json`、`model-*.safetensors`、`tokenizer.json` 等文件。

---

## 二、离线环境部署步骤

### 2.1 拷贝文件到离线机

将以下内容拷贝到目标机器：

- `infinilm-svc-nvidia.tar`（镜像包）
- `9g_8b_thinking_llama/`（或 `9g_8b_thinking/`）模型目录
- 部署脚本目录：`deployment/cases/nvidia/`（含 `deploy-offline.sh`、`start-master.sh`、`config/`、`9g_converter.py`、`validate.sh` 等）

### 2.2 一键离线部署

```bash
cd deployment/cases/nvidia

./deploy-offline.sh \
  --image-tar /path/to/infinilm-svc-nvidia.tar \
  --model-dir /path/to/9g_8b_thinking_llama
```

或使用环境变量：

```bash
export IMAGE_TAR=/path/to/infinilm-svc-nvidia.tar
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./deploy-offline.sh
```

### 2.3 指定端口（避免冲突）

```bash
./deploy-offline.sh \
  --image-tar infinilm-svc-nvidia.tar \
  --model-dir /data/models/9g_8b_thinking_llama \
  --ports 18002:8002
```

或：`REGISTRY_PORT=18002 ROUTER_PORT=8002 ./deploy-offline.sh ...`

---

## 三、常用 CLI 命令

### 3.1 启动服务（在线 / 已有镜像）

```bash
cd deployment/cases/nvidia
export MODEL1_DIR=/path/to/9g_8b_thinking_llama
./start-master.sh
```

### 3.2 停止服务

```bash
./stop-master.sh
```

或仅用 docker：`docker stop infinilm-svc-master`。加 `-r` 可一并删除容器：`./stop-master.sh -r`。

### 3.3 查看日志

```bash
docker logs -f infinilm-svc-master
```

### 3.4 验证服务

```bash
./validate.sh
```

或指定端口：

```bash
REGISTRY_PORT=18002 ROUTER_PORT=8002 ./validate.sh
```

### 3.5 健康检查（手动）

```bash
# 注册中心
curl http://localhost:18000/health

# 路由
curl http://localhost:8000/health

# 推理服务
curl http://localhost:8101/health
```

### 3.6 聊天补全测试

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"9g_8b_thinking","messages":[{"role":"user","content":"你好"}],"max_tokens":20}'
```

---

## 四、环境变量说明

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `IMAGE_NAME` | Docker 镜像名 | `infinilm-svc:nvidia` |
| `CONTAINER_NAME` | 容器名 | `infinilm-svc-master` |
| `MODEL1_DIR` | 模型目录路径 | 必填 |
| `REGISTRY_PORT` | 注册中心端口 | `18000` |
| `ROUTER_PORT` | 路由端口 | `8000` |

---

## 五、端口说明

| 端口 | 服务 |
|------|------|
| 18000 | 注册中心（Registry） |
| 8000 | 路由（Router），对外提供推理 API |
| 8100 | InfiniLM 推理服务 |
| 8101 | Babysitter 健康检查 |

---

## 六、故障排查

### 6.1 镜像加载失败

```bash
# 检查 tar 包
ls -lh infinilm-svc-nvidia.tar

# 手动加载
docker load -i infinilm-svc-nvidia.tar

# 确认镜像
docker images | grep infinilm-svc
```

### 6.2 模型路径错误

确认 `MODEL1_DIR` 指向的目录存在且包含 `config.json`、`model-*.safetensors` 等文件。

### 6.3 端口被占用

更换端口启动：

```bash
REGISTRY_PORT=18002 ROUTER_PORT=8002 ./start-master.sh
```

### 6.4 GPU 不可用

安装 [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)，并确认 `nvidia-smi` 正常。

### 6.5 使用 logs.sh 查看与导出日志

`scripts/logs.sh` 可按模块查看或导出容器内日志，便于排查问题。

**前置条件**：nvidia 部署使用容器名 `infinilm-svc-master`，需先设置环境变量：

```bash
export CONTAINER_NAME=infinilm-svc-master
```

**查看日志（display）**：

```bash
cd scripts

# 查看容器 stdout/stderr
./logs.sh display docker -f

# 查看 Registry 日志
./logs.sh display registry -f

# 查看 Router 日志
./logs.sh display router -f

# 查看 9g_8b_thinking 模型 babysitter 日志
./logs.sh display babysitter_master-9g_8b_thinking -f
```

**导出日志到宿主机（offload）**：

```bash
# 导出指定模块日志到目录
./logs.sh offload babysitter_master-9g_8b_thinking /tmp/9g-logs

# 导出全部日志（输出到 logs-all-<timestamp>）
./logs.sh offload
```

**PREFIX 说明**：`docker`（容器 stdout）、`registry`、`router`、`babysitter_master-9g_8b_thinking` 等。
