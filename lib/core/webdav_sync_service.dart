import 'dart:io';
import 'dart:convert'; // 💡 新增：用于解析和写入 JSON 销毁名单
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'database_helper.dart';
import 'dart:async';

class WebDavSyncService {
  static final WebDavSyncService instance = WebDavSyncService._init();
  WebDavSyncService._init();

  webdav.Client? _client;
  final String _remoteRoot = '/MyDiary_Data'; // 网盘上的日记根目录
  bool _isSyncing = false;
  Timer? _syncTimer;
  
  // 💡 核心优化：远程目录缓存
  final Set<String> _knownRemoteDirs = {};

  void startAutoSync() {
    _syncTimer?.cancel();
    // 每 15 分钟尝试同步一次
    _syncTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      startSync();
    });
    debugPrint("▶️ WebDAV 自动同步已开启");
  }

  // 💡 新增：停止同步锁（局域网同步时调用）
  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint("⏸️ WebDAV 自动同步已暂停 (同步锁激活)");
  }

  Future<void> _safeMkdir(String path) async {
    if (_knownRemoteDirs.contains(path)) return;
    try {
      await _client!.mkdir(path);
      _knownRemoteDirs.add(path); 
    } catch (_) {
      _knownRemoteDirs.add(path);
    }
  }
  

  // 1. 初始化客户端并测试连接
  Future<bool> connect(String url, String username, String password) async {
    try {
      _client = webdav.newClient(url, user: username, password: password, debug: kDebugMode);
      await _client!.ping();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webdav_url', url);
      await prefs.setString('webdav_user', username);
      await prefs.setString('webdav_pwd', password);
      
      await _safeMkdir(_remoteRoot);
      return true;
    } catch (e) {
      debugPrint("WebDAV 连接失败: $e");
      _client = null;
      return false;
    }
  }

  // 2. 自动读取本地配置进行连接
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

  // ================= 同步全局销毁名单 =================
  Future<Set<String>> _syncAndMergeDeletedRecords(String localRoot) async {
    Set<String> merged = {};
    File localFile = File(p.join(localRoot, '.deleted_records.json'));
    String remotePath = "$_remoteRoot/.deleted_records.json";

    // 1. 读取本地名单
    if (localFile.existsSync()) {
      try { merged.addAll(List<String>.from(jsonDecode(localFile.readAsStringSync()))); } catch (_) {}
    }

    // 2. 下载并读取云端名单
    String tempPath = p.join(localRoot, '.deleted_records_temp.json');
    try {
      await _client!.read2File(remotePath, tempPath);
      File tempFile = File(tempPath);
      if (tempFile.existsSync()) {
         merged.addAll(List<String>.from(jsonDecode(tempFile.readAsStringSync())));
         tempFile.deleteSync();
      }
    } catch (_) {} // 初次同步云端可能没有，忽略报错

    // 3. 合并后写回本地和云端
    if (merged.isNotEmpty) {
      try {
         String jsonContent = jsonEncode(merged.toList());
         localFile.writeAsStringSync(jsonContent);
         await _client!.writeFromFile(localFile.path, remotePath);
      } catch (_) {}
    }
    return merged;
  }

  // 3. 核心：执行双向静默同步
  Future<bool> startSync({Function(String)? onProgress}) async {
    if (_client == null || _isSyncing) return false;
    _isSyncing = true;
    bool hasChanges = false;

    try {
      final localRoot = await DatabaseHelper.instance.rootDir;
      onProgress?.call("正在扫描本地与云端文件...");

      final localDir = Directory(localRoot);
      if (!localDir.existsSync()) localDir.createSync(recursive: true);
      
      List<FileSystemEntity> localMonths = localDir.listSync().whereType<Directory>().toList();
      
      List<webdav.File> remoteMonths = [];
      try {
        remoteMonths = await _client!.readDir(_remoteRoot);
      } catch (_) {}

      Set<String> allMonths = {};
      for (var d in localMonths) {
        if (RegExp(r'^\d{4}-\d{2}$').hasMatch(p.basename(d.path))) allMonths.add(p.basename(d.path));
      }
      for (var r in remoteMonths) {
        if (r.isDir == true && r.name != null) {
          String baseName = p.basename(r.name!);
          if (RegExp(r'^\d{4}-\d{2}$').hasMatch(baseName)) allMonths.add(baseName);
        }
      }

      // 阶段 0：先同步并合并全局销毁名单 (Death Ledger)
      onProgress?.call("正在同步云端销毁名单...");
      Set<String> deletedRecords = await _syncAndMergeDeletedRecords(localRoot);

      // 阶段 1：先同步所有的 .md 文本文件
      for (String month in allMonths) {
        onProgress?.call("正在同步日记文本 $month ...");
        bool changed = await _syncDirectory(localRoot, _remoteRoot, month, null, deletedRecords);
        if (changed) hasChanges = true;
      }

      // 阶段 2：如果文本有变化，立刻重建数据库索引，确立最新的真理
      if (hasChanges) {
        onProgress?.call("正在重建本地数据库索引...");
        await DatabaseHelper.instance.rebuildIndexFromLocalFiles();
      }

      // 阶段 3：获取当前所有【存活】的媒体文件名单
      Set<String> validAssets = await DatabaseHelper.instance.getAllValidAssetNames();

      // 阶段 4：带着名单去同步 assets 文件夹，执行垃圾回收
      for (String month in allMonths) {
        onProgress?.call("正在同步媒体附件 $month ...");
        await _syncDirectory(localRoot, _remoteRoot, '$month/assets', validAssets, deletedRecords);
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

  // 4. 目录同步与跨端物理粉碎机制
  Future<bool> _syncDirectory(String localBase, String remoteBase, String subPath, Set<String>? validAssets, Set<String> deletedRecords) async {
    bool dbNeedsRebuild = false;
    final localDirPath = p.join(localBase, subPath);
    final remoteDirPath = p.normalize(p.join(remoteBase, subPath)).replaceAll('\\', '/');

    final localDir = Directory(localDirPath);
    if (!localDir.existsSync()) localDir.createSync(recursive: true);
    
    await _safeMkdir(remoteDirPath);

    Map<String, File> localFiles = {};
    for (var entity in localDir.listSync()) {
      if (entity is File) localFiles[p.basename(entity.path)] = entity;
    }

    Map<String, webdav.File> remoteFiles = {};
    try {
      List<webdav.File> list = await _client!.readDir(remoteDirPath);
      for (var f in list) {
        if (f.isDir != true && f.name != null) {
          remoteFiles[p.basename(f.name!)] = f; 
        }
      }
    } catch (_) {}

    bool isAsset = subPath.endsWith('assets');

    // 1. 本地 -> 云端
    for (String fileName in localFiles.keys) {
      File localF = localFiles[fileName]!;
      
      // 💡 跨端物理粉碎拦截：如果该文件在销毁名单中，彻底抹除两端！
      String relPath = p.normalize(p.join(subPath, fileName)).replaceAll('\\', '/');
      if (!isAsset && deletedRecords.contains(relPath)) {
        try { await localF.delete(); debugPrint("🗑️ 发现销毁名单，粉碎本地文件: $relPath");} catch (_) {}
        try { await _client!.removeAll("$remoteDirPath/$fileName"); debugPrint("🔥 发现销毁名单，粉碎云端文件: $relPath"); } catch (_) {}
        continue;
      }

      webdav.File? remoteF = remoteFiles[fileName];

      if (isAsset && validAssets != null && !validAssets.contains(fileName)) {
        try { await localF.delete(); debugPrint("🧹 清理本地幽灵附件: $fileName"); } catch(_) {}
        continue;
      }

      DateTime localTime = localF.lastModifiedSync();
      bool needUpload = remoteF == null;
      
      if (!isAsset && remoteF != null && remoteF.mTime != null) {
        needUpload = localTime.difference(remoteF.mTime!).inSeconds > 2;
      }

      if (needUpload) {
        String targetRemotePath = "$remoteDirPath/$fileName";
        debugPrint("⬆️ 上传: $fileName");
        await _client!.writeFromFile(localF.path, targetRemotePath);
      }
    }

    // 2. 云端 -> 本地
    for (String fileName in remoteFiles.keys) {
      webdav.File remoteF = remoteFiles[fileName]!;
      String sourceRemotePath = "$remoteDirPath/$fileName";

      // 💡 跨端物理粉碎拦截 (防云端复活)
      String relPath = p.normalize(p.join(subPath, fileName)).replaceAll('\\', '/');
      if (!isAsset && deletedRecords.contains(relPath)) {
        try { await _client!.removeAll(sourceRemotePath); } catch (_) {}
        if (localFiles[fileName] != null) {
          try { await localFiles[fileName]!.delete(); } catch (_) {}
        }
        continue;
      }

      File? localF = localFiles[fileName];

      if (isAsset && validAssets != null && !validAssets.contains(fileName)) {
        try { await _client!.removeAll(sourceRemotePath); debugPrint("🔥 焚毁云端亡灵附件: $fileName"); } catch(_) {}
        continue;
      }

      bool needDownload = localF == null;
      if (!isAsset && localF != null && remoteF.mTime != null) {
        needDownload = remoteF.mTime!.difference(localF.lastModifiedSync()).inSeconds > 2;
      }

      if (needDownload) {
        String targetLocalPath = p.join(localDirPath, fileName);
        debugPrint("⬇️ 下载: $fileName");
        await _client!.read2File(sourceRemotePath, targetLocalPath);
        
        try {
          if (remoteF.mTime != null) File(targetLocalPath).setLastModifiedSync(remoteF.mTime!);
        } catch (_) {}
        
        if (fileName.endsWith('.md')) dbNeedsRebuild = true;
      }
    }
    return dbNeedsRebuild;
  }

  // 💡 恢复之前被覆盖掉的注销方法
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // 1. 彻底清除存储在本地的账号密码
    await prefs.remove('webdav_url');
    await prefs.remove('webdav_user');
    await prefs.remove('webdav_pwd');
    
    // 2. 销毁当前内存中的客户端单例
    _client = null;
    _knownRemoteDirs.clear(); // 清空目录缓存
    debugPrint("✅ WebDAV 已断开连接，配置已清除");
  }
}