# Python FastAPI 后端教程 — 跨平台 AI 助手的第一步

> 本教程教你如何用 Python + FastAPI 搭建一个局域网后端服务，接收 iPhone 语音识别后的文字，并返回固定回复。这是为后续接入大模型（LLM）打基础的第一步。

---

## 目录

1. [环境准备](#1-环境准备)
2. [项目结构](#2-项目结构)
3. [完整后端代码](#3-完整后端代码)
4. [安装依赖](#4-安装依赖)
5. [查找电脑局域网 IP](#5-查找电脑局域网-ip)
6. [启动服务](#6-启动服务)
7. [用 curl 测试接口](#7-用-curl-测试接口)
8. [iPhone 端配置](#8-iphone-端配置)
9. [同时运行两端](#9-同时运行两端)
10. [常见问题排查](#10-常见问题排查)

---

## 1. 环境准备

你已经通过 conda 创建好了环境：

```bash
conda create -n firstpythonEnv310 python=3.10 -y
conda activate firstpythonEnv310
```

每次使用前都要激活环境：

```bash
conda activate firstpythonEnv310
```

---

## 2. 项目结构

```
python_fastapi/
├── test_fastapi.py      # FastAPI 主程序（本教程的核心文件）
└── BACKEND_TUTORIAL.md  # 本教程
```

---

## 3. 完整后端代码

**文件：** `python_fastapi/test_fastapi.py`

```python
from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# 允许所有来源访问（开发阶段使用，iPhone 和电脑在同一 WiFi 下）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Message(BaseModel):
    text: str

@app.post("/chat")
async def chat(msg: Message):
    print(f"[收到手机消息] {msg.text}")
    # 先固定回复 hello world!，后续可替换为大模型接口
    return {"reply": "hello world!"}

# 运行命令（见下方第6节）
# uvicorn test_fastapi:app --host 0.0.0.0 --port 8000
```

**代码说明：**

| 行 | 说明 |
|----|------|
| `CORSMiddleware` | 跨域中间件，允许 iPhone App 从不同域名/IP 访问后端 |
| `allow_origins=["*"]` | 开发阶段允许所有来源，生产环境应限制为具体域名 |
| `BaseModel` | Pydantic 模型，自动校验请求体 JSON 格式 |
| `@app.post("/chat")` | 定义 POST 接口，路径为 `/chat` |
| `--host 0.0.0.0` | 监听所有网卡，让局域网内其他设备可以访问 |

---

## 4. 安装依赖

在 `firstpythonEnv310` 环境中执行：

```bash
conda activate firstpythonEnv310
pip install fastapi uvicorn
```

验证安装：

```bash
python -c "import fastapi; print(fastapi.__version__)"
```

---

## 5. 查找电脑局域网 IP

### macOS

**方法一：终端命令**

```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

输出示例：

```
inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255
```

你的 IP 就是 `192.168.1.100`。

**方法二：图形界面**

1. 点击屏幕左上角 **苹果图标 → 系统设置**
2. 点击左侧 **Wi-Fi**
3. 点击右侧已连接 Wi-Fi 名称旁的 **详细信息**
4. 查看 **IP 地址** 一栏

### Windows

**方法一：命令提示符**

```cmd
ipconfig
```

在无线局域网适配器下找到：

```
IPv4 地址 . . . . . . . . . . . . : 192.168.1.100
```

**方法二：图形界面**

1. 打开 **设置 → 网络和 Internet → WLAN**
2. 点击已连接的 Wi-Fi 名称
3. 查看 **IPv4 地址**

> **重要：** 手机和电脑必须连接 **同一个 WiFi 路由器**，IP 段通常相同（如都是 `192.168.1.x`）。

---

## 6. 启动服务

确保在 `python_fastapi` 目录下，且环境已激活：

```bash
cd /Users/able/Desktop/app_game/VoiceToTTS_python_reponse/python_fastapi
conda activate firstpythonEnv310
uvicorn test_fastapi:app --host 0.0.0.0 --port 8000
```

成功启动后，终端会显示：

```
INFO:     Started server process [xxxxx]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

**参数说明：**

| 参数 | 含义 |
|------|------|
| `test_fastapi:app` | 文件名 `test_fastapi.py` 中的变量 `app` |
| `--host 0.0.0.0` | 监听所有网络接口，不只本地回环 |
| `--port 8000` | 服务端口，iPhone 将访问此端口 |

---

## 7. 用 curl 测试接口

在另一个终端窗口中测试后端是否正常工作：

```bash
curl -X POST "http://127.0.0.1:8000/chat" \
  -H "Content-Type: application/json" \
  -d '{"text": "你好世界"}'
```

预期返回：

```json
{"reply":"hello world!"}
```

同时运行后端的终端会打印：

```
[收到手机消息] 你好世界
```

---

## 8. iPhone 端配置

在 iPhone App 的底部输入框中，填入你电脑的局域网 IP：

```
http://192.168.1.100:8000
```

请将 `192.168.1.100` 替换为你实际查到的 IP 地址。

**注意：**
- 必须以 `http://` 开头
- 必须以 `:8000` 结尾（与后端启动端口一致）
- 不要包含末尾斜杠 `/`

---

## 9. 同时运行两端

### 电脑端（后端）

```bash
conda activate firstpythonEnv310
cd /Users/able/Desktop/app_game/VoiceToTTS_python_reponse/python_fastapi
uvicorn test_fastapi:app --host 0.0.0.0 --port 8000
```

### 手机端（iOS App）

1. 用 Xcode 将 App 安装到 iPhone
2. 确保 iPhone 和 Mac 连接 **同一 WiFi**
3. 打开 App，在底部输入框填入电脑 IP（如 `http://192.168.1.100:8000`）
4. 点击麦克风按钮，说一句话
5. 观察：
   - 你的语音文字显示在 **右侧**（蓝色气泡）
   - 后端回复 `hello world!` 显示在 **左侧**（灰色气泡）

---

## 10. 常见问题排查

### Q1: iPhone 提示 "Could not connect to the server"

**原因：** iPhone 无法访问电脑 IP。

**排查步骤：**
1. 确认手机和电脑连接 **同一个 WiFi 路由器**
2. 确认后端启动时使用了 `--host 0.0.0.0`
3. 在手机上用 Safari 访问 `http://<电脑IP>:8000/docs`，看能否打开 FastAPI 文档页
4. 检查 Mac 防火墙：
   - **macOS：** 系统设置 → 网络 → 防火墙 → 关闭或允许 Python/uvicorn

### Q2: 后端收到请求，但 iPhone 收不到回复

**原因：** 通常不是后端问题。检查 iPhone 端 `Info.plist` 是否已添加 `NSAppTransportSecurity` 允许 HTTP：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Q3: 后端启动报错 `ModuleNotFoundError: No module named 'fastapi'`

**解决：** 确认在正确的 conda 环境中：

```bash
conda activate firstpythonEnv310
pip install fastapi uvicorn
```

### Q4: 如何确认后端正在监听局域网？

在电脑上，用局域网 IP 自己测试：

```bash
curl -X POST "http://192.168.1.100:8000/chat" \
  -H "Content-Type: application/json" \
  -d '{"text": "test"}'
```

如果能通，说明后端确实在监听局域网。

---

## 下一步

当前后端固定回复 `hello world!`。下一步可以将 `chat()` 函数中的返回逻辑替换为：

- 调用 OpenAI /  Claude / 智谱等大模型 API
- 运行本地大模型（如 llama.cpp、Ollama）
- 接入知识库或搜索引擎

只需修改 `test_fastapi.py` 中的 `chat` 函数，iPhone 端无需任何改动即可升级 AI 能力。

---

*后端搭建完成！如有问题，请检查 IP 地址和防火墙设置。*
