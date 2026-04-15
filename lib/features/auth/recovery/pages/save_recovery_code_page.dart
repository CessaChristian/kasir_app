import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Page to display recovery code (SHOW ONLY ONCE!)
/// 
/// User must save the code before proceeding
class SaveRecoveryCodePage extends StatefulWidget {
  final String recoveryCode;
  final VoidCallback onComplete;

  const SaveRecoveryCodePage({
    super.key,
    required this.recoveryCode,
    required this.onComplete,
  });

  @override
  State<SaveRecoveryCodePage> createState() => _SaveRecoveryCodePageState();
}

class _SaveRecoveryCodePageState extends State<SaveRecoveryCodePage> {
  bool _hasAccepted = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryCode));
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery code copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // Prevent back button
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Save Recovery Code'),
          automaticallyImplyLeading: false, // Hide back button
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // Warning icon
                  Icon(
                    Icons.lock_reset,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Save Your Recovery Code',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Warning message
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This code will only be shown once!\nSave it in a secure place.',
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Recovery code display
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outline,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          widget.recoveryCode,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                fontFamily: 'monospace',
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        
                        // Copy button
                        FilledButton.icon(
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy Code'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Info text
                  Text(
                    'You will need this code to reset your PIN if you forget it. '
                    'Store it securely (e.g., password manager, secure note).',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Checkbox confirmation
                  CheckboxListTile(
                    value: _hasAccepted,
                    onChanged: (value) {
                      setState(() => _hasAccepted = value ?? false);
                    },
                    title: const Text(
                      'I have saved my recovery code securely',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 16),

                  // Continue button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _hasAccepted ? widget.onComplete : null,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
