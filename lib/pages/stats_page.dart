import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
// 💡 确保你在终端运行了: flutter pub add flutter_heatmap_calendar
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';

import '../core/database_helper.dart'; 
import 'summary_page.dart'; 

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 💡 核心状态变量都在这里声明
  int _totalDiaries = 0;
  int _totalWords = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;
  Map<String, int> _monthlyData = {}; 
  Map<DateTime, int> _heatMapDatasets = {}; // 💡 这里就是报错提示找不到的那个变量
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateStats();
  }

  Future<void> _calculateStats() async {
    final allDiaries = await DatabaseHelper.instance.getAllDiaries();
    
    int words = 0;
    List<DateTime> dates = [];
    Map<String, int> monthlyCounts = {};
    Map<DateTime, int> heatMapTemp = {}; // 临时拼装热力图数据

    for (var d in allDiaries) {
      String content = (d['content'] as String? ?? "").replaceAll(RegExp(r'\s+'), '');
      words += content.length;

      DateTime date = DateTime.parse(d['date'] as String);
      dates.add(DateTime(date.year, date.month, date.day));

      // 月度柱状图数据
      String monthKey = DateFormat('yyyy-MM').format(date);
      monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;

      // 热力图数据 (去除时分秒，仅保留到天)
      DateTime pureDate = DateTime(date.year, date.month, date.day);
      heatMapTemp[pureDate] = (heatMapTemp[pureDate] ?? 0) + 1;
    }

    dates.sort((a, b) => b.compareTo(a)); 
    final uniqueDates = dates.toSet().toList();
    
    int current = 0;
    int longest = 0;
    int tempLongest = 0;

    if (uniqueDates.isNotEmpty) {
      DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      
      if (uniqueDates[0] == today || uniqueDates[0] == today.subtract(const Duration(days: 1))) {
        current = 1;
        for (int i = 0; i < uniqueDates.length - 1; i++) {
          if (uniqueDates[i].difference(uniqueDates[i + 1]).inDays == 1) {
            current++;
          } else {
            break;
          }
        }
      }

      tempLongest = 1;
      for (int i = 0; i < uniqueDates.length - 1; i++) {
        if (uniqueDates[i].difference(uniqueDates[i + 1]).inDays == 1) {
          tempLongest++;
        } else {
          if (tempLongest > longest) longest = tempLongest;
          tempLongest = 1;
        }
      }
      if (tempLongest > longest) longest = tempLongest;
    }

    if (mounted) {
      setState(() {
        _totalDiaries = allDiaries.length;
        _totalWords = words;
        _currentStreak = current;
        _longestStreak = longest;
        _monthlyData = monthlyCounts;
        _heatMapDatasets = heatMapTemp; // 💡 赋值给状态变量
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("写作统计报表"),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: Colors.amber),
            tooltip: "生成年度总结海报",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SummaryPage()));
            },
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildStatCard("总篇数", _totalDiaries.toString(), Icons.book, Colors.blue),
                    _buildStatCard("总字数", _totalWords.toString(), Icons.text_fields, Colors.orange),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatCard("当前连胜", "$_currentStreak 天", Icons.local_fire_department, Colors.red),
                    _buildStatCard("最长连胜", "$_longestStreak 天", Icons.emoji_events, Colors.amber),
                  ],
                ),
                
                const SizedBox(height: 24),

                // ================== GitHub 风格打卡热力图 ==================
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("打卡热力图", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),
                        HeatMap(
                          datasets: _heatMapDatasets,
                          colorMode: ColorMode.opacity,
                          showText: false,
                          scrollable: true,
                          size: 16,
                          colorsets: const {
                            1: Colors.teal, // 基础颜色，写得越多会自动加深
                          },
                          onClick: (value) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(DateFormat('yyyy年MM月dd日').format(value) + " 的记录印记"))
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),

                // ================== 月度柱状图 ==================
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("最近月度写作量", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 30),
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (_monthlyData.values.isEmpty ? 10 : _monthlyData.values.reduce((a, b) => a > b ? a : b) + 2).toDouble(),
                              barGroups: _buildBarGroups(primaryColor),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: _getBottomTitles)),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: false),
                            )
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                const Text("“字字珠玑，皆是时光的印记”", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                const SizedBox(height: 30),
              ],
            ),
          ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups(Color color) {
    List<String> sortedMonths = _monthlyData.keys.toList()..sort();
    if (sortedMonths.length > 6) sortedMonths = sortedMonths.sublist(sortedMonths.length - 6);
    
    return sortedMonths.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: _monthlyData[e.value]!.toDouble(),
            color: color,
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          )
        ],
      );
    }).toList();
  }

  Widget _getBottomTitles(double value, TitleMeta meta) {
    List<String> sortedMonths = _monthlyData.keys.toList()..sort();
    if (sortedMonths.length > 6) {
      sortedMonths = sortedMonths.sublist(sortedMonths.length - 6);
    }
    
    if (value.toInt() >= 0 && value.toInt() < sortedMonths.length) {
      String month = sortedMonths[value.toInt()].split('-')[1];
      return SideTitleWidget(
        meta: meta, 
        space: 4,   
        child: Text("${month}月", style: const TextStyle(fontSize: 10, color: Colors.grey)),
      );
    }
    return const SizedBox.shrink();
  }
}