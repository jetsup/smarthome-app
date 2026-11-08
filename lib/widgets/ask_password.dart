import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Asks for the account password (with a show/hide eye). Returns it, or null
/// when cancelled.
Future<String?> askPassword(BuildContext context, String title, String why, {String confirm = 'Confirm', bool danger = false}) async {
  final r = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PasswordDialog(title: title, why: why, confirm: confirm, danger: danger),
  );
  return (r == null || r.isEmpty) ? null : r;
}

// The dialog owns its controller, so it is disposed only once the dialog is
// really gone (disposing it right after pop crashes during the close animation).
class _PasswordDialog extends StatefulWidget {
  final String title, why, confirm;
  final bool danger;
  const _PasswordDialog({required this.title, required this.why, required this.confirm, required this.danger});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctl = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.c.card,
      title: Text(widget.title, style: TextStyle(color: context.c.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.why, style: TextStyle(color: context.c.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            obscureText: !_show,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Your password',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide password' : 'Show password',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: context.c.badStrong) : null,
          onPressed: () => Navigator.pop(context, _ctl.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
