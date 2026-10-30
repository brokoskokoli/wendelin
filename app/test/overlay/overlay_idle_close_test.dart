import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/overlay/overlay_idle_close.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

class _RefProbe extends ConsumerWidget {
  const _RefProbe({required this.onBuild});
  final void Function(WidgetRef) onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onBuild(ref);
    return const SizedBox();
  }
}

void main() {
  group('nothingLeftToDo (WP186)', () {
    testWidgets(
      'blockiert wenn followUp aktiv ist, selbst wenn phase idle ist',
      (tester) async {
        late WidgetRef capturedRef;
        await tester.pumpWidget(
          ProviderScope(child: _RefProbe(onBuild: (ref) => capturedRef = ref)),
        );

        final voice = capturedRef.read(voiceControllerProvider.notifier);
        voice.seed(
          VoiceUiState(
            phase: VoiceState.idle,
            followUpUntil: DateTime.now().add(const Duration(seconds: 5)),
            followUpWindow: const Duration(seconds: 5),
          ),
        );
        await tester.pump();
        expect(
          nothingLeftToDo(capturedRef, locked: false, unlocking: false),
          isFalse,
          reason: 'followUp muss Schliessen blockieren',
        );

        voice.seed(const VoiceUiState(phase: VoiceState.idle));
        await tester.pump();
        expect(
          nothingLeftToDo(capturedRef, locked: false, unlocking: false),
          isTrue,
        );
      },
    );
  });

  group('IdleCloser followUp Listener (WP186)', () {
    testWidgets('schliesst wenn followUp endet (was=true, now=false)', (
      tester,
    ) async {
      final closes = <String>[];
      late WidgetRef capturedRef;
      IdleCloser? closer;

      await tester.pumpWidget(
        ProviderScope(
          child: _RefProbe(
            onBuild: (ref) {
              capturedRef = ref;
              closer ??= IdleCloser(
                ref: ref,
                enabled: () => true,
                typing: () => false,
                closing: () => false,
                locked: () => false,
                unlocking: () => false,
                close: (by) => closes.add(by),
                stopCloseDelay: () => Duration.zero,
                onListening: () {},
              );
              closer!.listen();
            },
          ),
        ),
      );

      final voice = capturedRef.read(voiceControllerProvider.notifier);

      // followUp wird aktiv (was=false, now=true): schliesst nicht
      voice.seed(
        VoiceUiState(
          phase: VoiceState.idle,
          followUpUntil: DateTime.now().add(const Duration(seconds: 5)),
          followUpWindow: const Duration(seconds: 5),
        ),
      );
      await tester.pump();
      expect(closes, isEmpty);

      // followUp bleibt aktiv (was=true, now=true): schliesst nicht
      voice.seed(
        VoiceUiState(
          phase: VoiceState.idle,
          followUpUntil: DateTime.now().add(const Duration(seconds: 4)),
          followUpWindow: const Duration(seconds: 5),
        ),
      );
      await tester.pump();
      expect(closes, isEmpty);

      // followUp endet (was=true, now=false): schliesst per idle
      voice.seed(const VoiceUiState(phase: VoiceState.idle));
      await tester.pump();
      expect(closes, ['idle']);
    });
  });
}
