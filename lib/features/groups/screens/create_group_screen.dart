import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/repositories/auth_repository.dart';
import '../models/group_model.dart';
import '../repositories/group_repository.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxPlayersController = TextEditingController(text: '20');

  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxPlayersController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isCreating || !_formKey.currentState!.validate()) return;

    final user = context.read<AuthRepository>().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請先使用 Google 登入，再建立球隊。')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      await context.read<GroupRepository>().createGroup(
        Group.create(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          adminId: user.id,
          adminName: user.name,
          maxPlayersDefault: int.parse(_maxPlayersController.text.trim()),
        ),
      );

      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('建立球隊失敗，請檢查網路後重試。')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('建立球隊')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '球隊名稱',
                  hintText: '例如：週末籃球團',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return '請輸入球隊名稱。';
                  if (name.length > 60) return '球隊名稱最多 60 個字。';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '球隊介紹（選填）',
                  hintText: '介紹球隊、程度或平常的活動方式。',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _maxPlayersController,
                decoration: const InputDecoration(
                  labelText: '每場預設總人數',
                  helperText: '建立球隊活動時可再調整。',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people_outline),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final count = int.tryParse(value?.trim() ?? '');
                  if (count == null) return '請輸入有效的人數。';
                  if (count < 2) return '每場至少需要 2 個名額。';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isCreating ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                icon: _isCreating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add),
                label: Text(_isCreating ? '建立中…' : '建立球隊'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
