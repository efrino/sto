import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Umpan balik suara + getar. Di area produksi yang bising, operator lebih
/// mengandalkan bunyi/getar daripada melihat layar.
class SoundService {
  SoundService({this.enabled = true});

  bool enabled;

  final AudioPlayer _player = AudioPlayer();

  Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await _play('sounds/succeed.mp3');
  }

  Future<void> beep() async {
    await HapticFeedback.selectionClick();
    await _play('sounds/beep.mp3');
  }

  Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await _play('sounds/beep.mp3');
  }

  Future<void> _play(String asset) async {
    if (!enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {
      // Perangkat tanpa audio - abaikan, getar sudah cukup.
    }
  }

  void dispose() => _player.dispose();
}
