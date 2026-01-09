// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Kybo';

  @override
  String get maintenanceTitle => 'Manutenzione';

  @override
  String get maintenanceDefaultMessage => 'Sistema in aggiornamento.';

  @override
  String get errorGeneric => 'Si è verificato un errore.';

  @override
  String get errorLoadDiet => 'Impossibile caricare la dieta.';

  @override
  String get errorCloudSync => 'Errore sincronizzazione Cloud.';

  @override
  String get shoppingListTitle => 'Lista Spesa';

  @override
  String get scanReceiptTitle => 'Scansiona Scontrino';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get btnRetry => 'Riprova';

  @override
  String get btnLogin => 'Accedi';

  @override
  String get msgWelcome => 'Benvenuto in Kybo';
}
