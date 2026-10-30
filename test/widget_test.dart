import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/campaigns/models/template_input.dart';
import 'package:wpapp/features/campaigns/widgets/template_parameter_fields.dart';

// Replaces the unused counter example. Execution is deferred at the owner's request.
void main() {
  const textInput = CampaignTemplateInput(
    key: 'body.1',
    component: 'body',
    kind: 'text',
    variable: '1',
    maxLength: 1024,
  );
  const mediaInput = CampaignTemplateInput(
    key: 'header.media',
    component: 'header',
    kind: 'image',
    maxLength: 2048,
  );

  testWidgets('required values remain editable after validation at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final form = GlobalKey<FormState>();
    var bindings = <String, dynamic>{
      'body.1': {'source': 'literal', 'value': ''}
    };
    await tester.pumpWidget(
        _form(form, [textInput], bindings, (next) => bindings = next));
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Bu alan zorunludur.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Ada');
    expect(form.currentState!.validate(), isTrue);
    await tester.pump();
    expect(bindings['body.1']['value'], 'Ada');
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact bindings replace literals and omit an empty fallback',
      (tester) async {
    final form = GlobalKey<FormState>();
    var bindings = <String, dynamic>{
      'body.1': {'source': 'literal', 'value': 'Old value'}
    };
    await tester.pumpWidget(
        _form(form, [textInput], bindings, (next) => bindings = next));
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kişi alanı').last);
    await tester.pumpAndSettle();
    expect(bindings['body.1'], {'source': 'contact', 'field': 'full_name'});
    await tester.enterText(find.byType(TextFormField), 'Müşterimiz');
    expect(bindings['body.1']['fallback'], 'Müşterimiz');
    await tester.enterText(find.byType(TextFormField), '');
    expect((bindings['body.1'] as Map).containsKey('fallback'), isFalse);
    expect(form.currentState!.validate(), isTrue);
  });

  testWidgets('media ID mode clears the previous URL and validates the ID',
      (tester) async {
    final form = GlobalKey<FormState>();
    var bindings = <String, dynamic>{
      'header.media': {
        'source': 'media_link',
        'value': 'https://cdn.example.com/picture.jpg',
      }
    };
    await tester.pumpWidget(
        _form(form, [mediaInput], bindings, (next) => bindings = next));
    expect(form.currentState!.validate(), isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WhatsApp medya kimliği').last);
    await tester.pumpAndSettle();
    expect(bindings['header.media'], {'source': 'media_id', 'value': ''});
    await tester.enterText(find.byType(TextFormField), '4::creation-handle');
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(find.byType(TextFormField), '123456789');
    expect(form.currentState!.validate(), isTrue);
  });
}

Widget _form(GlobalKey<FormState> key, List<CampaignTemplateInput> inputs,
    Map<String, dynamic> initial, ValueChanged<Map<String, dynamic>> changed) {
  var bindings = initial;
  return MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: StatefulBuilder(
        builder: (context, setState) => Form(
              key: key,
              child: TemplateParameterFields(
                inputs: inputs,
                bindings: bindings,
                onChanged: (next) {
                  changed(next);
                  setState(() => bindings = next);
                },
              ),
            )),
  )));
}
