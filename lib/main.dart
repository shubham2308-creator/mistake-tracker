import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  runApp(const ErrorBookApp());
}

class QuestionItem {
  final int? id;
  final String imagePath;
  final String subject;
  final String chapter;
  final String errorType;
  final String difficulty;
  int isSolved;

  QuestionItem({
    this.id,
    required this.imagePath,
    required this.subject,
    required this.chapter,
    required this.errorType,
    this.difficulty = 'Medium',
    this.isSolved = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'imagePath': imagePath,
        'subject': subject,
        'chapter': chapter,
        'errorType': errorType,
        'difficulty': difficulty,
        'isSolved': isSolved,
      };

  factory QuestionItem.fromMap(Map<String, dynamic> map) => QuestionItem(
        id: map['id'],
        imagePath: map['imagePath'],
        subject: map['subject'],
        chapter: map['chapter'],
        errorType: map['errorType'],
        difficulty: map['difficulty'] ?? 'Medium',
        isSolved: map['isSolved'] ?? 0,
      );
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mistake_book_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            imagePath TEXT NOT NULL,
            subject TEXT NOT NULL,
            chapter TEXT NOT NULL,
            errorType TEXT NOT NULL,
            difficulty TEXT NOT NULL,
            isSolved INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertQuestion(QuestionItem item) async {
    final db = await instance.database;
    return await db.insert('questions', item.toMap());
  }

  Future<List<QuestionItem>> getQuestions({
    String? subject,
    String? difficulty,
    int? isSolved,
  }) async {
    final db = await instance.database;
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (subject != null && subject != 'All') {
      whereClauses.add('subject = ?');
      whereArgs.add(subject);
    }
    if (difficulty != null && difficulty != 'All') {
      whereClauses.add('difficulty = ?');
      whereArgs.add(difficulty);
    }
    if (isSolved != null) {
      whereClauses.add('isSolved = ?');
      whereArgs.add(isSolved);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final result = await db.query(
      'questions',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'id DESC',
    );
    return result.map((e) => QuestionItem.fromMap(e)).toList();
  }

  Future<void> toggleSolved(int id, int currentStatus) async {
    final db = await instance.database;
    await db.update(
      'questions',
      {'isSolved': currentStatus == 1 ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateDifficulty(int id, String newDiff) async {
    final db = await instance.database;
    await db.update(
      'questions',
      {'difficulty': newDiff},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class ErrorBookApp extends StatelessWidget {
  const ErrorBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mistake Book',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.indigo,
        useMaterial3: false,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.indigo,
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late StreamSubscription _intentDataStreamSubscription;
  List<QuestionItem> questions = [];
  String selectedSubject = 'All';
  String selectedDifficulty = 'All';
  bool showOnlyUnsolved = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();

    // Listen to incoming shared images while app is open
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.path.isNotEmpty) {
        _showSaveDialog(value.first.path);
      }
    });

    // Handle shared image if app was opened directly from share menu
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty && value.first.path.isNotEmpty) {
        _showSaveDialog(value.first.path);
      }
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final list = await DatabaseHelper.instance.getQuestions(
      subject: selectedSubject,
      difficulty: selectedDifficulty,
      isSolved: showOnlyUnsolved ? 0 : null,
    );
    setState(() {
      questions = list;
    });
  }

  Future<void> _showSaveDialog(String tempPath) async {
    final subjectController = TextEditingController(text: 'Physics');
    final chapterController = TextEditingController();
    String errorType = 'Conceptual';
    String difficulty = 'Medium';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Save to Mistake Book'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: subjectController.text,
                  items: ['Physics', 'Chemistry', 'Biology']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => subjectController.text = v!),
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: chapterController,
                  decoration: const InputDecoration(
                    labelText: 'Chapter Name',
                    hintText: 'e.g. Thermodynamics',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: errorType,
                  items: ['Conceptual', 'Calculation', 'Time Trap', 'Silly Mistake']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => errorType = v!),
                  decoration: const InputDecoration(labelText: 'Error Reason'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: difficulty,
                  items: ['Easy', 'Medium', 'Hard']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => difficulty = v!),
                  decoration: const InputDecoration(labelText: 'Difficulty Level'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Discard'),
            ),
            ElevatedButton(
              onPressed: () async {
                final appDir = await getApplicationDocumentsDirectory();
                final fileName = p.basename(tempPath);
                final savedImage = await File(tempPath).copy('${appDir.path}/$fileName');

                await DatabaseHelper.instance.insertQuestion(
                  QuestionItem(
                    imagePath: savedImage.path,
                    subject: subjectController.text,
                    chapter: chapterController.text.trim().isEmpty
                        ? 'General'
                        : chapterController.text.trim(),
                    errorType: errorType,
                    difficulty: difficulty,
                  ),
                );

                if (mounted) Navigator.pop(ctx);
                _loadQuestions();
              },
              child: const Text('Save'),
            )
          ],
        );
      }),
    );
  }

  Color _getDifficultyColor(String diff) {
    switch (diff) {
      case 'Easy':
        return Colors.green;
      case 'Hard':
        return Colors.redAccent;
      case 'Medium':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<QuestionItem>> chapterGroups = {};
    for (var q in questions) {
      chapterGroups.putIfAbsent('${q.subject} - ${q.chapter}', () => []).add(q);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mistake Book Index'),
        actions: [
          IconButton(
            icon: Icon(
              showOnlyUnsolved ? Icons.filter_alt : Icons.filter_alt_off,
              color: showOnlyUnsolved ? Colors.amber : null,
            ),
            tooltip: showOnlyUnsolved ? 'Showing Pending Only' : 'Showing All',
            onPressed: () {
              setState(() {
                showOnlyUnsolved = !showOnlyUnsolved;
              });
              _loadQuestions();
            },
          )
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: ['All', 'Physics', 'Chemistry', 'Biology'].map((subj) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: FilterChip(
                    label: Text(subj),
                    selected: selectedSubject == subj,
                    onSelected: (val) {
                      setState(() => selectedSubject = subj);
                      _loadQuestions();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: ['All', 'Easy', 'Medium', 'Hard'].map((diff) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(diff),
                    selected: selectedDifficulty == diff,
                    selectedColor: diff == 'All'
                        ? null
                        : _getDifficultyColor(diff).withOpacity(0.3),
                    onSelected: (val) {
                      setState(() => selectedDifficulty = diff);
                      _loadQuestions();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: chapterGroups.isEmpty
                ? const Center(
                    child: Text(
                      'No questions found.\nShare a screenshot to Mistake Book to add one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: chapterGroups.keys.length,
                    itemBuilder: (ctx, i) {
                      final chapterKey = chapterGroups.keys.elementAt(i);
                      final qList = chapterGroups[chapterKey]!;
                      final solvedCount = qList.where((q) => q.isSolved == 1).length;
                      final allSolved = solvedCount == qList.length;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: allSolved ? Colors.green.withOpacity(0.5) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: allSolved
                                ? Colors.green.withOpacity(0.2)
                                : Colors.indigo.withOpacity(0.1),
                            child: Icon(
                              allSolved ? Icons.check_circle : Icons.menu_book,
                              color: allSolved ? Colors.green : Colors.indigo,
                            ),
                          ),
                          title: Text(
                            chapterKey,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '$solvedCount/${qList.length} Reviewed',
                            style: TextStyle(
                              color: allSolved ? Colors.green : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          children: qList.map((q) {
                            final isReviewed = q.isSolved == 1;

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isReviewed ? Colors.green : Colors.grey.shade300,
                                  width: isReviewed ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    dense: true,
                                    title: Text('Error: ${q.errorType}'),
                                    subtitle: Row(
                                      children: [
                                        const Text('Level: '),
                                        DropdownButton<String>(
                                          value: q.difficulty,
                                          isDense: true,
                                          underline: const SizedBox(),
                                          items: ['Easy', 'Medium', 'Hard'].map((d) {
                                            return DropdownMenuItem(
                                              value: d,
                                              child: Text(
                                                d,
                                                style: TextStyle(
                                                  color: _getDifficultyColor(d),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (newVal) async {
                                            if (newVal != null) {
                                              await DatabaseHelper.instance
                                                  .updateDifficulty(q.id!, newVal);
                                              _loadQuestions();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    trailing: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isReviewed ? Colors.green : Colors.grey.shade200,
                                        foregroundColor: isReviewed ? Colors.white : Colors.black87,
                                      ),
                                      icon: Icon(
                                        isReviewed ? Icons.check_circle : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: isReviewed ? Colors.white : Colors.grey,
                                      ),
                                      label: Text(isReviewed ? 'Reviewed' : 'Mark Reviewed'),
                                      onPressed: () async {
                                        await DatabaseHelper.instance.toggleSolved(q.id!, q.isSolved);
                                        _loadQuestions();
                                      },
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(8),
                                      bottomRight: Radius.circular(8),
                                    ),
                                    child: Image.file(
                                      File(q.imagePath),
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
