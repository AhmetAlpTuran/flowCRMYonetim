import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_links.dart';
import '../../../ui/ui.dart';
import '../../onboarding/widgets/auth_frame.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import '../providers/tenant_providers.dart';
import 'password_reset_screen.dart';

/// Sign-in and sign-up with email and password. Successful session events return a
/// pushed route to the root, where [AppEntry] routes the signed-in user.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.startWithSignUp = false});

  /// Opens on the sign-up form (the welcome's "İşletmeni oluştur").
  final bool startWithSignUp;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late bool _signUp = widget.startWithSignUp;
  String? _error;
  String? _notice;
  bool _loading = false;
  bool _showPassword = false;
  bool _navigating = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.valueOrNull == null || _navigating) return;
      _navigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    });
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    return AuthFrame(
      heroTitle: _signUp ? 'Müşterileriniz yanıtsız kalmasın.' : 'Tekrar hoş geldiniz.',
      heroEyebrow: '7/24 yanıt',
      heroLine: _signUp
          ? 'Hesabınızı açın, işletmenizi kurun. Asistanınız müşterilerinize gece gündüz yanıt versin.'
          : 'Sohbetleriniz, ekibiniz ve asistanınız tek ekranda. Kaldığınız yerden devam edin.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EntranceRise(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text(_signUp ? 'Hesap oluşturun' : 'Giriş yap', style: theme.textTheme.headlineLarge),
                  ),
                  const SizedBox(height: FlowSpace.sm),
                  Text(
                    _signUp
                        ? 'Önce hesabınızı açın, ardından işletmenizi oluşturun. İlk 14 gün ücretsiz.'
                        : 'İşletmenizin sohbetlerine kaldığınız yerden devam edin.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                ]),
              ),
              const SizedBox(height: FlowSpace.xl),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
                readOnly: _loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: _validateEmail,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'E-posta',
                  hintText: 'ornek@isletmeniz.com',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: FlowSpace.md),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                readOnly: _loading,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _authenticate(signUp: _signUp),
                validator: (value) => value == null || value.isEmpty ? 'Şifrenizi girin.' : null,
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: FlowSpace.xs),
                    child: TextButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      style: TextButton.styleFrom(foregroundColor: c.muted),
                      child: Text(
                        _showPassword ? 'Gizle' : 'Göster',
                        semanticsLabel: _showPassword ? 'Şifreyi gizle' : 'Şifreyi göster',
                      ),
                    ),
                  ),
                ),
              ),
              if (!_signUp)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => PasswordResetScreen(initialEmail: _emailController.text.trim()),
                            )),
                    child: const Text('Şifremi unuttum'),
                  ),
                )
              else
                const SizedBox(height: FlowSpace.md),
              if (_error != null) ...[
                InlineNotice(_error!),
                const SizedBox(height: FlowSpace.md),
              ],
              if (_notice != null) ...[
                InlineNotice(_notice!, tone: FlowTone.info),
                const SizedBox(height: FlowSpace.md),
              ],
              const SizedBox(height: FlowSpace.xs),
              FilledButton(
                onPressed: _loading ? null : () => _authenticate(signUp: _signUp),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_signUp ? 'Kayıt ol' : 'Giriş yap'),
              ),
              const SizedBox(height: FlowSpace.lg),
              const OrDivider(),
              const SizedBox(height: FlowSpace.lg),
              OutlinedButton(
                onPressed: _loading ? null : () => _switchMode(!_signUp),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg, vertical: 10),
                ),
                child: Text(
                  _signUp ? 'Zaten hesabım var · Giriş yap' : 'İşletmenizi oluşturun · 14 gün ücretsiz',
                  textAlign: TextAlign.center,
                ),
              ),
              if (AppLinks.privacyPolicyUrl.isNotEmpty) ...[
                const SizedBox(height: FlowSpace.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Kişisel verileriniz', style: theme.textTheme.bodySmall?.copyWith(color: c.faint)),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(AppLinks.privacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 44),
                        textStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Gizlilik politikası'),
                    ),
                    Text('kapsamında işlenir.', style: theme.textTheme.bodySmall?.copyWith(color: c.faint)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _switchMode(bool signUp) {
    setState(() {
      _signUp = signUp;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _authenticate({required bool signUp}) async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      final focus = _validateEmail(_emailController.text) == null ? _passwordFocus : _emailFocus;
      focus.requestFocus();
      return;
    }
    setState(() {
      _error = null;
      _notice = null;
      _loading = true;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      if (signUp) {
        final confirmationRequired =
            await controller.signUp(_emailController.text.trim(), _passwordController.text);
        if (mounted && confirmationRequired) {
          // The account exists but has no session yet: sign-in is the next step.
          setState(() {
            _signUp = false;
            _notice =
                'E-posta doğrulaması gerekiyorsa gelen kutunuzdaki bağlantıyı açın. Ardından giriş yapabilirsiniz.';
          });
        }
      } else {
        await controller.login(_emailController.text.trim(), _passwordController.text);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _authError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? value) =>
      value == null || value.trim().isEmpty || !value.contains('@') ? 'E-posta adresinizi girin.' : null;

  String _authError(Object error) {
    if (error is! AuthException) {
      return 'Bağlantı kurulamadı. Bilgileriniz korundu, tekrar deneyebilirsiniz.';
    }
    return switch (error.code) {
      'invalid_credentials' => 'E-posta veya şifre hatalı. Bilgilerinizi kontrol edin.',
      'email_not_confirmed' => 'Giriş yapmadan önce e-posta adresinizi doğrulayın.',
      'weak_password' => 'Şifre güvenlik koşullarını karşılamıyor. Daha uzun ve güçlü bir şifre seçin.',
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' =>
        'Çok fazla istek gönderildi. Bir süre bekleyip tekrar deneyin.',
      'signup_disabled' => 'Yeni hesap kaydı şu anda kullanılamıyor.',
      _ => 'İşlem tamamlanamadı. Bilgilerinizi kontrol edip tekrar deneyin.',
    };
  }
}
