import 'package:get_it/get_it.dart';

// Imports dei tuoi servizi
import '../../repositories/diet_repository.dart';
import '../../services/storage_service.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

final getIt = GetIt.instance;

void setupLocator() {
  // --- Services (Singleton) ---
  // Lazy = Viene creato solo quando qualcuno lo chiede la prima volta
  getIt.registerLazySingleton<StorageService>(() => StorageService());
  getIt.registerLazySingleton<FirestoreService>(() => FirestoreService());
  getIt.registerLazySingleton<AuthService>(() => AuthService());
  getIt.registerLazySingleton<NotificationService>(() => NotificationService());

  // --- Repositories ---
  getIt.registerLazySingleton<DietRepository>(() => DietRepository());
}
