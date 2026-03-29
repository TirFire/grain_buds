import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import 'package:archive/archive_io.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'collection_page.dart';
import '../core/database_helper.dart';
import '../widgets/diary_card.dart';
import 'edit_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'tags_page.dart';
import '../widgets/custom_title_bar.dart';
import '../core/constants.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'anniversaries_page.dart'; // 💡 新增这一行

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _isSearching = false;
  bool _isExtended = false;
  String _searchKeyword = "";
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSelectionMode = false;
  Set<int> _selectedIds = {};
  bool _isDescending = true;
  final ValueNotifier<int> _refreshTrigger = ValueNotifier(0);

  // 💡 新增：用于接管左右滑动的页面控制器
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    final results = await DatabaseHelper.instance.searchDiaries(keyword);
    setState(() {
      _searchResults = results;
    });
  }

  Future<void> _batchExport(String format) async {
    if (_selectedIds.isEmpty) return;

    String timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    String fileName = '';

    if (format == 'pdf')
      fileName = '批量合并日记_$timeStamp.pdf';
    else if (format == 'pdf_zip')
      fileName = '批量独立PDF_$timeStamp.zip';
    else
      fileName = '批量导出日记_$timeStamp.zip';

    String? savePath;

    if (Platform.isAndroid || Platform.isIOS) {
      // 📱 手机端：静默保存到本地
      final directory = await getApplicationDocumentsDirectory();
      final exportDir =
          Directory(p.join(directory.path, 'MyDiary_Data', 'Exports'));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      savePath = p.join(exportDir.path, fileName);
    } else {
      // 💻 电脑端：调用弹窗
      final FileSaveLocation? result =
          await getSaveLocation(suggestedName: fileName);
      if (result == null) return;
      savePath = result.path;
    }

    bool isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.teal),
          SizedBox(height: 15),
          Text("正在飞速打包中，请稍候...", style: TextStyle(fontWeight: FontWeight.bold))
        ]),
        actions: [
          TextButton(
              onPressed: () {
                isDialogShowing = false;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("📦 已转入后台导出，您可以继续使用软件。完成后将通知您！")));
              },
              child: const Text("转后台运行", style: TextStyle(color: Colors.grey)))
        ],
      ),
    ).then((_) => isDialogShowing = false);

    try {
      final allDiaries = await DatabaseHelper.instance.getAllDiaries();
      final selectedDiaries =
          allDiaries.where((d) => _selectedIds.contains(d['id'])).toList();

      if (format == 'pdf') {
        // 💡 替换为本地读取
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

        // ...

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String date = d['date'] ?? '';
          String formattedDate =
              date.length >= 16 ? date.substring(0, 16) : date;
          String content =
              d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');

          String weather =
              AppConstants.getWeatherEmoji(d['weather'] as String?);
          String mood = AppConstants.getMoodEmoji(d['mood'] as String?);

          List<String> images = [];
          try {
            if (d['image_path'] != null)
              images = List<String>.from(jsonDecode(d['image_path']));
            else if (d['imagePath'] != null)
              images = List<String>.from(jsonDecode(d['imagePath']));
          } catch (_) {}

          pdf.addPage(pw.MultiPage(
              build: (pw.Context context) => [
                    pw.Header(
                        level: 0,
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 24,
                                fontFallback: [emojiFont]))), // 💡 标题注入

                    pw.Text("记录时间: $formattedDate    天气: $weather    心情: $mood",
                        style: pw.TextStyle(
                            color: PdfColors.grey,
                            fontFallback: [emojiFont])), // 💡 表头注入
                    pw.SizedBox(height: 15),

                    // 💡 核心：调用新的 Markdown 渲染器，传入 emojiFont
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
                    ],
                    pw.SizedBox(height: 30),
                    pw.Divider()
                  ]));
        }
        final file = File(savePath);
        await file.writeAsBytes(await pdf.save());
      } else if (format == 'pdf_zip') {
        final archive = Archive();

        // 💡 修复：将这里也替换为本地离线字体读取！
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

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String date = d['date'] ?? '';
          String formattedDate =
              date.length >= 16 ? date.substring(0, 16) : date;
          String content =
              d['is_locked'] == 1 ? "【此日记已加密，无法导出明文】" : (d['content'] ?? '');

          String weather =
              AppConstants.getWeatherEmoji(d['weather'] as String?);
          String mood = AppConstants.getMoodEmoji(d['mood'] as String?);

          List<String> images = [];
          try {
            if (d['image_path'] != null)
              images = List<String>.from(jsonDecode(d['image_path']));
            else if (d['imagePath'] != null)
              images = List<String>.from(jsonDecode(d['imagePath']));
          } catch (_) {}

          // 💡 注册粗体和表情备用字体
          final singlePdf = pw.Document(
              theme: pw.ThemeData.withFont(
                  base: font, bold: fontBold, fontFallback: [emojiFont]));
          singlePdf.addPage(pw.MultiPage(
              build: (pw.Context context) => [
                    pw.Header(
                        level: 0,
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 24,
                                fontFallback: [emojiFont]))), // 💡 标题注入

                    pw.Text("记录时间: $formattedDate    天气: $weather    心情: $mood",
                        style: pw.TextStyle(
                            color: PdfColors.grey,
                            fontFallback: [emojiFont])), // 💡 表头注入
                    pw.SizedBox(height: 15),

                    // 💡 核心：调用新的 Markdown 渲染器，传入 emojiFont
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
                    ],
                  ]));
          List<int> pdfBytes = await singlePdf.save();
          archive.addFile(ArchiveFile(
              '${formattedDate.replaceAll(':', '')}_$safeTitle.pdf',
              pdfBytes.length,
              pdfBytes));
        }
        final zipData = ZipEncoder().encode(archive);
        await File(savePath).writeAsBytes(zipData);
      }

      if (mounted) {
        if (isDialogShowing) Navigator.pop(context);
        setState(() {
          _isSelectionMode = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("🎉 批量导出成功！"),
          backgroundColor: Colors.teal,
          action: (Platform.isAndroid || Platform.isIOS)
              ? SnackBarAction(
                  label: '分享/保存',
                  textColor: Colors.white,
                  onPressed: () async {
                    // 1. 等待用户操作分享面板（无论是分享成功还是取消）
                    await Share.shareXFiles([XFile(savePath!)]);
                  })
              : null,
        ));
      }
    } catch (e) {
      if (mounted) {
        if (isDialogShowing) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("批量导出失败: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showBatchExportMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                  padding: const EdgeInsets.only(
                      left: 16.0, right: 8.0, top: 12.0, bottom: 8.0),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("已选中 ${_selectedIds.length} 篇，请选择导出格式",
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(c))
                      ])),
              ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text("合并为一份 PDF 文档"),
                  subtitle: const Text("将所有选中的日记首尾相连成册"),
                  onTap: () {
                    Navigator.pop(c);
                    _batchExport('pdf');
                  }),
              ListTile(
                  leading:
                      const Icon(Icons.folder_zip, color: Colors.redAccent),
                  title: const Text("打包成独立的 PDF 压缩包"),
                  subtitle: const Text("每篇日记分别生成独立的高清 .pdf"),
                  onTap: () {
                    Navigator.pop(c);
                    _batchExport('pdf_zip');
                  }),
              ListTile(
                  leading: const Icon(Icons.folder_zip, color: Colors.blueGrey),
                  title: const Text("打包成 Markdown 压缩包 (.zip)"),
                  subtitle: const Text("每篇日记生成独立的 .md 文件"),
                  onTap: () {
                    Navigator.pop(c);
                    _batchExport('md');
                  }),
              ListTile(
                  leading: const Icon(Icons.folder_zip, color: Colors.grey),
                  title: const Text("打包成 TXT 压缩包 (.zip)"),
                  subtitle: const Text("每篇日记生成独立的 .txt 文件"),
                  onTap: () {
                    Navigator.pop(c);
                    _batchExport('txt');
                  }),
              ListTile(
                  leading: const Icon(Icons.folder_zip, color: Colors.blue),
                  title: const Text("打包成 Word 压缩包 (.zip)"),
                  subtitle: const Text("每篇日记生成独立的 .doc 文件"),
                  onTap: () {
                    Navigator.pop(c);
                    _batchExport('doc');
                  }),
              const Divider(),
              ListTile(
                  leading:
                      const Icon(Icons.cancel_outlined, color: Colors.grey),
                  title:
                      const Text("取消导出", style: TextStyle(color: Colors.grey)),
                  onTap: () => Navigator.pop(c)),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // 💡 针对手机端重构的精美侧边抽屉菜单
  Drawer _buildMobileDrawer(Color themeColor) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: themeColor),
            child: const SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('GrainBuds',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('记录生活，留住感动',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.search, color: Colors.blueGrey),
            title: const Text('全局搜索',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context); // 关闭抽屉
              setState(() {
                _isSearching = true;
                _searchKeyword = "";
                _searchResults.clear();
              });
            },
          ),
          // 💡 将归类收藏用 ExpansionTile 优雅地收纳起来
          ExpansionTile(
            leading:
                const Icon(Icons.collections_bookmark, color: Colors.blueGrey),
            title: const Text('归类收藏',
                style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              ListTile(
                  contentPadding: const EdgeInsets.only(left: 50),
                  leading: const Icon(Icons.sell_outlined, color: Colors.teal),
                  title: const Text('标签聚合墙'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const TagsPage()));
                  }),
              ListTile(
                  contentPadding: const EdgeInsets.only(left: 50),
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: const Text('星标日记'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const CollectionPage(type: 'starred')));
                  }),
              ListTile(
                  contentPadding: const EdgeInsets.only(left: 50),
                  leading: const Icon(Icons.archive, color: Colors.brown),
                  title: const Text('归档记录'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const CollectionPage(type: 'archived')));
                  }),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.event_note, color: Colors.blueGrey),
            title: const Text('时光看板', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AnniversariesPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart, color: Colors.blueGrey),
            title: const Text('统计报表',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const StatsPage()));
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.blueGrey),
            title: const Text('软件设置',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsPage()));
              _refreshTrigger.value++;
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;
    // 💡 核心新增：判断当前是否是手机端
    final bool isMobile = Platform.isAndroid || Platform.isIOS;

    // 1. 构建中间的主体内容区
    Widget mainContent = _isSearching
        ? (_searchKeyword.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore,
                        size: 80, color: themeColor.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    const Text("在茫茫岁月中，你想寻找哪段记忆？",
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            letterSpacing: 1)),
                  ],
                ),
              )
            : (_searchResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sentiment_dissatisfied,
                            size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text("未找到包含 “$_searchKeyword” 的日记",
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    // 💡 新增：当用户手指在这个列表中滑动时，立刻自动收起软键盘
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(top: 10, bottom: 40),
                    itemCount: _searchResults.length,
                    itemBuilder: (c, i) => DiaryCard(
                        diary: _searchResults[i],
                        onRefresh: () => _performSearch(_searchKeyword)))))
        // 💡 核心分离：手机端用 PageView 滑动，电脑端用 IndexedStack 原地切换
        : (isMobile
            ? PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                children: [
                  CalendarTab(refreshTrigger: _refreshTrigger),
                  TimelineTab(
                    refreshTrigger: _refreshTrigger,
                    isSelectionMode: _isSelectionMode,
                    selectedIds: _selectedIds,
                    isDescending: _isDescending,
                    onSelectionChanged: (id, selected) {
                      setState(() {
                        if (selected)
                          _selectedIds.add(id);
                        else
                          _selectedIds.remove(id);
                      });
                    },
                    onEnterSelectionMode: (startId) {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedIds.add(startId);
                      });
                    },
                  ),
                ],
              )
            : IndexedStack(
                index: _currentIndex,
                children: [
                  CalendarTab(refreshTrigger: _refreshTrigger),
                  TimelineTab(
                    refreshTrigger: _refreshTrigger,
                    isSelectionMode: _isSelectionMode,
                    selectedIds: _selectedIds,
                    isDescending: _isDescending,
                    onSelectionChanged: (id, selected) {
                      setState(() {
                        if (selected)
                          _selectedIds.add(id);
                        else
                          _selectedIds.remove(id);
                      });
                    },
                    onEnterSelectionMode: (startId) {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedIds.add(startId);
                      });
                    },
                  ),
                ],
              ));

    return Scaffold(
      drawerEdgeDragWidth: 60.0,
      // 💡 只有手机端，且非选择/非搜索模式下才启用抽屉
      drawer: (isMobile && !_isSelectionMode && !_isSearching)
          ? _buildMobileDrawer(themeColor)
          : null,

      appBar: isMobile
          ? AppBar(
              backgroundColor: _isSelectionMode ? Colors.blueGrey : themeColor,
              foregroundColor: Colors.white,
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectedIds.clear();
                        });
                      })
                  : (_isSearching
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchKeyword = "";
                              _searchResults.clear();
                            });
                          })
                      : null),
              title: _isSearching
                  ? TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                          hintText: '搜索...',
                          hintStyle: TextStyle(color: Colors.white60),
                          border: InputBorder.none),
                      onChanged: (val) {
                        setState(() => _searchKeyword = val);
                        _performSearch(val);
                      },
                    )
                  : Text(
                      _isSelectionMode
                          ? '已选中 ${_selectedIds.length} 篇'
                          : (_currentIndex == 0 ? '日历视图' : '时间轴'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                if (_isSelectionMode)
                  IconButton(
                      icon: const Icon(Icons.ios_share),
                      onPressed: _showBatchExportMenu)
              ],
            ) as PreferredSizeWidget
          : CustomTitleBar(
              backgroundColor: _isSelectionMode ? Colors.blueGrey : themeColor,
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectedIds.clear();
                        });
                      })
                  : (_isSearching
                      ? IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchKeyword = "";
                              _searchResults.clear();
                            });
                          })
                      : null),
              title: _isSearching
                  ? Container(
                      height: 36,
                      margin: const EdgeInsets.only(right: 30),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(18)),
                      child: TextField(
                          autofocus: true,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                              hintText: '搜索...',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.white70, size: 18)),
                          onChanged: (val) {
                            setState(() => _searchKeyword = val);
                            _performSearch(val);
                          }),
                    )
                  : Text(
                      _isSelectionMode
                          ? '已选中 ${_selectedIds.length} 篇'
                          : 'GrainBuds-小满日记',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: !_isSelectionMode ? 'Georgia' : null,
                          letterSpacing: !_isSelectionMode ? 1.5 : null)),
              actions: [
                if (_isSelectionMode)
                  IconButton(
                      icon: const Icon(Icons.ios_share, color: Colors.white),
                      onPressed: _showBatchExportMenu)
              ],
            ) as PreferredSizeWidget,

      // 💡 核心分离：手机端直接展示主内容，电脑端恢复 Row 左右分栏布局
      body: isMobile
          ? mainContent
          : Row(
              children: [
                if (!_isSearching && !_isSelectionMode)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: _isExtended ? 160 : 70,
                    color: themeColor.withOpacity(0.05),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 70,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: IconButton(
                                  icon: Icon(
                                      _isExtended
                                          ? Icons.menu_open
                                          : Icons.menu,
                                      color: Colors.grey),
                                  onPressed: () => setState(
                                      () => _isExtended = !_isExtended),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildNavItem(0, Icons.calendar_month_outlined,
                            Icons.calendar_month, '日历视图', themeColor),
                        _buildNavItem(1, Icons.timeline_outlined,
                            Icons.timeline, '时间轴', themeColor),
                        const Spacer(),
                        _buildSideActionButton(Icons.search, '全局搜索', () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) {
                              _searchKeyword = "";
                              _searchResults.clear();
                            }
                          });
                        }),
                        _buildSideActionButton(Icons.event_note, '时光看板', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AnniversariesPage()));
                        }),
                        _buildCollectionMenu(),
                        _buildSideActionButton(Icons.bar_chart, '统计报表', () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const StatsPage()));
                        }),
                        const SizedBox(height: 10),
                        _buildSideActionButton(Icons.settings, '软件设置',
                            () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const SettingsPage()));
                          _refreshTrigger.value++;
                        }),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                if (!_isSearching && !_isSelectionMode)
                  const VerticalDivider(
                      thickness: 1, width: 1, color: Colors.black12),
                Expanded(child: mainContent),
              ],
            ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: themeColor,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                        backgroundColor: themeColor,
                        child: const Icon(Icons.book, color: Colors.white)),
                    title: const Text('写日记'),
                    subtitle: const Text('记录今天的故事和感悟'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context,
                          createSmoothRoute(const DiaryEditPage(entryType: 0)));
                      if (result == true) _refreshTrigger.value++;
                    },
                  ),
                  ListTile(
                    leading: CircleAvatar(
                        backgroundColor: Colors.green.shade500,
                        child: const Icon(Icons.bolt, color: Colors.white)),
                    title: const Text('随手记'),
                    subtitle: const Text('快速记录闪念、灵感或待办'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context,
                          createSmoothRoute(const DiaryEditPage(entryType: 1)));
                      if (result == true) _refreshTrigger.value++;
                    },
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ================= 恢复电脑端专属侧边栏组件 =================

  Widget _buildNavItem(int index, IconData unselectedIcon,
      IconData selectedIcon, String label, Color themeColor) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? themeColor : Colors.grey;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // 💡 注意这里去掉了 PageView 的控制逻辑，改回原来的 setState 切换
        onTap: () => setState(() => _currentIndex = index),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              SizedBox(
                  width: 70,
                  child: Icon(isSelected ? selectedIcon : unselectedIcon,
                      color: color)),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      color: color,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideActionButton(
      IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              SizedBox(width: 70, child: Icon(icon, color: Colors.blueGrey)),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.blueGrey, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionMenu() {
    return PopupMenuButton<String>(
      tooltip: _isExtended ? '' : '归类与收藏',
      offset: const Offset(70, -100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'tags') {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const TagsPage()));
        } else if (value == 'starred') {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CollectionPage(type: 'starred')));
        } else if (value == 'archived') {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      const CollectionPage(type: 'archived')));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
            value: 'tags',
            child: Row(children: [
              Icon(Icons.sell_outlined, color: Colors.teal),
              SizedBox(width: 12),
              Text('标签聚合墙')
            ])),
        const PopupMenuItem<String>(
            value: 'starred',
            child: Row(children: [
              Icon(Icons.star, color: Colors.amber),
              SizedBox(width: 12),
              Text('星标日记')
            ])),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
            value: 'archived',
            child: Row(children: [
              Icon(Icons.archive, color: Colors.brown),
              SizedBox(width: 12),
              Text('归档记录')
            ])),
      ],
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(
                width: 70,
                child:
                    Icon(Icons.collections_bookmark, color: Colors.blueGrey)),
            const Expanded(
                child: Text('归类收藏',
                    style: TextStyle(
                        color: Colors.blueGrey, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip)),
          ],
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

