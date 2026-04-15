/// Result types for recovery operations
enum RecoveryResultType {
  success,
  invalidCode,
  locked,
  ownerNotFound,
  pinMismatch,
}

/// Result of a recovery operation
class RecoveryResult {
  final RecoveryResultType type;
  final String? message;
  final int? lockSeconds;
  final String? newRecoveryCode; // For regenerate/reset operations

  const RecoveryResult({
    required this.type,
    this.message,
    this.lockSeconds,
    this.newRecoveryCode,
  });

  bool get isSuccess => type == RecoveryResultType.success;
  bool get isLocked => type == RecoveryResultType.locked;

  /// Create success result
  factory RecoveryResult.success({String? newRecoveryCode, String? message}) {
    return RecoveryResult(
      type: RecoveryResultType.success,
      newRecoveryCode: newRecoveryCode,
      message: message,
    );
  }

  /// Create invalid code result
  factory RecoveryResult.invalidCode({String? message}) {
    return RecoveryResult(
      type: RecoveryResultType.invalidCode,
      message: message ?? 'Invalid recovery code',
    );
  }

  /// Create locked result
  factory RecoveryResult.locked({required int seconds}) {
    return RecoveryResult(
      type: RecoveryResultType.locked,
      lockSeconds: seconds,
      message: 'Too many attempts. Locked for $seconds seconds.',
    );
  }

  /// Create owner not found result
  factory RecoveryResult.ownerNotFound() {
    return const RecoveryResult(
      type: RecoveryResultType.ownerNotFound,
      message: 'Owner account not found',
    );
  }

  /// Create PIN mismatch result
  factory RecoveryResult.pinMismatch() {
    return const RecoveryResult(
      type: RecoveryResultType.pinMismatch,
      message: 'Incorrect PIN',
    );
  }
}

/// Status of recovery lock
class RecoveryLockStatus {
  final bool isLocked;
  final int secondsRemaining;

  const RecoveryLockStatus({
    required this.isLocked,
    this.secondsRemaining = 0,
  });

  factory RecoveryLockStatus.notLocked() {
    return const RecoveryLockStatus(isLocked: false);
  }

  factory RecoveryLockStatus.locked(int seconds) {
    return RecoveryLockStatus(
      isLocked: true,
      secondsRemaining: seconds,
    );
  }
}
