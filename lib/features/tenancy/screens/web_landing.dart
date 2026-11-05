import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_links.dart';
import '../../../ui/ui.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import 'login_screen.dart';

/// The web landing: one screen of cards ("bento"). Each card opens its details in a
/// panel (a bottom sheet on narrow screens, a side panel on wide ones), so the page
/// itself never becomes a long scroll.
class WebLanding extends StatelessWidget {
  const WebLanding({super.key});

  /// From this viewport size the bento fits the screen without scrolling.
  static const double roomyWidth = 1024;
  static const double roomyHeight = 700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final roomy = constraints.maxWidth >= roomyWidth && constraints.maxHeight >= roomyHeight;
          return roomy ? const _RoomyLanding() : const _CompactLanding();
        }),
      ),
    );
  }
}

void _openSignUp(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen(startWithSignUp: true)),
    );

void _openSignIn(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );

enum _Panel {
  howItWorks('Nasıl çalışır', 'Üç adımda kurulur, ilk geceden çalışır.', 'Üç adımda kurulum', Icons.route_outlined),
  features('Özellikler', 'Müşteri yazdığı an, ekip ve asistan aynı ekranda.', 'Gelen kutusu, asistan, katalog',
      Icons.dashboard_outlined),
  sectors('Sektörler', 'İşinizin dilini bilen hazır paketler.', 'Oto galeri, konaklama, randevu',
      Icons.storefront_outlined),
  pricing('Fiyatlar', 'Sade fiyat, sürpriz yok.', '1.490 ₺’den, aylık', Icons.sell_outlined),
  security('Güvenlik ve KVKK', 'Müşteri verisi sizindir, sizde kalır.', 'Her işletmenin verisi ayrı',
      Icons.shield_outlined);

  const _Panel(this.label, this.title, this.hint, this.icon);

  final String label;
  final String title;
  final String hint;
  final IconData icon;
}

/// Opens a panel: a bottom sheet up to 90% tall on narrow screens, a right-hand side
/// panel (at most 560 px) on wide ones.
Future<void> _showPanel(BuildContext context, _Panel panel) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < 720) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: size.height * 0.9),
      builder: (context) => _PanelBody(panel: panel, fill: false),
    );
  }
  final reduced = FlowMotion.reduced(context);
  final scrim = Theme.of(context).colorScheme.scrim.withValues(alpha: 0.55);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: scrim,
    transitionDuration: reduced ? Duration.zero : FlowMotion.entrance,
    pageBuilder: (context, _, __) {
      final c = FlowColors.of(context);
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(560, size.width),
          height: double.infinity,
          child: Material(
            color: c.surface,
            shape: Border(left: BorderSide(color: c.border)),
            child: SafeArea(left: false, child: _PanelBody(panel: panel, fill: true)),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: FlowMotion.curve)),
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Layouts

class _RoomyLanding extends StatelessWidget {
  const _RoomyLanding();

  @override
  Widget build(BuildContext context) {
    final gutter = FlowSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, FlowSpace.lg, gutter, FlowSpace.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(showTrial: true),
              SizedBox(height: FlowSpace.lg),
              Expanded(child: _BentoGrid()),
              SizedBox(height: FlowSpace.xs),
              _Footer(showSecurity: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _BentoGrid extends StatelessWidget {
  const _BentoGrid();

  static const double gap = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final column = (constraints.maxWidth - gap * 11) / 12;
      double span(int columns) => column * columns + gap * (columns - 1);
      final bottomHeight = (constraints.maxHeight * 0.36).clamp(176.0, 240.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: span(7), child: const _HeroCard()),
            const SizedBox(width: gap),
            SizedBox(width: span(5), child: const _DemoCard()),
          ]),
        ),
        const SizedBox(height: gap),
        SizedBox(
          height: bottomHeight,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: span(6), child: const _FeaturesCard()),
            const SizedBox(width: gap),
            SizedBox(width: span(3), child: const _PricingCard()),
            const SizedBox(width: gap),
            SizedBox(width: span(3), child: const _SectorsCard()),
          ]),
        ),
      ]);
    });
  }
}

