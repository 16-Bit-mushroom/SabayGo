import '../../domain/models/user_model.dart';
import '../../database/database_helper.dart';

// THE CONTRACT
abstract class IUserRepository {
  Future<UserModel?> getUser(String id);
  Future<void> updateUser(UserModel user);
  Future<void> createUser(UserModel user); 
}

// THE SQLITE IMPLEMENTATION
class SqliteUserRepository implements IUserRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  @override
  Future<UserModel?> getUser(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return UserModel.fromMap(maps.first);
    }
    return null;
  }

  @override
  Future<void> updateUser(UserModel user) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  @override
  Future<void> createUser(UserModel user) async {
    final db = await _dbHelper.database;
    await db.insert('users', user.toMap());
  }
}