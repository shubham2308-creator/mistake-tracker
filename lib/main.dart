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
  int isSolved;

  QuestionItem({
    this.id,
    required this.imagePath,
    required this.subject,
    required this.chapter,
    required this.errorType,
    this.isSolved = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'imagePath': imagePath,
        'subject': subject,
        'chapter': chapter,
        'errorType': errorType,
        'isSolved': isSolved,
      };

  factory QuestionItem.fromMap(Map<String, dynamic> map) => QuestionItem(
        id: map['id'],
        imagePath: map['imagePath'],
        subject: map['subject'],
        chapter: map['chapter'],
        errorType: map['errorType'],
        isSolved: map['isSolved'],
      );
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mistake_book.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE questions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          imagePath TEXT NOT NULL,
          subject TEXT NOT NULL,
          chapter TEXT NOT NULL,
          errorType TEXT NOT NULL,
          isSolved INTEGER NOT NULL
        )
      ''');
    });
  }

  Future<int> insertQuestion(QuestionItem item) async {
    final db = await instance.database;
    return await db.insert('questions', item.toMap());
  }

  Future<List<QuestionItem>> getQuestions({String? subject, int? isSolved}) async {
    final db = await instance.database;
    String whereString = '';
    List<dynamic> whereArgs = [];

    if (subject != null && subject != 'All') {
      whereString += 'subject = ?';
      whereArgs.add(subject);
    }
    if (isSolved != null) {
      if (whereString.isNotEmpty) whereString += ' AND ';
      whereString += 'isSolved = ?';
      whereArgs.add(isSolved);
    }

    final result = await db.query('questions',
        where: whereString.isEmpty ? null : whereString,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'id DESC');
    return result.map((e) => QuestionItem.fromMap(e)).toList();
  }

  Future<void> toggleSolved(int id, int currentStatus) async {
    final db = await instance.database;
    await db.update('questions', {'isSolved': currentStatus == 1 ? 0 : 1},
        where: 'id = ?', whereArgs: [id]);
  }
}

class ErrorBookApp extends StatelessWidget {
  const ErrorBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mistake Book',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
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
  bool showOnlyUnsolved = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.path.isNotEmpty) {
        _showSaveDialog(value.first.path);
      }
    });

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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Categorize Question'),
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
                TextField(
                  controller: chapterController,
                  decoration: const InputDecoration(
                    labelText: 'Chapter Name',
                    hintText: 'e.g. Rotational Motion',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: errorType,
                  items: ['Conceptual', 'Calculation', 'Time Trap', 'Silly Mistake']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => errorType = v!),
                  decoration: const InputDecoration(labelText: 'Error Reason'),
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
                  ),
                );

                Navigator.pop(ctx);
                _loadQuestions();
              },
              child: const Text('Save to Book'),
            )
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Improvement Book'),
        actions: [
          IconButton(
            icon: Icon(showOnlyUnsolved ? Icons.check_circle_outline : Icons.all_inbox),
            tooltip: 'Toggle Solved / Unsolved',
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['All', 'Physics', 'Chemistry', 'Biology'].map((subj) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(subj),
                    selected: selectedSubject == subj,
                    onSelected: (val) {
                      setState(() {
                        selectedSubject = subj;
                      });
                      _loadQuestions();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: questions.isEmpty
              ? const Center(
                  child: Text(
                    'No questions here! Take a screenshot and hit Share -> Mistake Book.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: questions.length,
                  itemBuilder: (ctx, i) {
                    final q = questions[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            title: Text('${q.subject} • ${q.chapter}'),
                            subtitle: Text('Error: ${q.errorType}'),
                            trailing: Checkbox(
                              value: q.isSolved == 1,
                              onChanged: (_) async {
                                await DatabaseHelper.instance.toggleSolved(q.id!, q.isSolved);
                                _loadQuestions();
                              },
                            ),
                          ),
                          Image.file(
                            File(q.imagePath),
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                        ],
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}
