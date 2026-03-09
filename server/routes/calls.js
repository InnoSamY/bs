const express = require('express');
const { authMiddleware } = require('./auth');
const { User } = require('../models');

const router = express.Router();

// 获取用户公钥（用于加密通话）
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

// 检查用户是否在线（通过WebSocket）
// 这个端点用于检查用户是否可以接听通话
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

    // 注意：实际在线状态需要通过WebSocket判断
    // 这里只返回用户基本信息
    res.json({
      success: true,
      data: {
        userId: user._id.toString(),
        username: user.username,
        isActive: user.isActive,
        lastLoginAt: user.lastLoginAt,
        // 实际在线状态需要WebSocket确认
        online: null
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
