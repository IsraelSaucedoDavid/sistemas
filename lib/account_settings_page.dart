import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _newPasswordCtrl = TextEditingController();
  bool _saving = false;
  String _status = 'Sin cambios por ahora.';

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _newPasswordCtrl.text.trim();
    if (password.length < 6) {
      setState(() => _status = 'La contrasena debe tener al menos 6 caracteres.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      setState(() {
        _newPasswordCtrl.clear();
        _status = 'Contrasena actualizada correctamente.';
      });
    } on AuthException catch (e) {
      setState(() => _status = e.message);
    } catch (e) {
      setState(() => _status = 'Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuracion de cuenta'),
        actions: const [ThemeToggleButton()],
      ),
      body: GradientBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Usuario', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(user?.email ?? 'Sin email'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Seguridad', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newPasswordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contrasena',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _updatePassword,
                    icon: const Icon(Icons.lock_reset_outlined),
                    label: Text(_saving ? 'Guardando...' : 'Actualizar contrasena'),
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
