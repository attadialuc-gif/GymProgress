import 'package:flutter/material.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/theme.dart';

/// Profile and settings (stage D core: unit and theme; the rest comes in stage E).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final settings = model.settings;
    void save(void Function(UserSettings s) change) {
      final s = model.settings;
      change(s);
      model.perform(() => model.repository.saveSettings(s));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        children: [
          const SectionTitle('Unidades y apariencia'),
          ListTile(
            title: const Text('Unidad de peso'),
            trailing: SegmentedButton<WeightUnit>(
              segments: const [
                ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                ButtonSegment(value: WeightUnit.lb, label: Text('lb')),
              ],
              selected: {settings.weightUnit},
              onSelectionChanged: (v) => save((s) => s.weightUnit = v.first),
            ),
          ),
          ListTile(
            title: const Text('Tema'),
            trailing: DropdownButton<AppTheme>(
              value: settings.theme,
              onChanged: (v) => save((s) => s.theme = v!),
              items: const [
                DropdownMenuItem(value: AppTheme.dark, child: Text('Oscuro')),
                DropdownMenuItem(value: AppTheme.light, child: Text('Claro')),
                DropdownMenuItem(value: AppTheme.system, child: Text('Sistema')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
