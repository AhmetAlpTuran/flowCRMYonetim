enum ConversationAction {
  claim('Üstlen'),
  assign('Temsilciye ata'),
  release('Ekibe bırak'),
  resolve('Çözüldü olarak işaretle'),
  reopen('Yeniden aç');

  const ConversationAction(this.label);
  final String label;
}

class ConversationActionRequest {
  const ConversationActionRequest(
      {required this.id,
      required this.revision,
      required this.action,
      this.assigneeId});
  final String id;
  final int revision;
  final ConversationAction action;
  final String? assigneeId;
}

class ConversationTeamMember {
  const ConversationTeamMember({required this.id, required this.name});
  final String id;
  final String name;
}

class ConversationActionFailure implements Exception {
  const ConversationActionFailure(this.code, {required this.uncertain});
  final String code;
  final bool uncertain;
}
