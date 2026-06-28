import 'package:flutter/material.dart';
import '../../core/config/server_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ServerConfig.baseUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _saving = true);
    await ServerConfig.save(url);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL saved. Restart the app if already logged in.')),
      );
    }
  }

  Future<void> _reset() async {
    await ServerConfig.reset();
    _urlCtrl.text = ServerConfig.baseUrl;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to default (Android emulator).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend Server URL',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your server\'s LAN IP and port.\n'
              'Example: http://192.168.1.42:8000',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.x.x:8000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Default URL (Android emulator → host)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            Text(
              ServerConfig.defaultUrl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Colors.grey[700],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
