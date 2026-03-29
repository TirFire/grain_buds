import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart'; // 💡 新增
import 'package:path/path.dart' as p; // 💡 新增
import 'package:share_plus/share_plus.dart'; // 💡 新增

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
      words +=
          (d['content'] as String? ?? "").replaceAll(RegExp(r'\s+'), '').length;

      String mood = AppConstants.getMoodEmoji(d['mood'] as String?);
      String weather = AppConstants.getWeatherEmoji(d['weather'] as String?);

      moodCount[mood] = (moodCount[mood] ?? 0) + 1;
      weatherCount[weather] = (weatherCount[weather] ?? 0) + 1;

      DateTime date = DateTime.parse(d['date'] as String);
      if (earliestDate == null || date.isBefore(earliestDate)) {
        earliestDate = date;
      }
    }

    String topMood =
        moodCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    String topWeather =
        weatherCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    if (mounted) {
      setState(() {
        _totalDiaries = diaries.length;
        _totalWords = words;
        _favoriteMood = topMood;
        _favoriteWeather = topWeather;
        _startDate =
            DateFormat('yyyy年MM月dd日').format(earliestDate ?? DateTime.now());
        _totalDays =
            DateTime.now().difference(earliestDate ?? DateTime.now()).inDays +
                1;
        _isLoading = false;
      });
    }
  }

  Future<void> _captureAndShare() async {
    setState(() => _isCapturing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final imageBytes = await _screenshotController.capture(pixelRatio: 1.5);

      if (imageBytes != null) {
        String? savePath;
        final String fileName =
            '年度海报_${DateTime.now().millisecondsSinceEpoch}.png';

        // 💡 核心修复：手机端直接存沙盒准备分享，Windows端呼出“另存为”对话框
        if (Platform.isAndroid || Platform.isIOS) {
          final directory = await getApplicationDocumentsDirectory();
          final exportDir =
              Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
          if (!await exportDir.exists()) {
            await exportDir.create(recursive: true);
          }
          savePath = p.join(exportDir.path, fileName);
        } else {
          // 💻 Windows 端：调用系统原生的“另存为”弹窗让用户选位置
          final FileSaveLocation? result =
              await getSaveLocation(suggestedName: fileName);
          if (result == null) {
            setState(() => _isCapturing = false);
            return;
          }
          savePath = result.path;
        }

        // 执行文件写入
        await File(savePath).writeAsBytes(imageBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('🎉 年度海报已成功生成！'),
            backgroundColor: Colors.amber.shade700,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: (Platform.isAndroid || Platform.isIOS) ? '分享/保存' : '立即查看',
              textColor: Colors.white,
              onPressed: () async {
                if (Platform.isAndroid || Platform.isIOS) {
                  // 📱 手机端：呼出系统原生分享面板，等待结束后删除临时图片
                  await Share.shareXFiles([XFile(savePath!)]);
                  try {
                    File(savePath).deleteSync();
                  } catch (_) {}
                } else {
                  // 💻 Windows端：直接打开文件所在位置（电脑端不删，因为是另存为的）
                  OpenFilex.open(savePath!);
                }
              },
            ),
          ));
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('截取失败，请稍微上下滑动页面再试')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('生成海报失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_totalDiaries == 0) {
      return Scaffold(
          appBar: AppBar(title: const Text("时光报告")),
          body: const Center(
              child: Text("还没有日记记录哦，快去写下第一篇吧！",
                  style: TextStyle(color: Colors.grey))));
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
            Screenshot(
                controller: _screenshotController, child: _buildPosterUI()),
            const SizedBox(height: 30),
            if (_isCapturing)
              const CircularProgressIndicator(color: Colors.amber)
            else
              ElevatedButton.icon(
                onPressed: _captureAndShare,
                // 💡 动态图标：手机端显示分享图标，Windows显示下载图标
                icon: Icon((Platform.isAndroid || Platform.isIOS)
                    ? Icons.share
                    : Icons.download),
                // 💡 动态文案
                label: Text(
                    (Platform.isAndroid || Platform.isIOS)
                        ? "生成并分享总结海报"
                        : "保存海报到电脑",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30))),
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
              Icon(Icons.auto_awesome,
                  color: Colors.amber.withOpacity(0.8), size: 40)
            ]),
            const SizedBox(height: 50),
            Text("自从 $_startDate 开始，",
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text("时光的齿轮已经转动了 $_totalDays 天。",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
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
                      style: TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(children: [
                    Text(_favoriteMood, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 15),
                    const Expanded(
                        child: Text("是你最常出现的心情，无论晴雨，都要好好爱自己。",
                            style:
                                TextStyle(color: Colors.white70, height: 1.5)))
                  ]),
                  const SizedBox(height: 15),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 15),
                  Row(children: [
                    Text(_favoriteWeather,
                        style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 15),
                    const Expanded(
                        child: Text("是陪伴你最多次的天气，愿你心中永远有光。",
                            style:
                                TextStyle(color: Colors.white70, height: 1.5)))
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
                  style: TextStyle(
                      color: Colors.white38, fontSize: 12, letterSpacing: 2))
            ]))
          ],
        ),
      ),
    );
  }

  Widget _buildDataBox(String prefix, String highlight, String suffix) {
    return RichText(
        text: TextSpan(
            style: const TextStyle(
                color: Colors.white70, fontSize: 18, height: 1.5),
            children: [
          TextSpan(text: "$prefix\n"),
          TextSpan(
              text: highlight,
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 40,
                  fontWeight: FontWeight.w900)),
          TextSpan(text: "  $suffix")
        ]));
  }
}
