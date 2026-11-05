import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ui/ui.dart';
import '../../onboarding/widgets/auth_frame.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import '../providers/tenant_providers.dart';

/// Two-step password recovery with an emailed one-time code, so it works in the
/// mobile app without deep links. Requires the recovery email template to
/// include `{{ .Token }}` (see docs/AUTH_ONBOARDING.md).
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  bool _showPassword = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    return AuthFrame(
      heroTitle: 'Yeni şifre, iki adımda.',
      heroEyebrow: 'Şifre sıfırlama',
      heroLine: 'E-postanıza gelen kodla şifrenizi yenileyin. Sohbetleriniz ve ayarlarınız yerinde kalır.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EntranceRise(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StepBars(count: 2, index: _codeSent ? 1 : 0),
                    const SizedBox(width: FlowSpace.md),
                    Flexible(
                      child: Eyebrow(_codeSent ? '02 / 02 · Yeni şifre' : '01 / 02 · Kod isteyin'),
                    ),
                  ]),
                  const SizedBox(height: FlowSpace.md),
                  Semantics(
                    header: true,
                    child: Text(
                      _codeSent ? 'Kodu ve yeni şifrenizi girin' : 'Şifrenizi sıfırlayın',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: FlowSpace.sm),
                  Text(
                    _codeSent
                        ? 'E-postanıza gelen 6 haneli kodu ve yeni şifrenizi girin.'
                        : 'Hesabınızın e-posta adresini girin; size bir doğrulama kodu gönderelim.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                ]),
              ),
              const SizedBox(height: FlowSpace.xl),
              TextFormField(
                controller: _emailController,
                readOnly: _loading || _codeSent,
                keyboardType: TextInputType.emailAddress,
                textInputAction: _codeSent ? TextInputAction.next : TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                onFieldSubmitted: (_) {
                  if (!_codeSent) _sendCode();
                },
                validator: (value) => value == null || !value.contains('@') ? 'E-posta adresinizi girin.' : null,
                decoration: const InputDecoration(
                  labelText: 'E-posta',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              if (_codeSent) ...[
                const SizedBox(height: FlowSpace.md),
                TextFormField(
                  controller: _codeController,
                  readOnly: _loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 10,
                  style: FlowText.mono(context, size: 16, color: c.text),
                  validator: (value) =>
                      RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '') ? null : 'E-postadaki kodu girin.',
                  decoration: const InputDecoration(
                    labelText: 'Doğrulama kodu',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: FlowSpace.xs),
                TextFormField(
                  controller: _passwordController,
                  readOnly: _loading,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _complete(),
                  validator: (value) => (value?.length ?? 0) < 8 ? 'En az 8 karakterlik bir şifre seçin.' : null,
                  decoration: InputDecoration(
                    labelText: 'Yeni şifre',
                    helperText: 'En az 8 karakter.',
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
              ],
              const SizedBox(height: FlowSpace.lg),
              if (_error != null) ...[
                InlineNotice(_error!),
                const SizedBox(height: FlowSpace.md),
              ],
              if (_notice != null) ...[
                InlineNotice(_notice!, tone: FlowTone.info),
                const SizedBox(height: FlowSpace.md),
              ],
              FilledButton(
                onPressed: _loading ? null : (_codeSent ? _complete : _sendCode),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_codeSent ? 'Şifreyi değiştir' : 'Kod gönder'),
              ),
              if (_codeSent) ...[
                const SizedBox(height: FlowSpace.sm),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: FlowSpace.xs,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : _changeEmail,
                      child: const Text('Başka bir e-posta kullan'),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _sendCode,
                      child: const Text('Kodu tekrar gönder'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _changeEmail() {
    setState(() {
      _codeSent = false;
      _error = null;
      _notice = null;
      _codeController.clear();
    });
  }

  Future<void> _sendCode() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
      if (!mounted) return;
      // The same notice is shown whether or not the address has an account.
      setState(() {
        _codeSent = true;
        _notice =
            'Bu adresle bir hesap varsa doğrulama kodu gönderildi. Gelen kutunuzu ve istenmeyen klasörünü kontrol edin.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = passwordResetError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _complete() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).completePasswordReset(
            email: _emailController.text,
            code: _codeController.text,
            newPassword: _passwordController.text,
          );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) setState(() => _error = passwordResetError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

String passwordResetError(Object error) {
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  if (error is! AuthException) {
    return 'İşlem tamamlanamadı. Tekrar deneyin.';
  }
  return switch (error.code) {
    'otp_expired' || 'invalid_credentials' || 'session_unavailable' =>
      'Kod hatalı veya süresi dolmuş. Yeni bir kod isteyin.',
    'weak_password' => 'Şifre güvenlik koşullarını karşılamıyor. Daha uzun ve güçlü bir şifre seçin.',
    'same_password' => 'Yeni şifre eskisinden farklı olmalı.',
    'over_request_rate_limit' || 'over_email_send_rate_limit' =>
      'Çok fazla istek gönderildi. Bir süre bekleyip tekrar deneyin.',
    _ => 'İşlem tamamlanamadı. Bilgilerinizi kontrol edip tekrar deneyin.',
  };
}
