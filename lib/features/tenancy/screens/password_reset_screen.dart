import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/tenant_providers.dart';

/// Two-step password recovery with an emailed one-time code, so it works in the
/// mobile app without deep links. Requires the recovery email template to
/// include `{{ .Token }}` (see docs/AUTH_ONBOARDING.md).
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre sıfırlama')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _codeSent
                              ? 'E-postanıza gelen 6 haneli kodu ve yeni şifrenizi girin.'
                              : 'Hesabınızın e-posta adresini girin; size bir doğrulama kodu gönderelim.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          readOnly: _loading || _codeSent,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          validator: (value) =>
                              value == null || !value.contains('@')
                                  ? 'E-posta adresinizi girin.'
                                  : null,
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                        ),
                        if (_codeSent) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _codeController,
                            readOnly: _loading,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            maxLength: 10,
                            validator: (value) =>
                                RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'E-postadaki kodu girin.',
                            decoration: const InputDecoration(
                              labelText: 'Doğrulama kodu',
                              prefixIcon: Icon(Icons.pin_outlined),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _passwordController,
                            readOnly: _loading,
                            obscureText: !_showPassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: (value) => (value?.length ?? 0) < 8
                                ? 'En az 8 karakterlik bir şifre seçin.'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Yeni şifre',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Şifreyi gizle'
                                    : 'Şifreyi göster',
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                                icon: Icon(_showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 12),
                          Semantics(liveRegion: true, child: Text(_notice!)),
                        ],
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (_codeSent)
                              TextButton(
                                onPressed: _loading ? null : _sendCode,
                                child: const Text('Kodu tekrar gönder'),
                              ),
                            FilledButton(
                              onPressed: _loading
                                  ? null
                                  : (_codeSent ? _complete : _sendCode),
                              child: _loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(_codeSent
                                      ? 'Şifreyi değiştir'
                                      : 'Kod gönder'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    'weak_password' =>
      'Şifre güvenlik koşullarını karşılamıyor. Daha uzun ve güçlü bir şifre seçin.',
    'same_password' => 'Yeni şifre eskisinden farklı olmalı.',
    'over_request_rate_limit' || 'over_email_send_rate_limit' =>
      'Çok fazla istek gönderildi. Bir süre bekleyip tekrar deneyin.',
    _ => 'İşlem tamamlanamadı. Bilgilerinizi kontrol edip tekrar deneyin.',
  };
}
