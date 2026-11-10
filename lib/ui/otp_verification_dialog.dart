import 'package:flutter/material.dart';
import '../auth/auth_feedback.dart';

class OtpVerificationDialog extends StatefulWidget {
  const OtpVerificationDialog(
      {super.key,
      required this.phoneNumber,
      required this.title,
      required this.message,
      required this.phoneLabel,
      required this.codeLabel,
      required this.invalidCode,
      required this.cancelLabel,
      required this.verifyLabel,
      required this.onVerify,
      required this.errorLabel});
  final String phoneNumber,
      title,
      message,
      phoneLabel,
      codeLabel,
      invalidCode,
      cancelLabel,
      verifyLabel;
  final Future<void> Function(String code) onVerify;
  final String Function(Object error) errorLabel;
  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerify(normalizedOtpCode(_code.text)!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorLabel(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(widget.title),
        content: Form(
            key: _form,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.message),
                  const SizedBox(height: 12),
                  Text(widget.phoneLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(widget.phoneNumber,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey('auth_otp'),
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    onFieldSubmitted: (_) => _verify(),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) => normalizedOtpCode(value ?? '') == null
                        ? widget.invalidCode
                        : null,
                    decoration: InputDecoration(
                        labelText: widget.codeLabel,
                        helperText: widget.invalidCode,
                        helperMaxLines: 3),
                  ),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(widget.cancelLabel)),
          FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.verifyLabel)),
        ],
      ));
}
