import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AppBackScope extends StatefulWidget {
  final Widget child;
  final String fallbackLocation;
  final bool preferPop;
  final String? exitSnackBarMessage;
  final Duration exitWindow;

  const AppBackScope({
    super.key,
    required this.child,
    required this.fallbackLocation,
    this.preferPop = true,
    this.exitSnackBarMessage,
    this.exitWindow = const Duration(seconds: 2),
  });

  static void goBack(
    BuildContext context, {
    required String fallbackLocation,
    bool preferPop = true,
  }) {
    if (preferPop && context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  }

  @override
  State<AppBackScope> createState() => _AppBackScopeState();
}

class _AppBackScopeState extends State<AppBackScope> {
  DateTime? _lastExitRequest;

  Future<bool> _handleBack() async {
    if (widget.exitSnackBarMessage != null) {
      final now = DateTime.now();
      final shouldExit = _lastExitRequest != null &&
          now.difference(_lastExitRequest!) <= widget.exitWindow;
      if (shouldExit) {
        await SystemNavigator.pop();
        return true;
      }
      _lastExitRequest = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.exitSnackBarMessage!)),
        );
      }
      return true;
    }

    AppBackScope.goBack(
      context,
      fallbackLocation: widget.fallbackLocation,
      preferPop: widget.preferPop,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: _handleBack,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBack();
        },
        child: widget.child,
      ),
    );
  }
}
