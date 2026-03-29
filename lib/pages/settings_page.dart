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
import '../core/webdav_sync_service.dart';
import '../core/encryption_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  String _webdavUrl = "";
  String _webdavUser = "";
  String _webdavPwd = "";

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
      final String savedLockPwd = prefs.getString('lock_pwd') ?? '';
      _pwdController.text = savedLockPwd.isNotEmpty ? '********' : '';
      _questionController.text = prefs.getString('lock_question') ?? '';
      _answerController.text = prefs.getString('lock_answer') ?? '';
      _cloudSyncPath = prefs.getString('cloud_sync_path') ?? '';
      _isDark = prefs.getBool('is_dark') ?? false;
      _isEyeCare = prefs.getBool('is_eye_care') ?? false;
      _localDataPath = root;
      _webdavUrl = prefs.getString('webdav_url') ?? '';
      _webdavUser = prefs.getString('webdav_user') ?? '';
      _webdavPwd = prefs.getString('webdav_pwd') ?? '';
    });
    _cloudSyncPath = prefs.getString('cloud_sync_path') ?? '';
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
    // 💡 只有当用户真的修改了密码时（不是默认的星号），才进行哈希并覆盖保存
    if (_pwdController.text.trim() != '********' &&
        _pwdController.text.trim().isNotEmpty) {
      String hashedPwd =
          EncryptionService.hashPassword(_pwdController.text.trim());
      await prefs.setString('lock_pwd', hashedPwd);
    } else if (!_useLock) {
      await prefs.setString('lock_pwd', ''); // 关闭锁时清空密码
    }
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
                                  await prefs.setInt('themeColor', color.toARGB32());
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

  // ================= 💡 WebDAV 专属方法 =================

  // 💡 新增：WebDAV 详细配置教程弹窗
  void _showWebdavGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("☁️ WebDAV 同步指南",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            "1. 选择 WebDAV 服务商：\n推荐使用「坚果云」，国内访问速度快且免费额度足够（每个月免费存1G，读取3G）。\n\n"
            "2. 获取授权码 (非常重要)：\n"
            "• 登录坚果云官网，进入【账户信息】->【安全选项】。\n"
            "• 在【第三方应用管理】中点击【添加应用】，名称填「小满日记」。\n"
            "• 复制系统生成的【应用密码】（注意：绝不是您的账号登录密码！）。\n\n"
            "3. 在此填写配置：\n"
            "• 服务器地址：https://dav.jianguoyun.com/dav/\n"
            "• 账号：您的坚果云登录邮箱\n"
            "• 密码/授权码：刚才生成的应用密码\n\n"
            "💡 同步机制：\n点击同步后，App 会智能比对手机和网盘的文件进行双向多退少补。文件采用增量同步且支持加密传输，保障您的绝对隐私！",
            style: TextStyle(height: 1.6, fontSize: 14, color: Colors.black87),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("我知道了", style: TextStyle(color: Colors.blue)))
        ],
      ),
    );
  }

  void _showWebdavConfigDialog() {
    final urlCtrl = TextEditingController(text: _webdavUrl);
    final userCtrl = TextEditingController(text: _webdavUser);
    final pwdCtrl = TextEditingController(text: _webdavPwd);
    bool isTesting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          // 💡 替换：去掉了 const，并加入了 Spacer 和包含小问号的 IconButton
          title: Row(
            children: [
              const Icon(Icons.cloud_sync, color: Colors.blue),
              const SizedBox(width: 8),
              const Text("WebDAV 配置",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(), // 将问号推到最右边
              IconButton(
                icon: const Icon(Icons.help_outline,
                    color: Colors.grey, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '查看配置教程',
                onPressed: () => _showWebdavGuide(context), // 💡 点击呼出教程
              )
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("支持坚果云、Nextcloud 等标准 WebDAV 服务。数据完全在您自己手中。",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                      labelText: '服务器地址 (URL)',
                      hintText: '如: https://dav.jianguoyun.com/dav/',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                      labelText: '账号', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '应用密码 / 授权码', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isTesting ? null : () => Navigator.pop(c),
              child: const Text("取消", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isTesting
                  ? null
                  : () async {
                      if (urlCtrl.text.isEmpty ||
                          userCtrl.text.isEmpty ||
                          pwdCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请填写完整信息')));
                        return;
                      }
                      setDialogState(() => isTesting = true);

                      // 调用引擎进行连接测试
                      bool success = await WebDavSyncService.instance.connect(
                        urlCtrl.text.trim(),
                        userCtrl.text.trim(),
                        pwdCtrl.text.trim(),
                      );

                      setDialogState(() => isTesting = false);

                      if (success) {
                        setState(() {
                          _webdavUrl = urlCtrl.text.trim();
                          _webdavUser = userCtrl.text.trim();
                          _webdavPwd = pwdCtrl.text.trim();
                        });
                        if (mounted) {
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('✅ 连接成功！已保存配置。'),
                                  backgroundColor: Colors.teal));
                        }
                      } else {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('❌ 连接失败，请检查地址或账号密码是否正确'),
                                  backgroundColor: Colors.red));
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text("测试连接并保存"),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _startWebdavSync() async {
    if (_webdavUrl.isEmpty) {
      _showWebdavConfigDialog();
      return;
    }

    // 使用 ValueNotifier 实时更新弹窗里的文字进度
    final ValueNotifier<String> progressNotifier =
        ValueNotifier("正在初始化同步引擎...");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progressNotifier,
                builder: (context, value, child) =>
                    Text(value, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );

    // 确保连接
    await WebDavSyncService.instance.autoConnect();

    // 执行同步，传入进度回调
    bool success = await WebDavSyncService.instance.startSync(
      onProgress: (msg) => progressNotifier.value = msg,
    );

    if (mounted) {
      Navigator.pop(context); // 关掉进度弹窗
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 WebDAV 多端同步完成！'), backgroundColor: Colors.teal));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ 同步失败，请检查网络或配置'), backgroundColor: Colors.red));
      }
    }
  }

  // ================= 3. 导入、备份与本地路径 =================
  Future<void> _changeStoragePath() async {
    try {
      // 1. 💡 提前拦截提示
      bool? preConfirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                title: const Text("迁移数据存储位置"),
                content: const Text(
                    "为了确保数据安全与整洁，请在接下来的选框中，务必【新建一个空的文件夹】（例如命名为 小满日记_Data）来作为新的专属存储库。\n\n⚠️ 注意：请勿选择系统盘根目录或已存放大量文件的文件夹。"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("取消", style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: const Text("我知道了，去选择"),
                  ),
                ],
              ));

      if (preConfirm != true) return;

      final String? selectedDirectory = await getDirectoryPath();
      if (selectedDirectory == null) return;

      // 💡 【核心优化：安全气囊】物理检测选定目录是否为空
      final targetDir = Directory(selectedDirectory);
      try {
        final List<FileSystemEntity> contents = targetDir.listSync();
        if (contents.isNotEmpty) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Row(children: [Icon(Icons.warning, color: Colors.orange), SizedBox(width: 8), Text("文件夹非空")]),
                content: const Text("为了防止数据混淆和迁移失败，请选择或【新建一个完全为空】的文件夹。"),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("返回"))],
              ),
            );
          }
          return; 
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ 无法访问该文件夹（权限受限），请换一个位置。"), backgroundColor: Colors.red));
        return;
      }

      // 3. 确认并执行迁移（逻辑保持不变，但增强了加载圈的关闭保护）
      bool? confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                title: const Text("确认开始迁移？"),
                content: Text("数据将迁移至:\n$selectedDirectory\n\n💡 迁移成功后，原位置的旧文件将被安全清理。"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("取消")),
                  ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("确定迁移")),
                ],
              ));

      if (confirm == true) {
        // ... 此处保留原有的 showDialog 加载圈代码 ...
        bool success = await DatabaseHelper.instance.changeRootDirectory(selectedDirectory);

        if (success && mounted) {
          String newRealRoot = await DatabaseHelper.instance.rootDir;
          setState(() => _localDataPath = newRealRoot); // 💡 更新路径变量
          await _rebuildIndex();
          if (mounted) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 数据迁移完成！'), backgroundColor: Colors.teal));
        } else {
          if (mounted) Navigator.pop(context); // 💡 失败也必须关闭加载圈
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('路径迁移失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // 💡 恢复：直接呼出电脑底层资源管理器
  Future<void> _openLocalDataFolder() async {
    final root = await DatabaseHelper.instance.rootDir;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [root]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [root]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [root]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法直接打开，请手动前往路径查看')));
      }
    }
  }
  // 💡 新增：长按复制本地文件夹路径
  Future<void> _copyLocalDataFolder() async {
    final root = await DatabaseHelper.instance.rootDir;
    await Clipboard.setData(ClipboardData(text: root));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 路径已复制到剪贴板:\n$root'), 
          backgroundColor: Colors.teal,
          duration: const Duration(seconds: 3),
        )
      );
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
                    CircularProgressIndicator(color: Colors.teal),
                    SizedBox(height: 10),
                    Text("正在智能合并数据...")
                  ])))),
    );

    try {
      final root = await DatabaseHelper.instance.rootDir;
      

      final bytes = await File(file.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final archiveFile in archive) {
        final String filename = archiveFile.name;
        
        // 💡 核心修复 1：绝对禁止解压数据库文件！
        // 这样就能保留手机里原有的日记记录，不被压缩包覆盖。
        if (filename.contains('diary_meta.db')) continue;

        final String outPath = p.normalize(p.join(root, filename));
        if (!outPath.startsWith(p.normalize(root))) continue; 

        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          File(outPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      // 💡 核心修复 2：文件解压完后，调用“重建索引”功能
      // 系统会自动识别哪些是新搬进来的 .md 文件，并把它们增量加入当前的日记本。
      int newCount = await DatabaseHelper.instance.rebuildIndexFromLocalFiles();

      if (mounted) {
        Navigator.pop(context); // 关闭加载圈
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎉 智能合并成功！共导入 $newCount 篇新内容'),
          backgroundColor: Colors.teal,
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('合并失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _rebuildIndex() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
          child: Card(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: Colors.teal),
                    SizedBox(height: 10),
                    Text("正在全盘解析 .md 文件重建索引...")
                  ])))),
    );
    try {
      int count = await DatabaseHelper.instance.rebuildIndexFromLocalFiles();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ 成功重建 $count 篇日记的索引！多端数据已对齐。'),
            backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ 重建索引失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportBackupZip() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final String defaultName =
        'GrainBuds_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';

    String? savePath;

    // 💡 核心修复：手机端与电脑端的路径保存策略分流
    if (Platform.isAndroid || Platform.isIOS) {
      // 📱 手机端：静默保存到应用的导出专区
      final directory = await getApplicationDocumentsDirectory();
      final exportDir =
          Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      savePath = p.join(exportDir.path, defaultName);
    } else {
      // 💻 电脑端：调用原生的“另存为”弹窗
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: defaultName);
      if (result == null) return; // 用户取消了保存
      savePath = result.path;
    }

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
      final res = await DatabaseHelper.instance.createFullBackup(savePath);

      if (mounted) {
        Navigator.pop(context); // 关闭加载转圈
        if (res != null) {
          // 💡 修复：导出成功后提供弹窗提示与“立即打开”按钮
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('✅ 完整备份包已成功导出！'),
            backgroundColor: Theme.of(context).primaryColor,
            action: (Platform.isAndroid || Platform.isIOS)
                ? SnackBarAction(
                    label: '分享/保存',
                    textColor: Colors.white,
                    onPressed: () async {
                      await Share.shareXFiles([XFile(savePath!)],
                          text: '小满日记完整备份');
                    })
                : null,
          ));
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
        'MyDiary_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';

    // 💡 核心修复：必须接收返回值，判断底层是否真的写入成功了！
    final result = await DatabaseHelper.instance
        .createFullBackup(p.join(_cloudSyncPath, fileName));

    if (mounted) {
      if (result != null) {
        bool isDesktop =
            Platform.isWindows || Platform.isMacOS || Platform.isLinux;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isDesktop ? '🚀 成功推送到网盘！' : '📁 成功备份至指定的本地文件夹！'),
            backgroundColor: Colors.teal));
      } else {
        // 如果写入被系统拦截，一定要报红错，不能骗用户！
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ 备份失败：手机系统拒绝了直接写入权限，请使用下方的【导出完整备份包】！'),
            backgroundColor: Colors.red));
      }
    }
  }

  // 💡 新增：统一的备份原理解释弹窗
 void _showUnifiedBackupGuide(BuildContext context) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text("📁 备份目录绑定指南"),
              content: const SingleChildScrollView(
                child: Text(
                    "为了数据安全，建议您绑定一个固定的备份文件夹：\n\n"
                    "1. 普通备份：您可以选择电脑上的任意文件夹，每次点击右侧图标，App 都会生成一个 ZIP 包存入其中。\n\n"
                    "2. 自动云同步（推荐）：如果您安装了【百度网盘】或【OneDrive】，请直接选择网盘生成的“同步文件夹”。\n\n"
                    "💡 这样，App 每次生成的本地备份，都会被网盘自动上传到云端，实现数据的双重保险！"),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text("我知道了", style: TextStyle(color: Colors.blue)))
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
    const String currentVersion = "1.2.0";
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
        if (_isNewerVersion(currentVersion, latestVersion) && mounted) {
          _showUpdateDialog(context, latestVersion);
        } else if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("✨ 当前已是最新版本"),
              backgroundColor: Theme.of(context).primaryColor));
        }
      }
    } catch (e) {
      if (showToast && mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("检查失败，请检查网络")));
    }
  }

  // 💡 新增：版本号比较算法 (支持 x.y.z 格式)
  bool _isNewerVersion(String current, String latest) {
    try {
      List<int> c = current.split('.').map((e) => int.parse(e)).toList();
      List<int> l = latest.split('.').map((e) => int.parse(e)).toList();

      // 逐位对比：大版本 > 次版本 > 修订版本
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true; // 远程位更大，有新版
        if (l[i] < c[i]) return false; // 远程位更小，是旧版
      }
    } catch (_) {}
    return false; // 相等或解析失败
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
            const Text("v 1.2.0", style: TextStyle(color: Colors.grey)),
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
              child: Text("数据管理", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
              
          // 1. 更改存储位置（仅限电脑端）
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            ListTile(
                leading: const Icon(Icons.folder_special, color: Colors.orange),
                title: const Text('更改数据存储位置'),
                subtitle: const Text('自由选择日记库目录（为了数据安全，必须选择空文件夹）', style: subtitleStyle),
                onTap: _changeStoragePath),
          // 💡 优化：增加长按复制功能与文案提示（仅限电脑端）
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.teal),
                title: const Text('打开本地数据文件夹'),
                // 💡 优化：显示当前真实路径，并解决变量未使用警告
                subtitle: Text('当前位置: $_localDataPath\n点击打开管理器，长按复制完整路径', style: subtitleStyle), 
                onTap: _openLocalDataFolder,
                onLongPress: _copyLocalDataFolder,
            ),
                
          // 2. WebDAV 多端同步（双端通用）
          ListTile(
              leading: const Icon(Icons.cloud_sync, color: Colors.blue),
              title: const Text('WebDAV 多端无感同步', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_webdavUrl.isEmpty ? "未配置。支持坚果云、Nextcloud 等，实现多端漫游。" : "已连接:\n$_webdavUrl", style: subtitleStyle),
              onTap: _showWebdavConfigDialog, 
              trailing: (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                  ? ElevatedButton.icon(
                      onPressed: _startWebdavSync, icon: const Icon(Icons.sync, size: 16), label: const Text("立即同步"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, elevation: 0),
                    )
                  : ElevatedButton(
                      onPressed: _startWebdavSync,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(60, 32)),
                      child: const Text("同步", style: TextStyle(fontSize: 13)),
                    ),
          ),
          
          // 3. 统一的备份目录绑定（仅限电脑端）
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            ListTile(
                leading: const Icon(Icons.drive_file_move_outline, color: Colors.blueAccent),
                title: Row(
                  children: [
                    const Text('绑定固定备份目录'),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showUnifiedBackupGuide(context), // 💡 呼叫全新的整合版教程
                      child: const Icon(Icons.help_outline, size: 16, color: Colors.grey)
                    )
                  ],
                ),
                subtitle: Text(
                  _cloudSyncPath.isEmpty 
                    ? "选择电脑上的一个文件夹（支持选为网盘同步目录）" 
                    : "同步至: $_cloudSyncPath", 
                  style: subtitleStyle
                ),
                onTap: _pickCloudDirectory,
                trailing: IconButton(
                  icon: const Icon(Icons.backup_outlined, color: Colors.blueAccent), 
                  onPressed: _syncToCloud, 
                  tooltip: "立即打包备份"
                )
            ),
          ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.teal),
              title: const Text('导出完整备份包'),
              subtitle: const Text('将所有日记及多媒体附件打包为 .zip 文件并保存到电脑',
                  style: subtitleStyle),
              onTap: _exportBackupZip),
          ListTile(
              leading: const Icon(Icons.library_add_check_outlined, color: Colors.green), // 💡 换一个更偏向“添加/检查”的图标
              title: const Text('合并备份包数据'),
              subtitle:
                  const Text('将 ZIP 备份包中的内容增量合并到当前日记本', style: subtitleStyle),
              onTap: _importBackupZip),
          ListTile(
              leading:
                  const Icon(Icons.drive_folder_upload, color: Colors.orange),
              title: const Text('批量导入日记'),
              subtitle:
                  const Text('支持批量导入 .md 或 .txt 格式的本地文件', style: subtitleStyle),
              onTap: _importDiaries),
          ListTile(
              leading: const Icon(Icons.sync_alt, color: Colors.blue),
              title: const Text(
                '一键重建本地索引',
              ),
              subtitle: const Text('扫描本地存储的所有日记文件并刷新列表，解决多端同步后的显示延迟', style: subtitleStyle),
              onTap: _rebuildIndex),
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
                  const Text('当前版本 v1.2.0，获取最新功能与修复\n注意：更新前把文件数据备份成压缩包保障数据安全', style: subtitleStyle),
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