class _CompactLanding extends StatelessWidget {
  const _CompactLanding();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final gutter = constraints.maxWidth < 600 ? FlowSpace.lg : FlowSpace.xl;
      // The hero fills most of the first screen and leaves the next card peeking.
      final heroMinHeight = math.max(0.0, constraints.maxHeight * 0.78 - 60);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, FlowSpace.sm, gutter, FlowSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(showTrial: constraints.maxWidth >= 600),
                const SizedBox(height: FlowSpace.md),
                _HeroCard(minHeight: heroMinHeight),
                const SizedBox(height: FlowSpace.md),
                const _DemoCard(),
                const SizedBox(height: FlowSpace.md),
                const _CompactGrid(),
                const SizedBox(height: FlowSpace.lg),
                const _Footer(showSecurity: false),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _CompactGrid extends StatelessWidget {
  const _CompactGrid();

  @override
  Widget build(BuildContext context) {
    const panels = _Panel.values;
    const gap = FlowSpace.md;
    final rows = <Widget>[];
    for (var i = 0; i < panels.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      if (i + 1 < panels.length) {
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _CompactTile(panels[i])),
            const SizedBox(width: gap),
            Expanded(child: _CompactTile(panels[i + 1])),
          ]),
        ));
      } else {
        rows.add(_CompactTile(panels[i]));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile(this.panel);

  final _Panel panel;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return _TapCard(
      label: '${panel.label}: ${panel.hint}',
      onTap: () => _showPanel(context, panel),
      padding: const EdgeInsets.all(FlowSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _IconBox(panel.icon),
        const SizedBox(height: FlowSpace.md),
        Text(panel.label, style: theme.textTheme.titleMedium),
        const SizedBox(height: FlowSpace.xs),
        Text(
          panel.hint,
          style: panel == _Panel.pricing
              ? FlowText.mono(context, size: 12)
              : theme.textTheme.bodySmall?.copyWith(color: c.muted),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showTrial});

  final bool showTrial;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        const FlowLogo(size: 26),
        const SizedBox(width: FlowSpace.md),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(onPressed: () => _openSignIn(context), child: const Text('Giriş yap')),
                if (showTrial)
                  FilledButton(onPressed: () => _openSignUp(context), child: const Text('Ücretsiz dene')),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.showSecurity});

  final bool showSecurity;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final linkStyle = TextButton.styleFrom(
      foregroundColor: c.muted,
      textStyle: Theme.of(context).textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.sm),
    );
    return Wrap(
      spacing: FlowSpace.md,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('© ${DateTime.now().year} FLOW CRM', style: FlowText.caps(context, color: c.faint)),
        if (showSecurity)
          TextButton(
            onPressed: () => _showPanel(context, _Panel.security),
            style: linkStyle,
            child: const Text('Güvenlik ve KVKK'),
          ),
        if (AppLinks.privacyPolicyUrl.isNotEmpty)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(AppLinks.privacyPolicyUrl), mode: LaunchMode.externalApplication),
            style: linkStyle,
            child: const Text('Gizlilik politikası'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cards

/// Lays [child] out at its natural height and scales it down only when the card is
/// too short, so a fixed-height bento card never overflows (large text, small
/// windows). In a scroll view it is a no-op.
class _FitHeight extends StatelessWidget {
  const _FitHeight({required this.child, this.alignment = Alignment.topLeft});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedHeight) return child;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: constraints.maxWidth, child: child),
      );
    });
  }
}

/// A card that opens something: the whole surface is one button.
class _TapCard extends StatelessWidget {
  const _TapCard({
    required this.child,
    required this.onTap,
    required this.label,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final VoidCallback onTap;
  final String label;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {this.assistant = false, this.size = 36});

  final IconData icon;
  final bool assistant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: assistant ? c.tealSoft : c.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.5, color: assistant ? c.tealText : c.accentText),
    );
  }
}

