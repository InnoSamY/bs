const mongoose = require('mongoose');

const contactSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: [true, '用户ID不能为空']
  },
  contactId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: [true, '联系人ID不能为空']
  },
  status: {
    type: String,
    enum: ['pending', 'accepted', 'rejected'],
    default: 'pending'
  },
  verificationMessage: {
    type: String,
    default: '',
    maxlength: [200, '验证信息最多200个字符']
  },
  requestedAt: {
    type: Date,
    default: Date.now
  },
  respondedAt: {
    type: Date,
    default: null
  }
}, {
  timestamps: true,
  toJSON: {
    transform: function(doc, ret) {
      delete ret.__v;
      return ret;
    }
  }
});

// 复合索引：确保用户和联系人的组合唯一
contactSchema.index({ userId: 1, contactId: 1 }, { unique: true });
contactSchema.index({ userId: 1, status: 1 });
contactSchema.index({ contactId: 1, status: 1 });

module.exports = mongoose.model('Contact', contactSchema);
