import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class LanSyncService {
  static HttpServer? _server;

  // 1. 智能获取本机局域网 IPv4 地址
  static Future<String?> getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          // 优先寻找常见的 192.168.x.x 局域网网段
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }
      // 如果没有 192.168，返回第一个非本地回环的 IPv4
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint("获取局域网IP失败: $e");
    }
    return null;
  }

  // 2. 作为发送端：开启临时微型服务器
  static Future<String?> startSharing() async {
    try {
      // 步骤 A：先生成一个包含所有最新数据的完整 ZIP 备份
      final tempDir = await getTemporaryDirectory();
      final backupPath = p.join(tempDir.path, 'lan_share_backup.zip');
      
      final resultPath = await DatabaseHelper.instance.createFullBackup(backupPath);
      if (resultPath == null) return null;

      // 步骤 B：强行关闭可能残留的旧服务，开启新服务 (固定端口 9527)
      _server?.close(); 
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 9527);
      
      // 步骤 C：监听请求，只要有人访问 /sync，就把 ZIP 扔给他
      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/sync') {
          final file = File(backupPath);
          if (await file.exists()) {
            request.response.headers.contentType = ContentType('application', 'zip');
            request.response.headers.add('Content-Disposition', 'attachment; filename="sync_data.zip"');
            await file.openRead().pipe(request.response);
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      });

      return await getLocalIpAddress();
    } catch (e) {
      debugPrint("开启局域网共享失败: $e");
      return null;
    }
  }

  // 3. 安全停止分享
  static void stopSharing() {
    _server?.close();
    _server = null;
  }

  // 4. 作为接收端：去连接另一台设备的 IP 并下载数据合并
  // 4. 作为接收端：去连接另一台设备的 IP 并【流式下载】合并
  static Future<bool> receiveData(String ipAddress) async {
    try {
      final url = Uri.parse('http://$ipAddress:9527/sync');
      
      // 💡 终极修复：使用 http.Request 进行流式下载，而不是用 get() 把几 G 数据全塞内存
      final request = http.Request('GET', url);
      final streamedResponse = await request.send().timeout(const Duration(minutes: 10)); // 给局域网大文件留够时间
      
      if (streamedResponse.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final zipPath = p.join(tempDir.path, 'received_lan_data.zip');
        
        final file = File(zipPath);
        final sink = file.openWrite(); // 打开管道
        
        // 💡 像水管一样，把接收到的数据一边下、一边存到硬盘，0 内存压力！
        await streamedResponse.stream.pipe(sink);
        await sink.close();
        
        // 下载完毕后，调用 DatabaseHelper 进行流式解压
        return await DatabaseHelper.instance.restoreFromZip(zipPath);
      }
      return false;
    } catch (e) {
      debugPrint("局域网接收数据失败: $e");
      return false;
    }
  }
}