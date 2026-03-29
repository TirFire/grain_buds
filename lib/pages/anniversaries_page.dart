import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/database_helper.dart';

class AnniversariesPage extends StatefulWidget {
  const AnniversariesPage({super.key});

  @override
  State<AnniversariesPage> createState() => _AnniversariesPageState();
}

class _AnniversariesPageState extends State<AnniversariesPage> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;

  final List<String> _emojis = ['🎉', '🎂', '❤️', '✈️', '💼', '🎓', '🥂', '👶'];
  final List<Color> _colors = [Colors.teal, Colors.pink, Colors.blue, Colors.orange, Colors.purple, Colors.green];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final data = await DatabaseHelper.instance.getAnniversaries();
    if (mounted) {
      setState(() {
        _events = data;
        _isLoading = false;
      });
    }
  }

  // 💡 核心升级：合并新建和编辑的逻辑，支持传入已有事件
  void _showEventDialog({Map<String, dynamic>? existingEvent}) {
    final titleCtrl = TextEditingController(text: existingEvent?['title'] ?? '');
    DateTime selectedDate = existingEvent != null ? DateTime.parse(existingEvent['date']) : DateTime.now();
    String selectedEmoji = existingEvent?['icon'] ?? _emojis.first;
    Color selectedColor = existingEvent != null ? Color(existingEvent['color_value'] as int) : _colors.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existingEvent == null ? "新建纪念日 / 倒数日" : "编辑事件", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: titleCtrl,
                autofocus: existingEvent == null,
                decoration: const InputDecoration(labelText: "事件名称 (如：恋爱纪念日、发工资)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("目标日期"),
                trailing: Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setModalState(() => selectedDate = picked);
                },
              ),
              const SizedBox(height: 10),
              const Text("选择图标与颜色", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _emojis.map((e) => GestureDetector(
                    onTap: () => setModalState(() => selectedEmoji = e),
                    child: Container(
                      margin: const EdgeInsets.only(right: 15),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: selectedEmoji == e ? Colors.grey.shade200 : Colors.transparent, shape: BoxShape.circle),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 15),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _colors.map((c) => GestureDetector(
                    onTap: () => setModalState(() => selectedColor = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 15),
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: selectedColor == c ? Border.all(color: Colors.black87, width: 3) : null),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    
                    final eventData = {
                      'title': titleCtrl.text.trim(),
                      'date': selectedDate.toString(),
                      'icon': selectedEmoji,
                      'color_value': selectedColor.value,
                      'create_time': existingEvent?['create_time'] ?? DateTime.now().toString(),
                    };

                    if (existingEvent == null) {
                      await DatabaseHelper.instance.insertAnniversary(eventData);
                    } else {
                      eventData['id'] = existingEvent['id'];
                      await DatabaseHelper.instance.updateAnniversary(eventData);
                    }
                    
                    if (mounted) Navigator.pop(context);
                    _loadEvents();
                  },
                  child: Text(existingEvent == null ? "保存并添加到看板" : "保存修改", style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 💡 核心修复 1：拆分 prefix 和 suffix 解决中文语序问题
  // 💡 核心修复 1：拆分 prefix 和 suffix 解决中文语序问题
  Map<String, dynamic> _calculateDays(String targetDateStr) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime tDate = DateTime.parse(targetDateStr);
    DateTime target = DateTime(tDate.year, tDate.month, tDate.day);

    int days = target.difference(today).inDays;
    
    if (days == 0) return {'type': 'today', 'days': 0, 'prefix': '就是', 'suffix': '今天'};
    // 💡 修复：将 '已过去' 改为 '已经'
    if (days < 0) return {'type': 'past', 'days': days.abs(), 'prefix': '已经', 'suffix': '天'};
    return {'type': 'future', 'days': days, 'prefix': '还有', 'suffix': '天'};
  }

  // 💡 新增：点击弹出的操作菜单
  void _showActionMenu(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('修改卡片'),
              onTap: () {
                Navigator.pop(c);
                _showEventDialog(existingEvent: event);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此纪念日'),
              onTap: () async {
                Navigator.pop(c);
                await DatabaseHelper.instance.deleteAnniversary(event['id']);
                _loadEvents();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final calc = _calculateDays(event['date']);
    final Color cardColor = Color(event['color_value'] as int);
    final isPast = calc['type'] == 'past';
    final isToday = calc['type'] == 'today';

    return GestureDetector(
      onTap: () => _showActionMenu(event), // 💡 统一为点击弹出菜单
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cardColor.withOpacity(0.8), cardColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cardColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), // 💡 缩小内边距防溢出
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 💡 彻底解决挤压溢出的关键
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                  child: Text(isToday ? "✨ 纪念日" : (isPast ? "🗓️ 纪念日" : "⏰ 倒数日"), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Text(event['icon'], style: const TextStyle(fontSize: 22)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // 💡 完美的语序与基线对齐
                // 💡 完美的语序与基线对齐
                isToday 
                  ? const Text("就是今天", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.0))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text("${calc['prefix']} ", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        Text("${calc['days']}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.0)),
                        Text(" ${calc['suffix']}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                const SizedBox(height: 4),
                Text("${isPast ? '起始日' : '目标日'}: ${event['date'].substring(0, 10)}", style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("时光看板", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _events.isEmpty
            ? Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_note, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text("还没有添加任何纪念日\n留住那些闪亮的日子吧", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)),
                ],
              ))
            : LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 1;
                  double ratio = 1.4; // 💡 优化电脑端比例，更舒适
                  if (constraints.maxWidth > 900) {
                    crossAxisCount = 4; ratio = 1.5;
                  } else if (constraints.maxWidth > 600) {
                    crossAxisCount = 3; ratio = 1.4;
                  } else if (constraints.maxWidth > 400) {
                    crossAxisCount = 2; ratio = 1.3;
                  }
                  
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: ratio,
                    ),
                    itemCount: _events.length,
                    itemBuilder: (context, index) => _buildEventCard(_events[index]),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEventDialog(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("新建", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}