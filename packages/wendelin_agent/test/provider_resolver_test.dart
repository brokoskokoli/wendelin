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
  final input = UserInput(text: 'Hallo');
  final privateInput = UserInput(text: 'privat: Hallo');
  bool isPrivate(UserInput i) => i.text.startsWith('privat');

  test('resolve returns the default target', () {
    final r = DefaultProviderResolver(tee).resolve(input);
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

  test('private request: floor is the default level', () {
    final r = DefaultProviderResolver(
      tee,
      isPrivate: isPrivate,
    ).resolve(privateInput);
    expect(r.reason, 'Privat');
    expect(r.privacyFloor, PrivacyLevel.tee);
  });

  test('no automatic target: nothing to escalate to (K28)', () {
    final resolver = DefaultProviderResolver(tee, isPrivate: isPrivate);
    expect(
      resolver.escalate(
        resolver.resolve(input),
        EscalationReason.userRequested,
      ),
      isNull,
    );
  });

  test('displayName falls back to the profile id', () {
    expect(tee.displayName, 'phala');
    final named = ProviderTarget(
      profileId: 'claude',
      modelId: 'm',
      provider: FakeLlmProvider(const []),
      privacy: PrivacyLevel.standard,
      name: 'Claude',
    );
    expect(named.displayName, 'Claude');
  });
}
