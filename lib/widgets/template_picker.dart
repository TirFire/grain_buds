import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database_helper.dart';

class TemplatePicker extends StatelessWidget {
  final Function(String title, String content, List<String> tags) onSelect;

  const TemplatePicker({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.instance.getTemplates(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final tpls = snapshot.data!;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("选择日记模板", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...tpls.map((t) => ListTile(
                leading: const Icon(Icons.description_outlined, color: Colors.teal),
                title: Text(t['name']),
                subtitle: Text(t['title_tpl'], maxLines: 1),
                onTap: () {
                  List<String> tags = [];
                  try { tags = List<String>.from(jsonDecode(t['tags_tpl'])); } catch(_) {}
                  onSelect(t['title_tpl'], t['content_tpl'], tags);
                  Navigator.pop(context);
                },
              )).toList(),
              if (tpls.isEmpty) const Text("暂无模板，可在设置中创建"),
            ],
          ),
        );
      },
    );
  }
}