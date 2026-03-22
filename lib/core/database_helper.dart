import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; 

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  String? _rootDir;

  DatabaseHelper._init();

  // 获取数据存储根目录 (用户文档/MyDiary_Data)
  Future<String> get rootDir async {
    if (_rootDir != null) return _rootDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'MyDiary_Data'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootDir = dir.path;
    return _rootDir!;
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
      version: 1, // 💡 正式发布起点，重置为 1
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
        date TEXT,
        weather TEXT,
        mood TEXT,
        tags TEXT,
        md_path TEXT,
        is_trash INTEGER DEFAULT 0,
        delete_time TEXT,
        audio_path TEXT,
        attachments TEXT,
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

    // 注入初始默认模板
    await _insertDefaultTemplates(db);
  }

  Future _onUpgrade(Database db, int oldV, int newV) async {
    // 初始发布为 V1，此方法暂时留空，供未来 V2 升级使用
  }

  // ================= 模板管理逻辑 =================

  Future<void> _insertDefaultTemplates(Database db) async {
    await db.insert('templates', {
      'name': '☀️ 每日复盘', 
      'title_tpl': '【今日复盘】', 
      'content_tpl': '### 1. 今日三件开心事\n- \n- \n- \n\n### 2. 今日收获/感悟\n\n### 3. 明日计划\n', 
      'tags_tpl': jsonEncode(['复盘', '成长'])
    });
    await db.insert('templates', {
      'name': '📖 读书笔记', 
      'title_tpl': '《书名》拆解', 
      'content_tpl': '### 核心观点\n\n### 精彩片段摘录\n> \n\n### 我的行动方案\n', 
      'tags_tpl': jsonEncode(['读书', '笔记'])
    });
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    final db = await instance.database;
    return await db.query('templates');
  }

  Future<int> saveTemplate(Map<String, dynamic> tpl) async {
    final db = await instance.database;
    if (tpl['id'] != null) {
      return await db.update('templates', tpl, where: 'id = ?', whereArgs: [tpl['id']]);
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

  Future<List<String>> _processMedia(List<String> absolutePaths, String yearMonth) async {
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
        final hash = md5.convert(utf8.encode(unique)).toString().substring(0, 8);
        String name = "${DateTime.now().millisecondsSinceEpoch}_$hash${p.extension(file.path)}";
        file.copySync(p.join(assetsDir.path, name));
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
      int endIdx = text.indexOf('\n---\n', 3);
      if (endIdx != -1) {
        String yamlStr = text.substring(3, endIdx);
        result['content'] = text.substring(endIdx + 5).trim();
        // 解析 YAML 头部中的媒体路径
        for (String line in yamlStr.split('\n')) {
          if (line.startsWith('images:')) {
            try { 
              List<String> relImgs = List<String>.from(jsonDecode(line.substring(7).trim())); 
              result['imagePath'] = jsonEncode(relImgs.map((r) => p.join(root, yearMonth, r)).toList()); 
            } catch (_) {}
          } else if (line.startsWith('video:')) {
            String vidRel = line.substring(6).trim(); 
            if (vidRel.isNotEmpty) result['videoPath'] = p.join(root, yearMonth, vidRel);
          } else if (line.startsWith('audio:')) {
            String audRel = line.substring(6).trim(); 
            if (audRel.isNotEmpty) result['audioPath'] = p.join(root, yearMonth, audRel);
          } else if (line.startsWith('attachments:')) {
            try { 
              List<String> relAtts = List<String>.from(jsonDecode(line.substring(12).trim())); 
              result['attachments'] = jsonEncode(relAtts.map((r) => p.join(root, yearMonth, r)).toList()); 
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
    String yearMonth = "${date.year}-${date.month.toString().padLeft(2, '0')}";
    Directory(p.join(root, yearMonth)).createSync(recursive: true);

    // 处理多媒体文件
    List<String> imgPaths = [];
    List<String> attPaths = [];
    try { imgPaths = List<String>.from(jsonDecode((diary['imagePath'] as String?) ?? '[]')); } catch(_) {}
    try { attPaths = List<String>.from(jsonDecode((diary['attachments'] as String?) ?? '[]')); } catch(_) {}
    
    List<String> relImages = await _processMedia(imgPaths, yearMonth);
    List<String> relAtts = await _processMedia(attPaths, yearMonth);
    
    String relVideo = "";
    if (diary['videoPath'] != null) {
      var v = await _processMedia([diary['videoPath'] as String], yearMonth);
      if (v.isNotEmpty) relVideo = v.first;
    }

    String relAudio = "";
    if (diary['audioPath'] != null) {
      var a = await _processMedia([diary['audioPath'] as String], yearMonth);
      if (a.isNotEmpty) relAudio = a.first;
    }

    // 生成文件名
    String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
    String safeTitle = ((diary['title'] as String?) ?? "无标题")
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    String mdName = "${date.toString().substring(0, 10)}_$timeStamp" + 
                    (safeTitle.isNotEmpty ? "_$safeTitle" : "") + ".md";
    
    String relPath = _normalizePath(p.join(yearMonth, mdName));

    // 💡 修复：在这里补全物理文件的写入逻辑！
    // 只有把内容写进硬盘，下次读取时内容才不会消失
    String mdContent = "---\ntitle: ${diary['title']}\ndate: ${diary['date']}\nweather: ${diary['weather']}\nmood: ${diary['mood']}\ntags: ${diary['tags']}\nimages: ${jsonEncode(relImages)}\nvideo: $relVideo\naudio: $relAudio\nattachments: ${jsonEncode(relAtts)}\n---\n${diary['content']}";
    await File(p.join(root, relPath)).writeAsString(mdContent);

    // 写入数据库
    return await db.insert('diaries', {
      'title': diary['title'], 'date': diary['date'], 'weather': diary['weather'],
      'mood': diary['mood'], 'tags': diary['tags'], 'md_path': relPath, 'is_trash': 0,
      'audio_path': relAudio, 'attachments': jsonEncode(relAtts),
      'is_locked': diary['is_locked'] ?? 0, 'is_archived': diary['is_archived'] ?? 0, 'pwd_hash': diary['pwd_hash'],
      'update_time': DateTime.now().toString(),
      'location': diary['location'],
      'is_starred': diary['is_starred'] ?? 0,
      'type': diary['type'] ?? 0,
    });
  }

  Future<int> updateDiary(Map<String, dynamic> diary) async {
    final db = await instance.database;
    final root = await rootDir;
    final old = await db.query('diaries', where: 'id = ?', whereArgs: [diary['id']]);
    if (old.isEmpty) return 0;
    
    final String oldRelPath = old.first['md_path'] as String;
    final String yearMonth = p.dirname(oldRelPath);

    List<String> imgPaths = [];
    List<String> attPaths = [];
    try { imgPaths = List<String>.from(jsonDecode((diary['imagePath'] as String?) ?? '[]')); } catch(_) {}
    try { attPaths = List<String>.from(jsonDecode((diary['attachments'] as String?) ?? '[]')); } catch(_) {}
    
    List<String> relImages = await _processMedia(imgPaths, yearMonth);
    List<String> relAtts = await _processMedia(attPaths, yearMonth);
    
    String relVideo = "";
    if (diary['videoPath'] != null) {
      var v = await _processMedia([diary['videoPath'] as String], yearMonth);
      if (v.isNotEmpty) relVideo = v.first;
    }

    String relAudio = "";
    if (diary['audioPath'] != null) {
      var a = await _processMedia([diary['audioPath'] as String], yearMonth);
      if (a.isNotEmpty) relAudio = a.first;
    }

    // 更新 MD 文件
    String mdContent = "---\ntitle: ${diary['title']}\ndate: ${diary['date']}\nweather: ${diary['weather']}\nmood: ${diary['mood']}\ntags: ${diary['tags']}\nimages: ${jsonEncode(relImages)}\nvideo: $relVideo\naudio: $relAudio\nattachments: ${jsonEncode(relAtts)}\n---\n${diary['content']}";
    await File(p.join(root, oldRelPath)).writeAsString(mdContent);

    return await db.update('diaries', {
      'title': diary['title'], 'weather': diary['weather'], 'mood': diary['mood'], 'tags': diary['tags'],
      'audio_path': relAudio, 'attachments': jsonEncode(relAtts),
      'is_locked': diary['is_locked'] ?? 0, 'is_archived': diary['is_archived'] ?? 0, 'pwd_hash': diary['pwd_hash'],
      'update_time': DateTime.now().toString(),
      'location': diary['location'],
      'type': diary['type'] ?? 0,
    }, where: 'id = ?', whereArgs: [diary['id']]);
  }

  // ================= 查询与删除逻辑 =================

  Future<List<Map<String, dynamic>>> searchDiaries(String keyword) async {
    final db = await instance.database;
    final metaList = await db.query('diaries', where: '(title LIKE ? OR tags LIKE ?) AND is_trash = 0', whereArgs: ['%$keyword%', '%$keyword%'], orderBy: 'date DESC');
    Set<int> foundIds = metaList.map((m) => m['id'] as int).toSet();
    List<Map<String, dynamic>> fullResults = [];
    for(var m in metaList) fullResults.add(await _readMdFile(m));

    final allMeta = await db.query('diaries', where: 'is_trash = 0');
    for (var m in allMeta) {
      if (foundIds.contains(m['id'])) continue;
      final fullDiary = await _readMdFile(m);
      if ((fullDiary['content'] ?? '').toString().toLowerCase().contains(keyword.toLowerCase())) fullResults.add(fullDiary);
    }
    fullResults.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return fullResults;
  }

  Future<int> deleteToTrash(int id) async {
    final db = await instance.database;
    return await db.update('diaries', {'is_trash': 1, 'delete_time': DateTime.now().toString()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> restoreDiary(int id) async {
    final db = await instance.database;
    return await db.update('diaries', {'is_trash': 0, 'delete_time': null}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> permanentlyDeleteDiary(int id) async {
    final db = await instance.database;
    final root = await rootDir;
    final list = await db.query('diaries', where: 'id = ?', whereArgs: [id]);

    if (list.isNotEmpty) {
       final meta = list.first;
       final String? mdPath = meta['md_path'] as String?;
       if (mdPath != null) {
           File mdFile = File(p.join(root, mdPath));
           if (mdFile.existsSync()) {
               final fullDiary = await _readMdFile(meta);
               List<String> imgs = []; List<String> atts = [];
               try { imgs = List<String>.from(jsonDecode((fullDiary['imagePath'] as String?) ?? '[]')); } catch(_) {}
               try { atts = List<String>.from(jsonDecode((fullDiary['attachments'] as String?) ?? '[]')); } catch(_) {}
               for (String img in imgs) { File f = File(img); if (f.existsSync()) f.deleteSync(); }
               for (String att in atts) { File f = File(att); if (f.existsSync()) f.deleteSync(); }
               if (fullDiary['videoPath'] != null) { File f = File(fullDiary['videoPath'] as String); if (f.existsSync()) f.deleteSync(); }
               if (fullDiary['audioPath'] != null) { File f = File(fullDiary['audioPath'] as String); if (f.existsSync()) f.deleteSync(); }
               mdFile.deleteSync();
           }
       }
    }
    return await db.delete('diaries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> toggleStarDiary(int id, bool currentStarStatus) async {
    final db = await instance.database;
    return await db.update('diaries', {'is_starred': currentStarStatus ? 0 : 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ================= 列表获取逻辑 =================

  Future<List<Map<String, dynamic>>> getAllDiaries() async {
    final db = await instance.database;
    final metaList = await db.query('diaries', where: 'is_trash = 0', orderBy: 'date DESC');
    List<Map<String, dynamic>> fullList = [];
    for(var m in metaList) fullList.add(await _readMdFile(m));
    return fullList;
  }

  Future<List<Map<String, dynamic>>> getDiariesByDate(DateTime date) async {
    final db = await instance.database;
    String dateStr = date.toString().substring(0, 10);
    final metaList = await db.query('diaries', where: 'date LIKE ? AND is_trash = 0', whereArgs: ['$dateStr%'], orderBy: 'date DESC');
    List<Map<String, dynamic>> fullList = [];
    for(var m in metaList) fullList.add(await _readMdFile(m));
    return fullList;
  }

  Future<List<Map<String, dynamic>>> getTrashedDiaries() async {
    final db = await instance.database;
    final metaList = await db.query('diaries', where: 'is_trash = 1', orderBy: 'delete_time DESC');
    List<Map<String, dynamic>> fullList = [];
    for(var m in metaList) fullList.add(await _readMdFile(m));
    return fullList;
  }

  // ================= 备份逻辑 =================

  Future<String?> createFullBackup(String savePath) async {
    try {
      final root = await rootDir;
      final encoder = ZipFileEncoder();
      encoder.create(savePath);
      encoder.addDirectory(Directory(root));
      encoder.close();
      return savePath;
    } catch (e) { return null; }
  }
}