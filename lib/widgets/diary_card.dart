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

import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';

import '../core/database_helper.dart';
import '../core/constants.dart'; // 💡 新增：引入状态码字典解析器
import '../pages/edit_page.dart';
import '../core/encryption_service.dart';
import 'full_screen_gallery.dart';
import '../pages/diary_share_page.dart';
import 'package:markdown/markdown.dart' as md;

class DiaryCard extends StatelessWidget {
  final Map<String, dynamic> diary;
  final VoidCallback onRefresh;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(bool)? onSelected;
  final VoidCallback? onLongPress;

  const DiaryCard(
      {super.key,
      required this.diary,
      required this.onRefresh,
      this.isSelectionMode = false,
      this.isSelected = false,
      this.onSelected,
      this.onLongPress});

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
        dateStr.length >= 10 ? dateStr.substring(0, 10) : "未知日期";
    String fileName = '${datePrefix}_$safeTitle.$format';
    final FileSaveLocation? result =
        await getSaveLocation(suggestedName: fileName);
    if (result == null) return;
    if (format == 'pdf') {
      try {
        final font = await PdfGoogleFonts.notoSansSCRegular();
        final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));
        pdf.addPage(pw.MultiPage(
            build: (pw.Context context) => [
                  pw.Header(
                      level: 0,
                      child: pw.Text(title,
                          style: pw.TextStyle(
                              fontSize: 24, fontWeight: pw.FontWeight.bold))),
                  pw.Text("记录时间: $dateStr",
                      style: const pw.TextStyle(color: PdfColors.grey)),
                  pw.SizedBox(height: 20),
                  pw.Text(content,
                      style: const pw.TextStyle(fontSize: 14, lineSpacing: 5))
                ]));
        final file = File(result.path);
        await file.writeAsBytes(await pdf.save());
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("🎉 PDF 导出成功！"), backgroundColor: Colors.teal));
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
      final file = File(result.path);
      await file.writeAsString(outputContent);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("🎉 成功导出为 .$format 文件！"),
            backgroundColor: Colors.teal));
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
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (context.mounted)
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DiarySharePage(
                                    diary: diary, decryptedContent: content)));
                    });
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
    final images = _parseList(diary['imagePath'] as String?);
    final String? videoPath =
        (diary['videoPath'] != null && diary['videoPath'].toString().isNotEmpty)
            ? diary['videoPath']
            : null;

    final dateStr = diary['date'] as String? ?? DateTime.now().toString();
    final titleStr = diary['title'] as String? ?? '无标题';
    final contentStr = decryptedContent ?? (diary['content'] as String? ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 💡 福利：详情窗内显示天气与心情！
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])} ",
                  style: const TextStyle(fontSize: 18)),
              Expanded(child: Text(titleStr)),
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
                  data: contentStr,
                  selectable: true,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  onTapLink: (text, href, title) async {
                    if (href != null) {
                      final Uri url = Uri.parse(href);
                      if (await canLaunchUrl(url))
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                if (images.isNotEmpty || videoPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (videoPath != null)
                          _buildBrowseItem(context, videoPath, isVideo: true),
                        ...images.asMap().entries.map((entry) =>
                            _buildBrowseItem(context, entry.value,
                                isVideo: false,
                                index: entry.key,
                                allImages: images)),
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
                  Navigator.pop(context);
                  _showExportMenu(context, titleStr, contentStr, dateStr);
                }),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: '移至回收站',
                onPressed: () {
                  showDialog(
                      context: context,
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
                                      Navigator.pop(context);
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
                  Navigator.pop(context);
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => DiaryEditPage(existingDiary: {
                                ...diary,
                                'content': contentStr
                              })));
                  onRefresh();
                },
                child: const Text('编 辑',
                    style: TextStyle(
                        color: Colors.teal, fontWeight: FontWeight.bold))),
            TextButton(
                onPressed: () => Navigator.pop(context),
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
            isVideo || isLive
                ? LivePhotoThumbnail(videoPath: path, width: 80, height: 80)
                : Image.file(File(path),
                    width: 80, height: 80, fit: BoxFit.cover),
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

  List<String> _parseList(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(jsonStr));
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStr = diary['title'] as String? ?? '无标题';
    final isLocked = diary['is_locked'] == 1;
    final isNote = (diary['type'] as int? ?? 0) == 1;
    final String dateStr = diary['date'] as String? ?? '';
    final String? updateStr = diary['update_time'] as String?;
    String cTime = "";
    String uTime = "";
    try {
      if (dateStr.isNotEmpty)
        cTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(dateStr));
      if (updateStr != null && updateStr.isNotEmpty)
        uTime =
            DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(updateStr));
    } catch (_) {}
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
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          border: Border.all(color: Colors.green.shade200),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text("随手记",
                          style: TextStyle(
                              color: Colors.green.shade600, fontSize: 9))),
                  const SizedBox(width: 6)
                ],
                // 💡 福利：时间轴/列表缩略图里也直接显示天气和心情！
                Text(
                    "${AppConstants.getWeatherEmoji(diary['weather'])} ${AppConstants.getMoodEmoji(diary['mood'])}  ",
                    style: const TextStyle(fontSize: 12)),
                Expanded(
                    child: Text(
                        "创建: $cTime" +
                            (uTime.isNotEmpty && uTime != cTime
                                ? "  |  编辑: $uTime"
                                : ""),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
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
              if (isSelectionMode) {
                onSelected?.call(!isSelected);
              } else {
                _handleOpen(context);
              }
            },
            onLongPress: onLongPress));
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
  late final player = Player();
  late final controller = VideoController(player);
  @override
  void initState() {
    super.initState();
    player.setVolume(0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(widget.videoPath));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child:
                      Video(controller: controller, controls: NoVideoControls)))
        ]));
  }
}
