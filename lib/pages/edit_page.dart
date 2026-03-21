import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart'; 
import 'package:pasteboard/pasteboard.dart';    
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';  
import 'package:http/http.dart' as http; // 💡 引入 http 用于 Windows 逆地理编码
import '../widgets/full_screen_gallery.dart';

// 核心依赖
import '../core/database_helper.dart'; 
import '../main.dart';            
import '../widgets/voice_recorder.dart';
import '../widgets/template_picker.dart'; // 💡 确保这个文件已建立
import '../core/encryption_service.dart';

class DiaryEditPage extends StatefulWidget {
  final Map<String, dynamic>? existingDiary;
  final int entryType; // 💡 新增：0 代表日记，1 代表随手记
  
  const DiaryEditPage({super.key, this.existingDiary, this.entryType = 0});

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> {

  String? _location; // 保存当前定位

  // 1. 控制器
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final tagsController = TextEditingController();
  final AudioPlayer _typingPlayer = AudioPlayer();

  // 2. 状态变量
  final List<String> _imagePaths = [];
  final List<String> _attachments = []; 
  String? _videoPath;
  String? _audioPath; 
  
  bool _isLoading = false;
  bool _isDragging = false; 
  String _selectedWeather = "☀️";
  String _selectedMood = "😊";
  final List<String> weathers = ["☀️", "☁️", "🌧️", "❄️", "🌩️"];
  final List<String> moods = ["😊", "😄", "😔", "😠", "😴"];

  // 3. 安全与统计
  bool _isLocked = false;
  bool _isArchived = false;
  String? _pwdHash;
  String? _tempKey; 
  
  Timer? _debounceTimer;
  int? _currentDiaryId;
  late String _creationDate;
  String _saveStatusText = "";
  int _wordCount = 0;
  int _lastTextLength = 0;

  @override
  void initState() {
    super.initState();
    _initData();
    titleController.addListener(_onDataChanged);
    contentController.addListener(_onDataChanged);
    tagsController.addListener(_onDataChanged);
    
    // 💡 新增：监听页面全局键盘事件，捕获 Ctrl+V
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  // 💡 新增：在页面销毁时清理内存
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    _debounceTimer?.cancel();
    _typingPlayer.dispose();
    super.dispose();
  }

  // 💡 新增：核心拦截逻辑（检测 Ctrl+V 或 Cmd+V）
  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
        _checkAndPasteImage();
      }
    }
    // 返回 false 非常重要！这代表我们不“吞掉”这个事件，这样文本框里的文字粘贴依然可以正常工作。
    return false; 
  }

  // 💡 新增：从剪贴板读取图片并保存
  // 💡 升级版：同时支持“截图像素数据”和“本地图片文件”的粘贴
  Future<void> _checkAndPasteImage() async {
    if (_isArchived) return;
    try {
      bool hasPasted = false;

      // 1. 先尝试读取作为“文件”复制的图片（例如在文件夹里右键复制的图片）
      final files = await Pasteboard.files();
      if (files != null && files.isNotEmpty) {
        for (String path in files) {
          final ext = p.extension(path).toLowerCase();
          if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
             await _saveMediaFile(path, 'image'); // 复用现有的保存逻辑
             hasPasted = true;
          }
        }
      }

      // 2. 如果没有检测到文件，再尝试读取内存中的“截图”（例如微信/系统截图工具）
      if (!hasPasted) {
        final imageBytes = await Pasteboard.image;
        if (imageBytes != null && imageBytes.isNotEmpty) {
          final appDir = await getApplicationDocumentsDirectory();
          final savedPath = p.join(appDir.path, 'PASTE_${DateTime.now().millisecondsSinceEpoch}.png');
          await File(savedPath).writeAsBytes(imageBytes);
          
          setState(() {
            _imagePaths.add(savedPath);
          });
          _performAutoSave();
          hasPasted = true;
        }
      }

      // 3. 成功反馈
      if (hasPasted && mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📎 成功粘贴图片！'), duration: Duration(seconds: 2)));
      } else {
         // 如果剪贴板里既没有截图也没有图片文件，也给个提示
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板中没有发现图片'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      debugPrint("粘贴图片失败: $e");
    }
  }

  void _initData() {
    if (widget.existingDiary != null) {
      final d = widget.existingDiary!;
      _currentDiaryId = d['id'] as int?;
      _creationDate = d['date'] as String? ?? DateTime.now().toString();
      titleController.text = d['title'] as String? ?? '';
      _isLocked = (d['is_locked'] == 1);
      _isArchived = (d['is_archived'] == 1);
      _pwdHash = d['pwd_hash'] as String?;
      contentController.text = d['content'] as String? ?? '';
      _selectedWeather = d['weather'] as String? ?? "☀️";
      _selectedMood = d['mood'] as String? ?? "😊";
      _videoPath = d['videoPath'] as String?;
      _audioPath = d['audioPath'] as String?;
      _location = d['location'] as String?;

      if (d['imagePath'] != null) {
        try { _imagePaths.addAll(List<String>.from(jsonDecode(d['imagePath']))); } catch(_) {}
      }
      if (d['attachments'] != null) {
        try { _attachments.addAll(List<String>.from(jsonDecode(d['attachments']))); } catch(_) {}
      }
      if (d['tags'] != null) {
        try { tagsController.text = List<String>.from(jsonDecode(d['tags'])).join(" "); } catch(_) {}
      }
      _updateWordCount();
    } else {
      _creationDate = DateTime.now().toString();
    }
    _lastTextLength = contentController.text.length;
  }

  // ================= 核心：监听与自动保存 =================

  void _onDataChanged() {
    if (globalEnableTypingSound && contentController.text.length > _lastTextLength) {
      _typingPlayer.play(AssetSource('sounds/click.mp3'), volume: 0.5).catchError((_){});
    }
    _lastTextLength = contentController.text.length;
    _updateWordCount(); 

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    setState(() { _saveStatusText = "正在输入..."; });
    _debounceTimer = Timer(const Duration(seconds: 2), () => _performAutoSave());
  }

  void _updateWordCount() {
    setState(() => _wordCount = contentController.text.replaceAll(RegExp(r'\s+'), '').length);
  }

  Future<void> _performAutoSave() async {
    if (titleController.text.isEmpty && contentController.text.isEmpty) return;
    if (mounted) setState(() { _saveStatusText = "保存中..."; });

    String finalContent = contentController.text;
    if (_isLocked && _tempKey != null) {
      finalContent = EncryptionService.encrypt(finalContent, _tempKey!);
    }

    final Map<String, dynamic> diaryData = {
      'title': titleController.text,
      'content': finalContent,
      'date': _creationDate,
      'imagePath': jsonEncode(_imagePaths),
      'videoPath': _videoPath,
      'audioPath': _audioPath,
      'attachments': jsonEncode(_attachments),
      'weather': _selectedWeather,
      'mood': _selectedMood,
      'tags': jsonEncode(tagsController.text.trim().split(RegExp(r'\s+')).where((e)=>e.isNotEmpty).toList()),
      'is_locked': _isLocked ? 1 : 0,
      'is_archived': _isArchived ? 1 : 0,
      'pwd_hash': _pwdHash,
      'location': _location,
      'type': widget.existingDiary?['type'] ?? widget.entryType,
    };

    if (_currentDiaryId == null) {
      _currentDiaryId = await DatabaseHelper.instance.insertDiary(diaryData);
    } else {
      diaryData['id'] = _currentDiaryId;
      await DatabaseHelper.instance.updateDiary(diaryData);
    }

    if (mounted) setState(() { _saveStatusText = "已保存 ${DateFormat('HH:mm').format(DateTime.now())}"; });
  }

  // ================= 核心：模板套用逻辑 =================

  void _showTemplatePicker() {
    if (_isArchived) return;
    if (contentController.text.isNotEmpty || titleController.text.isNotEmpty) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("注意"),
          content: const Text("套用模板将清空当前已写的内容，确定吗？"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
            TextButton(onPressed: () { Navigator.pop(c); _openPicker(); }, child: const Text("确定", style: TextStyle(color: Colors.red))),
            
         ],
        ),
      );
    } else {
      _openPicker();
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => TemplatePicker(
        onSelect: (title, content, tags) {
          setState(() {
            titleController.text = title;
            contentController.text = content;
            tagsController.text = tags.join(" ");
          });
          _performAutoSave();
        },
      ),
    );
  }

  // ================= 核心：安全控制 =================

  void _showSecurityMenu() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_isLocked ? Icons.lock_open : Icons.enhanced_encryption, color: Colors.blue),
              title: Text(_isLocked ? "解除加密锁定" : "启用 AES-256 加密锁定"),
              onTap: () { Navigator.pop(c); _handleLockToggle(); },
            ),
            ListTile(
              leading: Icon(_isArchived ? Icons.unarchive : Icons.archive, color: Colors.brown),
              title: Text(_isArchived ? "取消归档" : "归档日记 (变为只读)"),
              onTap: () { 
                setState(() => _isArchived = !_isArchived); 
                _performAutoSave();
                Navigator.pop(c); 
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleLockToggle() {
    if (_isLocked) {
      setState(() { _isLocked = false; _tempKey = null; _pwdHash = null; });
      _performAutoSave();
    } else {
      final ctrl = TextEditingController();
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("设置加密密码"),
          content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(hintText: "此密码仅用于本篇")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
            TextButton(onPressed: () {
              if (ctrl.text.isNotEmpty) {
                setState(() { _isLocked = true; _tempKey = ctrl.text; _pwdHash = EncryptionService.hashPassword(ctrl.text); });
                _performAutoSave();
                Navigator.pop(c);
              }
            }, child: const Text("锁定")),
          ],
        ),
      );
    }
  }

  // ================= 媒体处理 =================

  Future<void> _saveMediaFile(String originalPath, String type) async {
    final appDir = await getApplicationDocumentsDirectory();
    final savedPath = p.join(appDir.path, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(originalPath)}');
    await File(originalPath).copy(savedPath);
    setState(() { 
      if (type == 'video') _videoPath = savedPath; 
      else if (type == 'audio') _audioPath = savedPath;
      else if (type == 'file') _attachments.add(savedPath);
      // 💡 重点：如果是 'live' 模式，我们将它和普通图片放在同一个数组里混排！
      else _imagePaths.add(savedPath); 
    });
    _performAutoSave();
  }

  

