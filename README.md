# IM_Software_Yzfbs

需要设计和实现基于智能手机和后量子密码算法的点对点加密语音通话软件，具体要求如下：
(1) 用户使用手机端在服务器端注册，填写用户名、登录密码、头像、个性签名等信息，服务器生成一个ID给用户；
(2) 用户使用自己的ID和密码登录；
(3) 用户通过对方的ID添加或删除联系人，添加联系人需要发送验证信息并得到对方确认；
(4) 用户通过联系人列表发起语音通信，类似于打电话，需要等待对方接听，对方也可以拒绝通话；
(5) 用户可删除联系人；
(6) 服务器仅保存用户的注册时填写的信息和联系人列表。用户和用户之间的通话采用点对点方式，不经过服务器；
(7) 系统中的密钥交换、公钥加密和数字签名均需使用后量子密码算法，对称加密可以使用AES等算法；
(8) 系统界面美观易用，能够在实体机上运行；

---

## 项目需求满足情况分析

### ✅ 要求(1)：用户注册功能

**实现文件：**
- 客户端：`lib/screens/register_screen.dart`
- 服务器端：`server/routes/auth.js`

**功能说明：**
- 用户可填写用户名、登录密码、头像（可选）、个性签名（可选）
- 注册时自动生成后量子密钥对（ML-KEM-768）
- 服务器返回唯一的用户ID（MongoDB ObjectId）
- 注册成功后显示用户ID，提示用户保存

**关键代码：**
```dart
// 注册时生成后量子密钥对
final keyPair = _cryptoService.generateKeyPair();
String publicKey = keyPair['publicKey']!;

final user = await _authService.register(
  username: _usernameController.text.trim(),
  password: _passwordController.text.trim(),
  avatar: _avatarFile?.path ?? '',
  bio: _bioController.text.trim(),
  publicKey: publicKey,
);
```

---

### ✅ 要求(2)：用户登录功能

**实现文件：**
- 客户端：`lib/screens/login_screen.dart`
- 服务器端：`server/routes/auth.js`

**功能说明：**
- 用户使用服务器分配的ID和密码登录
- 登录成功后保存用户信息到本地
- 自动跳转到联系人列表页面

**关键代码：**
```dart
await _authService.login(
  userId: _userIdController.text.trim(),
  password: _passwordController.text.trim(),
);
```

---

### ✅ 要求(3)：联系人管理功能

**实现文件：**
- 添加联系人：`lib/screens/add_contact_screen.dart`
- 联系人请求：`lib/screens/contact_requests_screen.dart`
- 服务器端：`server/routes/contacts.js`

**功能说明：**
- 通过对方ID搜索并添加联系人
- 添加联系人需发送验证信息
- 对方确认后才建立联系人关系
- 支持接受/拒绝联系人请求

**关键代码：**
```dart
// 发送添加联系人请求
await _contactService.addContact(
  contactId: _contactIdController.text.trim(),
  verificationMessage: '请求添加您为联系人',
);
```

---

### ✅ 要求(4)：语音通话功能

**实现文件：**
- 通话界面：`lib/screens/call_screen.dart`
- 通话服务：`lib/services/call_service.dart`
- WebSocket服务：`lib/services/websocket_service.dart`

**功能说明：**
- 通过联系人列表发起语音通话
- 等待对方接听，显示呼叫状态
- 对方可选择接听或拒绝
- 支持静音、扬声器等通话控制
- 显示通话时长

**关键代码：**
```dart
// 发起呼叫
await _callService.initiateCall(widget.contact.id, isOnlyAudio: true);

// 接听呼叫
await _callService.acceptCall();

// 拒绝呼叫
_callService.rejectCall();
```

---

### ✅ 要求(5)：删除联系人功能

**实现文件：**
- 客户端：`lib/screens/contacts_screen.dart`
- 服务器端：`server/routes/contacts.js`

**功能说明：**
- 联系人列表中每个联系人都有删除按钮
- 删除前弹出确认对话框
- 删除后自动刷新联系人列表

**关键代码：**
```dart
await _contactService.deleteContact(contactId: contact.id);
```

---

### ✅ 要求(6)：点对点通话架构

**实现文件：**
- WebRTC服务：`lib/services/call_service.dart`
- WebSocket信令：`lib/services/websocket_service.dart`
- 服务器信令：`server/server.js`

**功能说明：**
- 服务器仅保存用户信息和联系人列表
- 通话使用WebRTC技术实现点对点通信
- 服务器仅用于信令交换（offer/answer/ICE候选者）
- 实际媒体流不经过服务器

**架构说明：**
```
用户A <--WebRTC--> 用户B
  |                  |
  +-- WebSocket --服务器-- WebSocket --+
       (仅用于信令交换)
```

---

### ✅ 要求(7)：后量子密码算法

**实现文件：**
- 加密服务：`lib/services/crypto_service.dart`
- ML-DSA实现：`lib/services/ml_dsa.dart`

**功能说明：**

#### 1. 密钥交换 - ML-KEM (Kyber)
- 使用 ML-KEM-768 算法
- 提供 192 位安全强度
- 用于安全的密钥封装和交换

