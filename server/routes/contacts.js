const express = require('express');
const { User, Contact } = require('../models');
const { authMiddleware } = require('./auth');

const router = express.Router();

// 获取联系人列表
router.get('/', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;

    // 查找所有已接受的联系人
    const contacts = await Contact.find({
      userId,
      status: 'accepted'
    }).populate('contactId', 'username avatar bio publicKey');

    // 格式化返回数据
    const formattedContacts = contacts.map(contact => ({
      id: contact.contactId._id.toString(),
      username: contact.contactId.username,
      avatar: contact.contactId.avatar,
      bio: contact.contactId.bio,
      publicKey: contact.contactId.publicKey,
      addedAt: contact.createdAt
    }));

    res.json({
      success: true,
      data: formattedContacts
    });
  } catch (error) {
    console.error('获取联系人列表错误:', error);
    res.status(500).json({
      success: false,
      message: '获取联系人列表失败',
      error: error.message
    });
  }
});

// 搜索用户（通过用户名或ID）
router.get('/search', authMiddleware, async (req, res) => {
  try {
    const { query } = req.query;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: '搜索关键词不能为空'
      });
    }

    // 搜索用户（排除当前用户）
    const users = await User.find({
      $and: [
        { _id: { $ne: req.userId } },
        {
          $or: [
            { username: { $regex: query, $options: 'i' } },
            { _id: query.match(/^[0-9a-fA-F]{24}$/) ? query : undefined }
          ]
        }
      ]
    }).select('username avatar bio publicKey createdAt');

    // 检查是否已经是联系人
    const contacts = await Contact.find({ userId: req.userId });
    const contactIds = new Set(contacts.map(c => c.contactId.toString()));

    const formattedUsers = users.map(user => ({
      id: user._id.toString(),
      username: user.username,
      avatar: user.avatar,
      bio: user.bio,
      publicKey: user.publicKey,
      isContact: contactIds.has(user._id.toString()),
      createdAt: user.createdAt
    }));

    res.json({
      success: true,
      data: formattedUsers
    });
  } catch (error) {
    console.error('搜索用户错误:', error);
    res.status(500).json({
      success: false,
      message: '搜索用户失败',
      error: error.message
    });
  }
});

// 发送添加联系人请求
router.post('/add', authMiddleware, async (req, res) => {
  try {
    const { contactId, verificationMessage } = req.body;
    const userId = req.userId;

    if (!contactId) {
      return res.status(400).json({
        success: false,
        message: '联系人ID不能为空'
      });
    }

    // 不能添加自己
    if (contactId === userId) {
      return res.status(400).json({
        success: false,
        message: '不能添加自己为联系人'
      });
    }

    // 检查目标用户是否存在
    const targetUser = await User.findById(contactId);
    if (!targetUser) {
      return res.status(404).json({
        success: false,
        message: '用户不存在'
      });
    }

    // 检查是否已经是联系人或已有待处理请求
    const existingContact = await Contact.findOne({
      $or: [
        { userId, contactId },
        { userId: contactId, contactId: userId }
      ]
    });

    if (existingContact) {
      if (existingContact.status === 'accepted') {
        return res.status(409).json({
          success: false,
          message: '已经是联系人'
        });
      }
      if (existingContact.status === 'pending') {
        return res.status(409).json({
          success: false,
          message: '已有待处理的请求'
        });
      }
    }

    // 创建联系人请求
    const contact = new Contact({
      userId,
      contactId,
      status: 'pending',
      verificationMessage: verificationMessage || ''
    });

    await contact.save();

    res.json({
      success: true,
      message: '添加请求已发送',
      data: {
        id: contact._id.toString(),
        contactId: contact.contactId.toString(),
        status: contact.status,
        verificationMessage: contact.verificationMessage,
        requestedAt: contact.requestedAt
      }
    });
  } catch (error) {
    console.error('添加联系人错误:', error);
    res.status(500).json({
      success: false,
      message: '添加联系人失败',
      error: error.message
    });
  }
});

