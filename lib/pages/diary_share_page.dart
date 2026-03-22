import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart'; // 💡 引入状态码解析字典

class DiarySharePage extends StatefulWidget {
  final Map<String, dynamic> diary;
  final String decryptedContent;

  const DiarySharePage(
      {super.key, required this.diary, required this.decryptedContent});

  @override
  State<DiarySharePage> createState() => _DiarySharePageState();
}

class _DiarySharePageState extends State<DiarySharePage> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isCapturing = false;

  Future<void> _captureAndShare() async {
    setState(() => _isCapturing = true);
    try {
      final imageBytes = await _screenshotController.capture(pixelRatio: 3.0);
      if (imageBytes != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File(
                '${directory.path}/diary_share_${DateTime.now().millisecondsSinceEpoch}.png')
            .create();
        await imagePath.writeAsBytes(imageBytes);
        await Share.shareXFiles([XFile(imagePath.path)], text: '与你分享我的时光印记');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('生成长图失败: $e')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStr = widget.diary['title'] as String? ?? '无标题';
    final dateStr = widget.diary['date'] as String? ?? '';

    // 💡 核心修复：通过字典把英文字符串转回表情 Emoji
    final weather =
        AppConstants.getWeatherEmoji(widget.diary['weather'] as String?);
    final mood = AppConstants.getMoodEmoji(widget.diary['mood'] as String?);

    String cTime = "";
    String weekdayStr = "";
    try {
      if (dateStr.isNotEmpty) {
        final date = DateTime.parse(dateStr);
        cTime = DateFormat('yyyy年MM月dd日 HH:mm').format(date);
        final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
        weekdayStr = weekdays[date.weekday - 1];
      }
    } catch (_) {}

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
          title: const Text("生成长图"),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Screenshot(
              controller: _screenshotController,
              child: Container(
                color: const Color(0xFFFAF9F6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cTime,
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                    letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(weekdayStr,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                        Row(
                          children: [
                            Text(weather, style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 8),
                            Text(mood, style: const TextStyle(fontSize: 24)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(titleStr,
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                            height: 1.3)),
                    const SizedBox(height: 24),
                    MarkdownBody(
                      data: widget.decryptedContent,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                            fontSize: 16, height: 1.8, color: Colors.black87),
                        h1: const TextStyle(
                            fontSize: 22,
                            height: 1.5,
                            fontWeight: FontWeight.bold),
                        h2: const TextStyle(
                            fontSize: 20,
                            height: 1.5,
                            fontWeight: FontWeight.bold),
                        blockquote: const TextStyle(
                            color: Colors.blueGrey,
                            fontStyle: FontStyle.italic),
                        blockquoteDecoration: BoxDecoration(
                            border: Border(
                                left: BorderSide(
                                    color: Colors.teal.shade200, width: 4))),
                      ),
                    ),
                    const SizedBox(height: 60),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 15),
                    const Center(
                        child: Text("—— 记录于「我的时光印记」——",
                            style: TextStyle(
                                color: Colors.black38,
                                fontSize: 12,
                                letterSpacing: 2)))
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (_isCapturing)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _captureAndShare,
                icon: const Icon(Icons.share),
                label: const Text("保存并分享长图",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
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
}
