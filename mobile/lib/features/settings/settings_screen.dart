import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/server_config.dart';
import '../../core/navigation/app_back.dart';
import '../auth/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Server URL saved. Restart the app if already logged in.'),
      ),
    );
  }

  Future<void> _reset() async {
    await ServerConfig.reset();
    if (!mounted) return;
    _urlCtrl.text = ServerConfig.baseUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to default (Android emulator).')),
    );
  }

  String? _validatePassword(String? value) {
    final password = value?.trim() ?? '';
    if (password.length < 10) return 'Minimum 10 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Use letters and numbers';
    }
    return null;
  }

  Future<void> _showChangePasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              setDialogState(() => submitting = true);
              final ok = await ref.read(authProvider.notifier).changePassword(
                    currentCtrl.text.trim(),
                    newCtrl.text.trim(),
                  );
              if (!mounted) return;
              if (ok) {
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Password changed')),
                );
              } else {
                setDialogState(() => submitting = false);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ref.read(authProvider).error ?? 'Password change failed',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Change Password'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                      ),
                      validator: (value) =>
                          (value?.trim().isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                      ),
                      validator: (value) {
                        if ((value ?? '') != newCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _showResetStaffPasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              setDialogState(() => submitting = true);
              final ok =
                  await ref.read(authProvider.notifier).resetStaffPassword(
                        emailCtrl.text.trim(),
                        newCtrl.text.trim(),
                      );
              if (!mounted) return;
              if (ok) {
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Staff password reset')),
                );
              } else {
                setDialogState(() => submitting = false);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ref.read(authProvider).error ?? 'Password reset failed',
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('Reset Staff Password'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Staff Email',
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Required';
                        if (!email.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                      ),
                      validator: (value) {
                        if ((value ?? '') != newCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final role = auth.user?['role'] as String?;
    final isAdmin = role == 'ADMIN';

    return AppBackScope(
      fallbackLocation: '/home',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => AppBackScope.goBack(
              context,
              fallbackLocation: '/home',
            ),
          ),
          title: const Text('Server Settings'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backend Server URL',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your server\'s LAN IP and port.\n'
                  'Example: http://192.168.1.42:8000',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
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
                if (auth.isLoggedIn) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Account Security',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showChangePasswordDialog,
                  ),
                  if (isAdmin)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Reset Staff Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showResetStaffPasswordDialog,
                    ),
                ],
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Default URL (Android emulator -> host)',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
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
        ),
      ),
    );
  }
}
