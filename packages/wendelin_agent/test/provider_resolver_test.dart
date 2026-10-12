import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

ProviderTarget target(String id, PrivacyLevel privacy, {String model = 'm'}) =>
    ProviderTarget(
      profileId: id,
      modelId: model,
      provider: FakeLlmProvider(const []),
      privacy: privacy,
    );

void main() {
  final tee = target('phala', PrivacyLevel.tee);
  final std = target('claude', PrivacyLevel.standard);
  final local = target('ollama', PrivacyLevel.local);
  final input = UserInput(text: 'Hallo');
  final privateInput = UserInput(text: 'privat: Hallo');
  bool isPrivate(UserInput i) => i.text.startsWith('privat');

  test('resolve returns the default target', () {
    final r = DefaultProviderResolver(tee, [std]).resolve(input);
    expect(r.target, same(tee));
    expect(r.profileId, 'phala');
    expect(r.modelId, 'm');
    expect(r.provider, same(tee.provider));
    expect(r.privacy, PrivacyLevel.tee);
    expect(r.reason, 'Standard');
    expect(r.privacyFloor, isNull);
    expect(r.belowPrivacyFloor, isFalse);
    expect(r.toString(), contains('phala'));
    expect(tee.toString(), contains('tee'));
  });

  test('escalate walks the chain and ends with null', () {
    final resolver = DefaultProviderResolver(tee, [std, local]);
    final r1 = resolver.resolve(input);
    final r2 = resolver.escalate(r1, EscalationReason.providerError)!;
    expect(r2.profileId, 'claude');
    expect(r2.reason, 'Eskalation: providerError');
    final r3 = resolver.escalate(r2, EscalationReason.noProgress)!;
    expect(r3.profileId, 'ollama');
    expect(resolver.escalate(r3, EscalationReason.noProgress), isNull);
  });

  test('private request: floor is the default level', () {
    final r = DefaultProviderResolver(tee, [
      std,
    ], isPrivate: isPrivate).resolve(privateInput);
    expect(r.reason, 'Privat');
    expect(r.privacyFloor, PrivacyLevel.tee);
  });

  test('private request prefers a compliant target further down the chain', () {
    final resolver = DefaultProviderResolver(tee, [
      std,
      local,
    ], isPrivate: isPrivate);
    final next = resolver.escalate(
      resolver.resolve(privateInput),
      EscalationReason.providerError,
    )!;
    expect(next.profileId, 'ollama');
    expect(next.belowPrivacyFloor, isFalse);
    expect(next.privacyFloor, PrivacyLevel.tee);
  });

  test('tee → standard is flagged below the privacy floor', () {
    final resolver = DefaultProviderResolver(tee, [std], isPrivate: isPrivate);
    final next = resolver.escalate(
      resolver.resolve(privateInput),
      EscalationReason.providerError,
    )!;
    expect(next.profileId, 'claude');
    expect(next.belowPrivacyFloor, isTrue);
  });

  test('below the floor the first remaining target wins', () {
    final std2 = target('openai', PrivacyLevel.standard);
    final eu = target('mistral', PrivacyLevel.eu);
    final resolver = DefaultProviderResolver(tee, [
      std,
      eu,
      std2,
    ], isPrivate: isPrivate);
    final next = resolver.escalate(
      resolver.resolve(privateInput),
      EscalationReason.providerError,
    )!;
    expect(next.profileId, 'claude');
    expect(next.belowPrivacyFloor, isTrue);
  });

  test('non-private request may escalate to a lower level', () {
    final resolver = DefaultProviderResolver(tee, [std], isPrivate: isPrivate);
    final next = resolver.escalate(
      resolver.resolve(input),
      EscalationReason.providerError,
    )!;
    expect(next.belowPrivacyFloor, isFalse);
  });

  test('current target outside the chain escalates to the first other', () {
    final resolver = DefaultProviderResolver(tee, [std]);
    final foreign = Resolution(target: local, reason: 'Regel');
    expect(
      resolver.escalate(foreign, EscalationReason.userRequested)!.profileId,
      'phala',
    );
  });

  test('same profile with another model is a separate link', () {
    final small = target('claude', PrivacyLevel.standard, model: 'haiku');
    final big = target('claude', PrivacyLevel.standard, model: 'sonnet');
    final resolver = DefaultProviderResolver(small, [big]);
    final next = resolver.escalate(
      resolver.resolve(input),
      EscalationReason.modelGaveUp,
    )!;
    expect(next.modelId, 'sonnet');
  });
}
