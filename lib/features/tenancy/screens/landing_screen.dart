import 'package:flutter/material.dart';

import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary,
                    child: const Icon(Icons.message, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flow CRM',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'WhatsApp tabanli musteri yonetimi',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (isWide)
                    FilledButton.icon(
                      onPressed: () => _openLogin(context),
                      icon: const Icon(Icons.login),
                      label: const Text('Giris / Kayit'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _HeroCard(isWide: isWide, onLogin: () => _openLogin(context)),
              const SizedBox(height: 24),
              Text(
                'Nasil calisir?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: const [
                  _StepCard(
                    icon: Icons.alternate_email,
                    title: '1. Kayit ol',
                    description:
                        'Kurumsal e-posta ile hesap olustur ve giris yap.',
                  ),
                  _StepCard(
                    icon: Icons.apartment_outlined,
                    title: '2. Tenant eslesmesi',
                    description:
                        'Yonetici seni dogru tenant icine ekler veya onaylar.',
                  ),
                  _StepCard(
                    icon: Icons.tune,
                    title: '3. Yetkiler ve ayarlar',
                    description:
                        'Rolun ve izinlerin tanimlandiktan sonra moduller acilir.',
                  ),
                  _StepCard(
                    icon: Icons.forum_outlined,
                    title: '4. Operasyon baslar',
                    description:
                        'Gelen kutusu, kampanyalar ve bot modulleri aktif olur.',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Neler sunar?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: const [
                  _FeatureCard(
                    icon: Icons.inbox_outlined,
                    title: 'Gelen Kutusu',
                    description:
                        'WhatsApp gorusmelerini tek merkezde yonetin.',
                  ),
                  _FeatureCard(
                    icon: Icons.auto_awesome_outlined,
                    title: 'AI ve Bilgi Bankasi',
                    description:
                        'Otomatik yanitlar ve bilgi bankasi senaryolari.',
                  ),
                  _FeatureCard(
                    icon: Icons.campaign_outlined,
                    title: 'Kampanyalar',
                    description:
                        'Onayli kisilere toplu mesaj ve teklif gonderimi.',
                  ),
                  _FeatureCard(
                    icon: Icons.bar_chart_outlined,
                    title: 'Raporlar',
                    description:
                        'Basari, durum ve ekip performans ozetleri.',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Giris nasil yapilir?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _BulletLine(
                        icon: Icons.check_circle_outline,
                        text:
                            'Kayit olduktan sonra e-posta dogrulamasini tamamla.',
                      ),
                      const SizedBox(height: 8),
                      _BulletLine(
                        icon: Icons.check_circle_outline,
                        text:
                            'Yonetici tarafindan tenant atamasi yapildiginda',
                      ),
                      _BulletLine(
                        icon: Icons.check_circle_outline,
                        text:
                            'giris ekranindan hesabinla sisteme baglan.',
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () => _openLogin(context),
                          icon: const Icon(Icons.login),
                          label: const Text('Giris ekranina git'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isWide) ...[
                const SizedBox(height: 24),
                Center(
                  child: FilledButton.icon(
                    onPressed: () => _openLogin(context),
                    icon: const Icon(Icons.login),
                    label: const Text('Giris / Kayit'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.isWide, required this.onLogin});

  final bool isWide;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            scheme.tertiary,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: isWide
            ? Row(
                children: [
                  Expanded(child: _HeroText(onLogin: onLogin)),
                  const SizedBox(width: 20),
                  const _HeroMock(),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroText(onLogin: onLogin),
                  const SizedBox(height: 20),
                  const _HeroMock(),
                ],
              ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tek panelden WhatsApp operasyonu',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Flow CRM ile gelen kutusu, kampanyalar ve AI destekli yanitlari tek '
          'ekranda yonetin. Multi-tenant yapi sayesinde her musteri kendi '
          'verisini guvenle kullanir.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withOpacity(0.92),
              ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onLogin,
          icon: const Icon(Icons.login),
          label: const Text('Hemen giris yap'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _HeroMock extends StatelessWidget {
  const _HeroMock();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            color: Color(0x22000000),
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _HeroRow(
            icon: Icons.chat_bubble_outline,
            title: 'Gelen Kutusu',
            subtitle: 'Canli gorusmeler',
          ),
          const Divider(height: 24),
          _HeroRow(
            icon: Icons.auto_awesome_outlined,
            title: 'AI Asistani',
            subtitle: 'Akilli yanitlar',
          ),
          const Divider(height: 24),
          _HeroRow(
            icon: Icons.campaign_outlined,
            title: 'Kampanyalar',
            subtitle: 'Hedefli gonderim',
          ),
        ],
      ),
    );
  }
}

class _HeroRow extends StatelessWidget {
  const _HeroRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.tertiary),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
