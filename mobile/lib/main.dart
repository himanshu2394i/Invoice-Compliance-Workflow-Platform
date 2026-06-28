import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/server_config.dart';
import 'core/storage/hive_service.dart';
import 'features/capture/sync_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  await ServerConfig.load();

  // Auto-sync whenever network is restored
  Connectivity().onConnectivityChanged.listen((results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (connected) {
      syncService.syncPending().ignore();
    }
  });

  runApp(const ProviderScope(child: InvoiceCaptureApp()));
}
