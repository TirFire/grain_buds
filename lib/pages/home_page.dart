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

import '../core/database_helper.dart'; 
import '../widgets/diary_card.dart';
import 'edit_page.dart';
import 'settings_page.dart';
import 'stats_page.dart'; 
import 'tags_page.dart'; // 💡 新增：引入标签墙页面

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _isSearching = false;
  String _searchKeyword = "";
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSelectionMode = false;
  Set<int> _selectedIds = {};
  bool _isDescending = true;
  final ValueNotifier<int> _refreshTrigger = ValueNotifier(0);

  Future<void> _performSearch(String keyword) async {
    if (keyword.isEmpty) { setState(() { _searchResults = []; }); return; }
    final results = await DatabaseHelper.instance.searchDiaries(keyword);
    setState(() { _searchResults = results; });
  }

  // ================= 💡 批量导出引擎 (防卡死 & 支持后台运行) =================
  Future<void> _batchExport(String format) async {
    if (_selectedIds.isEmpty) return;
    
    // 1️⃣ 第一步：先唤起系统文件选择器（不在此时弹 Loading，彻底避免和系统窗口冲突）
    String timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    FileSaveLocation? result;

    if (format == 'pdf') {
      result = await getSaveLocation(suggestedName: '批量合并日记_$timeStamp.pdf');
    } else if (format == 'pdf_zip') {
      result = await getSaveLocation(suggestedName: '批量独立PDF_$timeStamp.zip');
    } else {
      result = await getSaveLocation(suggestedName: '批量导出日记_$timeStamp.zip');
    }

    // 💡 保护机制：如果用户在选择保存路径时点了“取消”或直接关了窗口，直接安静退出！
    if (result == null) return;

    // 2️⃣ 第二步：用户确认了保存路径，开始显示 Loading 进度框
    // 增加一个标志位，用来判断 Loading 框是否还显示在屏幕上
    bool isDialogShowing = true;
    showDialog(
      context: context, 
      barrierDismissible: false, // 禁止点击外部关闭，防止误触
      builder: (dialogContext) => AlertDialog(
        content: const Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            CircularProgressIndicator(color: Colors.teal), 
            SizedBox(height: 15), 
            Text("正在飞速打包中，请稍候...", style: TextStyle(fontWeight: FontWeight.bold))
          ]
        ),
        actions: [
          // 💡 核心升级：后台运行按钮
          TextButton(
            onPressed: () {
              isDialogShowing = false;
              Navigator.pop(dialogContext); // 关掉 Loading 框
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("📦 已转入后台导出，您可以继续使用软件。完成后将通知您！"))
              );
            }, 
            child: const Text("转后台运行", style: TextStyle(color: Colors.grey))
          )
        ],
      ),
    ).then((_) => isDialogShowing = false);

    // 3️⃣ 第三步：开始处理繁重的导出任务
    try {
      final allDiaries = await DatabaseHelper.instance.getAllDiaries();
      final selectedDiaries = allDiaries.where((d) => _selectedIds.contains(d['id'])).toList();

      // 👉 策略 1：如果是 PDF 合并
      if (format == 'pdf') {
        final font = await PdfGoogleFonts.notoSansSCRegular();
        final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String date = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          
          pdf.addPage(
            pw.MultiPage(
              build: (pw.Context context) => [
                pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
                pw.Text("记录时间: $date", style: const pw.TextStyle(color: PdfColors.grey)),
                pw.SizedBox(height: 15),
                pw.Text(content, style: const pw.TextStyle(fontSize: 14, lineSpacing: 5)),
                pw.SizedBox(height: 30),
                pw.Divider(),
              ],
            ),
          );
        }
        final file = File(result.path);
        await file.writeAsBytes(await pdf.save());
      } 
      // 👉 策略 2：打包独立的 PDF 到 ZIP 里
      else if (format == 'pdf_zip') {
        final archive = Archive();
        final font = await PdfGoogleFonts.notoSansSCRegular(); 

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法导出明文】" : (d['content'] ?? '');
          
          final singlePdf = pw.Document(theme: pw.ThemeData.withFont(base: font));
          singlePdf.addPage(
            pw.MultiPage(
              build: (pw.Context context) => [
                pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
                pw.Text("记录时间: $dateStr", style: const pw.TextStyle(color: PdfColors.grey)),
                pw.SizedBox(height: 15),
                pw.Text(content, style: const pw.TextStyle(fontSize: 14, lineSpacing: 5)),
              ],
            ),
          );
          
          List<int> pdfBytes = await singlePdf.save();
          archive.addFile(ArchiveFile('${dateStr.length >= 10 ? dateStr.substring(0,10) : '未知日期'}_$safeTitle.pdf', pdfBytes.length, pdfBytes));
        }
        
        final zipData = ZipEncoder().encode(archive);
        if (zipData != null) {
          final file = File(result.path);
          await file.writeAsBytes(zipData);
        }
      }
      // 👉 策略 3：普通的 MD/TXT/DOC 压缩包
      else {
        final archive = Archive();
        
        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          
          String outputContent = "";
          if (format == 'md') {
            outputContent = "# $title\n\n**记录时间:** $dateStr\n\n---\n\n$content";
          } else if (format == 'txt') {
            outputContent = "标题: $title\n时间: $dateStr\n\n$content";
          } else if (format == 'doc') {
            outputContent = "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\" xmlns=\"http://www.w3.org/TR/REC-html40\"><head><meta charset=\"utf-8\"><title>$title</title></head><body style=\"font-family: 'Microsoft YaHei', sans-serif;\"><h1 style=\"text-align: center;\">$title</h1><p style=\"color: gray; text-align: center;\">记录时间: $dateStr</p><hr><div style=\"white-space: pre-wrap; line-height: 1.6; font-size: 12pt;\">$content</div></body></html>";
          }
          
          List<int> bytes = utf8.encode(outputContent);
          archive.addFile(ArchiveFile('${dateStr.length >= 10 ? dateStr.substring(0,10) : '未知日期'}_$safeTitle.$format', bytes.length, bytes));
        }
        
        final zipData = ZipEncoder().encode(archive);
        if (zipData != null) {
          final file = File(result.path);
          await file.writeAsBytes(zipData);
        }
      }

      // 4️⃣ 导出完成后的扫尾工作
      if (mounted) {
        if (isDialogShowing) {
          Navigator.pop(context); // 如果 Loading 框还在，就关掉它
        }
        setState(() { _isSelectionMode = false; _selectedIds.clear(); }); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎉 批量导出成功！"), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        if (isDialogShowing) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("批量导出失败: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showBatchExportMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 💡 修复 1：把原本纯文本的标题改成了一行（Row），右边加上了关闭 (X) 按钮
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 12.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("已选中 ${_selectedIds.length} 篇，请选择导出格式", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(c), // 点击 X 直接关闭菜单
                    ),
                  ],
                ),
              ),
              
              ListTile(leading: const Icon(Icons.picture_as_pdf, color: Colors.red), title: const Text("合并为一份 PDF 文档"), subtitle: const Text("将所有选中的日记首尾相连成册"), onTap: () { Navigator.pop(c); _batchExport('pdf'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.redAccent), title: const Text("打包成独立的 PDF 压缩包"), subtitle: const Text("每篇日记分别生成独立的高清 .pdf"), onTap: () { Navigator.pop(c); _batchExport('pdf_zip'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.blueGrey), title: const Text("打包成 Markdown 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .md 文件"), onTap: () { Navigator.pop(c); _batchExport('md'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.grey), title: const Text("打包成 TXT 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .txt 文件"), onTap: () { Navigator.pop(c); _batchExport('txt'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.blue), title: const Text("打包成 Word 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .doc 文件"), onTap: () { Navigator.pop(c); _batchExport('doc'); }),
              
              // 💡 修复 2：在菜单最底部加一个明确的“取消”选项，防止误触
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.grey), 
                title: const Text("取消导出", style: TextStyle(color: Colors.grey)), 
                onTap: () => Navigator.pop(c), // 点击取消关闭菜单
              ),
              const SizedBox(height: 10), // 底部留白，适配没有全面屏手势的手机/电脑
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 💡 核心修复：多选模式下，在左上角显示一个“X”按钮来退出
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedIds.clear();
                  });
                },
              )
            : null, // 普通模式下保持默认
            
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '搜索日记...', 
                  hintStyle: TextStyle(color: Colors.white70), 
                  border: InputBorder.none
                ),
                onChanged: (val) { _searchKeyword = val; _performSearch(val); },
              )
            : Text(
                _isSelectionMode ? '已选中 ${_selectedIds.length} 篇' : 'GrainBuds', 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: Colors.white,
                  fontFamily: !_isSelectionMode ? 'Georgia' : null, 
                  letterSpacing: !_isSelectionMode ? 1.5 : null,
                )
              ),
        backgroundColor: _isSelectionMode ? Colors.blueGrey : Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 多选模式下的右上角按钮
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '批量导出',
              onPressed: _showBatchExportMenu,
            )
          // 普通模式下的右上角按钮组
          else ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchKeyword = "";
                    _searchResults.clear();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.sell_outlined), // 标签图标
              tooltip: '标签墙',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TagsPage())),
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: '统计报表',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsPage())),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
                _refreshTrigger.value++; 
              },
            ),
          ]
        ],
      ),
      body: _isSearching
          ? ListView.builder(itemCount: _searchResults.length, itemBuilder: (c, i) => DiaryCard(diary: _searchResults[i], onRefresh: () => _performSearch(_searchKeyword)))
          : IndexedStack(
              index: _currentIndex,
              children: [
                CalendarTab(refreshTrigger: _refreshTrigger),
                TimelineTab(
                  refreshTrigger: _refreshTrigger, 
                  isSelectionMode: _isSelectionMode, selectedIds: _selectedIds,
                  isDescending: _isDescending, 
                  onSelectionChanged: (id, selected) { setState(() { if (selected) _selectedIds.add(id); else _selectedIds.remove(id); }); },
                  onEnterSelectionMode: (startId) { setState(() { _isSelectionMode = true; _selectedIds.add(startId); }); },
                ),
              ],
            ),
      bottomNavigationBar: _isSearching || _isSelectionMode ? null : BottomNavigationBar(
        currentIndex: _currentIndex, onTap: (index) => setState(() => _currentIndex = index), selectedItemColor: Colors.teal,
        items: const [BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '日历'), BottomNavigationBarItem(icon: Icon(Icons.timeline), label: '时间轴')],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: () {
          // 💡 点击加号时弹出选择底栏
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (c) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.book, color: Colors.white)),
                    title: const Text('写日记'),
                    subtitle: const Text('记录今天的故事和感悟'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const DiaryEditPage(entryType: 0)));
                      if (result == true) _refreshTrigger.value++;
                    },
                  ),
                  ListTile(
                    // 💡 这里换成了绿色
                    leading: CircleAvatar(backgroundColor: Colors.green.shade500, child: const Icon(Icons.bolt, color: Colors.white)),
                    title: const Text('随手记'),
                    subtitle: const Text('快速记录闪念、灵感或待办'),
                    onTap: () async {
                      Navigator.pop(c);
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const DiaryEditPage(entryType: 1)));
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
  @override
  void initState() { super.initState(); _fetchData(); widget.refreshTrigger.addListener(_fetchData); }
  @override
  void dispose() { widget.refreshTrigger.removeListener(_fetchData); super.dispose(); }
  Future<void> _fetchData() async {
    final data = await DatabaseHelper.instance.getDiariesByDate(_selectedDay);
    if (mounted) setState(() { diaries = data; });
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar(firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, selectedDayPredicate: (day) => isSameDay(_selectedDay, day), onDaySelected: (sDay, fDay) { setState(() { _selectedDay = sDay; _focusedDay = fDay; }); _fetchData(); }),
        const Divider(),
        Expanded(child: ListView.builder(itemCount: diaries.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: DiaryCard(diary: diaries[i], onRefresh: () => widget.refreshTrigger.value++)))),
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

  const TimelineTab({super.key, required this.refreshTrigger, required this.isSelectionMode, required this.selectedIds, required this.isDescending, required this.onSelectionChanged, required this.onEnterSelectionMode});
  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  List<Map<String, dynamic>> allDiaries = [];
  List<Map<String, dynamic>> onThisDayDiaries = []; 
  int _filterType = -1;

  @override
  void initState() { super.initState(); _fetchAll(); widget.refreshTrigger.addListener(_fetchAll); }
  @override
  void dispose() { widget.refreshTrigger.removeListener(_fetchAll); super.dispose(); }
  
  Future<void> _fetchAll() async {
    List<Map<String, dynamic>> rawData = await DatabaseHelper.instance.getAllDiaries();
    
    // 💡 按照筛选类型过滤数据
    List<Map<String, dynamic>> data = [];
    if (_filterType == -1) {
      data = rawData;
    } else {
      data = rawData.where((d) => (d['type'] as int? ?? 0) == _filterType).toList();
    }

    if (!widget.isDescending) data = data.reversed.toList();

    DateTime today = DateTime.now();
    List<Map<String, dynamic>> historical = [];
    for (var d in data) {
      DateTime diaryDate = DateTime.parse(d['date'] as String);
      if (diaryDate.month == today.month && diaryDate.day == today.day && diaryDate.year < today.year) {
        historical.add(d);
      }
    }

    if (mounted) {
      setState(() { allDiaries = data; onThisDayDiaries = historical; });
    }
  }

  Widget _buildOnThisDayBanner() {
    if (onThisDayDiaries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.orange.shade200, Colors.orange.shade50]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [Icon(Icons.history, color: Colors.deepOrange), SizedBox(width: 8), Text("历史上的今天", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 18))]),
          const SizedBox(height: 10),
          ...onThisDayDiaries.map((diary) {
            final int yearsAgo = DateTime.now().year - DateTime.parse(diary['date'] as String).year;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text("🕰️ $yearsAgo年前的今天: ${(diary['title'] as String?) ?? '无标题'}", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> diary, bool isFirst, bool isLast) {
    final int id = diary['id'] as int;
    final DateTime date = DateTime.parse(diary['date'] as String);
    
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 70, 
            child: Padding(
              padding: const EdgeInsets.only(top: 25, left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${date.day}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
                  Text("${date.month}月", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(DateFormat('HH:mm').format(date), style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.w300)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VerticalDivider(color: Colors.teal.withOpacity(0.3), thickness: 2),
                Positioned(top: 32, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.teal, width: 2), boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.2), blurRadius: 4)]))),
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
    // 把顶部的筛选按钮构建成一个组件
    Widget filterBar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _filterType == -1,
            selectedColor: Colors.teal.shade100,
            onSelected: (v) { setState(() => _filterType = -1); _fetchAll(); },
          ),
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('日记'),
            selected: _filterType == 0,
            selectedColor: Colors.teal.shade100,
            onSelected: (v) { setState(() => _filterType = 0); _fetchAll(); },
          ),
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('随手记'),
            selected: _filterType == 1,
            // 💡 换成浅绿色背景，和卡片上的图标呼应
            selectedColor: Colors.green.shade100, 
            onSelected: (v) { setState(() => _filterType = 1); _fetchAll(); },
          ),
        ],
      ),
    );

    if (allDiaries.isEmpty && _filterType == -1) {
      return Column(children: [filterBar, const Expanded(child: Center(child: Text('时间轴空空如也，快去记录吧！', style: TextStyle(color: Colors.grey))))]);
    }
    
    return Column(
      children: [
        filterBar, // 💡 在列表最顶部插入筛选栏
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              _buildOnThisDayBanner(), 
              ...allDiaries.asMap().entries.map((entry) {
                int index = entry.key;
                return _buildTimelineItem(entry.value, index == 0, index == allDiaries.length - 1);
              }),
            ],
          ),
        ),
      ],
    );
  }
}