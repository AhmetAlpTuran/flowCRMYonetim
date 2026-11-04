/// Public links, supplied at build time so each environment can point to its own
/// hosted pages:
///
///   --dart-define=PRIVACY_POLICY_URL=https://example.com/gizlilik
///   --dart-define=SUPPORT_EMAIL=destek@example.com
///
/// An empty value hides the corresponding link. Store submissions require a
/// privacy policy URL (see docs/RELEASE.md).
class AppLinks {
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
