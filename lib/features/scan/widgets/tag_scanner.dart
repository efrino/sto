import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scan_code.dart';

/// Pemindai tag STO yang dipakai bersama oleh halaman Scan (hitung) dan
/// halaman Batal Tag.
///
/// Tiga jalur masuknya kode:
/// 1. kamera perangkat (mobile_scanner),
/// 2. scanner fisik/laser yang mengetik seperti keyboard - ditangkap penerima
///    tombol tersembunyi yang selalu fokus (tanpa memunculkan keyboard layar),
/// 3. ketikan manual sebagai jalur darurat.
class TagScanner extends StatefulWidget {
  const TagScanner({
    super.key,
    required this.onCode,
    this.busy = false,
    this.hint = '',
    this.formats = const [BarcodeFormat.qrCode],
    this.normalisasi,
  });

  /// Format kode yang dipindai. Tag STO memakai QR; Tag OK dari produksi
  /// dicetak sebagai barcode biasa, jadi formatnya bisa berbeda.
  final List<BarcodeFormat> formats;

  /// Cara membaca kode mentah menjadi nomor. Null memakai pola tag STO.
  final String? Function(String? raw)? normalisasi;

  /// Dipanggil dengan nomor tag yang sudah dinormalkan.
  final Future<void> Function(String tagNo) onCode;

  /// true = sedang memproses hasil scan sebelumnya.
  final bool busy;

  final String hint;

  @override
  State<TagScanner> createState() => TagScannerState();
}

class TagScannerState extends State<TagScanner> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: widget.formats,
  );

  final FocusNode _wedgeFocus = FocusNode(debugLabel: 'scanner-wedge');
  final StringBuffer _wedgeBuffer = StringBuffer();
  DateTime? _lastKeyAt;

  final TextEditingController _manualController = TextEditingController();
  final FocusNode _manualFocus = FocusNode();

  String? _lastCode;
  DateTime? _lastScanAt;

  @override
  void initState() {
    super.initState();
    _wedgeFocus.addListener(_onFocusChanged);
    _manualFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _wedgeFocus.removeListener(_onFocusChanged);
    _manualFocus.removeListener(_onFocusChanged);
    _wedgeFocus.dispose();
    _manualController.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- dipakai halaman
  Future<void> pauseCamera() async {
    try {
      await _controller.stop();
    } catch (_) {
      // kamera mungkin memang belum jalan
    }
  }

  Future<void> resumeCamera() async {
    try {
      await _controller.start();
    } catch (_) {
      // scanner fisik & input manual tetap bisa dipakai
    }
  }

  void armWedge() {
    if (!mounted) return;
    _wedgeBuffer.clear();
    if (!_manualFocus.hasFocus) _wedgeFocus.requestFocus();
  }

  // ------------------------------------------------------------- internal
  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Ketikan manusia jauh lebih lambat dari scanner; jeda panjang dianggap
    // awal kode baru supaya sisa karakter lama tidak ikut terbawa.
    final now = DateTime.now();
    if (_lastKeyAt != null &&
        now.difference(_lastKeyAt!) > const Duration(milliseconds: 600)) {
      _wedgeBuffer.clear();
    }
    _lastKeyAt = now;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _wedgeBuffer.toString();
      _wedgeBuffer.clear();
      if (code.trim().isNotEmpty) _emit(code);
      return;
    }

    final character = event.character;
    if (character != null && character.isNotEmpty && character != '\n') {
      _wedgeBuffer.write(character);
    }
  }

  Future<void> _emit(String? raw) async {
    final tagNo = (widget.normalisasi ?? ScanCode.extractTagNo)(raw);
    if (tagNo == null || widget.busy) return;

    // Kamera bisa membaca kode yang sama berkali-kali dalam sedetik.
    final now = DateTime.now();
    if (_lastCode == tagNo &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastCode = tagNo;
    _lastScanAt = now;

    await widget.onCode(tagNo);
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _wedgeFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _manualFocus.unfocus();
          armWedge();
        },
        child: Column(
          children: [
            Expanded(child: _kamera()),
            _panelBawah(),
          ],
        ),
      ),
    );
  }

  Widget _kamera() {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (capture.barcodes.isEmpty) return;
            _emit(capture.barcodes.first.rawValue);
          },
          errorBuilder: (context, error) => _kameraMati(error),
          placeholderBuilder: (context) => Container(
            color: const Color(0xFF14181F),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        if (widget.busy)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _kameraMati(MobileScannerException error) {
    final pesan = error.errorDetails?.message ?? error.errorCode.name;
    return Container(
      color: const Color(0xFF14181F),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white70, size: 46),
            const SizedBox(height: 16),
            const Text(
              'Siap menerima scanner perangkat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kamera tidak bisa dipakai: $pesan. Tekan tombol scan perangkat, '
              'atau ketik nomor tag di bawah.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: resumeCamera,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Coba nyalakan kamera'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                minimumSize: const Size(0, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelBawah() {
    final aktif = _wedgeFocus.hasFocus;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                aktif ? Icons.sensors : Icons.sensors_off,
                size: 16,
                color: aktif ? AppColors.success : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.hint.isNotEmpty
                      ? widget.hint
                      : (aktif
                          ? 'Tombol scan perangkat aktif'
                          : 'Ketuk layar untuk mengaktifkan tombol scan'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  focusNode: _manualFocus,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'atau ketik nomor tag',
                    prefixIcon: Icon(Icons.keyboard_alt_outlined),
                  ),
                  onSubmitted: (value) {
                    _emit(value);
                    _manualController.clear();
                    armWedge();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    _emit(_manualController.text);
                    _manualController.clear();
                    armWedge();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(72, 46),
                  ),
                  child: const Text('CARI'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
