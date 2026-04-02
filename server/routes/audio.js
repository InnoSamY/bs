/**
 * 音频通话路由模块
 * 
 * 这个文件包含所有音频通话相关的 API 路由。
 * 
 * 主要功能：
 * 1. 安全邀请 V2（secure-invite-v2）
 * 2. 安全应答 V2（answer-v2）
 * 3. ICE 候选者交换（candidate）
 * 4. 挂断通话（hangup）
 * 5. 拒绝通话（reject）
 * 6. 用户状态和公钥查询
 * 
 * 信令流程：
 * 1. 呼叫方 -> 发起安全邀请 V2 -> 服务器 -> 被叫方
 * 2. 被叫方 -> 发送安全应答 V2 -> 服务器 -> 呼叫方
 * 3. 双方 -> 交换 ICE 候选者 (candidate)
 * 4. 任意一方 -> 挂断/拒绝 -> 服务器 -> 另一方
 * 
 * 认证要求：
 * - 所有路由需要 JWT 认证
 * - 使用 authMiddleware 中间件进行验证
 * 
 * WebSocket 事件：
 * - audio: 音频通话相关事件
 * - 类型：invite, answer, candidate, hangup, reject
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
const userSockets = require('./audio-sockets');



/**
 * 发送 WebRTC Answer V2（安全版本）
 * 
 * 路由：POST /api/audio/answer-v2
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 转发 WebRTC answer 到对方
 * 2. 包含数字签名信息
 * 3. 完成媒体协商
 * 
 * 请求体：
 * - userId: 目标用户ID
 * - answer: WebRTC Answer 对象
 * - signature: 数字签名
 * - sigPublicKey: 签名公钥
 * - timestamp: 时间戳
 * 
 * WebSocket 事件：
 * - type: 'answer'
 * - fromUserId: 发送方ID
 * - answer: Answer 对象
 * - signature: 数字签名
 * - sigPublicKey: 签名公钥
 * - timestamp: 时间戳
 */
router.post('/answer-v2', authMiddleware, async (req, res) => {
  try {
    const { userId, answer, signature, sigPublicKey, timestamp } = req.body;
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
    io.to(targetSocketId).emit('audio', {
      type: 'answer',
      fromUserId: senderId,
      answer: answer,
      signature: signature,
      sigPublicKey: sigPublicKey,
      timestamp: timestamp
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('answer-v2错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 发送 ICE 候选者
 * 
 * 路由：POST /api/audio/candidate
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
    io.to(targetSocketId).emit('audio', {
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
 * 路由：POST /api/audio/hangup
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
      io.to(targetSocketId).emit('audio', {
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
 * 拒绝通话
 * 
 * 路由：POST /api/audio/reject
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 通知对方通话被拒绝
 * 2. 清理通话相关状态
 * 
 * 请求体：
 * - userId: 对方用户ID
 * 
 * WebSocket 事件：
 * - type: 'reject'
 * - fromUserId: 拒绝方ID
 */
router.post('/reject', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
    console.log(`[REJECT] ${senderId} 拒绝通话，目标: ${userId}, socket: ${targetSocketId}`);
    
    // 如果对方在线，发送拒绝事件
    if (targetSocketId) {
      const io = req.app.get('io');
      io.to(targetSocketId).emit('audio', {
        type: 'reject',
        fromUserId: senderId
      });
      console.log(`[REJECT] 已发送 reject 事件到 ${targetSocketId}`);
    } else {
      console.log(`[REJECT] 目标用户不在线: ${userId}`);
    }

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('reject错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * 获取用户公钥
 * 
 * 路由：GET /api/audio/public-key/:userId
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
        userId: user._id,
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
 * 更新用户公钥
 * 
 * 路由：POST /api/audio/update-keys
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 更新用户的加密公钥
 * 2. 用于密钥轮换
 * 
 * 请求体：
 * - publicKey: 新的公钥
 * 
 * 响应：
 * - success: true/false
 */
router.post('/update-keys', authMiddleware, async (req, res) => {
  try {
    const { publicKey } = req.body;
    const userId = req.user._id.toString();

    // 更新用户公钥
    await User.findByIdAndUpdate(userId, { publicKey });

    res.json({
      success: true,
      message: '公钥更新成功'
    });
  } catch (error) {
    console.error('更新公钥错误:', error);
    res.status(500).json({
      success: false,
      message: '更新公钥失败',
      error: error.message
    });
  }
});

/**
 * 获取用户状态
 * 
 * 路由：GET /api/audio/status/:userId
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
 * - data: { userId, username, isOnline }
 */
router.get('/status/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    // 查找用户
    const user = await User.findById(userId).select('username');
    
    if (!user) {
      return res.status(404).json({
        success: false,
        message: '用户不存在'
      });
    }

    // 检查是否在线
    const isOnline = userSockets.has(userId);

    res.json({
      success: true,
      data: {
        userId: user._id,
        username: user.username,
        isOnline: isOnline
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
 * 发起安全音频通话邀请 V2（带后量子加密和 WebRTC Offer）
 * 
 * 路由：POST /api/audio/secure-invite-v2
 * 认证：需要（JWT）
 * 
 * 功能：
 * 1. 发起带数字签名的安全通话邀请
 * 2. 包含 ML-KEM 密文
 * 3. 包含 WebRTC Offer
 * 4. 用于后量子安全通话
 * 
 * 请求体：
 * - userId: 被叫方用户ID
 * - isOnlyAudio: 是否仅音频
 * - kemCiphertext: ML-KEM 密文
 * - signature: 通话请求签名
 * - sigPublicKey: ML-DSA 签名公钥
 * - offer: WebRTC Offer 对象
 * - timestamp: 时间戳
 * 
 * 安全特性：
 * - 签名验证：防止通话请求被篡改
 * - KEM 密钥封装：建立安全会话密钥
 * - Offer 包含：开始 WebRTC 协商
 */
router.post('/secure-invite-v2', authMiddleware, async (req, res) => {
  try {
    const { userId, isOnlyAudio, kemCiphertext, signature, sigPublicKey, offer, timestamp } = req.body;
    const callerId = req.user._id.toString();
    const callerInfo = await User.findById(callerId).select('username');

    const calleeSocketId = userSockets.get(userId);
    
    if (!calleeSocketId) {
      return res.json({
        success: false,
        code: -1,
        message: '用户不在线'
      });
    }

    const io = req.app.get('io');
    // 发送带完整加密信息的邀请
    io.to(calleeSocketId).emit('audio', {
      type: 'invite',
      fromUserId: callerId,
      fromUserName: callerInfo?.username || '未知用户',
      isOnlyAudio: isOnlyAudio !== false,
      kemCiphertext: kemCiphertext,    // ML-KEM 密文
      signature: signature,             // 通话请求签名
      sigPublicKey: sigPublicKey,       // ML-DSA 公钥
      offer: offer,                     // WebRTC Offer
      timestamp: timestamp              // 时间戳
    });

    console.log(`安全通话邀请V2: ${callerId} -> ${userId}`);

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('secure-invite-v2错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});



// 导出路由模块
module.exports = router;
