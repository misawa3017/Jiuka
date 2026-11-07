import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../repositories/auth_repository.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Jiuka 揪咖',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 16),
                  const Text('找球友，一起分攤場地費', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  if (auth.errorMessage != null) ...[
                    Text(auth.errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: auth.isLoading ? null : auth.signInWithGoogle,
                    icon: auth.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(auth.isLoading ? '登入中…' : '使用 Google 帳號登入'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
