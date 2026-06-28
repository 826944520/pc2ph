# AudioRelay Client - Flutter 跨平台版

将 PC 端 AudioRelay 的音频流式传输到手机（iOS + Android）。

**Windows 开发 → 云端构建 iOS → 同时支持 Android 真机调试！**

## 技术栈

| 层 | 技术 |
|---|------|
| 框架 | Flutter 3.22+ / Dart 3.2+ |
| 状态管理 | Provider + ChangeNotifier |
| 网络控制 | `dart:io` WebSocket + 自实现帧协议 |
| 音频数据 | `dart:io` RawDatagramSocket (UDP) |
| 序列化 | 自实现 Protobuf Wire Format 解析器 |
| 音频解码 | `dart:ffi` → libopus C 库 |
| 音频播放 | PCM → AudioTrack (Android) / AVAudioEngine (iOS) |
| 服务发现 | mDNS + UDP 广播 |
| UI | Material 3 (暗色主题) |

## Windows 开发环境配置

### 1. 安装 Flutter

```powershell
# 下载 Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable
# 添加到 PATH

flutter doctor
```

### 2. 安装 Android Studio

- 下载 [Android Studio](https://developer.android.com/studio)
- 安装 Android SDK + NDK
- 创建 Android 模拟器 (或使用 USB 真机)

### 3. 运行项目

```bash
cd audiorelay_flutter
flutter pub get
flutter run                    # 连接 Android 设备/模拟器
```

## iOS 构建（无 Mac 方案）

### 方案 A: GitHub Actions (免费)

1. Fork 仓库到 GitHub
2. Push 代码 → 自动触发构建 (见 `.github/workflows/build.yml`)
3. 下载 Artifact 中的 IPA 文件
4. 使用 [AltStore](https://altstore.io/) 侧载安装到 iPhone

### 方案 B: Codemagic (免费 500 分钟/月)

1. 注册 [codemagic.io](https://codemagic.io)
2. 连接 GitHub 仓库
3. 配置 iOS 构建
4. 自动签名 + 发布到 TestFlight

### 方案 C: 手动侧载

```bash
# 在 CI 构建后获取 unsigned IPA
# 使用个人 Apple ID 签名 (7 天有效期)
# 工具: AltStore / Sideloadly / ios-app-signer
```

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── models/
│   ├── server_info.dart          # 服务器信息 + 音频格式 + 统计
│   └── connection_state.dart     # 状态机枚举
├── network/
│   ├── websocket_client.dart     # WebSocket 控制通道
│   ├── udp_audio_receiver.dart   # UDP 音频接收
│   └── protocol/
│       └── messages.dart         # Protobuf 编解码
├── audio/
│   ├── opus_decoder.dart         # libopus FFI 绑定
│   └── audio_player.dart         # PCM 播放器
├── discovery/
│   └── server_discoverer.dart    # 局域网服务发现
├── state/
│   └── audio_manager.dart        # 核心状态管理
└── ui/
    ├── home_page.dart            # 主页面
    ├── server_list_view.dart     # 服务器列表
    ├── streaming_view.dart       # 播放界面
    └── manual_connect_dialog.dart # 手动连接
```

## 协议兼容性

基于 AudioRelay v0.27.5 逆向：
- 控制: WebSocket TCP + 4字节长度前缀 + Protobuf
- 音频: UDP 59100 + Opus 编码
- 发现: mDNS `_audiorelay._tcp` + UDP 广播

详见 [协议文档](lib/network/protocol/messages.dart)