/// "Planları gör →": the hint at the foot of a tappable card.
class _MoreLink extends StatelessWidget {
  const _MoreLink(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.accentText),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: FlowSpace.xs),
      Icon(Icons.arrow_forward, size: 16, color: c.accentText),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FlowRadius.pill),
        border: Border.all(color: c.borderStrong),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({this.minHeight});

  /// Set in the scrolling layout; null fills a fixed bento cell.
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 480;
    final padding = narrow ? 20.0 : 28.0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LiveLine('WhatsApp + yapay zekâ · 7/24'),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            'Tüm WhatsApp’ınız tek bir komuta merkezinde.',
            style: narrow ? theme.textTheme.headlineLarge : theme.textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Asistanınız müşterilerinize gece gündüz yanıt verir, talepleri ve randevuları kaydeder. '
            'Ekibiniz yalnızca satışı kapatmaya odaklanır.',
            style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(spacing: FlowSpace.md, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: () => _openSignUp(context),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('14 gün ücretsiz dene'),
          ),
          OutlinedButton(
            onPressed: () => _showPanel(context, _Panel.howItWorks),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            child: const Text('Nasıl çalışır'),
          ),
        ]),
        const SizedBox(height: FlowSpace.lg),
        Text('KREDİ KARTI GEREKMEZ · İSTEDİĞİNİZ AN İPTAL', style: FlowText.caps(context, color: c.faint)),
      ],
    );
    final min = minHeight;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGrid(
        child: Stack(fit: min == null ? StackFit.expand : StackFit.loose, children: [
          const Positioned(right: -180, bottom: -220, child: SignalRings(size: 560)),
          Padding(
            padding: EdgeInsets.all(padding),
            child: min == null
                ? _FitHeight(alignment: Alignment.centerLeft, child: content)
                : ConstrainedBox(
                    constraints: BoxConstraints(minHeight: math.max(0, min - padding * 2)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [content],
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// A static mini console: what a customer sees at 02:14. Sample content only.
class _DemoCard extends StatelessWidget {
  const _DemoCard();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final body = Theme.of(context).textTheme.bodyMedium;
    final numberStyle = FlowText.mono(context, size: 14, color: c.text, weight: FontWeight.w600);
    const bubbleRadius = Radius.circular(FlowRadius.card);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Flexible(child: LiveLine('Canlı · Sohbetler')),
          SizedBox(width: FlowSpace.sm),
          StatusBadge('Örnek'),
        ]),
        const SizedBox(height: FlowSpace.lg),
        EntranceRise(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.86,
              alignment: Alignment.centerLeft,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.raised,
                    border: Border.all(color: c.border),
                    borderRadius: const BorderRadius.only(
                      topLeft: bubbleRadius,
                      topRight: bubbleRadius,
                      bottomRight: bubbleRadius,
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  child: Text('Merhaba, 1 milyon altı otomatik vites aracınız var mı?', style: body),
                ),
                const SizedBox(height: 4),
                Text('02:14', style: FlowText.mono(context, size: 11)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: FlowSpace.md),
        EntranceRise(
          index: 1,
          child: Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.9,
              alignment: Alignment.centerRight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const RoleTag.bot(),
                  const SizedBox(width: 6),
                  Text('02:14', style: FlowText.mono(context, size: 11)),
                ]),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.tealSoft,
                    border: Border.all(color: c.teal),
                    borderRadius: const BorderRadius.only(
                      topLeft: bubbleRadius,
                      topRight: bubbleRadius,
                      bottomLeft: bubbleRadius,
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(style: body?.copyWith(height: 1.45), children: [
                      const TextSpan(text: 'Bütçenize uygun otomatik aracımız: 2021 Renault Clio 1.0 TCe, '),
                      TextSpan(text: '40.000 km', style: numberStyle),
                      const TextSpan(text: ', '),
                      TextSpan(text: '900.000 ₺', style: numberStyle),
                      const TextSpan(text: '. Fotoğraflarını göndereyim mi?'),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: FlowSpace.md),
        EntranceRise(
          index: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: FlowSpace.sm),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(FlowRadius.pill),
              ),
              child: Text(
                'TALEP OLUŞTU · TEST SÜRÜŞÜ · YARIN 14:00',
                style: FlowText.caps(context, color: c.accentText),
              ),
            ),
          ),
        ),
      ],
    );
    return _TapCard(
      label: 'Örnek sohbet: asistan bir müşteriye yanıt veriyor ve test sürüşü talebi oluşturuyor. Özellikleri aç',
      onTap: () => _showPanel(context, _Panel.features),
      padding: const EdgeInsets.all(FlowSpace.xl - 2),
      child: _FitHeight(alignment: Alignment.center, child: content),
    );
  }
}

