import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:luminar/config/dependencies.dart';
import 'package:luminar/domain/models/connection.dart';
import 'package:luminar/ui/features/activity_log/views/log_screen.dart';
import 'package:luminar/ui/features/home/view_models/home_view_model.dart';
import 'package:luminar/ui/core/theme.dart';
import 'package:luminar/ui/core/widgets.dart';

/// The connection, backups, the activity log, and starting over.
class SettingsScreen extends StatelessWidget {
  final HomeViewModel viewModel;
  const SettingsScreen({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = viewModel;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings', style: display(20)),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final n = c.lights.length;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  const SectionHeader('Connection'),
                  _Group(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bluetooth_rounded),
                        title: Text(c.connectionLabel),
                        subtitle: Text('$n light${n == 1 ? '' : 's'} on this phone'),
                        trailing: c.lights.isEmpty
                            ? null
                            : TextButton(
                                onPressed: c.connection == Connection.connecting || c.busy
                                    ? null
                                    : c.toggleConnection,
                                child: Text(c.isConnected ? 'Disconnect' : 'Connect'),
                              ),
                      ),
                    ],
                  ),
                  const SectionHeader('Backup'),
                  _Group(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('Back up lights'),
                        subtitle: const Text('A code that brings your lights to another phone'),
                        enabled: c.lights.isNotEmpty,
                        onTap: () => _backup(context),
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings_backup_restore_rounded),
                        title: const Text('Restore from backup'),
                        subtitle: const Text('Replaces the lights on this phone'),
                        onTap: () async {
                          if (await showRestoreDialog(context, c) && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                  const SectionHeader('Troubleshooting'),
                  _Group(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: const Text('Activity log'),
                        subtitle: const Text('Every message to and from your lights'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LogScreen(
                              viewModel: context.read<Dependencies>().activityLogViewModel(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _Group(
                    children: [
                      ListTile(
                        leading: Icon(Icons.delete_forever_outlined, color: p.danger),
                        title: Text('Start over', style: TextStyle(color: p.danger)),
                        subtitle: const Text('Forget every light on this phone'),
                        onTap: () => _startOver(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _backup(BuildContext context) async {
    final c = viewModel;
    final code = c.backupCode();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Backup code', style: display(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keep this code somewhere private, like a password manager. It restores your lights on this or another phone, and it also works in the Lamplight web app.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.of(ctx).bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) Navigator.pop(ctx);
              c.backupCopied();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () =>
                SharePlus.instance.share(ShareParams(text: code, subject: 'Luminar backup code')),
            child: const Text('Share'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _startOver(BuildContext context) async {
    final ok = await confirm(
      context,
      'Start over?',
      'This phone forgets all your lights. Each bulb will need a reset before you can add it again.',
      action: 'Start over',
      danger: true,
    );
    if (!ok) return;
    await viewModel.startOver();
    if (context.mounted) Navigator.pop(context);
  }
}

/// Asks for a backup code and restores it. Returns true if it was restored.
Future<bool> showRestoreDialog(BuildContext context, HomeViewModel viewModel) async {
  final text = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Restore from backup', style: display(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Paste your backup code. This replaces the lights on this phone.'),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'LAMPLIGHT1:…',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true) return false;
  return viewModel.restore(text.text);
}

/// Settings rows on one rounded surface.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
      child: Column(
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: p.line),
            w,
          ],
        ],
      ),
    );
  }
}
