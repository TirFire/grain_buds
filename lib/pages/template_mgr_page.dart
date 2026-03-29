import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database_helper.dart';

class TemplateMgrPage extends StatefulWidget {
  const TemplateMgrPage({super.key});
  @override
  State<TemplateMgrPage> createState() => _TemplateMgrPageState();
}

class _TemplateMgrPageState extends State<TemplateMgrPage> {
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final data = await DatabaseHelper.instance.getTemplates();
    setState(() => _templates = data);
  }

  void _showEditDialog([Map<String, dynamic>? tpl]) {
    final nameCtrl = TextEditingController(text: tpl?['name'] ?? "");
    final titleCtrl = TextEditingController(text: tpl?['title_tpl'] ?? "");
    final contentCtrl = TextEditingController(text: tpl?['content_tpl'] ?? "");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tpl == null ? "新建模板" : "修改模板"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "模板名称 (如: 读书笔记)")),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "默认标题")),
              TextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(labelText: "默认正文内容 (支持 Markdown)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              await DatabaseHelper.instance.saveTemplate({
                if (tpl != null) 'id': tpl['id'],
                'name': nameCtrl.text,
                'title_tpl': titleCtrl.text,
                'content_tpl': contentCtrl.text,
                'tags_tpl': tpl?['tags_tpl'] ?? jsonEncode([]),
              });
              Navigator.pop(c);
              _refresh();
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("日记模板管理"), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
      body: ListView.builder(
        itemCount: _templates.length,
        itemBuilder: (context, index) {
          final t = _templates[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: Icon(Icons.copy_all, color: Theme.of(context).primaryColor),
              title: Text(t['name']),
              subtitle: Text(t['title_tpl'], maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showEditDialog(t)),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () async {
                    await DatabaseHelper.instance.deleteTemplate(t['id']);
                    _refresh();
                  }),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}