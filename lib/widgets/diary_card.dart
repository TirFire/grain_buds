import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

import '../core/database_helper.dart';
import '../core/constants.dart'; // 💡 新增：引入状态码字典解析器
import '../pages/edit_page.dart';
import '../core/encryption_service.dart';
import 'full_screen_gallery.dart';
import '../pages/diary_share_page.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DiaryCard extends StatelessWidget {
  final Map<String, dynamic> diary;
  final VoidCallback onRefresh;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(bool)? onSelected;
  final VoidCallback? onLongPress;
  final String heroTagPrefix;
  final bool showDate;

  const DiaryCard(
      {super.key,
      required this.diary,
      required this.onRefresh,
      this.isSelectionMode = false,
      this.isSelected = false,
      this.onSelected,
      this.onLongPress,
      this.heroTagPrefix = '',
      this.showDate = true});

  void _handleOpen(BuildContext context) {
    if (diary['is_locked'] == 1) {
      _showUnlockDialog(context);
    } else {
      _showDetail(context, null);
    }
  }

  void _showUnlockDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock, color: Colors.orange),
          SizedBox(width: 8),
          Text("解密日记")
        ]),
        content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: "请输入此篇日记的独立密码")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              final pwd = controller.text;
              if (EncryptionService.verifyPassword(pwd, diary['pwd_hash'])) {
                Navigator.pop(c);
                final decryptedBody =
                    EncryptionService.decrypt(diary['content'], pwd);
                _showDetail(context, decryptedBody, pwdKey: pwd);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("密码错误，无法解密"), backgroundColor: Colors.red));
              }
            },
            child: const Text("解密"),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDiary(BuildContext context, String title, String content,
      String dateStr, String format) async {
    String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String datePrefix =
        dateStr.length >= 10 ? (dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr) : "未知日期";
    String fileName = '${datePrefix}_$safeTitle.$format';

    String? savePath;

    // 💡 核心修复：手机端与电脑端的路径保存策略分流
    if (Platform.isAndroid || Platform.isIOS) {
      // 📱 手机端：直接保存到应用的导出专区
      final directory = await getApplicationDocumentsDirectory();
      final exportDir =
          Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      savePath = p.join(exportDir.path, fileName);
    } else {
      // 💻 电脑端：调用系统原生的“另存为”弹窗
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: fileName);
      if (result == null) return; // 用户取消了保存
      savePath = result.path;
    }

    if (format == 'pdf') {
      try {
        final regularData =
            await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
        final font = pw.Font.ttf(regularData);
        final boldData =
            await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
        final fontBold = pw.Font.ttf(boldData);
        pw.Font emojiFont;
        try {
          emojiFont = await PdfGoogleFonts.notoColorEmoji()
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          emojiFont = font;
        }

        final pdf = pw.Document(
            theme: pw.ThemeData.withFont(
                base: font, bold: fontBold, fontFallback: [emojiFont]));

        String formattedDate = dateStr;
        try {
          formattedDate =
              DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(dateStr));
        } catch (_) {
          formattedDate =
              dateStr.length >= 16 ? dateStr.substring(0, 16) : dateStr;
        }

        String weather =
            AppConstants.getWeatherEmoji(diary['weather'] as String?);
        String mood = AppConstants.getMoodEmoji(diary['mood'] as String?);

        List<String> images = [];
        try {
          if (diary['image_path'] != null)
            images = List<String>.from(jsonDecode(diary['image_path']));
          else if (diary['imagePath'] != null)
            images = List<String>.from(jsonDecode(diary['imagePath']));
        } catch (_) {}

        pdf.addPage(pw.MultiPage(
            build: (pw.Context context) => [
                  pw.Header(
                      level: 0,
                      child: pw.Text(title,
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 24,
                              fontFallback: [emojiFont]))),
                  pw.Text("记录时间: $formattedDate    天气: $weather    心情: $mood",
                      style: pw.TextStyle(
                          color: PdfColors.grey, fontFallback: [emojiFont])),
                  pw.SizedBox(height: 20),
                  ..._renderMarkdown(content, font, fontBold, emojiFont),
                  if (images.isNotEmpty) ...[
                    pw.SizedBox(height: 20),
                    ...List.generate((images.length / 2).ceil(), (rowIndex) {
                      int start = rowIndex * 2;
                      int end = start + 2 > images.length ? images.length : start + 2;
                      var rowImages = images.sublist(start, end);
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 10),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: rowImages.map((path) {
                            try {
                              final file = File(path);
                              if (file.existsSync()) {
                                return pw.Expanded(
                                  child: pw.Padding(
                                    padding: const pw.EdgeInsets.only(right: 10),
                                    child: pw.Image(pw.MemoryImage(file.readAsBytesSync()), height: 200, fit: pw.BoxFit.contain)
                                  )
                                );
                              }
                            } catch (_) {}
                            return pw.Expanded(child: pw.SizedBox()); 
                          }).toList(),
                        )
                      );
                    })
                  ]
                ]));

        final file = File(savePath);
        await file.writeAsBytes(await pdf.save());
        if (context.mounted) {
          // 💡 修复：手机端导出成功后，提供“立即打开”的快捷入口
          // 💡 修复：手机端导出成功后，提供“分享/保存”的快捷入口
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("🎉 PDF 导出成功！"),
            backgroundColor: Colors.teal,
            action: (Platform.isAndroid || Platform.isIOS)
                ? SnackBarAction(
                    label: '分享/保存',
                    textColor: Colors.white,
                    onPressed: () async {
                      await Share.shareXFiles([XFile(savePath!)]);
                    })
                : null,
          ));
        }
      } catch (e) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("PDF 导出失败: $e"), backgroundColor: Colors.red));
      }
      return;
    }

    String outputContent = "";
    if (format == 'md')
      outputContent = "# $title\n\n**记录时间:** $dateStr\n\n---\n\n$content";
    else if (format == 'txt')
      outputContent = "标题: $title\n时间: $dateStr\n\n$content";
    else if (format == 'doc')
      outputContent =
          "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\" xmlns=\"http://www.w3.org/TR/REC-html40\"><head><meta charset=\"utf-8\"><title>$title</title></head><body style=\"font-family: 'Microsoft YaHei', sans-serif;\"><h1 style=\"text-align: center;\">$title</h1><p style=\"color: gray; text-align: center;\">记录时间: $dateStr</p><hr><div style=\"white-space: pre-wrap; line-height: 1.6; font-size: 12pt;\">$content</div></body></html>";

    try {
      final file = File(savePath);
      await file.writeAsString(outputContent);
      if (context.mounted) {
        // 💡 修复：手机端导出成功后提供分享入口
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("🎉 成功导出为 .$format 文件！"),
          backgroundColor: Colors.teal,
          action: (Platform.isAndroid || Platform.isIOS)
              ? SnackBarAction(
                  label: '分享/保存',
                  textColor: Colors.white,
                  onPressed: () async {
                    await Share.shareXFiles([XFile(savePath!)]);
                  })
              : null,
        ));
      }
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("导出失败: $e"), backgroundColor: Colors.red));
    }
  }

  void _showExportMenu(
      BuildContext context, String title, String content, String dateStr) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => SafeArea(
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("单篇另存为...",
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold))),
              ListTile(
                  leading: const Icon(Icons.image, color: Colors.purple),
                  title: const Text("生成精美长图分享"),
                  subtitle: const Text("排版为长图海报，保存相册或分享朋友圈"),
                  onTap: () {
                    Navigator.pop(c);
                    // 💡 修复：移除多余的延时和拦截，直接使用卡片自带的稳定 context 跳转
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DiarySharePage(
                                diary: diary, decryptedContent: content)));
                  }),
              ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text("导出为 PDF (.pdf)"),
                  subtitle: const Text("超清文本排版，适合多平台分享"),
                  onTap: () {
                    Navigator.pop(c);
                    _exportDiary(context, title, content, dateStr, 'pdf');
                  }),
              ListTile(
                  leading: const Icon(Icons.code, color: Colors.blueGrey),
                  title: const Text("导出为 Markdown (.md)"),
                  subtitle: const Text("适合程序员和笔记软件"),
                  onTap: () {
                    Navigator.pop(c);
                    _exportDiary(context, title, content, dateStr, 'md');
                  }),
              ListTile(
                  leading: const Icon(Icons.text_snippet, color: Colors.grey),
                  title: const Text("导出为纯文本 (.txt)"),
                  subtitle: const Text("兼容所有设备，去除格式"),
                  onTap: () {
                    Navigator.pop(c);
                    _exportDiary(context, title, content, dateStr, 'txt');
                  }),
              ListTile(
                  leading: const Icon(Icons.description, color: Colors.blue),
                  title: const Text("导出为 Word 文档 (.doc)"),
                  subtitle: const Text("适合排版打印、提交报告"),
                  onTap: () {
                    Navigator.pop(c);
                    _exportDiary(context, title, content, dateStr, 'doc');
                  })
            ]))));
  }

  void _showDetail(BuildContext context, String? decryptedContent,
      {String? pwdKey}) {
    // 💡 修复 2：使用终极容错解析，不再依赖危险的 try-catch 和强转
    final images = _parseSafeList(diary['image_path'] ?? diary['imagePath']);
    final videos = _parseSafeList(diary['video_path'] ?? diary['videoPaths']);
    if (videos.isEmpty &&
        diary['videoPath'] != null &&
        diary['videoPath'].toString().isNotEmpty) {
      videos.add(diary['videoPath'].toString());
    }
    final audios = _parseSafeList(diary['audio_path'] ?? diary['audioPaths']);
    if (audios.isEmpty &&
        diary['audioPath'] != null &&
        diary['audioPath'].toString().isNotEmpty) {
      audios.add(diary['audioPath'].toString());
    }
    final attachments = _parseSafeList(diary['attachments']);

    // 💡 修复 3：将所有危险的 `as String?` 替换为绝对安全的 `?.toString()`
    final dateStr = diary['date']?.toString() ?? DateTime.now().toString();
    final titleStr = diary['title']?.toString() ?? '无标题';
    final contentStr = decryptedContent ?? (diary['content']?.toString() ?? '');
    final updateStr = diary['update_time']?.toString();
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: '关闭',
      transitionDuration:
          const Duration(milliseconds: 250), // 💡 加快动画速度，250ms最干脆
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 极简流畅的缩放淡入
        return ScaleTransition(
          scale: animation.drive(Tween(begin: 0.95, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut))),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          AlertDialog(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])} ",
                  style: const TextStyle(fontSize: 18)),
              Expanded(
                  child: Text(
                titleStr,
                // 💡 手机端仅加粗不放大，电脑端保持默认放大
                style: (Platform.isAndroid || Platform.isIOS)
                    ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                    : null,
              )),
            ],
          ),
          if (diary['location'] != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 14, color: Colors.teal),
              const SizedBox(width: 4),
              Text(diary['location'],
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.teal,
                      fontWeight: FontWeight.normal))
            ])
          ]
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarkdownBody(
                  data: contentStr.split('\n').map((line) {
                    String pLine = line;
                    int spaceCount = 0;
                    while (spaceCount < pLine.length &&
                        (pLine[spaceCount] == ' ' ||
                            pLine[spaceCount] == '　' ||
                            pLine[spaceCount] == '\t' ||
                            pLine[spaceCount] == ' ')) {
                      spaceCount++;
                    }
                    if (spaceCount > 0) {
                      pLine =
                          '\u3000' * spaceCount + pLine.substring(spaceCount);
                    }
                    return pLine;
                  }).join('\n\n'),
                  selectable: true,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  onTapLink: (text, href, title) async {
                    if (href != null) {
                      final Uri url = Uri.parse(href);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                ),
                if (images.isNotEmpty || videos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 25, bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...videos.asMap().entries.map((entry) =>
                            _buildBrowseItem(context, entry.value,
                                isVideo: true,
                                index: entry.key,
                                allImages: videos)),
                        ...images.asMap().entries.map((entry) =>
                            _buildBrowseItem(context, entry.value,
                                isVideo: false,
                                index: entry.key,
                                allImages: images)),
                      ],
                    ),
                  ),
                if (audios.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Column(
                      children: audios
                          .map((path) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: MiniAudioPlayer(audioPath: path)))
                          .toList(),
                    ),
                  ),
                if (attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Column(
                      children: attachments.map((path) {
                        String fileName =
                            path.split(Platform.pathSeparator).last;
                        return Card(
                          elevation: 0,
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.05),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: Icon(Icons.file_present,
                                color: Theme.of(context).primaryColor),
                            title: Text(fileName,
                                style: const TextStyle(fontSize: 13)),
                            trailing: const Icon(Icons.share,
                                size: 16, color: Colors.grey), // 改为分享图标
                            onTap: () =>
                                Share.shareXFiles([XFile(path)]), // 调用分享面板
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                if (Platform.isAndroid || Platform.isIOS)
                  Padding(
                    padding: const EdgeInsets.only(top: 25, bottom: 5),
                    child: Column(
                      children: [
                        const Divider(color: Colors.black12),
                        const SizedBox(height: 8),
                        Text(
                            "创建时间: ${dateStr.length >= 16 ? dateStr.substring(0, 16) : dateStr}",
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        if (updateStr != null && updateStr.isNotEmpty)
                          Text(
                              "编辑时间: ${updateStr.length >= 16 ? updateStr.substring(0, 16) : updateStr}",
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                icon: const Icon(Icons.ios_share, color: Colors.blueGrey),
                tooltip: '导出与分享',
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showExportMenu(context, titleStr, contentStr, dateStr);
                }),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: '移至回收站',
                onPressed: () {
                  showDialog(
                      context: dialogContext,
                      builder: (c) => AlertDialog(
                              title: const Text('删除提示'),
                              content: const Text('确定要把这篇记录移至回收站吗？'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text("取消")),
                                TextButton(
                                    onPressed: () async {
                                      Navigator.pop(c);
                                      Navigator.pop(dialogContext);
                                      await DatabaseHelper.instance
                                          .deleteToTrash(diary['id']);
                                      onRefresh();
                                    },
                                    child: const Text('删除',
                                        style: TextStyle(color: Colors.red)))
                              ]));
                })
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);

                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DiaryEditPage(
                              existingDiary: {...diary, 'content': contentStr},
                              pwdKey: pwdKey,
                            )),
                  );
                  onRefresh();
                },
                child: const Text('编 辑',
                    style: TextStyle(
                        color: Colors.teal, fontWeight: FontWeight.bold))),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关 闭', style: TextStyle(color: Colors.grey)))
          ]),
        ],
      ),
    );
  }

  Widget _buildBrowseItem(BuildContext context, String path,
      {required bool isVideo, int? index, List<String>? allImages}) {
    final bool isLive = path.toLowerCase().endsWith('.mp4') ||
        path.toLowerCase().endsWith('.mov');

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => FullScreenGallery(
                  images: isVideo ? [path] : (allImages ?? [path]),
                  initialIndex: index ?? 0))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 💡 修复 1：正确嵌套 errorBuilder 到 Image.file 内部
            isVideo || isLive
                ? LivePhotoThumbnail(videoPath: path, width: 80, height: 80)
                : Image.file(
                    File(path),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    errorBuilder: (context, error, stackTrace) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey.shade200,
                        child:
                            const Icon(Icons.broken_image, color: Colors.grey)),
                  ),

            // 💡 修复 2：逻辑判断现在回到了 Stack 的 children 列表中
            if (isVideo)
              Container(
                  width: 80,
                  height: 80,
                  color: Colors.black26,
                  child: const Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 30)),
          ],
        ),
      ),
    );
  }

  // 💡 修复 1：终极容错的 _parseSafeList，彻底消灭 jsonDecode 和 List.from 带来的致命闪退！
  List<String> _parseSafeList(dynamic input) {
    if (input == null) return [];
    String str = input.toString().trim();
    if (str.isEmpty) return [];
    try {
      var decoded = jsonDecode(str);
      if (decoded is List) {
        return decoded
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList();
      } else if (decoded is String) {
        return [decoded];
      }
    } catch (_) {
      // 兼容旧版的纯字符串路径
      if (!str.startsWith('[')) return [str];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final titleStr = diary['title'] as String? ?? '无标题';
    final isLocked = diary['is_locked'] == 1;
    final isNote = (diary['type'] as int? ?? 0) == 1;
    final String dateStr = diary['date'] as String? ?? '';
    bool isUnknownDate = dateStr.startsWith('1900-01-01');
    final String? updateStr = diary['update_time'] as String?;
    String cTime = "";
    String uTime = "";
    bool isEdited = false;
    try {
      if (dateStr.isNotEmpty) {
        DateTime cDate = DateTime.parse(dateStr);
        cTime = DateFormat('yyyy-MM-dd HH:mm').format(cDate);
        if (updateStr != null && updateStr.isNotEmpty) {
          DateTime uDate = DateTime.parse(updateStr);
          if (uDate.difference(cDate).inMinutes > 2) {
            uTime = DateFormat('yyyy-MM-dd HH:mm').format(uDate);
            isEdited = true;
          }
        }
      }
    } catch (_) {}

    // 💡 实时判断平台
    bool isMobile = Platform.isAndroid || Platform.isIOS;

    // ==========================================
    // 💻 电脑端：保持原样 (经典的 ListTile 布局)
    // ==========================================
    if (!isMobile) {
      return Card(
          color: isSelected ? Colors.teal.shade50 : null,
          shape: isSelected
              ? RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.teal, width: 2),
                  borderRadius: BorderRadius.circular(12))
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
              leading: Icon(
                  isLocked
                      ? Icons.lock
                      : (isNote ? Icons.bolt : Icons.description_outlined),
                  color: isLocked
                      ? Colors.orange
                      : (isNote ? Colors.green.shade500 : Colors.teal)),
              title: Text(titleStr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                        isLocked
                            ? "内容已加密，点击输入密码查看"
                            : (diary['content'] as String? ?? ""),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (isNote) ...[
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.green.shade200),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text("随手记",
                                style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontSize: 9))),
                        const SizedBox(width: 6)
                      ],
                      if ((diary['is_archived'] as int? ?? 0) == 1) ...[
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.brown.shade200),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text("已归档",
                                style: TextStyle(
                                    color: Colors.brown.shade600,
                                    fontSize: 9))),
                        const SizedBox(width: 6)
                      ],
                      Text(
                          "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])}  ",
                          style: const TextStyle(fontSize: 12)),
                      Expanded(
                          child: Text(
                              isUnknownDate
                                  ? "⏳ 岁月深处的回忆"
                                  : "创建: $cTime" +
                                      (isEdited ? "  |  编辑: $uTime" : ""),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isUnknownDate
                                      ? Colors.brown
                                      : Colors.grey),
                              overflow: TextOverflow.ellipsis))
                    ])
                  ]),
              trailing: isSelectionMode
                  ? Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? Colors.teal : Colors.grey)
                  : IconButton(
                      icon: Icon(
                          diary['is_starred'] == 1
                              ? Icons.star
                              : Icons.star_border,
                          color: diary['is_starred'] == 1
                              ? Colors.amber
                              : Colors.grey.shade300),
                      onPressed: () async {
                        await DatabaseHelper.instance.toggleStarDiary(
                            diary['id'], diary['is_starred'] == 1);
                        onRefresh();
                      }),
              onTap: () {
                if (isSelectionMode)
                  onSelected?.call(!isSelected);
                else
                  _handleOpen(context);
              },
              onLongPress: onLongPress));
    }

    // ==========================================
    // 📱 手机端：全新定制的清爽布局
    // ==========================================
    return Card(
      color: isSelected ? Colors.teal.shade50 : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Colors.teal, width: 2),
              borderRadius: BorderRadius.circular(12))
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isSelectionMode)
            onSelected?.call(!isSelected);
          else
            _handleOpen(context);
        },
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 💡 变化1：左侧图标与随手记文字上下排列
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLocked
                        ? Icons.lock
                        : (isNote ? Icons.bolt : Icons.description_outlined),
                    color: isLocked
                        ? Colors.orange
                        : (isNote ? Colors.green.shade500 : Colors.teal),
                    size: 26,
                  ),
                  if (isNote)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text("随手记",
                          style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    )
                ],
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate) ...[
                      // 💡 日历页面：保持原样（第一行日期/天气心情，第二行标题）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              isUnknownDate
                                  ? "⏳ 岁月深处"
                                  : (dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr),
                              style: TextStyle(
                                  color: isUnknownDate
                                      ? Colors.brown
                                      : Colors.teal.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])}",
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(titleStr,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ] else ...[
                      // 💡 时间轴页面：标题与天气心情合并到第一行
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              titleStr,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                              "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])}",
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    // 摘要预览
                    Text(
                        isLocked
                            ? "内容已加密，点击输入密码查看"
                            : (diary['content'] as String? ?? ""),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87, height: 1.4)),
                  ],
                ),
              ),

              // 最右侧：星标或选中圈
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? Colors.teal : Colors.grey),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: GestureDetector(
                    onTap: () async {
                      await DatabaseHelper.instance.toggleStarDiary(
                          diary['id'], diary['is_starred'] == 1);
                      onRefresh();
                    },
                    child: Icon(
                        diary['is_starred'] == 1
                            ? Icons.star
                            : Icons.star_border,
                        color: diary['is_starred'] == 1
                            ? Colors.amber
                            : Colors.grey.shade300,
                        size: 22),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  // ================= 💡 新增：PDF 专属 Markdown 解析器 (终极完美版) =================
  List<pw.Widget> _renderMarkdown(
      String text, pw.Font regular, pw.Font bold, pw.Font emoji) {
    List<pw.Widget> widgets = [];
    final lines = text.split('\n');

    // 💡 核心修复 1：强制显式注入 fallback，确保每一行文字哪怕混排中英文，也绝对不会丢失 Emoji
    final fallbackStyle = pw.TextStyle(font: regular, fontFallback: [emoji]);
    final fallbackBoldStyle = pw.TextStyle(font: bold, fontFallback: [emoji]);

    for (String line in lines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
      } else if (trimmed.startsWith('# ')) {
        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(trimmed.substring(2),
                style: pw.TextStyle(
                    font: bold, fontSize: 20, fontFallback: [emoji]))));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
            child: pw.Text(trimmed.substring(3),
                style: pw.TextStyle(
                    font: bold, fontSize: 18, fontFallback: [emoji]))));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 2),
            child: pw.Text(trimmed.substring(4),
                style: pw.TextStyle(
                    font: bold, fontSize: 16, fontFallback: [emoji]))));
      } else if (trimmed.startsWith('> ')) {
        widgets.add(pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.only(left: 10),
            decoration: const pw.BoxDecoration(
                border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.grey, width: 3))),
            child: _parseInline(trimmed.substring(2).trim(), fallbackStyle,
                fallbackBoldStyle)));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('*')) {
        // 💡 核心修复 2：极高宽容度的正则匹配，完美兼容 ***加粗列表** 和 *无空格列表
        String cleanLine = trimmed;
        if (trimmed.startsWith('- ')) {
          cleanLine = trimmed.substring(2).trim();
        } else if (trimmed.startsWith('***')) {
          cleanLine = trimmed.substring(1).trim(); // 剥离最外层的列表 *，保留里层的 ** 给加粗解析器
        } else if (trimmed.startsWith('**')) {
          // 如果只是纯加粗段落而不是列表，直接跳过列表渲染
          widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: _parseInline(trimmed, fallbackStyle, fallbackBoldStyle)));
          continue;
        } else if (trimmed.startsWith('*')) {
          cleanLine = trimmed.substring(1).trim();
        }

        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 10, bottom: 4),
            child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // 💡 核心修复 3：直接用画笔画一个纯黑的实心圆！彻底避免特殊字符乱码！
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6, right: 8),
                    child: pw.Container(
                        width: 4,
                        height: 4,
                        decoration: const pw.BoxDecoration(
                            shape: pw.BoxShape.circle, color: PdfColors.black)),
                  ),
                  pw.Expanded(
                      child: _parseInline(
                          cleanLine, fallbackStyle, fallbackBoldStyle))
                ])));
      } else {
        widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: _parseInline(trimmed, fallbackStyle, fallbackBoldStyle)));
      }
    }
    return widgets;
  }

  pw.Widget _parseInline(
      String text, pw.TextStyle regularStyle, pw.TextStyle boldStyle,
      {bool isQuote = false}) {
    final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    final Iterable<RegExpMatch> matches = exp.allMatches(text);

    pw.TextStyle baseStyle = isQuote
        ? regularStyle.copyWith(color: PdfColors.grey700)
        : regularStyle;
    pw.TextStyle bStyle =
        isQuote ? boldStyle.copyWith(color: PdfColors.grey700) : boldStyle;

    if (matches.isEmpty)
      return pw.Text(text, style: baseStyle.copyWith(lineSpacing: 3));

    List<pw.TextSpan> spans = [];
    int lastMatchEnd = 0;
    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(pw.TextSpan(
            text: text.substring(lastMatchEnd, match.start), style: baseStyle));
      }
      spans.add(pw.TextSpan(text: match.group(1), style: bStyle));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(
          pw.TextSpan(text: text.substring(lastMatchEnd), style: baseStyle));
    }
    return pw.RichText(text: pw.TextSpan(children: spans));
  }
}

