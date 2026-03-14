/**
 * 视频通话路由模块
 * 
 * 这个文件包含所有视频通话相关的 API 路由。
 * 
 * 主要功能：
 * 1. 发起呼叫邀请（invite）
 * 2. 接听/拒绝通话（accept）
 * 3. WebRTC 信令交换（offer/answer/candidate）
 * 4. 挂断通话（hangup）
 * 5. 后量子加密相关（secure-invite/key-exchange/update-keys）
 * 6. 用户状态和公钥查询
 * 
 * 信令流程：
 * 1. 呼叫方 -> 发起邀请 -> 服务器 -> 被叫方
 * 2. 被叫方 -> 接听 -> 服务器 -> 呼叫方
 * 3. 双方 -> 交换 SDP (offer/answer)
 * 4. 双方 -> 交换 ICE 候选者 (candidate)
 * 5. 任意一方 -> 挂断 -> 服务器 -> 另一方
 * 
 * 认证要求：
 * - 大部分路由需要 JWT 认证
 * - 使用 authMiddleware 中间件进行验证
 * 
 * WebSocket 事件：
 * - video: 视频通话相关事件
 * - 类型：invite, accept, offer, answer, candidate, hangup, key-exchange
 */

// 导入 Express 框架
const express = require('express');
// 导入认证中间件
const { authMiddleware } = require('./auth');
// 导入用户模型
const { User } = require('../models');

// 创建 Express 路由实例
const router = express.Router();

// 导入用户 socket 映射（用于 WebSocket 路由）
const userSockets = require('./video-sockets');

/**
 * 发起视频通话邀请
 * 
 * 路由：POST /api/video/invite
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 验证用户身份
 * 2. 检查被叫方是否在线
 * 3. 通过 WebSocket 发送邀请到被叫方
 * 
 * 请求体：
 * - userId: 被叫方用户ID
 * - isOnlyAudio: 是否仅音频通话（可选，默认为 true）
 * 
 * 响应：
 * - success: true/false
 * - code: 0 成功，-1 用户不在线
 * - message: 错误信息
 * 
 * WebSocket 事件：
 * - type: 'invite'
 * - fromUserId: 呼叫方ID
 * - fromUserName: 呼叫方用户名
 * - isOnlyAudio: 是否仅音频
 */
