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
import 'tags_page.dart'; 

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

  Future<void> _batchExport(String format) async {
    if (_selectedIds.isEmpty) return;
    
    String timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    FileSaveLocation? result;

    if (format == 'pdf') { result = await getSaveLocation(suggestedName: '批量合并日记_$timeStamp.pdf'); } 
    else if (format == 'pdf_zip') { result = await getSaveLocation(suggestedName: '批量独立PDF_$timeStamp.zip'); } 
    else { result = await getSaveLocation(suggestedName: '批量导出日记_$timeStamp.zip'); }

    if (result == null) return;

    bool isDialogShowing = true;
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (dialogContext) => AlertDialog(
        content: const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.teal), SizedBox(height: 15), Text("正在飞速打包中，请稍候...", style: TextStyle(fontWeight: FontWeight.bold))]),
        actions: [TextButton(onPressed: () { isDialogShowing = false; Navigator.pop(dialogContext); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("📦 已转入后台导出，您可以继续使用软件。完成后将通知您！"))); }, child: const Text("转后台运行", style: TextStyle(color: Colors.grey)))],
      ),
    ).then((_) => isDialogShowing = false);

    try {
      final allDiaries = await DatabaseHelper.instance.getAllDiaries();
      final selectedDiaries = allDiaries.where((d) => _selectedIds.contains(d['id'])).toList();

      if (format == 'pdf') {
        final font = await PdfGoogleFonts.notoSansSCRegular();
        final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font));

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String date = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          pdf.addPage(pw.MultiPage(build: (pw.Context context) => [pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))), pw.Text("记录时间: $date", style: const pw.TextStyle(color: PdfColors.grey)), pw.SizedBox(height: 15), pw.Text(content, style: const pw.TextStyle(fontSize: 14, lineSpacing: 5)), pw.SizedBox(height: 30), pw.Divider()]));
        }
        final file = File(result.path);
        await file.writeAsBytes(await pdf.save());
      } 
      else if (format == 'pdf_zip') {
        final archive = Archive();
        final font = await PdfGoogleFonts.notoSansSCRegular(); 

        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法导出明文】" : (d['content'] ?? '');
          final singlePdf = pw.Document(theme: pw.ThemeData.withFont(base: font));
          singlePdf.addPage(pw.MultiPage(build: (pw.Context context) => [pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))), pw.Text("记录时间: $dateStr", style: const pw.TextStyle(color: PdfColors.grey)), pw.SizedBox(height: 15), pw.Text(content, style: const pw.TextStyle(fontSize: 14, lineSpacing: 5))]));
          List<int> pdfBytes = await singlePdf.save();
          archive.addFile(ArchiveFile('${dateStr.length >= 10 ? dateStr.substring(0,10) : '未知日期'}_$safeTitle.pdf', pdfBytes.length, pdfBytes));
        }
        final zipData = ZipEncoder().encode(archive);
        if (zipData != null) await File(result.path).writeAsBytes(zipData);
      }
      else {
        final archive = Archive();
        for (var d in selectedDiaries) {
          String title = d['title'] ?? '无标题';
          String safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          String dateStr = d['date'] ?? '';
          String content = d['is_locked'] == 1 ? "【此日记已加密，无法批量导出明文】" : (d['content'] ?? '');
          String outputContent = "";
          if (format == 'md') { outputContent = "# $title\n\n**记录时间:** $dateStr\n\n---\n\n$content"; } else if (format == 'txt') { outputContent = "标题: $title\n时间: $dateStr\n\n$content"; } else if (format == 'doc') { outputContent = "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\" xmlns=\"http://www.w3.org/TR/REC-html40\"><head><meta charset=\"utf-8\"><title>$title</title></head><body style=\"font-family: 'Microsoft YaHei', sans-serif;\"><h1 style=\"text-align: center;\">$title</h1><p style=\"color: gray; text-align: center;\">记录时间: $dateStr</p><hr><div style=\"white-space: pre-wrap; line-height: 1.6; font-size: 12pt;\">$content</div></body></html>"; }
          List<int> bytes = utf8.encode(outputContent);
          archive.addFile(ArchiveFile('${dateStr.length >= 10 ? dateStr.substring(0,10) : '未知日期'}_$safeTitle.$format', bytes.length, bytes));
        }
        final zipData = ZipEncoder().encode(archive);
        if (zipData != null) await File(result.path).writeAsBytes(zipData);
      }

      if (mounted) {
        if (isDialogShowing) Navigator.pop(context); 
        setState(() { _isSelectionMode = false; _selectedIds.clear(); }); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎉 批量导出成功！"), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        if (isDialogShowing) Navigator.pop(context);
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
              Padding(padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 12.0, bottom: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("已选中 ${_selectedIds.length} 篇，请选择导出格式", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(c))])),
              ListTile(leading: const Icon(Icons.picture_as_pdf, color: Colors.red), title: const Text("合并为一份 PDF 文档"), subtitle: const Text("将所有选中的日记首尾相连成册"), onTap: () { Navigator.pop(c); _batchExport('pdf'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.redAccent), title: const Text("打包成独立的 PDF 压缩包"), subtitle: const Text("每篇日记分别生成独立的高清 .pdf"), onTap: () { Navigator.pop(c); _batchExport('pdf_zip'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.blueGrey), title: const Text("打包成 Markdown 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .md 文件"), onTap: () { Navigator.pop(c); _batchExport('md'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.grey), title: const Text("打包成 TXT 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .txt 文件"), onTap: () { Navigator.pop(c); _batchExport('txt'); }),
              ListTile(leading: const Icon(Icons.folder_zip, color: Colors.blue), title: const Text("打包成 Word 压缩包 (.zip)"), subtitle: const Text("每篇日记生成独立的 .doc 文件"), onTap: () { Navigator.pop(c); _batchExport('doc'); }),
              const Divider(),
              ListTile(leading: const Icon(Icons.cancel_outlined, color: Colors.grey), title: const Text("取消导出", style: TextStyle(color: Colors.grey)), onTap: () => Navigator.pop(c)),
              const SizedBox(height: 10), 
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
        leading: _isSelectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { _isSelectionMode = false; _selectedIds.clear(); }); })
            : null,
            
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: '搜索日记...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
                onChanged: (val) { _searchKeyword = val; _performSearch(val); },
              )
            : Text(
                _isSelectionMode ? '已选中 ${_selectedIds.length} 篇' : 'GrainBuds-小满日记', 
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontFamily: !_isSelectionMode ? 'Georgia' : null, letterSpacing: !_isSelectionMode ? 1.5 : null)
              ),
        backgroundColor: _isSelectionMode ? Colors.blueGrey : Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isSelectionMode)
            IconButton(icon: const Icon(Icons.ios_share), tooltip: '批量导出', onPressed: _showBatchExportMenu)
          else ...[
            IconButton(icon: Icon(_isSearching ? Icons.close : Icons.search), onPressed: () { setState(() { _isSearching = !_isSearching; if (!_isSearching) { _searchKeyword = ""; _searchResults.clear(); } }); }),
            IconButton(icon: const Icon(Icons.sell_outlined), tooltip: '标签墙', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TagsPage()))),
            IconButton(icon: const Icon(Icons.bar_chart), tooltip: '统计报表', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsPage()))),
            IconButton(icon: const Icon(Icons.settings), tooltip: '设置', onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage())); _refreshTrigger.value++; }),
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
                  isSelectionMode: _isSelectionMode, selectedIds: _selectedIds, isDescending: _isDescending, 
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
    try { return List<String>.from(jsonDecode(imgData)); } catch (_) { return []; }
  }

  void _extractCoverImages(List<Map<String, dynamic>> allDiariesData) {
    Map<DateTime, String> covers = {};
    Map<DateTime, List<Map<String, dynamic>>> grouped = {};
    
    for (var d in allDiariesData) {
      DateTime parsedDate = DateTime.parse(d['date']);
      DateTime dateKey = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      grouped.putIfAbsent(dateKey, () => []).add(d);
    }

    for (var entry in grouped.entries) {
      DateTime dateKey = entry.key;
      List<Map<String, dynamic>> dailyDocs = entry.value;
      String? bestImg;

      for (var doc in dailyDocs.where((e) => e['type'] == 0)) {
        List<String> imgs = _parseImages(doc['imagePath']);
        if (imgs.isNotEmpty) { bestImg = imgs.first; break; }
      }

      if (bestImg == null) {
        for (var doc in dailyDocs.where((e) => e['type'] == 1)) {
          List<String> imgs = _parseImages(doc['imagePath']);
          if (imgs.isNotEmpty) { bestImg = imgs.first; break; }
        }
      }

      if (bestImg != null) { covers[dateKey] = bestImg; }
    }
    setState(() { _dailyCoverImages = covers; });
  }

  Future<void> _fetchData() async {
    final data = await DatabaseHelper.instance.getDiariesByDate(_selectedDay);
    final allData = await DatabaseHelper.instance.getAllDiaries();
    
    if (mounted) {
      _extractCoverImages(allData); 
      setState(() { diaries = data; }); 
    }
  }

  // 💡 保证绝对居中，且只用于有图片的日期
  Widget _buildCell(DateTime date, String imgPath, {bool isSelected = false, bool isToday = false}) {
    return Container(
      margin: const EdgeInsets.all(4.0),
      alignment: Alignment.center, 
      decoration: isSelected 
          ? BoxDecoration(border: Border.all(color: Colors.teal, width: 3), shape: BoxShape.circle)
          : (isToday ? BoxDecoration(border: Border.all(color: Colors.teal, width: 2), shape: BoxShape.circle) : null),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              File(imgPath), width: 36, height: 36, fit: BoxFit.cover,
              errorBuilder: (c, o, s) => const Icon(Icons.broken_image, size: 10, color: Colors.grey),
            ),
          ),
          Text(
            '${date.day}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4), Shadow(color: Colors.black87, blurRadius: 4), Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }

  String _getEmptyPlaceholder() {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '这一天没有留下印记';
    if (sDay.isAfter(today)) return '未来的这一天还是未知的';
    return '今天还没有记录哦';
  }

  String _getWriteLabel() {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '补写这天的回忆';
    if (sDay.isAfter(today)) return '写给这天的期许';
    return '开始记录这一天';
  }

  String _getAddMoreLabel() {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return '再补写一篇这天的回忆';
    if (sDay.isAfter(today)) return '再写一篇给这天的期许';
    return '再记录一篇';
  }

  IconData _getWriteIcon() {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    if (sDay.isBefore(today)) return Icons.history_edu;
    if (sDay.isAfter(today)) return Icons.flight_takeoff;
    return Icons.edit;
  }

  void _openMemoryEditorDialog(BuildContext context) {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime sDay = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    
    bool isPast = sDay.isBefore(today);
    bool isFuture = sDay.isAfter(today);
    
    String titlePrefix = isPast ? '补写回忆' : (isFuture ? '未来期许' : '记录');
    String dateStr = '${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2,'0')}-${_selectedDay.day.toString().padLeft(2,'0')}';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(backgroundColor: Colors.teal, child: Icon(isPast ? Icons.history_edu : Icons.book, color: Colors.white)),
              title: Text('$titlePrefix日记'),
              subtitle: Text('日期将被锚定在 $dateStr'),
              onTap: () async {
                Navigator.pop(c);
                final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => DiaryEditPage(entryType: 0, selectedDate: _selectedDay)));
                if (result == true) widget.refreshTrigger.value++;
              },
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: Colors.green.shade500, child: const Icon(Icons.bolt, color: Colors.white)),
              title: Text('$titlePrefix随手记'),
              subtitle: const Text('快速记录闪念或待办'),
              onTap: () async {
                Navigator.pop(c);
                final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => DiaryEditPage(entryType: 1, selectedDate: _selectedDay)));
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
          onDaySelected: (sDay, fDay) { setState(() { _selectedDay = sDay; _focusedDay = fDay; }); _fetchData(); },
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
                    Icon(Icons.edit_calendar, size: 48, color: Colors.teal.shade100),
                    const SizedBox(height: 16),
                    Text(_getEmptyPlaceholder(), style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 20),
                    // 💡 把按钮换成最醒目的样式
                    ElevatedButton.icon(
                      icon: Icon(_getWriteIcon()),
                      label: Text(_getWriteLabel(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade50, foregroundColor: Colors.teal, elevation: 0),
                          onPressed: () => _openMemoryEditorDialog(context),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), 
                    child: DiaryCard(diary: diaries[i], onRefresh: () => widget.refreshTrigger.value++)
                  );
                }
              )
        ),
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
    Widget filterBar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(label: const Text('全部'), selected: _filterType == -1, selectedColor: Colors.teal.shade100, onSelected: (v) { setState(() => _filterType = -1); _fetchAll(); }),
          const SizedBox(width: 10),
          FilterChip(label: const Text('日记'), selected: _filterType == 0, selectedColor: Colors.teal.shade100, onSelected: (v) { setState(() => _filterType = 0); _fetchAll(); }),
          const SizedBox(width: 10),
          FilterChip(label: const Text('随手记'), selected: _filterType == 1, selectedColor: Colors.green.shade100, onSelected: (v) { setState(() => _filterType = 1); _fetchAll(); }),
        ],
      ),
    );

    if (allDiaries.isEmpty && _filterType == -1) {
      return Column(children: [filterBar, const Expanded(child: Center(child: Text('时间轴空空如也，快去记录吧！', style: TextStyle(color: Colors.grey))))]);
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
                return _buildTimelineItem(entry.value, index == 0, index == allDiaries.length - 1);
              }),
            ],
          ),
        ),
      ],
    );
  }
}