class LivePhotoThumbnail extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;
  const LivePhotoThumbnail(
      {super.key,
      required this.videoPath,
      required this.width,
      required this.height});
  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  Player? _player;
  VideoController? _controller;
  bool _isReady = false;
  bool _fileExists = true;

  @override
  void initState() {
    super.initState();
    // 💡 修复 4：将原本同步且会引发 Windows 死锁报错的 existsSync() 移到后台异步执行！
    _checkFileAndInit();
  }

  Future<void> _checkFileAndInit() async {
    try {
      // 异步判断文件存在，绝不卡死主线程
      bool exists = await File(widget.videoPath).exists();
      if (!mounted) return;
      setState(() => _fileExists = exists);

      if (exists) {
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted) {
            try {
              _player = Player();
              _player!.setVolume(0);
              _player!.setPlaylistMode(PlaylistMode.loop);
              _controller = VideoController(_player!);
              _player!.open(Media(widget.videoPath));
              setState(() => _isReady = true);
            } catch (e) {
              debugPrint("LivePhoto 播放器初始化失败: $e");
            }
          }
        });
      }
    } catch (e) {
      // 遇到文件权限拒绝时，静默视为文件不存在，保护程序绝对不崩溃！
      if (mounted) setState(() => _fileExists = false);
    }
  }

  @override
  void dispose() {
    final p = _player;
    _player = null;
    if (p != null) Future.microtask(() => p.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_fileExists) {
      return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.videocam_off, color: Colors.grey, size: 30));
    }
    // 💡 引擎没准备好之前，显示等待框
    if (!_isReady || _controller == null) {
      return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade100,
          child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.grey)));
    }
    return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: Video(
                      controller: _controller!, controls: NoVideoControls)))
        ]));
  }
}
