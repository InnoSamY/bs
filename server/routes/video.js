const express = require('express');
const { authMiddleware } = require('./auth');
const { User } = require('../models');

const router = express.Router();

const userSockets = require('./video-sockets');

router.post('/invite', authMiddleware, async (req, res) => {
  try {
    const { userId, isOnlyAudio } = req.body;
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
    io.to(calleeSocketId).emit('video', {
      type: 'invite',
      fromUserId: callerId,
      fromUserName: callerInfo?.username || '未知用户',
      isOnlyAudio: isOnlyAudio !== false
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('invite错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

router.post('/accept', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const accepterId = req.user._id.toString();

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
      type: 'accept',
      fromUserId: accepterId
    });

    res.json({ success: true, code: 0 });
  } catch (error) {
    console.error('accept错误:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

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

router.post('/hangup', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    const senderId = req.user._id.toString();

    const targetSocketId = userSockets.get(userId);
    
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

router.get('/public-key/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

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

    if (!user.isActive) {
      return res.status(403).json({
        success: false,
        message: '用户账户已被禁用'
      });
    }

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

module.exports = router;
