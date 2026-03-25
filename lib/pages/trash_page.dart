import 'package:flutter/material.dart';
import '../core/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Map<String, dynamic>> trashedDiaries = [];
  bool _isSelectionMode = false;
  Set<int> _selectedIds = {};
  int _autoCleanDays = 30;

  Future<void> _loadAutoCleanSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoCleanDays = prefs.getInt('auto_clean_days') ?? 30; 
    });
  }

  void _showAutoCleanDialog() {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: '关闭',
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: animation.drive(Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.easeOut))),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_delete, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('自动清理设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCleanOption(dialogContext, 7, '7 天后自动彻底删除'),
            _buildCleanOption(dialogContext, 15, '15 天后自动彻底删除'),
            _buildCleanOption(dialogContext, 30, '30 天后自动彻底删除'),
            _buildCleanOption(dialogContext, 90, '90 天后自动彻底删除'),
            _buildCleanOption(dialogContext, 0, '从不自动清理 (需手动)'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关 闭', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  // 💡 新增：对话框里的选项构建器
  Widget _buildCleanOption(BuildContext dialogContext, int days, String label) {
    bool isSelected = _autoCleanDays == days;
    return ListTile(
      title: Text(label, style: TextStyle(fontSize: 15, color: isSelected ? Theme.of(context).primaryColor : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? Icon(Icons.radio_button_checked, color: Theme.of(context).primaryColor) : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : null,
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('auto_clean_days', days);
        setState(() => _autoCleanDays = days);
        if (mounted) {
          Navigator.pop(dialogContext);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已更改为: $label'), backgroundColor: Colors.teal));
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadTrash();
    _loadAutoCleanSetting();
  }

  Future<void> _loadTrash() async {
    final data = await DatabaseHelper.instance.getTrashedDiaries();
    if (mounted) setState(() { trashedDiaries = data; });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _restoreSelected() async {
    for (int id in _selectedIds) {
      await DatabaseHelper.instance.restoreDiary(id);
    }
    _exitSelectionMode();
    _loadTrash();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 选中的日记已恢复！')));
  }

  Future<void> _deleteSelected() async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('批量粉碎警告', style: TextStyle(color: Colors.red)),
        content: Text('即将彻底销毁 ${_selectedIds.length} 篇日记及其包含的图片视频附件。\n\n此操作绝对不可逆！确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              for (int id in _selectedIds) {
                await DatabaseHelper.instance.permanentlyDeleteDiary(id);
              }
              _exitSelectionMode();
              _loadTrash();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🧹 选中的文件已彻底销毁！')));
            },
            child: const Text('全部粉碎', style: TextStyle(color: Colors.red)),
          )
        ],
      )
    );
  }

  void _exitSelectionMode() {
    setState(() { _isSelectionMode = false; _selectedIds.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode 
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode) 
            : null,
        title: Text(_isSelectionMode ? '已选 ${_selectedIds.length} 项' : '回收站'),
        backgroundColor: _isSelectionMode ? Colors.blueGrey : Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () {
                setState(() => _selectedIds = trashedDiaries.map((d) => d['id'] as int).toSet());
              },
            )
          else // 💡 重点补充了这里：如果不处于多选模式，就显示设置齿轮
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '自动清理设置',
              onPressed: _showAutoCleanDialog,
            )
        ],
      ),
      body: trashedDiaries.isEmpty
          ? const Center(child: Text('回收站是空的', style: TextStyle(color: Colors.grey, fontSize: 16)))
          : Column(
              children: [
                // 💡 优化 1：增加极其醒目的长按提示栏
                if (!_isSelectionMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    color: Colors.orange.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Text("小提示：长按某篇日记即可进入批量恢复与彻底粉碎模式", 
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: trashedDiaries.length,
                    itemBuilder: (context, index) {
                      final diary = trashedDiaries[index];
                      final int id = diary['id'] as int;
                      final bool isSelected = _selectedIds.contains(id);

                      return Card(
                        color: isSelected ? Colors.teal.shade50 : null,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: _isSelectionMode 
                              ? Checkbox(value: isSelected, onChanged: (v) => _toggleSelection(id))
                              : const Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(diary['title'] ?? '无标题', style: const TextStyle(decoration: TextDecoration.lineThrough)),
                          subtitle: Text('删除时间: ${(diary['delete_time'] ?? '').toString().split('.').first}'),
                          onTap: () {
                            if (_isSelectionMode) _toggleSelection(id);
                          },
                          onLongPress: () {
                            setState(() { _isSelectionMode = true; _selectedIds.add(id); });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _isSelectionMode ? BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.restore, color: Colors.green),
              label: const Text('恢复选中', style: TextStyle(color: Colors.green)),
              onPressed: _selectedIds.isEmpty ? null : _restoreSelected,
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('彻底粉碎', style: TextStyle(color: Colors.red)),
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
          ],
        ),
      ) : null,
    );
  }
}