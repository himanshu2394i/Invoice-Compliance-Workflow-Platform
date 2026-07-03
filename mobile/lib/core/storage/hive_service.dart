import 'package:hive_flutter/hive_flutter.dart';
import '../models/bundle.dart';

class HiveService {
  static const String _bundleBoxName = 'queued_bundles';
  static const String _draftBoxName = 'capture_draft';
  static const String _draftKey = 'current';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(QueuedPhotoAdapter());
    Hive.registerAdapter(QueuedBundleAdapter());
    await Hive.openBox<QueuedBundle>(_bundleBoxName);
    await Hive.openBox<QueuedBundle>(_draftBoxName);
  }

  static Box<QueuedBundle> get bundleBox =>
      Hive.box<QueuedBundle>(_bundleBoxName);

  static Box<QueuedBundle> get draftBox =>
      Hive.box<QueuedBundle>(_draftBoxName);

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

  static Future<void> saveCaptureDraft(QueuedBundle draft) async {
    if (!Hive.isBoxOpen(_draftBoxName)) return;
    draft.status = 'draft';
    await draftBox.put(_draftKey, draft);
  }

  static QueuedBundle? loadCaptureDraft() {
    if (!Hive.isBoxOpen(_draftBoxName)) return null;
    return draftBox.get(_draftKey);
  }

  static bool hasCaptureDraft() => loadCaptureDraft() != null;

  static Future<void> clearCaptureDraft() async {
    if (!Hive.isBoxOpen(_draftBoxName)) return;
    await draftBox.delete(_draftKey);
  }
}
