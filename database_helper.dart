import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'digits.dart';

/// yyyy-MM-dd with Latin digits (safe to use as a database key in any locale).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ───────────────────────── Models ─────────────────────────

class Question {
  final int? id;
  final String text;
  final String correct;
  final String wrong1;
  final String wrong2;

  const Question({
    this.id,
    required this.text,
    required this.correct,
    required this.wrong1,
    required this.wrong2,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'text': text,
        'correct': correct,
        'wrong1': wrong1,
        'wrong2': wrong2,
      };

  factory Question.fromMap(Map<String, Object?> m) => Question(
        id: m['id'] as int,
        text: westernDigits(m['text'] as String),
        correct: westernDigits(m['correct'] as String),
        wrong1: westernDigits(m['wrong1'] as String),
        wrong2: westernDigits(m['wrong2'] as String),
      );
}

class SchoolClass {
  final int? id;
  final String name;
  const SchoolClass({this.id, required this.name});

  factory SchoolClass.fromMap(Map<String, Object?> m) =>
      SchoolClass(id: m['id'] as int, name: westernDigits(m['name'] as String));
}

/// Gender codes stored in the database (students.gender).
const String kMale = 'm';
const String kFemale = 'f';

class Student {
  final int? id;
  final int classId;
  final String name;

  /// Persistent score: +1 for each correct answer given while selected.
  final int points;

  /// [kMale] or [kFemale]. Used for the Arabic praise: أَحْسَنْتَ / أَحْسَنْتِ.
  final String gender;

  const Student({
    this.id,
    required this.classId,
    required this.name,
    this.points = 0,
    this.gender = kMale,
  });

  bool get isFemale => gender == kFemale;

  Student copyWith({String? name, int? points, String? gender}) => Student(
        id: id,
        classId: classId,
        name: name ?? this.name,
        points: points ?? this.points,
        gender: gender ?? this.gender,
      );

  factory Student.fromMap(Map<String, Object?> m) => Student(
        id: m['id'] as int,
        classId: m['class_id'] as int,
        name: westernDigits(m['name'] as String),
        points: (m['points'] as int?) ?? 0,
        gender: m['gender'] == kFemale ? kFemale : kMale,
      );
}

class TimetableEntry {
  final int day; // 1 = Monday ... 6 = Saturday
  final int slot; // 0-based period index
  final int classId;
  final String className;
  final String room;

  const TimetableEntry({
    required this.day,
    required this.slot,
    required this.classId,
    required this.className,
    required this.room,
  });

  factory TimetableEntry.fromMap(Map<String, Object?> m) => TimetableEntry(
        day: m['day'] as int,
        slot: m['slot'] as int,
        classId: m['class_id'] as int,
        className: m['class_name'] as String,
        room: westernDigits((m['room'] as String?) ?? ''),
      );
}

// ───────────────────────── Database ─────────────────────────

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Future<Database>? _dbFuture;

