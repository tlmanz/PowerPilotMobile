// Pairing: the design's "07 Pair" and "08 Scan". The server's admin page
// hands out a powerpilot://pair link as a QR code; the phone checks the token
// by listing the server's UPSes, then keeps it in the Keychain or Keystore.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/cloud_source.dart' show CloudSource, describeError;
import '../../data/pairing.dart';
import '../../models/ups.dart';
import '../../state/controllers.dart';
import '../theme.dart';
import '../widgets.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  bool _busy = false;

  /// Checks the link's token with the server, picks the UPS, and pairs.
  Future<void> _connect(String text) async {
    final PairingLink link;
    try {
      link = PairingLink.parse(text);
    } on FormatException catch (e) {
      toast(context, e.message, bad: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final devices = await CloudSource.devices(link.server, link.token);
      if (!mounted) return;
      final device = await _pickDevice(link, devices);
      if (device == null || !mounted) return;
      await AppScope.of(context).pair(Pairing.cloud(server: link.server, token: link.token, device: device));
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickDevice(PairingLink link, List<DeviceSummary> devices) async {
    if (link.device != null) {
      if (devices.any((d) => d.id == link.device)) return link.device;
      toast(context, "The server doesn't know the UPS “${link.device}”", bad: true);
      return null;
    }
    if (devices.isEmpty) {
      toast(context, 'The server has no UPS yet. Connect the ESP32, or PowerPilot in Publish mode, first.', bad: true);
      return null;
    }
    if (devices.length == 1) return devices.single.id;
    return pickOption<String>(
      context,
      title: 'Which UPS?',
      subtitle: 'The server watches more than one. You can switch later in Settings.',
      options: [for (final d in devices) (d.id, '${d.device.name} · ${d.id}${d.online ? '' : ' (offline)'}')],
    );
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<_ScanResult>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (!mounted || result == null) return;
    if (result.paste) {
      await _paste();
    } else if (result.link != null) {
      await _connect(result.link!);
    }
  }

  /// A dialog for a link copied from the admin page, filled from the
  /// clipboard when it holds one.
  Future<void> _paste() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!mounted) return;
    final field = TextEditingController(text: clip.startsWith('powerpilot://') ? clip : '');
    final link = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste a pairing link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Copy it from the admin page. It starts with powerpilot://pair'),
            const SizedBox(height: 14),
            TextField(
              controller: field,
              autofocus: field.text.isEmpty,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              style: text(14),
              decoration: const InputDecoration(hintText: 'powerpilot://pair?url=…&token=…'),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: text(15, weight: FontWeight.w600, color: AppColors.ink2),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(
              'Pair',
              style: text(15, weight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ],
      ),
    );
    field.dispose();
    if (link != null && link.trim().isNotEmpty) await _connect(link);
  }

  @override
  Widget build(BuildContext context) {
    final keychain = Platform.isIOS ? 'Keychain' : 'Keystore';
    final steps = [
      ("Open the server's admin page", 'On your computer, through SSH: localhost:8081'),
      ('Create a phone token', 'Choose Phone. The token is shown once, as a QR code.'),
      ('Scan it with this phone', 'The address and token are saved in the $keychain.'),
    ];
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ConstrainedBox(
              // Never negative: Android's first frame can be zero high.
              constraints: BoxConstraints(minHeight: (c.maxHeight - 28).clamp(0.0, double.infinity)),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('images/logo.png', width: 56, height: 56)),
                    const SizedBox(height: 14),
                    Text('Pair this phone', style: text(30, weight: FontWeight.w700, spacing: -0.6)),
                    const SizedBox(height: 6),
                    Text(
                      'Connect to your PowerPilot server to watch and control your UPS from anywhere.',
                      style: text(15, color: AppColors.ink2, height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    AppCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < steps.length; i++) ...[
                            if (i > 0) const SizedBox(height: 14),
                            _Step(i + 1, steps[i].$1, steps[i].$2),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy ? null : _scan,
                        child: _busy
                            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.scanQrCode, size: 20, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Scan QR code',
                                    style: text(16, weight: FontWeight.w600, color: Colors.white),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Section(
                      'Other ways',
                      children: [
                        ControlRow(
                          icon: LucideIcons.clipboardPaste,
                          title: 'Paste a pairing link',
                          subtitle: 'For a link copied from the admin page',
                          trailing: const ValueChevron(null),
                          onTap: _busy ? null : _paste,
                        ),
                        ControlRow(
                          icon: LucideIcons.play,
                          wash: AppColors.goodWash,
                          iconColor: AppColors.goodInk,
                          title: 'Try with demo data',
                          subtitle: 'A simulated UPS. Pair a server later in Settings.',
                          trailing: const ValueChevron(null),
                          onTap: _busy ? null : () => AppScope.of(context).pair(const Pairing.demo()),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        'Each token can be revoked on the admin page. Unpairing deletes it from this phone.',
                        textAlign: TextAlign.center,
                        style: text(12, color: AppColors.ink3, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.title, this.subtitle);

  final int n;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.primaryWash, shape: BoxShape.circle),
        child: Text(
          '$n',
          style: text(13, weight: FontWeight.w700, color: AppColors.primary),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text(15, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: text(12, color: AppColors.ink3, height: 1.35)),
          ],
        ),
      ),
    ],
  );
}

/// What the scanner hands back: a pairing link, or a request to paste one.
class _ScanResult {
  const _ScanResult.link(String this.link) : paste = false;
  const _ScanResult.paste() : link = null, paste = true;

  final String? link;
  final bool paste;
}

const _window = 260.0;

/// The camera, under the design's "08 Scan" overlay.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _camera = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  DateTime _warned = DateTime(0);

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue?.trim() ?? '';
      if (value.startsWith('powerpilot://pair')) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, _ScanResult.link(value));
        return;
      }
    }
    // Some other QR code: say so, but not on every frame.
    if (DateTime.now().difference(_warned) > const Duration(seconds: 3)) {
      _warned = DateTime.now();
      toast(context, "That isn't a PowerPilot pairing code", bad: true);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: const Color(0xFF070B17),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _camera, onDetect: _detect, errorBuilder: (context, error) => _CameraProblem(error)),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _ViewfinderPainter())),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _RoundButton(LucideIcons.x, label: 'Close', onTap: () => Navigator.pop(context)),
                      Expanded(
                        child: Text(
                          'Scan pairing code',
                          textAlign: TextAlign.center,
                          style: text(17, weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _camera,
                        builder: (context, state, _) => _RoundButton(
                          state.torchState == TorchState.on ? LucideIcons.flashlightOff : LucideIcons.flashlight,
                          label: 'Torch',
                          onTap: state.torchState == TorchState.unavailable ? null : _camera.toggleTorch,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Padding(
                      // The hint sits under the window, which is centered on the screen.
                      padding: EdgeInsets.only(top: c.maxHeight / 2 + _window / 2 + 28, left: 40, right: 40),
                      child: Text(
                        "Point the camera at the QR code on the server's admin page.",
                        textAlign: TextAlign.center,
                        style: text(15, color: const Color(0xCCFFFFFF), height: 1.4),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0x1FFFFFFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context, const _ScanResult.paste()),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.clipboardPaste, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'Paste a link instead',
                            style: text(15, weight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(this.icon, {required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: const Color(0x1FFFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: onTap == null ? const Color(0x66FFFFFF) : Colors.white)),
      ),
    ),
  );
}

/// Dims the camera outside the scan window and draws its corners.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final window = Rect.fromCenter(center: size.center(Offset.zero), width: _window, height: _window);
    final hole = RRect.fromRectAndRadius(window, const Radius.circular(24));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = const Color(0x99070B17),
    );
    const l = 44.0;
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final (left, top, right, bottom) = (window.left, window.top, window.right, window.bottom);
    canvas.drawPath(
      Path()
        ..moveTo(left, top + l)
        ..lineTo(left, top)
        ..lineTo(left + l, top)
        ..moveTo(right - l, top)
        ..lineTo(right, top)
        ..lineTo(right, top + l)
        ..moveTo(left, bottom - l)
        ..lineTo(left, bottom)
        ..lineTo(left + l, bottom)
        ..moveTo(right - l, bottom)
        ..lineTo(right, bottom)
        ..lineTo(right, bottom - l),
      corner,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => false;
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'PowerPilot needs the camera to scan the code. Allow it in Settings, or paste the link instead.',
      MobileScannerErrorCode.unsupported => "This device has no camera PowerPilot can use. Paste the link instead.",
      _ => "The camera didn't start. Paste the link instead.",
    };
    return Container(
      color: const Color(0xFF070B17),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.cameraOff, size: 32, color: Color(0xCCFFFFFF)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: text(15, color: const Color(0xCCFFFFFF), height: 1.4),
          ),
        ],
      ),
    );
  }
}
