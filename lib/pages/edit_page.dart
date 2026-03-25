import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../widgets/full_screen_gallery.dart';
import '../core/database_helper.dart';
import '../core/constants.dart'; // 💡 新增：引入状态码字典
import '../widgets/voice_recorder.dart';
import '../widgets/template_picker.dart';
import '../core/encryption_service.dart';
import '../widgets/custom_title_bar.dart';

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

class _DiaryEditPageState extends State<DiaryEditPage> {
  String? _location;
  bool _isUnknownDate = false; //新增：标记是否为不可考的回忆
  bool _canPop = false;

  final titleController = TextEditingController();
  final contentController = TextEditingController();
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
    titleController.addListener(_onDataChanged);
    contentController.addListener(_onDataChanged);
    tagsController.addListener(_onDataChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    titleController.dispose();
    contentController.dispose();
    _contentFocusNode.dispose();
    tagsController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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
                setState(() => _isUnknownDate = !_isUnknownDate);
                _performAutoSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // 1. Ctrl + V (粘贴图片)
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
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
          setState(() => _imagePaths.add(savedPath));
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
      if (d['videoPaths'] != null) {
        try {
          _videoPaths.addAll(List<String>.from(jsonDecode(d['videoPaths'])));
        } catch (_) {}
      } else if (d['videoPath'] != null) {
        _videoPaths.add(d['videoPath'] as String);
      }

      if (d['audioPaths'] != null) {
        try {
          _audioPaths.addAll(List<String>.from(jsonDecode(d['audioPaths'])));
        } catch (_) {}
      } else if (d['audioPath'] != null) {
        _audioPaths.add(d['audioPath'] as String);
      }

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

      if (d['imagePath'] != null) {
        try {
          _imagePaths.addAll(List<String>.from(jsonDecode(d['imagePath'])));
        } catch (_) {}
      }
      if (d['attachments'] != null) {
        try {
          _attachments.addAll(List<String>.from(jsonDecode(d['attachments'])));
        } catch (_) {}
      }
      _imagePaths.removeWhere((path) => path.trim().isEmpty);
      _videoPaths.removeWhere((path) => path.trim().isEmpty);
      _audioPaths.removeWhere((path) => path.trim().isEmpty);
      _attachments.removeWhere((path) => path.trim().isEmpty);
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
        if (sDay.isBefore(today))
          tagsController.text = "回忆 ";
        else if (sDay.isAfter(today)) tagsController.text = "期许 ";
      } else {
        _creationDate = DateTime.now().toString();
      }
    }
  }

  void _onDataChanged() {
    _updateWordCount();
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
    if (titleController.text.isEmpty && contentController.text.isEmpty) return;
    if (mounted) setState(() => _saveStatusText = "保存中...");
    String finalContent = contentController.text;
    if (_isLocked && _tempKey != null) {
      finalContent = EncryptionService.encrypt(finalContent, _tempKey!);
    }
    final Map<String, dynamic> diaryData = {
      'title': titleController.text, 'content': finalContent,
      'date': _isUnknownDate ? "1900-01-01 00:00:00" : _creationDate,
      // 💡 升级 1：告诉数据库，我们现在存的是无限音视频数组 (加了s)
      'imagePath': jsonEncode(_imagePaths),
      'videoPaths': jsonEncode(_videoPaths),
      'audioPaths': jsonEncode(_audioPaths),
      'attachments': jsonEncode(_attachments),
      // 💡 存入数据库的只有干净的状态码
      'weather': _selectedWeatherKey, 'mood': _selectedMoodKey,
      'tags': jsonEncode(tagsController.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList()),
      'is_locked': _isLocked ? 1 : 0, 'is_archived': _isArchived ? 1 : 0,
      'pwd_hash': _pwdHash, 'location': _location,
      'type': widget.existingDiary?['type'] ?? widget.entryType,
    };
    if (_currentDiaryId == null) {
      _currentDiaryId = await DatabaseHelper.instance.insertDiary(diaryData);
    } else {
      diaryData['id'] = _currentDiaryId;
      await DatabaseHelper.instance.updateDiary(diaryData);
    }
    if (mounted)
      setState(() => _saveStatusText =
          "已保存 ${DateFormat('HH:mm').format(DateTime.now())}");
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

  // 💡 修复 2：将媒体文件直接写入 assets 文件夹，拒绝 Documents 污染
  Future<void> _saveMediaFile(String originalPath, String type) async {
    final assetDir = await _getAssetDir();
    final savedPath = p.join(assetDir,
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(originalPath)}');
    await File(originalPath).copy(savedPath);
    setState(() {
      // 💡 升级 2：使用 .add() 把新文件追加到列表中，不再互相覆盖！
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

  Future<void> _fetchLocation() async {
    setState(() => _location = "正在定位...");

    // 1. 尝试调用 Windows 原生定位 (依赖 Wi-Fi 和系统定位权限)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
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
              _location = suburb.isNotEmpty ? "$city · $suburb" : city;
            });
            await _performAutoSave();
            return;
          }
        }
      }
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
                        _location = null;
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
                            _location = ctrl.text.trim();
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
    return prefix + (widget.entryType == 1 ? "随手记" : "日记");
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 修复：使用动态变量控制是否允许退出
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performAutoSave();
        
        // 修复：保存完成后，把锁打开，并重新触发退出
        setState(() { _canPop = true; });
        if (context.mounted) {
          Future.microtask(() => Navigator.pop(context, true));
        }
      },
      child: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          setState(() {
            _isDragging = false;
          });
          for (var xfile in details.files) {
            String ext = p.extension(xfile.path).toLowerCase();
            _saveMediaFile(
                xfile.path,
                ext == '.mp4'
                    ? 'video'
                    : (['.mp3', '.m4a'].contains(ext) ? 'audio' : 'image'));
          }
        },
        

        child: Scaffold(
          appBar: CustomTitleBar(
              backgroundColor: _isDragging ? Colors.orange : (_isLocked ? Colors.indigo : Theme.of(context).primaryColor),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  await _performAutoSave();
                  setState(() { _canPop = true; });
                  if (context.mounted) Navigator.pop(context, true);
                },
              ),
              title: Text(_getAppBarTitle(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            body: Column(
            children: [
              // 💡 修复：使用 GestureDetector 包裹，点击下方的空白处也能呼出光标
              // 💡 终极修复：放弃全局滚动，改为专业的分栏布局，彻底根除输入法定位 Bug！
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildHeader(), // 头部信息（标题、日期等）固定在上方
                      const Divider(),
                      
                      // 💡 核心：输入框独占并撑满中间区域，内部独立滚动！这样 Windows 就能精准计算坐标了！
                      Expanded(
                        child: _buildEditor(),
                      ),
                      
                      // 媒体展示区移到底部，限制高度，独立滚动，绝不抢占输入框的视野
                      if (_videoPaths.isNotEmpty || _imagePaths.isNotEmpty || _audioPaths.isNotEmpty || _attachments.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          margin: const EdgeInsets.only(top: 10, bottom: 10),
                          child: SingleChildScrollView(
                            child: _buildMediaDisplay(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!_isArchived) const Divider(height: 1, color: Colors.black12),
              _buildToolbar(),
              _buildFooter(),
            ],
          ),
        ),
      ),
      );
  }

  Widget _buildHeader() {
    // 解析真实时间
    final date = DateTime.parse(_creationDate);
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final dateStr =
        "${DateFormat('yyyy-MM-dd').format(date)}  ${weekdays[date.weekday - 1]}";

    if (_creationDate.startsWith("1900-01-01")) _isUnknownDate = true;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 🌟 第一行：日期（左侧） + 定位（右侧）
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _isArchived ? null : _showDateOptions, // 点击呼出菜单
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
                    child: Icon(Icons.keyboard_arrow_down,
                        size: 16, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),

        // 定位按钮 (靠右对齐)
        GestureDetector(
          onTap: _handleLocationTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on,
                  size: 16, color: Theme.of(context).primaryColor),
              const SizedBox(width: 4),
              Container(
                constraints:
                    const BoxConstraints(maxWidth: 130), // 限制最大宽度，防止地名太长溢出
                child: Text(
                  _location ?? "点击添加位置",
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).primaryColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ]),

      const SizedBox(height: 8),

      // 🌟 第二行：天气 + 心情（增加了前缀文字，并去掉了丑陋的下划线）
      Row(
        children: [
          const Text("天气 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
          DropdownButton<String>(
              value: _selectedWeatherKey,
              underline: const SizedBox(), // 去掉下划线
              icon: const SizedBox(), // 去掉下拉箭头
              items: AppConstants.weatherMap.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child:
                          Text(e.value, style: const TextStyle(fontSize: 18))))
                  .toList(),
              onChanged: _isArchived
                  ? null
                  : (v) => setState(() => _selectedWeatherKey = v!)),

          const SizedBox(width: 20), // 两个选项之间拉开一点距离

          const Text("心情 ", style: TextStyle(fontSize: 13, color: Colors.grey)),
          DropdownButton<String>(
              value: _selectedMoodKey,
              underline: const SizedBox(),
              icon: const SizedBox(),
              items: AppConstants.moodMap.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child:
                          Text(e.value, style: const TextStyle(fontSize: 18))))
                  .toList(),
              onChanged: _isArchived
                  ? null
                  : (v) => setState(() => _selectedMoodKey = v!))
        ],
      ),

      // 🌟 标题与标签输入框
      TextField(
          controller: titleController,
          enabled: !_isArchived,
          decoration:
              const InputDecoration(hintText: '标题', border: InputBorder.none),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

      TextField(
          controller: tagsController,
          enabled: !_isArchived,
          decoration: const InputDecoration(
              hintText: '#标签 (空格分隔)', border: InputBorder.none),
          style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14))
    ]);
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
    return Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.teal),
              tooltip: '选择图片',
              onPressed: () => _pickMedia('image')),
          IconButton(
              icon: const Icon(Icons.content_paste, color: Colors.teal),
              tooltip: '粘贴截图或复制的图片',
              onPressed: _checkAndPasteImage),
          IconButton(
              icon: const Icon(Icons.motion_photos_on_outlined,
                  color: Colors.amber),
              tooltip: '插入 Live 图',
              onPressed: () => _pickMedia('live')),
          IconButton(
              icon: const Icon(Icons.videocam_outlined, color: Colors.teal),
              tooltip: '插入视频',
              onPressed: () => _pickMedia('video')),
          // 优化 2：聚合录音和导入音频功能
          IconButton(
              icon: const Icon(Icons.mic_none_outlined, color: Colors.teal),
              tooltip: '添加语音或音频文件',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(15))),
                  builder: (c) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading:
                              const Icon(Icons.mic, color: Colors.redAccent),
                          title: const Text("录制新语音"),
                          subtitle: const Text("使用麦克风实时录制闪念"),
                          onTap: () {
                            Navigator.pop(c);
                            showModalBottomSheet(
                                context: context,
                                builder: (c2) => VoiceRecorderDialog(
                                    onRecordComplete: (path) =>
                                        _saveMediaFile(path, 'audio')));
                          },
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.audio_file, color: Colors.teal),
                          title: const Text("从电脑导入音频文件"),
                          subtitle: const Text("支持 MP3, M4A 等本地音频格式"),
                          onTap: () {
                            Navigator.pop(c);
                            _pickMedia('audio'); // 完美复用底层已有的 _pickMedia 逻辑
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
          IconButton(
              icon: const Icon(Icons.attach_file_outlined, color: Colors.teal),
              tooltip: '添加附件',
              onPressed: () => _pickMedia('file'))
        ]));
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
                    onDelete: () =>
                        setState(() => _videoPaths.removeAt(entry.key)),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => FullScreenGallery(
                                images: _videoPaths,
                                initialIndex: entry.key))))),
                ..._imagePaths.asMap().entries.map((entry) => _buildMediaItem(
                    path: entry.value,
                    isVideo: false,
                    onDelete: () =>
                        setState(() => _imagePaths.removeAt(entry.key)),
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
                    setState(() => _audioPaths.removeAt(entry.key));
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
                  setState(() => _attachments.removeAt(entry.key));
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

  Future<void> _performSaveAndPop() async {
    await _performAutoSave();
    setState(() {
      _canPop = true;
    });
    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildFooter() {
    return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // 稍微增加点高度
        decoration:
            BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ]),
        child: Row(
          children: [
            // 左侧信息区：字数 + 加密状态 + 保存状态
            Text("字数: $_wordCount",
                style: const TextStyle(
                    color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            if (_isLocked)
              const Padding(
                padding: EdgeInsets.only(left: 12.0),
                child: Text("🔒 AES-256 已加密",
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text(_saveStatusText,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),

            const Spacer(),

            // 💡 优化 3：把顶部拥挤的按钮全部移到底部，形成专业级的操作底栏
            if (!_isArchived) ...[
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome_motion, size: 18),
                label: const Text("套用模板"),
                onPressed: _showTemplatePicker,
                style: TextButton.styleFrom(foregroundColor: Colors.teal),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: Icon(_isLocked ? Icons.lock : Icons.security, size: 18),
                label: Text(_isLocked ? "解除加密" : "加密/归档"),
                onPressed: _showSecurityMenu,
                style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
              ),
              const SizedBox(width: 16),
              // 主操作按钮：完成并保存
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text("完成并保存",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _performSaveAndPop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ] else ...[
              // 归档状态下，只显示解锁和关闭
              TextButton.icon(
                icon: const Icon(Icons.unarchive, size: 18),
                label: const Text("取消归档/权限"),
                onPressed: _showSecurityMenu,
                style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 18),
                label: const Text("关 闭"),
                onPressed: _performSaveAndPop,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white),
              ),
            ]
          ],
        ));
  }

  // 💡 优化：移除会导致线程焦点丢失的 Future.delayed，并严格遵守 Windows 规范加上 label
  Future<void> _pickMedia(String type) async {
    XTypeGroup typeGroup;

    // 💡 修复：必须加上 label 属性，否则 Windows 必崩溃
    if (type == 'video' || type == 'live') {
      typeGroup = const XTypeGroup(label: '视频文件', extensions: ['mp4', 'mov']);
    } else if (type == 'audio') {
      typeGroup = const XTypeGroup(label: '音频文件', extensions: ['mp3', 'm4a']);
    } else if (type == 'file') {
      typeGroup = const XTypeGroup(label: '文档附件', extensions: ['pdf', 'zip']);
    } else {
      typeGroup = const XTypeGroup(
          label: '图片文件', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp']);
    }

    try {
      // 直接呼出系统原生窗口，绝对不能用 await Future.delayed 挂起线程
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

      if (file != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('正在处理媒体文件...'),
              duration: Duration(milliseconds: 500)));
        }
        await _saveMediaFile(file.path, type);
      }
    } catch (e) {
      // 增加容错保护，防止用户在弹窗时强制关掉窗口导致异常
      debugPrint("取消选择或打开失败: $e");
    }
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