import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
  String _localDataPath = "";

  // 外观与交互状态
  bool _isDark = false;
  bool _isEyeCare = false;

  // 提供 8 种精美的莫兰迪/高级色系供用户选择
  final List<Color> _availableColors = [
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.deepPurple,
    Colors.pink,
    Colors.orange,
    Colors.brown,
    Colors.blueGrey
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ================= 1. 配置加载与保存 =================
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final root = await DatabaseHelper.instance.rootDir;

    setState(() {
      _useLock = prefs.getBool('use_lock') ?? false;
      _pwdController.text = prefs.getString('lock_pwd') ?? '';
      _questionController.text = prefs.getString('lock_question') ?? '';
      _answerController.text = prefs.getString('lock_answer') ?? '';
      _cloudSyncPath = prefs.getString('cloud_sync_path') ?? '';
      _isDark = prefs.getBool('is_dark') ?? false;
      _isEyeCare = prefs.getBool('is_eye_care') ?? false;
      _localDataPath = root;
    });
  }

  Future<void> _saveSettings() async {
    if (_useLock) {
      if (_pwdController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('密码不能为空！')));
        return;
      }
      if (_questionController.text.trim().isEmpty ||
          _answerController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请完善密保问题和答案，防止忘记密码！')));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_lock', _useLock);
    await prefs.setString('lock_pwd', _pwdController.text.trim());
    await prefs.setString('lock_question', _questionController.text.trim());
    await prefs.setString('lock_answer', _answerController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ 密码与密保设置已保存')));
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



  void _showThemeColorPicker(BuildContext context) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("选择全局主题强调色",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: _availableColors
                          .map((color) => GestureDetector(
                                onTap: () async {
                                  globalThemeColor.value = color;
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setInt('themeColor', color.value);
                                  if (mounted) Navigator.pop(c);
                                },
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: globalThemeColor.value.value ==
                                            color.value
                                        ? Border.all(
                                            color: Colors.black87, width: 3)
                                        : null,
                                  ),
                                  child: globalThemeColor.value.value ==
                                          color.value
                                      ? const Icon(Icons.check,
                                          color: Colors.white)
                                      : null,
                                ),
                              ))
                          .toList(),
                    )
                  ],
                ),
              ),
            ));
  }

  // ================= 3. 导入、备份与本地路径 =================
  Future<void> _openLocalDataFolder() async {
    if (_localDataPath.isEmpty) return;
    try {
      final Uri uri = Uri.file(_localDataPath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw Exception('系统不支持直接打开该路径');
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: _localDataPath));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('无法直接打开，路径已复制到剪贴板，请在资源管理器中粘贴访问'),
            backgroundColor: Colors.orange));
      }
    }
  }

  Future<void> _importDiaries() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final typeGroup = const XTypeGroup(extensions: ['md', 'txt']);
    final List<XFile> files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
          child: Card(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text("正在解析并导入...")
                  ])))),
    );

    int successCount = 0;
    for (var xfile in files) {
      try {
        File file = File(xfile.path);
        String content = await file.readAsString();
        String title = p.basenameWithoutExtension(file.path);
        String date = DateTime.now().toString();
        try {
          var stat = await file.stat();
          date = stat.modified.toString();
        } catch (_) {}

        final diaryData = {
          'title': title,
          'content': content,
          'date': date,
          'weather': "sunny",
          'mood': "happy",
          'tags': '[]',
          'imagePath': '[]',
          'type': 0
        };
        await DatabaseHelper.instance.insertDiary(diaryData);
        successCount++;
      } catch (e) {
        debugPrint("导入失败: $e");
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎉 成功导入 $successCount 篇日记！'),
          backgroundColor: Theme.of(context).primaryColor));
    }
  }

  Future<void> _importBackupZip() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final typeGroup = const XTypeGroup(extensions: ['zip']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
          child: Card(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text("正在解压覆盖...")
                  ])))),
    );

    try {
      final root = await DatabaseHelper.instance.rootDir;
      final bytes = await File(file.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final archiveFile in archive) {
        final String filename = archiveFile.name;
        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          File(p.join(root, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(p.join(root, filename)).createSync(recursive: true);
        }
      }
      if (mounted) {
        Navigator.pop(context);
        showDialog(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('恢复成功 🎉'),
                    content: const Text('备份已覆盖，请重启应用。'),
                    actions: [
                      TextButton(
                          onPressed: () => exit(0), child: const Text('立即退出'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败: $e')));
      }
    }
  }

  Future<void> _exportBackupZip() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final String defaultName =
        'GrainBuds_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    final FileSaveLocation? result =
        await getSaveLocation(suggestedName: defaultName);
    if (result == null) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
            child: Card(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text("正在打包所有数据，请稍候...")
                    ])))),
      );
    }

    try {
      final savePath = result.path;
      final res = await DatabaseHelper.instance.createFullBackup(savePath);

      if (mounted) {
        Navigator.pop(context);
        if (res != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ 备份包已成功保存至:\n$savePath'),
              backgroundColor: Theme.of(context).primaryColor));
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('❌ 导出失败，请检查目录权限')));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 导出发生异常: $e')));
      }
    }
  }

  // ================= 4. 网盘与弹窗 =================
  Future<void> _pickCloudDirectory() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_sync_path', directoryPath);
      setState(() {
        _cloudSyncPath = directoryPath;
      });
    }
  }

  Future<void> _syncToCloud() async {
    if (_cloudSyncPath.isEmpty) return;
    final String fileName =
        'MyDiary_CloudSync_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    await DatabaseHelper.instance
        .createFullBackup(p.join(_cloudSyncPath, fileName));
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🚀 成功推送到网盘！')));
  }

  void _showCloudSyncGuide(BuildContext context) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text("☁️ 如何实现多设备无感同步？"),
              content: const SingleChildScrollView(
                child: Text(
                    "1. 在电脑上下载并安装【百度网盘】、【坚果云】或【OneDrive】等客户端。\n\n2. 点击日记的“网盘同步”，选中云盘在电脑里生成的本地同步文件夹。\n\n3. 每次写完日记点击右侧的【推送备份】按钮，数据就会被打包到该文件夹中并自动同步到云端！\n\n4. 在新电脑上，从这个压缩包恢复即可。"),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("我知道了"))
              ],
            ));
  }

  void _showDonateDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("☕️ 请开发者喝杯咖啡",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  const Text("GrainBuds 功能免费无广。如果它帮到了你，欢迎赞助支持服务器和证书费用~",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/donate_qr.png',
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text("感恩每一份善意 ❤️",
                      style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ));
  }

  Future<void> _checkForUpdates(BuildContext context,
      {bool showToast = false}) async {
    const String currentVersion = "1.1.0";
    const String versionUrl =
        "https://raw.githubusercontent.com/TirFire/grain_buds/refs/heads/main/version.txt";

    if (showToast)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("正在检查更新...")));

    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        String latestVersion = response.body.trim();
        if (latestVersion != currentVersion && mounted) {
          _showUpdateDialog(context, latestVersion);
        } else if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("✨ 已是最新版本"),
              backgroundColor: Theme.of(context).primaryColor));
        }
      }
    } catch (e) {
      if (showToast && mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("检查失败，请检查网络")));
    }
  }

  void _showUpdateDialog(BuildContext context, String newVersion) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("🚀 发现新版本！"),
        content: Text("检测到新版本 $newVersion，建议立即更新以获得更好的体验。"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("稍后再说", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final Uri url = Uri.parse(
                  'https://github.com/TirFire/grain_buds/releases/latest');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
                if (context.mounted) Navigator.pop(c);
              } else {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("无法打开浏览器，请手动前往 GitHub 检查更新")));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white),
            child: const Text("立即前往下载"),
          ),
        ],
      ),
    );
  }

  void _showFeatureIntro(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.amber, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text("探索全新特性",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFeatureItem(
                          Icons.play_circle_fill,
                          Colors.teal,
                          "丝滑的多媒体体验",
                          "全新升级底层引擎，支持本地视频、Live图、音频无缝混排，点开即看，告别黑屏与卡顿。"),
                      _buildFeatureItem(
                          Icons.security,
                          Colors.orange,
                          "银行级隐私保护",
                          "采用 AES-256 高级加密标准，从底层加密你的专属日记，100% 本地离线存储，数据仅属于你。"),
                      _buildFeatureItem(
                          Icons.history,
                          Colors.deepOrange,
                          "时光印记与回忆",
                          "智能聚合“历史上的今天”，配合 GitHub 极客风打卡热力图，让每天的坚持清晰可见。"),
                      _buildFeatureItem(
                          Icons.ios_share,
                          Colors.blue,
                          "优雅的分享与导出",
                          "支持一键生成精美的带日历水印长图海报，或将日记无损导出为 PDF、Word、Markdown 格式。"),
                      _buildFeatureItem(Icons.cloud_sync, Colors.purple,
                          "数据安全备份", "支持将完整多媒体数据打包导出为 ZIP，或配置云盘目录实现无感自动备份。"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("立即体验",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
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
            Icon(Icons.eco, size: 60, color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            const Text("GrainBuds (小满日记)",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("v 1.1.0", style: TextStyle(color: Colors.grey)),
            const Divider(height: 30),
            const Text("数据 100% 存储于本地，守护每一颗闪念的种子。",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            Text("Developed by 叁火同学",
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold)),
            const Text("© 2026 GrainBuds Studio",
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("确定"))
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
      IconData icon, Color color, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.grey, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const subtitleStyle = TextStyle(fontSize: 12, color: Colors.grey);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ================= 外观 =================
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("外观与交互",
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold))),
          SwitchListTile(
              title: const Text('深色模式'),
              subtitle: const Text('全局暗色背景，夜间创作更舒适', style: subtitleStyle),
              secondary: const Icon(Icons.dark_mode),
              value: _isDark,
              onChanged: _toggleTheme),
          SwitchListTile(
              title: const Text('纸张护眼模式'),
              subtitle: const Text('模拟纸质暖色调，有效减轻视觉疲劳', style: subtitleStyle),
              secondary: const Icon(Icons.remove_red_eye),
              value: _isEyeCare,
              onChanged: _toggleEyeCare),

          // 💡 动态 UI 主题颜色入口
          ValueListenableBuilder<Color>(
              valueListenable: globalThemeColor,
              builder: (context, color, child) {
                return ListTile(
                  leading: Icon(Icons.color_lens, color: color),
                  title: const Text('UI 主题配色'),
                  subtitle: const Text('自定义软件的强调色与顶部边框', style: subtitleStyle),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  onTap: () => _showThemeColorPicker(context),
                );
              }),

          const Divider(height: 40),

          // ================= 安全 =================
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("安全防护",
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold))),
          SwitchListTile(
              title: const Text('启用密码锁'),
              subtitle: const Text('开启后每次进入应用需验证密码，守护隐私', style: subtitleStyle),
              activeColor: primaryColor,
              value: _useLock,
              onChanged: (v) => setState(() => _useLock = v)),
          if (_useLock) ...[
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                    controller: _pwdController,
                    decoration: const InputDecoration(
                        labelText: '密码',
                        border: OutlineInputBorder(),
                        hintText: '请输入访问密码'))),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                    controller: _questionController,
                    decoration: const InputDecoration(
                        labelText: '密保问题',
                        border: OutlineInputBorder(),
                        hintText: '如：我的家乡在哪里？'))),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                    controller: _answerController,
                    decoration: const InputDecoration(
                        labelText: '密保答案',
                        border: OutlineInputBorder(),
                        hintText: '用于忘记密码时找回'))),
            ElevatedButton(onPressed: _saveSettings, child: const Text('保存密码')),
          ],

          const Divider(height: 40),

          // ================= 数据 =================
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("数据管理",
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold))),
          ListTile(
            leading: Icon(Icons.folder_open, color: primaryColor),
            title: const Text('本地数据文件夹'),
            subtitle: Text('日记和媒体均保存在此 (点击打开，长按复制):\n$_localDataPath',
                style: subtitleStyle),
            trailing:
                const Icon(Icons.open_in_new, size: 20, color: Colors.grey),
            onTap: _openLocalDataFolder,
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: _localDataPath));
              if (mounted)
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('✅ 路径已复制到剪贴板')));
            },
          ),
          ListTile(
              leading: const Icon(Icons.cloud_sync, color: Colors.blue),
              title: Row(
                children: [
                  const Text('网盘同步'),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showCloudSyncGuide(context),
                    child: const Icon(Icons.help_outline,
                        size: 16, color: Colors.grey),
                  )
                ],
              ),
              subtitle: Text(
                  _cloudSyncPath.isEmpty
                      ? "选择坚果云等网盘的本地目录，实现自动备份"
                      : "当前路径:\n$_cloudSyncPath",
                  style: subtitleStyle),
              onTap: _pickCloudDirectory,
              trailing: IconButton(
                  icon: const Icon(Icons.backup),
                  onPressed: _syncToCloud,
                  tooltip: "立即推送备份")),
          ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.teal),
              title: const Text('导出完整备份包'),
              subtitle: const Text('将所有日记及多媒体附件打包为 .zip 文件并保存到电脑',
                  style: subtitleStyle),
              onTap: _exportBackupZip),
          ListTile(
              leading: const Icon(Icons.restore_page, color: Colors.green),
              title: const Text('从备份包恢复'),
              subtitle:
                  const Text('从 .zip 压缩包中还原所有日记与配置', style: subtitleStyle),
              onTap: _importBackupZip),
          ListTile(
              leading:
                  const Icon(Icons.drive_folder_upload, color: Colors.orange),
              title: const Text('批量导入日记'),
              subtitle:
                  const Text('支持批量导入 .md 或 .txt 格式的本地文件', style: subtitleStyle),
              onTap: _importDiaries),
          ListTile(
              leading: const Icon(Icons.edit_document, color: Colors.indigo),
              title: const Text('日记模板管理'),
              subtitle: const Text('添加、修改或删除常用的写作模板', style: subtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const TemplateMgrPage()))),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('回收站'),
              subtitle: const Text('找回被删除的日记，避免误删遗失', style: subtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const TrashPage()))),

          const Divider(height: 40),

          // ================= 关于 =================
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("关于",
                  style: TextStyle(
                      color: primaryColor, fontWeight: FontWeight.bold))),
          ListTile(
              leading: const Icon(Icons.coffee, color: Colors.brown),
              title: const Text('赞助开发者'),
              subtitle: const Text('用爱发电，感谢支持', style: subtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDonateDialog(context)),
          ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.amber),
              title: const Text('功能特性介绍'),
              subtitle:
                  const Text('了解 GrainBuds 的全新多媒体与写作功能', style: subtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showFeatureIntro(context)),
          ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于 GrainBuds'),
              subtitle: const Text('查看软件设计理念与开发者信息', style: subtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAboutDetail(context)),
          
          ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('检查版本更新'),
              subtitle:
                  const Text('当前版本 v1.1.0，获取最新功能与修复', style: subtitleStyle),
              onTap: () => _checkForUpdates(context, showToast: true)),

          const SizedBox(height: 60),
          Center(
              child: Text("GrainBuds • Crafted with ❤️",
                  style: TextStyle(
                      color: Colors.grey.withOpacity(0.5), fontSize: 10))),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
