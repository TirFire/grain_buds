import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // 用于 kIsWeb 等检测
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../widgets/full_screen_gallery.dart';
import '../core/database_helper.dart';
import '../core/constants.dart'; // 💡 新增：引入状态码字典
import '../widgets/voice_recorder.dart';
import '../widgets/template_picker.dart';
import '../core/encryption_service.dart';
import '../widgets/custom_title_bar.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/webdav_sync_service.dart';
import 'package:image_picker/image_picker.dart';
import '../core/markdown_controller.dart';
import '../core/ai_service.dart';




class DiaryEditPage extends StatefulWidget {
  final Map<String, dynamic>? existingDiary;
  final int entryType;
  final DateTime? selectedDate;
  final String? pwdKey; // 💡 修复 1：新增接收密码钥匙
  final String heroTag; // 💡 顺便加个接收 Hero Tag（为后面的 Bug 2 铺垫）

  const DiaryEditPage(
      {super.key, 
      this.existingDiary, 
      this.entryType = 0, 
      this.selectedDate, 
      this.pwdKey, 
      this.heroTag = 'diary_hero_new'}); // 默认值防错

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> with WidgetsBindingObserver {
  String? _location;
  bool _isUnknownDate = false; //新增：标记是否为不可考的回忆
  bool _canPop = false;
  bool _isSaving = false;
  bool _isFirstSession = false; // 💡 标记是否为首次创建的会话
  String _sessionStartTime = ""; // 💡 记录首次会话的起始时间
  bool _hasRealChanges = false; // 💡 标记是否有实质性改动
  bool _showTextFormatBar = false;
  bool _isAILoading = false;
  String _aiLoadingText = "🪄 小满正在整理...";

  final titleController = TextEditingController();
  final contentController = MarkdownTextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  final tagsController = TextEditingController();

  final List<String> _imagePaths = [];
  final List<String> _attachments = [];
  // 💡 升级 1：从 String? 升级为 List<String>
  final List<String> _videoPaths = [];
  final List<String> _audioPaths = [];

  bool _isDragging = false;

  // 💡 核心修改：现在我们只在内存里保存纯正的“英文字符串状态码”
  String _selectedWeatherKey = 'sunny';
  String _selectedMoodKey = 'happy';

  bool _isLocked = false;
  bool _isArchived = false;
  String? _pwdHash;
  String? _tempKey;

  Timer? _debounceTimer;
  int? _currentDiaryId;
  late String _creationDate;
  String _saveStatusText = "";
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _initData();
    WidgetsBinding.instance.addObserver(this);
    titleController.addListener(_onDataChanged);
    contentController.addListener(_onDataChanged);
    tagsController.addListener(_onDataChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    titleController.dispose();
    contentController.dispose();
    _contentFocusNode.dispose();
    tagsController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // 💡 核心新增：监听系统状态变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当 App 被切到后台 (paused) 或者失去焦点 (inactive) 时，强制触发保存！
    // 完美避免系统强杀导致写了一半的日记丢失
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (titleController.text.isNotEmpty || contentController.text.isNotEmpty) {
        _performAutoSave();
        debugPrint("系统切后台，已触发紧急自动保存！");
      }
    }
  }