router.post('/invite', authMiddleware, async (req, res) => {
  try {
    // 获取请求参数
    const { userId, isOnlyAudio } = req.body;
    // 获取当前用户ID（从 JWT token 中解析）
    const callerId = req.user._id.toString();
    // 获取呼叫方用户名
    const callerInfo = await User.findById(callerId).select('username');

    // 查找被叫方的 socket ID
    const calleeSocketId = userSockets.get(userId);
    
    // 如果被叫方不在线，返回错误
    if (!calleeSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    // 获取 WebSocket IO 实例
    const io = req.app.get('io');
    // 发送邀请事件到被叫方
    io.to(calleeSocketId).emit('video', {
      type: 'invite',
      fromUserId: callerId,
      fromUserName: callerInfo?.username || '未知用户',
      isOnlyAudio: isOnlyAudio !== false
    });

    // 返回成功响应
    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('invite错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 接听视频通话
 * 
 * 路由：POST /api/video/accept
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 验证用户身份
 * 2. 检查呼叫方是否在线
 * 3. 通过 WebSocket 发送接听响应
 * 
 * 请求体：
 * - userId: 呼叫方用户ID
 * 
 * WebSocket 事件：
 * - type: 'accept'
 * - fromUserId: 接听方ID
 */
router.post('/accept', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const accepterId = req.user._id.toString();

    // 查找呼叫方的 socket ID
    const targetSocketId = userSockets.get(userId);
    
    if (!targetSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    // 发送接听事件
    io.to(targetSocketId).emit('video', {
      type: 'accept',
      fromUserId: accepterId
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('accept错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 发送 WebRTC Offer
 * 
 * 路由：POST /api/video/offer
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 转发 WebRTC offer 到对方
 * 2. 用于建立点对点连接
 * 
 * 请求体：
 * - userId: 目标用户ID
 * - desc: SDP 描述（包含媒体信息）
 * 
 * WebSocket 事件：
 * - type: 'offer'
 * - fromUserId: 发送方ID
 * - desc: SDP 描述
 */
router.post('/offer', authMiddleware, async (req, res) => {
  try {
    const { userId, desc } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    if (!targetSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    io.to(targetSocketId).emit('video', {
      type: 'offer',
      fromUserId: senderId,
      desc: desc
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('offer错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 发送 WebRTC Answer
 * 
 * 路由：POST /api/video/answer
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 转发 WebRTC answer 到对方
 * 2. 完成媒体协商
 * 
 * 请求体：
 * - userId: 目标用户ID
 * - desc: SDP 描述
 * 
 * WebSocket 事件：
 * - type: 'answer'
 * - fromUserId: 发送方ID
 * - desc: SDP 描述
 */
router.post('/answer', authMiddleware, async (req, res) => {
  try {
    const { userId, desc } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    if (!targetSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    io.to(targetSocketId).emit('video', {
      type: 'answer',
      fromUserId: senderId,
      desc: desc
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('answer错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 发送 ICE 候选者
 * 
 * 路由：POST /api/video/candidate
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 转发 ICE 候选者到对方
 * 2. 用于 NAT 穿透和建立连接
 * 
 * 请求体：
 * - userId: 目标用户ID
 * - candidate: ICE 候选者信息
 * 
 * WebSocket 事件：
 * - type: 'candidate'
 * - fromUserId: 发送方ID
 * - candidate: ICE 候选者
 */
router.post('/candidate', authMiddleware, async (req, res) => {
  try {
    const { userId, candidate } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    if (!targetSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    io.to(targetSocketId).emit('video', {
      type: 'candidate',
      fromUserId: senderId,
      candidate: candidate
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('candidate错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 挂断通话
 * 
 * 路由：POST /api/video/hangup
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 通知对方挂断通话
 * 2. 清理通话相关状态
 * 
 * 请求体：
 * - userId: 对方用户ID
 * 
 * WebSocket 事件：
 * - type: 'hangup'
 * - fromUserId: 挂断方ID
 */
router.post('/hangup', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    // 如果对方在线，发送挂断事件
    if (targetSocketId) {
      const io = req.app.get('io');
      io.to(targetSocketId).emit('video', {
        type: 'hangup',
        fromUserId: senderId
      });
    }

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('hangup错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 获取用户公钥
 * 
 * 路由：GET /api/video/public-key/:userId
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 获取指定用户的公钥
 * 2. 用于通话前的密钥交换准备
 * 
 * 参数：
 * - userId: 用户ID（URL 参数）
 * 
 * 响应：
 * - success: true/false
 * - data: { userId, username, publicKey }
 */
router.get('/public-key/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    // 查找用户并获取公钥
    const user = await User.findById(userId).select('username publicKey');
    
    if (!user) {
      return res.status(404).json({
        success: false,
        message: '用户不存在'
      });
    }

    res.json({
      success: true,
      data: {
        userId: user._id.toString(),
        username: user.username,
        publicKey: user.publicKey
      }
    });
  } catch (error) {
    console.error('获取公钥错误:', error);
    res.status(500).json({
      success: false,
      message: '获取公钥失败',
      error: error.message
    });
  }
});

/**
 * 获取用户在线状态
 * 
 * 路由：GET /api/video/status/:userId
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 检查用户是否在线
 * 2. 获取用户基本信息
 * 
 * 参数：
 * - userId: 用户ID（URL 参数）
 * 
 * 响应：
 * - success: true/false
 * - data: { userId, username, isActive, lastLoginAt, online }
 */
router.get('/status/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await User.findById(userId).select('username lastLoginAt isActive');
    
    if (!user) {
      return res.status(404).json({
        success: false,
        message: '用户不存在'
      });
    }

    // 检查账户是否被禁用
    if (!user.isActive) {
      return res.status(403).json({
        success: false,
        message: '用户账户已被禁用'
      });
    }

    // 检查用户是否在线（是否有 socket 连接）
    const isOnline = userSockets.has(userId);

    res.json({
      success: true,
      data: {
        userId: user._id.toString(),
        username: user.username,
        isActive: user.isActive,
        lastLoginAt: user.lastLoginAt,
        online: isOnline
      }
    });
  } catch (error) {
    console.error('获取用户状态错误:', error);
    res.status(500).json({
      success: false,
      message: '获取用户状态失败',
      error: error.message
    });
  }
});

/**
 * 发起安全视频通话邀请（带后量子加密）
 * 
 * 路由：POST /api/video/secure-invite
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 发起带数字签名的安全通话邀请
 * 2. 包含 ML-DSA 公钥
 * 3. 用于后量子安全通话
 * 
 * 请求体：
 * - userId: 被叫方用户ID
 * - isOnlyAudio: 是否仅音频
 * - signature: 通话请求签名
 * - publicKey: ML-DSA 公钥
 * - timestamp: 时间戳
 * 
 * 安全特性：
 * - 签名验证：防止通话请求被篡改
 * - 公钥交换：为后续密钥交换做准备
 */
router.post('/secure-invite', authMiddleware, async (req, res) => {
  try {
    const { userId, isOnlyAudio, signature, publicKey, timestamp } = req.body;
    const callerId = req.user._id.toString();
    const callerInfo = await User.findById(callerId).select('username');

    // 将用户的签名公钥存储到数据库
    await User.findByIdAndUpdate(callerId, {
      signaturePublicKey: publicKey
    });

    const calleeSocketId = userSockets.get(userId);
    
    if (!calleeSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    // 发送带加密信息的邀请
    io.to(calleeSocketId).emit('video', {
      type: 'invite',
      fromUserId: callerId,
      fromUserName: callerInfo?.username || '未知用户',
      isOnlyAudio: isOnlyAudio !== false,
      signature: signature,      // 通话请求签名
      publicKey: publicKey,    // ML-DSA 公钥
      timestamp: timestamp      // 时间戳
    });

    console.log(`安全通话邀请: ${callerId} -> ${userId}`);

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('secure-invite错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 后量子密钥交换
 * 
 * 路由：POST /api/video/key-exchange
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 转发 ML-KEM 密钥封装密文
 * 2. 用于建立后量子安全会话
 * 
 * 请求体：
 * - userId: 目标用户ID
 * - keyData: { ciphertext } 包含 ML-KEM 密文
 * 
 * 安全流程：
 * 1. 发送方使用接收方公钥进行 ML-KEM 封装
 * 2. 将密文发送给接收方
 * 3. 接收方使用私钥解封装，获得共享密钥
 */
router.post('/key-exchange', authMiddleware, async (req, res) => {
  try {
    const { userId, keyData } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    if (!targetSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    // 发送密钥交换消息
    io.to(targetSocketId).emit('video', {
      type: 'key-exchange',
      fromUserId: senderId,
      keyData: keyData
    });

    console.log(`密钥交换: ${senderId} -> ${userId}`);

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('key-exchange错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 更新用户后量子公钥
 * 
 * 路由：POST /api/video/update-keys
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 更新用户的 ML-DSA 签名公钥
 * 2. 更新用户的 ML-KEM 加密公钥
 * 
 * 请求体：
 * - signaturePublicKey: ML-DSA 公钥（可选）
 * - encryptionPublicKey: ML-KEM 公钥（可选）
 * 
 * 用途：
 * - 用户登录时更新公钥
 * - 公钥过期或泄露时重新生成
 */
router.post('/update-keys', authMiddleware, async (req, res) => {
  try {
    const { signaturePublicKey, encryptionPublicKey } = req.body;
    const userId = req.user._id.toString();

    // 构建更新对象
    const updateData = {};
    if (signaturePublicKey) updateData.signaturePublicKey = signaturePublicKey;
    if (encryptionPublicKey) updateData.encryptionPublicKey = encryptionPublicKey;

    // 更新用户公钥
    await User.findByIdAndUpdate(userId, updateData);

    console.log(`用户 ${userId} 更新了公钥`);

    res.json({ 
      success: true, 
      message: '公钥更新成功' 
    });
  } catch (error) {
    console.error('update-keys错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 获取用户的后量子公钥
 * 
 * 路由：GET /api/video/user-keys/:userId
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 获取用户的 ML-DSA 签名公钥
 * 2. 获取用户的 ML-KEM 加密公钥
 * 
 * 参数：
 * - userId: 用户ID（URL 参数）
 * 
 * 响应：
 * - success: true/false
 * - data: { userId, username, signaturePublicKey, encryptionPublicKey }
 * 
 * 用途：
 * - 通话前获取对方公钥
 * - 密钥交换前准备
 */
router.get('/user-keys/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await User.findById(userId).select('username signaturePublicKey encryptionPublicKey');
    
    if (!user) {
      return res.status(404).json({
        success: false,
        message: '用户不存在'
      });
    }

    res.json({
      success: true,
      data: {
        userId: user._id.toString(),
        username: user.username,
        signaturePublicKey: user.signaturePublicKey,
        encryptionPublicKey: user.encryptionPublicKey
      }
    });
  } catch (error) {
    console.error('获取用户公钥错误:', error);
    res.status(500).json({
      success: false,
      message: '获取用户公钥失败',
      error: error.message
    });
  }
});

// 导出路由模块
module.exports = router;
