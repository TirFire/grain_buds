import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'database_helper.dart';

class WebDavSyncService {
  static final WebDavSyncService instance = WebDavSyncService._init();
  WebDavSyncService._init();

  webdav.Client? _client;
  final String _remoteRoot = '/MyDiary_Data'; // 网盘上的日记根目录
  bool _isSyncing = false;

  // 💡 1. 初始化客户端并测试连接
  Future<bool> connect(String url, String username, String password) async {
    try {
      _client = webdav.newClient(
        url,
        user: username,
        password: password,
        debug: kDebugMode, // 开发模式下打印日志
      );
      // ping 一下服务器看看是否通畅
      await _client!.ping();
      
      // 保存配置到本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webdav_url', url);
      await prefs.setString('webdav_user', username);
      await prefs.setString('webdav_pwd', password);
      
      // 确保云端有根目录
      try {
        await _client!.mkdir(_remoteRoot);
      } catch (_) {} // 目录已存在会报错，忽略即可
      
      return true;
    } catch (e) {
      debugPrint("WebDAV 连接失败: $e");
      _client = null;
      return false;
    }
  }

  // 💡 2. 自动读取本地配置进行连接（用于 App 启动时）
  Future<bool> autoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('webdav_url');
    final user = prefs.getString('webdav_user');
    final pwd = prefs.getString('webdav_pwd');

    if (url != null && user != null && pwd != null && url.isNotEmpty) {
      return await connect(url, user, pwd);
    }
    return false;
  }

  // 💡 3. 核心：执行双向静默同步
  Future<bool> startSync({Function(String)? onProgress}) async {
    if (_client == null || _isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;

    try {
      final localRoot = await DatabaseHelper.instance.rootDir;
      onProgress?.call("正在扫描本地与云端文件...");

      // 获取本地所有的年月文件夹 (例如: 2026-03)
      final localDir = Directory(localRoot);
      if (!localDir.existsSync()) localDir.createSync(recursive: true);
      
      List<FileSystemEntity> localMonths = localDir.listSync().whereType<Directory>().toList();
      
      // 获取云端所有的年月文件夹
      List<webdav.File> remoteMonths = [];
      try {
        remoteMonths = await _client!.readDir(_remoteRoot);
      } catch (_) {}

      // 建立一个需要同步的月份合集（合并本地和云端有的月份）
      Set<String> allMonths = {};
      for (var d in localMonths) {
        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(p.basename(d.path))) {
          allMonths.add(p.basename(d.path));
        }
      }
      for (var r in remoteMonths) {
        if (r.isDir == true && RegExp(r'^\d{4}-\d{2}$').hasMatch(r.name!)) {
          allMonths.add(r.name!);
        }
      }

      // ================= 开始逐个月份进行双向比对 =================
      for (String month in allMonths) {
        onProgress?.call("正在同步 $month ...");
        hasChanges |= await _syncDirectory(localRoot, _remoteRoot, month);
        hasChanges |= await _syncDirectory(localRoot, _remoteRoot, '$month/assets');
      }

      // 💡 4. 如果有文件发生了变动（下载了新文件），触发数据库索引重建！
      if (hasChanges) {
        onProgress?.call("正在重建本地数据库索引...");
        await DatabaseHelper.instance.rebuildIndexFromLocalFiles();
      }
      
      onProgress?.call("同步完成");
      return true;
    } catch (e) {
      debugPrint("同步过程中发生异常: $e");
      onProgress?.call("同步失败: $e");
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  // 💡 文件夹比对与上传下载逻辑
  Future<bool> _syncDirectory(String localBase, String remoteBase, String subPath) async {
    bool dbNeedsRebuild = false;
    final localDirPath = p.join(localBase, subPath);
    final remoteDirPath = p.normalize(p.join(remoteBase, subPath)).replaceAll('\\', '/');

    final localDir = Directory(localDirPath);
    if (!localDir.existsSync()) localDir.createSync(recursive: true);
    
    // 确保云端对应的目录存在
    try { await _client!.mkdir(remoteDirPath); } catch (_) {}

    // 1. 获取本地文件列表
    Map<String, File> localFiles = {};
    for (var entity in localDir.listSync()) {
      if (entity is File) {
        localFiles[p.basename(entity.path)] = entity;
      }
    }

    // 2. 获取云端文件列表
    Map<String, webdav.File> remoteFiles = {};
    try {
      List<webdav.File> list = await _client!.readDir(remoteDirPath);
      for (var f in list) {
        if (f.isDir != true && f.name != null) {
          remoteFiles[f.name!] = f;
        }
      }
    } catch (_) {}

    // 3. 开始比对：本地 -> 云端 (上传)
    for (String fileName in localFiles.keys) {
      File localF = localFiles[fileName]!;
      webdav.File? remoteF = remoteFiles[fileName];

      DateTime localTime = localF.lastModifiedSync();
      
      bool isAsset = subPath.endsWith('assets');
      bool needUpload = remoteF == null;
      if (!isAsset && remoteF != null && remoteF.mTime != null) {
        // 💡 修复 1：使用 2 秒容差代替强制的时间修改，防止微小网络延迟引起误判
        needUpload = localTime.difference(remoteF.mTime!).inSeconds > 2;
      }

      if (needUpload) {
        String targetRemotePath = "$remoteDirPath/$fileName";
        debugPrint("⬆️ 上传文件: $fileName");
        await _client!.writeFromFile(localF.path, targetRemotePath);
        // 🚫 删掉这行！不要再强行 add(seconds: 2) 修改本地时间了！
      }
    }

    // 4. 开始比对：云端 -> 本地 (下载)
    for (String fileName in remoteFiles.keys) {
      webdav.File remoteF = remoteFiles[fileName]!;
      File? localF = localFiles[fileName];

      bool isAsset = subPath.endsWith('assets');
      bool needDownload = localF == null;
      if (!isAsset && localF != null && remoteF.mTime != null) {
        // 💡 修复 2：下载也加入 2 秒容差
        needDownload = remoteF.mTime!.difference(localF.lastModifiedSync()).inSeconds > 2;
      }

      if (needDownload) {
        String sourceRemotePath = "$remoteDirPath/$fileName";
        String targetLocalPath = p.join(localDirPath, fileName);
        debugPrint("⬇️ 下载文件: $fileName");
        await _client!.read2File(sourceRemotePath, targetLocalPath);
        
        // 💡 核心修复 3：下载完成后，强制将本地物理文件的时间对齐为云端时间！
        // 这样下一次同步时，两边时间一模一样，彻底斩断无限同步死循环！
        try {
          File(targetLocalPath).setLastModifiedSync(remoteF.mTime!);
        } catch (_) {}
        
        if (fileName.endsWith('.md')) {
          dbNeedsRebuild = true;
        }
      }
    }
    return dbNeedsRebuild;
  }
}