const _features = [
  (
    Icons.forum_outlined,
    'Ortak gelen kutusu',
    'Tüm ekip aynı sohbetleri görür. Kimin yanıtladığı, kimin beklediği, hangisinin asistanda olduğu ilk bakışta belli.',
    false,
  ),
  (
    Icons.auto_awesome_outlined,
    'Yapay zekâ asistanı',
    'Kataloğunuzdan, notlarınızdan ve belgelerinizden yanıt verir. Bilmediği konuda uydurmaz, sohbeti temsilcinize aktarır.',
    true,
  ),
  (
    Icons.event_available_outlined,
    'Katalog ve randevular',
    'Araç, oda ya da hizmetlerinizi fotoğraflarıyla ekleyin. Asistan müsaitliği kontrol eder, talebi ve randevuyu kaydeder.',
    false,
  ),
  (
    Icons.campaign_outlined,
    'İzinli kampanyalar',
    'Yalnızca izin veren müşterilere, Meta onaylı şablonlarla toplu mesaj gönderin. “RET” yazan kişi listeden kendiliğinden çıkar.',
    false,
  ),
];

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    Widget tile(int i) => _FeatureTile(icon: _features[i].$1, title: _features[i].$2, assistant: _features[i].$4);
    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: FlowSpace.xs),
          child: Eyebrow('Özellikler'),
        ),
        const SizedBox(height: FlowSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: tile(0)),
                const SizedBox(width: 10),
                Expanded(child: tile(1)),
              ]),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: tile(2)),
                const SizedBox(width: 10),
                Expanded(child: tile(3)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.title, required this.assistant});

  final IconData icon;
  final String title;
  final bool assistant;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    void open() => _showPanel(context, _Panel.features);
    return Semantics(
      button: true,
      label: title,
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: c.canvas,
        shape: RoundedRectangleBorder(borderRadius: FlowRadius.controlAll, side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: FlowSpace.sm),
            child: _FitHeight(
              alignment: Alignment.centerLeft,
              child: Row(children: [
                _IconBox(icon, assistant: assistant, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return _TapCard(
      label: 'Fiyatlar: aylık ${formatPrice(1490)}’den başlar, KDV hariç. Planları gör',
      onTap: () => _showPanel(context, _Panel.pricing),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _FitHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Eyebrow('Fiyatlar'),
              const SizedBox(height: FlowSpace.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: formatPrice(1490), style: FlowText.number(context, size: 32)),
                    TextSpan(
                      text: '’den',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.muted),
                    ),
                  ]),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: FlowSpace.sm),
              Text('aylık · KDV hariç', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted)),
            ]),
          ),
        ),
        const SizedBox(height: FlowSpace.sm),
        const _MoreLink('Planları gör'),
      ]),
    );
  }
}

class _SectorsCard extends StatelessWidget {
  const _SectorsCard();

  @override
  Widget build(BuildContext context) {
    return _TapCard(
      label: 'Sektörler: oto galeri, konaklama ve randevu paketleri. Paketleri gör',
      onTap: () => _showPanel(context, _Panel.sectors),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _FitHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Eyebrow('Sektörler'),
              const SizedBox(height: FlowSpace.md),
              Text('İşinizin dilini bilen hazır paketler.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: FlowSpace.md),
              const Wrap(spacing: 6, runSpacing: 6, children: [
                _Pill('Oto galeri'),
                _Pill('Konaklama'),
                _Pill('Randevu'),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: FlowSpace.sm),
        const _MoreLink('Paketleri gör'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Panels

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.panel, required this.fill});

  final _Panel panel;

  /// Fills a full-height side panel; otherwise sizes to its content (bottom sheet).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(FlowSpace.xl, FlowSpace.sm, FlowSpace.xl, FlowSpace.lg),
      child: switch (panel) {
        _Panel.howItWorks => const _HowItWorksPanel(),
        _Panel.features => const _FeaturesPanel(),
        _Panel.sectors => const _SectorsPanel(),
        _Panel.pricing => const _PricingPanel(),
        _Panel.security => const _SecurityPanel(),
      },
    );
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(FlowSpace.xl, 20, FlowSpace.md, FlowSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow(panel.label),
                const SizedBox(height: FlowSpace.sm),
                Semantics(header: true, child: Text(panel.title, style: theme.textTheme.headlineSmall)),
              ]),
            ),
            const SizedBox(width: FlowSpace.sm),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Kapat'),
            ),
          ]),
        ),
        if (fill) Expanded(child: body) else Flexible(child: body),
        Divider(height: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(FlowSpace.xl, FlowSpace.md, FlowSpace.xl, 20),
          child: FilledButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(MaterialPageRoute<void>(builder: (_) => const LoginScreen(startWithSignUp: true)));
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('14 gün ücretsiz dene'),
          ),
        ),
      ],
    );
  }
}

