import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'sheets.dart' show showPinSheet;

const _defaultReferenceTemplate = 'CHAMA-{member_short}-{period}';

/// Connect the chama's own Daraja shortcode: save the keys, copy the callback URL, verify.
class MpesaSetupScreen extends StatefulWidget {
  const MpesaSetupScreen({
    super.key,
    required this.controller,
    required this.group,
  });

  final AppController controller;
  final Chama group;

  @override
  State<MpesaSetupScreen> createState() => _MpesaSetupScreenState();
}

class _MpesaSetupScreenState extends State<MpesaSetupScreen> {
  final _shortcode = TextEditingController();
  final _key = TextEditingController();
  final _secret = TextEditingController();
  final _passkey = TextEditingController();
  final _template = TextEditingController(text: _defaultReferenceTemplate);

  String _type = 'paybill';
  String _environment = 'sandbox';
  PaymentSettings? _settings;
  String? _callbackUrl;
  String? _loadError;
  String? _formError;
  Map<String, String> _fields = const {};
  bool _loading = true;
  bool _saving = false;
  bool _verifying = false;
  bool _testing = false;
  bool _callbackCopied = false;

  bool get _configured => _settings?.configured == true;
  bool get _verified => _settings?.isVerified == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shortcode.dispose();
    _key.dispose();
    _secret.dispose();
    _passkey.dispose();
    _template.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await widget.controller.api.paymentSettings(
        widget.group.id,
      );
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _shortcode.text = settings.shortcode;
        _type = settings.shortcodeType.isEmpty
            ? 'paybill'
            : settings.shortcodeType;
        _environment = settings.darajaEnvironment.isEmpty
            ? 'sandbox'
            : settings.darajaEnvironment;
        final template = settings.accountReferenceTemplate.trim();
        _template.text = template.isEmpty
            ? _defaultReferenceTemplate
            : template;
        if (settings.callbackUrl.isNotEmpty) {
          _callbackUrl = settings.callbackUrl;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final shortcode = _shortcode.text.trim();
    final template = _template.text.trim();
    final local = <String, String>{};
    if (!RegExp(r'^\d{4,9}$').hasMatch(shortcode)) {
      local['shortcode'] = 'Enter the 4 to 9 digit M-Pesa shortcode.';
    }
    if (template.isEmpty) {
      local['account_reference_template'] = 'Keep a reference for each member.';
    }
    if (!_configured) {
      if (_key.text.trim().length < 8) {
        local['consumer_key'] =
            'Paste the consumer key from the Daraja portal.';
      }
      if (_secret.text.trim().length < 8) {
        local['consumer_secret'] =
            'Paste the consumer secret from the Daraja portal.';
      }
      if (_passkey.text.trim().length < 8) {
        local['passkey'] = 'Paste the Lipa na M-Pesa passkey.';
      }
    }
    if (local.isNotEmpty) {
      setState(() {
        _fields = local;
        _formError = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
      _fields = const {};
    });
    try {
      final saved = await widget.controller.api.savePaymentSettings(
        groupId: widget.group.id,
        shortcodeType: _type,
        shortcode: shortcode,
        environment: _environment,
        accountReferenceTemplate: template,
        consumerKey: _key.text.trim(),
        consumerSecret: _secret.text.trim(),
        passkey: _passkey.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _settings = saved;
        if (saved.callbackUrl.isNotEmpty) {
          _callbackUrl = saved.callbackUrl;
        }
        _key.clear();
        _secret.clear();
        _passkey.clear();
      });
      _notice('Saved. Copy the callback URL into your Daraja app.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _applyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _formError = null;
      _fields = const {};
    });
    try {
      final verified = await widget.controller.api.verifyPaymentSettings(
        widget.group.id,
      );
      if (!mounted) return;
      setState(() {
        _settings = verified;
        if (verified.callbackUrl.isNotEmpty) {
          _callbackUrl = verified.callbackUrl;
        }
      });
      _notice('Verified. Daraja accepted these keys.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _applyError(error));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _applyError(Object error) {
    if (error is ApiException) {
      _fields = error.fields;
      _formError = error.fields.isEmpty ? error.message : null;
      return;
    }
    _fields = const {};
    _formError = 'Something went wrong. Try again.';
  }

  String _message(Object error) {
    if (error is ApiException) {
      if (error.fields.isNotEmpty) return error.fields.values.first;
      return error.message;
    }
    return 'We could not load the M-Pesa settings.';
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _sendTest() async {
    final pin = await showPinSheet(context);
    if (pin == null || !mounted) return;
    setState(() {
      _testing = true;
      _formError = null;
      _fields = const {};
    });
    try {
      final result = await widget.controller.sendTestCollection(
        group: widget.group,
        pin: pin,
      );
      if (!mounted) return;
      _notice('${result.message} KES ${result.amount} stays with the chama.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _applyError(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _copyCallback() async {
    final url = _callbackUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _callbackCopied = true);
    _notice('Callback URL copied.');
  }

  List<({String title, String body, bool done})> get _checklist => [
    (
      title: 'Shortcode ready',
      body: 'A paybill or till registered to the chama, with Lipa na M-Pesa Online enabled.',
      done: _configured,
    ),
    (
      title: 'Daraja app live',
      body: 'Create an app on developer.safaricom.co.ke and go live with this shortcode.',
      done: _configured && _settings?.darajaEnvironment == 'production',
    ),
    (
      title: 'Keys saved',
      body: 'Consumer key, consumer secret and the passkey from the go-live email.',
      done: (_settings?.consumerKeyMasked.isNotEmpty ?? false),
    ),
    (
      title: 'Callback URL pasted',
      body:
          'Copy the URL below into the Daraja app as the STK Push result URL.',
      done: _callbackCopied,
    ),
    (
      title: 'Verified',
      body: 'We check the keys with Safaricom. This moves no money.',
      done: _verified,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChamaColors.canvas,
      appBar: AppBar(
        backgroundColor: ChamaColors.deep,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        title: const Text('M-Pesa setup'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonCard(height: 110),
          SizedBox(height: 12),
          SkeletonCard(height: 240),
          SizedBox(height: 12),
          SkeletonCard(height: 160),
        ],
      );
    }
    if (_loadError != null) {
      return ErrorState(message: _loadError!, onRetry: _load);
    }
    return RefreshIndicator(
      color: ChamaColors.purple,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          _StatusCard(
            group: widget.group,
            configured: _configured,
            verified: _verified,
            shortcode: _settings?.shortcode ?? '',
            shortcodeType: _settings?.shortcodeType ?? _type,
          ),
          const SizedBox(height: 20),
          const SectionHeading(title: 'Setup checklist'),
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < _checklist.length; i++)
                  _ChecklistRow(
                    number: i + 1,
                    title: _checklist[i].title,
                    body: _checklist[i].body,
                    done: _checklist[i].done,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeading(title: 'Shortcode and keys'),
          const SizedBox(height: 10),
          SurfaceCard(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chipRow(
                  label: 'Shortcode type',
                  options: const ['paybill', 'till'],
                  labels: const {'paybill': 'Paybill', 'till': 'Till'},
                  value: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
                const SizedBox(height: 14),
                _field(
                  label: 'M-Pesa shortcode',
                  controller: _shortcode,
                  hint: 'For example 247247',
                  field: 'shortcode',
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                _chipRow(
                  label: 'Daraja environment',
                  options: const ['sandbox', 'production'],
                  labels: const {
                    'sandbox': 'Sandbox',
                    'production': 'Production',
                  },
                  value: _environment,
                  onChanged: (value) => setState(() => _environment = value),
                ),
                const SizedBox(height: 14),
                _field(
                  label: 'Consumer key',
                  controller: _key,
                  field: 'consumer_key',
                  helper: _configured
                      ? 'Saved ${_settings?.consumerKeyMasked ?? ''}. Leave blank to keep it.'
                      : null,
                ),
                _field(
                  label: 'Consumer secret',
                  controller: _secret,
                  secret: true,
                  field: 'consumer_secret',
                  helper: _configured
                      ? 'Saved ${_settings?.consumerSecretMasked ?? ''}. Leave blank to keep it.'
                      : null,
                ),
                _field(
                  label: 'Lipa na M-Pesa passkey',
                  controller: _passkey,
                  secret: true,
                  field: 'passkey',
                  helper: _configured
                      ? 'Saved ${_settings?.passkeyMasked ?? ''}. Leave blank to keep it.'
                      : null,
                ),
                _field(
                  label: 'Account reference',
                  controller: _template,
                  field: 'account_reference_template',
                  helper: 'Appears on the member\'s M-Pesa SMS.',
                ),
                if (_formError != null) _FormError(message: _formError!),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _configured
                                ? 'Save changes'
                                : 'Save M-Pesa details',
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_callbackUrl != null && _callbackUrl!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeading(title: 'Callback URL'),
            const SizedBox(height: 10),
            SurfaceCard(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paste this into the Daraja app as the STK Push result URL.',
                    style: TextStyle(color: ChamaColors.muted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _callbackUrl!,
                    style: const TextStyle(
                      color: ChamaColors.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _copyCallback,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_configured)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _verifying ? null : _verify,
                icon: _verifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined, size: 18),
                label: Text(
                  _verified ? 'Verify again' : 'Verify with Safaricom',
                ),
              ),
            ),
          if (_configured) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _sendTest,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send a KES 1 test'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sends a real KES 1 prompt to your phone. The money goes to the chama and nothing is added to the ledger.',
                style: TextStyle(
                  color: ChamaColors.muted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SurfaceCard(
            color: ChamaColors.soft,
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: ChamaColors.purple,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Contributions settle to ${widget.group.name}\'s own shortcode. '
                    'The app never holds chama funds and cannot withdraw from it.',
                    style: const TextStyle(
                      color: ChamaColors.muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRow({
    required String label,
    required List<String> options,
    required Map<String, String> labels,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ChamaColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(labels[option] ?? option),
                selected: value == option,
                onSelected: (_) => onChanged(option),
                selectedColor: ChamaColors.purple,
                labelStyle: TextStyle(
                  color: value == option ? Colors.white : ChamaColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: ChamaColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: value == option
                        ? ChamaColors.purple
                        : ChamaColors.line,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helper,
    String? field,
    bool secret = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    final error = field == null ? null : _fields[field];
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            obscureText: secret,
            keyboardType: keyboard,
            inputFormatters: formatters,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(hintText: hint, helperText: helper),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                error,
                style: const TextStyle(
                  color: ChamaColors.danger,
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.group,
    required this.configured,
    required this.verified,
    required this.shortcode,
    required this.shortcodeType,
  });

  final Chama group;
  final bool configured;
  final bool verified;
  final String shortcode;
  final String shortcodeType;

  @override
  Widget build(BuildContext context) {
    final color = verified
        ? ChamaColors.green
        : configured
        ? ChamaColors.warning
        : ChamaColors.muted;
    final title = verified
        ? 'Connected and verified'
        : configured
        ? 'Saved, not verified yet'
        : 'Not connected';
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              verified
                  ? Icons.verified_rounded
                  : configured
                  ? Icons.pending_outlined
                  : Icons.payments_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  configured
                      ? '${shortcodeType == 'till' ? 'Till' : 'Paybill'} $shortcode · ${group.name}'
                      : 'Add the chama\'s shortcode and Daraja keys below.',
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.number,
    required this.title,
    required this.body,
    required this.done,
  });

  final int number;
  final String title;
  final String body;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: done ? ChamaColors.greenSoft : ChamaColors.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: ChamaColors.green,
                  )
                : Text(
                    '$number',
                    style: const TextStyle(
                      color: ChamaColors.purple,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: done ? ChamaColors.muted : ChamaColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: ChamaColors.danger, fontSize: 12),
      ),
    );
  }
}
