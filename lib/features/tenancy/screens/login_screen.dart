import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_links.dart';
import '../providers/tenant_providers.dart';
import 'password_reset_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabınız')),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
                child: Form(
              key: _formKey,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_open_outlined,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Hesap girişi',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                        'İşletme hesabınıza e-posta ve şifrenizle giriş yapın.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        readOnly: _loading,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        validator: _validateEmail,
                        decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.alternate_email))),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        readOnly: _loading,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _authenticate(signUp: false),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Şifrenizi girin.'
                            : null,
                        decoration: InputDecoration(
                            labelText: 'Şifre',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Şifreyi gizle'
                                    : 'Şifreyi göster',
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                                icon: Icon(_showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined)))),
                    if (AppLinks.privacyPolicyUrl.isNotEmpty)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                              onPressed: () => launchUrl(
                                  Uri.parse(AppLinks.privacyPolicyUrl),
                                  mode: LaunchMode.externalApplication),
                              child: const Text('Gizlilik politikası'))),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => PasswordResetScreen(
                                            initialEmail:
                                                _emailController.text.trim()))),
                            child: const Text('Şifremi unuttum'))),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 12),
                      Semantics(liveRegion: true, child: Text(_notice!)),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton(
                              onPressed: _loading
                                  ? null
                                  : () => _authenticate(signUp: true),
                              child: const Text('Kayıt ol')),
                          FilledButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _authenticate(signUp: false),
                              icon: _loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.login, size: 18),
                              label: const Text('Giriş yap')),
                        ]),
                  ]),
            )),
          )),
        ),
      ))),
    );
  }

  Future<void> _authenticate({required bool signUp}) async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      final focus = _validateEmail(_emailController.text) == null
          ? _passwordFocus
          : _emailFocus;
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
        final confirmationRequired = await controller.signUp(
            _emailController.text.trim(), _passwordController.text);
        if (mounted && confirmationRequired) {
          setState(() => _notice =
              'E-posta doğrulaması gerekiyorsa gelen kutunuzdaki bağlantıyı açın. Ardından giriş yapabilirsiniz.');
        }
      } else {
        await controller.login(
            _emailController.text.trim(), _passwordController.text);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _authError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? value) =>
      value == null || value.trim().isEmpty || !value.contains('@')
          ? 'E-posta adresinizi girin.'
          : null;

  String _authError(Object error) {
    if (error is! AuthException) {
      return 'Bağlantı kurulamadı. Bilgileriniz korundu, tekrar deneyebilirsiniz.';
    }
    return switch (error.code) {
      'invalid_credentials' =>
        'E-posta veya şifre hatalı. Bilgilerinizi kontrol edin.',
      'email_not_confirmed' =>
        'Giriş yapmadan önce e-posta adresinizi doğrulayın.',
      'weak_password' =>
        'Şifre güvenlik koşullarını karşılamıyor. Daha uzun ve güçlü bir şifre seçin.',
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' =>
        'Çok fazla istek gönderildi. Bir süre bekleyip tekrar deneyin.',
      'signup_disabled' => 'Yeni hesap kaydı şu anda kullanılamıyor.',
      _ => 'İşlem tamamlanamadı. Bilgilerinizi kontrol edip tekrar deneyin.',
    };
  }
}