// ========= Tab 1: 日历页 =========
class CalendarTab extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  const CalendarTab({super.key, required this.refreshTrigger});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  List<Map<String, dynamic>> diaries = [];
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Map<DateTime, String> _dailyCoverImages = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
    widget.refreshTrigger.addListener(_fetchData);
  }

  @override
  void dispose() {
    widget.refreshTrigger.removeListener(_fetchData);
    super.dispose();
  }

  List<String> _parseImages(dynamic imgData) {
    if (imgData == null) return [];
    try {
      return List<String>.from(jsonDecode(imgData));
    } catch (_) {
      return [];
    }
  }

  void _extractCoverImages(List<Map<String, dynamic>> allDiariesData) {
    Map<DateTime, String> covers = {};
    Map<DateTime, List<Map<String, dynamic>>> grouped = {};

    for (var d in allDiariesData) {
      DateTime parsedDate = DateTime.parse(d['date']);
      DateTime dateKey =
          DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      grouped.putIfAbsent(dateKey, () => []).add(d);
    }

    for (var entry in grouped.entries) {
      DateTime dateKey = entry.key;
      List<Map<String, dynamic>> dailyDocs = entry.value;
      String? bestImg;

      for (var doc in dailyDocs.where((e) => e['type'] == 0)) {
        List<String> imgs = _parseImages(doc['image_path'] ?? doc['imagePath']);
        if (imgs.isNotEmpty) {
          bestImg = imgs.first;
          break;
        }
      }

      if (bestImg == null) {
        for (var doc in dailyDocs.where((e) => e['type'] == 1)) {
          List<String> imgs =
              _parseImages(doc['image_path'] ?? doc['imagePath']);
          if (imgs.isNotEmpty) {
            bestImg = imgs.first;
            break;
          }
        }
      }

      if (bestImg != null) {
        // 💡 核心修复：把路径交给 UI 渲染前，先验证物理文件是否真的存在！
        // 彻底切断 Image.file 去读取空气导致报错卡死调试器的问题
        try {
          if (File(bestImg).existsSync()) {
            covers[dateKey] = bestImg;
          }
        } catch (_) {}
      }
    }

    setState(() {
      _dailyCoverImages = covers;
    });
  }

  Future<void> _fetchData() async {
    final data = await DatabaseHelper.instance.getDiariesByDate(_selectedDay);
    final allData = await DatabaseHelper.instance.getAllDiaries();

    if (mounted) {
      _extractCoverImages(allData);
      setState(() {
        diaries = data;
      });
    }
  }

  Widget _buildCell(DateTime date, String imgPath,
      {bool isSelected = false, bool isToday = false}) {
    return Container(
      margin: const EdgeInsets.all(4.0),
      alignment: Alignment.center,
      decoration: isSelected
          ? BoxDecoration(
              border: Border.all(color: Colors.teal, width: 3),
              shape: BoxShape.circle)
          : (isToday
              ? BoxDecoration(
                  border: Border.all(color: Colors.teal, width: 2),
                  shape: BoxShape.circle)
              : null),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              File(imgPath),
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              cacheWidth: 100,
              errorBuilder: (c, o, s) =>
                  const Icon(Icons.broken_image, size: 10, color: Colors.grey),
            ),
          ),
          Text(
            '${date.day}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4),
                Shadow(color: Colors.black87, blurRadius: 4),
                Shadow(color: Colors.black, blurRadius: 6)
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getEmptyPlaceholder() {
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '这一天没有留下印记';
    if (sDay.isAfter(today)) return '未来的这一天还是未知的';
    return '今天还没有记录哦';
  }

  String _getWriteLabel() {
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '补写这天的回忆';
    if (sDay.isAfter(today)) return '写给这天的期许';
    return '开始记录这一天';
  }

  String _getAddMoreLabel() {
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '再补写一篇这天的回忆';
    if (sDay.isAfter(today)) return '再写一篇给这天的期许';
    return '再记录一篇';
  }

  IconData _getWriteIcon() {
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return Icons.history_edu;
    if (sDay.isAfter(today)) return Icons.flight_takeoff;
    return Icons.edit;
  }

  void _openMemoryEditorDialog(BuildContext context) {
    DateTime today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);

    bool isPast = sDay.isBefore(today);
    bool isFuture = sDay.isAfter(today);

    String titlePrefix = isPast ? '补写回忆' : (isFuture ? '未来期许' : '记录');
    String dateStr =
        '${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(isPast ? Icons.history_edu : Icons.book,
                      color: Colors.white)),
              title: Text('$titlePrefix日记'),
              subtitle: Text('日期将被锚定在 $dateStr'),
              onTap: () async {
                Navigator.pop(c);
                final result = await Navigator.push(
                    context,
                    createSmoothRoute(DiaryEditPage(
                        entryType: 0, selectedDate: _selectedDay)));
                if (result == true) widget.refreshTrigger.value++;
              },
            ),
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: Colors.green.shade500,
                  child: const Icon(Icons.bolt, color: Colors.white)),
              title: Text('$titlePrefix随手记'),
              subtitle: const Text('快速记录闪念或待办'),
              onTap: () async {
                Navigator.pop(c);
                final result = await Navigator.push(
                    context,
                    createSmoothRoute(DiaryEditPage(
                        entryType: 1, selectedDate: _selectedDay)));
                if (result == true) widget.refreshTrigger.value++;
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (sDay, fDay) {
            setState(() {
              _selectedDay = sDay;
              _focusedDay = fDay;
            });
            _fetchData();
          },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, date, focusedDay) {
              DateTime dateKey = DateTime(date.year, date.month, date.day);
              String? imgPath = _dailyCoverImages[dateKey];
              if (imgPath == null) return null;
              return _buildCell(date, imgPath);
            },
            selectedBuilder: (context, date, focusedDay) {
              DateTime dateKey = DateTime(date.year, date.month, date.day);
              String? imgPath = _dailyCoverImages[dateKey];
              if (imgPath == null) return null;
              return _buildCell(date, imgPath, isSelected: true);
            },
            todayBuilder: (context, date, focusedDay) {
              DateTime dateKey = DateTime(date.year, date.month, date.day);
              String? imgPath = _dailyCoverImages[dateKey];
              if (imgPath == null) return null;
              return _buildCell(date, imgPath, isToday: true);
            },
            markerBuilder: null,
          ),
        ),
        const Divider(height: 1),
        Expanded(
            child: diaries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_calendar,
                            size: 48, color: Colors.teal.shade100),
                        const SizedBox(height: 16),
                        Text(_getEmptyPlaceholder(),
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: Icon(_getWriteIcon()),
                          label: Text(_getWriteLabel(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            elevation: 2,
                          ),
                          onPressed: () => _openMemoryEditorDialog(context),
                        )
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: diaries.length + 1,
                    itemBuilder: (c, i) {
                      if (i == diaries.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(_getAddMoreLabel()),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade50,
                                  foregroundColor: Colors.teal,
                                  elevation: 0),
                              onPressed: () => _openMemoryEditorDialog(context),
                            ),
                          ),
                        );
                      }
                      return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 4.0),
                          child: DiaryCard(
                              diary: diaries[i],
                              onRefresh: () => widget.refreshTrigger.value++));
                    })),
      ],
    );
  }
}