// 获取待处理的联系人请求
router.get('/requests', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;

    // 查找发送给我的待处理请求
    const receivedRequests = await Contact.find({
      contactId: userId,
      status: 'pending'
    }).populate('userId', 'username avatar bio');

    // 查找我发送的待处理请求
    const sentRequests = await Contact.find({
      userId,
      status: 'pending'
    }).populate('contactId', 'username avatar bio');

    res.json({
      success: true,
      data: {
        received: receivedRequests.map(req => ({
          id: req._id.toString(),
          userId: req.userId._id.toString(),
          username: req.userId.username,
          avatar: req.userId.avatar,
          bio: req.userId.bio,
          verificationMessage: req.verificationMessage,
          requestedAt: req.requestedAt
        })),
        sent: sentRequests.map(req => ({
          id: req._id.toString(),
          contactId: req.contactId._id.toString(),
          username: req.contactId.username,
          avatar: req.contactId.avatar,
          bio: req.contactId.bio,
          verificationMessage: req.verificationMessage,
          requestedAt: req.requestedAt
        }))
      }
    });
  } catch (error) {
    console.error('获取联系人请求错误:', error);
    res.status(500).json({
      success: false,
      message: '获取联系人请求失败',
      error: error.message
    });
  }
});

// 接受联系人请求
router.post('/accept', authMiddleware, async (req, res) => {
  try {
    const { requestId } = req.body;
    const userId = req.userId;

    if (!requestId) {
      return res.status(400).json({
        success: false,
        message: '请求ID不能为空'
      });
    }

    // 查找请求
    const contact = await Contact.findOne({
      _id: requestId,
      contactId: userId,
      status: 'pending'
    });

    if (!contact) {
      return res.status(404).json({
        success: false,
        message: '请求不存在或已处理'
      });
    }

    // 更新请求状态
    contact.status = 'accepted';
    contact.respondedAt = new Date();
    await contact.save();

    // 创建反向联系人关系
    const reverseContact = new Contact({
      userId: contact.contactId,
      contactId: contact.userId,
      status: 'accepted',
      respondedAt: new Date()
    });
    await reverseContact.save();

    res.json({
      success: true,
      message: '已接受联系人请求'
    });
  } catch (error) {
    console.error('接受联系人请求错误:', error);
    res.status(500).json({
      success: false,
      message: '接受请求失败',
      error: error.message
    });
  }
});

// 拒绝联系人请求
router.post('/reject', authMiddleware, async (req, res) => {
  try {
    const { requestId } = req.body;
    const userId = req.userId;

    if (!requestId) {
      return res.status(400).json({
        success: false,
        message: '请求ID不能为空'
      });
    }

    // 查找请求
    const contact = await Contact.findOne({
      _id: requestId,
      contactId: userId,
      status: 'pending'
    });

    if (!contact) {
      return res.status(404).json({
        success: false,
        message: '请求不存在或已处理'
      });
    }

    // 更新请求状态
    contact.status = 'rejected';
    contact.respondedAt = new Date();
    await contact.save();

    res.json({
      success: true,
      message: '已拒绝联系人请求'
    });
  } catch (error) {
    console.error('拒绝联系人请求错误:', error);
    res.status(500).json({
      success: false,
      message: '拒绝请求失败',
      error: error.message
    });
  }
});

// 删除联系人
router.delete('/:contactId', authMiddleware, async (req, res) => {
  try {
    const { contactId } = req.params;
    const userId = req.userId;

    // 删除双向联系人关系
    await Contact.deleteMany({
      $or: [
        { userId, contactId },
        { userId: contactId, contactId: userId }
      ]
    });

    res.json({
      success: true,
      message: '联系人已删除'
    });
  } catch (error) {
    console.error('删除联系人错误:', error);
    res.status(500).json({
      success: false,
      message: '删除联系人失败',
      error: error.message
    });
  }
});

module.exports = router;
