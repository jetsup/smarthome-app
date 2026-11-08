import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/providers.dart';
import '../theme/app_colors.dart';

/// The picture behind the clock on a display's lock screen. Pick any photo: the hub fits it to the
/// screen (320 x 240), smooths the colours and sends it to the display.
class LockBackgroundCard extends ConsumerStatefulWidget {
  final String displaySlug;
  const LockBackgroundCard({super.key, required this.displaySlug});

  @override
  ConsumerState<LockBackgroundCard> createState() => _LockBackgroundCardState();
}

class _LockBackgroundCardState extends ConsumerState<LockBackgroundCard> {
  Uint8List? _preview;
  XFile? _picked;
  double _zoom = 1, _panX = 0.5, _panY = 0.5;
  bool _busy = false;
  bool _loading = true;
  String? _msg;
  bool _msgOk = true;

  String get _path => '/api/hmis/${widget.displaySlug}/background';

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final r = await ref.read(apiServiceProvider).getBytes(_path);
      if (mounted)
        setState(() => _preview = Uint8List.fromList(r.data ?? const []));
    } catch (_) {
      if (mounted) setState(() => _preview = null); // none uploaded yet
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _error(Object e, String fallback) {
    try {
      final d = (e as dynamic).response?.data;
      if (d is Map && d['error'] != null) return '${d['error']}';
    } catch (_) {}
    return fallback;
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 92,
    );
    if (f == null) return;
    _picked = f;
    _zoom = 1;
    _panX = 0.5;
    _panY = 0.5;
    await _upload();
  }

  Future<void> _upload() async {
    final f = _picked;
    if (f == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(f.path, filename: 'lock.jpg'),
        'zoom': _zoom.toStringAsFixed(2),
        'panX': _panX.toStringAsFixed(2),
        'panY': _panY.toStringAsFixed(2),
      });
      await ref.read(apiServiceProvider).post(_path, data: form);
      await _loadPreview();
      setState(() {
        _msg = 'Sent. The display picks it up within a few seconds.';
        _msgOk = true;
      });
    } catch (e) {
      setState(() {
        _msg = _error(e, 'Could not upload the picture');
        _msgOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).delete(_path);
      setState(() {
        _preview = null;
        _picked = null;
        _msg = 'Removed. The display goes back to its built-in backgrounds.';
        _msgOk = true;
      });
    } catch (e) {
      setState(() {
        _msg = _error(e, 'Could not remove it');
        _msgOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: c.bg,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _preview != null && _preview!.isNotEmpty
                    ? Image.memory(
                        _preview!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_outlined,
                              size: 34,
                              color: c.muted,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No picture yet',
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'The display uses one of its built-in backgrounds.',
                              style: TextStyle(color: c.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _preview != null
                        ? 'Choose another picture'
                        : 'Choose a picture',
                  ),
                ),
              ),
              if (_preview != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
          if (_picked != null) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Adjust the crop',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                children: [
                  _slider('Zoom', _zoom, 1, 4, (v) => _zoom = v),
                  _slider('Left – right', _panX, 0, 1, (v) => _panX = v),
                  _slider('Up – down', _panY, 0, 1, (v) => _panY = v),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _busy ? null : _upload,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_msg != null) ...[
            const SizedBox(height: 8),
            Text(
              _msg!,
              style: TextStyle(color: _msgOk ? c.ok : c.bad, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double v,
    double lo,
    double hi,
    void Function(double) set,
  ) => Row(
    children: [
      SizedBox(
        width: 84,
        child: Text(
          label,
          style: TextStyle(color: context.c.muted, fontSize: 12),
        ),
      ),
      Expanded(
        child: Slider(
          value: v,
          min: lo,
          max: hi,
          onChanged: (x) => setState(() => set(x)),
        ),
      ),
    ],
  );
}
