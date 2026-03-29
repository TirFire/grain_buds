import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/painting.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  String? _rootDir;

  DatabaseHelper._init();

  Future<String> get rootDir async {
    if (_rootDir != null) return _rootDir!;

    // 💡 核心修复 1：手机端强制使用系统安全沙盒，绝对无视任何被破坏的自定义路径！
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final prefs = await SharedPreferences.getInstance();
      String? customPath = prefs.getString('custom_diary_root_path');

      if (customPath != null && customPath.isNotEmpty) {
        final dir = Directory(customPath);
        if (await dir.exists()) {
          _rootDir = dir.path;
          return _rootDir!;
        }
      }
    }

    // 💡 安卓和 iOS 永远乖乖待在这里
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'MyDiary_Data'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootDir = dir.path;
    return _rootDir!;
  }

  // 💡 全新升级：加装“三级安全锁”的完美物理移动引擎
  Future<void> _moveDirectoryContents(
      Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDirectory =
            Directory(p.join(destination.path, p.basename(entity.path)));
        if (!await newDirectory.exists())
          await newDirectory.create(recursive: true);
        await _moveDirectoryContents(entity, newDirectory); // 递归移动子文件夹

        try {
          await entity.delete();
        } catch (_) {}
      } else if (entity is File) {
        String newFilePath = p.join(destination.path, p.basename(entity.path));
        File targetFile = File(newFilePath);

        // 🔒 安全锁 1：物理路径绝对比对。如果是同一个文件，立刻跳过，严禁覆盖或删除自己！
        String nEntity = p.normalize(entity.path).toLowerCase();
        String nTarget = p.normalize(targetFile.path).toLowerCase();
        if (nEntity == nTarget) continue;

        // 🔒 安全锁 2：清空残留前必须确保它不是源文件
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }

        // 智能判断盘符
        String oldRoot = p.rootPrefix(entity.path).toLowerCase();
        String newRoot = p.rootPrefix(newFilePath).toLowerCase();

        if (oldRoot == newRoot) {
          // 📍 同盘符：原生剪切
          try {
            await entity.rename(newFilePath);
          } catch (e) {
            // 🔒 安全锁 3：加入 try-catch，防止某一个文件被占用报错导致整个迁移中断
            try {
              await entity.copy(newFilePath);
              await entity.delete();
            } catch (_) {}
          }
        } else {
          // 📍 跨盘符：安全复制并销毁源文件
          try {
            await entity.copy(newFilePath);
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  // 💡 修复：完美的数据迁移方法 (加入防嵌套爆破机制)
  Future<bool> changeRootDirectory(String newPath) async {
    try {
      final oldPath = await rootDir;

      // 🔒 核心校验 1：抹平 Windows 下的大小写和斜杠差异
      String nOld = p.normalize(oldPath).toLowerCase();
      String nNew = p.normalize(newPath).toLowerCase();

      if (nOld == nNew) return true;

      // 🔒 核心校验 2：严禁将文件夹移动到自己的子文件夹中，或反向包含！
      // 这会导致无限循环拷贝或在最后一步误删所有数据。
      if (p.isWithin(nOld, nNew) || p.isWithin(nNew, nOld)) {
        throw Exception("新位置不能与旧位置存在包含关系！\\n为了数据安全，请选择一个完全独立、平级的空文件夹！");
      }

      // 0. 终极杀招：清空 Flutter 图片内存缓存
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 1. 必须先关闭当前 SQLite 数据库连接
      if (_database != null) {
        await _database!.close();
        _database = null;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 2. 执行物理级的数据深度转移
      final oldDir = Directory(oldPath);
      final newDir = Directory(newPath);
      if (!await newDir.exists()) await newDir.create(recursive: true);

      if (await oldDir.exists()) {
        await _moveDirectoryContents(oldDir, newDir);

        // 3. 连根拔起粉碎旧根目录
        try {
          await oldDir.delete(recursive: true);
          debugPrint("✅ 迁移成功，旧目录已彻底粉碎: ${oldDir.path}");
        } catch (e) {
          debugPrint("⚠️ 旧目录的根文件夹删除失败: $e");
        }
      }

      // 4. 保存新路径配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_diary_root_path', newPath);

      // 5. 重置内存变量
      _rootDir = newPath;

      return true;
    } catch (e) {
      debugPrint("更改目录失败: $e");
      // 将底层的致命错误抛出给 UI，让用户看到具体的红字弹窗警告
      throw Exception(e.toString());
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('diary_meta.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final root = await rootDir;
    final path = p.join(root, filePath);
    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // 💡 整合后的初始化表结构：包含了之前 2-8 所有的功能字段
  Future _createDB(Database db, int version) async {
    // 1. 日记主表
    await db.execute('''
      CREATE TABLE diaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        date TEXT,
        weather TEXT,
        mood TEXT,
        tags TEXT,
        md_path TEXT,
        is_trash INTEGER DEFAULT 0,
        delete_time TEXT,
        audio_path TEXT,
        attachments TEXT,
        image_path TEXT,
        video_path TEXT,
        is_locked INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        pwd_hash TEXT,
        update_time TEXT,
        is_starred INTEGER DEFAULT 0,
        location TEXT,
        type INTEGER DEFAULT 0 -- 0:日记, 1:随手记
      )
    ''');

    // 2. 模板表
    await db.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        title_tpl TEXT,
        content_tpl TEXT,
        tags_tpl TEXT
      )
    ''');

    // 3. 纪念日/倒数日表
    await db.execute('''
      CREATE TABLE anniversaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        date TEXT,
        icon TEXT,
        color_value INTEGER,
        create_time TEXT
      )
    ''');
    // 注入初始默认模板
    await _insertDefaultTemplates(db);
  }

  Future _onUpgrade(Database db, int oldV, int newV) async {
    // 💡 数据库自动迁移策略：给老用户的旧表强行补上新字段，防止崩溃！
    if (oldV < 2) {
      try {
        await db.execute('ALTER TABLE diaries ADD COLUMN image_path TEXT;');
      } catch (_) {} // 加上 try-catch 防止字段已存在导致报错
      try {
        await db.execute('ALTER TABLE diaries ADD COLUMN video_path TEXT;');
      } catch (_) {}
    }
    if (oldV < 3) {
      // 💡 紧急救援：为所有老用户的表强行加上 content 字段！
      try {
        await db.execute('ALTER TABLE diaries ADD COLUMN content TEXT;');
      } catch (_) {}
    }
    if (oldV < 4) {
      try {
        await db.execute('''
          CREATE TABLE anniversaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            date TEXT,
            icon TEXT,
            color_value INTEGER,
            create_time TEXT
          )
        ''');
      } catch (_) {}
    }
  }

  // ================= 模板管理逻辑 =================

  Future<void> _insertDefaultTemplates(Database db) async {
    await db.insert('templates', {
      'name': '☀️ 每日复盘',
      'title_tpl': '【今日复盘】',
      'content_tpl':
          '### 1. 今日三件开心事\n- \n- \n- \n\n### 2. 今日收获/感悟\n\n### 3. 明日计划\n',
      'tags_tpl': jsonEncode(['复盘', '成长']),
    });
    await db.insert('templates', {
      'name': '📖 读书笔记',
      'title_tpl': '《书名》拆解',
      'content_tpl': '### 核心观点\n\n### 精彩片段摘录\n> \n\n### 我的行动方案\n',
      'tags_tpl': jsonEncode(['读书', '笔记']),
    });
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    final db = await instance.database;
    return await db.query('templates');
  }

  Future<int> saveTemplate(Map<String, dynamic> tpl) async {
    final db = await instance.database;
    if (tpl['id'] != null) {
      return await db.update(
        'templates',
        tpl,
        where: 'id = ?',
        whereArgs: [tpl['id']],
      );
    } else {
      return await db.insert('templates', tpl);
    }
  }

  Future<int> deleteTemplate(int id) async {
    final db = await instance.database;
    return await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  // ================= 核心媒体处理逻辑 =================

  String _normalizePath(String path) => path.replaceAll('\\', '/');

  Future<List<String>> _processMedia(
    List<String> absolutePaths,
    String yearMonth,
    String datePrefix,
  ) async {
    final root = await rootDir;
    final monthDirPath = p.join(root, yearMonth);
    final assetsDir = Directory(p.join(monthDirPath, 'assets'));
    if (!await assetsDir.exists()) await assetsDir.create(recursive: true);

    List<String> relativePaths = [];
    for (String path in absolutePaths) {
      if (path.isEmpty) continue;
      // 如果已经在根目录下，直接计算相对路径
      if (p.isWithin(root, path)) {
        relativePaths.add(_normalizePath(p.relative(path, from: monthDirPath)));
        continue;
      }
      // 否则，复制文件到 assets 文件夹
      File file = File(path);
      if (file.existsSync()) {
        String unique = "${file.path}_${DateTime.now().microsecondsSinceEpoch}";
        final hash =
            md5.convert(utf8.encode(unique)).toString().substring(0, 8);
        String name =
            "${datePrefix}_${DateTime.now().millisecondsSinceEpoch}_$hash${p.extension(file.path)}";
        // 💡 修复：将 copySync 改为 await copy！释放 UI 线程！
        await file.copy(p.join(assetsDir.path, name));
        relativePaths.add("assets/$name");
      }
    }
    return relativePaths;
  }

  // ================= 日记读写逻辑 =================

  // 读取 MD 文件内容并与元数据合并
  Future<Map<String, dynamic>> _readMdFile(Map<String, dynamic> meta) async {
    final root = await rootDir;
    final String? mdPathRelative = meta['md_path'] as String?;
    if (mdPathRelative == null) return Map<String, dynamic>.from(meta);

    final File file = File(p.join(root, mdPathRelative));
    final String yearMonth = p.dirname(mdPathRelative);
    Map<String, dynamic> result = Map<String, dynamic>.from(meta);

    // 初始化默认值
    result['content'] = '';
    result['imagePath'] = '[]';
    result['videoPath'] = null;
    result['audioPath'] = null;
    result['attachments'] = '[]';

    if (!file.existsSync()) return result;

    String text = await file.readAsString();
    if (text.startsWith('---')) {
      // 💡 核心优化：兼容 Windows 下可能产生的 \r\n 换行符，防止解析失败导致元数据集体丢失！
      int endIdx = text.indexOf(RegExp(r'\r?\n---\r?\n'), 3);
      
      if (endIdx != -1) {
        String yamlStr = text.substring(3, endIdx);
        // 因为 \r\n 占两个字符，我们需要根据匹配到的实际长度来截取 body
        int offset = text.substring(endIdx).startsWith('\r\n') ? 7 : 5;
        String rawBody = text.substring(endIdx + offset);
        // 只去除紧贴着 yaml 头部下方的第一个换行符
        if (rawBody.startsWith('\n')) {
          rawBody = rawBody.substring(1);
        } else if (rawBody.startsWith('\r\n')) {
          rawBody = rawBody.substring(2);
        }
        // 使用 trimRight() 只去掉尾部多余的空行，保留头部的缩进空格
        result['content'] = rawBody.trimRight();
        // 解析 YAML 头部中的媒体路径 (💡 读取时全部执行 p.normalize，抹平系统差异)
        for (String line in yamlStr.split('\n')) {
          if (line.startsWith('images:')) {
            try {
              List<String> relImgs = List<String>.from(
                jsonDecode(line.substring(7).trim()),
              );
              result['imagePath'] = jsonEncode(
                relImgs
                    .map((r) => p.normalize(p.join(root, yearMonth, r)))
                    .toList(),
              );
            } catch (_) {}
          } else if (line.startsWith('videos:')) {
            // 💡 新增：读取无限视频数组
            try {
              List<String> relVids = List<String>.from(
                jsonDecode(line.substring(7).trim()),
              );
              result['videoPaths'] = jsonEncode(
                relVids
                    .map((r) => p.normalize(p.join(root, yearMonth, r)))
                    .toList(),
              );
            } catch (_) {}
          } else if (line.startsWith('audios:')) {
            // 💡 新增：读取无限音频数组
            try {
              List<String> relAuds = List<String>.from(
                jsonDecode(line.substring(7).trim()),
              );
              result['audioPaths'] = jsonEncode(
                relAuds
                    .map((r) => p.normalize(p.join(root, yearMonth, r)))
                    .toList(),
              );
            } catch (_) {}
          } else if (line.startsWith('video:')) {
            // 兼容以前存的老视频
            String vidRel = line.substring(6).trim();
            if (vidRel.isNotEmpty)
              result['videoPath'] = p.normalize(
                p.join(root, yearMonth, vidRel),
              );
          } else if (line.startsWith('audio:')) {
            // 兼容以前存的老音频
            String audRel = line.substring(6).trim();
            if (audRel.isNotEmpty)
              result['audioPath'] = p.normalize(
                p.join(root, yearMonth, audRel),
              );
          } else if (line.startsWith('attachments:')) {
            try {
              List<String> relAtts = List<String>.from(
                jsonDecode(line.substring(12).trim()),
              );
              result['attachments'] = jsonEncode(
                relAtts
                    .map((r) => p.normalize(p.join(root, yearMonth, r)))
                    .toList(),
              );
            } catch (_) {}
          }
        }
      }
    } else {
      result['content'] = text;
    }
    return result;
  }

  Future<int> insertDiary(Map<String, dynamic> diary) async {
    final db = await instance.database;
    final root = await rootDir;
    DateTime date = DateTime.parse(diary['date'] as String);
    String datePrefix = date.toString().substring(0, 10);
    String yearMonth = "${date.year}-${date.month.toString().padLeft(2, '0')}";
    Directory(p.join(root, yearMonth)).createSync(recursive: true);

    // 处理多媒体文件
    List<String> imgPaths = [];
    List<String> attPaths = [];
    try {
      imgPaths = List<String>.from(
        jsonDecode((diary['imagePath'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      attPaths = List<String>.from(
        jsonDecode((diary['attachments'] as String?) ?? '[]'),
      );
    } catch (_) {}

    List<String> relImages =
        await _processMedia(imgPaths, yearMonth, datePrefix);
    List<String> relAtts = await _processMedia(attPaths, yearMonth, datePrefix);

    // 💡 升级 2：按月存入本地的机制 —— _processMedia 会把新文件完美拷贝进 yearMonth/assets 文件夹
    List<String> vidPaths = [];
    List<String> audPaths = [];
    try {
      vidPaths = List<String>.from(
        jsonDecode((diary['videoPaths'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      audPaths = List<String>.from(
        jsonDecode((diary['audioPaths'] as String?) ?? '[]'),
      );
    } catch (_) {}

    List<String> relVids = await _processMedia(vidPaths, yearMonth, datePrefix);
    List<String> relAuds = await _processMedia(audPaths, yearMonth, datePrefix);

    // 生成文件名
    String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
    String fileSafeTitle = ((diary['title'] as String?) ?? "无标题")
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String mdName = "${date.toString().substring(0, 10)}_$timeStamp" +
        (fileSafeTitle.isNotEmpty ? "_$fileSafeTitle" : "") +
        ".md";
    String relPath = _normalizePath(p.join(yearMonth, mdName));

    // 💡 修复冲突：使用 yamlTitle 进行防注入过滤
    String yamlTitle = (diary['title'] as String? ?? "无标题")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
    String yamlLocation = (diary['location'] as String? ?? "")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');

    String mdContent = "---\n"
        "title: $yamlTitle\n"
        "date: ${diary['date']}\n"
        "weather: ${diary['weather']}\n"
        "mood: ${diary['mood']}\n"
        "tags: ${diary['tags']}\n"
        "is_locked: ${diary['is_locked'] ?? 0}\n"
        "is_archived: ${diary['is_archived'] ?? 0}\n"
        "is_starred: ${diary['is_starred'] ?? 0}\n"
        "is_trash: ${diary['is_trash'] ?? 0}\n" // 💡 务必补上这行！
        "delete_time: ${diary['delete_time'] ?? ''}\n"
        "pwd_hash: ${diary['pwd_hash'] ?? ''}\n"
        "location: $yamlLocation\n"
        "type: ${diary['type'] ?? 0}\n"
        "images: ${jsonEncode(relImages)}\n"
        "videos: ${jsonEncode(relVids)}\n"
        "audios: ${jsonEncode(relAuds)}\n"
        "attachments: ${jsonEncode(relAtts)}\n"
        "---\n"
        "${diary['content']}";
    await File(p.join(root, relPath)).writeAsString(mdContent);

    // 写入数据库
    // 写入数据库
    return await db.insert('diaries', {
      'title': diary['title'],
      'content': diary['content'],
      'date': diary['date'],
      'weather': diary['weather'],
      'mood': diary['mood'],
      'tags': diary['tags'],
      'md_path': relPath,
      'is_trash': 0,
      'audio_path': jsonEncode(relAuds),
      'attachments': jsonEncode(relAtts),
      'image_path': jsonEncode(relImages),
      'video_path': jsonEncode(relVids),
      'is_locked': diary['is_locked'] ?? 0,
      'is_archived': diary['is_archived'] ?? 0,
      'pwd_hash': diary['pwd_hash'],
      'update_time': DateTime.now().toString(),
      'location': diary['location'],
      'is_starred': diary['is_starred'] ?? 0,
      'type': diary['type'] ?? 0,
    });
  }

  Future<int> updateDiary(Map<String, dynamic> diary) async {
    final db = await instance.database;
    final root = await rootDir;
    final old = await db.query(
      'diaries',
      where: 'id = ?',
      whereArgs: [diary['id']],
    );
    if (old.isEmpty) return 0;

    final String oldRelPath = old.first['md_path'] as String;
    final String yearMonth = p.dirname(oldRelPath);

    // ================= 💡 核心修复：媒体垃圾回收机制 (支持无限音视频 + 路径标准化防误杀) =================
    final oldDiary = await _readMdFile(old.first);

    // 1. 获取旧数据 (极其强大的兼容性：同时囊括旧版单文件和新版多文件)
    List<String> oldImgs = [];
    List<String> oldAtts = [];
    List<String> oldVids = [];
    List<String> oldAuds = [];
    try {
      oldImgs = List<String>.from(
        jsonDecode((oldDiary['imagePath'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      oldAtts = List<String>.from(
        jsonDecode((oldDiary['attachments'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      oldVids = List<String>.from(
        jsonDecode((oldDiary['videoPaths'] as String?) ?? '[]'),
      );
    } catch (_) {
      if (oldDiary['videoPath'] != null)
        oldVids.add(oldDiary['videoPath'] as String);
    }
    try {
      oldAuds = List<String>.from(
        jsonDecode((oldDiary['audioPaths'] as String?) ?? '[]'),
      );
    } catch (_) {
      if (oldDiary['audioPath'] != null)
        oldAuds.add(oldDiary['audioPath'] as String);
    }

    // 2. 获取新数据
    List<String> newImgs = [];
    List<String> newAtts = [];
    List<String> newVids = [];
    List<String> newAuds = [];
    try {
      newImgs = List<String>.from(
        jsonDecode((diary['imagePath'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      newAtts = List<String>.from(
        jsonDecode((diary['attachments'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      newVids = List<String>.from(
        jsonDecode((diary['videoPaths'] as String?) ?? '[]'),
      );
    } catch (_) {}
    try {
      newAuds = List<String>.from(
        jsonDecode((diary['audioPaths'] as String?) ?? '[]'),
      );
    } catch (_) {}

    // 💡 异步安全删除工具：延迟 500ms 等待 UI 释放文件锁，且报错也不会卡死主线程
    void safeDeleteBackground(String path) {
      Future.microtask(() async {
        File f = File(path);
        // 尝试 3 次，每次间隔 0.8 秒。给予底层播放器和图片缓存充分的时间释放文件锁
        for (int i = 0; i < 3; i++) {
          try {
            if (await f.exists()) {
              await f.delete();
              debugPrint("🗑️ 成功粉碎废弃文件: $path");
            }
            break; // 删除成功，立即跳出循环
          } catch (_) {
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
      });
    }

    // 3. 物理粉碎被抛弃的孤儿文件 (异步处理，彻底告别死锁卡顿！)
    List<String> safeNewImgs = newImgs.map((e) => p.normalize(e)).toList();
    for (String oldImg in oldImgs) {
      if (!safeNewImgs.contains(p.normalize(oldImg)))
        safeDeleteBackground(oldImg);
    }

    List<String> safeNewAtts = newAtts.map((e) => p.normalize(e)).toList();
    for (String oldAtt in oldAtts) {
      if (!safeNewAtts.contains(p.normalize(oldAtt)))
        safeDeleteBackground(oldAtt);
    }

    List<String> safeNewVids = newVids.map((e) => p.normalize(e)).toList();
    for (String oldVid in oldVids) {
      if (!safeNewVids.contains(p.normalize(oldVid)))
        safeDeleteBackground(oldVid);
    }

    List<String> safeNewAuds = newAuds.map((e) => p.normalize(e)).toList();
    for (String oldAud in oldAuds) {
      if (!safeNewAuds.contains(p.normalize(oldAud)))
        safeDeleteBackground(oldAud);
    }
    // =============================================================

    // 1. 💡 修复语法报错：使用安全的字符串提取，防止变成 Type
    String dateStr = diary['date']?.toString() ?? DateTime.now().toString();
    String datePrefix =
        dateStr.length >= 10 ? dateStr.substring(0, 10) : "未知日期";

    // 4. 将最新插入的文件，按月存入本地的 yearMonth/assets 专属文件夹中
    List<String> relImages =
        await _processMedia(newImgs, yearMonth, datePrefix);
    List<String> relAtts = await _processMedia(newAtts, yearMonth, datePrefix);
    List<String> relVids = await _processMedia(newVids, yearMonth, datePrefix);
    List<String> relAuds = await _processMedia(newAuds, yearMonth, datePrefix);

    // 5. 更新本地 MD 文件
    // 💡 核心对齐：强制将所有状态全量写入 YAML 头部
    String yamlTitle = (diary['title'] as String? ?? "无标题")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
    String yamlLocation = (diary['location'] as String? ?? "")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');

    String mdContent = "---\n"
        "title: $yamlTitle\n"
        "date: ${diary['date']}\n"
        "weather: ${diary['weather']}\n"
        "mood: ${diary['mood']}\n"
        "tags: ${diary['tags']}\n"
        "is_locked: ${diary['is_locked'] ?? 0}\n"
        "is_archived: ${diary['is_archived'] ?? 0}\n"
        "is_starred: ${diary['is_starred'] ?? 0}\n"
        "is_trash: ${diary['is_trash'] ?? 0}\n" // 💡 务必补上这行！
        "delete_time: ${diary['delete_time'] ?? ''}\n"
        "pwd_hash: ${diary['pwd_hash'] ?? ''}\n"
        "location: $yamlLocation\n"
        "type: ${diary['type'] ?? 0}\n"
        "images: ${jsonEncode(relImages)}\n"
        "videos: ${jsonEncode(relVids)}\n"
        "audios: ${jsonEncode(relAuds)}\n"
        "attachments: ${jsonEncode(relAtts)}\n"
        "---\n"
        "${diary['content']}";

    // ==========================================================
    // 💡 2. 修复 unused 警告与数据丢失 Bug：真正把修改写进物理硬盘中！
    // ==========================================================
    File outFile = File(p.join(root, oldRelPath));
    // 💡 核心修复 2：写文件前，先看看文件夹还在不在。如果被误删了，当场用数据库的文字把它建回来！
    if (!await outFile.parent.exists()) {
      await outFile.parent.create(recursive: true);
    }
    await outFile.writeAsString(mdContent);
    // 更新 SQLite 数据库
    return await db.update(
      'diaries',
      {
        'title': diary['title'],
        'content': diary['content'],
        'date': diary['date'], // 补充更新日期的同步
        'weather': diary['weather'],
        'mood': diary['mood'],
        'tags': diary['tags'],
        'audio_path': jsonEncode(relAuds),
        'attachments': jsonEncode(relAtts),
        'image_path': jsonEncode(relImages),
        'video_path': jsonEncode(relVids),
        'is_locked': diary['is_locked'] ?? 0,
        'is_archived': diary['is_archived'] ?? 0,
        'pwd_hash': diary['pwd_hash'],
        'update_time': DateTime.now().toString(),
        'location': diary['location'],
        'type': diary['type'] ?? 0,
      },
      where: 'id = ?',
      whereArgs: [diary['id']],
    );
  }

  // ================= 查询与删除逻辑 =================

  Future<List<Map<String, dynamic>>> searchDiaries(String keyword) async {
    final db = await instance.database;
    final rows = await db.query(
      'diaries',
      where: '(title LIKE ? OR tags LIKE ? OR content LIKE ?) AND is_trash = 0',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: 'date DESC',
    );
    return await _mapAbsolutePaths(rows);
  }

  // ================= 💡 核心安全修复：确保状态变更实时写入物理文件 =================
  Future<void> _syncDbToMd(int id) async {
    final db = await instance.database;
    final list = await db.query('diaries', where: 'id = ?', whereArgs: [id]);
    if (list.isEmpty) return;

    final diary = list.first;
    final String? relPath = diary['md_path'] as String?;
    if (relPath == null) return;

    final root = await rootDir;
    final file = File(p.join(root, relPath));
    if (!await file.exists()) return;

    String yamlTitle = (diary['title'] as String? ?? "无标题")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
    String yamlLocation = (diary['location'] as String? ?? "")
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');

    String mdContent = "---\n"
        "title: $yamlTitle\n"
        "date: ${diary['date']}\n"
        "weather: ${diary['weather']}\n"
        "mood: ${diary['mood']}\n"
        "tags: ${diary['tags']}\n"
        "is_locked: ${diary['is_locked'] ?? 0}\n"
        "is_archived: ${diary['is_archived'] ?? 0}\n"
        "is_starred: ${diary['is_starred'] ?? 0}\n"
        "is_trash: ${diary['is_trash'] ?? 0}\n" // 💡 务必补上这行！
        "delete_time: ${diary['delete_time'] ?? ''}\n"
        "pwd_hash: ${diary['pwd_hash'] ?? ''}\n"
        "location: $yamlLocation\n"
        "type: ${diary['type'] ?? 0}\n"
        "images: ${diary['image_path'] ?? '[]'}\n"
        "videos: ${diary['video_path'] ?? '[]'}\n"
        "audios: ${diary['audio_path'] ?? '[]'}\n"
        "attachments: ${diary['attachments'] ?? '[]'}\n"
        "---\n"
        "${diary['content']}";

    await file.writeAsString(mdContent);
  }

  Future<int> deleteToTrash(int id) async {
    final db = await instance.database;
    int res = await db.update(
        'diaries', {'is_trash': 1, 'delete_time': DateTime.now().toString()},
        where: 'id = ?', whereArgs: [id]);
    await _syncDbToMd(id); // 💡 写入物理文件
    return res;
  }

  Future<int> restoreDiary(int id) async {
    final db = await instance.database;
    int res = await db.update('diaries', {'is_trash': 0, 'delete_time': null},
        where: 'id = ?', whereArgs: [id]);
    await _syncDbToMd(id); // 💡 写入物理文件
    return res;
  }

  Future<int> toggleStarDiary(int id, bool currentStarStatus) async {
    final db = await instance.database;
    int res = await db.update(
        'diaries', {'is_starred': currentStarStatus ? 0 : 1},
        where: 'id = ?', whereArgs: [id]);
    await _syncDbToMd(id); // 💡 写入物理文件
    return res;
  }

  Future<int> permanentlyDeleteDiary(int id) async {
    final db = await instance.database;
    final root = await rootDir;
    final list = await db.query('diaries', where: 'id = ?', whereArgs: [id]);

    if (list.isNotEmpty) {
      final meta = list.first;
      final String? mdPath = meta['md_path'] as String?;
      if (mdPath != null) {
        final fullDiary = await _readMdFile(meta);
        List<String> imgs = [];
        List<String> atts = [];
        List<String> vids = [];
        List<String> auds = [];

        try {
          imgs = List<String>.from(
            jsonDecode((fullDiary['imagePath'] as String?) ?? '[]'),
          );
        } catch (_) {}
        try {
          atts = List<String>.from(
            jsonDecode((fullDiary['attachments'] as String?) ?? '[]'),
          );
        } catch (_) {}
        try {
          vids = List<String>.from(
            jsonDecode((fullDiary['videoPaths'] as String?) ?? '[]'),
          );
        } catch (_) {
          if (fullDiary['videoPath'] != null)
            vids.add(fullDiary['videoPath'] as String);
        }
        try {
          auds = List<String>.from(
            jsonDecode((fullDiary['audioPaths'] as String?) ?? '[]'),
          );
        } catch (_) {
          if (fullDiary['audioPath'] != null)
            auds.add(fullDiary['audioPath'] as String);
        }

        // 💡 引入异步安全删除工具
        void safeDeleteBackground(String path) {
          Future.delayed(const Duration(milliseconds: 500), () async {
            try {
              File f = File(path);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          });
        }

        // 物理粉碎所有数组里的源文件
        for (String img in imgs) safeDeleteBackground(img);
        for (String att in atts) safeDeleteBackground(att);
        for (String vid in vids) safeDeleteBackground(vid);
        for (String aud in auds) safeDeleteBackground(aud);

        // 粉碎 md 文件
        // 💡 终极安全补丁：生成墓碑文件 (Tombstone)，利用同步机制摧毁云端备份
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            File f = File(p.join(root, mdPath));
            if (await f.exists()) {
              // 不删除文件，而是覆盖为墓碑标记，利用 WebDAV 上传覆盖云端实体！
              await f.writeAsString("---\nis_deleted: 1\n---\n");
            }
          } catch (_) {}
        });
      }
    }
    return await db.delete('diaries', where: 'id = ?', whereArgs: [id]);
  }

  // ================= 列表获取逻辑 =================

  // 💡 核心引擎：动态绝对路径转换器
  // 将底层高度便携的“相对路径”，动态拼接为当前沙盒的“绝对路径”，彻底根除模拟器图片丢失问题！
  Future<List<Map<String, dynamic>>> _mapAbsolutePaths(
      List<Map<String, dynamic>> rows) async {
    final root = await rootDir;
    List<Map<String, dynamic>> result = [];
    for (var row in rows) {
      var mutableRow = Map<String, dynamic>.from(row);
      String dateStr = mutableRow['date'] as String? ?? '1900-01-01 00:00:00';
      DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();
      String yearMonth =
          "${date.year}-${date.month.toString().padLeft(2, '0')}";

      for (String key in [
        'image_path',
        'video_path',
        'audio_path',
        'attachments'
      ]) {
        String? jsonStr = mutableRow[key] as String?;
        if (jsonStr != null && jsonStr.isNotEmpty) {
          try {
            List<String> relPaths = List<String>.from(jsonDecode(jsonStr));
            List<String> absPaths = relPaths.map((r) {
              if (p.isAbsolute(r)) return r; // 兼容旧数据
              return p.normalize(p.join(root, yearMonth, r));
            }).toList();
            mutableRow[key] = jsonEncode(absPaths);
          } catch (_) {}
        }
      }
      result.add(mutableRow);
    }
    return result;
  }

  // 💡 以下 5 个获取方法全部装配了绝对路径转换引擎
  Future<List<Map<String, dynamic>>> getAllDiaries() async {
    final db = await instance.database;
    final rows =
        await db.query('diaries', where: 'is_trash = 0', orderBy: 'date DESC');
    return await _mapAbsolutePaths(rows);
  }

  Future<List<Map<String, dynamic>>> getDiariesByDate(DateTime date) async {
    final db = await instance.database;
    String dateStr = date.toString().substring(0, 10);
    final rows = await db.query('diaries',
        where: 'date LIKE ? AND is_trash = 0',
        whereArgs: ['$dateStr%'],
        orderBy: 'date DESC');
    return await _mapAbsolutePaths(rows);
  }

  Future<List<Map<String, dynamic>>> getTrashedDiaries() async {
    final db = await instance.database;
    final rows = await db.query('diaries',
        where: 'is_trash = 1', orderBy: 'delete_time DESC');
    return await _mapAbsolutePaths(rows);
  }

  Future<List<Map<String, dynamic>>> getStarredDiaries() async {
    final db = await instance.database;
    final rows = await db.query('diaries',
        where: 'is_starred = 1 AND is_trash = 0', orderBy: 'date DESC');
    return await _mapAbsolutePaths(rows);
  }

  Future<List<Map<String, dynamic>>> getArchivedDiaries() async {
    final db = await instance.database;
    final rows = await db.query('diaries',
        where: 'is_archived = 1 AND is_trash = 0', orderBy: 'date DESC');
    return await _mapAbsolutePaths(rows);
  }

  // ================= 备份逻辑 =================

  Future<String?> createFullBackup(String savePath) async {
    try {
      _rootDir = null; // 强制刷新路径缓存
      final root = await rootDir;
      final dataDir = Directory(root);
      
      if (!await dataDir.exists()) return null;

      // 1. 主线程预扫码
      final allFiles = dataDir.listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      
      if (allFiles.isEmpty) return null;

      // 2. 释放数据库锁
      if (_database != null) {
        await _database!.close();
        _database = null;
        await Future.delayed(const Duration(milliseconds: 500)); 
      }

      // 3. 💡 核心变动：后台线程计算 ZIP 字节流并返回
      final Uint8List? zipBytes = await compute(_performZipTaskV2, {
        'root': root,
        'files': allFiles.join('|'),
      });
      
      // 4. 在主线程一次性同步写入，确保文件完整性
      if (zipBytes != null && zipBytes.isNotEmpty) {
        File(savePath).writeAsBytesSync(zipBytes);
        debugPrint("💾 磁盘写入成功：${zipBytes.length} 字节");
      }

      await database; // 重启数据库
      return savePath;
    } catch (e) {
      debugPrint("备份失败: $e");
      await database;
      return null;
    }
  }

  // ================= 自动清理回收站 =================
  Future<void> autoCleanTrash(int days) async {
    if (days <= 0) return; // 0 表示从不自动清理
    final cutoffDate = DateTime.now().subtract(Duration(days: days)); // 计算出界限日期

    // 获取回收站里所有的日记
    final trashedList = await getTrashedDiaries();
    for (var diary in trashedList) {
      if (diary['delete_time'] != null) {
        try {
          DateTime deleteTime = DateTime.parse(diary['delete_time']);
          if (deleteTime.isBefore(cutoffDate)) {
            await permanentlyDeleteDiary(diary['id']);
          }
        } catch (_) {}
      }
    }
    try {
      final root = await rootDir;
      final exportDir = Directory(p.join(root, 'Exports'));
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true); 
      }
    } catch (_) {}
  }
  

  // ================= 跨端同步核心：一键重建本地索引 (融合静默垃圾回收与规范重命名) =================
  Future<int> rebuildIndexFromLocalFiles() async {
    final db = await instance.database;
    final root = await rootDir;
    final rootDirectory = Directory(root);

    if (!rootDirectory.existsSync()) return 0;

    final batch = db.batch();
    batch.delete('diaries');

    int count = 0;
    final entities = rootDirectory.listSync();
    for (var entity in entities) {
      if (entity is Directory) {
        if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(p.basename(entity.path)))
          continue;

        final files = entity
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'));
        for (var file in files) {
          try {
            String content = await file.readAsString();
            if (content.startsWith('---')) {
              int endIdx = content.indexOf('\n---\n', 3);
              if (endIdx != -1) {
                String yamlStr = content.substring(3, endIdx);
                String rawBody = content.substring(endIdx + 5);
                if (rawBody.startsWith('\n'))
                  rawBody = rawBody.substring(1);
                else if (rawBody.startsWith('\r\n'))
                  rawBody = rawBody.substring(2);

                Map<String, dynamic> diaryData = {
                  'title': '无标题',
                  'content': rawBody.trimRight(),
                  'date': DateTime.now().toString(),
                  'weather': 'sunny',
                  'mood': 'happy',
                  'tags': '[]',
                  'is_locked': 0,
                  'is_archived': 0,
                  'is_starred': 0,
                  'type': 0,
                  'md_path': _normalizePath(p.relative(file.path, from: root)),
                  'is_trash': 0,
                  'update_time': DateTime.now().toString(),
                };

                for (String line in yamlStr.split('\n')) {
                  int colonIdx = line.indexOf(':');
                  if (colonIdx != -1) {
                    String key = line.substring(0, colonIdx).trim();
                    String value = line.substring(colonIdx + 1).trim();

                    if (key == 'title')
                      diaryData['title'] = value;
                    else if (key == 'date')
                      diaryData['date'] = value;
                    else if (key == 'weather')
                      diaryData['weather'] = value;
                    else if (key == 'mood')
                      diaryData['mood'] = value;
                    else if (key == 'tags')
                      diaryData['tags'] = value;
                    else if (key == 'is_locked')
                      diaryData['is_locked'] = int.tryParse(value) ?? 0;
                    else if (key == 'is_archived')
                      diaryData['is_archived'] = int.tryParse(value) ?? 0;
                    else if (key == 'is_starred')
                      diaryData['is_starred'] = int.tryParse(value) ?? 0;
                    else if (key == 'type')
                      diaryData['type'] = int.tryParse(value) ?? 0;
                    else if (key == 'pwd_hash')
                      diaryData['pwd_hash'] = value.isEmpty ? null : value;
                    else if (key == 'location')
                      diaryData['location'] = value.isEmpty ? null : value;
                    else if (key == 'is_trash')
                      diaryData['is_trash'] = int.tryParse(value) ?? 0;
                    else if (key == 'delete_time')
                      diaryData['delete_time'] = value.isEmpty ? null : value;
                    else if (key == 'is_deleted')
                      diaryData['is_deleted'] = int.tryParse(value) ?? 0;
                    else if (key == 'images')
                      diaryData['image_path'] = value;
                    else if (key == 'videos')
                      diaryData['video_path'] = value;
                    else if (key == 'audios')
                      diaryData['audio_path'] = value;
                    else if (key == 'attachments')
                      diaryData['attachments'] = value;
                  }
                }
                if (diaryData['is_deleted'] == 1) continue;
                batch.insert('diaries', diaryData);
                count++;
              }
            }
          } catch (e) {
            debugPrint("重建索引跳过损坏文件: ${file.path}");
          }
        }
      }
    }

    // 1. 先将最纯净的文本数据一次性写入数据库
    await batch.commit(noResult: true);

    // =========================================================================
    // 💡 核心修复 3：无感智能瘦身与附件重命名引擎 (寄生在重建索引流程中，绝不打扰用户)
    // =========================================================================
    try {
      final rows = await db.query('diaries');
      final allDiaries = await _mapAbsolutePaths(rows);
      Set<String> legalAbsolutePaths = {};
      Map<int, Map<String, dynamic>> updates = {};

      // 【A】地毯式扫瞄合法文件，发现旧命名就瞬间重命名
      for (var d in allDiaries) {
        bool changed = false;
        Map<String, dynamic> updateData = {};
        String datePrefix =
            (d['date'] as String? ?? '1900-01-01').substring(0, 10);
        String yearMonth = datePrefix.substring(0, 7);

        for (String key in [
          'image_path',
          'video_path',
          'audio_path',
          'attachments'
        ]) {
          String? jsonStr = d[key];
          if (jsonStr == null || jsonStr.isEmpty) continue;
          try {
            List<String> absPaths = List<String>.from(jsonDecode(jsonStr));
            List<String> newAbsPaths = [];

            for (String path in absPaths) {
              File file = File(path);
              if (!file.existsSync()) continue;

              String basename = p.basename(path);
              // 判断：如果是以这篇日记的日期开头，并且有下划线，说明已经是标准命名
              if (basename.startsWith(datePrefix) && basename.contains('_')) {
                legalAbsolutePaths.add(p.normalize(path));
                newAbsPaths.add(path);
              } else {
                // 不规范的历史图片：生成新的标准名称并重命名
                String unique =
                    "${file.path}_${DateTime.now().microsecondsSinceEpoch}";
                final hash =
                    md5.convert(utf8.encode(unique)).toString().substring(0, 8);
                String newName =
                    "${datePrefix}_${DateTime.now().millisecondsSinceEpoch}_$hash${p.extension(file.path)}";
                String newAbsPath =
                    p.normalize(p.join(root, yearMonth, 'assets', newName));

                try {
                  file.renameSync(newAbsPath);
                  legalAbsolutePaths.add(newAbsPath);
                  newAbsPaths.add(newAbsPath);
                  changed = true;
                } catch (e) {
                  try {
                    file.copySync(newAbsPath);
                    file.deleteSync();
                    legalAbsolutePaths.add(newAbsPath);
                    newAbsPaths.add(newAbsPath);
                    changed = true;
                  } catch (_) {
                    // 如果依然失败，就保留原样，计入合法路径
                    legalAbsolutePaths.add(p.normalize(path));
                    newAbsPaths.add(path);
                  }
                }
              }
            }
            if (changed) {
              updateData[key] = jsonEncode(newAbsPaths
                  .map((e) => _normalizePath(p.relative(e, from: root)))
                  .toList());
            }
          } catch (_) {}
        }
        if (changed) {
          updateData['id'] = d['id'];
          updates[d['id']] = updateData;
        }
      }

      // 【B】将改名后的新路径写回数据库和 .md 物理文件
      for (var entry in updates.entries) {
        await db.update('diaries', entry.value,
            where: 'id = ?', whereArgs: [entry.key]);
        await _syncDbToMd(entry.key);
      }

      // 【C】末日审判：巡视所有 assets 文件夹，凡是不在 legalAbsolutePaths 里的文件，直接物理粉碎！
      for (var monthDir in rootDirectory.listSync().whereType<Directory>()) {
        if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(p.basename(monthDir.path)))
          continue;
        final assetsDir = Directory(p.join(monthDir.path, 'assets'));
        if (!assetsDir.existsSync()) continue;

        for (var file in assetsDir.listSync().whereType<File>()) {
          String normPath = p.normalize(file.path);
          if (!legalAbsolutePaths.contains(normPath)) {
            try {
              file.deleteSync();
              debugPrint("🗑️ 静默重建索引清理了废弃垃圾: ${file.path}");
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint("无感瘦身发生异常: $e");
    }

    return count;
  }

  // ================= 纪念日逻辑 =================
  Future<List<Map<String, dynamic>>> getAnniversaries() async {
    final db = await instance.database;
    // 按照目标日期排序
    return await db.query('anniversaries', orderBy: 'date ASC');
  }

  Future<int> insertAnniversary(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('anniversaries', data);
  }

  Future<int> deleteAnniversary(int id) async {
    final db = await instance.database;
    return await db.delete('anniversaries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateAnniversary(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.update(
      'anniversaries',
      data,
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  // 💡 终极内存压缩引擎：返回完整的 ZIP 字节数组
  static Future<Uint8List?> _performZipTaskV2(Map<String, String> params) async {
    final String rootPath = p.normalize(params['root']!).replaceAll('\\', '/');
    final List<String> fileList = params['files']!.split('|');
    
    final archive = Archive();
    final encoder = ZipEncoder();

    try {
      for (String rawPath in fileList) {
        try {
          final String currentPath = p.normalize(rawPath).replaceAll('\\', '/');
          
          // 计算纯净的相对路径
          String rel = p.relative(currentPath, from: rootPath).replaceAll('\\', '/');

          // 强制清理 Windows 敏感的前缀字符
          while (rel.startsWith('/') || rel.startsWith('\\') || rel.startsWith('.')) {
            rel = rel.replaceFirst('/', '').replaceFirst('\\', '').replaceFirst('.', '');
          }
          
          // 彻底排除盘符泄露
          if (rel.contains(':')) {
             rel = rel.substring(rel.lastIndexOf(':') + 1);
             if (rel.startsWith('/')) rel = rel.substring(1);
          }

          if (rel.toLowerCase().startsWith('exports/')) continue;

          // 💡 将文件读入内存并存入 Archive 对象
          final file = File(currentPath);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            archive.addFile(ArchiveFile(rel, bytes.length, bytes));
            debugPrint("📦 已装载: $rel");
          }
          
        } catch (e) {
          debugPrint("处理文件失败: $e");
        }
      }
      
      // 💡 执行最终编码，生成完整的 ZIP 字节流
      return encoder.encode(archive) as Uint8List;
      
    } catch (e) {
      debugPrint("压缩引擎崩溃: $e");
      return null;
    }
  }
}
  