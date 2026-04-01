import 'package:flutter/material.dart';
import '../core/lan_sync_service.dart';

class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  bool _isSharing = false;
  bool _isProcessing = false;
  String? _myIpAddress;
  final TextEditingController _ipController = TextEditingController();

  @override
  void dispose() {
    LanSyncService.stopSharing(); // 退出页面时自动关闭服务器，防止端口占用
    _ipController.dispose();
    super.dispose();
  }

  void _toggleShare() async {
    if (_isSharing) {
      LanSyncService.stopSharing();
      setState(() => _isSharing = false);
    } else {
      setState(() => _isProcessing = true);
      String? ip = await LanSyncService.startSharing();
      setState(() {
        _isProcessing = false;
        if (ip != null) {
          _myIpAddress = ip;
          _isSharing = true;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开启共享失败，请检查网络连接')));
        }
      });
    }
  }

  void _startReceive() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入发送端的 IP 地址')));
      return;
    }

    setState(() => _isProcessing = true);
    bool success = await LanSyncService.receiveData(ip);
    setState(() => _isProcessing = false);

    if (mounted) {
      if (success) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('传输成功')]),
            content: const Text('数据已成功从另一台设备合并到本机！'),
            actions: [
              TextButton(onPressed: () { Navigator.pop(c); Navigator.pop(context); }, child: const Text('完成'))
            ],
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('传输失败：请确保两台设备在同一 Wi-Fi 下，且 IP 正确')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网极速快传'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text("在没有网络或需要极速迁移数据时，您可以使用此功能将日记与多媒体文件直接克隆到另一台设备。", 
                  style: TextStyle(color: Colors.grey, height: 1.5)),
              const SizedBox(height: 30),

              // ====== 发送方卡片 ======
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.upload_rounded, color: Colors.blue, size: 28),
                          SizedBox(width: 10),
                          Text("我是发送方", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      if (_isSharing) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              const Text("请在接收端输入以下 IP 地址：", style: TextStyle(color: Colors.blueGrey)),
                              const SizedBox(height: 10),
                              Text(_myIpAddress ?? '', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue, letterSpacing: 2)),
                            ],
                          ),
                        ),
                      ] else 
                        const Text("点击开启共享后，本机将作为热点，等待接收端连接。", style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _toggleShare,
                          style: ElevatedButton.styleFrom(backgroundColor: _isSharing ? Colors.redAccent : Colors.blue, foregroundColor: Colors.white),
                          child: Text(_isSharing ? "停止共享" : "开启共享模式", style: const TextStyle(fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // ====== 接收方卡片 ======
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.download_rounded, color: Colors.teal, size: 28),
                          SizedBox(width: 10),
                          Text("我是接收方", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      const Text("请确保两台设备连接在同一个 Wi-Fi 网络下。", style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _ipController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '输入发送方显示的 IP 地址',
                          hintText: '例如: 192.168.1.100',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.wifi),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (_isSharing || _isProcessing) ? null : _startReceive,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          child: const Text("开始拉取并合并数据", style: TextStyle(fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 加载遮罩
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text("正在打包或传输数据，请勿退出...", style: TextStyle(color: Colors.white, fontSize: 16, decoration: TextDecoration.none)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}