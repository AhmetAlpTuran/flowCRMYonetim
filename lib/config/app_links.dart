/// Public links, overridable at build time per environment:
///
///   --dart-define=PRIVACY_POLICY_URL=https://example.com/gizlilik
///   --dart-define=SUPPORT_EMAIL=destek@example.com
///
/// The privacy policy defaults to the page published from `docs/gizlilik/` with
/// GitHub Pages (see docs/RELEASE.md). An empty value hides a link.
class AppLinks {
  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://ahmetalpturan.github.io/flowCRMYonetim/gizlilik/',
  );
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
