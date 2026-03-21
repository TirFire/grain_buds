import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database_helper.dart';
import '../widgets/diary_card.dart';

// ================= 1. 标签聚合墙 =================
class TagsPage extends StatefulWidget {
  const TagsPage({super.key});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  bool _isLoading = true;
  Map<String, int> _tagCounts = {};

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final diaries = await DatabaseHelper.instance.getAllDiaries();
    Map<String, int> counts = {};
    
    // 遍历所有日记，提取并统计标签频率
    for (var d in diaries) {
      try {
        List<String> tags = List<String>.from(jsonDecode((d['tags'] as String?) ?? '[]'));
        for (var t in tags) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
      } catch (_) {}
    }
    
    // 按照标签使用频率从高到低排序
    var sortedEntries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    if (mounted) {
      setState(() {
        _tagCounts = Map.fromEntries(sortedEntries);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签墙', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tagCounts.isEmpty
              ? const Center(
                  child: Text('暂无标签\n在写日记时添加 #标签 即可在此处聚合', 
                  textAlign: TextAlign.center, 
                  style: TextStyle(color: Colors.grey, height: 1.5)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("共发现 ${_tagCounts.length} 个专属印记", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12, // 水平间距
                        runSpacing: 16, // 垂直间距
                        children: _tagCounts.entries.map((e) {
                          return ActionChip(
                            elevation: 1,
                            backgroundColor: Colors.teal.shade50,
                            side: BorderSide(color: Colors.teal.shade200),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            // 💡 视觉设计：左侧显示标签名，右侧显示小巧的使用次数
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('# ${e.key}', style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.teal.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                  child: Text('${e.value}', style: TextStyle(fontSize: 12, color: Colors.teal.shade900)),
                                )
                              ],
                            ),
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (context) => TagResultPage(tag: e.key)
                              )).then((_) => _loadTags()); // 从结果页返回时，刷新标签墙（防止在结果页删了日记导致数量对不上）
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ================= 2. 标签对应的日记列表页 =================
class TagResultPage extends StatefulWidget {
  final String tag;
  const TagResultPage({super.key, required this.tag});

  @override
  State<TagResultPage> createState() => _TagResultPageState();
}

class _TagResultPageState extends State<TagResultPage> {
  List<Map<String, dynamic>> _diaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiaries();
  }

  Future<void> _loadDiaries() async {
    final allDiaries = await DatabaseHelper.instance.getAllDiaries();
    List<Map<String, dynamic>> filtered = [];
    
    // 筛选出包含当前选中标签的所有日记
    for (var d in allDiaries) {
      try {
        List<String> tags = List<String>.from(jsonDecode((d['tags'] as String?) ?? '[]'));
        if (tags.contains(widget.tag)) {
          filtered.add(d);
        }
      } catch (_) {}
    }
    
    if (mounted) {
      setState(() {
        _diaries = filtered;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('# ${widget.tag} (${_diaries.length} 篇)'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _diaries.isEmpty
              ? const Center(child: Text('没有找到相关记录', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 40),
                  itemCount: _diaries.length,
                  itemBuilder: (context, index) {
                    return DiaryCard(
                      diary: _diaries[index],
                      onRefresh: _loadDiaries, // 若在此页编辑或删除日记，自动刷新列表
                    );
                  },
                ),
    );
  }
}