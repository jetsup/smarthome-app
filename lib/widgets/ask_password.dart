import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Asks for the account password. Returns it, or null when cancelled.
Future<String?> askPassword(BuildContext context, String title, String why, {String confirm = 'Confirm', bool danger = false}) async {
  final ctl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.c.card,
      title: Text(title, style: TextStyle(color: ctx.c.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(why, style: TextStyle(color: ctx.c.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Your password'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.c.badStrong) : null,
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
  ctl.dispose();
  return (r == null || r.isEmpty) ? null : r;
}