  // 新增：点击日期后弹出的“修改日期/岁月深处”菜单
  void _showDateOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.teal),
              title: const Text("修改日记日期"),
              subtitle:
                  const Text("重新选择这篇日记所属的时间", style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(c);
                DateTime initDate = _isUnknownDate
                    ? DateTime.now()
                    : DateTime.parse(_creationDate);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  final time = initDate;
                  final newDate = DateTime(picked.year, picked.month,
                      picked.day, time.hour, time.minute, time.second);
                  setState(() {
                    _creationDate = newDate.toString();
                    _isUnknownDate = false;
                    _hasRealChanges = true;
                  });
                  _performAutoSave();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_empty, color: Colors.brown),
              title: Text(_isUnknownDate ? "恢复为具体日期" : "标记为日期不可考 (岁月深处)"),
              subtitle: const Text("适用于只记得大概，但不确定具体哪天的回忆",
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(c);
                setState(() { _isUnknownDate = !_isUnknownDate; _hasRealChanges = true; });
                _performAutoSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  

  // 💡 智能决策修改时间
  String get _determinedUpdateTime {
    if (_isFirstSession) return _sessionStartTime; // 新建日记：整个初次编辑过程锁定更新时间！
    if (_hasRealChanges) return DateTime.now().toString(); // 已有日记且真正改动了内容：更新为现在
    return widget.existingDiary?['update_time']?.toString() ?? _creationDate; // 没改动内容：保持原有的修改时间
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // 💡 改造：只有在电脑端才监听 Ctrl+V 粘贴
      if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
          event.logicalKey == LogicalKeyboardKey.keyV &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        _checkAndPasteImage();
        return true;
      }

      // 2. 新增：Ctrl + S (保存并退出)
      if (event.logicalKey == LogicalKeyboardKey.keyS &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        if (!_isArchived) {
          _performAutoSave().then((_) {
            setState(() {
              _canPop = true;
            });
            if (mounted) Navigator.pop(context, true);
          });
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _checkAndPasteImage() async {
    if (_isArchived) return;
    try {
      bool hasPasted = false;
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        for (String path in files) {
          final ext = p.extension(path).toLowerCase();
          if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
            await _saveMediaFile(path, 'image');
            hasPasted = true;
          }
        }
      }
      if (!hasPasted) {
        final imageBytes = await Pasteboard.image;
        if (imageBytes != null && imageBytes.isNotEmpty) {
          final assetDir = await _getAssetDir();
          final savedPath = p.join(
              assetDir, 'PASTE_${DateTime.now().millisecondsSinceEpoch}.png');
          await File(savedPath).writeAsBytes(imageBytes);
          setState(() {
            _imagePaths.add(savedPath);
            _hasRealChanges = true; // 💡 补上这行
          });
          await _performAutoSave();
          hasPasted = true;
        }
      }
      if (!context.mounted) return;
      if (hasPasted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('📎 成功粘贴图片！'), duration: Duration(seconds: 2)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('剪贴板中没有发现图片'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      debugPrint("粘贴图片失败: $e");
    }
  }

  
  
    void _initData() {
    if (widget.pwdKey != null) {
      _tempKey = widget.pwdKey;
    }
    
    if (widget.existingDiary != null) {
      final d = widget.existingDiary!;
      _currentDiaryId = d['id'] as int?;
      _creationDate = d['date'] as String? ?? DateTime.now().toString();
      titleController.text = d['title'] as String? ?? '';
      _isLocked = (d['is_locked'] == 1);
      _isArchived = (d['is_archived'] == 1);
      _pwdHash = d['pwd_hash'] as String?;
      contentController.text = d['content'] as String? ?? '';
      _location = d['location'] as String?;

      // ==============================================================
      // 💡 核心修复：完美兼容读取 SQLite 数据库中的新老字段命名，照片视频再也不会丢了！
      String? imgStr = d['image_path'] ?? d['imagePath'];
      if (imgStr != null) { try { _imagePaths.addAll(List<String>.from(jsonDecode(imgStr))); } catch(_) {} }

      String? vidStr = d['video_path'] ?? d['videoPaths'];
      if (vidStr != null) { try { _videoPaths.addAll(List<String>.from(jsonDecode(vidStr))); } catch(_) {} }
      else if (d['videoPath'] != null) { _videoPaths.add(d['videoPath'] as String); }

      String? audStr = d['audio_path'] ?? d['audioPaths'];
      if (audStr != null) { try { _audioPaths.addAll(List<String>.from(jsonDecode(audStr))); } catch(_) {} }
      else if (d['audioPath'] != null) { _audioPaths.add(d['audioPath'] as String); }
      
      String? attStr = d['attachments'];
      if (attStr != null) { try { _attachments.addAll(List<String>.from(jsonDecode(attStr))); } catch(_) {} }
      
      // 去除空路径
      _imagePaths.removeWhere((path) => path.trim().isEmpty);
      _videoPaths.removeWhere((path) => path.trim().isEmpty);
      _audioPaths.removeWhere((path) => path.trim().isEmpty);
      _attachments.removeWhere((path) => path.trim().isEmpty);
      // ==============================================================

      // 💡 智能解析：即使数据库里有测试用的旧表情，也能反向解析出正确的 key
      String dbWeather = d['weather'] as String? ?? 'sunny';
      _selectedWeatherKey = AppConstants.weatherMap.containsKey(dbWeather)
          ? dbWeather
          : (AppConstants.weatherMap.entries
              .firstWhere((e) => e.value == dbWeather,
                  orElse: () => const MapEntry('sunny', '☀️'))
              .key);

      String dbMood = d['mood'] as String? ?? 'happy';
      _selectedMoodKey = AppConstants.moodMap.containsKey(dbMood)
          ? dbMood
          : (AppConstants.moodMap.entries
              .firstWhere((e) => e.value == dbMood,
                  orElse: () => const MapEntry('happy', '😊'))
              .key);

      if (d['tags'] != null) {
        try {
          tagsController.text =
              List<String>.from(jsonDecode(d['tags'])).join(" ");
        } catch (_) {}
      }
      _updateWordCount();
    } else {
      if (widget.selectedDate != null) {
        DateTime now = DateTime.now();
        _creationDate = DateTime(
                widget.selectedDate!.year,
                widget.selectedDate!.month,
                widget.selectedDate!.day,
                now.hour,
                now.minute,
                now.second)
            .toString();
        DateTime today = DateTime(now.year, now.month, now.day);
        DateTime sDay = DateTime(widget.selectedDate!.year,
            widget.selectedDate!.month, widget.selectedDate!.day);
        if (sDay.isBefore(today)) {
          tagsController.text = "回忆 ";
        } else if (sDay.isAfter(today)) {
          tagsController.text = "期许 ";
        }
      } else {
        _creationDate = DateTime.now().toString();
      }
      _isFirstSession = true; 
      _sessionStartTime = _creationDate; // 💡 将首次会话的初始时间与创建时间强绑定
    }
    _fixMediaPaths();
  }
  // ====================================================================
  // 💡 新增：专门解决模拟器重启/重装App导致的“沙盒路径漂移”问题
  // ====================================================================
  // lib/pages/edit_page.dart

Future<void> _fixMediaPaths() async {
  final appDir = await getApplicationDocumentsDirectory();
  final rootPath = appDir.path; // 注意：这里改用沙盒根目录，不再包含 MyDiary_Data

  void repair(List<String> paths) {
    for (int i = 0; i < paths.length; i++) {
      // 寻找 MyDiary_Data 标志
      int idx = paths[i].indexOf('MyDiary_Data');
      if (idx != -1) {
        // 💡 修复重点：直接将最新的沙盒根路径与相对于沙盒的路径拼接
        // 不要重复包含 MyDiary_Data 文件夹
        paths[i] = p.join(rootPath, paths[i].substring(idx));
      }
    }
  }

  if (mounted) {
    setState(() {
      repair(_imagePaths);
      repair(_videoPaths);
      repair(_audioPaths);
      repair(_attachments);
    });
    // 💡 只有在路径真的发生变化时才触发自动保存，或者直接去掉这里的强制保存
    // 因为 _onDataChanged 稍后会处理
  }
}

  // 💡 智能格式覆盖 (剥洋葱机制)
  void _insertMarkdown(String prefix, {String suffix = ''}) {
    if (_isArchived) return;

    final text = contentController.text;
    final selection = contentController.selection;

    int start = selection.isValid ? selection.start : text.length;
    int end = selection.isValid ? selection.end : text.length;

    if (start == -1) {
      start = text.length;
      end = text.length;
    }

    String selectedText = text.substring(start, end);

    if (selectedText.isNotEmpty) {
      selectedText = selectedText
          .replaceAll(RegExp(r'^\*\*|\*\*$'), '')
          .replaceAll(RegExp(r'^\*|\*$'), '')
          .replaceAll(RegExp(r'^~~|~~$'), '')
          .replaceAll(RegExp(r'^`|`$'), '')
          .replaceAll(RegExp(r'^#{1,6}\s+'), '') // 💡 剥离旧的标题标记
          .replaceAll(RegExp(r'^\[(red|blue|green|orange|purple)\]|\[/\]$'), '')
          .replaceAll(RegExp(r'^<font color=".*?">|</font>$'), '')
          .replaceAll(RegExp(r'^\[bg_(yellow|red|green|blue|purple)\]|\[/bg\]$'), '');
    }

    final newText = text.replaceRange(start, end, '$prefix$selectedText$suffix');

    contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + selectedText.length),
    );

    setState(() => _hasRealChanges = true);
    _performAutoSave(); 
  }
  
  void _onDataChanged() {
    _updateWordCount();
    _hasRealChanges = true;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    setState(() => _saveStatusText = "正在输入...");
    _debounceTimer =
        Timer(const Duration(seconds: 2), () => _performAutoSave());
  }

  void _updateWordCount() {
    setState(() => _wordCount =
        contentController.text.replaceAll(RegExp(r'\s+'), '').length);
  }

  Future<void> _performAutoSave() async {
    // 💡 核心防御 1：如果当前已经有一个保存任务在执行，直接跳过，防止并发导致重复插入
    if (_isSaving) return;

    // 💡 核心防御 2：一旦进入保存流程，立刻取消待执行的定时器，防止“双重保存”
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    final title = titleController.text.trim();
    final content = contentController.text.trim();

    if (title.isEmpty && content.isEmpty &&
        _imagePaths.isEmpty && _videoPaths.isEmpty && 
        _audioPaths.isEmpty && _attachments.isEmpty) {
      return;
    }

    _isSaving = true; // 🔒 上锁
    if (mounted) setState(() => _saveStatusText = "保存中...");
    
    try {
      String finalContent = contentController.text;
      if (_isLocked && _tempKey != null) {
        finalContent = EncryptionService.encrypt(finalContent, _tempKey!);
      }

      final Map<String, dynamic> diaryData = {
        'title': titleController.text, 
        'content': finalContent,
        'date': _isUnknownDate ? "1900-01-01 00:00:00" : _creationDate,
        'imagePath': jsonEncode(_imagePaths),
        'videoPaths': jsonEncode(_videoPaths),
        'audioPaths': jsonEncode(_audioPaths),
        'attachments': jsonEncode(_attachments),
        'weather': _selectedWeatherKey, 
        'mood': _selectedMoodKey,
        'tags': jsonEncode(tagsController.text.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList()),
        'is_locked': _isLocked ? 1 : 0, 
        'is_archived': _isArchived ? 1 : 0,
        'pwd_hash': _pwdHash, 
        'location': _location,
        'type': widget.existingDiary?['type'] ?? widget.entryType,
        'update_time': _determinedUpdateTime,
      };

      if (_currentDiaryId == null) {
        _currentDiaryId = await DatabaseHelper.instance.insertDiary(diaryData);
        debugPrint("✨ 首次插入成功，ID: $_currentDiaryId");
      } else {
        diaryData['id'] = _currentDiaryId;
        await DatabaseHelper.instance.updateDiary(diaryData);
        debugPrint("📝 更新成功，ID: $_currentDiaryId");
      }

      if (mounted) {
        setState(() => _saveStatusText = "已保存 ${DateFormat('HH:mm').format(DateTime.now())}");
      }
    } catch (e) {
      debugPrint("自动保存拦截: $e");
      if (mounted) setState(() => _saveStatusText = "仅保存至缓存");
    } finally {
      _isSaving = false; // 🔓 解锁
    }
  }

  // 💡 新增：排版快捷工具栏
  Widget _buildTextFormatBar() {
    if (_isArchived) return const SizedBox.shrink();

    return Container(
      height: 40,
      color: Theme.of(context).cardColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.format_bold, size: 20, color: Colors.blueGrey), onPressed: () => _insertMarkdown('**', suffix: '**'), tooltip: '加粗'),
            IconButton(icon: const Icon(Icons.format_italic, size: 20, color: Colors.blueGrey), onPressed: () => _insertMarkdown('*', suffix: '*'), tooltip: '斜体'),
            IconButton(icon: const Icon(Icons.format_strikethrough, size: 20, color: Colors.blueGrey), onPressed: () => _insertMarkdown('~~', suffix: '~~'), tooltip: '删除线'),
            
            const VerticalDivider(indent: 10, endIndent: 10, width: 20, color: Colors.black12),
            
            // 💡 1. 标题等级选择器
            PopupMenuButton<String>(
              tooltip: '选择标题等级',
              icon: const Icon(Icons.format_size, size: 20, color: Colors.blueGrey),
              onSelected: (value) => _insertMarkdown(value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: '# ', child: Text('一级大标题', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                const PopupMenuItem(value: '## ', child: Text('二级中标题', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const PopupMenuItem(value: '### ', child: Text('三级小标题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              ],
            ),

            IconButton(icon: const Icon(Icons.format_quote, size: 20, color: Colors.blueGrey), onPressed: () => _insertMarkdown('> '), tooltip: '段落引用'),
            IconButton(icon: const Icon(Icons.format_list_bulleted, size: 20, color: Colors.blueGrey), onPressed: () => _insertMarkdown('- '), tooltip: '无序列表'),
            
            const VerticalDivider(indent: 10, endIndent: 10, width: 20, color: Colors.black12),
            
            // 💡 2. 文本颜色选择 (替换为下拉菜单！)
            PopupMenuButton<String>(
              tooltip: '文本颜色',
              onSelected: (value) => _insertMarkdown('[$value]', suffix: '[/]'),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'red', child: Row(children: [Icon(Icons.circle, color: Colors.redAccent), const SizedBox(width:8), const Text('红色')])),
                PopupMenuItem(value: 'blue', child: Row(children: [Icon(Icons.circle, color: Colors.blue), const SizedBox(width:8), const Text('蓝色')])),
                PopupMenuItem(value: 'green', child: Row(children: [Icon(Icons.circle, color: Colors.teal), const SizedBox(width:8), const Text('绿色')])),
                PopupMenuItem(value: 'orange', child: Row(children: [Icon(Icons.circle, color: Colors.orange), const SizedBox(width:8), const Text('橙色')])),
                PopupMenuItem(value: 'purple', child: Row(children: [Icon(Icons.circle, color: Colors.purpleAccent), const SizedBox(width:8), const Text('紫色')])),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.palette_outlined, size: 18, color: Colors.blueAccent),
                    Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueAccent),
                  ],
                ),
              ),
            ),
            
            const VerticalDivider(indent: 10, endIndent: 10, width: 20, color: Colors.black12),

            // 💡 3. 背景高亮选择器
            PopupMenuButton<String>(
              tooltip: '文本背景高亮',
              icon: const Icon(Icons.border_color, size: 18, color: Colors.amber), // 荧光笔图标
              onSelected: (value) => _insertMarkdown('[bg_$value]', suffix: '[/bg]'),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'yellow', child: Row(children: [Icon(Icons.circle, color: Colors.yellow.shade300), const SizedBox(width:8), const Text('经典黄')])),
                PopupMenuItem(value: 'red', child: Row(children: [Icon(Icons.circle, color: Colors.red.shade200), const SizedBox(width:8), const Text('柔和红')])),
                PopupMenuItem(value: 'green', child: Row(children: [Icon(Icons.circle, color: Colors.teal.shade200), const SizedBox(width:8), const Text('清爽绿')])),
                PopupMenuItem(value: 'blue', child: Row(children: [Icon(Icons.circle, color: Colors.blue.shade200), const SizedBox(width:8), const Text('天空蓝')])),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  void _showTemplatePicker() {
    if (_isArchived) return;
    if (contentController.text.isNotEmpty || titleController.text.isNotEmpty) {
      showDialog(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text("注意"),
                  content: const Text("套用模板将清空当前已写的内容，确定吗？"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("取消")),
                    TextButton(
                        onPressed: () {
                          Navigator.pop(c);
                          _openPicker();
                        },
                        child: const Text("确定",
                            style: TextStyle(color: Colors.red)))
                  ]));
    } else
      _openPicker();
  }

  void _openPicker() {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => TemplatePicker(onSelect: (title, content, tags) {
              setState(() {
                titleController.text = title;
                contentController.text = content;
                tagsController.text = tags.join(" ");
              });
              _performAutoSave();
            }));
  }

  void _showSecurityMenu() {
    showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: Icon(
                      _isLocked ? Icons.lock_open : Icons.enhanced_encryption,
                      color: Colors.blue),
                  title: Text(_isLocked ? "解除加密锁定" : "启用 AES-256 加密锁定"),
                  onTap: () {
                    Navigator.pop(c);
                    _handleLockToggle();
                  }),
              ListTile(
                  leading: Icon(_isArchived ? Icons.unarchive : Icons.archive,
                      color: Colors.brown),
                  title: Text(_isArchived ? "取消归档" : "归档日记 (变为只读)"),
                  onTap: () {
                    setState(() {
                      _isArchived = !_isArchived;
                    });
                    _performAutoSave();
                    Navigator.pop(c);
                  })
            ])));
  }

  void _handleLockToggle() {
    if (_isLocked) {
      setState(() {
        _isLocked = false;
        _tempKey = null;
        _pwdHash = null;
      });
      _performAutoSave();
    } else {
      final ctrl = TextEditingController();
      showDialog(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text("设置加密密码"),
                  // 💡 替换的部分在这里：把单行的 TextField 换成了包含红字警告的 Column
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                          controller: ctrl,
                          obscureText: true,
                          autofocus: true,
                          decoration:
                              const InputDecoration(hintText: "请输入独立密码")),
                      const SizedBox(height: 12),
                      const Text("⚠️ 请务必牢记此密码！\n单篇加密无法通过密保找回，一旦遗忘将导致此日记永久丢失！",
                          style: TextStyle(
                              color: Colors.red, fontSize: 12, height: 1.4))
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("取消")),
                    TextButton(
                        onPressed: () {
                          if (ctrl.text.isNotEmpty) {
                            setState(() {
                              _isLocked = true;
                              _tempKey = ctrl.text;
                              _pwdHash =
                                  EncryptionService.hashPassword(ctrl.text);
                            });
                            _performAutoSave();
                            Navigator.pop(c);
                          }
                        },
                        child: const Text("锁定"))
                  ]));
    }
  }

  // 重大修复 1：直接获取当前日记所属月份的 assets 文件夹
  Future<String> _getAssetDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final root = p.join(appDir.path, 'MyDiary_Data');
    final date =
        DateTime.parse(_isUnknownDate ? "1900-01-01 00:00:00" : _creationDate);
    String yearMonth = "${date.year}-${date.month.toString().padLeft(2, '0')}";
    final dir = Directory(p.join(root, yearMonth, 'assets'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _saveMediaFile(String originalPath, String type) async {
    final assetDir = await _getAssetDir();
    
    // 💡 修复 4：直接在一开始就把名字命名为规范的“日期开头”格式
    final date = DateTime.parse(_isUnknownDate ? "1900-01-01 00:00:00" : _creationDate);
    String datePrefix = date.toString().substring(0, 10);
    // 过滤掉原名里可能导致系统崩溃的特殊符号
    String safeBaseName = p.basename(originalPath).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    // 生成标准唯一的文件名 (如：2026-03-31_16480000_photo.jpg)
    String newName = "${datePrefix}_${DateTime.now().millisecondsSinceEpoch}_$safeBaseName";
    
    final savedPath = p.join(assetDir, newName);
    
    // 1. 先安全地将原文件拷贝到日记的沙盒文件夹中
    await File(originalPath).copy(savedPath);

    // ================== 🧹 智能垃圾清理机制 ==================
    try {
      final tempDir = await getTemporaryDirectory();
      if (p.isWithin(tempDir.path, originalPath)) {
        await File(originalPath).delete();
        debugPrint("🗑️ 成功清理临时垃圾文件: $originalPath");
      }
    } catch (e) {
      debugPrint("临时文件清理失败: $e");
    }
    // ========================================================

    setState(() {
      _hasRealChanges = true;
      if (type == 'video' || type == 'live') {
        _videoPaths.add(savedPath);
      } else if (type == 'audio') {
        _audioPaths.add(savedPath);
      } else if (type == 'file') {
        _attachments.add(savedPath);
      } else {
        _imagePaths.add(savedPath);
      }
    });
    await _performAutoSave();
  }

  // 💡 新增：通用的权限请求与永久拒绝引导设置的辅助方法
  Future<bool> _requestPermission(Permission permission, String featureName) async {
    // 💡 隔离策略：桌面端不需要请求移动端的权限，直接放行
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return true;

    final status = await permission.status;
    if (status.isGranted) return true; // 一旦获得权限，不再重复询问

    final result = await permission.request();
    if (result.isGranted) return true;

    // 💡 优雅处理：如果用户永久拒绝了权限（或者点击了“不再询问”）
    if (result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('缺少 $featureName 权限'),
            content: Text('您已永久拒绝了 $featureName 权限。为了正常使用该功能，请前往系统设置中允许。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(c);
                  openAppSettings(); // 💡 唤起系统设置，引导用户去手动开启
                },
                child: const Text('去设置'),
              )
            ],
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('需要 $featureName 权限才能使用该功能')));
      }
    }
    return false;
  }

  Future<void> _fetchLocation() async {
    setState(() => _location = "正在定位...");

    // 💡 场景触发：只有在用户真的点击了“自动获取当前位置”时，才去申请定位权限！
    if (Platform.isAndroid || Platform.isIOS) {
      bool hasPermission = await _requestPermission(Permission.location, "定位");
      if (!hasPermission) {
        setState(() => _location = "定位权限未授予");
        return; // 用户拒绝了，直接终止后续定位逻辑
      }
    }

    // 1. 尝试调用原生定位 (桌面端或已授权的移动端)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        // 💡 删除了原有的 Geolocator.requestPermission() 冗余代码，完全交给 permission_handler 优雅接管
        Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 4)));
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1');
        final response = await http.get(url, headers: {
          'Accept-Language': 'zh-CN',
          'User-Agent': 'GrainBudsDiaryApp/1.0'
        }).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final address = data['address'];
          String city = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['county'] ??
              "未知城市";
          String suburb = address['suburb'] ?? address['neighbourhood'] ?? "";
          setState(() {
            _location = suburb.isNotEmpty ? "$city · $suburb" : city;_hasRealChanges = true;
          });
          await _performAutoSave();
          return;
        }
      }
    // 💡 就是这里！之前这里多了一个 }，现已修正
    } catch (_) {
      debugPrint("原生定位失败，切换至 IP 定位");
    }

    // 💡 2. 修复重点：优先使用国内高精度的免费 IP 定位 API (精确到区县)
    try {
      final ipUrl = Uri.parse('https://qifu-api.baidubce.com/info/pip');
      final ipResponse =
          await http.get(ipUrl).timeout(const Duration(seconds: 5));
      if (ipResponse.statusCode == 200) {
        // 确保中文解码正确
        final decodedBody = utf8.decode(ipResponse.bodyBytes);
        final data = jsonDecode(decodedBody);

        if (data['code'] == 'Success') {
          final prov = data['data']['prov'] ?? '';
          final city = data['data']['city'] ?? '';
          final district = data['data']['district'] ?? '';

          setState(() {
            _hasRealChanges = true;
            if (district.isNotEmpty && district != city) {
              _location = "$city · $district";
            } else {
              _location = city.isNotEmpty ? city : prov;
            }
          });
          await _performAutoSave();
          return;
        }
      }
    } catch (e) {
      debugPrint("国内IP定位失败: $e");
    }

    // 3. 最后备用：海外 IP 定位接口 (ip-api.com)
    try {
      final ipUrl = Uri.parse('http://ip-api.com/json/?lang=zh-CN');
      final ipResponse =
          await http.get(ipUrl).timeout(const Duration(seconds: 5));
      if (ipResponse.statusCode == 200) {
        final data = jsonDecode(ipResponse.body);
        if (data['status'] == 'success') {
          setState(() {
            _hasRealChanges = true;
            _location = "${data['regionName']} ${data['city']}";
          });
          await _performAutoSave();
          return;
        }
      }
    } catch (e) {
      debugPrint("海外IP定位失败: $e");
    }

    setState(() => _location = "定位失败，请手动输入");
  }

  void _handleLocationTap() {
    if (_isArchived) return;
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.my_location, color: Colors.teal),
                  title: const Text("自动获取当前位置"),
                  onTap: () {
                    Navigator.pop(c);
                    _fetchLocation();
                  }),
              ListTile(
                  leading:
                      const Icon(Icons.edit_location_alt, color: Colors.orange),
                  title: const Text("手动输入位置"),
                  onTap: () {
                    Navigator.pop(c);
                    _showManualLocationDialog();
                  }),
              if (_location != null &&
                  !_location!.contains("失败") &&
                  !_location!.contains("定位"))
                ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text("清除位置信息"),
                    onTap: () {
                      setState(() {
                        _location = null;_hasRealChanges = true;
                      });
                      _performAutoSave();
                      Navigator.pop(c);
                    })
            ])));
  }

  void _showManualLocationDialog() {
    String currentText = (_location == null ||
            _location!.contains("点击") ||
            _location!.contains("失败"))
        ? ""
        : _location!;
    final ctrl = TextEditingController(text: currentText);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text("手动修改位置"),
                content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: "例如：北京·三里屯", border: OutlineInputBorder())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("取消",
                          style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                      onPressed: () {
                        if (ctrl.text.trim().isNotEmpty) {
                          setState(() {
                            _location = ctrl.text.trim();_hasRealChanges = true;
                          });
                          _performAutoSave();
                        }
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white),
                      child: const Text("确定"))
                ]));
  }

  String _getAppBarTitle() {
    if (_isArchived) return "查看归档";
    if (widget.existingDiary != null) return "编辑";
    String prefix = "新";
    if (widget.selectedDate != null) {
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime sDay = DateTime(widget.selectedDate!.year,
          widget.selectedDate!.month, widget.selectedDate!.day);
      if (sDay.isBefore(today))
        prefix = "补写回忆 - ";
      else if (sDay.isAfter(today)) prefix = "写给未来 - ";
    }
    return "$prefix${widget.entryType == 1 ? '随手记' : '日记'}";
  }

  @override
  Widget build(BuildContext context) {
    // 💡 判断平台，用于加载不同的 UI 逻辑
    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    // =========================================================
    // 💡 A. Windows/Desktop 端：全新打造的极致宽屏体验
    // =========================================================
    if (isDesktop) {
      return PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _performAutoSave();
          setState(() { _canPop = true; });
          if (context.mounted) Future.microtask(() => Navigator.pop(context, true));
          _triggerSilentSync();
        },
        // 💡 修改 1：用 Stack 包裹原本的 DropTarget
        child: Stack(
          children: [
            DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() { _isDragging = false; });
                for (var xfile in details.files) {
                  String ext = p.extension(xfile.path).toLowerCase();
                  _saveMediaFile(xfile.path, ext == '.mp4' ? 'video' : (['.mp3', '.m4a'].contains(ext) ? 'audio' : 'image'));
                }
              },
              child: Scaffold(
                appBar: CustomTitleBar(
                  backgroundColor: _isDragging ? Colors.orange : (_isLocked ? Colors.indigo : Theme.of(context).primaryColor),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () async { await _performSaveAndPop(); },
                  ),
                  title: Text(_getAppBarTitle(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ) as PreferredSizeWidget,
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildWindowsHeader(),
                      Expanded(child: _buildEditor()),
                      
                      if (_videoPaths.isNotEmpty || _imagePaths.isNotEmpty || _audioPaths.isNotEmpty || _attachments.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          margin: const EdgeInsets.only(top: 10, bottom: 10),
                          child: SingleChildScrollView(child: _buildMediaDisplay()),
                        ),
                      
                      if (!_isArchived) const Divider(height: 1, color: Colors.black12),
                      _buildTextFormatBar(), 
                      const Divider(height: 1, color: Colors.black12),

                      _buildWindowsToolbar(),
                      _buildWindowsFooter(),
                    ],
                  ),
                ),
              ),
            ),
            // 💡 电脑端 AI 遮罩
            if (_isAILoading) _buildAILoadingOverlay(),
          ],
        ),
      );
    }

    // =========================================================
    // 💡 B. 手机端：继续保持极致的沉浸输入与键盘防遮挡
    // =========================================================
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performAutoSave();
        setState(() { _canPop = true; });
        if (context.mounted) Future.microtask(() => Navigator.pop(context, true));
        _triggerSilentSync();
      },
      // 💡 修改 2：用 Stack 包裹原本的 Scaffold
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              title: Text(_getAppBarTitle(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            body: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildHeader(),
                        const Divider(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildEditor(),
                    ),
                  ),
                  if (!isKeyboardOpen && (_videoPaths.isNotEmpty || _imagePaths.isNotEmpty || _audioPaths.isNotEmpty || _attachments.isNotEmpty))
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      margin: const EdgeInsets.only(top: 5, bottom: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(child: _buildMediaDisplay()),
                    ),
                  
                  if (!isDesktop && _showTextFormatBar) ...[
                    _buildTextFormatBar(),
                    const Divider(height: 1, color: Colors.black12),
                  ],
                  
                  _buildToolbar(),
                  if (!_isArchived && !isKeyboardOpen) const Divider(height: 1, color: Colors.black12),
                  if (!isKeyboardOpen) _buildFooter(),
                ],
              ),
            ),
          ),
          // 💡 手机端 AI 遮罩
          if (_isAILoading) _buildAILoadingOverlay(),
        ],
      ),
    );
  }

  // =======================================================
  // 💡 全局 AI 施法遮罩 UI
  // =======================================================
  Widget _buildAILoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6), 
        child: Center( // 💡 移除了这里的 const
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.amber), // 补上精确的 const
              const SizedBox(height: 20), // 补上精确的 const
              Text(
                _aiLoadingText, // 这是一个变量，所以它外面不能有 const
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  decoration: TextDecoration.none, 
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ========================================================================
  // 💡 以下 3 个是 Windows 桌面端专属的 UI 构建方法，与手机端完全隔离
  // ========================================================================

  Widget _buildWindowsHeader() {
    final date = DateTime.parse(_creationDate);
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateStr = "${DateFormat('yyyy-MM-dd').format(date)}  ${weekdays[date.weekday - 1]}";

    if (_creationDate.startsWith("1900-01-01")) {
      _isUnknownDate = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _isArchived ? null : _showDateOptions,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(_isUnknownDate ? "⏳ 岁月深处的回忆" : dateStr,
                        style: TextStyle(color: _isUnknownDate ? Colors.brown : Colors.grey, fontWeight: FontWeight.bold)),
                    if (!_isArchived)
                      const Padding(padding: EdgeInsets.only(left: 4.0), child: Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _handleLocationTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, size: 16, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(_location ?? "点击添加位置", style: TextStyle(fontSize: 13, color: Theme.of(context).primaryColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: titleController,
                enabled: !_isArchived,
                decoration: const InputDecoration(hintText: '无标题', border: InputBorder.none, contentPadding: EdgeInsets.zero),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 20),
            const Text("天气 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
            DropdownButton<String>(
                value: _selectedWeatherKey,
                underline: const SizedBox(),
                icon: const SizedBox(),
                items: AppConstants.weatherMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 18)))).toList(),
                onChanged: _isArchived ? null : (v) {
                  if (v != null) {
                    setState(() => _selectedWeatherKey = v);
                    _performAutoSave();
                  }
                }),
            const SizedBox(width: 20),
            const Text("心情 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
            DropdownButton<String>(
                value: _selectedMoodKey,
                underline: const SizedBox(),
                icon: const SizedBox(),
                items: AppConstants.moodMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 18)))).toList(),
                onChanged: _isArchived ? null : (v) {
                  if (v != null) {
                    setState(() => _selectedMoodKey = v);
                    _performAutoSave();
                  }
                }),
          ],
        ),
        TextField(
            controller: tagsController,
            enabled: !_isArchived,
            decoration: const InputDecoration(hintText: '#标签 (空格分隔)', border: InputBorder.none, contentPadding: EdgeInsets.zero),
            style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14)),
      ],
      
    );
  }

  Widget _buildWindowsToolbar() {
    if (_isArchived) return const SizedBox.shrink();
    return Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 4), 
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
          children: [
            IconButton(icon: const Icon(Icons.image_outlined, color: Colors.teal), tooltip: '选择图片', onPressed: () => _pickMedia('image')),
            IconButton(icon: const Icon(Icons.content_paste, color: Colors.teal), tooltip: '粘贴图片', onPressed: _checkAndPasteImage),
            IconButton(icon: const Icon(Icons.motion_photos_on_outlined, color: Colors.amber), tooltip: '插入 Live 图', onPressed: () => _pickMedia('live')),
            IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.teal), tooltip: '插入视频', onPressed: () => _pickMedia('video')),
            IconButton(
                icon: const Icon(Icons.mic_none_outlined, color: Colors.teal),
                tooltip: '添加语音',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
                    builder: (c) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.mic, color: Colors.redAccent),
                            title: const Text("录制新语音"),
                            onTap: () {
                              Navigator.pop(c);
                              showModalBottomSheet(context: context, builder: (c2) => VoiceRecorderDialog(onRecordComplete: (path) => _saveMediaFile(path, 'audio')));
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.audio_file, color: Colors.teal),
                            title: const Text("从电脑导入音频"),
                            onTap: () {
                              Navigator.pop(c);
                              _pickMedia('audio');
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            IconButton(icon: const Icon(Icons.attach_file_outlined, color: Colors.teal), tooltip: '添加附件', onPressed: () => _pickMedia('file')),
            IconButton(icon: const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent), tooltip: 'AI 写作魔法', onPressed: _showAIAssistantMenu),
          ]
        ));
  }

  Widget _buildWindowsFooter() {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: const [BoxShadow(color: Color.fromARGB(13, 0, 0, 0), blurRadius: 10, offset: Offset(0, -2))]
        ),
        child: Row(
          children: [
            Text("字数: $_wordCount", style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            if (_isLocked) 
              const Padding(
                padding: EdgeInsets.only(left: 12.0), 
                child: Text("🔒 AES-256 已加密", style: TextStyle(color: Colors.orange, fontSize: 12))
              ),
            Padding(
              padding: const EdgeInsets.only(left: 16.0), 
              child: Text(_saveStatusText, style: const TextStyle(fontSize: 12, color: Colors.grey))
            ),
            const Spacer(),
            if (!_isArchived) ...[
              IconButton(icon: const Icon(Icons.auto_awesome_motion, size: 20, color: Colors.teal), onPressed: _showTemplatePicker),
              const SizedBox(width: 8),
              IconButton(icon: Icon(_isLocked ? Icons.lock : Icons.security, size: 20, color: Colors.blueGrey), onPressed: _showSecurityMenu),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text("完成并保存", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _performSaveAndPop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ] else ...[
              TextButton.icon(icon: const Icon(Icons.unarchive, size: 18), label: const Text("取消归档/权限"), onPressed: _showSecurityMenu, style: TextButton.styleFrom(foregroundColor: Colors.blueGrey)),
              const SizedBox(width: 16),
              ElevatedButton(onPressed: _performSaveAndPop, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white), child: const Text("关闭")),
            ]
          ],
        ));
  }

  Widget _buildHeader() {
    // 💡 智能分流：如果是电脑端，返回原来的老头部；如果是手机，返回极致压缩的新头部
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return _buildDesktopHeader();
    }
    return _buildMobileHeader();
  }

  // =======================================================
  // 💡 Windows 端专属头部（保持您最初的原始面貌，消除未引用警告）
  // =======================================================
  Widget _buildDesktopHeader() {
    final date = DateTime.parse(_creationDate);
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateStr = "${DateFormat('yyyy-MM-dd').format(date)}  ${weekdays[date.weekday - 1]}";

    if (_creationDate.startsWith("1900-01-01")) {
      _isUnknownDate = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _isArchived ? null : _showDateOptions,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(_isUnknownDate ? "⏳ 岁月深处的回忆" : dateStr,
                        style: TextStyle(
                            color: _isUnknownDate ? Colors.brown : Colors.grey,
                            fontWeight: FontWeight.bold)),
                    if (!_isArchived)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child: Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _handleLocationTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, size: 16, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      _location ?? "点击添加位置",
                      style: TextStyle(fontSize: 13, color: Theme.of(context).primaryColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text("天气 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
            DropdownButton<String>(
                value: _selectedWeatherKey,
                underline: const SizedBox(),
                icon: const SizedBox(),
                items: AppConstants.weatherMap.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 18))))
                    .toList(),
                onChanged: _isArchived ? null : (v) {
                  if (v != null) {
                    setState(() { _selectedWeatherKey = v; _hasRealChanges = true; }); // 💡 天气加上
                    _performAutoSave();
                  }
                }),
            const SizedBox(width: 20),
            const Text("心情 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
            DropdownButton<String>(
                value: _selectedMoodKey,
                underline: const SizedBox(),
                icon: const SizedBox(),
                items: AppConstants.moodMap.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 18))))
                    .toList(),
                onChanged: _isArchived ? null : (v) {
                  if (v != null) {
                    setState(() { _selectedMoodKey = v; _hasRealChanges = true; }); // 💡 心情加上
                    _performAutoSave();
                  }
                }),
          ],
        ),
        TextField(
            controller: titleController,
            enabled: !_isArchived,
            decoration: const InputDecoration(hintText: '标题', border: InputBorder.none),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        TextField(
            controller: tagsController,
            enabled: !_isArchived,
            decoration: const InputDecoration(hintText: '#标签 (空格分隔)', border: InputBorder.none),
            style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14)),
      ],
    );
  }

  // =======================================================
  // 💡 手机端专属头部（极致压缩：标题、天气表情、心情表情、锁定放一行）
  // =======================================================
  Widget _buildMobileHeader() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: titleController,
                enabled: !_isArchived,
                decoration: const InputDecoration(
                  hintText: '无标题', border: InputBorder.none, contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            
            // 💡 天气表情 (向右靠拢，移除前缀文本)
            PopupMenuButton<String>(
              initialValue: _selectedWeatherKey,
              enabled: !_isArchived,
              onSelected: (v) {
                setState(() { _selectedWeatherKey = v; _hasRealChanges = true; }); // 💡 天气加上
                _performAutoSave();
              },
              itemBuilder: (c) => AppConstants.weatherMap.entries
                  .map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(AppConstants.getWeatherEmoji(_selectedWeatherKey), style: const TextStyle(fontSize: 22)),
              ),
            ),
            
            const SizedBox(width: 4),
            
            // 💡 心情表情 (向右靠拢，紧贴天气)
            PopupMenuButton<String>(
              initialValue: _selectedMoodKey,
              enabled: !_isArchived,
              onSelected: (v) {
                setState(() { _selectedMoodKey = v; _hasRealChanges = true; }); // 💡 心情加上
                _performAutoSave();
              },
              itemBuilder: (c) => AppConstants.moodMap.entries
                  .map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(AppConstants.getMoodEmoji(_selectedMoodKey), style: const TextStyle(fontSize: 22)),
              ),
            ),
            // 💡 已将右上角的冗余锁定图标删除！
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            GestureDetector(
              onTap: _isArchived ? null : _showDateOptions,
              child: Text(
                _isUnknownDate ? "⏳ 岁月深处" : _creationDate.substring(0, 10),
                style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _handleLocationTap,
                child: Text(
                  _location ?? '未添加定位',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

 Widget _buildEditor() {
    return TextField(
        focusNode: _contentFocusNode,
        controller: contentController,
        maxLines: null,
        expands: true, 
        textAlignVertical: TextAlignVertical.top,
        enabled: !_isArchived,
        keyboardType: TextInputType.multiline,

        scrollPadding: const EdgeInsets.only(bottom: 80),
        
        decoration: InputDecoration(
            hintText: _isArchived ? "内容已归档锁定" : "记录这一刻...",
            border: InputBorder.none,

            contentPadding: const EdgeInsets.only(bottom: 40, top: 10), 
        ),
        
        style: const TextStyle(fontSize: 16, fontFamily: 'Microsoft YaHei'),
    );
  }

  Widget _buildToolbar() {
    if (_isArchived) return const SizedBox.shrink();
    
    bool isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    
    return Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 4), 
        child: Row(
          mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.spaceEvenly, 
          children: [
            if (isDesktop) ...[
              Padding(
                padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("$_wordCount字", style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    Text(_saveStatusText, style: const TextStyle(fontSize: 9, color: Colors.grey)), 
                  ],
                ),
              ),
              const Spacer(), 
            ],
            
            // 💡 新增：手机端专属的第一个按钮 "T" (文字排版开关)
            if (!isDesktop)
              IconButton(
                icon: Icon(Icons.text_format, color: _showTextFormatBar ? Theme.of(context).primaryColor : Colors.blueGrey),
                onPressed: () {
                  setState(() => _showTextFormatBar = !_showTextFormatBar);
                  // 弹出菜单时确保输入框有焦点
                  if (_showTextFormatBar) FocusScope.of(context).requestFocus(_contentFocusNode);
                }
              ),

            IconButton(icon: const Icon(Icons.image_outlined, color: Colors.teal), tooltip: '选择图片', onPressed: () => _pickMedia('image')),
            
            // 💡 限制：剪贴板按钮仅电脑端可用
            if (isDesktop) 
              IconButton(icon: const Icon(Icons.content_paste, color: Colors.teal), tooltip: '粘贴图片', onPressed: _checkAndPasteImage),
            
            // IconButton(icon: const Icon(Icons.motion_photos_on_outlined, color: Colors.amber), tooltip: '插入 Live 图', onPressed: () => _pickMedia('live')),
            IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.teal), tooltip: '插入视频', onPressed: () => _pickMedia('video')),
            IconButton(
                icon: const Icon(Icons.mic_none_outlined, color: Colors.teal),
                tooltip: '添加语音',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
                    builder: (c) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(leading: const Icon(Icons.mic, color: Colors.redAccent), title: const Text("录制新语音"), onTap: () { Navigator.pop(c); showModalBottomSheet(context: context, builder: (c2) => VoiceRecorderDialog(onRecordComplete: (path) => _saveMediaFile(path, 'audio'))); }),
                          ListTile(leading: const Icon(Icons.audio_file, color: Colors.teal), title: const Text("导入音频"), onTap: () { Navigator.pop(c); _pickMedia('audio'); }),
                        ],
                      ),
                    ),
                  );
                }),
            IconButton(icon: const Icon(Icons.attach_file_outlined, color: Colors.teal), tooltip: '添加附件', onPressed: () => _pickMedia('file')),
            IconButton(icon: const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent), tooltip: 'AI 写作魔法', onPressed: _showAIAssistantMenu),

            if (!isDesktop)
              IconButton(
                icon: const Icon(Icons.keyboard_hide, color: Colors.grey),
                tooltip: '收起键盘',
                onPressed: () => FocusScope.of(context).unfocus(),
              ),
          ]
        ));
  }
  Widget _buildMediaDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (_videoPaths.isNotEmpty || _imagePaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ..._videoPaths.asMap().entries.map((entry) => _buildMediaItem(
                    path: entry.value,
                    isVideo: true,
                    onDelete: () => setState(() { _videoPaths.removeAt(entry.key); _hasRealChanges = true; }),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => FullScreenGallery(
                                images: _videoPaths,
                                initialIndex: entry.key))))),
                ..._imagePaths.asMap().entries.map((entry) => _buildMediaItem(
                    path: entry.value,
                    isVideo: false,
                    onDelete: () => setState(() { _imagePaths.removeAt(entry.key); _hasRealChanges = true; }),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => FullScreenGallery(
                                images: _imagePaths,
                                initialIndex: entry.key))))),
              ],
            ),
          ),


        if (_audioPaths.isNotEmpty)
          ..._audioPaths.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8), 
            child: Row(
              children: [
                Expanded(child: MiniAudioPlayer(audioPath: entry.value)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () {
                    setState(() { _audioPaths.removeAt(entry.key); _hasRealChanges = true; });
                    _performAutoSave(); // 删完立刻自动保存
                  }
                ),
              ],
            )
          )),
        
        if (_attachments.isNotEmpty)
          ..._attachments.asMap().entries.map((entry) => Card(
            child: ListTile(
              leading: const Icon(Icons.file_present), 
              title: Text(p.basename(entry.value)), 
              onTap: () => OpenFilex.open(entry.value),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  setState(() { _attachments.removeAt(entry.key); _hasRealChanges = true; }); // 💡 补上
                  _performAutoSave(); // 删完立刻自动保存
                }
              ),
            )
          )),
      ],
    );
  }

  Widget _buildMediaItem({
  required String path,
  required bool isVideo,
  required VoidCallback onDelete,
  required VoidCallback onTap,
}) {
  final bool isLive = path.toLowerCase().endsWith('.mp4') || path.toLowerCase().endsWith('.mov');
  
  return Stack(
    children: [
      GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center, 
            children: [
              // 💡 修复重点：将 errorBuilder 移入 Image.file 内部
              isVideo || isLive
                  ? LivePhotoThumbnail(videoPath: path, width: 100, height: 100)
                  : Image.file(
                      File(path),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      // ✅ 正确位置：作为 Image.file 的命名参数
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
              if (isVideo)
                Container(
                  width: 100,
                  height: 100,
                  color: Colors.black26,
                  child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 40),
                ),
            ],
          ),
        ),
      ),
      // 💡 Positioned 是外部 Stack 的子组件，用于显示右上角的删除按钮
      if (!_isArchived)
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: () {
              onDelete();
              _performAutoSave();
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
    ],
  );
}
  // ====================================================================
  // 💡 新增：静默触发 WebDAV 同步（完全不阻塞 UI，后台默默执行）
  // ====================================================================
  void _triggerSilentSync() {
    Future.microtask(() async {
      // 尝试自动连接，如果用户没在设置里配置过 WebDAV，这里会直接返回 false
      bool connected = await WebDavSyncService.instance.autoConnect();
      if (connected) {
        debugPrint("🚀 退出编辑页，开始后台静默 WebDAV 同步...");
        await WebDavSyncService.instance.startSync();
        debugPrint("✅ 后台静默 WebDAV 同步完成！");
      }
    });
  }

  Future<void> _performSaveAndPop() async {
    // 💡 退出前先强制杀掉定时器，确保所有保存逻辑都走这一行 await
    _debounceTimer?.cancel();
    await _performAutoSave();
    
    setState(() {
      _canPop = true;
    });
    if (mounted) Navigator.pop(context, true);
    _triggerSilentSync();
  }

  // ================= 💡 新增 & 修改：底部栏平台适配 =================



  Widget _buildFooter() {
    bool isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    
    return Container(
        // 💡 背景全宽拉满，内部内容保留 16 的边距以对齐文字
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: const [BoxShadow(color: Color.fromARGB(13, 0, 0, 0), blurRadius: 10, offset: Offset(0, -2))]
        ),
        child: Row(
          mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
          children: [
            // ==========================================
            // 左侧区域 (电脑端恢复原样 / 手机端显示字数)
            // ==========================================
            if (isDesktop) ...[
              Text("字数: $_wordCount", style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
              if (_isLocked) const Padding(padding: EdgeInsets.only(left: 12.0), child: Text("🔒 已加密", style: TextStyle(color: Colors.orange, fontSize: 12))),
              Padding(padding: const EdgeInsets.only(left: 16.0), child: Text(_saveStatusText, style: const TextStyle(fontSize: 12, color: Colors.grey))),
              const Spacer(),
            ] else ...[
              // 💡 手机端：字数和保存状态被转移到了最后一层的最左边
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("$_wordCount 字", style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  Text(_saveStatusText, style: const TextStyle(fontSize: 10, color: Colors.grey)), 
                ],
              ),
            ],

            // ==========================================
            // 右侧区域 (操作按钮组)
            // ==========================================
            if (!_isArchived) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.auto_awesome_motion, size: 20, color: Colors.teal), onPressed: _showTemplatePicker),
                  const SizedBox(width: 8),
                  IconButton(icon: Icon(_isLocked ? Icons.lock : Icons.security, size: 20, color: Colors.blueGrey), onPressed: _showSecurityMenu),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _performSaveAndPop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(isDesktop ? "完成并保存" : "完成", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(icon: const Icon(Icons.unarchive, size: 18), label: const Text("取消归档"), onPressed: _showSecurityMenu),
                  const SizedBox(width: 16),
                  ElevatedButton(onPressed: _performSaveAndPop, child: const Text("关闭")),
                ]
              )
            ]
          ],
        ));
  }

  // 💡 优化：智能分流，手机拉起相册，电脑拉起文件管理器
  Future<void> _pickMedia(String type) async {
    // ==========================================
    // 📱 手机端逻辑：使用 image_picker 访问原生相册
    // ==========================================
    if (Platform.isAndroid || Platform.isIOS) {
      final ImagePicker picker = ImagePicker();
      try {
        if (type == 'image' || type == 'live') {

          final List<XFile> images = await picker.pickMultiImage(
            imageQuality: 80, // 💡 适当压缩，提升处理速度
          );
          for (var img in images) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在处理...'), duration: Duration(milliseconds: 500)));
            await _saveMediaFile(img.path, 'image');
          }
        } else if (type == 'video') {
          final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
          if (video != null) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在处理...'), duration: Duration(milliseconds: 500)));
            await _saveMediaFile(video.path, 'video');
          }
        } else {
          // 音频和普通附件依然走文件管理器
          await _pickFilesFallback(type);
        }
      } catch (e) {
        debugPrint("打开相册失败: $e");
      }
      return;
    }

    // ==========================================
    // 💻 电脑端逻辑：直接走文件管理器
    // ==========================================
    await _pickFilesFallback(type);
  }

  // 抽离出来的电脑端/文件选择通用逻辑
  Future<void> _pickFilesFallback(String type) async {
    XTypeGroup typeGroup;
    if (type == 'video' || type == 'live') {
      typeGroup = const XTypeGroup(label: '视频文件', extensions: ['mp4', 'mov']);
    } else if (type == 'audio') {
      typeGroup = const XTypeGroup(label: '音频文件', extensions: ['mp3', 'm4a']);
    } else if (type == 'file') {
      typeGroup = const XTypeGroup(label: '文档附件', extensions: ['pdf', 'zip']);
    } else {
      typeGroup = const XTypeGroup(label: '图片文件', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp']);
    }

    try {
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在处理媒体文件...'), duration: Duration(milliseconds: 500)));
        await _saveMediaFile(file.path, type);
      }
    } catch (e) {
      debugPrint("取消选择或打开失败: $e");
    }
  }
  // =======================================================
  // 💡 ✨ AI 智能助手相关逻辑 ✨
  // =======================================================

  void _showAIAssistantMenu() {
    if (_isArchived) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text("✨ AI 写作魔法", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.mic_external_on, color: Colors.white, size: 20)),
              title: const Text("语音速记整理"),
              subtitle: const Text("录制语音，AI 自动去除废话并整理成排版清晰的文字", style: TextStyle(fontSize: 12)),
              onTap: () { Navigator.pop(c); _handleAIVoiceMemo(); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.title, color: Colors.white, size: 20)),
              title: const Text("帮我起标题"),
              subtitle: const Text("根据正文生成 3 个文艺标题供选择", style: TextStyle(fontSize: 12)),
              onTap: () { Navigator.pop(c); _handleAITTitle(); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.edit_document, color: Colors.white, size: 20)),
              title: const Text("润色扩写"),
              subtitle: const Text("将干瘪的流水账变身成有温度的故事", style: TextStyle(fontSize: 12)),
              onTap: () { Navigator.pop(c); _handleAIPolish(); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.sell, color: Colors.white, size: 20)),
              title: const Text("自动提取标签"),
              subtitle: const Text("理解文意，自动填入符合主题的 #标签", style: TextStyle(fontSize: 12)),
              onTap: () { Navigator.pop(c); _handleAITags(); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.pinkAccent, child: Icon(Icons.mood, color: Colors.white, size: 20)),
              title: const Text("推测心情与天气"),
              subtitle: const Text("从字里行间感受你的情绪并自动选择表情", style: TextStyle(fontSize: 12)),
              onTap: () { Navigator.pop(c); _handleAIMoodWeather(); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      )
    );
  }

  void _handleAITTitle() async {
    final content = contentController.text;
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("📝 请先写点正文再生成标题哦！")));
      return;
    }
    setState(() => _isAILoading = true);
    final titles = await AIService.generateTitles(content);
    setState(() => _isAILoading = false);

    if (titles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ 生成失败，请检查网络或配置")));
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text("请选择喜欢的标题", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...titles.map((t) => ListTile(
              leading: const Icon(Icons.lightbulb_outline, color: Colors.amber),
              title: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                setState(() { titleController.text = t; _hasRealChanges = true; });
                _performAutoSave();
                Navigator.pop(c);
              }
            )),
            const SizedBox(height: 10),
          ],
        )
      )
    );
  }

  void _handleAIPolish() async {
    final content = contentController.text;
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("📝 请先写点想润色的内容吧！")));
      return;
    }
    setState(() => _isAILoading = true);
    final newContent = await AIService.polishContent(content);
    setState(() => _isAILoading = false);

    if (newContent.contains("请求失败") || newContent.contains("异常") || newContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ $newContent")));
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [Icon(Icons.auto_awesome, color: Colors.amber), SizedBox(width: 8), Text("AI 润色预览")]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(newContent, style: const TextStyle(height: 1.6, fontSize: 15)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("放弃", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              setState(() { contentController.text = newContent; _hasRealChanges = true; });
              _performAutoSave();
              Navigator.pop(c);
            },
            child: const Text("替换原文")
          )
        ]
      )
    );
  }

  void _handleAITags() async {
    final content = contentController.text;
    if (content.trim().isEmpty) return;
    
    setState(() => _isAILoading = true);
    final tags = await AIService.extractTags(content);
    setState(() => _isAILoading = false);

    if (tags.isNotEmpty && !tags.contains("失败") && !tags.contains("异常")) {
      setState(() { 
         String oldTags = tagsController.text.trim();
         tagsController.text = oldTags.isEmpty ? tags : "$oldTags $tags";
         _hasRealChanges = true; 
      });
      _performAutoSave();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 标签已自动生成并补充")));
    }
  }

  void _handleAIMoodWeather() async {
    final content = contentController.text;
    if (content.trim().isEmpty) return;

    setState(() => _isAILoading = true);
    final result = await AIService.inferMoodWeather(content);
    setState(() => _isAILoading = false);
    
    if (result != null) {
      setState(() {
         if (AppConstants.moodMap.containsKey(result['mood'])) _selectedMoodKey = result['mood']!;
         if (AppConstants.weatherMap.containsKey(result['weather'])) _selectedWeatherKey = result['weather']!;
         _hasRealChanges = true;
      });
      _performAutoSave();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 心情与天气已自动匹配")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ 自动匹配失败，可能内容特征不够明显")));
    }
  }
  void _handleAIVoiceMemo() {
    if (_isArchived) return;
    
    // 拉起原有的录音面板
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (c2) => VoiceRecorderDialog(
        onRecordComplete: (path) async {
          // 💡 录音结束后，立刻进入全屏接管状态
          setState(() {
            _isAILoading = true;
            _aiLoadingText = "🎤 正在将语音转为文字...";
          });

          // 第一步：调用 Whisper 把音频转成毫无排版的碎碎念
          String rawText = await AIService.speechToText(path);

          if (rawText.contains("失败") || rawText.contains("异常") || rawText.trim().isEmpty) {
            setState(() => _isAILoading = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ $rawText")));
            return;
          }

          // 第二步：UI 提示改变，开始洗稿
          setState(() {
            _aiLoadingText = "✨ 正在剔除废话并智能排版...";
          });

          String organizedText = await AIService.organizeVoiceMemo(rawText);
          
          setState(() {
            _isAILoading = false;
            _aiLoadingText = "🪄 小满正在施展魔法..."; // 重置文案
          });

          if (organizedText.contains("失败") || organizedText.contains("异常") || organizedText.isEmpty) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ $organizedText")));
            return;
          }

          // 第三步：将整理好的完美文字插入编辑器
          if (mounted) {
            setState(() {
              String current = contentController.text;
              // 智能拼接：如果原来有内容，就空两行再追加；没有就直接填入
              contentController.text = current.trim().isEmpty ? organizedText : "$current\n\n$organizedText";
              _hasRealChanges = true;
            });
            _performAutoSave();
            ScaffoldMessenger.of(context).showSnackBar(
  SnackBar( // 去掉外层的 const
    content: const Text("✅ 语音速记已智能整理并插入正文"), // 把 const 给到固定的 Text
    backgroundColor: Colors.teal,
  )
);
          }
          
          try {
            File(path).delete();
          } catch (_) {}
        }
      )
    );
  }
}

