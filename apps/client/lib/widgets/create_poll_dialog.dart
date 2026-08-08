import 'package:flutter/material.dart';

import '../l10n/messages.dart';
import 'hl_button.dart';

class CreatePollResult {
  const CreatePollResult({
    required this.question,
    required this.answers,
    this.maxSelections = 1,
  });

  final String question;
  final List<String> answers;
  final int maxSelections;
}

Future<CreatePollResult?> showCreatePollDialog(
  BuildContext context, {
  required AppStrings strings,
}) {
  return showDialog<CreatePollResult>(
    context: context,
    builder: (context) => _CreatePollDialog(strings: strings),
  );
}

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _question = TextEditingController();
  final _answers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  var _multi = false;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addAnswer() {
    if (_answers.length >= 8) return;
    setState(() => _answers.add(TextEditingController()));
  }

  void _removeAnswer(int index) {
    if (_answers.length <= 2) return;
    setState(() {
      _answers.removeAt(index).dispose();
    });
  }

  void _submit() {
    final question = _question.text.trim();
    final answers = _answers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (question.isEmpty || answers.length < 2) return;
    Navigator.pop(
      context,
      CreatePollResult(
        question: question,
        answers: answers,
        maxSelections: _multi ? answers.length.clamp(2, answers.length) : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.createPoll),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _question,
                autofocus: true,
                decoration: InputDecoration(labelText: s.pollQuestion),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _answers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _answers[i],
                          decoration: InputDecoration(
                            labelText: s.pollOption(i + 1),
                          ),
                        ),
                      ),
                      if (_answers.length > 2)
                        IconButton(
                          tooltip: s.delete,
                          onPressed: () => _removeAnswer(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: HlButton.text(
                  onPressed: _answers.length >= 8 ? null : _addAnswer,
                  label: Text(s.addPollOption),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.pollAllowMultiple),
                value: _multi,
                onChanged: (v) => setState(() => _multi = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        HlButton.text(
          onPressed: () => Navigator.pop(context),
          label: Text(s.cancel),
        ),
        HlButton.primary(
          onPressed: _submit,
          label: Text(s.createPoll),
        ),
      ],
    );
  }
}
