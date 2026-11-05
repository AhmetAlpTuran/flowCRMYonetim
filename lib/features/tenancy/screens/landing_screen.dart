import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import 'login_screen.dart';
import 'web_landing.dart';

/// The signed-out entry. The web build shows the one-screen card landing
/// ([WebLanding]); phone and tablet apps open the three-step welcome ([WelcomeFlow]).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key, this.web = kIsWeb});

  /// True shows the web landing instead of the app welcome.
  final bool web;

  @override
  Widget build(BuildContext context) => web ? const WebLanding() : const WelcomeFlow();
}

class _WelcomeStep {
  const _WelcomeStep(this.eyebrow, this.title, this.body);

  final String eyebrow;
  final String title;
  final String body;
}

const _steps = [
  _WelcomeStep(
    '01 / 03 · 7/24 yanıt',
    'WhatsApp’ınız artık uyumuyor.',
    'Gece 02:00’de gelen soruya bile asistanınız anında, sizin bilgilerinizle yanıt verir.',
  ),
  _WelcomeStep(
    '02 / 03 · Tek ekran',
    'Ekip ve asistan aynı ekranda.',
    'Asistan zorlandığında sohbet ekibinize geçer. Kimin neyi beklediği her an belli.',
  ),
  _WelcomeStep(
    '03 / 03 · Talepler',
    'Talepler kendiliğinden kayda girer.',
    'Test sürüşü, rezervasyon ya da randevu: hepsi Müşteriler ekranında sizi bekler.',
  ),
];

/// Three short pages on the dot grid: "İleri" walks through them, the last one leads
/// to sign-up, and sign-in is always one tap away.
class WelcomeFlow extends StatefulWidget {
  const WelcomeFlow({super.key});

  @override
  State<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends State<WelcomeFlow> {
  int _index = 0;

  bool get _isLast => _index == _steps.length - 1;

  void _go(int index) => setState(() => _index = index.clamp(0, _steps.length - 1));

  void _openLogin({bool signUp = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(startWithSignUp: signUp)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final step = _steps[_index];
    final switchDuration = FlowMotion.reduced(context) ? Duration.zero : FlowMotion.entrance;

    Widget swap(Widget child) => AnimatedSwitcher(
          duration: switchDuration,
          switchInCurve: FlowMotion.curve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(key: ValueKey(_index), child: child),
        );

    return Scaffold(
      body: DotGrid(
        child: Stack(fit: StackFit.expand, children: [
          const Positioned(left: -115, top: 40, child: SignalRings(size: 620)),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -200) _go(_index + 1);
                if (velocity > 200) _go(_index - 1);
              },
              child: LayoutBuilder(builder: (context, constraints) {
                final gutter = constraints.maxWidth < 600 ? 20.0 : FlowSpace.xxl;
                const top = FlowSpace.md;
                const bottom = 28.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(gutter, top, gutter, bottom),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - top - bottom)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 48,
                          child: Row(children: [
                            const FlowLogo(size: 26),
                            const Spacer(),
                            if (!_isLast)
                              TextButton(
                                onPressed: _openLogin,
                                style: TextButton.styleFrom(foregroundColor: c.muted),
                                child: const Text('Atla'),
                              ),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: FlowSpace.xxl),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: swap(_Illustration(_index)),
                            ),
                          ),
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                swap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Eyebrow(step.eyebrow),
                                  const SizedBox(height: 14),
                                  Semantics(
                                    header: true,
                                    child: Text(step.title, style: theme.textTheme.displaySmall?.copyWith(height: 1)),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(step.body, style: theme.textTheme.bodyLarge?.copyWith(color: c.muted)),
                                ])),
                                const SizedBox(height: 20),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: StepBars(count: _steps.length, index: _index),
                                ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: _isLast ? () => _openLogin(signUp: true) : () => _go(_index + 1),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    textStyle: theme.textTheme.labelLarge?.copyWith(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: Text(_isLast ? 'İşletmeni oluştur' : 'İleri'),
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton(
                                  onPressed: _openLogin,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg, vertical: 10),
                                  ),
                                  child: const Text('Zaten hesabım var · Giriş yap', textAlign: TextAlign.center),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The picture for each step, built from the app's own bubbles, badges and role tags.
/// Sample content only: no live numbers.
class _Illustration extends StatelessWidget {
  const _Illustration(this.index);

  final int index;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: switch (index) {
          0 => const _ChatSample(),
          1 => const _QueueSample(),
          _ => const _RequestSample(),
        },
      );
}

class _ChatSample extends StatelessWidget {
  const _ChatSample();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final body = Theme.of(context).textTheme.bodyMedium;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: c.raised,
            border: Border.all(color: c.border),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(FlowRadius.card),
              topRight: Radius.circular(FlowRadius.card),
              bottomRight: Radius.circular(FlowRadius.card),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Text('Saat kaça kadar açıksınız?', style: body),
        ),
      ),
      const SizedBox(height: FlowSpace.md),
      FractionallySizedBox(
        alignment: Alignment.centerRight,
        widthFactor: 0.84,
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
                topLeft: Radius.circular(FlowRadius.card),
                topRight: Radius.circular(FlowRadius.card),
                bottomLeft: Radius.circular(FlowRadius.card),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              'Hafta içi 19:00’a kadar açığız. Yarın için randevu ayarlayayım mı?',
              style: body?.copyWith(height: 1.45),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _QueueSample extends StatelessWidget {
  const _QueueSample();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    const rows = [
      ('Mehmet Kaya', 'Temsilci bekliyor', FlowTone.warning),
      ('Ayşe Yılmaz', 'Asistanda', FlowTone.assistant),
      ('Zeynep Demir', 'Ekip yanıtladı', FlowTone.accent),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: FlowSpace.md),
            decoration: BoxDecoration(
              border: i < rows.length - 1 ? Border(bottom: BorderSide(color: c.border)) : null,
            ),
            child: Row(children: [
              InitialsAvatar(rows[i].$1, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              Flexible(child: StatusBadge(rows[i].$2, tone: rows[i].$3)),
            ]),
          ),
      ]),
    );
  }
}

class _RequestSample extends StatelessWidget {
  const _RequestSample();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Wrap(spacing: 6, runSpacing: 6, children: [
          StatusBadge('Yeni talep', tone: FlowTone.accent),
          StatusBadge('Test sürüşü'),
        ]),
        const SizedBox(height: FlowSpace.md),
        Text('Ayşe Yılmaz', style: theme.textTheme.titleLarge),
        const SizedBox(height: FlowSpace.xs),
        Text('2021 Renault Clio 1.0 TCe', style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: FlowSpace.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(upperTr('Yarın 14:00'), style: FlowText.number(context, size: 26)),
        ),
      ]),
    );
  }
}