class MiniAudioPlayer extends StatefulWidget {
  final String audioPath;
  const MiniAudioPlayer({super.key, required this.audioPath});
  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  static final ValueNotifier<String?> _globalPlayingPath = ValueNotifier<String?>(null);

  // 💡 彻底设为可空！不准它提前创建！
  Player? _player; 
  bool _isPlaying = false;
  bool _isInitialized = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _globalPlayingPath.addListener(_onGlobalPathChange);

    // 💡 延迟 450ms 后，才去真正申请内存创建引擎
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _initPlayer();
    });
  }

  void _onGlobalPathChange() {
    if (_globalPlayingPath.value != widget.audioPath && _isPlaying) {
      _player?.pause();
    }
  }

  Future<void> _initPlayer() async {
    try {
      if (!File(widget.audioPath).existsSync()) return;

      _player = Player(); // 💡 在这里才真正向系统申请播放器内存！

      _subscriptions.add(_player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }));
      _subscriptions.add(_player!.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }));
      _subscriptions.add(_player!.stream.position.listen((p) {
        if (mounted && p <= _duration) setState(() => _position = p);
      }));
      _subscriptions.add(_player!.stream.completed.listen((completed) {
        if (mounted && completed) {
          setState(() { _position = Duration.zero; _isPlaying = false; });
          if (_globalPlayingPath.value == widget.audioPath) _globalPlayingPath.value = null;
        }
      }));

      await _player!.open(Media(p.normalize(widget.audioPath)), play: false);
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("音频初始化失败: $e");
    }
  }

  @override
  void dispose() {
    _globalPlayingPath.removeListener(_onGlobalPathChange);
    for (var s in _subscriptions) { s.cancel(); }
    
    // 💡 安全销毁
    final p = _player;
    _player = null;
    if (p != null) Future.microtask(() => p.dispose());
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    double maxVal = _duration.inMilliseconds.toDouble();
    if (maxVal <= 0.0) maxVal = 1.0; 
    double currentVal = _position.inMilliseconds.toDouble().clamp(0.0, maxVal);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
              color: _isInitialized ? Theme.of(context).primaryColor : Colors.grey,
              size: 32,
            ),
            onPressed: !_isInitialized ? null : () async {
              try {
                if (_isPlaying) {
                  await _player?.pause();
                } else {
                  _globalPlayingPath.value = widget.audioPath;
                  if (_position >= _duration && _duration != Duration.zero) {
                    await _player?.seek(Duration.zero);
                  }
                  await _player?.play();
                }
              } catch (e) { debugPrint("播放操作失败: $e"); }
            }
          ),
          Text(_formatDuration(_position), style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          Expanded(
            child: Slider(
              activeColor: Theme.of(context).primaryColor,
              inactiveColor: Theme.of(context).primaryColor.withOpacity(0.2),
              max: maxVal,
              value: currentVal,
              onChanged: (!_isInitialized || _duration == Duration.zero) ? null : (v) {
                _player?.seek(Duration(milliseconds: v.toInt()));
              }
            )
          ),
          Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        ]
      ),
    );
  }
}