  /// The open call is cached as a Future so concurrent first calls never open the file twice.
  Future<Database> get database => _dbFuture ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'math_teacher.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE questions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            correct TEXT NOT NULL,
            wrong1 TEXT NOT NULL,
            wrong2 TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE classes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            points INTEGER NOT NULL DEFAULT 0,
            gender TEXT NOT NULL DEFAULT 'm'
          )''');
        await db.execute('''
          CREATE TABLE timetable(
            day INTEGER NOT NULL,
            slot INTEGER NOT NULL,
            class_id INTEGER NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
            room TEXT NOT NULL DEFAULT '',
            PRIMARY KEY(day, slot)
          )''');
        await db.execute('''
          CREATE TABLE notes(
            date TEXT PRIMARY KEY,
            content TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE settings(
            k TEXT PRIMARY KEY,
            v TEXT
          )''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE students ADD COLUMN points INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 3) {
          // Existing students default to male; edit a student to change it.
          await db.execute("ALTER TABLE students ADD COLUMN gender TEXT NOT NULL DEFAULT 'm'");
        }
      },
    );
  }

  // ── Questions ──
  /// [newestFirst] = true for the question bank list, false (creation order) for the quiz.
  Future<List<Question>> getQuestions({bool newestFirst = true}) async {
    final db = await database;
    final rows = await db.query('questions', orderBy: newestFirst ? 'id DESC' : 'id ASC');
    return rows.map(Question.fromMap).toList();
  }

  Future<int> countQuestions() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM questions')) ?? 0;
  }

  Future<void> insertQuestion(Question q) async {
    final db = await database;
    final map = q.toMap()..remove('id');
    await db.insert('questions', map);
  }

  Future<void> updateQuestion(Question q) async {
    final db = await database;
    await db.update('questions', q.toMap(), where: 'id = ?', whereArgs: [q.id]);
  }

  Future<void> deleteQuestion(int id) async {
    final db = await database;
    await db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  // ── Classes ──
  Future<List<SchoolClass>> getClasses() async {
    final db = await database;
    final rows = await db.query('classes', orderBy: 'id ASC');
    return rows.map(SchoolClass.fromMap).toList();
  }

  Future<int> insertClass(String name) async {
    final db = await database;
    return db.insert('classes', {'name': name});
  }

  Future<void> renameClass(int id, String name) async {
    final db = await database;
    await db.update('classes', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// Also removes the class students and its timetable slots (ON DELETE CASCADE).
  Future<void> deleteClass(int id) async {
    final db = await database;
    await db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<int, int>> getStudentCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT class_id, COUNT(*) AS c FROM students GROUP BY class_id');
    return {for (final r in rows) r['class_id'] as int: r['c'] as int};
  }

  // ── Students ──
  Future<List<Student>> getStudents(int classId) async {
    final db = await database;
    final rows = await db.query('students',
        where: 'class_id = ?', whereArgs: [classId], orderBy: 'id ASC');
    return rows.map(Student.fromMap).toList();
  }

  Future<Student?> getStudent(int id) async {
    final db = await database;
    final rows = await db.query('students', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  /// Adds one point to the student and returns the new total.
  Future<int> addPoint(int studentId) async {
    final db = await database;
    await db.rawUpdate('UPDATE students SET points = points + 1 WHERE id = ?', [studentId]);
    final rows = await db.query('students',
        columns: ['points'], where: 'id = ?', whereArgs: [studentId], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['points'] as int?) ?? 0;
  }

  Future<void> resetPoints(int classId) async {
    final db = await database;
    await db.update('students', {'points': 0}, where: 'class_id = ?', whereArgs: [classId]);
  }

  /// All [names] get the same [gender] (add boys and girls in two batches).
  Future<void> insertStudents(int classId, List<String> names, {String gender = kMale}) async {
    final db = await database;
    final batch = db.batch();
    for (final n in names) {
      batch.insert('students', {'class_id': classId, 'name': n, 'gender': gender});
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateStudent(int id, String name, String gender) async {
    final db = await database;
    await db.update('students', {'name': name, 'gender': gender},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteStudent(int id) async {
    final db = await database;
    await db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  // ── Timetable ──
  Future<List<TimetableEntry>> getTimetable() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.day, t.slot, t.class_id, t.room, c.name AS class_name
      FROM timetable t JOIN classes c ON c.id = t.class_id
    ''');
    return rows.map(TimetableEntry.fromMap).toList();
  }

  Future<void> setTimetableSlot(int day, int slot, int classId, String room) async {
    final db = await database;
    await db.insert(
      'timetable',
      {'day': day, 'slot': slot, 'class_id': classId, 'room': room},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearTimetableSlot(int day, int slot) async {
    final db = await database;
    await db.delete('timetable', where: 'day = ? AND slot = ?', whereArgs: [day, slot]);
  }

  // ── Daily notes ──
  Future<String> getNote(String date) async {
    final db = await database;
    final rows = await db.query('notes', where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? '' : westernDigits(rows.first['content'] as String);
  }

  Future<Map<String, String>> getAllNotes() async {
    final db = await database;
    final rows = await db.query('notes');
    return {for (final r in rows) r['date'] as String: westernDigits(r['content'] as String)};
  }

  /// An empty note removes the row, so the calendar marker disappears.
  Future<void> saveNote(String date, String content) async {
    final db = await database;
    if (content.trim().isEmpty) {
      await db.delete('notes', where: 'date = ?', whereArgs: [date]);
    } else {
      await db.insert('notes', {'date': date, 'content': content},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ── Settings (language, active class) ──
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
