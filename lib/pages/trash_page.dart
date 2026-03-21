import 'package:flutter/material.dart';

// 💡 引入数据库操作类
import '../core/database_helper.dart'; 

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Map<String, dynamic>> trashedDiaries = [];

  @override
  void initState() { 
    super.initState(); 
    _loadTrash(); 
  }

  // 💡 加载回收站数据
  Future<void> _loadTrash() async {
    final data = await DatabaseHelper.instance.getTrashedDiaries();
    if (mounted) {
      setState(() { 
        trashedDiaries = data; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'), 
        backgroundColor: Colors.blueGrey, 
        foregroundColor: Colors.white
      ),
      body: trashedDiaries.isEmpty
          ? const Center(
              child: Text(
                '回收站是空的\n(被删除的日记会暂存在这里)', 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16)
              )
            )
          : ListView.builder(
              itemCount: trashedDiaries.length,
              itemBuilder: (context, index) {
                final diary = trashedDiaries[index];
                
                // 💡 强类型安全提取数据
                final int id = diary['id'] as int;
                final String title = (diary['title'] as String?) ?? '无标题';
                final String deleteTime = (diary['delete_time'] as String?) ?? '未知时间';
                final String dateDisplay = deleteTime.length >= 16 ? deleteTime.substring(0, 16) : deleteTime;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    // 标题加上删除线效果
                    title: Text(
                      title, 
                      style: const TextStyle(decoration: TextDecoration.lineThrough)
                    ),
                    subtitle: Text('删除时间: $dateDisplay'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🟢 恢复按钮
                        IconButton(
                          icon: const Icon(Icons.restore, color: Colors.green), 
                          tooltip: '恢复日记', 
                          onPressed: () async { 
                            await DatabaseHelper.instance.restoreDiary(id); 
                            _loadTrash(); 
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🎉 日记已成功恢复！'))); 
                            }
                          }
                        ),
                        
                        // 🔴 彻底删除按钮
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red), 
                          tooltip: '彻底粉碎', 
                          onPressed: () { 
                            showDialog(
                              context: context, 
                              builder: (c) => AlertDialog(
                                title: const Text('彻底粉碎'), 
                                content: const Text('物理文件（包括绑定的图片、音频、视频、附件）将被彻底从硬盘删除，此操作不可逆转！\n\n确定要粉碎吗？'), 
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c), 
                                    child: const Text('取消')
                                  ), 
                                  TextButton(
                                    onPressed: () async { 
                                      Navigator.pop(c); 
                                      await DatabaseHelper.instance.permanentlyDeleteDiary(id); 
                                      _loadTrash(); 
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🧹 文件已彻底销毁！'))); 
                                      }
                                    }, 
                                    child: const Text('彻底粉碎', style: TextStyle(color: Colors.red))
                                  )
                                ]
                              )
                            ); 
                          }
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}