import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

// 💡 核心修复 1：隐藏 media_kit 里的 PlayerState，解决名字冲突！
import 'package:media_kit/media_kit.dart' hide PlayerState;
// 💡 核心修复 2：加上这行，Video 和 VideoController 就全都能识别了！
import 'package:media_kit_video/media_kit_video.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:desktop_drop/desktop_drop.dart'; 
import 'package:pasteboard/pasteboard.dart';    
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; 

import '../widgets/full_screen_gallery.dart';
import '../core/database_helper.dart'; 
import '../main.dart';            
import '../widgets/voice_recorder.dart';
import '../widgets/template_picker.dart'; 
import '../core/encryption_service.dart';

// ... 下面保留你原本的 class DiaryEditPage extends StatefulWidget { ...

class DiaryEditPage extends StatefulWidget {
  final Map<String, dynamic>? existingDiary;
  final int entryType; 
  final DateTime? selectedDate; 
  
  const DiaryEditPage({super.key, this.existingDiary, this.entryType = 0, this.selectedDate});

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> {
  String? _location; 

  final titleController = TextEditingController();
  final contentController = TextEditingController();
  final tagsController = TextEditingController();
  final AudioPlayer _typingPlayer = AudioPlayer();

  final List<String> _imagePaths = [];
  final List<String> _attachments = []; 
  String? _videoPath;
  String? _audioPath; 
  
  bool _isDragging = false; 
  String _selectedWeather = "☀️";
  String _selectedMood = "😊";
  final List<String> weathers = ["☀️", "☁️", "🌧️", "❄️", "🌩️"];
  final List<String> moods = ["😊", "😄", "😔", "😠", "😴"];

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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

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

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
        _checkAndPasteImage();
      }
    }
    return false; 
  }

  Future<void> _checkAndPasteImage() async {
    if (_isArchived) {
      return;
    }
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
          final appDir = await getApplicationDocumentsDirectory();
          final savedPath = p.join(appDir.path, 'PASTE_${DateTime.now().millisecondsSinceEpoch}.png');
          await File(savedPath).writeAsBytes(imageBytes);
          
          setState(() {
            _imagePaths.add(savedPath);
          });
          await _performAutoSave();
          hasPasted = true;
        }
      }

      // 💡 修复警告：使用 context.mounted 判断
      if (!context.mounted) {
        return;
      }
      
      if (hasPasted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📎 成功粘贴图片！'), duration: Duration(seconds: 2)));
      } else {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板中没有发现图片'), duration: Duration(seconds: 1)));
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
        try { 
          _imagePaths.addAll(List<String>.from(jsonDecode(d['imagePath']))); 
        } catch(_) {} 
      }
      if (d['attachments'] != null) { 
        try { 
          _attachments.addAll(List<String>.from(jsonDecode(d['attachments']))); 
        } catch(_) {} 
      }
      if (d['tags'] != null) { 
        try { 
          tagsController.text = List<String>.from(jsonDecode(d['tags'])).join(" "); 
        } catch(_) {} 
      }
      _updateWordCount();
    } else {
      if (widget.selectedDate != null) {
        DateTime now = DateTime.now();
        _creationDate = DateTime(
          widget.selectedDate!.year, widget.selectedDate!.month, widget.selectedDate!.day,
          now.hour, now.minute, now.second
        ).toString();
        
        DateTime today = DateTime(now.year, now.month, now.day);
        DateTime sDay = DateTime(widget.selectedDate!.year, widget.selectedDate!.month, widget.selectedDate!.day);
        
        if (sDay.isBefore(today)) {
          tagsController.text = "回忆 ";
        } else if (sDay.isAfter(today)) {
          tagsController.text = "期许 ";
        }
      } else {
        _creationDate = DateTime.now().toString();
      }
    }
    _lastTextLength = contentController.text.length;
  }

  void _onDataChanged() {
    if (globalEnableTypingSound && contentController.text.length > _lastTextLength) {
      _typingPlayer.play(AssetSource('sounds/click.mp3'), volume: 0.5).catchError((_){});
    }
    _lastTextLength = contentController.text.length;
    _updateWordCount(); 

    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }
    setState(() { 
      _saveStatusText = "正在输入..."; 
    });
    _debounceTimer = Timer(const Duration(seconds: 2), () => _performAutoSave());
  }

  void _updateWordCount() {
    setState(() {
      _wordCount = contentController.text.replaceAll(RegExp(r'\s+'), '').length;
    });
  }

  Future<void> _performAutoSave() async {
    if (titleController.text.isEmpty && contentController.text.isEmpty) {
      return;
    }
    // 注意：setState 不涉及 context，所以用 mounted 是安全的
    if (mounted) {
      setState(() { 
        _saveStatusText = "保存中..."; 
      });
    }

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

    if (mounted) {
      setState(() { 
        _saveStatusText = "已保存 ${DateFormat('HH:mm').format(DateTime.now())}"; 
      });
    }
  }

  void _showTemplatePicker() {
    if (_isArchived) {
      return;
    }
    if (contentController.text.isNotEmpty || titleController.text.isNotEmpty) {
      showDialog(
        context: context, 
        builder: (c) => AlertDialog(
          title: const Text("注意"), 
          content: const Text("套用模板将清空当前已写的内容，确定吗？"), 
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c), 
              child: const Text("取消")
            ), 
            TextButton(
              onPressed: () { 
                Navigator.pop(c); 
                _openPicker(); 
              }, 
              child: const Text("确定", style: TextStyle(color: Colors.red))
            )
          ],
        )
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
        }
      )
    );
  }

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
              onTap: () { 
                Navigator.pop(c); 
                _handleLockToggle(); 
              }
            ), 
            ListTile(
              leading: Icon(_isArchived ? Icons.unarchive : Icons.archive, color: Colors.brown), 
              title: Text(_isArchived ? "取消归档" : "归档日记 (变为只读)"), 
              onTap: () { 
                setState(() {
                  _isArchived = !_isArchived;
                }); 
                _performAutoSave(); 
                Navigator.pop(c); 
              }
            )
          ]
        )
      )
    );
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
          content: TextField(
            controller: ctrl, 
            obscureText: true, 
            decoration: const InputDecoration(hintText: "此密码仅用于本篇")
          ), 
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c), 
              child: const Text("取消")
            ), 
            TextButton(
              onPressed: () { 
                if (ctrl.text.isNotEmpty) { 
                  setState(() { 
                    _isLocked = true; 
                    _tempKey = ctrl.text; 
                    _pwdHash = EncryptionService.hashPassword(ctrl.text); 
                  }); 
                  _performAutoSave(); 
                  Navigator.pop(c); 
                } 
              }, 
              child: const Text("锁定")
            )
          ]
        )
      );
    }
  }

  Future<void> _saveMediaFile(String originalPath, String type) async {
    final appDir = await getApplicationDocumentsDirectory();
    final savedPath = p.join(appDir.path, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(originalPath)}');
    await File(originalPath).copy(savedPath);
    setState(() { 
      if (type == 'video') {
        _videoPath = savedPath; 
      } else if (type == 'audio') {
        _audioPath = savedPath;
      } else if (type == 'file') {
        _attachments.add(savedPath);
      } else {
        _imagePaths.add(savedPath); 
      }
    });
    await _performAutoSave();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _location = "正在定位...";
    });
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 4), 
            ),
          );
          final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1');
          final response = await http.get(url, headers: {'Accept-Language': 'zh-CN', 'User-Agent': 'GrainBudsDiaryApp/1.0'}).timeout(const Duration(seconds: 4));
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final address = data['address'];
            String city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'] ?? "未知城市";
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

    try {
      final ipUrl = Uri.parse('http://ip-api.com/json/?lang=zh-CN');
      final ipResponse = await http.get(ipUrl).timeout(const Duration(seconds: 5));
      if (ipResponse.statusCode == 200) {
        final data = jsonDecode(ipResponse.body);
        if (data['status'] == 'success') {
          String city = data['city'] ?? "";
          String region = data['regionName'] ?? "";
          setState(() { 
            _location = "$region $city"; 
          });
          await _performAutoSave();
          return; 
        }
      }
    } catch (e) { 
      debugPrint("IP定位失败: $e"); 
    }
    
    setState(() {
      _location = "定位失败，请手动输入";
    });
  }

  void _handleLocationTap() {
    if (_isArchived) {
      return;
    }
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))), 
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            ListTile(
              leading: const Icon(Icons.my_location, color: Colors.teal), 
              title: const Text("自动获取当前位置"), 
              onTap: () { 
                Navigator.pop(c); 
                _fetchLocation(); 
              }
            ), 
            ListTile(
              leading: const Icon(Icons.edit_location_alt, color: Colors.orange), 
              title: const Text("手动输入位置"), 
              onTap: () { 
                Navigator.pop(c); 
                _showManualLocationDialog(); 
              }
            ), 
            if (_location != null && !_location!.contains("失败") && !_location!.contains("定位")) 
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red), 
                title: const Text("清除位置信息"), 
                onTap: () { 
                  setState(() {
                    _location = null;
                  }); 
                  _performAutoSave(); 
                  Navigator.pop(c); 
                }
              )
          ]
        )
      )
    );
  }

  void _showManualLocationDialog() {
    String currentText = (_location == null || _location!.contains("点击") || _location!.contains("失败")) ? "" : _location!;
    final ctrl = TextEditingController(text: currentText);
    showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("手动修改位置"), 
        content: TextField(
          controller: ctrl, 
          autofocus: true, 
          decoration: const InputDecoration(hintText: "例如：北京·三里屯", border: OutlineInputBorder())
        ), 
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c), 
            child: const Text("取消", style: TextStyle(color: Colors.grey))
          ), 
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white), 
            child: const Text("确定")
          )
        ]
      )
    );
  }

  String _getAppBarTitle() {
    if (_isArchived) {
      return "查看归档";
    }
    if (widget.existingDiary != null) {
      return "编辑";
    }
    
    String prefix = "新";
    if (widget.selectedDate != null) {
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime sDay = DateTime(widget.selectedDate!.year, widget.selectedDate!.month, widget.selectedDate!.day);
      if (sDay.isBefore(today)) {
        prefix = "补写回忆 - ";
      } else if (sDay.isAfter(today)) {
        prefix = "写给未来 - ";
      }
    }
    return prefix + (widget.entryType == 1 ? "随手记" : "日记");
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _performAutoSave();
        // 💡 修复警告：验证 context
        if (!context.mounted) {
          return;
        }
        Navigator.pop(context, true);
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
            _saveMediaFile(xfile.path, ext == '.mp4' ? 'video' : (['.mp3','.m4a'].contains(ext) ? 'audio' : 'image'));
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_getAppBarTitle()), 
            backgroundColor: _isDragging ? Colors.orange : (_isLocked ? Colors.indigo : Colors.teal),
            foregroundColor: Colors.white,
            actions: [
              Center(child: Text(_saveStatusText, style: const TextStyle(fontSize: 10, color: Colors.white70))),
              IconButton(icon: const Icon(Icons.auto_awesome_motion), tooltip: '套用模板', onPressed: _isArchived ? null : _showTemplatePicker),
              IconButton(icon: Icon(_isLocked ? Icons.lock : (_isArchived ? Icons.archive : Icons.security)), onPressed: _showSecurityMenu),
              IconButton(icon: const Icon(Icons.check), onPressed: () async { 
                await _performAutoSave(); 
                // 💡 修复警告：验证 context
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(context, true); 
              }),
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
            GestureDetector(
              onTap: _isArchived ? null : _handleLocationTap,
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
            DropdownButton<String>(
              value: _selectedWeather, 
              items: weathers.map((w)=>DropdownMenuItem(value: w, child: Text(w))).toList(), 
              onChanged: _isArchived ? null : (v) {
                setState(() {
                  _selectedWeather = v!;
                });
              }
            ),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _selectedMood, 
              items: moods.map((m)=>DropdownMenuItem(value: m, child: Text(m))).toList(), 
              onChanged: _isArchived ? null : (v) {
                setState(() {
                  _selectedMood = v!;
                });
              }
            ),
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
      scrollPadding: const EdgeInsets.only(bottom: 150),
      decoration: InputDecoration(hintText: _isArchived ? "内容已归档锁定" : "记录这一刻...", border: InputBorder.none),
      style: const TextStyle(fontSize: 16, height: 1.6),
    );
  }

 Widget _buildToolbar() {
    if (_isArchived) {
      return const SizedBox.shrink();
    }
    return Container(
      color: Theme.of(context).cardColor, 
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.image_outlined, color: Colors.teal), tooltip: '选择图片', onPressed: () => _pickMedia('image')),
          IconButton(icon: const Icon(Icons.content_paste, color: Colors.teal), tooltip: '粘贴截图或复制的图片', onPressed: _checkAndPasteImage),
          IconButton(icon: const Icon(Icons.motion_photos_on_outlined, color: Colors.amber), tooltip: '插入 Live 图', onPressed: () => _pickMedia('live')),
          IconButton(icon: const Icon(Icons.videocam_outlined, color: Colors.teal), tooltip: '插入视频', onPressed: () => _pickMedia('video')),
          IconButton(icon: const Icon(Icons.mic_none_outlined, color: Colors.teal), tooltip: '录音', onPressed: () { 
            showModalBottomSheet(
              context: context, 
              builder: (c) => VoiceRecorderDialog(
                onRecordComplete: (path) => _saveMediaFile(path, 'audio')
              )
            ); 
          }),
          IconButton(icon: const Icon(Icons.attach_file_outlined, color: Colors.teal), tooltip: '添加附件', onPressed: () => _pickMedia('file')),
        ],
      ),
    );
  }
  
  Widget _buildMediaDisplay() {
    // 💡 构造一个混合媒体列表，将图片和视频放在一起处理
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_audioPath != null) MiniAudioPlayer(audioPath: _audioPath!),
        if (_attachments.isNotEmpty) ..._attachments.map((path) => Card(child: ListTile(leading: const Icon(Icons.file_present), title: Text(p.basename(path)), onTap: () => OpenFilex.open(path)))),
        const SizedBox(height: 10),
        
        // 💡 统一的媒体展示区域
        Wrap(
          spacing: 12, 
          runSpacing: 12, 
          children: [
            // 1. 处理视频缩略图 (如果存在)
            if (_videoPath != null)
              _buildMediaItem(
                path: _videoPath!, 
                isVideo: true, 
                onDelete: () => setState(() => _videoPath = null),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FullScreenGallery(images: [_videoPath!], initialIndex: 0))),
              ),
            
            // 2. 处理图片列表
            ..._imagePaths.asMap().entries.map((entry) => _buildMediaItem(
              path: entry.value, 
              isVideo: false, 
              onDelete: () => setState(() => _imagePaths.removeAt(entry.key)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FullScreenGallery(images: _imagePaths, initialIndex: entry.key))),
            )),
          ],
        ),
      ],
    );
  }

  // 💡 辅助方法：构建统一大小的媒体方块
  Widget _buildMediaItem({required String path, required bool isVideo, required VoidCallback onDelete, required VoidCallback onTap}) {
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
                // 底层：缩略图 (视频使用 LivePhotoThumbnail 预览)
                isVideo || isLive 
                  ? LivePhotoThumbnail(videoPath: path, width: 100, height: 100)
                  : Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover),
                
                // 💡 视频专属遮罩：半透明黑影 + 播放图标，用于和照片区分
                if (isVideo)
                  Container(
                    width: 100, height: 100,
                    color: Colors.black26,
                    child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 40),
                  ),
              ],
            ),
          ),
        ),
        if (!_isArchived)
          Positioned(
            right: 4, top: 4,
            child: GestureDetector(
              onTap: () { onDelete(); _performAutoSave(); },
              child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)),
            ),
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
    if (type == 'video' || type == 'live') {
      typeGroup = const XTypeGroup(extensions: ['mp4', 'mov']);
    } else if (type == 'audio') {
      typeGroup = const XTypeGroup(extensions: ['mp3', 'm4a']);
    } else if (type == 'file') {
      typeGroup = const XTypeGroup(extensions: ['pdf', 'zip']);
    } else {
      typeGroup = const XTypeGroup(extensions: ['jpg', 'png', 'gif', 'webp']); 
    }
    
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _saveMediaFile(file.path, type);
    }
  }
}

