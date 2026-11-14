import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../repositories/auth_repository.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.sports_basketball,
                            size: 40,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '揪咖 Jiuka',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '找球友，一起分攤場地費',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      for (final (icon, text) in const [
                        (Icons.campaign_outlined, '主揪發布缺人場次，分享連結就能揪人'),
                        (Icons.how_to_reg_outlined, '球友線上報名，額滿自動候補遞補'),
                        (Icons.payments_outlined, '費用事先講清楚，固定價或場租平分'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(icon, size: 20, color: scheme.primary),
                              const SizedBox(width: 12),
                              Expanded(child: Text(text)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (auth.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            auth.errorMessage!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton.icon(
                        onPressed: auth.isLoading
                            ? null
                            : auth.signInWithGoogle,
                        icon: auth.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(auth.isLoading ? '登入中…' : '使用 Google 帳號登入'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '瀏覽場次不需登入；發布與報名需要 Google 帳號',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
