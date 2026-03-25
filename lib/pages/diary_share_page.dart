import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
// 💡 引入了路径处理和打开文件的库，删掉了 file_selector
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // 用于解析 JSON 字符串
import '../core/constants.dart';

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

  // 💡 1. 新增：定义 3 种海报模板配色
  int _selectedThemeIndex = 0; 
  final List<Map<String, Color>> _themes = [
    {'bg': const Color(0xFFFAF9F6), 'text': Colors.black87, 'subText': Colors.grey, 'accent': Colors.teal}, // 经典白
    {'bg': const Color(0xFFE8F4E6), 'text': const Color(0xFF004D40), 'subText': const Color(0xFF00796B), 'accent': Colors.green}, // 护眼绿
    {'bg': const Color(0xFF2C2C2C), 'text': Colors.white70, 'subText': Colors.white54, 'accent': Colors.blueGrey}, // 暗夜黑
  ];

  Future<void> _captureAndShare() async {
    setState(() => _isCapturing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final imageBytes = await _screenshotController.capture(pixelRatio: 1.5);
      
      if (imageBytes != null) {
        final directory = await getApplicationDocumentsDirectory();
        final exportDir = Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }

        final String fileName = '长图分享_${DateTime.now().millisecondsSinceEpoch}.png';
        final String savePath = p.join(exportDir.path, fileName);
        
        await File(savePath).writeAsBytes(imageBytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('🎉 长图已成功保存！'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '立即打开查看',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(savePath), 
            ),
          ));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('截取失败，请稍微上下滑动页面再试')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成错误: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStr = widget.diary['title'] as String? ?? '无标题';
    final dateStr = widget.diary['date'] as String? ?? '';
    final weather = AppConstants.getWeatherEmoji(widget.diary['weather'] as String?);
    final mood = AppConstants.getMoodEmoji(widget.diary['mood'] as String?);
    List<String> images = [];
    try {
      final imgPath = widget.diary['imagePath'];
      if (imgPath != null && imgPath.toString().isNotEmpty) {
        images = List<String>.from(jsonDecode(imgPath.toString()));
      }
    } catch (_) {}

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

    // 💡 获取当前选中的主题颜色
    final currentTheme = _themes[_selectedThemeIndex];

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
          title: const Text("生成长图"),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Screenshot(
              controller: _screenshotController,
              // 💡 2. 这里就是你刚才找不到的绘制区！我们将颜色换成了 currentTheme['bg']
              child: Container(
                color: currentTheme['bg'], 
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                // margin: const EdgeInsets.symmetric(horizontal: 16), // 去掉 margin，让生成的截图没有多余的白边
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
                                style: TextStyle(
                                    color: currentTheme['subText'], // 💡 使用主题副文本色
                                    fontSize: 13,
                                    letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(weekdayStr,
                                style: TextStyle(
                                    color: currentTheme['subText'], fontSize: 13)), // 💡 使用主题副文本色
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
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: currentTheme['text'], // 💡 使用主题主文本色
                            height: 1.3)),
                    const SizedBox(height: 24),
                    MarkdownBody(
                      data: widget.decryptedContent,
                      styleSheet: MarkdownStyleSheet(
                        // 💡 正文也使用主题的主文本色
                        p: TextStyle(fontSize: 16, height: 1.8, color: currentTheme['text']),
                        h1: TextStyle(fontSize: 22, height: 1.5, fontWeight: FontWeight.bold, color: currentTheme['text']),
                        h2: TextStyle(fontSize: 20, height: 1.5, fontWeight: FontWeight.bold, color: currentTheme['text']),
                        blockquote: TextStyle(color: currentTheme['subText'], fontStyle: FontStyle.italic),
                        blockquoteDecoration: BoxDecoration(
                            border: Border(left: BorderSide(color: currentTheme['accent']!, width: 4))),
                      ),
                    ),
                    //优化排版：将单张铺满的大图改为精致的“照片墙” (九宫格风格)
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      Wrap(
                        spacing: 12, 
                        runSpacing: 12, 
                        children: images.map((path) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 100, 
                            height: 100, 
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 100, height: 100, color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, color: Colors.white, size: 30),
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 60),
                    Divider(color: currentTheme['subText']?.withOpacity(0.2)),
                    const SizedBox(height: 15),
                    Center(
                        child: Text("—— 记录于「GrainBuds-小满日记」——",
                            style: TextStyle(
                                color: currentTheme['subText'],
                                fontSize: 12,
                                letterSpacing: 2)))
                  ],
                ),
              ),
            ),
            
            // 💡 3. 新增：底部主题选择器
            const SizedBox(height: 20),
            const Text("选择海报模板", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_themes.length, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _selectedThemeIndex = index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _themes[index]['bg'],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedThemeIndex == index ? Colors.blue : Colors.grey.shade400,
                        width: _selectedThemeIndex == index ? 3 : 1,
                      ),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 30),
            if (_isCapturing)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _captureAndShare,
                icon: const Icon(Icons.download), 
                label: const Text("保存长图到电脑",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}