// ========= Tab 2: 时间轴页 =========
class TimelineTab extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  final bool isSelectionMode;
  final Set<int> selectedIds;
  final bool isDescending;
  final Function(int, bool) onSelectionChanged;
  final Function(int) onEnterSelectionMode;

  const TimelineTab(
      {super.key,
      required this.refreshTrigger,
      required this.isSelectionMode,
      required this.selectedIds,
      required this.isDescending,
      required this.onSelectionChanged,
      required this.onEnterSelectionMode});
  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  List<Map<String, dynamic>> allDiaries = [];
  List<Map<String, dynamic>> onThisDayDiaries = [];
  int _filterType = -1;

  @override
  void initState() {
    super.initState();
    _fetchAll();
    widget.refreshTrigger.addListener(_fetchAll);
  }

  @override
  void dispose() {
    widget.refreshTrigger.removeListener(_fetchAll);
    super.dispose();
  }

  Future<void> _fetchAll() async {
    List<Map<String, dynamic>> rawData =
        await DatabaseHelper.instance.getAllDiaries();

    List<Map<String, dynamic>> data = [];
    if (_filterType == -1) {
      data = rawData;
    } else {
      data = rawData
          .where((d) => (d['type'] as int? ?? 0) == _filterType)
          .toList();
    }

    if (!widget.isDescending) data = data.reversed.toList();

    DateTime today = DateTime.now();
    List<Map<String, dynamic>> historical = [];
    for (var d in data) {
      DateTime diaryDate = DateTime.parse(d['date'] as String);
      if (diaryDate.month == today.month &&
          diaryDate.day == today.day &&
          diaryDate.year < today.year) {
        historical.add(d);
      }
    }

    if (mounted) {
      setState(() {
        allDiaries = data;
        onThisDayDiaries = historical;
      });
    }
  }

  Widget _buildOnThisDayBanner() {
    if (onThisDayDiaries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.orange.shade200, Colors.orange.shade50]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.orange.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.history, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text("历史上的今天",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                    fontSize: 18))
          ]),
          const SizedBox(height: 10),
          ...onThisDayDiaries.map((diary) {
            final int yearsAgo = DateTime.now().year -
                DateTime.parse(diary['date'] as String).year;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                  "🕰️ $yearsAgo年前的今天: ${(diary['title'] as String?) ?? '无标题'}",
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w500)),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
      Map<String, dynamic> diary, bool isFirst, bool isLast) {
    final int id = diary['id'] as int;
    final String dateStr = diary['date'] as String;
    final DateTime date = DateTime.parse(dateStr);

    final bool isUnknownDate = dateStr.startsWith('1900-01-01');
    final bool isArchived = (diary['is_archived'] as int? ?? 0) == 1;
    final Color lineColor =
        isArchived ? Colors.grey.shade400 : Theme.of(context).primaryColor;

    // 💡 核心：区分双端尺寸，极致压缩手机端左侧宽度
    bool isMobile = Platform.isAndroid || Platform.isIOS;
    double leftWidth = isMobile ? 45.0 : 70.0;
    double lineWidth = isMobile ? 20.0 : 30.0;
    double dateFontSize = isMobile ? 18.0 : 22.0;
    double monthFontSize = isMobile ? 10.0 : 12.0;
    double timeFontSize = isMobile ? 9.0 : 10.0;
    double iconSize = isMobile ? 18.0 : 24.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：日期与时间
          SizedBox(
            width: leftWidth,
            child: Padding(
              padding: EdgeInsets.only(
                  top: 25, left: isMobile ? 4 : 12, right: isMobile ? 4 : 0),
              child: isUnknownDate
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(Icons.hourglass_empty,
                            color: Colors.brown, size: iconSize),
                        const SizedBox(height: 4),
                        Text("岁月深处",
                            style: TextStyle(
                                fontSize: timeFontSize, color: Colors.brown)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${date.day}",
                            style: TextStyle(
                                fontSize: dateFontSize,
                                fontWeight: FontWeight.bold,
                                color: lineColor)),
                        Text("${date.month}月",
                            style: TextStyle(
                                fontSize: monthFontSize, color: Colors.grey)),
                        Text(DateFormat('HH:mm').format(date),
                            style: TextStyle(
                                fontSize: timeFontSize,
                                color: lineColor,
                                fontWeight: FontWeight.w300)),
                      ],
                    ),
            ),
          ),
          // 中间：线与圆点
          SizedBox(
            width: lineWidth,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VerticalDivider(
                    color: lineColor.withOpacity(0.3),
                    thickness: isMobile ? 1.5 : 2),
                Positioned(
                    top: 32,
                    child: Container(
                        height: isMobile ? 10 : 12,
                        width: isMobile ? 10 : 12,
                        decoration: BoxDecoration(
                            color: isArchived
                                ? Colors.grey.shade200
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: lineColor, width: isMobile ? 1.5 : 2),
                            boxShadow: [
                              BoxShadow(
                                  color: lineColor.withOpacity(0.2),
                                  blurRadius: 4)
                            ]))),
              ],
            ),
          ),
          // 右侧：日记卡片
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  right: isMobile ? 12.0 : 16.0,
                  top: isMobile ? 6 : 10,
                  bottom: isMobile ? 6 : 10),
              child: DiaryCard(
                diary: diary,
                onRefresh: () => widget.refreshTrigger.value++,
                isSelectionMode: widget.isSelectionMode,
                isSelected: widget.selectedIds.contains(id),
                onSelected: (selected) =>
                    widget.onSelectionChanged(id, selected),
                onLongPress: () => widget.onEnterSelectionMode(id),
                heroTagPrefix: 'home_',
                showDate: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget filterBar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
              label: const Text('全部'),
              selected: _filterType == -1,
              selectedColor: Colors.teal.shade100,
              onSelected: (v) {
                setState(() => _filterType = -1);
                _fetchAll();
              }),
          const SizedBox(width: 10),
          FilterChip(
              label: const Text('日记'),
              selected: _filterType == 0,
              selectedColor: Colors.teal.shade100,
              onSelected: (v) {
                setState(() => _filterType = 0);
                _fetchAll();
              }),
          const SizedBox(width: 10),
          FilterChip(
              label: const Text('随手记'),
              selected: _filterType == 1,
              selectedColor: Colors.green.shade100,
              onSelected: (v) {
                setState(() => _filterType = 1);
                _fetchAll();
              }),
        ],
      ),
    );

    if (allDiaries.isEmpty && _filterType == -1) {
      return Column(children: [
        filterBar,
        const Expanded(
            child: Center(
                child: Text('时间轴空空如也，快去记录吧！',
                    style: TextStyle(color: Colors.grey))))
      ]);
    }

    return Column(
      children: [
        filterBar,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            // 💡 优化 1：按需渲染。如果有“历史上的今天”，总数要 +1
            itemCount:
                allDiaries.length + (onThisDayDiaries.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              // 1. 如果有历史上的今天，并且是第 0 项，渲染 Banner
              if (onThisDayDiaries.isNotEmpty && index == 0) {
                return _buildOnThisDayBanner();
              }

              // 2. 计算日记在 allDiaries 中的真实索引
              int diaryIndex = onThisDayDiaries.isNotEmpty ? index - 1 : index;

              return _buildTimelineItem(allDiaries[diaryIndex], diaryIndex == 0,
                  diaryIndex == allDiaries.length - 1);
            },
          ),
        ),
      ],
    );
  }
}

// ================= 全局丝滑路由切换工具 =================
Route createSmoothRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: ScaleTransition(
          scale: animation.drive(Tween(begin: 0.95, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOutCubic))),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
  );
}