// ================= 子组件：全能视频播放器 (media_kit 重构版) =================
class MiniVideoPlayer extends StatefulWidget {
  final String videoPath;
  const MiniVideoPlayer({super.key, required this.videoPath});
  @override
  State<MiniVideoPlayer> createState() => _MiniVideoPlayerState();
}

class _MiniVideoPlayerState extends State<MiniVideoPlayer> {
  late final player = Player();
  late final controller = VideoController(player);
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    player.open(Media(widget.videoPath), play: false);
    player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });
  }

  @override
  void dispose() {
    player.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9, 
      child: Stack(
        alignment: Alignment.center,
        children: [
          Video(
            controller: controller,
            controls: NoVideoControls, 
          ),
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle : Icons.play_circle, 
              color: Colors.white.withValues(alpha: 0.8), 
              size: 50
            ),
            onPressed: () {
              if (_isPlaying) {
                player.pause();
              } else {
                player.play();
              }
            }
          )
        ],
      ),
    );
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
    _audioPlayer.onPlayerStateChanged.listen((s) { 
      if(mounted) {
        setState(() => _isPlaying = s == PlayerState.playing); 
      }
    }); 
    _audioPlayer.onDurationChanged.listen((d) { 
      if(mounted) {
        setState(() => _duration = d); 
      }
    }); 
    _audioPlayer.onPositionChanged.listen((p) { 
      if(mounted) {
        setState(() => _position = p); 
      }
    }); 
  } 

  @override 
  void dispose() { 
    _audioPlayer.dispose(); 
    super.dispose(); 
  } 

  @override 
  Widget build(BuildContext context) { 
    return Row(
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow), 
          onPressed: () {
            if (_isPlaying) {
              _audioPlayer.pause();
            } else {
              _audioPlayer.play(DeviceFileSource(widget.audioPath));
            }
          }
        ), 
        Expanded(
          child: Slider(
            max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0, 
            value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()), 
            onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt()))
          )
        )
      ]
    ); 
  } 
}

// ================= 子组件：Live图缩略图自动播放器 (media_kit 重构版) =================
class LivePhotoThumbnail extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  const LivePhotoThumbnail({super.key, required this.videoPath, required this.width, required this.height});
  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  late final player = Player();
  late final controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    player.setVolume(0); 
    player.setPlaylistMode(PlaylistMode.loop); 
    player.open(Media(widget.videoPath)); 
  }

  @override
  void dispose() { 
    player.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width, 
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Video(controller: controller, controls: NoVideoControls),
            ),
          ),
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