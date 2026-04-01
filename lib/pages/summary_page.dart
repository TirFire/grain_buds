import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:path/path.dart' as p; 
import 'package:share_plus/share_plus.dart'; 
import 'package:gal/gal.dart'; // 💡 引入相册保存插件

import '../core/database_helper.dart';
import '../core/constants.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  final ScreenshotController _screenshotController = ScreenshotController();

  bool _isLoading = true;
  bool _isCapturing = false;

  int _totalDays = 0;
  int _totalWords = 0;
  int _totalDiaries = 0;
  String _favoriteMood = "😊";
  String _favoriteWeather = "☀️";
  String _startDate = "";

  @override
  void initState() {
    super.initState();
    _generateReport();
  }

  Future<void> _generateReport() async {
    final diaries = await DatabaseHelper.instance.getAllDiaries();
    if (diaries.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    int words = 0;
    Map<String, int> moodCount = {};
    Map<String, int> weatherCount = {};
    DateTime? earliestDate;

    for (var d in diaries) {
      words += (d['content'] as String? ?? "").replaceAll(RegExp(r'\s+'), '').length;

      String mood = AppConstants.getMoodEmoji(d['mood'] as String?);
      String weather = AppConstants.getWeatherEmoji(d['weather'] as String?);

      moodCount[mood] = (moodCount[mood] ?? 0) + 1;
      weatherCount[weather] = (weatherCount[weather] ?? 0) + 1;

      DateTime date = DateTime.parse(d['date'] as String);
      if (earliestDate == null || date.isBefore(earliestDate)) {
        earliestDate = date;
      }
    }

    String topMood = moodCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    String topWeather = weatherCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    if (mounted) {
      setState(() {
        _totalDiaries = diaries.length;
        _totalWords = words;
        _favoriteMood = topMood;
        _favoriteWeather = topWeather;
        _startDate = DateFormat('yyyy年MM月dd日').format(earliestDate ?? DateTime.now());
        _totalDays = DateTime.now().difference(earliestDate ?? DateTime.now()).inDays + 1;
        _isLoading = false;
      });
    }
  }

  // 💡 核心修复：复刻长图分享页的“分流分享”逻辑
  Future<void> _captureAndShare() async {
    setState(() => _isCapturing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      // 保持高清画质
      final imageBytes = await _screenshotController.capture(pixelRatio: 2.0);

      if (imageBytes != null) {
        String? savePath;
        final String fileName = '时光报告_${DateTime.now().millisecondsSinceEpoch}.png';

        if (Platform.isAndroid || Platform.isIOS) {
          // 📱 手机端：存入临时导出目录
          final directory = await getApplicationDocumentsDirectory();
          final exportDir = Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
          if (!await exportDir.exists()) await exportDir.create(recursive: true);
          
          savePath = p.join(exportDir.path, fileName);
          await File(savePath).writeAsBytes(imageBytes);

          if (mounted) {
            // 💡 弹出与长图分享完全一致的底部选择器
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (c) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text("时光海报已生成", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ),
                    ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.share, color: Colors.white)),
                      title: const Text("分享给好友 (微信/QQ等)"),
                      onTap: () async {
                        Navigator.pop(c);
                        await Share.shareXFiles([XFile(savePath!)]);
                      },
                    ),
                    ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.save_alt, color: Colors.white)),
                      title: const Text("直接保存到手机相册"),
                      onTap: () async {
                        Navigator.pop(c);
                        try {
                          await Gal.putImage(savePath!); // 💡 使用你验证成功的保存逻辑
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已成功存入相册，快去朋友圈展示吧！'), backgroundColor: Colors.teal));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 保存失败：$e'), backgroundColor: Colors.red));
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          }
        } else {
          // 💻 电脑端：保持原有的“另存为”逻辑
          final FileSaveLocation? result = await getSaveLocation(suggestedName: fileName);
          if (result == null) {
            setState(() => _isCapturing = false);
            return;
          }
          await File(result.path).writeAsBytes(imageBytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 已成功保存到电脑！')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成海报失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_totalDiaries == 0) {
      return Scaffold(
          appBar: AppBar(title: const Text("时光报告")),
          body: const Center(child: Text("还没有日记记录哦，快去写下第一篇吧！", style: TextStyle(color: Colors.grey))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
          title: const Text("我的时光报告", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Screenshot(controller: _screenshotController, child: _buildPosterUI()),
            const SizedBox(height: 30),
            if (_isCapturing)
              const CircularProgressIndicator(color: Colors.amber)
            else
              ElevatedButton.icon(
                onPressed: _captureAndShare,
                icon: Icon((Platform.isAndroid || Platform.isIOS) ? Icons.share : Icons.download),
                label: Text((Platform.isAndroid || Platform.isIOS) ? "生成并分享总结海报" : "保存海报到电脑",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterUI() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C3E50), Color(0xFF000000)])),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("ANNUAL\nREPORT",
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: 2)),
              Icon(Icons.auto_awesome, color: Colors.amber.withOpacity(0.8), size: 40)
            ]),
            const SizedBox(height: 50),
            Text("自从 $_startDate 开始，", style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text("时光的齿轮已经转动了 $_totalDays 天。",
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            _buildDataBox("你总共留下了", "$_totalDiaries 篇", "回忆的印记"),
            const SizedBox(height: 20),
            _buildDataBox("键盘敲击了", "$_totalWords 字", "胜过千言万语"),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("在这段旅程中：",
                      style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(children: [
                    Text(_favoriteMood, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 15),
                    const Expanded(
                        child: Text("是你最常出现的心情，无论晴雨，都要好好爱自己。",
                            style: TextStyle(color: Colors.white70, height: 1.5)))
                  ]),
                  const SizedBox(height: 15),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 15),
                  Row(children: [
                    Text(_favoriteWeather, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 15),
                    const Expanded(
                        child: Text("是陪伴你最多次的天气，愿你心中永远有光。",
                            style: TextStyle(color: Colors.white70, height: 1.5)))
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 60),
            const Center(
                child: Column(children: [
              Icon(Icons.fingerprint, color: Colors.amber, size: 50),
              SizedBox(height: 10),
              Text("—— 由「GrainBuds-小满日记」生成 ——",
                  style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 2))
            ]))
          ],
        ),
      ),
    );
  }

  Widget _buildDataBox(String prefix, String highlight, String suffix) {
    return RichText(
        text: TextSpan(
            style: const TextStyle(color: Colors.white70, fontSize: 18, height: 1.5),
            children: [
          TextSpan(text: "$prefix\n"),
          TextSpan(
              text: highlight,
              style: const TextStyle(color: Colors.amber, fontSize: 40, fontWeight: FontWeight.w900)),
          TextSpan(text: "  $suffix")
        ]));
  }
}