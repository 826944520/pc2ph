# AudioRelay iOS Client

将 PC 端 AudioRelay 的音频流式传输到 iOS 设备的客户端应用。

## 协议

AudioRelay v0.27.5 协议（逆向工程）：

```
控制通道: WebSocket → PC Server (TCP ~59200)
音频通道: UDP 59100 ← Opus 编码音频包
序列化:   Protocol Buffers (Lite)
```

详细协议文档见 `Sources/Network/Protocol/audiorelay.proto`

## 环境要求

- macOS 14+ (Sonoma)
- Xcode 16+
- iOS 17+ 设备或模拟器
- Swift 5.9+

## 构建步骤

### 1. 安装 libopus

```bash
# Option A: Via Homebrew
brew install opus

# Option B: Build from source
git clone https://github.com/xiph/opus.git
cd opus
./configure --host=arm-apple-darwin --prefix=/tmp/opus-ios
make && make install
```

### 2. 创建 XCFramework (如果手动编译)

```bash
# Build for device
./configure --host=arm-apple-darwin \
    CC="$(xcrun --sdk iphoneos --find clang)" \
    CFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -mios-version-min=17.0"

# Build for simulator
./configure --host=arm-apple-darwin \
    CC="$(xcrun --sdk iphonesimulator --find clang)" \
    CFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -mios-version-min=17.0"

# Create XCFramework
xcodebuild -create-xcframework \
    -library build-device/.libs/libopus.a \
    -library build-sim/.libs/libopus.a \
    -output opus.xcframework
```

### 3. 打开项目

```bash
# 使用 Swift Package Manager
swift package resolve
swift build

# 或直接在 Xcode 中打开:
# File → Open → 选择项目根目录
```

### 4. 配置

在 Xcode 中:
1. 设置 Team (Signing & Capabilities)
2. 添加 libopus XCFramework 到 Link Binary With Libraries
3. 确保 Info.plist 中的 NSLocalNetworkUsageDescription 已配置

### 5. 运行

- **设备**: 选择 iOS 17+ 真机或模拟器
- 确保 iPhone/iPad 与 PC 在同一 WiFi 网络
- PC 端需要运行 AudioRelay (v0.27.5)

## 项目结构

```
Sources/
├── App/
│   ├── AppEntry.swift          # @main 入口
│   └── AudioRelayManager.swift # 核心控制器
├── UI/
│   └── ContentView.swift       # SwiftUI 主界面
├── Network/
│   ├── WebSocketClient.swift   # WebSocket 控制通道
│   ├── UDPAudioReceiver.swift  # UDP 音频接收器
│   └── Protocol/
│       ├── audiorelay.proto    # Protobuf 协议定义
│       └── Messages.swift      # 消息编解码
├── Audio/
│   ├── OpusDecoder.swift       # Opus 解码器
│   └── AudioPlayer.swift       # AVAudioEngine 播放器
├── Discovery/
│   └── ServerDiscoverer.swift  # Bonjour/广播 服务器发现
└── Model/
    ├── ConnectionState.swift   # 连接状态机
    └── ServerInfo.swift        # 数据模型
```

## 功能

- [x] 局域网服务器自动发现 (Bonjour + UDP 广播)
- [x] WebSocket 控制通道 (TLS/明文)
- [x] UDP 音频数据接收 (端口 59100)
- [x] Opus → PCM 解码
- [x] 实时音频播放 (AVAudioEngine)
- [x] 音量控制
- [x] 断线自动重连
- [x] 网络统计
- [x] 暗色模式
- [x] 后台音频播放
- [ ] 多设备同时播放 (Premium 功能)
- [ ] USB 有线连接模式

## 协议逆向说明

AudioRelay 为闭源商业软件。本客户端的协议通过分析 v0.27.5 版本字节码和网络流量逆向得出：

- 控制通道使用 OkHttp 4.10.0 + Ktor WebSocket
- 音频包使用 Opus 编码，通过 UDP 59100 端口传输
- 消息序列化使用 Protobuf Lite 运行时
- 特征协商包括: compression, multi-payload, message, stream-data, retransmission, server-audio-config

## License

本项目仅供学习研究使用。
