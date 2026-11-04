import 'package:flutter_test/flutter_test.dart';
import 'package:wpapp/features/templates/models/template_header_media.dart';

void main() {
  test('header media rules match WhatsApp template limits', () {
    expect(templateHeaderMediaError('IMAGE', 'PNG', 1024), isNull);
    expect(templateHeaderMediaError('IMAGE', 'jpeg', 5 * 1024 * 1024), isNull);
    expect(templateHeaderMediaError('VIDEO', 'mp4', 16 * 1024 * 1024), isNull);
    expect(templateHeaderMediaError('DOCUMENT', 'pdf', 10), isNull);

    expect(templateHeaderMediaError('IMAGE', 'gif', 10), contains('Desteklenmeyen'));
    expect(templateHeaderMediaError('DOCUMENT', 'docx', 10), contains('pdf'));
    expect(templateHeaderMediaError('IMAGE', null, 10), isNotNull);
    expect(templateHeaderMediaError('IMAGE', 'png', 0), 'Dosya boş.');
    expect(templateHeaderMediaError('IMAGE', 'png', 5 * 1024 * 1024 + 1),
        contains('5 MB'));
    expect(templateHeaderMediaError('TEXT', 'png', 10), isNotNull);
  });
}