class _PanelBlock extends StatelessWidget {
  const _PanelBlock({required this.leading, required this.title, required this.text});

  final Widget leading;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        leading,
        const SizedBox(width: FlowSpace.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: FlowSpace.xs),
            Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _HowItWorksPanel extends StatelessWidget {
  const _HowItWorksPanel();

  static const _steps = [
    (
      'Numaranızı bağlayın',
      'WhatsApp Business numaranızı Flow’a bağlayın. Bütün mesajlar tek ekranda, tüm ekibin önünde toplanır.',
    ),
    (
      'Asistanı tanıtın',
      'Sektörünüzü seçin, birkaç soruyu yanıtlayın. Adresiniz, fiyatlarınız ve kurallarınız asistanın bilgisine eklenir.',
    ),
    (
      'Gerisini Flow yapsın',
      'Asistan soruları yanıtlar, talep ve randevuları kaydeder. Emin olmadığı her konuda sohbeti ekibinize devreder.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < _steps.length; i++) ...[
        if (i > 0) Divider(height: 1, color: c.border),
        _PanelBlock(
          leading: SizedBox(
            width: 56,
            child: Text(
              (i + 1).toString().padLeft(2, '0'),
              style: FlowText.number(context, size: 36, color: c.accentText),
            ),
          ),
          title: _steps[i].$1,
          text: _steps[i].$2,
        ),
      ],
    ]);
  }
}

class _FeaturesPanel extends StatelessWidget {
  const _FeaturesPanel();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < _features.length; i++) ...[
        if (i > 0) Divider(height: 1, color: c.border),
        _PanelBlock(
          leading: _IconBox(_features[i].$1, assistant: _features[i].$4, size: 40),
          title: _features[i].$2,
          text: _features[i].$3,
        ),
      ],
    ]);
  }
}

class _SectorsPanel extends StatelessWidget {
  const _SectorsPanel();