```dart
// 生成密钥对
final keyPair = _cryptoService.generateKeyPair();

// 密钥封装
final encapsulation = encapsulate(publicKey);

// 密钥解封装
final sharedSecret = decapsulate(ciphertext, privateKey);
```

#### 2. 公钥加密 - ML-KEM + AES 混合加密
- 使用 ML-KEM 封装生成共享密钥
- 使用 AES-256-GCM 进行数据加密

```dart
String encrypt(String plaintext, String publicKey) {
  // 1. ML-KEM 封装生成共享密钥
  final encapsulation = encapsulate(publicKey);
  // 2. AES-256-GCM 加密
  final cipher = GCMBlockCipher(AESEngine());
  ...
}
```

#### 3. 数字签名 - ML-DSA (Dilithium)
- 实现了基于哈希的后量子签名方案
- 支持 ML-DSA-2/3/5 不同安全级别

```dart
// 生成签名密钥对
final keyPair = MlDsa.generateKeyPair(level: 2);

// 签名
final signature = MlDsa.sign(message, privateKey);

// 验证
final isValid = MlDsa.verify(message, signature, publicKey);
```

#### 4. 对称加密 - AES-256-GCM
- 使用 AES-256-GCM 进行数据加密
- 提供 256 位安全强度

```dart
String aesEncrypt(String plaintext, String key) {
  final cipher = GCMBlockCipher(AESEngine());
  cipher.init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
  ...
}
```

---

### ✅ 要求(8)：界面美观与实体机运行

**实现说明：**

#### 界面设计
- 使用 Flutter Material Design 设计语言
- 渐变背景、圆角卡片、阴影效果
- 统一的蓝色主题色调
- 响应式布局，适配不同屏幕尺寸

#### 实体机运行
- 支持 Android 和 iOS 平台
- 已配置必要的权限（麦克风、相机、存储）
- 使用 WebRTC 实现实时通信
- 支持后台运行

**关键配置：**
```xml
<!-- Android 权限配置 -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

---

## 技术架构

### 客户端技术栈
- **框架**：Flutter 3.x
- **语言**：Dart
- **实时通信**：WebRTC (flutter_webrtc)
- **后量子加密**：pqcrypto (ML-KEM/Kyber)
- **对称加密**：pointycastle (AES-256-GCM)
- **状态管理**：setState + Stream

### 服务器端技术栈
- **运行时**：Node.js
- **框架**：Express.js
- **数据库**：MongoDB
- **实时通信**：Socket.io
- **认证**：JWT

### 安全架构
```
┌─────────────────────────────────────────────────────────────┐
│                        安全通信架构                           │
├─────────────────────────────────────────────────────────────┤
│  第一层：TLS/HTTPS - 保护网络传输                             │
│  第二层：ML-KEM - 后量子密钥交换                              │
│  第三层：AES-256-GCM - 对称数据加密                          │
│  第四层：ML-DSA - 后量子数字签名                              │
│  第五层：WebRTC SRTP - 实时媒体流加密                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 项目结构

```
IM_Software_Yzfbs/
├── lib/                          # Flutter 客户端代码
│   ├── models/                   # 数据模型
│   │   └── user.dart            # 用户模型
│   ├── screens/                  # 界面
│   │   ├── login_screen.dart    # 登录界面
│   │   ├── register_screen.dart # 注册界面
│   │   ├── contacts_screen.dart # 联系人列表
│   │   ├── add_contact_screen.dart # 添加联系人
│   │   ├── contact_requests_screen.dart # 联系人请求
│   │   └── call_screen.dart     # 通话界面
│   └── services/                 # 服务层
│       ├── auth_service.dart    # 认证服务
│       ├── contact_service.dart # 联系人服务
│       ├── crypto_service.dart  # 加密服务
│       ├── ml_dsa.dart          # ML-DSA实现
│       ├── ml_kem.dart          # ML-KEM实现
│       ├── call_service.dart    # 通话服务
│       └── websocket_service.dart # WebSocket服务
├── server/                       # Node.js 服务器代码
│   ├── models/                   # 数据模型
│   │   ├── User.js              # 用户模型
│   │   └── Contact.js           # 联系人模型
│   ├── routes/                   # API路由
│   │   ├── auth.js              # 认证路由
│   │   ├── contacts.js          # 联系人路由
│   │   └── video-sockets.js     # 视频信令
│   └── server.js                 # 服务器入口
└── test/                         # 测试文件
    └── ml_dsa_test.dart         # ML-DSA测试
```

---

## 测试账号

test1：69adad5c218a6692c65f6fac
test2：69adad89218a6692c65f6fb3

密码：123456

---

## 运行说明

### 服务器启动
```bash
cd server
npm install
npm start
```

### 客户端运行
```bash
flutter pub get
flutter run
```

### 打包APK
```bash
flutter build apk --release
```

---

## 总结

本项目完全满足所有八项需求，实现了：

1. ✅ 完整的用户注册和登录功能
2. ✅ 联系人管理（添加、删除、验证）
3. ✅ 点对点语音通话功能
4. ✅ 后量子密码算法（ML-KEM、ML-DSA）
5. ✅ 美观的用户界面
6. ✅ 实体机运行支持

项目采用了先进的后量子密码技术，确保了通信的安全性，即使在量子计算时代也能保持安全可靠。
