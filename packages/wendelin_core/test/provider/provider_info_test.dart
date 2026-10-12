import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('ModelInfo', () {
    test('displayName defaults to id', () {
      expect(const ModelInfo(id: 'm').displayName, 'm');
      expect(const ModelInfo(id: 'm', displayName: 'M').displayName, 'M');
    });
    test('equality per field', () {
      const a = ModelInfo(
        id: 'm',
        contextWindow: 1,
        supportsTools: true,
        supportsVision: false,
      );
      expect(
        a,
        const ModelInfo(
          id: 'm',
          contextWindow: 1,
          supportsTools: true,
          supportsVision: false,
        ),
      );
      expect(a.hashCode, isNot(const ModelInfo(id: 'x').hashCode));
      expect(
        a,
        isNot(
          const ModelInfo(
            id: 'n',
            contextWindow: 1,
            supportsTools: true,
            supportsVision: false,
          ),
        ),
      );
      expect(
        a,
        isNot(
          const ModelInfo(
            id: 'm',
            displayName: 'D',
            contextWindow: 1,
            supportsTools: true,
            supportsVision: false,
          ),
        ),
      );
      expect(
        a,
        isNot(
          const ModelInfo(
            id: 'm',
            contextWindow: 2,
            supportsTools: true,
            supportsVision: false,
          ),
        ),
      );
      expect(
        a,
        isNot(
          const ModelInfo(
            id: 'm',
            contextWindow: 1,
            supportsTools: false,
            supportsVision: false,
          ),
        ),
      );
      expect(
        a,
        isNot(
          const ModelInfo(
            id: 'm',
            contextWindow: 1,
            supportsTools: true,
            supportsVision: true,
          ),
        ),
      );
      expect(a.toString(), contains('m'));
    });
  });

  group('HealthCheck', () {
    HealthCheck h({
      bool ok = true,
      int ms = 5,
      String msg = 'ok',
      List<ModelInfo>? models,
      ProviderCapabilities? detected,
    }) => HealthCheck(
      ok: ok,
      latency: Duration(milliseconds: ms),
      message: msg,
      models: models,
      detected: detected,
    );

    test('equality per field', () {
      expect(h(), h());
      expect(h().hashCode, h().hashCode);
      expect(
        h(models: const [ModelInfo(id: 'a')]),
        h(models: const [ModelInfo(id: 'a')]),
      );
      expect(h(), isNot(h(ok: false)));
      expect(h(), isNot(h(ms: 6)));
      expect(h(), isNot(h(msg: 'x')));
      expect(h(), isNot(h(models: const [])));
      expect(
        h(detected: const ProviderCapabilities(tools: true)),
        h(detected: const ProviderCapabilities(tools: true)),
      );
      expect(h(), isNot(h(detected: const ProviderCapabilities())));
      expect(
        h(detected: const ProviderCapabilities(tools: true)),
        isNot(h(detected: const ProviderCapabilities())),
      );
      expect(h().toString(), contains('ok'));
    });

    test('models are unmodifiable', () {
      expect(
        () =>
            h(models: [const ModelInfo(id: 'a')]).models!
                .add(const ModelInfo(id: 'b')),
        throwsUnsupportedError,
      );
      expect(h().models, isNull);
    });
  });

  group('ProviderCapabilities', () {
    test('defaults false, equality per flag', () {
      const none = ProviderCapabilities();
      expect([
        none.tools,
        none.vision,
        none.streaming,
        none.promptCaching,
        none.tee,
      ], everyElement(isFalse));
      expect(none, const ProviderCapabilities());
      expect(none.hashCode, const ProviderCapabilities().hashCode);
      expect(none, isNot(const ProviderCapabilities(tools: true)));
      expect(none, isNot(const ProviderCapabilities(vision: true)));
      expect(none, isNot(const ProviderCapabilities(streaming: true)));
      expect(none, isNot(const ProviderCapabilities(promptCaching: true)));
      expect(none, isNot(const ProviderCapabilities(tee: true)));
      expect(none.toString(), contains('tee: false'));
    });
  });
}