class LivePhotoThumbnail extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  const LivePhotoThumbnail({super.key, required this.videoPath, required this.width, required this.height});
  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  // 💡 彻底设为可空！
  Player? _player;
  VideoController? _controller;
  bool _isReady = false;
  bool _fileExists = true;

  @override
  void initState() {
    super.initState();
    _fileExists = File(widget.videoPath).existsSync();

    if (_fileExists) {
      // 💡 延迟创建
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) {
          _player = Player();
          _player!.setVolume(0);
          _player!.setPlaylistMode(PlaylistMode.loop);
          _controller = VideoController(_player!);
          _player!.open(Media(widget.videoPath));
          setState(() => _isReady = true);
        }
      });
    }
  }

  @override
  void dispose() {
    final p = _player;
    _player = null;
    if (p != null) Future.microtask(() => p.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_fileExists) {
      return Container(width: widget.width, height: widget.height, color: Colors.grey.shade200, child: const Icon(Icons.videocam_off, color: Colors.grey, size: 30));
    }
    // 💡 引擎没准备好之前，显示等待框
    if (!_isReady || _controller == null) {
      return Container(width: widget.width, height: widget.height, color: Colors.grey.shade100, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)));
    }
    return SizedBox(
        width: widget.width, height: widget.height,
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(fit: BoxFit.cover, child: SizedBox(width: widget.width, height: widget.height, child: Video(controller: _controller!, controls: NoVideoControls)))
        ]));
  }

}