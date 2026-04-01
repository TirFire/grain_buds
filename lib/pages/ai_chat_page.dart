import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart'; // ✅ 修复 getTemporaryDirectory 报错
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ai_service.dart';
import 'edit_page.dart';

// ================= 💡 数据模型 =================
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isSummary;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isSummary = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'isSummary': isSummary,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    text: json['text'],
    isUser: json['isUser'],
    timestamp: DateTime.parse(json['timestamp']),
    isSummary: json['isSummary'] ?? false,
  );
}

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _chatContext = [];
  final Set<String> _selectedIds = {}; // 存放当前被选中的消息 ID
  
  bool _isVoiceMode = false;
  bool _isThinking = false;
  final String _storageKey = 'ai_chat_history_v1';
  
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  // ✅ 移除了未使用的 _lastRecordPath，解决 unused_field 报错

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ================= 🧠 语音识别逻辑 =================

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_ai_voice.m4a';
        
        const config = RecordConfig(); 
        await _audioRecorder.start(config, path: path);
      }
    } catch (e) {
      debugPrint("录音启动失败: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() => _isThinking = true); 
        
        String transcribedText = await AIService.speechToText(path);
        
        // 💡 核心修复：拿到文字后，必须先解除状态锁！
        if (mounted) {
          setState(() => _isThinking = false); 
        }
        
        if (transcribedText.isNotEmpty && !transcribedText.contains("识别失败")) {
          // 解锁后，正常发送给对话大模型，_sendMessage 会自己重新管理思考状态
          _sendMessage(transcribedText); 
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(transcribedText)));
          }
        }
      }
    } catch (e) {
      debugPrint("处理语音失败: $e");
      if (mounted) setState(() => _isThinking = false);
    }
  }

  // ================= 📝 一键转存功能 =================

  void _saveAsEntry(String content, int entryType) {
    if (content.trim().isEmpty) return;

    final Map<String, dynamic> initialData = {
      'content': content,
      'type': entryType, 
      'date': DateTime.now().toString(),
      'mood': 'happy',
      'weather': 'sunny',
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryEditPage(
          existingDiary: initialData, 
          entryType: entryType,
        ),
      ),
    ).then((saved) {
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(entryType == 1 ? '✅ 已存入随手记' : '✅ 已存入日记'), backgroundColor: Colors.teal)
        );
      }
    });
  }

  // ================= 🧠 记忆与基础逻辑 =================

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedList = prefs.getStringList(_storageKey);
    
    if (savedList != null && savedList.isNotEmpty) {
      setState(() {
        _messages.clear();
        for (String jsonStr in savedList) {
          _messages.add(ChatMessage.fromJson(jsonDecode(jsonStr)));
        }
      });
    } else {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: "你好！我是你的时光伴侣 🌟\n你可以把我当成树洞随时倾诉，或者让我帮你回顾过去这几天的点滴。",
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _saveHistory();
    }
    _reconstructContext();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = _messages.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  void _reconstructContext() {
    _chatContext.clear();
    _chatContext.add({"role": "system", "content": "你是用户的专属时光伴侣「小满」。你的语言温暖、治愈、有同理心，像一个懂心理学的老朋友。回复请尽量精简自然，不要像机器。"});
    final recent = _messages.length > 20 ? _messages.sublist(_messages.length - 20) : _messages;
    for (var msg in recent) {
      if (!msg.isSummary) {
         _chatContext.add({"role": msg.isUser ? "user" : "assistant", "content": msg.text});
      }
    }
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty || _isThinking) return;

    setState(() {
      _messages.add(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), text: text, isUser: true, timestamp: DateTime.now()));
      _textController.clear();
      _isThinking = true;
    });
    _scrollToBottom();
    _saveHistory();

    _chatContext.add({"role": "user", "content": text});

    String aiResponse = await AIService.sendMessage(_chatContext);

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), text: aiResponse, isUser: false, timestamp: DateTime.now()));
      });
      _scrollToBottom();
      _saveHistory();
      
      _chatContext.add({"role": "assistant", "content": aiResponse});
      if (_chatContext.length > 21) _chatContext.removeRange(1, 3);
    }
  }

  void _requestWeeklySummary() async {
    if (_isThinking) return;

    setState(() {
      _messages.add(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), text: "帮我总结一下这周的日记 📝", isUser: true, timestamp: DateTime.now()));
      _isThinking = true;
    });
    _scrollToBottom();
    _saveHistory();

    String summary = await AIService.generateWeeklySummary();

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), text: summary, isUser: false, timestamp: DateTime.now(), isSummary: true));
      });
      _scrollToBottom();
      _saveHistory();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ================= ⚙️ 设置与多选清理 =================

  void _showApiSettingsDialog() {
    final keyController = TextEditingController();
    final urlController = TextEditingController();
    final modelController = TextEditingController();

    SharedPreferences.getInstance().then((prefs) {
      keyController.text = prefs.getString('ai_api_key') ?? '';
      urlController.text = prefs.getString('ai_base_url') ?? 'https://api.deepseek.com/chat/completions';
      modelController.text = prefs.getString('ai_model') ?? 'deepseek-chat';
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("AI 时光伴侣配置", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: keyController, decoration: const InputDecoration(labelText: "API Key")),
                TextField(controller: urlController, decoration: const InputDecoration(labelText: "Base URL (接口地址)")),
                TextField(controller: modelController, decoration: const InputDecoration(labelText: "Model (模型名称)")),
                const SizedBox(height: 15),
                const Text("💡 若使用硅基流动，地址填 https://api.siliconflow.cn/v1/chat/completions", style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5))
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
              onPressed: () async {
                await prefs.setString('ai_api_key', keyController.text.trim());
                await prefs.setString('ai_base_url', urlController.text.trim());
                await prefs.setString('ai_model', modelController.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ API 配置已保存")));
                }
              },
              child: const Text("保存"),
            )
          ],
        ),
      );
    });
  }

  void _deleteSelected() {
    setState(() {
      _messages.removeWhere((msg) => _selectedIds.contains(msg.id));
      _selectedIds.clear();
    });
    _saveHistory();
    _reconstructContext();
  }

  void _clearAll() {
    if (_messages.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清空记录"),
        content: const Text("确定要删除所有聊天记录吗？清空后 AI 会忘记你们的上下文。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
            onPressed: () {
              setState(() { _messages.clear(); _selectedIds.clear(); });
              _saveHistory(); 
              _reconstructContext();
              Navigator.pop(context);
            },
            child: const Text("清空", style: TextStyle(color: Colors.red)),
          )
        ],
      )
    );
  }

  // ================= 🎨 UI 构建 =================

  PreferredSizeWidget _buildAppBar() {
    if (_isSelectionMode) {
      return AppBar(
        title: Text("已选择 ${_selectedIds.length} 项", style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.blueGrey.shade50, foregroundColor: Colors.black87,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear())),
        actions: [IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSelected)],
      );
    }
    return AppBar(
      title: const Text("小满", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0, centerTitle: true,
      actions: [
        IconButton(icon: const Icon(Icons.auto_awesome), tooltip: '一键总结本周', onPressed: _requestWeeklySummary),
        IconButton(icon: const Icon(Icons.delete_sweep, size: 22), tooltip: '清空记录', onPressed: _clearAll),
        IconButton(icon: const Icon(Icons.settings, size: 22), tooltip: 'API 配置', onPressed: _showApiSettingsDialog),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 10, bottom: 20, left: 16, right: 16),
              itemCount: _messages.length + (_isThinking ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isThinking) return _buildTypingIndicator(themeColor);
                return _buildChatBubble(_messages[index], themeColor);
              },
            ),
          ),
          if (!_isSelectionMode) _buildBottomInputBar(themeColor),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message, Color themeColor) {
    bool isMe = message.isUser;
    bool isSelected = _selectedIds.contains(message.id);
    
    return GestureDetector(
      onLongPress: () => setState(() => _selectedIds.add(message.id)),
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) _selectedIds.remove(message.id);
            else _selectedIds.add(message.id);
          });
        }
      },
      child: Container(
        color: isSelected ? themeColor.withOpacity(0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildAvatar(isMe, themeColor),
            const SizedBox(width: 10),
            
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isMe ? themeColor : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4), bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
                    ),
                    child: Text(message.text, style: TextStyle(fontSize: 15, height: 1.5, color: isMe ? Colors.white : Colors.black87)),
                  ),
                  
                  if (!isMe) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(DateFormat('HH:mm').format(message.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 12),
                        PopupMenuButton<int>(
                          enabled: !_isSelectionMode,
                          tooltip: '保存到我的记录',
                          onSelected: (int type) => _saveAsEntry(message.text, type),
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                            const PopupMenuItem<int>(value: 1, child: Row(children: [Icon(Icons.edit_note, color: Colors.amber, size: 20), SizedBox(width: 8), Text('存为随手记')])),
                            const PopupMenuItem<int>(value: 0, child: Row(children: [Icon(Icons.book, color: Colors.teal, size: 20), SizedBox(width: 8), Text('存为正式日记')])),
                          ],
                          child: Row(
                            children: [
                              Icon(Icons.bookmark_add_outlined, size: 14, color: themeColor),
                              const SizedBox(width: 2),
                              Text("转存", style: TextStyle(fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
                              Icon(Icons.arrow_drop_down, size: 14, color: themeColor),
                            ],
                          ),
                        )
                      ],
                    )
                  ] else ...[
                     Padding(
                       padding: const EdgeInsets.only(top: 4, right: 4),
                       child: Text(DateFormat('HH:mm').format(message.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                     )
                  ]
                ],
              ),
            ),
            
            const SizedBox(width: 10),
            if (isMe) _buildAvatar(isMe, themeColor),
            
            if (_isSelectionMode && isMe) ...[
               const SizedBox(width: 8),
               Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? themeColor : Colors.grey)
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isMe, Color themeColor) => CircleAvatar(radius: 18, backgroundColor: isMe ? themeColor.withOpacity(0.2) : Colors.white, child: Icon(isMe ? Icons.person : Icons.auto_awesome, size: 20, color: isMe ? themeColor : Colors.amber));

  Widget _buildTypingIndicator(Color themeColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(false, themeColor),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor)),
              const SizedBox(width: 10),
              const Text("小满正在思考...", style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildBottomInputBar(Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8).copyWith(bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(color: const Color(0xFFF7F7F7), border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(icon: Icon(_isVoiceMode ? Icons.keyboard : Icons.mic_none, color: Colors.black54), onPressed: () => setState(() => _isVoiceMode = !_isVoiceMode)),
          Expanded(
            child: _isVoiceMode ? _buildVoiceRecordButton() : Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: TextField(
                controller: _textController, maxLines: null, textInputAction: TextInputAction.send, onSubmitted: _sendMessage,
                decoration: const InputDecoration(hintText: "聊点什么吧...", hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!_isVoiceMode)
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(20)),
              child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: () => _sendMessage(_textController.text)),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecordButton() {
    return GestureDetector(
      // 1. 手指按下，开始录音
      onLongPressStart: (_) async {
        Feedback.forLongPress(context);
        await _startRecording();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎤 正在倾听，请说话...'),
              duration: Duration(days: 1), // 保持长显，但靠代码清除
            )
          );
        }
      },
      // 2. 手指在按钮内正常松开，停止录音并发送
      onLongPressEnd: (_) async {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await _stopRecording();
      },
      // 💡 核心修复 3：防手滑/防中断！当手指滑出按钮范围，或系统中断手势时触发
      onLongPressCancel: () async {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await _stopRecording(); // 确保强制结束录音进程
        if (mounted) {
          // 给个轻量提示，告知录音已结束
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已结束录音'), duration: Duration(milliseconds: 800))
          );
        }
      },
      child: Container(
        height: 42, 
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: _isThinking ? Colors.amber : Colors.grey.shade300)
        ),
        child: Center(
          child: Text(
            _isThinking ? "正在识别中..." : "按住 说话", 
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87)
          )
        ),
      ),
    );
  }
}