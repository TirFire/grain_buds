import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';
import 'dart:ui';
import '../core/database_helper.dart';
import '../core/constants.dart';
import '../core/custom_markdown.dart';
import 'diary_share_page.dart';
import '../widgets/full_screen_gallery.dart';

class RetrospectPage extends StatefulWidget {
  const RetrospectPage({super.key});

  @override
  State<RetrospectPage> createState() => _RetrospectPageState();
}

class _RetrospectPageState extends State<RetrospectPage> {
  List<Map<String, dynamic>> _diaries = [];
  bool _isLoading = true;
  int _filterType = -1; 
  final PageController _pageController = PageController(viewportFraction: 0.88);

  @override
  void initState() {
    super.initState();
    _loadAndShuffleDiaries();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAndShuffleDiaries() async {
    setState(() => _isLoading = true);
    final allDiaries = await DatabaseHelper.instance.getAllDiaries();
    
    List<Map<String, dynamic>> filtered = allDiaries.where((d) => 
      (d['is_locked'] as int? ?? 0) == 0 && 
      (d['is_archived'] as int? ?? 0) == 0
    ).toList();

    if (_filterType != -1) {
      filtered = filtered.where((d) => (d['type'] as int? ?? 0) == _filterType).toList();
    }
    
    setState(() {
      _diaries = filtered;
      _diaries.shuffle();
      _isLoading = false;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  // 💡 优化：极简风格筛选栏
  Widget _buildFilterBar() {
    return Padding(
      // 进一步压缩上下间距
      padding: const EdgeInsets.only(top: 8, bottom: 0), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _filterChip("全部", -1),
          const SizedBox(width: 8),
          _filterChip("日记", 0),
          const SizedBox(width: 8),
          _filterChip("随手记", 1),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int type) {
    bool isSelected = _filterType == type;
    final themeColor = Theme.of(context).primaryColor;
    
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black54,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12, // 💡 字体由 13 缩小至 12
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected && _filterType != type) {
          setState(() => _filterType = type);
          _loadAndShuffleDiaries();
        }
      },
      // 💡 核心优化：使用紧凑布局和收缩点击区域
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4), 
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, 
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      
      selectedColor: themeColor,
      backgroundColor: Colors.white,
      elevation: 0, 
      pressElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade200),
    );
  }

  List<String> _parseSafeList(dynamic input) {
    if (input == null) return [];
    String str = input.toString().trim();
    if (str.isEmpty) return [];
    try {
      var decoded = jsonDecode(str);
      if (decoded is List) return decoded.where((e) => e != null).map((e) => e.toString()).toList();
      if (decoded is String) return [decoded];
    } catch (_) {
      if (!str.startsWith('[')) return [str];
    }
    return [];
  }

  Widget _buildDiaryCard(Map<String, dynamic> diary, double scale) {
    final titleStr = diary['title'] as String? ?? '无标题';
    final contentStr = diary['content'] as String? ?? '';
    final dateStr = diary['date'] as String? ?? '';
    final weather = AppConstants.getWeatherEmoji(diary['weather'] as String?);
    final mood = AppConstants.getMoodEmoji(diary['mood'] as String?);
    final images = _parseSafeList(diary['image_path'] ?? diary['imagePath']);

    String formattedDate = dateStr;
    try {
      if (dateStr.isNotEmpty) {
        DateTime date = DateTime.parse(dateStr);
        formattedDate = DateFormat('yyyy年MM月dd日  EEEE', 'zh_CN').format(date);
      }
    } catch (_) {}

    return Transform.scale(
      scale: scale,
      child: Card(
        elevation: 6,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // 💡 调整边距，让卡片利用更多空间
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), 
        color: Theme.of(context).cardColor,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.03),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        formattedDate,
                        style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Text("$weather $mood", style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  primary: false, 
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleStr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4)),
                      const SizedBox(height: 16),
                      MarkdownBody(
                        data: contentStr.split('\n').join('\n\n'),
                        selectable: false,
                        extensionSet: md.ExtensionSet.gitHubFlavored,
                        inlineSyntaxes: [ColorTextSyntax(), OldColorTextSyntax(), HighlightTextSyntax()],
                        builders: {'colortext': ColorTextBuilder(), 'highlighttext': HighlightTextBuilder()},
                        styleSheet: MarkdownStyleSheet(
                          pPadding: EdgeInsets.zero,
                          blockSpacing: 4,
                          p: const TextStyle(fontSize: 15, height: 1.7, color: Colors.black87),
                        ),
                        imageBuilder: (uri, title, alt) {
                          final path = uri.toString();
                          if (path.startsWith('http')) return Image.network(path);
                          if (path.startsWith('assets')) return Image.asset(path);
                          return Image.file(File(path));
                        },
                      ),
                      if (images.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: images.asMap().entries.map((entry) {
                            return GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenGallery(images: images, initialIndex: entry.key))),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(File(entry.value), width: 75, height: 75, fit: BoxFit.cover),
                              ),
                            );
                          }).toList(),
                        )
                      ]
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => DiarySharePage(diary: diary, decryptedContent: contentStr)
                        ));
                      },
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text("生成长图", style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), 
      appBar: AppBar(
        title: const Text("时光回溯", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        // 💡 缩小 AppBar 高度
        toolbarHeight: 45, 
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _diaries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _filterType == -1 ? "还没有日记哦" : "暂无相关回忆", 
                              style: const TextStyle(color: Colors.grey, fontSize: 14)
                            ),
                          ],
                        ))
                    : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: { PointerDeviceKind.touch, PointerDeviceKind.mouse },
                        ),
                        child: PageView.builder(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _diaries.length,
                          itemBuilder: (context, index) {
                            return AnimatedBuilder(
                              animation: _pageController,
                              builder: (context, child) {
                                double value = 1.0;
                                if (_pageController.position.haveDimensions) {
                                  value = _pageController.page! - index;
                                  value = (1 - (value.abs() * 0.12)).clamp(0.88, 1.0);
                                }
                                return _buildDiaryCard(_diaries[index], value);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}