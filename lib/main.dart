import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

late final SupabaseClient supabase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sekchgllbimoedsjoumi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFjIiwic2VydmljZV9yb2xlIiwiaWF0IjoxNzM1MDc0MDI3LCJleHAiOjIwNDA2NTAwMjcsInJvbGUiOiJodHRwczovL3Nla2NoZ2xsYmltb2VkcmpvdW1pLnN1cGFiYXNlLmNvIn0.2KyojN-jT9-7QV0SME6tKQOc030mCx1diz7aP31MA3E',
  );

  supabase = Supabase.instance.client;

  runApp(const MrOtakuApp());
}

/// =======================================================
/// أدوات عامة
/// =======================================================

Future<void> playClickSound() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

int toInt(dynamic value) {
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double toDouble(dynamic value) {
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String clean(dynamic value) {
  return value?.toString() ?? '';
}

String getUserLevel(int points) {
  if (points >= 100) return 'SS';
  if (points >= 70) return 'S';
  if (points >= 40) return 'A';
  if (points >= 20) return 'B';
  if (points >= 10) return 'C';
  if (points >= 5) return 'D';
  return 'E';
}

String quizTypeName(String type) {
  switch (type) {
    case 'guess_character':
      return 'احزر الشخصية';
    case 'image_character':
      return 'خمن الشخصية من الصورة';
    default:
      return 'أسئلة مباشرة';
  }
}

/// =======================================================
/// الشارات
/// =======================================================

class BadgeInfo {
  final int points;
  final String icon;
  final String name;

  const BadgeInfo({
    required this.points,
    required this.icon,
    required this.name,
  });
}

const List<BadgeInfo> otakuBadges = [
  BadgeInfo(points: 30, icon: '🥉', name: 'أوتاكو ممتاز'),
  BadgeInfo(points: 60, icon: '⚔️', name: 'محارب الأنمي'),
  BadgeInfo(points: 100, icon: '🥈', name: 'أوتاكو متقدم'),
  BadgeInfo(points: 150, icon: '🔥', name: 'عاشق الأنمي'),
  BadgeInfo(points: 250, icon: '💎', name: 'أوتاكو نادر'),
  BadgeInfo(points: 400, icon: '👑', name: 'سيد الأوتاكو'),
  BadgeInfo(points: 600, icon: '🌟', name: 'أسطورة الأنمي'),
  BadgeInfo(points: 1000, icon: '🏆', name: 'إمبراطور الأنمي'),
];

BadgeInfo? getCurrentBadge(int points) {
  BadgeInfo? current;
  for (final badge in otakuBadges) {
    if (points >= badge.points) {
      current = badge;
    }
  }
  return current;
}

/// =======================================================
/// جلسة المدير
/// =======================================================

Future<bool> checkAdminSession() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('mr_otaku_admin_session') ?? false;

  if (!saved) return false;

  final user = supabase.auth.currentUser;
  if (user == null) {
    await prefs.setBool('mr_otaku_admin_session', false);
    return false;
  }

  try {
    final admin = await supabase
        .from('admins')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    final result = admin != null;
    if (!result) {
      await prefs.setBool('mr_otaku_admin_session', false);
      await supabase.auth.signOut();
    }
    return result;
  } catch (e) {
    debugPrint('Admin session error: $e');
    return false;
  }
}

/// =======================================================
/// AppData
/// =======================================================

class AppData extends ChangeNotifier {
  List<Map<String, dynamic>> news = [];
  List<Map<String, dynamic>> players = [];
  List<Map<String, dynamic>> latest = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> purchaseRequests = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> quizQuestions = [];

  List<Map<String, dynamic>> ratingCharacters = [];
  List<Map<String, dynamic>> ratingAnime = [];
  List<Map<String, dynamic>> publicChat = [];

  final Map<dynamic, int> likeCounts = {};
  final Set<String> likedNews = {};
  final Map<dynamic, int> commentCounts = {};

  Map<String, dynamic>? activePoll;
  List<Map<String, dynamic>> activePollOptions = [];
  final Map<dynamic, int> pollVoteCounts = {};
  String? votedPollId;

  final Set<String> _readNotifications = {};

  bool loading = true;
  bool _isAdmin = false;

  int? currentAccountId;
  String currentUserName = '';

  bool get isAdmin => _isAdmin;
  bool get hasAccount =>
      currentAccountId != null && currentUserName.trim().isNotEmpty;
  bool get hasQuizQuestions => quizQuestions.isNotEmpty;

  int get unreadNotificationCount {
    return notifications.where((n) {
      return !_readNotifications.contains(n['id'].toString());
    }).length;
  }

  Map<String, dynamic>? get currentPlayer {
    if (currentAccountId == null) return null;
    for (final player in players) {
      if (toInt(player['account_id']) == currentAccountId) {
        return player;
      }
    }
    return null;
  }

  int get currentPoints => toInt(currentPlayer?['points']);
  String get currentLevel => getUserLevel(currentPoints);
  BadgeInfo? get currentBadge => getCurrentBadge(currentPoints);

  Map<String, dynamic>? get leader {
    if (players.isEmpty) return null;
    final sorted = [...players];
    sorted.sort((a, b) => toInt(b['points']).compareTo(toInt(a['points'])));
    return sorted.first;
  }

  Future<void> setAdminSession(bool value) async {
    _isAdmin = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mr_otaku_admin_session', value);
    notifyListeners();
  }

  Future<void> loadLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('mr_otaku_account_id');
    final name = prefs.getString('mr_otaku_user_name');
    currentAccountId = int.tryParse(id ?? '');
    currentUserName = name?.trim() ?? '';
  }

  Future<bool> loginAccount(String name, int accountId) async {
    if (name.trim().isEmpty || accountId <= 0) return false;

    try {
      final player = await supabase
          .from('players')
          .select()
          .eq('account_id', accountId)
          .maybeSingle();

      if (player == null) return false;

      final savedName = clean(player['name']).trim();
      if (savedName.toLowerCase() != name.trim().toLowerCase()) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mr_otaku_account_id', accountId.toString());
      await prefs.setString('mr_otaku_user_name', savedName);

      currentAccountId = accountId;
      currentUserName = savedName;

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Account login error: $e');
      return false;
    }
  }

  Future<void> logoutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mr_otaku_account_id');
    await prefs.remove('mr_otaku_user_name');

    currentAccountId = null;
    currentUserName = '';
    notifyListeners();
  }

  Future<void> loadData() async {
    loading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        supabase.from('news').select().order('created_at', ascending: false),
        supabase.from('players').select().order('points', ascending: false),
        supabase.from('latest').select().order('created_at', ascending: false),
      ]);

      news = List<Map<String, dynamic>>.from(results[0]);
      players = List<Map<String, dynamic>>.from(results[1]);
      latest = List<Map<String, dynamic>>.from(results[2]);

      await loadLikes();
      await loadCommentCounts();
      await loadNotifications();
      await loadPoll();
      await loadQuizQuestions();
      await loadRatingCharacters();
      await loadRatingAnime();
      await loadPublicChat();

      if (_isAdmin) {
        final messagesData = await supabase
            .from('messages')
            .select()
            .order('created_at', ascending: false);
        messages = List<Map<String, dynamic>>.from(messagesData);

        final requestsData = await supabase
            .from('purchase_requests')
            .select()
            .order('created_at', ascending: false);
        purchaseRequests = List<Map<String, dynamic>>.from(requestsData);
      } else {
        messages = [];
        purchaseRequests = [];
      }
    } catch (e) {
      debugPrint('Load data error: $e');
    }

    loading = false;
    notifyListeners();
  }

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('mr_otaku_client_id');

    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString('mr_otaku_client_id', id);
    }

    return id;
  }

  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId();
      final result =
          await supabase.from('news_likes').select('news_id, client_id');

      likeCounts.clear();
      likedNews.clear();

      for (final item in result) {
        final id = item['news_id'];
        likeCounts[id] = (likeCounts[id] ?? 0) + 1;

        if (clean(item['client_id']) == clientId) {
          likedNews.add(id.toString());
        }
      }
    } catch (e) {
      debugPrint('Likes error: $e');
    }
  }

  Future<bool> toggleLike(dynamic newsId) async {
    try {
      final clientId = await getClientId();
      final key = newsId.toString();

      if (likedNews.contains(key)) {
        await supabase
            .from('news_likes')
            .delete()
            .eq('news_id', newsId)
            .eq('client_id', clientId);

        likedNews.remove(key);
        likeCounts[newsId] = max(0, (likeCounts[newsId] ?? 1) - 1);
      } else {
        await supabase.from('news_likes').insert({
          'news_id': newsId,
          'client_id': clientId,
        });

        likedNews.add(key);
        likeCounts[newsId] = (likeCounts[newsId] ?? 0) + 1;
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Toggle like error: $e');
      return false;
    }
  }

  Future<void> loadCommentCounts() async {
    try {
      final result =
          await supabase.from('news_comments').select('news_id');

      commentCounts.clear();
      for (final item in result) {
        final id = item['news_id'];
        commentCounts[id] = (commentCounts[id] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('Comment count error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getComments(dynamic newsId) async {
    try {
      final result = await supabase
          .from('news_comments')
          .select()
          .eq('news_id', newsId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      return [];
    }
  }

  Future<bool> addComment(dynamic newsId, String userName, String text) async {
    if (text.trim().isEmpty) return false;

    try {
      final clientId = await getClientId();
      final name = currentUserName.trim().isNotEmpty
          ? currentUserName.trim()
          : userName.trim().isEmpty
              ? 'مستخدم'
              : userName.trim();

      await supabase.from('news_comments').insert({
        'news_id': newsId,
        'client_id': clientId,
        'user_name': name,
        'comment_text': text.trim(),
      });

      commentCounts[newsId] = (commentCounts[newsId] ?? 0) + 1;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add comment error: $e');
      return false;
    }
  }

  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('mr_otaku_read_notifications');

      _readNotifications.clear();
      if (saved != null) {
        _readNotifications.addAll(saved);
      }

      final result = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      notifications = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Notifications error: $e');
    }
  }

  Future<void> markNotificationRead(dynamic id) async {
    final prefs = await SharedPreferences.getInstance();
    _readNotifications.add(id.toString());
    await prefs.setStringList(
        'mr_otaku_read_notifications', _readNotifications.toList());
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in notifications) {
      _readNotifications.add(item['id'].toString());
    }
    await prefs.setStringList(
        'mr_otaku_read_notifications', _readNotifications.toList());
    notifyListeners();
  }

  Future<bool> addNotification(String title, String body) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      await supabase.from('notifications').insert({
        'title': title.trim(),
        'body': body.trim(),
      });

      await loadNotifications();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add notification error: $e');
      return false;
    }
  }

  Future<void> loadPoll() async {
    try {
      final polls = await supabase
          .from('polls')
          .select()
          .eq('active', true)
          .order('created_at', ascending: false);

      if (polls.isEmpty) {
        activePoll = null;
        activePollOptions = [];
        pollVoteCounts.clear();
        votedPollId = null;
        return;
      }

      activePoll = Map<String, dynamic>.from(polls.first);
      final pollId = activePoll!['id'];

      final options = await supabase
          .from('poll_options')
          .select()
          .eq('poll_id', pollId)
          .order('position', ascending: true);

      activePollOptions = List<Map<String, dynamic>>.from(options);

      final votes = await supabase
          .from('poll_votes')
          .select('option_id, client_id')
          .eq('poll_id', pollId);

      pollVoteCounts.clear();
      final clientId = await getClientId();
      votedPollId = null;

      for (final vote in votes) {
        final optionId = vote['option_id'];
        pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;

        if (clean(vote['client_id']) == clientId) {
          votedPollId = pollId.toString();
        }
      }
    } catch (e) {
      debugPrint('Poll load error: $e');
    }
  }

  bool get hasVotedInActivePoll {
    if (activePoll == null) return false;
    return votedPollId == clean(activePoll!['id']);
  }

  int get totalPollVotes {
    return pollVoteCounts.values.fold(0, (a, b) => a + b);
  }

  double getPollPercentage(dynamic optionId) {
    if (totalPollVotes == 0) return 0;
    return (pollVoteCounts[optionId] ?? 0) / totalPollVotes * 100;
  }

  Future<bool> votePoll(dynamic optionId) async {
    if (activePoll == null || hasVotedInActivePoll) return false;

    try {
      final clientId = await getClientId();
      await supabase.from('poll_votes').insert({
        'poll_id': activePoll!['id'],
        'option_id': optionId,
        'client_id': clientId,
      });

      votedPollId = clean(activePoll!['id']);
      pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Vote error: $e');
      return false;
    }
  }

  Future<void> loadQuizQuestions() async {
    try {
      final result = await supabase
          .from('quiz_questions')
          .select()
          .order('created_at', ascending: true);

      quizQuestions = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Quiz load error: $e');
      quizQuestions = [];
    }
  }

  Future<void> loadRatingCharacters() async {
    try {
      final result = await supabase
          .from('rating_characters')
          .select()
          .order('created_at', ascending: false);

      ratingCharacters = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      ratingCharacters = [];
    }
  }

  Future<void> loadRatingAnime() async {
    try {
      final result = await supabase
          .from('rating_anime')
          .select()
          .order('created_at', ascending: false);

      ratingAnime = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      ratingAnime = [];
    }
  }

  Future<void> loadPublicChat() async {
    try {
      final result = await supabase
          .from('public_chat')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      publicChat = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      publicChat = [];
    }
  }

  Future<bool> sendPublicChat(String message) async {
    if (message.trim().isEmpty) return false;

    try {
      await supabase.from('public_chat').insert({
        'account_id': currentAccountId,
        'user_name': currentUserName.trim().isEmpty
            ? 'مستخدم'
            : currentUserName.trim(),
        'message': message.trim(),
      });

      await loadPublicChat();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<double> characterAverage(dynamic characterId) async {
    try {
      final result = await supabase
          .from('character_ratings')
          .select('rating')
          .eq('character_id', characterId);

      if (result.isEmpty) return 0;
      double sum = 0;
      for (final row in result) {
        sum += toDouble(row['rating']);
      }
      return sum / result.length;
    } catch (e) {
      return 0;
    }
  }

  Future<double> animeAverage(dynamic animeId) async {
    try {
      final result = await supabase
          .from('anime_ratings')
          .select('rating')
          .eq('anime_id', animeId);

      if (result.isEmpty) return 0;
      double sum = 0;
      for (final row in result) {
        sum += toDouble(row['rating']);
      }
      return sum / result.length;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> rateCharacter(dynamic characterId, double rating) async {
    if (currentAccountId == null) return false;
    try {
      await supabase.from('character_ratings').upsert({
        'character_id': characterId,
        'account_id': currentAccountId!,
        'rating': rating,
        'updated_at': DateTime.now().toIso8601String(),
      });
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rateAnime(dynamic animeId, double rating) async {
    if (currentAccountId == null) return false;
    try {
      await supabase.from('anime_ratings').upsert({
        'anime_id': animeId,
        'account_id': currentAccountId!,
        'rating': rating,
        'updated_at': DateTime.now().toIso8601String(),
      });
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isFavorite(String type, dynamic id) async {
    if (currentAccountId == null) return false;
    try {
      final result = await supabase
          .from('favorites')
          .select('id')
          .eq('account_id', currentAccountId!)
          .eq('item_type', type)
          .eq('item_id', id)
          .maybeSingle();

      return result != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleFavorite(String type, dynamic id) async {
    if (currentAccountId == null) return false;
    try {
      final existing = await supabase
          .from('favorites')
          .select('id')
          .eq('account_id', currentAccountId!)
          .eq('item_type', type)
          .eq('item_id', id)
          .maybeSingle();

      if (existing != null) {
        await supabase.from('favorites').delete().eq('id', existing['id']);
      } else {
        await supabase.from('favorites').insert({
          'account_id': currentAccountId!,
          'item_type': type,
          'item_id': id,
        });
      }
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getFavorites(String type) async {
    if (currentAccountId == null) return [];
    try {
      final result = await supabase
          .from('favorites')
          .select()
          .eq('account_id', currentAccountId!)
          .eq('item_type', type)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      return [];
    }
  }
}

/// =======================================================
/// التطبيق
/// =======================================================

class MrOtakuApp extends StatefulWidget {
  const MrOtakuApp({super.key});

  @override
  State<MrOtakuApp> createState() => _MrOtakuAppState();
}

class _MrOtakuAppState extends State<MrOtakuApp> {
  final AppData data = AppData();
  bool checking = true;

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    final admin = await checkAdminSession();
    await data.setAdminSession(admin);

    if (!admin) {
      await data.loadLocalAccount();
    }

    await data.loadData();

    if (!mounted) return;
    setState(() {
      checking = false;
    });
  }

  ThemeData get theme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF100606),
      cardColor: const Color(0xFF241010),
      colorSchemeSeed: Colors.red.shade900,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A0808),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF1A0808),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF211010),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF241010),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AnimatedBuilder(
      animation: data,
      builder: (_, __) {
        Widget home;
        if (data.isAdmin) {
          home = AdminPanelPage(data: data);
        } else if (!data.hasAccount) {
          home = AccountSetupPage(data: data);
        } else {
          home = HomePage(data: data);
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مستر أوتاكو',
          theme: theme,
          home: home,
        );
      },
    );
  }
}

/// =======================================================
/// تسجيل الدخول بالحساب
/// =======================================================

class AccountSetupPage extends StatefulWidget {
  final AppData data;

  const AccountSetupPage({super.key, required this.data});

  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage> {
  final nameController = TextEditingController();
  final idController = TextEditingController();
  bool loading = false;

  Future<void> login() async {
    final name = nameController.text.trim();
    final id = int.tryParse(idController.text.trim());

    if (name.isEmpty || id == null || id <= 0) {
      showSnack(context, 'أدخل اسم المستخدم ومعرف الحساب بشكل صحيح.');
      return;
    }

    setState(() {
      loading = true;
    });

    await playClickSound();
    final success = await widget.data.loginAccount(name, id);

    if (!mounted) return;
    setState(() {
      loading = false;
    });

    if (!success) {
      showSnack(context, 'المعرف غير موجود أو الاسم لا يطابق الحساب.');
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(data: widget.data)),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome, size: 75),
                    const SizedBox(height: 15),
                    const Text(
                      'مستر أوتاكو',
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('تسجيل الدخول إلى حسابك',
                        style: TextStyle(fontSize: 17)),
                    const SizedBox(height: 25),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: idController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'معرف الحساب',
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loading ? null : login,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: const Text('دخول'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'إذا لم يكن لديك حساب، اطلب من الإدارة إنشاء حساب لك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================================================
/// الرئيسية
/// =======================================================

class HomePage extends StatefulWidget {
  final AppData data;

  const HomePage({super.key, required this.data});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(data: widget.data),
      NewsPage(data: widget.data),
      ServicesPage(data: widget.data),
      SettingsPage(data: widget.data),
    ];

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) async {
          await playClickSound();
          if (!mounted) return;
          setState(() {
            index = value;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: Icon(Icons.newspaper),
            label: 'الأخبار',
          ),
          const NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'الخدمات',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.data.unreadNotificationCount > 0,
              label: Text(widget.data.unreadNotificationCount.toString()),
              child: const Icon(Icons.settings_outlined),
            ),
            selectedIcon: const Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// الصفحة الرئيسية - التبويب الأول
/// =======================================================

class HomeTab extends StatefulWidget {
  final AppData data;

  const HomeTab({super.key, required this.data});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final PageController controller = PageController();
  Timer? timer;
  int newsIndex = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.data.news.isEmpty || !controller.hasClients) {
        return;
      }
      if (newsIndex >= widget.data.news.length) {
        newsIndex = 0;
      }
      newsIndex = (newsIndex + 1) % widget.data.news.length;
      controller.animateToPage(
        newsIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leader = widget.data.leader;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مستر أوتاكو',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () async {
              await playClickSound();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsPage(data: widget.data),
                ),
              );
            },
            icon: Badge(
              isLabelVisible: widget.data.unreadNotificationCount > 0,
              label: Text(widget.data.unreadNotificationCount.toString()),
              child: const Icon(Icons.notifications),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.data.loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF4A1010),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text(
                  'من تطوير برهان البريهي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.data.news.isNotEmpty)
              _NewsCarousel(data: widget.data, controller: controller),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome, size: 60),
                    const SizedBox(height: 10),
                    Text(
                      'مرحباً ${widget.data.currentUserName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('مجتمع ومسابقات وأخبار الأنمي'),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniStat(
                          title: 'النقاط',
                          value: widget.data.currentPoints.toString(),
                        ),
                        const SizedBox(width: 25),
                        _MiniStat(
                          title: 'المستوى',
                          value: widget.data.currentLevel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (leader != null)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.emoji_events)),
                  title: const Text('متصدر الأوتاكو',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(clean(leader['name'])),
                  trailing: Text('${toInt(leader['points'])} نقطة'),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.data.activePoll != null) PollCard(data: widget.data),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كل جديد',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    if (widget.data.latest.isEmpty)
                      const Text('لا يوجد جديد حالياً.')
                    else
                      ...widget.data.latest.take(5).map(
                        (item) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.campaign),
                            title: Text(clean(item['title'])),
                            subtitle: Text(clean(item['description'])),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStat({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(title, style: TextStyle(color: Colors.grey.shade400)),
      ],
    );
  }
}

class _NewsCarousel extends StatelessWidget {
  final AppData data;
  final PageController controller;

  const _NewsCarousel({required this.data, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: controller,
        itemCount: data.news.length,
        itemBuilder: (context, index) {
          final item = data.news[index];
          final image = clean(item['image_url']);

          return GestureDetector(
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewsDetailsPage(data: data, news: item),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration:
                  BoxDecoration(borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.isNotEmpty)
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF351010),
                        child: const Icon(Icons.newspaper, size: 50),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF351010),
                      child: const Icon(Icons.newspaper, size: 50),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Text(
                        clean(item['title']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// =======================================================
/// تفاصيل الخبر
/// =======================================================

class NewsDetailsPage extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> news;

  const NewsDetailsPage({super.key, required this.data, required this.news});

  @override
  Widget build(BuildContext context) {
    final image = clean(news['image_url']);

    return Scaffold(
      appBar: AppBar(title: const Text('الخبر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                image,
                height: 230,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 230,
                  child: Center(child: Icon(Icons.broken_image, size: 50)),
                ),
              ),
            ),
          const SizedBox(height: 15),
          Text(clean(news['title']),
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(clean(news['description']),
              style: const TextStyle(fontSize: 17, height: 1.6)),
        ],
      ),
    );
  }
}

/// =======================================================
/// استطلاع
/// =======================================================

class PollCard extends StatelessWidget {
  final AppData data;

  const PollCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.activePoll == null) return const SizedBox.shrink();
    final voted = data.hasVotedInActivePoll;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('استطلاع الرأي',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(clean(data.activePoll!['question']),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 10),
            ...data.activePollOptions.map((option) {
              final id = option['id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: voted
                      ? null
                      : () async {
                          await playClickSound();
                          await data.votePoll(id);
                        },
                  child: Row(
                    children: [
                      Expanded(child: Text(clean(option['option_text']))),
                      if (voted)
                        Text(
                            '${data.getPollPercentage(id).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// الأخبار
/// =======================================================

class NewsPage extends StatelessWidget {
  final AppData data;

  const NewsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأخبار')),
      body: RefreshIndicator(
        onRefresh: data.loadData,
        child: data.news.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('لا توجد أخبار حالياً.')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: data.news.length,
                itemBuilder: (_, index) =>
                    NewsCard(data: data, news: data.news[index]),
              ),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> news;

  const NewsCard({super.key, required this.data, required this.news});

  @override
  Widget build(BuildContext context) {
    final id = news['id'];
    final image = clean(news['image_url']);
    final liked = data.likedNews.contains(id.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty)
            Image.network(
              image,
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 210,
                child: Center(child: Icon(Icons.broken_image, size: 50)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clean(news['title']),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(clean(news['description'])),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        await playClickSound();
                        await data.toggleLike(id);
                      },
                      icon: Icon(
                          liked ? Icons.favorite : Icons.favorite_border),
                    ),
                    Text('${data.likeCounts[id] ?? 0}'),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () async {
                        await playClickSound();
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CommentsPage(data: data, newsId: id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.comment_outlined),
                    ),
                    Text('${data.commentCounts[id] ?? 0}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// التعليقات
/// =======================================================

class CommentsPage extends StatefulWidget {
  final AppData data;
  final dynamic newsId;

  const CommentsPage({super.key, required this.data, required this.newsId});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.data.getComments(widget.newsId);
    if (!mounted) return;
    setState(() {
      comments = result;
      loading = false;
    });
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;
    await playClickSound();

    final ok = await widget.data.addComment(
      widget.newsId,
      widget.data.currentUserName,
      controller.text,
    );

    if (!mounted) return;
    if (ok) {
      controller.clear();
      await load();
    } else {
      showSnack(context, 'تعذر إرسال التعليق.');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التعليقات')),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : comments.isEmpty
                    ? const Center(child: Text('لا توجد تعليقات بعد.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: comments.length,
                        itemBuilder: (_, index) {
                          final item = comments[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.person)),
                              title: Text(clean(item['user_name'])),
                              subtitle: Text(clean(item['comment_text'])),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(labelText: 'اكتب تعليقك'),
                  ),
                ),
                IconButton(onPressed: send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// الإشعارات
/// =======================================================

class NotificationsPage extends StatelessWidget {
  final AppData data;

  const NotificationsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (data.notifications.isNotEmpty)
            IconButton(
              onPressed: () async {
                await playClickSound();
                await data.markAllNotificationsRead();
              },
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: data.notifications.isEmpty
          ? const Center(child: Text('لا توجد إشعارات.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.notifications.length,
              itemBuilder: (_, index) {
                final item = data.notifications[index];
                final id = item['id'];
                final read =
                    data._readNotifications.contains(id.toString());

                return Card(
                  child: ListTile(
                    leading: Icon(
                      read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(clean(item['title']),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(clean(item['body'])),
                    onTap: () async {
                      await data.markNotificationRead(id);
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// =======================================================
/// الخدمات
/// =======================================================

class ServicesPage extends StatelessWidget {
  final AppData data;

  const ServicesPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ServiceTile(
            icon: Icons.quiz,
            title: 'لعبة الأسئلة',
            subtitle: 'ثلاثة أنواع من الأسئلة',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionsHubPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.star_rate,
            title: 'تقييمات الأنمي',
            subtitle: 'قيّم الشخصيات والأنميات',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RatingsPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.favorite,
            title: 'المفضلة',
            subtitle: 'الشخصيات والأنميات المفضلة',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FavoritesPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.chat,
            title: 'الدردشة العامة',
            subtitle: 'تحدث مع مجتمع مستر أوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicChatPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.sports_esports,
            title: 'لعبة القفز',
            subtitle: 'اقفز فوق الصخور وحطم رقمك',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JumpGamePage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.leaderboard,
            title: 'المتصدرون',
            subtitle: 'شاهد ترتيب لاعبي الأوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeaderboardPage(data: data),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const ServiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

/// =======================================================
/// الصفحات الملحقة
/// =======================================================

class SettingsPage extends StatelessWidget {
  final AppData data;

  const SettingsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle, size: 40),
              title: Text(data.currentUserName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('معرف الحساب: ${data.currentAccountId ?? "غير معروف"}'),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await data.logoutAccount();
            },
          ),
        ],
      ),
    );
  }
}

class QuestionsHubPage extends StatelessWidget {
  final AppData data;

  const QuestionsHubPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة الأسئلة')),
      body: const Center(child: Text('صفحة الأسئلة')),
    );
  }
}

class RatingsPage extends StatelessWidget {
  final AppData data;

  const RatingsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقييمات الأنمي')),
      body: const Center(child: Text('صفحة التقييمات')),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  final AppData data;

  const FavoritesPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: const Center(child: Text('صفحة المفضلة')),
    );
  }
}

class PublicChatPage extends StatelessWidget {
  final AppData data;

  const PublicChatPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدردشة العامة')),
      body: const Center(child: Text('صفحة الدردشة')),
    );
  }
}

class JumpGamePage extends StatelessWidget {
  final AppData data;

  const JumpGamePage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة القفز')),
      body: const Center(child: Text('صفحة لعبة القفز')),
    );
  }
}

class LeaderboardPage extends StatelessWidget {
  final AppData data;

  const LeaderboardPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: const Center(child: Text('جدول المتصدرين')),
    );
  }
}

class AdminPanelPage extends StatelessWidget {
  final AppData data;

  const AdminPanelPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم')),
      body: const Center(child: Text('صفحة لوحة التحكم للمدير')),
    );
  }
}
