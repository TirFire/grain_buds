import 'package:flutter/material.dart';
import '../core/database_helper.dart';
import '../widgets/diary_card.dart';

class CollectionPage extends StatefulWidget {
  final String type; // 接收 'starred' 或 'archived'
  const CollectionPage({super.key, required this.type});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List<Map<String, dynamic>> _diaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    List<Map<String, dynamic>> data = [];
    if (widget.type == 'starred') {
      data = await DatabaseHelper.instance.getStarredDiaries();
    } else if (widget.type == 'archived') {
      data = await DatabaseHelper.instance.getArchivedDiaries();
    }
    
    if (mounted) {
      setState(() {
        _diaries = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStar = widget.type == 'starred';
    final themeColor = Theme.of(context).primaryColor;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isStar ? '星标日记' : '归档记录'),
        backgroundColor: isStar ? Colors.amber.shade700 : Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : _diaries.isEmpty
              ? Center(child: Text(isStar ? '暂无星标日记' : '暂无归档日记', style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 40),
                  itemCount: _diaries.length,
                  itemBuilder: (context, index) {
                    return DiaryCard(
                      diary: _diaries[index],
                      onRefresh: _loadData, // 💡 操作后自动刷新列表
                    );
                  },
                ),
    );
  }
}