import 'package:hive_flutter/hive_flutter.dart';
import '../models/bundle.dart';

class HiveService {
  static const String _bundleBoxName = 'queued_bundles';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(QueuedPhotoAdapter());
    Hive.registerAdapter(QueuedBundleAdapter());
    await Hive.openBox<QueuedBundle>(_bundleBoxName);
  }

  static Box<QueuedBundle> get bundleBox =>
      Hive.box<QueuedBundle>(_bundleBoxName);

  static Future<void> saveBundle(QueuedBundle bundle) async {
    await bundleBox.put(bundle.localId, bundle);
  }

  static Future<void> updateBundleStatus(
    String localId,
    String status, {
    String? error,
  }) async {
    final bundle = bundleBox.get(localId);
    if (bundle == null) return;
    bundle.status = status;
    bundle.syncError = error;
    await bundle.save();
  }

  static List<QueuedBundle> pendingBundles() => bundleBox.values
      .where((b) => b.status == 'pending' || b.status == 'failed')
      .toList();

  static List<QueuedBundle> allBundles() =>
      bundleBox.values.toList()
        ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
}
