import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_model.dart';
import 'home/home_screen.dart';
import 'progress/progress_screen.dart';
import 'profile/profile_screen.dart';
import 'routines/routines_screen.dart';
import 'workout/workout_screen.dart';

/// Five sections like iOS. Bottom navigation on phones; side navigation rail on wide windows
/// (Windows/tablets). Each tab keeps its own navigation stack.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _navigators = {for (final t in AppTab.values) t: GlobalKey<NavigatorState>()};
  bool _offeredResume = false;

  static const _destinations = [
    (AppTab.home, Icons.home_outlined, Icons.home, 'Inicio'),
    (AppTab.routines, Icons.list_alt_outlined, Icons.list_alt, 'Rutinas'),
    (AppTab.workout, Icons.fitness_center_outlined, Icons.fitness_center, 'Entrenar'),
    (AppTab.progress, Icons.show_chart_outlined, Icons.show_chart, 'Progreso'),
    (AppTab.profile, Icons.person_outline, Icons.person, 'Perfil'),
  ];

  Widget _root(AppTab tab) => switch (tab) {
    AppTab.home => const HomeScreen(),
    AppTab.routines => const RoutinesScreen(),
    AppTab.workout => const WorkoutScreen(),
    AppTab.progress => const ProgressScreen(),
    AppTab.profile => const ProfileScreen(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offeredResume) return;
    _offeredResume = true;
    // On launch (also after process death), an interrupted session is offered for resuming.
    final model = AppScope.read(context);
    if (model.storeError == null && model.workout.openSession() != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerResume(model));
    }
  }

  Future<void> _offerResume(AppModel model) async {
    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tenés un entrenamiento en curso'),
        content: const Text('Se guardó todo lo que registraste, incluidas tus decisiones sobre las recomendaciones.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Más tarde')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retomar')),
        ],
      ),
    );
    if (resume == true) model.selectTab(AppTab.workout);
  }

  void _select(AppModel model, int index) {
    final tab = _destinations[index].$1;
    if (tab == model.selectedTab) {
      // Tapping the current tab returns to its first screen.
      _navigators[tab]!.currentState?.popUntil((r) => r.isFirst);
    }
    model.selectTab(tab);
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    if (model.errorMessage != null) {
      final message = model.errorMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || model.errorMessage == null) return;
        model.clearError();
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Atención'),
            content: Text(message),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      });
    }
    final index = AppTab.values.indexOf(model.selectedTab);
    final stack = IndexedStack(
      index: index,
      children: [
        for (final (tab, _, _, _) in _destinations)
          Navigator(
            key: _navigators[tab],
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => _root(tab)),
          ),
      ],
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < _destinations.length; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () =>
              _select(model, i),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _navigators[model.selectedTab]!.currentState?.maybePop(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => model.completeNextSet?.call(),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          // Android back: pops inside the current tab first (screens and sheets); exits only at the
          // tab's root. Decided at the moment of the gesture (nested navigators don't rebuild Shell).
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = _navigators[model.selectedTab]!.currentState;
            if (nav != null && await nav.maybePop()) return;
            await SystemNavigator.pop();
          },
          child: wide
              ? Scaffold(
                  body: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: index,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (i) => _select(model, i),
                        destinations: [
                          for (final (_, icon, selected, label) in _destinations)
                            NavigationRailDestination(
                              icon: Icon(icon),
                              selectedIcon: Icon(selected),
                              label: Text(label),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: stack),
                    ],
                  ),
                )
              : Scaffold(
                  body: stack,
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: (i) => _select(model, i),
                    destinations: [
                      for (final (_, icon, selected, label) in _destinations)
                        NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