// ... 其他代码

Future<void> _fetchLocation() async {
  setState(() => _location = "正在定位...");
  try {
    // 1. 获取经纬度 (Windows 上 geolocator 是支持的)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _location = "系统定位未开启");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _location = "权限被拒绝");
        return;
      }
    }

    // 获取当前位置
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );

    // 2. Windows 专属：通过 Web API 获取地址 (替代 geocoding 插件)
    // 使用 OpenStreetMap 的免费接口 (Nominatim)
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1'
    );

    // 💡 发送请求获取位置描述
    final response = await http.get(url, headers: {'Accept-Language': 'zh-CN'});
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final address = data['address'];
      
      // 提取城市和区域
      String city = address['city'] ?? address['town'] ?? address['village'] ?? "未知城市";
      String suburb = address['suburb'] ?? address['neighbourhood'] ?? "";
      
      setState(() {
        _location = "$city · $suburb";
      });
      _performAutoSave(); // 保存到数据库
    } else {
      setState(() => _location = "地址转换失败");
    }
  } catch (e) {
    debugPrint("Windows定位错误: $e");
    setState(() => _location = "定位异常");
  }
}
  // ================= UI 构建 =================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _performAutoSave();
        if (mounted) Navigator.pop(context, true);
      },
      child: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          setState(() => _isDragging = false);
          for (var xfile in details.files) {
            String ext = p.extension(xfile.path).toLowerCase();
            _saveMediaFile(xfile.path, ext == '.mp4' ? 'video' : (['.mp3','.m4a'].contains(ext) ? 'audio' : 'image'));
          }
        },
        child: Scaffold(
          appBar: AppBar(
            // 💡 动态显示标题
            title: Text(_isArchived ? "查看" : (widget.existingDiary == null ? (widget.entryType == 1 ? "新随手记" : "新日记") : "编辑")),
            backgroundColor: _isDragging ? Colors.orange : (_isLocked ? Colors.indigo : Colors.teal),
            foregroundColor: Colors.white,
            actions: [
              Center(child: Text(_saveStatusText, style: const TextStyle(fontSize: 10, color: Colors.white70))),
              
              // 💡 目标图标在这里：魔法卡片（模板）
              IconButton(
                icon: const Icon(Icons.auto_awesome_motion), 
                tooltip: '套用模板', 
                onPressed: _isArchived ? null : _showTemplatePicker
              ),
              
              IconButton(icon: Icon(_isLocked ? Icons.lock : (_isArchived ? Icons.archive : Icons.security)), onPressed: _showSecurityMenu),
              IconButton(icon: const Icon(Icons.check), onPressed: () async { await _performAutoSave(); Navigator.pop(context, true); }),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildHeader(),
                      const Divider(),
                      _buildEditor(),
                      _buildMediaDisplay(),
                      const SizedBox(height: 150),
                    ],
                  ),
                ),
              ),
              if (!_isArchived) const Divider(height: 1, color: Colors.black12), // 加一条浅色的分割线
              _buildToolbar(), // 固定在底部的工具栏
              _buildFooter(),  // 最底部的字数统计栏
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // 💡 解析日期并计算星期几
    final date = DateTime.parse(_creationDate);
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekdayStr = weekdays[date.weekday - 1];
    final dateStr = "${DateFormat('yyyy-MM-dd').format(date)}  $weekdayStr";

    return Column(
      children: [
        Row(
          children: [
            Text(dateStr, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            // 💡 一键定位按钮
            GestureDetector(
              onTap: _isArchived ? null : _fetchLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text(_location ?? "点击定位", style: const TextStyle(fontSize: 12, color: Colors.teal)),
                  ],
                ),
              ),
            ),
            const Spacer(),
            DropdownButton<String>(value: _selectedWeather, items: weathers.map((w)=>DropdownMenuItem(value: w, child: Text(w))).toList(), onChanged: _isArchived ? null : (v)=>setState(()=>_selectedWeather=v!)),
            const SizedBox(width: 10),
            DropdownButton<String>(value: _selectedMood, items: moods.map((m)=>DropdownMenuItem(value: m, child: Text(m))).toList(), onChanged: _isArchived ? null : (v)=>setState(()=>_selectedMood=v!)),
          ],
        ),
        TextField(controller: titleController, enabled: !_isArchived, decoration: const InputDecoration(hintText: '标题', border: InputBorder.none), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        TextField(controller: tagsController, enabled: !_isArchived, decoration: const InputDecoration(hintText: '#标签 (空格分隔)', border: InputBorder.none), style: const TextStyle(color: Colors.teal, fontSize: 14)),
      ],
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: contentController,
      maxLines: null,
      minLines: 10,
      enabled: !_isArchived,
      // 💡 修复：增加底部滚动边距。当光标输入到底部时，系统会自动将页面向上推，始终在光标下方留出 150 像素的舒适视野
      scrollPadding: const EdgeInsets.only(bottom: 150),
      decoration: InputDecoration(hintText: _isArchived ? "内容已归档锁定" : "记录这一刻...", border: InputBorder.none),
      style: const TextStyle(fontSize: 16, height: 1.6),
    );
  }

 Widget _buildToolbar() {
    if (_isArchived) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).cardColor, 
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.image_outlined, color: Colors.teal), tooltip: '选择图片', onPressed: () => _pickMedia('image')),
          
          // 💡 新增：专门的粘贴剪贴板图片按钮（双保险）
          IconButton(icon: const Icon(Icons.content_paste, color: Colors.teal), tooltip: '粘贴截图或复制的图片', onPressed: _checkAndPasteImage),
          
          IconButton(icon: const Icon(Icons.motion_photos_on_outlined, color: Colors.amber), tooltip: '插入 Live 图', onPressed: () => _pickMedia('live')),
          IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.teal), tooltip: '插入视频', onPressed: () => _pickMedia('video')),
          IconButton(icon: const Icon(Icons.mic_none_outlined, color: Colors.teal), tooltip: '录音', onPressed: () {
            showModalBottomSheet(context: context, builder: (c) => VoiceRecorderDialog(onRecordComplete: (path) => _saveMediaFile(path, 'audio')));
          }),
          IconButton(icon: const Icon(Icons.attach_file_outlined, color: Colors.teal), tooltip: '添加附件', onPressed: () => _pickMedia('file')),
        ],
      ),
    );
  }
  
  Widget _buildMediaDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_audioPath != null) MiniAudioPlayer(audioPath: _audioPath!),
        if (_videoPath != null) MiniVideoPlayer(videoPath: _videoPath!),
        if (_attachments.isNotEmpty) ..._attachments.map((path) => Card(child: ListTile(leading: const Icon(Icons.file_present), title: Text(p.basename(path)), onTap: () => OpenFilex.open(path)))),
        const SizedBox(height: 10),
        
        if (_imagePaths.isNotEmpty)
          Wrap(
            spacing: 12, 
            runSpacing: 12, 
            children: _imagePaths.asMap().entries.map((entry) {
              final String path = entry.value;
              // 💡 魔法时刻：判断文件后缀是否为视频
              final bool isLive = path.toLowerCase().endsWith('.mp4') || path.toLowerCase().endsWith('.mov');
              
              // 根据是否为 Live 图，渲染不同的微型组件
              Widget thumbnail = isLive 
                  ? LivePhotoThumbnail(videoPath: path, width: 100, height: 100)
                  : Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover);

              return Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => FullScreenGallery(images: _imagePaths, initialIndex: entry.key)
                      ));
                    },
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: thumbnail),
                  ),
                  if (!_isArchived)
                    Positioned(
                      right: 4, top: 4,
                      child: GestureDetector(
                        onTap: () { setState(() => _imagePaths.removeAt(entry.key)); _performAutoSave(); },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("字数: $_wordCount", style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          if (_isLocked) const Text("🔒 AES-256 已加密", style: TextStyle(color: Colors.orange, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickMedia(String type) async {
    XTypeGroup typeGroup;
    // 💡 让 live 和 video 一样选择视频格式
    if (type == 'video' || type == 'live') typeGroup = const XTypeGroup(extensions: ['mp4', 'mov']);
    else if (type == 'audio') typeGroup = const XTypeGroup(extensions: ['mp3', 'm4a']);
    else if (type == 'file') typeGroup = const XTypeGroup(extensions: ['pdf', 'zip']);
    // 💡 顺手让普通图片支持 GIF 等动图
    else typeGroup = const XTypeGroup(extensions: ['jpg', 'png', 'gif', 'webp']); 
    
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) _saveMediaFile(file.path, type);
  }
}

// ================= 子组件：视频播放器 =================
class MiniVideoPlayer extends StatefulWidget {
  final String videoPath;
  const MiniVideoPlayer({super.key, required this.videoPath});
  @override
  State<MiniVideoPlayer> createState() => _MiniVideoPlayerState();
}
class _MiniVideoPlayerState extends State<MiniVideoPlayer> {
  late VideoPlayerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))..initialize().then((_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized 
      ? AspectRatio(aspectRatio: _controller.value.aspectRatio, child: Stack(alignment: Alignment.center, children: [VideoPlayer(_controller), IconButton(icon: Icon(_controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 50), onPressed: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()))])) 
      : const CircularProgressIndicator();
  }
}

// ================= 子组件：音频播放器 =================
class MiniAudioPlayer extends StatefulWidget {
  final String audioPath;
  const MiniAudioPlayer({super.key, required this.audioPath});
  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}
class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  @override
  void initState() {
    super.initState();
    _audioPlayer.setSourceDeviceFile(widget.audioPath);
    _audioPlayer.onPlayerStateChanged.listen((s) { if(mounted) setState(() => _isPlaying = s == PlayerState.playing); });
    _audioPlayer.onDurationChanged.listen((d) { if(mounted) setState(() => _duration = d); });
    _audioPlayer.onPositionChanged.listen((p) { if(mounted) setState(() => _position = p); });
  }
  @override
  void dispose() { _audioPlayer.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(DeviceFileSource(widget.audioPath))),
        Expanded(child: Slider(max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0, value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()), onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt())))),
      ],
    );
  }
}
// ================= 子组件：Live图缩略图自动播放器 =================
class LivePhotoThumbnail extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  const LivePhotoThumbnail({super.key, required this.videoPath, required this.width, required this.height});
  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..setVolume(0) // 强制静音
      ..setLooping(true) // 强制循环
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play(); // 加载完立即静默播放
        }
      });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width, height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _controller.value.isInitialized
              ? FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)))
              : Container(color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))),
          // 专属 LIVE 呼吸角标
          Positioned(
            left: 4, top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.motion_photos_on, size: 10, color: Colors.white),
                  SizedBox(width: 2),
                  Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}