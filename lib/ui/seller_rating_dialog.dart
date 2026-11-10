import 'package:flutter/material.dart';

class SellerRatingDraft {
  const SellerRatingDraft(this.rating, this.comment);
  final int rating;
  final String comment;
}

/// Temporary input state lives with its route, including its closing animation.
class SellerRatingDialog extends StatefulWidget {
  const SellerRatingDialog(
      {super.key,
      required this.title,
      required this.commentLabel,
      required this.cancelLabel,
      required this.sendLabel,
      required this.ratingLabel,
      this.initialDraft});
  final String title, commentLabel, cancelLabel, sendLabel;
  final SellerRatingDraft? initialDraft;
  final String Function(int rating) ratingLabel;
  @override
  State<SellerRatingDialog> createState() => _SellerRatingDialogState();
}

class _SellerRatingDialogState extends State<SellerRatingDialog> {
  late final TextEditingController _comment;
  late int _rating;
  @override
  void initState() {
    super.initState();
    _comment = TextEditingController(text: widget.initialDraft?.comment ?? '');
    _rating = widget.initialDraft?.rating ?? 5;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(widget.title),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(alignment: WrapAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                selected: i == _rating,
                child: IconButton(
                    tooltip: widget.ratingLabel(i),
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                        i <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.amber.shade300
                            : Colors.amber.shade800)),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _comment,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                  labelText: widget.commentLabel, alignLabelWithHint: true)),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.cancelLabel)),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, SellerRatingDraft(_rating, _comment.text.trim())),
              child: Text(widget.sendLabel)),
        ],
      );
}
