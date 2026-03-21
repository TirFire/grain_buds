import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:archive/archive_io.dart'; 
import 'package:http/http.dart' as http; // 💡 用于检查更新
import 'package:url_launcher/url_launcher.dart'; // 💡 用于跳转官网

import 'template_mgr_page.dart'; 
import '../core/database_helper.dart'; 
import '../main.dart';            
import 'trash_page.dart';         

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 安全与同步状态
  bool _useLock = false; 
  final _pwdController = TextEditingController();
  final _questionController = TextEditingController(); 
  final _answerController = TextEditingController();
  String _cloudSyncPath = ""; 
  
  // 外观与交互状态
  bool _isDark = false;
  bool _isEyeCare = false;
  bool _typingSound = false;

  @override
  void initState() { 
    super.initState(); 
    _loadSettings(); 
  }
  
  // ================= 1. 配置加载与保存 =================
  Future<void> _loadSettings() async { 
    final prefs = await SharedPreferences.getInstance(); 
    setState(() { 
      _useLock = prefs.getBool('use_lock') ?? false; 
      _pwdController.text = prefs.getString('lock_pwd') ?? ''; 
      _questionController.text = prefs.getString('lock_question') ?? ''; 
      _answerController.text = prefs.getString('lock_answer') ?? ''; 
      _cloudSyncPath = prefs.getString('cloud_sync_path') ?? ''; 
      _isDark = prefs.getBool('is_dark') ?? false;
      _isEyeCare = prefs.getBool('is_eye_care') ?? false;
      _typingSound = prefs.getBool('typing_sound') ?? false;
    }); 
  }
  
  Future<void> _saveSettings() async {
    if (_useLock) {
      if (_pwdController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码不能为空！'))); return; 
      }
      if (_questionController.text.trim().isEmpty || _answerController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请完善密保问题和答案，防止忘记密码！'))); return; 
      }
    }
    final prefs = await SharedPreferences.getInstance(); 
    await prefs.setBool('use_lock', _useLock); 
    await prefs.setString('lock_pwd', _pwdController.text.trim());
    await prefs.setString('lock_question', _questionController.text.trim());
    await prefs.setString('lock_answer', _answerController.text.trim());
    if (mounted) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 密码与密保设置已保存'))); 
    }
  }

  // ================= 2. 外观与交互控制 =================
  Future<void> _toggleTheme(bool isDark) async {
    setState(() => _isDark = isDark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark', isDark);
    globalThemeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _toggleEyeCare(bool isEyeCare) async {
    setState(() => _isEyeCare = isEyeCare);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_eye_care', isEyeCare);
    globalEyeCareMode.value = isEyeCare;
  }

  Future<void> _toggleTypingSound(bool enable) async {
    setState(() => _typingSound = enable);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('typing_sound', enable);
    globalEnableTypingSound = enable;
  }

  // ================= 3. 导入与备份引擎 =================
  Future<void> _importDiaries() async {
    final typeGroup = const XTypeGroup(extensions: ['md', 'txt']);
    final List<XFile> files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (c) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("正在解析并导入...")])))),
    );

    int successCount = 0;
    for (var xfile in files) {
      try {
        File file = File(xfile.path);
        String content = await file.readAsString();
        String title = p.basenameWithoutExtension(file.path);
        String date = DateTime.now().toString();
        try { var stat = await file.stat(); date = stat.modified.toString(); } catch (_) {}
        
        final diaryData = { 
          'title': title, 'content': content, 'date': date, 'weather': "☀️", 
          'mood': "😊", 'tags': '[]', 'imagePath': '[]', 'type': 0 
        };
        await DatabaseHelper.instance.insertDiary(diaryData);
        successCount++;
      } catch (e) { debugPrint("导入失败: $e"); }
    }

    if (mounted) {
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎉 成功导入 $successCount 篇日记！'), backgroundColor: Colors.teal));
    }
  }

  Future<void> _importBackupZip() async {
    final typeGroup = const XTypeGroup(extensions: ['zip']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (c) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("正在解压覆盖...")])))),
    );

    try {
      final root = await DatabaseHelper.instance.rootDir;
      final bytes = await File(file.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final archiveFile in archive) {
        final String filename = archiveFile.name;
        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          File(p.join(root, filename))..createSync(recursive: true)..writeAsBytesSync(data);
        } else {
          Directory(p.join(root, filename)).createSync(recursive: true);
        }
      }
      if (mounted) {
        Navigator.pop(context); 
        showDialog(context: context, builder: (c) => AlertDialog(title: const Text('恢复成功 🎉'), content: const Text('备份已覆盖，请重启应用。'), actions: [TextButton(onPressed: () => exit(0), child: const Text('立即退出'))]));
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e'))); }
    }
  }

  // ================= 4. 网盘与更新逻辑 =================
  Future<void> _pickCloudDirectory() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_sync_path', directoryPath);
      setState(() { _cloudSyncPath = directoryPath; });
    }
  }

  Future<void> _syncToCloud() async {
    if (_cloudSyncPath.isEmpty) return;
    final String fileName = 'MyDiary_CloudSync_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    await DatabaseHelper.instance.createFullBackup(p.join(_cloudSyncPath, fileName));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚀 成功推送到网盘！')));
  }

  // 💡 检查更新逻辑
  Future<void> _checkForUpdates(BuildContext context, {bool showToast = false}) async {
    const String currentVersion = "1.0.0"; 
    const String versionUrl = "https://raw.githubusercontent.com/TirFire/grain_buds/refs/heads/main/version.txt";

    if (showToast) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在检查更新...")));

    try {
      final response = await http.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        String latestVersion = response.body.trim();
        if (latestVersion != currentVersion && mounted) {
          _showUpdateDialog(context, latestVersion);
        } else if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✨ 已是最新版本"), backgroundColor: Colors.teal));
        }
      }
    } catch (e) {
      if (showToast && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("检查失败，请检查网络")));
    }
  }

  void _showUpdateDialog(BuildContext context, String newVersion) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("🚀 发现新版本！"),
        content: Text("检测到新版本 $newVersion，建议立即更新。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
          ElevatedButton(onPressed: () async => await launchUrl(Uri.parse('https://你的官网')), child: const Text("更新")),
        ],
      ),
    );
  }

  void _showAboutDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco, size: 60, color: Colors.teal),
            const SizedBox(height: 16),
            const Text("GrainBuds (小满日记)", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("v 1.0.0", style: TextStyle(color: Colors.grey)),
            const Divider(height: 30),
            const Text("数据 100% 存储于本地，守护每一颗闪念的种子。", textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            const Text("Developed by [叁火同学]", style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)),
            const Text("© 2026 GrainBuds Studio", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("确定"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 外观
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("外观与交互", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
          SwitchListTile(title: const Text('深色模式'), secondary: const Icon(Icons.dark_mode), value: _isDark, onChanged: _toggleTheme),
          SwitchListTile(title: const Text('纸张护眼模式'), secondary: const Icon(Icons.remove_red_eye), value: _isEyeCare, onChanged: _toggleEyeCare),
          SwitchListTile(title: const Text('打字机音效'), secondary: const Icon(Icons.keyboard), value: _typingSound, onChanged: _toggleTypingSound),
          
          const Divider(height: 40),

          // 安全
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("安全防护", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
          SwitchListTile(title: const Text('启用密码锁'), activeColor: primaryColor, value: _useLock, onChanged: (v) => setState(() => _useLock = v)),
          if (_useLock) ...[
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: TextField(controller: _pwdController, decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()))),
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: TextField(controller: _questionController, decoration: const InputDecoration(labelText: '密保问题', border: OutlineInputBorder()))),
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: TextField(controller: _answerController, decoration: const InputDecoration(labelText: '密保答案', border: OutlineInputBorder()))),
            ElevatedButton(onPressed: _saveSettings, child: const Text('保存密码')),
          ],

          const Divider(height: 40),

          // 数据
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("数据管理", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.cloud_sync), title: const Text('网盘同步'), subtitle: Text(_cloudSyncPath.isEmpty ? "未绑定" : _cloudSyncPath), onTap: _pickCloudDirectory, trailing: IconButton(icon: const Icon(Icons.backup), onPressed: _syncToCloud)),
          ListTile(leading: const Icon(Icons.restore_page, color: Colors.green), title: const Text('从备份包恢复'), onTap: _importBackupZip),
          ListTile(leading: const Icon(Icons.drive_folder_upload, color: Colors.orange), title: const Text('批量导入日记'), onTap: _importDiaries),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('回收站'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TrashPage()))),

          const Divider(height: 40),

          // 关于
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("关于", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('关于 GrainBuds'), subtitle: const Text('v 1.0.0'), trailing: const Icon(Icons.chevron_right), onTap: () => _showAboutDetail(context)),
          ListTile(leading: const Icon(Icons.system_update_alt), title: const Text('检查版本更新'), onTap: () => _checkForUpdates(context, showToast: true)),
          
          const SizedBox(height: 60),
          Center(child: Text("GrainBuds • Crafted with ❤️", style: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 10))),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}