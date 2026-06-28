# AudioRelay iOS 客户端开发计划

## 逆向分析结论

### 协议架构
```
iOS Client                          AudioRelay PC Server
    |                                       |
    |--- WebSocket (TCP) ------------------>|  控制通道
    |    - Feature Negotiation              |  (Ktor + OkHttp)
    |    - Config Exchange                  |
    |    - Ping/Pong Keepalive              |
    |    - Start/Stop Commands              |
    |                                       |
    |<== UDP Audio Stream (Port 59100) =====|  数据通道
    |    - Opus Encoded Packets             |
    |    - Packet Retransmission            |
    |    - Network Measurement              |
    +---------------------------------------+
```

### 关键技术栈
- **传输**: WebSocket (控制) + UDP:59100 (音频)
- **序列化**: Protocol Buffers (Lite runtime)
- **音频**: Opus codec
- **PC实现**: Ktor + OkHttp 4.10.0, Kotlin

### 协议消息（已知结构）
| 消息 | 用途 |
|------|------|
| `ServerFeatures` | 服务端特征声明 (压缩/多设备/消息/流数据/配置) |
| `PlayerFeatures` | 客户端特征声明 |
| `ConnectionConfig` | 连接配置 (含特征协商) |
| `ConfigExchangeResult` | 配置交换结果 |
| `CompressionFeature` | 压缩配置 (bitrate) |
| `PingRequest/Response` | 心跳保活 |
| `Stopping` | 停止理由 |
| `NetworkMeasurements` | 网络质量统计 |
| `ExecutionResult` | 包处理结果 |
| `WaitRetransmissionState` | 重传等待状态 |

---

## iOS 开发计划

### 第一阶段：协议逆向验证 (预计 2h)
**目标**: 通过抓包确认 WebSocket 端口和完整消息格式

1. 启动 AudioRelay PC，连接 Android 客户端
2. 用 Wireshark/tcpdump 抓取 WebSocket 握手 + UDP 音频包
3. 提取 protobuf 二进制消息，用 protoc 反序列化验证格式
4. 编写 `.proto` schema 文件

### 第二阶段：iOS 项目搭建 (预计 1h)
**目标**: SwiftUI 项目骨架 + 依赖集成

**技术栈**: SwiftUI + Swift 5.9+, iOS 17+, Xcode 16+

```
AudioRelayClient/
├── AudioRelayClient.xcodeproj
├── Sources/
│   ├── App/
│   │   └── AudioRelayClientApp.swift       # 入口
│   ├── UI/
│   │   ├── ContentView.swift               # 主界面
│   │   ├── ServerDiscoveryView.swift       # 服务器发现
│   │   ├── ConnectionView.swift            # 连接状态
│   │   └── SettingsView.swift              # 设置
│   ├── Network/
│   │   ├── WebSocketClient.swift           # WebSocket 控制通道
│   │   ├── UDPAudioReceiver.swift          # UDP 音频接收
│   │   └── Protocol/
│   │       ├── messages.proto              # Protobuf 定义
│   │       └── Messages.swift              # 生成的消息类
│   ├── Audio/
│   │   ├── OpusDecoder.swift               # Opus 解码
│   │   └── AudioPlayer.swift               # 音频播放 (AVAudioEngine)
│   └── Model/
│       ├── ServerInfo.swift                # 服务器信息模型
│       └── ConnectionState.swift           # 连接状态机
└── Package.swift                           # SPM 依赖
```

**SPM 依赖**:
- `SwiftProtobuf` - Protocol Buffers
- `libopus` (via XCFramework 或手动编译)
- `Network` framework (系统自带)

### 第三阶段：核心功能实现 (预计 4-6h)

#### 3.1 Protobuf 消息定义
从逆向数据重建最小 `.proto` schema：
```protobuf
syntax = "proto3";
message ConnectionConfig {
    string client_config = 1;
    repeated string features = 2;
}
message ServerFeatures {
    CompressionFeature compression_feature = 1;
    bool multi_payload_feature = 2;
    // ...
}
// ... 更多消息
```

#### 3.2 WebSocket 控制通道
- 连接到 PC 服务器 (IP:Port)
- 发送 ClientFeatures 进行握手
- 接收 ServerFeatures 和配置
- Ping/Pong 保活
- 启动/停止音频流命令

#### 3.3 UDP 音频接收
- 绑定本地端口接收 UDP 音频包
- 包序号检查和重传请求
- 缓冲区管理 (jitter buffer)
- 包丢失统计

#### 3.4 Opus 解码 + 音频播放
- 编译 libopus 为 iOS 静态库
- Opus 解码器 (48kHz/44.1kHz, 立体声)
- AVAudioEngine 实时音频播放
- 延迟控制 (buffer 可调)

### 第四阶段：UI 实现 (预计 2-3h)
- 局域网服务器扫描 (Bonjour/mDNS / 手动IP)
- 连接状态指示 (断线重连)
- 音量控制
- 延迟/缓冲设置
- 暗色模式支持

### 第五阶段：测试调试 (预计 2h)
- 与 AudioRelay PC v0.27.5 联调
- 协议兼容性验证
- 音频质量测试
- 稳定性测试

---

## 最快跑通路径（MVP）

1. **跳过完整 proto 逆向** — 先用硬编码的二进制消息握手
2. **只实现 WebSocket 控制 + UDP 音频接收 + Opus 解码播放**
3. **手动输入 IP 连接**（不做自动发现）
4. **最简 UI**: IP 输入框 + 连接按钮 + 音量滑块

**目标**: 2-3 小时听到声音
