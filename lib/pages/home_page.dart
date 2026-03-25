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
    FileSaveLocation? result;

    if (format == 'pdf') {
      result = await getSaveLocation(suggestedName: '批量合并日记_$timeStamp.pdf');
    } else if (format == 'pdf_zip') {
      result = await getSaveLocation(suggestedName: '批量独立PDF_$timeStamp.zip');
    } else {
      result = await getSaveLocation(suggestedName: '批量导出日记_$timeStamp.zip');
    }

    if (result == null) return;

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
        final font = await PdfGoogleFonts.notoSansSCRegular();
        final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String date = d['date'] ?? '';
          String content =
              d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          pdf.addPage(pw.MultiPage(
              build: (pw.Context context) => [
                    pw.Header(
                        level: 0,
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 24, fontWeight: pw.FontWeight.bold))),
                    pw.Text("记录时间: $date",
                        style: const pw.TextStyle(color: PdfColors.grey)),
                    pw.SizedBox(height: 15),
                    pw.Text(content,
                        style:
                            const pw.TextStyle(fontSize: 14, lineSpacing: 5)),
                    pw.SizedBox(height: 30),
                    pw.Divider()
                  ]));
        }
        final file = File(result.path);
        await file.writeAsBytes(await pdf.save());
      } else if (format == 'pdf_zip') {
        final archive = Archive();
        final font = await PdfGoogleFonts.notoSansSCRegular();

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content =
              d['is_locked'] == 1 ? "【此日记已加密，无法导出明文】" : (d['content'] ?? '');
          final singlePdf =
              pw.Document(theme: pw.ThemeData.withFont(base: font));
          singlePdf.addPage(pw.MultiPage(
              build: (pw.Context context) => [
                    pw.Header(
                        level: 0,
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 24, fontWeight: pw.FontWeight.bold))),
                    pw.Text("记录时间: $dateStr",
                        style: const pw.TextStyle(color: PdfColors.grey)),
                    pw.SizedBox(height: 15),
                    pw.Text(content,
                        style: const pw.TextStyle(fontSize: 14, lineSpacing: 5))
                  ]));
          List<int> pdfBytes = await singlePdf.save();
          archive.addFile(ArchiveFile(
              '${dateStr.length >= 10 ? dateStr.substring(0, 10) : '未知日期'}_$safeTitle.pdf',
              pdfBytes.length,
              pdfBytes));
        }
        final zipData = ZipEncoder().encode(archive);
        await File(result.path).writeAsBytes(zipData);
      } else {
        final archive = Archive();
        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content =
              d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          String outputContent = "";
          if (format == 'md') {
            outputContent = "# $title\n\n**记录时间:** $dateStr\n\n---\n\n$content";
          } else if (format == 'txt') {
            outputContent = "标题: $title\n时间: $dateStr\n\n$content";
          } else if (format == 'doc') {
            outputContent =
                "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\" xmlns=\"http://www.w3.org/TR/REC-html40\"><head><meta charset=\"utf-8\"><title>$title</title></head><body style=\"font-family: 'Microsoft YaHei', sans-serif;\"><h1 style=\"text-align: center;\">$title</h1><p style=\"color: gray; text-align: center;\">记录时间: $dateStr</p><hr><div style=\"white-space: pre-wrap; line-height: 1.6; font-size: 12pt;\">$content</div></body></html>";
          }
          List<int> bytes = utf8.encode(outputContent);
          archive.addFile(ArchiveFile(
              '${dateStr.length >= 10 ? dateStr.substring(0, 10) : '未知日期'}_$safeTitle.$format',
              bytes.length,
              bytes));
        }
        final zipData = ZipEncoder().encode(archive);
        await File(result.path).writeAsBytes(zipData);
      }

      if (mounted) {
        if (isDialogShowing) Navigator.pop(context);
        setState(() {
          _isSelectionMode = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("🎉 批量导出成功！"), backgroundColor: Colors.teal));
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

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: CustomTitleBar(
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: '退出搜索',
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
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: '输入日记标题、正文内容或标签查找...',
                    hintStyle: TextStyle(color: Colors.white60),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    prefixIcon: Icon(Icons.search, color: Colors.white70, size: 18),
                  ),
                  onChanged: (val) {
                    setState(() => _searchKeyword = val);
                    _performSearch(val);
                  },
                ),
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
                tooltip: '批量导出',
                onPressed: _showBatchExportMenu)
        ],
      ),
      
      body: Row(
        children: [
          // 🌟 终极修复：彻底抛弃有跳转 BUG 的 NavigationRail，换成丝滑无比的自定义动画侧边栏
          if (!_isSearching && !_isSelectionMode)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic, // 让展开和收起更加顺滑
              width: _isExtended ? 160 : 70, // 侧边栏宽度平滑过渡
              color: themeColor.withOpacity(0.05),
              child: Column(
                children: [
                  // 顶部汉堡菜单按钮
                  SizedBox(
                    height: 70,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: IconButton(
                            icon: Icon(_isExtended ? Icons.menu_open : Icons.menu, color: Colors.grey),
                            onPressed: () => setState(() => _isExtended = !_isExtended),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 主导航：日历视图
                  _buildNavItem(0, Icons.calendar_month_outlined, Icons.calendar_month, '日历视图', themeColor),
                  // 主导航：时间轴
                  _buildNavItem(1, Icons.timeline_outlined, Icons.timeline, '时间轴', themeColor),
                  
                  const Spacer(),
                  
                  // 底部工具栏
                  _buildSideActionButton(Icons.search, '全局搜索', () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchKeyword = "";
                        _searchResults.clear();
                      }
                    });
                  }),
                  _buildCollectionMenu(),
                  _buildSideActionButton(Icons.bar_chart, '统计报表', () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsPage()));
                  }),
                  const SizedBox(height: 10),
                  _buildSideActionButton(Icons.settings, '软件设置', () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
                    _refreshTrigger.value++;
                  }),
                  const SizedBox(height: 20),
                ],
              ),
            ),

          const VerticalDivider(thickness: 1, width: 1, color: Colors.black12),

          Expanded(
            child: _isSearching
              ? (_searchKeyword.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.travel_explore, size: 80, color: themeColor.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          const Text("在茫茫岁月中，你想寻找哪段记忆？", style: TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1)),
                        ],
                      ),
                    )
                  : (_searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text("未找到包含 “$_searchKeyword” 的日记", style: const TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 10, bottom: 40),
                          itemCount: _searchResults.length,
                          itemBuilder: (c, i) => DiaryCard(
                              diary: _searchResults[i],
                              onRefresh: () => _performSearch(_searchKeyword)))))
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
                          if (selected) _selectedIds.add(id);
                          else _selectedIds.remove(id);
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
                ),
          ),
        ],
      ),
      
      floatingActionButton: FloatingActionButton(
        backgroundColor: themeColor,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: CircleAvatar(backgroundColor: themeColor, child: const Icon(Icons.book, color: Colors.white)),
                    title: const Text('写日记'),
                    subtitle: const Text('记录今天的故事和感悟'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context, createSmoothRoute(const DiaryEditPage(entryType: 0)));
                      if (result == true) _refreshTrigger.value++;
                    },
                  ),
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.green.shade500, child: const Icon(Icons.bolt, color: Colors.white)),
                    title: const Text('随手记'),
                    subtitle: const Text('快速记录闪念、灵感或待办'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context, createSmoothRoute(const DiaryEditPage(entryType: 1)));
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

  // ================= 新增：丝滑无跳动的侧边栏组件 =================

  Widget _buildNavItem(int index, IconData unselectedIcon, IconData selectedIcon, String label, Color themeColor) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? themeColor : Colors.grey;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        child: SizedBox(
          height: 56, // 导航项高度
          child: Row(
            children: [
              // 💡 魔法 1：永远固定在 70 像素的盒子里，图标死也不会乱动！
              SizedBox(width: 70, child: Icon(isSelected ? selectedIcon : unselectedIcon, color: color)),
              // 💡 魔法 2：剩余空间交给文字，利用 clip 裁剪实现像拉开幕布一样的文字显隐效果
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  maxLines: 1,
                  softWrap: false, // 禁止换行
                  overflow: TextOverflow.clip, // 边缘直接裁剪，形成幕布滑动效果
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideActionButton(IconData icon, String label, VoidCallback onTap) {
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
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold),
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

  Widget _buildCollectionMenu() {
    return PopupMenuButton<String>(
      tooltip: _isExtended ? '' : '归类与收藏',
      offset: const Offset(70, -100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'tags') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const TagsPage()));
        } else if (value == 'starred') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const CollectionPage(type: 'starred')));
        } else if (value == 'archived') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const CollectionPage(type: 'archived')));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'tags',
          child: Row(children: [Icon(Icons.sell_outlined, color: Colors.teal), SizedBox(width: 12), Text('标签聚合墙')]),
        ),
        const PopupMenuItem<String>(
          value: 'starred',
          child: Row(children: [Icon(Icons.star, color: Colors.amber), SizedBox(width: 12), Text('星标日记')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'archived',
          child: Row(children: [Icon(Icons.archive, color: Colors.brown), SizedBox(width: 12), Text('归档记录')]),
        ),
      ],
      // 这里的 child 就是显示在侧边栏上的按钮本体
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 70, child: Icon(Icons.collections_bookmark, color: Colors.blueGrey)),
            const Expanded(
              child: Text(
                '归类收藏',
                style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========= Tab 1: 日历页 =========

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
        List<String> imgs = _parseImages(doc['imagePath']);
        if (imgs.isNotEmpty) {
          bestImg = imgs.first;
          break;
        }
      }

      if (bestImg == null) {
        for (var doc in dailyDocs.where((e) => e['type'] == 1)) {
          List<String> imgs = _parseImages(doc['imagePath']);
          if (imgs.isNotEmpty) {
            bestImg = imgs.first;
            break;
          }
        }
      }

      if (bestImg != null) {
        covers[dateKey] = bestImg;
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

  // 💡 保证绝对居中，且只用于有图片的日期
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
                    createSmoothRoute(DiaryEditPage(entryType: 0, selectedDate: _selectedDay)));
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
                    createSmoothRoute(DiaryEditPage(entryType: 1, selectedDate: _selectedDay)));
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
              // 💡 修复重点 1：如果没有图，直接 return null！完全交给插件原生渲染，不再出 bug。
              if (imgPath == null) return null;
              return _buildCell(date, imgPath);
            },
            selectedBuilder: (context, date, focusedDay) {
              DateTime dateKey = DateTime(date.year, date.month, date.day);
              String? imgPath = _dailyCoverImages[dateKey];
              // 💡 修复重点 2：选中状态下没图也交还给插件原生渲染
              if (imgPath == null) return null;
              return _buildCell(date, imgPath, isSelected: true);
            },
            todayBuilder: (context, date, focusedDay) {
              DateTime dateKey = DateTime(date.year, date.month, date.day);
              String? imgPath = _dailyCoverImages[dateKey];
              // 💡 修复重点 3：今天状态没图同样交还给原生
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
                    // 💡 修复重点 4：加上 mainAxisSize.min，保证内容绝对居中不会被挤出屏幕
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_calendar,
                            size: 48, color: Colors.teal.shade100),
                        const SizedBox(height: 16),
                        Text(_getEmptyPlaceholder(),
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 20),
                        // 💡 把按钮换成最醒目的样式
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
    
    // 💡 视觉魔法：判断是否为特殊状态
    final bool isUnknownDate = dateStr.startsWith('1900-01-01');
    final bool isArchived = (diary['is_archived'] as int? ?? 0) == 1;
    // 归档后的日记，时间轴线条和数字都会变成灰色
    final Color lineColor = isArchived ? Colors.grey.shade400 : Theme.of(context).primaryColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.only(top: 25, left: 12),
              // 💡 特效 1：如果日期不可考，左侧变成沙漏
              child: isUnknownDate 
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(Icons.hourglass_empty, color: Colors.brown, size: 24),
                      SizedBox(height: 4),
                      Text("岁月深处", style: TextStyle(fontSize: 10, color: Colors.brown)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${date.day}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: lineColor)),
                      Text("${date.month}月", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('HH:mm').format(date), style: TextStyle(fontSize: 10, color: lineColor, fontWeight: FontWeight.w300)),
                    ],
                  ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VerticalDivider(color: lineColor.withOpacity(0.3), thickness: 2),
                Positioned(
                    top: 32,
                    child: Container(
                        height: 12, width: 12,
                        decoration: BoxDecoration(
                            color: isArchived ? Colors.grey.shade200 : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: lineColor, width: 2),
                            boxShadow: [BoxShadow(color: lineColor.withOpacity(0.2), blurRadius: 4)]))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
              child: DiaryCard(
                diary: diary,
                onRefresh: () => widget.refreshTrigger.value++,
                isSelectionMode: widget.isSelectionMode,
                isSelected: widget.selectedIds.contains(id),
                onSelected: (selected) => widget.onSelectionChanged(id, selected),
                onLongPress: () => widget.onEnterSelectionMode(id),
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
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              _buildOnThisDayBanner(),
              ...allDiaries.asMap().entries.map((entry) {
                int index = entry.key;
                return _buildTimelineItem(
                    entry.value, index == 0, index == allDiaries.length - 1);
              }),
            ],
          ),
        ),
      ],
    );
  }
}
// ================= 新增：全局丝滑路由切换工具 =================
Route createSmoothRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: ScaleTransition(
          // 从 0.95 微微放大到 1.0，非常高级的推入感
          scale: animation.drive(Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic))),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
  );
}