  static const _packs = [
    (
      'Oto galeri',
      'Oto galeriler',
      '“Kredi ile alabilir miyim?”',
      ['Araç kataloğu ve fotoğraflar', 'Test sürüşü talepleri', 'Takas, kredi ve garanti yanıtları'],
    ),
    (
      'Konaklama',
      'Otel ve pansiyonlar',
      '“Hafta sonu iki kişilik oda var mı?”',
      ['Oda tipleri ve fiyatlar', 'Tarihe göre müsaitlik', 'Rezervasyon talebi ve ön tutma'],
    ),
    (
      'Randevu',
      'Salon ve klinikler',
      '“Cumartesi öğleden sonra yer var mı?”',
      ['Hizmet listesi ve süreleri', 'Uzmana göre boş saatler', 'Randevu kaydı ve onayı'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final pack in _packs) ...[
        Container(
          margin: const EdgeInsets.only(bottom: FlowSpace.md),
          padding: const EdgeInsets.all(FlowSpace.lg),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: FlowRadius.cardAll,
            border: Border.all(color: c.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow('Paket · ${pack.$1}'),
            const SizedBox(height: FlowSpace.sm),
            Text(pack.$2, style: theme.textTheme.titleLarge),
            const SizedBox(height: FlowSpace.xs),
            Text(pack.$3, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted, fontStyle: FontStyle.italic)),
            const SizedBox(height: FlowSpace.md),
            for (final item in pack.$4)
              Padding(
                padding: const EdgeInsets.only(bottom: FlowSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.check, size: 16, color: c.accentText),
                  ),
                  const SizedBox(width: FlowSpace.sm),
                  Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Plan {
  const _Plan(this.name, this.description, this.monthly, this.yearly, this.limits, {this.trial = false});

  final String name;
  final String description;
  final int monthly;
  final int yearly;
  final List<String> limits;
  final bool trial;
}

// Starting prices and limits from docs/BILLING.md (TRY, VAT excluded).
const _plans = [
  _Plan('Başlangıç', 'Tek numara ve küçük ekipler için.', 1490, 14900, [
    '2 kullanıcı',
    '1 WhatsApp numarası',
    '1 asistan',
    'Ayda ~1.000 yapay zekâ yanıtı',
    'Ayda 1.000 kampanya mesajı',
  ]),
  _Plan('Profesyonel', 'Birden fazla numara, ek asistanlar, düzenli kampanyalar.', 3490, 34900, [
    '5 kullanıcı',
    '2 WhatsApp numarası',
    '3 asistan',
    'Ayda ~5.000 yapay zekâ yanıtı',
    'Ayda 10.000 kampanya mesajı',
  ], trial: true),
  _Plan('İşletme', 'Büyük ekipler, şubeler ve yüksek hacim.', 7990, 79900, [
    '15 kullanıcı',
    '5 WhatsApp numarası',
    '11 asistan',
    'Ayda ~20.000 yapay zekâ yanıtı',
    'Ayda 50.000 kampanya mesajı',
  ]),
];

class _PricingPanel extends StatefulWidget {
  const _PricingPanel();

  @override
  State<_PricingPanel> createState() => _PricingPanelState();
}

class _PricingPanelState extends State<_PricingPanel> {
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Aylık')),
            ButtonSegment(value: true, label: Text('Yıllık · 2 ay bizden')),
          ],
          selected: {_yearly},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _yearly = value.first),
        ),
      ),
      const SizedBox(height: FlowSpace.lg),
      for (final plan in _plans)
        Container(
          margin: const EdgeInsets.only(bottom: FlowSpace.md),
          padding: const EdgeInsets.all(FlowSpace.lg),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: FlowRadius.cardAll,
            border: Border.all(color: plan.trial ? c.accentText : c.border, width: plan.trial ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(plan.name, style: theme.textTheme.titleLarge),
              if (plan.trial) const StatusBadge('Deneme bu planla', tone: FlowTone.accent),
            ]),
            const SizedBox(height: FlowSpace.xs),
            Text(plan.description, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
            const SizedBox(height: FlowSpace.md),
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
              Text(formatCount(_yearly ? plan.yearly : plan.monthly), style: FlowText.number(context, size: 36)),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(_yearly ? '₺ / yıl' : '₺ / ay', style: FlowText.mono(context, size: 13)),
              ),
            ]),
            const SizedBox(height: FlowSpace.md),
            for (final limit in plan.limits)
              Padding(
                padding: const EdgeInsets.only(bottom: FlowSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.check, size: 16, color: c.accentText),
                  ),
                  const SizedBox(width: FlowSpace.sm),
                  Expanded(child: Text(limit, style: theme.textTheme.bodyMedium)),
                ]),
              ),
          ]),
        ),
      Text(
        'Fiyatlara KDV dahil değildir. WhatsApp şablon mesaj ücretleri Meta tarafından doğrudan '
        'işletmenize faturalanır. Yapay zekâ yanıt sayıları ortalama yanıt uzunluğuna göre tahminidir.',
        style: theme.textTheme.bodySmall?.copyWith(color: c.faint),
      ),
    ]);
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel();

  static const _points = [
    (Icons.domain_outlined, 'Her işletme ayrı', 'Verileriniz başka işletmelerle karışmaz; her sorgu işletme bazında yetkilendirilir.'),
    (Icons.key_outlined, 'Şifreli anahtarlar', 'WhatsApp bağlantı anahtarlarınız işletme başına şifrelenerek saklanır.'),
    (Icons.verified_user_outlined, 'İzinsiz pazarlama yok',
        'Kampanyalar yalnızca kayıtlı izni olan kişilere gider; izin kaynağı saklanır.'),
    (Icons.admin_panel_settings_outlined, 'Yetkiye göre ekran',
        'Her ekip üyesine yalnızca işi için gereken ekranları açarsınız.'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Flow, işletmenizin verisini yalnızca size ve yetki verdiğiniz ekip üyelerine açar. '
        'Pazarlama izinleri kayıt altındadır.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
      const SizedBox(height: FlowSpace.sm),
      for (var i = 0; i < _points.length; i++) ...[
        if (i > 0) Divider(height: 1, color: c.border),
        _PanelBlock(leading: _IconBox(_points[i].$1, size: 40), title: _points[i].$2, text: _points[i].$3),
      ],
    ]);
  }
}
