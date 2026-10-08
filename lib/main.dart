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
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNla2NoZ2xsYmltb2Vkc2pvdW1pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzI3NTk5MDAsImV4cCI6MjA0ODMzNTkwMH0.2KyojN-jT9-7QV0SME6tKQOc030mCx1diz7aP31MA3E',
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

    sorted.sort(
      (a, b) => toInt(b['points']).compareTo(toInt(a['points'])),
    );

    return sorted.first;
  }

  Future<void> setAdminSession(bool value) async {
    _isAdmin = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mr_otaku_admin_session', value);

    notifyListeners();
  }

  /// ===================== الحساب =====================

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

      await prefs.setString(
        'mr_otaku_account_id',
        accountId.toString(),
      );
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

  /// ===================== تحميل البيانات =====================

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

        purchaseRequests =
            List<Map<String, dynamic>>.from(requestsData);
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

  /// ===================== Client ID =====================

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();

    String? id = prefs.getString('mr_otaku_client_id');

    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString('mr_otaku_client_id', id);
    }

    return id;
  }

  /// ===================== الإعجابات =====================

  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId();

      final result = await supabase
          .from('news_likes')
          .select('news_id, client_id');

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

  /// ===================== التعليقات =====================

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

  Future<List<Map<String, dynamic>>> getComments(
    dynamic newsId,
  ) async {
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

  Future<bool> addComment(
    dynamic newsId,
    String userName,
    String text,
  ) async {
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

  /// ===================== الإشعارات =====================

  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saved =
          prefs.getStringList('mr_otaku_read_notifications');

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
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();

    for (final item in notifications) {
      _readNotifications.add(item['id'].toString());
    }

    await prefs.setStringList(
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

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

  /// ===================== الاستطلاع =====================

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

        pollVoteCounts[optionId] =
            (pollVoteCounts[optionId] ?? 0) + 1;

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

  Future<bool> createPoll(
    String question,
    List<String> options,
  ) async {
    if (!_isAdmin || question.trim().isEmpty || options.length < 2) {
      return false;
    }

    try {
      await supabase
          .from('polls')
          .update({'active': false})
          .eq('active', true);

      final poll = await supabase
          .from('polls')
          .insert({'question': question.trim(), 'active': true})
          .select()
          .single();

      for (int i = 0; i < options.length; i++) {
        if (options[i].trim().isEmpty) continue;

        await supabase.from('poll_options').insert({
          'poll_id': poll['id'],
          'option_text': options[i].trim(),
          'position': i,
        });
      }

      await loadPoll();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Create poll error: $e');
      return false;
    }
  }

  /// ===================== الأسئلة =====================

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

  Future<bool> addQuizQuestion({
    required String question,
    required String option1,
    required String option2,
    required String option3,
    required String option4,
    required int correctOption,
    String quizType = 'direct',
    String? imageUrl,
  }) async {
    if (!_isAdmin ||
        question.trim().isEmpty ||
        option1.trim().isEmpty ||
        option2.trim().isEmpty ||
        option3.trim().isEmpty ||
        option4.trim().isEmpty ||
        correctOption < 1 ||
        correctOption > 4) {
      return false;
    }

    try {
      await supabase.from('quiz_questions').insert({
        'question': question.trim(),
        'option1': option1.trim(),
        'option2': option2.trim(),
        'option3': option3.trim(),
        'option4': option4.trim(),
        'correct_option': correctOption,
        'quiz_type': quizType,
        'image_url': imageUrl,
      });

      await loadQuizQuestions();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add quiz error: $e');
      return false;
    }
  }

  Future<bool> updateQuizQuestion({
    required dynamic id,
    required String question,
    required String option1,
    required String option2,
    required String option3,
    required String option4,
    required int correctOption,
    String quizType = 'direct',
    String? imageUrl,
  }) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('quiz_questions')
          .update({
            'question': question.trim(),
            'option1': option1.trim(),
            'option2': option2.trim(),
            'option3': option3.trim(),
            'option4': option4.trim(),
            'correct_option': correctOption,
            'quiz_type': quizType,
            'image_url': imageUrl,
          })
          .eq('id', id);

      await loadQuizQuestions();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Update quiz error: $e');
      return false;
    }
  }

  Future<bool> deleteQuizQuestion(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('quiz_questions')
          .delete()
          .eq('id', id);

      await loadQuizQuestions();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> uploadQuizImage(File file) async {
    if (!_isAdmin) return null;

    try {
      final extension = file.path.split('.').last.toLowerCase();
      final path =
          'quiz/${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('news-images').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Quiz image upload error: $e');
      return null;
    }
  }

  /// ===================== الأخبار =====================

  Future<bool> addNews(
    String title,
    String description, {
    File? imageFile,
  }) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      String? imageUrl;

      if (imageFile != null) {
        final extension =
            imageFile.path.split('.').last.toLowerCase();
        final path =
            'news_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await supabase.storage.from('news-images').upload(
              path,
              imageFile,
              fileOptions: const FileOptions(upsert: false),
            );

        imageUrl =
            supabase.storage.from('news-images').getPublicUrl(path);
      }

      await supabase.from('news').insert({
        'title': title.trim(),
        'description': description.trim(),
        'image_url': imageUrl,
      });

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Add news error: $e');
      return false;
    }
  }

  Future<bool> deleteNews(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('news').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== اللاعبين =====================

  Future<bool> addPlayer(
    String name,
    int points, {
    int? accountId,
  }) async {
    if (!_isAdmin || name.trim().isEmpty) return false;

    try {
      if (accountId != null) {
        if (accountId <= 0) return false;

        final exists = await supabase
            .from('players')
            .select('id')
            .eq('account_id', accountId)
            .maybeSingle();

        if (exists != null) return false;
      }

      await supabase.from('players').insert({
        'name': name.trim(),
        'points': max(0, points),
        if (accountId != null) 'account_id': accountId,
      });

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Add player error: $e');
      return false;
    }
  }

  Future<bool> updatePlayer(
    dynamic id,
    String name,
    int points, {
    int? accountId,
  }) async {
    if (!_isAdmin || name.trim().isEmpty) return false;

    try {
      if (accountId != null) {
        final existing = await supabase
            .from('players')
            .select('id')
            .eq('account_id', accountId)
            .maybeSingle();

        if (existing != null && clean(existing['id']) != clean(id)) {
          return false;
        }
      }

      await supabase
          .from('players')
          .update({
            'name': name.trim(),
            'points': max(0, points),
            'account_id': accountId,
          })
          .eq('id', id);

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Update player error: $e');
      return false;
    }
  }

  Future<bool> deletePlayer(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('players').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== كل جديد =====================

  Future<bool> addLatest(String title, String description) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      await supabase.from('latest').insert({
        'title': title.trim(),
        'description': description.trim(),
      });

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteLatest(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('latest').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== الرسائل =====================

  Future<bool> sendMessage(String name, String message) async {
    if (message.trim().isEmpty) return false;

    try {
      await supabase.from('messages').insert({
        'name': currentUserName.trim().isNotEmpty
            ? currentUserName
            : name.trim().isEmpty
                ? 'مستخدم'
                : name.trim(),
        'message': message.trim(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteMessage(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('messages').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== المشتريات =====================

  Future<bool> createPurchaseRequest(
    dynamic playerId,
    String itemType,
    int cost,
  ) async {
    try {
      await supabase.from('purchase_requests').insert({
        'player_id': playerId,
        'item_type': itemType,
        'cost': cost,
        'status': 'pending',
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approvePurchase(Map<String, dynamic> request) async {
    if (!_isAdmin || request['status'] != 'pending') return false;

    try {
      final playerId = request['player_id'];
      final cost = toInt(request['cost']);

      final player = await supabase
          .from('players')
          .select()
          .eq('id', playerId)
          .maybeSingle();

      if (player == null) return false;

      final points = toInt(player['points']);

      if (points < cost) return false;

      await supabase
          .from('players')
          .update({'points': points - cost})
          .eq('id', playerId);

      await supabase
          .from('purchase_requests')
          .update({'status': 'approved'})
          .eq('id', request['id']);

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectPurchase(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('purchase_requests')
          .update({'status': 'rejected'})
          .eq('id', id);

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== الشخصيات =====================

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

  Future<bool> addCharacter(
    String name,
    String description, {
    File? imageFile,
  }) async {
    if (!_isAdmin || name.trim().isEmpty) return false;

    try {
      String? imageUrl;

      if (imageFile != null) {
        imageUrl = await uploadGeneralImage(imageFile, 'characters');
      }

      await supabase.from('rating_characters').insert({
        'name': name.trim(),
        'description': description.trim(),
        'image_url': imageUrl,
      });

      await loadRatingCharacters();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateCharacter(
    dynamic id,
    String name,
    String description, {
    String? imageUrl,
    File? imageFile,
  }) async {
    if (!_isAdmin) return false;

    try {
      String? finalImage = imageUrl;

      if (imageFile != null) {
        finalImage = await uploadGeneralImage(imageFile, 'characters');
      }

      await supabase
          .from('rating_characters')
          .update({
            'name': name.trim(),
            'description': description.trim(),
            'image_url': finalImage,
          })
          .eq('id', id);

      await loadRatingCharacters();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteCharacter(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('rating_characters')
          .delete()
          .eq('id', id);

      await loadRatingCharacters();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// ===================== الأنميات =====================

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

  Future<bool> addAnime(
    String title,
    String description, {
    File? imageFile,
  }) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      String? imageUrl;

      if (imageFile != null) {
        imageUrl = await uploadGeneralImage(imageFile, 'anime');
      }

      await supabase.from('rating_anime').insert({
        'title': title.trim(),
        'description': description.trim(),
        'image_url': imageUrl,
      });

      await loadRatingAnime();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateAnime(
    dynamic id,
    String title,
    String description, {
    String? imageUrl,
    File? imageFile,
  }) async {
    if (!_isAdmin) return false;

    try {
      String? finalImage = imageUrl;

      if (imageFile != null) {
        finalImage = await uploadGeneralImage(imageFile, 'anime');
      }

      await supabase
          .from('rating_anime')
          .update({
            'title': title.trim(),
            'description': description.trim(),
            'image_url': finalImage,
          })
          .eq('id', id);

      await loadRatingAnime();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteAnime(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('rating_anime').delete().eq('id', id);
      await loadRatingAnime();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> uploadGeneralImage(
    File file,
    String folder,
  ) async {
    try {
      final extension = file.path.split('.').last.toLowerCase();
      final path =
          '$folder/${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('news-images').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  /// ===================== التقييمات =====================

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

    if (rating < 0 ||
        rating > 10 ||
        (rating * 2).roundToDouble() != rating * 2) {
      return false;
    }

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

    if (rating < 0 ||
        rating > 10 ||
        (rating * 2).roundToDouble() != rating * 2) {
      return false;
    }

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

  /// ===================== المفضلة =====================

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
        await supabase
            .from('favorites')
            .delete()
            .eq('id', existing['id']);
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

  /// ===================== الدردشة =====================

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

  Future<bool> deletePublicChat(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('public_chat').delete().eq('id', id);
      await loadPublicChat();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
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

  const AccountSetupPage({
    super.key,
    required this.data,
  });

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
      showSnack(
        context,
        'أدخل اسم المستخدم ومعرف الحساب بشكل صحيح.',
      );
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
      showSnack(
        context,
        'المعرف غير موجود أو الاسم لا يطابق الحساب.',
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(data: widget.data),
      ),
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
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تسجيل الدخول إلى حسابك',
                      style: TextStyle(fontSize: 17),
                    ),
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

  const HomePage({
    super.key,
    required this.data,
  });

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
      body: IndexedStack(index: index, children: pages),
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
              label: Text(
                widget.data.unreadNotificationCount.toString(),
              ),
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
/// الصفحة الرئيسية
/// =======================================================

class HomeTab extends StatefulWidget {
  final AppData data;

  const HomeTab({
    super.key,
    required this.data,
  });

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

    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted ||
            widget.data.news.isEmpty ||
            !controller.hasClients) {
          return;
        }

        if (newsIndex + 1 >= widget.data.news.length) {
          newsIndex = 0;
        } else {
          newsIndex++;
        }

        if (!controller.hasClients) return;

        controller.animateToPage(
          newsIndex,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOut,
        );
      },
    );
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
        title: const Text(
          'مستر أوتاكو',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
              label: Text(
                widget.data.unreadNotificationCount.toString(),
              ),
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.data.news.isNotEmpty)
              _NewsCarousel(
                data: widget.data,
                controller: controller,
              ),
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
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
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
                  leading: const CircleAvatar(
                    child: Icon(Icons.emoji_events),
                  ),
                  title: const Text(
                    'متصدر الأوتاكو',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(clean(leader['name'])),
                  trailing: Text('${toInt(leader['points'])} نقطة'),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.data.activePoll != null)
              PollCard(data: widget.data),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كل جديد',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.data.latest.isEmpty)
                      const Text('لا يوجد جديد حالياً.')
                    else
                      ...widget.data.latest.take(5).map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.campaign),
                              title: Text(clean(item['title'])),
                              subtitle: Text(
                                clean(item['description']),
                              ),
                            ),
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

  const _MiniStat({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: TextStyle(color: Colors.grey.shade400),
        ),
      ],
    );
  }
}

/// =======================================================
/// شريط الأخبار
/// =======================================================

class _NewsCarousel extends StatelessWidget {
  final AppData data;
  final PageController controller;

  const _NewsCarousel({
    required this.data,
    required this.controller,
  });

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
                  builder: (_) => NewsDetailsPage(
                    data: data,
                    news: item,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 4, left: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.isNotEmpty)
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: const Color(0xFF351010),
                          child: const Icon(
                            Icons.newspaper,
                            size: 50,
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      color: const Color(0xFF351010),
                      child: const Icon(
                        Icons.newspaper,
                        size: 50,
                      ),
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
                          colors: [
                            Colors.transparent,
                            Colors.black87,
                          ],
                        ),
                      ),
                      child: Text(
                        clean(item['title']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
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

  const NewsDetailsPage({
    super.key,
    required this.data,
    required this.news,
  });

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
                errorBuilder: (_, __, ___) {
                  return const SizedBox(
                    height: 230,
                    child: Center(
                      child: Icon(Icons.broken_image, size: 50),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 15),
          Text(
            clean(news['title']),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            clean(news['description']),
            style: const TextStyle(fontSize: 17, height: 1.6),
          ),
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

  const PollCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final voted = data.hasVotedInActivePoll;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'استطلاع الرأي',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              clean(data.activePoll!['question']),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
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
                      Expanded(
                        child: Text(
                          clean(option['option_text']),
                        ),
                      ),
                      if (voted)
                        Text(
                          '${data.getPollPercentage(id).toStringAsFixed(0)}%',
                        ),
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

  const NewsPage({
    super.key,
    required this.data,
  });

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
                itemBuilder: (_, index) {
                  return NewsCard(
                    data: data,
                    news: data.news[index],
                  );
                },
              ),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> news;

  const NewsCard({
    super.key,
    required this.data,
    required this.news,
  });

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
              errorBuilder: (_, __, ___) {
                return const SizedBox(
                  width: double.infinity,
                  height: 210,
                  child: Center(
                    child: Icon(Icons.broken_image, size: 50),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clean(news['title']),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                        liked ? Icons.favorite : Icons.favorite_border,
                      ),
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
                            builder: (_) => CommentsPage(
                              data: data,
                              newsId: id,
                            ),
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

  const CommentsPage({
    super.key,
    required this.data,
    required this.newsId,
  });

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
                    ? const Center(
                        child: Text('لا توجد تعليقات بعد.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: comments.length,
                        itemBuilder: (_, index) {
                          final item = comments[index];

                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: Text(
                                clean(item['user_name']),
                              ),
                              subtitle: Text(
                                clean(item['comment_text']),
                              ),
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
                    decoration: const InputDecoration(
                      labelText: 'اكتب تعليقك',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send),
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
/// الإشعارات
/// =======================================================

class NotificationsPage extends StatelessWidget {
  final AppData data;

  const NotificationsPage({
    super.key,
    required this.data,
  });

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
                final read = data._readNotifications
                    .contains(id.toString());

                return Card(
                  child: ListTile(
                    leading: Icon(
                      read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(
                      clean(item['title']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

  const ServicesPage({
    super.key,
    required this.data,
  });

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
          ServiceTile(
            icon: Icons.shopping_bag,
            title: 'متجر النقاط',
            subtitle: 'استخدم نقاطك للحصول على المزايا',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.message,
            title: 'إرسال رسالة',
            subtitle: 'تواصل مع إدارة مستر أوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SendMessagePage(data: data),
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
        onTap: onTap,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_back_ios, size: 18),
      ),
    );
  }
}

/// =======================================================
/// مركز الأسئلة
/// =======================================================

class QuestionsHubPage extends StatelessWidget {
  final AppData data;

  const QuestionsHubPage({
    super.key,
    required this.data,
  });

  Future<void> open(BuildContext context, String type) async {
    await playClickSound();
    await data.loadQuizQuestions();

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizPage(data: data, typeFilter: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأسئلة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _QuestionTypeCard(
            icon: Icons.person_search,
            title: 'احزر الشخصية',
            description: 'سؤال نصي مع أربعة اختيارات.',
            onTap: () => open(context, 'guess_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.image_search,
            title: 'خمن اسم الشخصية من الصورة',
            description: 'تظهر صورة الشخصية مع أربعة أسماء.',
            onTap: () => open(context, 'image_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.help_outline,
            title: 'أسئلة مباشرة',
            description: 'أسئلة مباشرة عن الأنمي والشخصيات.',
            onTap: () => open(context, 'direct'),
          ),
        ],
      ),
    );
  }
}

class _QuestionTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _QuestionTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(radius: 28, child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_back_ios),
        onTap: onTap,
      ),
    );
  }
}

/// =======================================================
/// لعبة الأسئلة
/// =======================================================

class QuizPage extends StatefulWidget {
  final AppData data;
  final String typeFilter;

  const QuizPage({
    super.key,
    required this.data,
    required this.typeFilter,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<Map<String, dynamic>> questions;

  int current = 0;
  int correctAnswers = 0;
  int? selected;
  bool answered = false;

  @override
  void initState() {
    super.initState();

    questions = widget.data.quizQuestions.where((q) {
      final rawType = clean(q['quiz_type']);
      final type = rawType.isEmpty ? 'direct' : rawType;
      return type == widget.typeFilter;
    }).toList();
  }

  Map<String, dynamic>? get currentQuestion {
    if (questions.isEmpty || current >= questions.length) return null;
    return questions[current];
  }

  String option(int number) {
    return clean(currentQuestion?['option$number']);
  }

  Future<void> answer(int number) async {
    if (answered || currentQuestion == null) return;

    await playClickSound();

    final correct = toInt(currentQuestion!['correct_option']);

    setState(() {
      selected = number;
      answered = true;

      if (number == correct) {
        correctAnswers++;
      }
    });
  }

  void next() {
    if (!answered) return;

    if (current + 1 >= questions.length) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuizResultPage(
            data: widget.data,
            correct: correctAnswers,
            total: questions.length,
            typeFilter: widget.typeFilter,
          ),
        ),
      );
      return;
    }

    setState(() {
      current++;
      selected = null;
      answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(quizTypeName(widget.typeFilter)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'لا توجد أسئلة من هذا النوع حالياً.\nيمكن للمدير إضافتها من لوحة الإدارة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    final q = currentQuestion!;
    final correct = toInt(q['correct_option']);

    return Scaffold(
      appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(
            value: (current + 1) / questions.length,
          ),
          const SizedBox(height: 12),
          Text(
            'السؤال ${current + 1} من ${questions.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (widget.typeFilter == 'image_character' &&
              clean(q['image_url']).isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                clean(q['image_url']),
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return const SizedBox(
                    height: 150,
                    child: Center(
                      child: Icon(Icons.broken_image, size: 50),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                clean(q['question']),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          for (int i = 1; i <= 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: answered ? null : () => answer(i),
                  style: FilledButton.styleFrom(
                    backgroundColor: answered && i == correct
                        ? Colors.green
                        : answered && i == selected
                            ? Colors.red
                            : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      option(i),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          if (answered)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Icon(
                      selected == correct
                          ? Icons.check_circle
                          : Icons.cancel,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selected == correct
                            ? 'إجابة صحيحة! 🔥'
                            : 'إجابة خاطئة. الإجابة الصحيحة هي: ${option(correct)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: answered ? next : null,
            icon: const Icon(Icons.arrow_back),
            label: Text(
              current + 1 >= questions.length
                  ? 'عرض النتيجة'
                  : 'السؤال التالي',
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// نتيجة الأسئلة
/// =======================================================

class QuizResultPage extends StatelessWidget {
  final AppData data;
  final int correct;
  final int total;
  final String typeFilter;

  const QuizResultPage({
    super.key,
    required this.data,
    required this.correct,
    required this.total,
    required this.typeFilter,
  });

  double get percentage {
    if (total == 0) return 0;
    return correct / total * 100;
  }

  String get message {
    if (percentage >= 90) return 'أسطوري! معلوماتك رائعة 🏆';
    if (percentage >= 70) return 'ممتاز! مستواك قوي جداً 🔥';
    if (percentage >= 50) return 'جيد! يمكنك الوصول للأفضل ⚔️';
    return 'تحتاج إلى المزيد من التدريب 😄';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events, size: 80),
                  const SizedBox(height: 15),
                  const Text(
                    'نتيجتك',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('$correct من $total إجابات صحيحة'),
                  const SizedBox(height: 15),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => QuizPage(
                              data: data,
                              typeFilter: typeFilter,
                            ),
                          ),
                        );
                      },
                      child: const Text('إعادة الاختبار'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('العودة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================================================
/// التقييمات
/// =======================================================

class RatingsPage extends StatefulWidget {
  final AppData data;

  const RatingsPage({
    super.key,
    required this.data,
  });

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage>
    with SingleTickerProviderStateMixin {
  late TabController tabs;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقييمات'),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'الشخصيات', icon: Icon(Icons.person)),
            Tab(text: 'الأنميات', icon: Icon(Icons.movie)),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          CharacterRatingsList(data: widget.data),
          AnimeRatingsList(data: widget.data),
        ],
      ),
    );
  }
}

class CharacterRatingsList extends StatefulWidget {
  final AppData data;

  const CharacterRatingsList({
    super.key,
    required this.data,
  });

  @override
  State<CharacterRatingsList> createState() =>
      _CharacterRatingsListState();
}

class _CharacterRatingsListState extends State<CharacterRatingsList> {
  Map<dynamic, double> averages = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final map = <dynamic, double>{};

    for (final item in widget.data.ratingCharacters) {
      map[item['id']] =
          await widget.data.characterAverage(item['id']);
    }

    if (!mounted) return;

    setState(() {
      averages = map;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = [...widget.data.ratingCharacters];

    list.sort(
      (a, b) => (averages[b['id']] ?? 0)
          .compareTo(averages[a['id']] ?? 0),
    );

    return RefreshIndicator(
      onRefresh: load,
      child: list.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 200),
                Center(
                  child: Text('لا توجد شخصيات للتقييم حالياً.'),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final item = list[index];

                return RatingItemCard(
                  title: clean(item['name']),
                  description: clean(item['description']),
                  imageUrl: clean(item['image_url']),
                  average: averages[item['id']] ?? 0,
                  onRate: () => showRatingDialog(
                    context,
                    'character',
                    item['id'],
                    widget.data,
                  ),
                  onFavorite: () async {
                    await widget.data.toggleFavorite(
                      'character',
                      item['id'],
                    );

                    if (mounted) setState(() {});
                  },
                );
              },
            ),
    );
  }
}

class AnimeRatingsList extends StatefulWidget {
  final AppData data;

  const AnimeRatingsList({
    super.key,
    required this.data,
  });

  @override
  State<AnimeRatingsList> createState() => _AnimeRatingsListState();
}

class _AnimeRatingsListState extends State<AnimeRatingsList> {
  Map<dynamic, double> averages = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final map = <dynamic, double>{};

    for (final item in widget.data.ratingAnime) {
      map[item['id']] =
          await widget.data.animeAverage(item['id']);
    }

    if (!mounted) return;

    setState(() {
      averages = map;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = [...widget.data.ratingAnime];

    list.sort(
      (a, b) => (averages[b['id']] ?? 0)
          .compareTo(averages[a['id']] ?? 0),
    );

    return RefreshIndicator(
      onRefresh: load,
      child: list.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 200),
                Center(
                  child: Text('لا توجد أنميات للتقييم حالياً.'),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final item = list[index];

                return RatingItemCard(
                  title: clean(item['title']),
                  description: clean(item['description']),
                  imageUrl: clean(item['image_url']),
                  average: averages[item['id']] ?? 0,
                  onRate: () => showRatingDialog(
                    context,
                    'anime',
                    item['id'],
                    widget.data,
                  ),
                  onFavorite: () async {
                    await widget.data.toggleFavorite(
                      'anime',
                      item['id'],
                    );

                    if (mounted) setState(() {});
                  },
                );
              },
            ),
    );
  }
}

class RatingItemCard extends StatelessWidget {
  final String title;
  final String description;
  final String imageUrl;
  final double average;
  final VoidCallback onRate;
  final VoidCallback onFavorite;

  const RatingItemCard({
    super.key,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.average,
    required this.onRate,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: Center(
                    child: Icon(Icons.broken_image, size: 45),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.star),
                    const SizedBox(width: 5),
                    Text(
                      average.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onFavorite,
                      icon: const Icon(Icons.favorite_border),
                    ),
                    FilledButton(
                      onPressed: onRate,
                      child: const Text('قيّم'),
                    ),
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

Future<void> showRatingDialog(
  BuildContext context,
  String type,
  dynamic id,
  AppData data,
) async {
  double value = 5;

  await showDialog(
    context: context,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('اختر تقييمك'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Slider(
                  value: value,
                  min: 0,
                  max: 10,
                  divisions: 20,
                  label: value.toStringAsFixed(1),
                  onChanged: (v) {
                    setState(() {
                      value = v;
                    });
                  },
                ),
                const Text('التقييم من 0 إلى 10 بنصف نقطة'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  await playClickSound();

                  final ok = type == 'character'
                      ? await data.rateCharacter(id, value)
                      : await data.rateAnime(id, value);

                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(
                      context,
                      ok
                          ? 'تم حفظ تقييمك.'
                          : 'تعذر حفظ التقييم.',
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// =======================================================
/// المفضلة
/// =======================================================

class FavoritesPage extends StatefulWidget {
  final AppData data;

  const FavoritesPage({
    super.key,
    required this.data,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late TabController tabs;

  List<Map<String, dynamic>> characterFavorites = [];
  List<Map<String, dynamic>> animeFavorites = [];

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this);
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final characters =
        await widget.data.getFavorites('character');
    final anime = await widget.data.getFavorites('anime');

    if (!mounted) return;

    setState(() {
      characterFavorites = characters;
      animeFavorites = anime;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المفضلة'),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'الشخصيات'),
            Tab(text: 'الأنميات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          FavoritesList(
            favorites: characterFavorites,
            source: widget.data.ratingCharacters,
            titleKey: 'name',
            type: 'character',
            data: widget.data,
            onRefresh: load,
          ),
          FavoritesList(
            favorites: animeFavorites,
            source: widget.data.ratingAnime,
            titleKey: 'title',
            type: 'anime',
            data: widget.data,
            onRefresh: load,
          ),
        ],
      ),
    );
  }
}

class FavoritesList extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> source;
  final String titleKey;
  final String type;
  final AppData data;
  final Future<void> Function() onRefresh;

  const FavoritesList({
    super.key,
    required this.favorites,
    required this.source,
    required this.titleKey,
    required this.type,
    required this.data,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[];

    for (final fav in favorites) {
      for (final item in source) {
        if (clean(item['id']) == clean(fav['item_id'])) {
          items.add(item);
        }
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 200),
                Center(child: Text('لا توجد عناصر مفضلة.')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                final image = clean(item['image_url']);

                return Card(
                  child: ListTile(
                    leading: image.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(image),
                          )
                        : const CircleAvatar(
                            child: Icon(Icons.movie),
                          ),
                    title: Text(clean(item[titleKey])),
                    trailing: IconButton(
                      onPressed: () async {
                        await playClickSound();
                        await data.toggleFavorite(type, item['id']);
                        await onRefresh();
                      },
                      icon: const Icon(Icons.favorite),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// =======================================================
/// الدردشة العامة
/// =======================================================

class PublicChatPage extends StatefulWidget {
  final AppData data;

  const PublicChatPage({
    super.key,
    required this.data,
  });

  @override
  State<PublicChatPage> createState() => _PublicChatPageState();
}

class _PublicChatPageState extends State<PublicChatPage> {
  final controller = TextEditingController();
  Timer? timer;

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        await widget.data.loadPublicChat();
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;

    await playClickSound();

    final ok = await widget.data.sendPublicChat(controller.text);

    if (!mounted) return;

    if (ok) {
      controller.clear();
    } else {
      showSnack(context, 'تعذر إرسال الرسالة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدردشة العامة'),
        actions: [
          IconButton(
            onPressed: () async {
              await playClickSound();
              await widget.data.loadPublicChat();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.data.publicChat.isEmpty
                ? const Center(child: Text('لا توجد رسائل بعد.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.data.publicChat.length,
                    itemBuilder: (_, index) {
                      final item = widget.data.publicChat[index];

                      final mine = clean(item['account_id']) ==
                          clean(widget.data.currentAccountId);

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  clean(item['user_name']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(clean(item['message'])),
                                if (widget.data.isAdmin)
                                  IconButton(
                                    onPressed: () async {
                                      await playClickSound();
                                      await widget.data
                                          .deletePublicChat(item['id']);
                                      if (mounted) setState(() {});
                                    },
                                    icon: const Icon(Icons.delete),
                                  ),
                              ],
                            ),
                          ),
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
                    decoration: const InputDecoration(
                      labelText: 'اكتب رسالتك',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send),
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
/// لعبة القفز
/// =======================================================

class JumpGamePage extends StatefulWidget {
  final AppData data;

  const JumpGamePage({
    super.key,
    required this.data,
  });

  @override
  State<JumpGamePage> createState() => _JumpGamePageState();
}

class _JumpGamePageState extends State<JumpGamePage> {
  Timer? timer;

  double playerY = 0;
  double velocity = 0;
  double rockX = 1.1;

  bool playing = false;
  bool gameOver = false;

  int score = 0;
  int best = 0;

  DateTime lastScore = DateTime.now();

  @override
  void initState() {
    super.initState();
    loadBest();
  }

  Future<void> loadBest() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      best = prefs.getInt('mr_otaku_jump_best') ?? 0;
    });
  }

  Future<void> saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mr_otaku_jump_best', best);
  }

  void startGame() {
    timer?.cancel();

    setState(() {
      playing = true;
      gameOver = false;
      playerY = 0;
      velocity = 0;
      rockX = 1.1;
      score = 0;
      lastScore = DateTime.now();
    });

    timer = Timer.periodic(
      const Duration(milliseconds: 30),
      (_) => updateGame(),
    );
  }

  void updateGame() {
    if (!mounted || !playing) return;

    const gravity = -0.014;

    playerY += velocity;
    velocity += gravity;

    if (playerY < 0) {
      playerY = 0;
      velocity = 0;
    }

    final difficulty = 0.018 + min(score * 0.0007, 0.018);
    rockX -= difficulty;

    if (rockX < -1.2) {
      rockX = 1.1;
    }

    final playerHitX = rockX < -0.55 && rockX > -0.82;
    final playerOnGround = playerY < 0.10;

    if (playerHitX && playerOnGround) {
      endGame();
      return;
    }

    if (DateTime.now().difference(lastScore).inMilliseconds > 900) {
      lastScore = DateTime.now();

      setState(() {
        score++;
      });
    }

    setState(() {});
  }

  void jump() {
    if (!playing) {
      startGame();
      return;
    }

    if (playerY <= 0.01) {
      velocity = 0.25;
    }
  }

  Future<void> endGame() async {
    timer?.cancel();

    setState(() {
      playing = false;
      gameOver = true;
    });

    if (score > best) {
      best = score;
      await saveBest();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة القفز')),
      body: GestureDetector(
        onTap: jump,
        child: Container(
          width: double.infinity,
          color: const Color(0xFF160707),
          child: Column(
            children: [
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'النقاط: $score',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'الأفضل: $best',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: CustomPaint(
                  painter: JumpPainter(
                    playerY: playerY,
                    rockX: rockX,
                  ),
                  child: Container(),
                ),
              ),
              if (!playing)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        gameOver
                            ? 'انتهت اللعبة! نتيجتك: $score'
                            : 'اضغط للبدء',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      FilledButton.icon(
                        onPressed: startGame,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          gameOver
                              ? 'إعادة اللعب'
                              : 'ابدأ اللعبة',
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('اضغط على الشاشة للقفز فوق الصخور'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class JumpPainter extends CustomPainter {
  final double playerY;
  final double rockX;

  JumpPainter({
    required this.playerY,
    required this.rockX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.78;
    final playerX = size.width * 0.25;

    const playerHeight = 55.0;

    final py = groundY - playerY * size.height * 0.75 - playerHeight;

    final player = Paint()..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(playerX, py, 40, playerHeight),
        const Radius.circular(10),
      ),
      player,
    );

    final rockPaint = Paint()..style = PaintingStyle.fill;
    final rockXPosition = size.width * ((rockX + 1) / 2);

    final rockRect = Rect.fromLTWH(
      rockXPosition,
      groundY - 40,
      42,
      40,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rockRect,
        const Radius.circular(8),
      ),
      rockPaint,
    );

    final groundPaint = Paint()..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, 5),
      groundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant JumpPainter oldDelegate) {
    return oldDelegate.playerY != playerY ||
        oldDelegate.rockX != rockX;
  }
}

/// =======================================================
/// المتصدرون
/// =======================================================

class LeaderboardPage extends StatelessWidget {
  final AppData data;

  const LeaderboardPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final list = [...data.players];

    list.sort(
      (a, b) => toInt(b['points']).compareTo(toInt(a['points'])),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: list.isEmpty
          ? const Center(child: Text('لا يوجد لاعبون.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final player = list[index];
                final points = toInt(player['points']);
                final badge = getCurrentBadge(points);

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(clean(player['name'])),
                    subtitle: Text(
                      'المستوى ${getUserLevel(points)}'
                      '${badge == null ? '' : ' • ${badge.icon} ${badge.name}'}',
                    ),
                    trailing: Text(
                      '$points نقطة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// =======================================================
/// المتجر
/// =======================================================

class ShopPage extends StatefulWidget {
  final AppData data;

  const ShopPage({
    super.key,
    required this.data,
  });

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  Map<String, dynamic>? selectedPlayer;

  @override
  void initState() {
    super.initState();
    selectedPlayer = widget.data.currentPlayer;
  }

  Future<void> buy(String item, int cost) async {
    if (selectedPlayer == null) {
      showSnack(context, 'لم يتم العثور على حساب.');
      return;
    }

    final points = toInt(selectedPlayer!['points']);

    if (points < cost) {
      showSnack(context, 'نقاطك غير كافية.');
      return;
    }

    final ok = await widget.data.createPurchaseRequest(
      selectedPlayer!['id'],
      item,
      cost,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إرسال طلب الشراء للإدارة.' : 'تعذر إرسال الطلب.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متجر النقاط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (selectedPlayer != null)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(clean(selectedPlayer!['name'])),
                subtitle: Text(
                  '${toInt(selectedPlayer!['points'])} نقطة',
                ),
              ),
            ),
          const SizedBox(height: 15),
          _ShopItem(
            title: 'تغيير اسم المجموعة',
            cost: 5,
            icon: Icons.edit,
            onBuy: () => buy('تغيير اسم المجموعة', 5),
          ),
          _ShopItem(
            title: 'أيقونة خاصة',
            cost: 10,
            icon: Icons.image,
            onBuy: () => buy('أيقونة خاصة', 10),
          ),
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String title;
  final int cost;
  final IconData icon;
  final VoidCallback onBuy;

  const _ShopItem({
    required this.title,
    required this.cost,
    required this.icon,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('$cost نقاط'),
        trailing: FilledButton(
          onPressed: onBuy,
          child: const Text('شراء'),
        ),
      ),
    );
  }
}

/// =======================================================
/// إرسال رسالة للإدارة
/// =======================================================

class SendMessagePage extends StatefulWidget {
  final AppData data;

  const SendMessagePage({
    super.key,
    required this.data,
  });

  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final ok = await widget.data.sendMessage(
      widget.data.currentUserName,
      controller.text,
    );

    if (!mounted) return;

    if (ok) {
      controller.clear();
      showSnack(context, 'تم إرسال رسالتك للإدارة.');
    } else {
      showSnack(context, 'تعذر إرسال الرسالة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال رسالة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'سيتم إرسال الرسالة باسم ${widget.data.currentUserName}',
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'رسالتك',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: send,
                icon: const Icon(Icons.send),
                label: const Text('إرسال'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// الإعدادات
/// =======================================================

class SettingsPage extends StatelessWidget {
  final AppData data;

  const SettingsPage({
    super.key,
    required this.data,
  });

  Future<void> logout(BuildContext context) async {
    await playClickSound();
    await data.logoutAccount();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSetupPage(data: data),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = data.currentBadge;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    child: Icon(Icons.person, size: 35),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    data.currentUserName,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('معرف الحساب: ${data.currentAccountId}'),
                  Text('المستوى: ${data.currentLevel}'),
                  Text('النقاط: ${data.currentPoints}'),
                  if (badge != null)
                    Text('${badge.icon} ${badge.name}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ServiceTile(
            icon: Icons.notifications,
            title: 'الإشعارات',
            subtitle: 'عرض إشعارات الإدارة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsPage(data: data),
                ),
              );
            },
          ),
          if (data.isAdmin)
            ServiceTile(
              icon: Icons.admin_panel_settings,
              title: 'لوحة الإدارة',
              subtitle: 'إدارة التطبيق',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminPanelPage(data: data),
                  ),
                );
              },
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('تسجيل الخروج'),
              onTap: () => logout(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// تسجيل دخول المدير
/// =======================================================

class AdminLoginPage extends StatefulWidget {
  final AppData data;

  const AdminLoginPage({
    super.key,
    required this.data,
  });

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) return;

    setState(() {
      loading = true;
    });

    try {
      final result = await supabase.auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );

      final user = result.user;

      if (user == null) throw Exception();

      final admin = await supabase
          .from('admins')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (admin == null) {
        await supabase.auth.signOut();
        throw Exception('not_admin');
      }

      await widget.data.setAdminSession(true);
      await widget.data.loadData();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => AdminPanelPage(data: widget.data),
        ),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'بيانات الدخول غير صحيحة أو الحساب ليس مديراً.',
        );
      }
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول الإدارة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : login,
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text('دخول'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// لوحة الإدارة
/// =======================================================

class AdminPanelPage extends StatelessWidget {
  final AppData data;

  const AdminPanelPage({
    super.key,
    required this.data,
  });

  Future<void> logout(BuildContext context) async {
    await supabase.auth.signOut();
    await data.setAdminSession(false);

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSetupPage(data: data),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!data.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('الإدارة')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminLoginPage(data: data),
                ),
              );
            },
            child: const Text('دخول الإدارة'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
        actions: [
          IconButton(
            onPressed: () => logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminTile(
            icon: Icons.quiz,
            title: 'إدارة الأسئلة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageQuizPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.person,
            title: 'إدارة الشخصيات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageCharactersPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.movie,
            title: 'إدارة الأنميات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageAnimePage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.newspaper,
            title: 'إدارة الأخبار',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageNewsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.notifications,
            title: 'إدارة الإشعارات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageNotificationsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.poll,
            title: 'إدارة الاستطلاعات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManagePollPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.people,
            title: 'إدارة اللاعبين والحسابات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManagePointsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.campaign,
            title: 'إدارة كل جديد',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageLatestPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.message,
            title: 'الرسائل',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageMessagesPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.chat,
            title: 'الدردشة العامة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicChatPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.shopping_bag,
            title: 'طلبات المتجر',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManagePurchaseRequestsPage(data: data),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: const Icon(Icons.arrow_back_ios),
      ),
    );
  }
}

/// =======================================================
/// إدارة الأسئلة
/// =======================================================

class ManageQuizPage extends StatefulWidget {
  final AppData data;

  const ManageQuizPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageQuizPage> createState() => _ManageQuizPageState();
}

class _ManageQuizPageState extends State<ManageQuizPage> {
  @override
  Widget build(BuildContext context) {
    final list = widget.data.quizQuestions;

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأسئلة')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuizEditorPage(data: widget.data),
            ),
          );

          if (!mounted) return;
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
      body: list.isEmpty
          ? const Center(child: Text('لا توجد أسئلة.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final q = list[index];

                return Card(
                  child: ListTile(
                    title: Text(clean(q['question'])),
                    subtitle: Text(
                      quizTypeName(
                        clean(q['quiz_type']).isEmpty
                            ? 'direct'
                            : clean(q['quiz_type']),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QuizEditorPage(
                                  data: widget.data,
                                  question: q,
                                ),
                              ),
                            );

                            if (!mounted) return;
                            setState(() {});
                          },
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          onPressed: () async {
                            await widget.data
                                .deleteQuizQuestion(q['id']);
                            if (!mounted) return;
                            setState(() {});
                          },
                          icon: const Icon(Icons.delete),
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
/// محرر الأسئلة
/// =======================================================

class QuizEditorPage extends StatefulWidget {
  final AppData data;
  final Map<String, dynamic>? question;

  const QuizEditorPage({
    super.key,
    required this.data,
    this.question,
  });

  @override
  State<QuizEditorPage> createState() => _QuizEditorPageState();
}

class _QuizEditorPageState extends State<QuizEditorPage> {
  late final TextEditingController question;
  late final TextEditingController option1;
  late final TextEditingController option2;
  late final TextEditingController option3;
  late final TextEditingController option4;

  late int correct;
  String type = 'direct';
  File? imageFile;
  String? imageUrl;
  bool saving = false;

  bool get editing => widget.question != null;

  @override
  void initState() {
    super.initState();

    final q = widget.question;

    question = TextEditingController(text: clean(q?['question']));
    option1 = TextEditingController(text: clean(q?['option1']));
    option2 = TextEditingController(text: clean(q?['option2']));
    option3 = TextEditingController(text: clean(q?['option3']));
    option4 = TextEditingController(text: clean(q?['option4']));

    correct = toInt(q?['correct_option']);

    if (correct < 1 || correct > 4) {
      correct = 1;
    }

    type = clean(q?['quiz_type']).isEmpty
        ? 'direct'
        : clean(q?['quiz_type']);

    imageUrl = clean(q?['image_url']);

    if (imageUrl?.isEmpty ?? true) {
      imageUrl = null;
    }
  }

  @override
  void dispose() {
    question.dispose();
    option1.dispose();
    option2.dispose();
    option3.dispose();
    option4.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();

    final picked = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      imageFile = File(picked.path);
    });
  }

  Future<void> save() async {
    if (question.text.trim().isEmpty ||
        option1.text.trim().isEmpty ||
        option2.text.trim().isEmpty ||
        option3.text.trim().isEmpty ||
        option4.text.trim().isEmpty) {
      showSnack(context, 'أكمل جميع الحقول.');
      return;
    }

    setState(() {
      saving = true;
    });

    String? finalImage = imageUrl;

    if (type == 'image_character') {
      if (imageFile != null) {
        finalImage =
            await widget.data.uploadQuizImage(imageFile!);
      }

      if (finalImage == null || finalImage.isEmpty) {
        if (!mounted) return;

        showSnack(
          context,
          'أضف صورة لهذا النوع من الأسئلة.',
        );

        setState(() {
          saving = false;
        });

        return;
      }
    } else {
      finalImage = null;
    }

    bool ok;

    if (editing) {
      ok = await widget.data.updateQuizQuestion(
        id: widget.question!['id'],
        question: question.text,
        option1: option1.text,
        option2: option2.text,
        option3: option3.text,
        option4: option4.text,
        correctOption: correct,
        quizType: type,
        imageUrl: finalImage,
      );
    } else {
      ok = await widget.data.addQuizQuestion(
        question: question.text,
        option1: option1.text,
        option2: option2.text,
        option3: option3.text,
        option4: option4.text,
        correctOption: correct,
        quizType: type,
        imageUrl: finalImage,
      );
    }

    if (!mounted) return;

    setState(() {
      saving = false;
    });

    if (ok) {
      Navigator.pop(context);
    } else {
      showSnack(context, 'تعذر حفظ السؤال.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'تعديل السؤال' : 'إضافة سؤال'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(
              labelText: 'نوع السؤال',
            ),
            items: const [
              DropdownMenuItem(
                value: 'direct',
                child: Text('أسئلة مباشرة'),
              ),
              DropdownMenuItem(
                value: 'guess_character',
                child: Text('احزر الشخصية'),
              ),
              DropdownMenuItem(
                value: 'image_character',
                child: Text('خمن الشخصية من الصورة'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                type = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: question,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'السؤال',
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: [
                  option1,
                  option2,
                  option3,
                  option4,
                ][i],
                decoration: InputDecoration(
                  labelText: 'الخيار ${i + 1}',
                ),
              ),
            ),
          DropdownButtonFormField<int>(
            value: correct,
            decoration: const InputDecoration(
              labelText: 'الإجابة الصحيحة',
            ),
            items: List.generate(
              4,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('الخيار ${index + 1}'),
              ),
            ),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  correct = value;
                });
              }
            },
          ),
          if (type == 'image_character') ...[
            const SizedBox(height: 15),
            if (imageFile != null)
              Image.file(
                imageFile!,
                height: 180,
                fit: BoxFit.contain,
              )
            else if (imageUrl != null)
              Image.network(
                imageUrl!,
                height: 180,
                fit: BoxFit.contain,
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: pickImage,
              icon: const Icon(Icons.image),
              label: const Text('اختيار صورة الشخصية'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: saving
                ? const CircularProgressIndicator()
                : const Text('حفظ السؤال'),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// إدارة الشخصيات
/// =======================================================

class ManageCharactersPage extends StatefulWidget {
  final AppData data;

  const ManageCharactersPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageCharactersPage> createState() =>
      _ManageCharactersPageState();
}

class _ManageCharactersPageState extends State<ManageCharactersPage> {
  Future<void> edit([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: clean(item?['name']));
    final description =
        TextEditingController(text: clean(item?['description']));

    File? file;
    String image = clean(item?['image_url']);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(item == null ? 'إضافة شخصية' : 'تعديل شخصية'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشخصية',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (file != null)
                    Image.file(file!, height: 120)
                  else if (image.isNotEmpty)
                    Image.network(image, height: 120),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );

                      if (picked != null) {
                        setState(() {
                          file = File(picked.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('اختيار صورة'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  bool ok;

                  if (item == null) {
                    ok = await widget.data.addCharacter(
                      name.text,
                      description.text,
                      imageFile: file,
                    );
                  } else {
                    ok = await widget.data.updateCharacter(
                      item['id'],
                      name.text,
                      description.text,
                      imageUrl: image,
                      imageFile: file,
                    );
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(
                      context,
                      ok ? 'تم الحفظ.' : 'تعذر الحفظ.',
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    description.dispose();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الشخصيات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.data.ratingCharacters.length,
        itemBuilder: (_, index) {
          final item = widget.data.ratingCharacters[index];

          return Card(
            child: ListTile(
              title: Text(clean(item['name'])),
              subtitle: Text(clean(item['description'])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => edit(item),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    onPressed: () async {
                      await widget.data
                          .deleteCharacter(item['id']);
                      if (!mounted) return;
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete),
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
/// إدارة الأنميات
/// =======================================================

class ManageAnimePage extends StatefulWidget {
  final AppData data;

  const ManageAnimePage({
    super.key,
    required this.data,
  });

  @override
  State<ManageAnimePage> createState() => _ManageAnimePageState();
}

class _ManageAnimePageState extends State<ManageAnimePage> {
  Future<void> edit([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: clean(item?['title']));
    final description =
        TextEditingController(text: clean(item?['description']));

    File? file;
    String image = clean(item?['image_url']);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(item == null ? 'إضافة أنمي' : 'تعديل أنمي'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'اسم الأنمي',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (file != null)
                    Image.file(file!, height: 120)
                  else if (image.isNotEmpty)
                    Image.network(image, height: 120),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );

                      if (picked != null) {
                        setState(() {
                          file = File(picked.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('اختيار صورة'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  bool ok;

                  if (item == null) {
                    ok = await widget.data.addAnime(
                      title.text,
                      description.text,
                      imageFile: file,
                    );
                  } else {
                    ok = await widget.data.updateAnime(
                      item['id'],
                      title.text,
                      description.text,
                      imageUrl: image,
                      imageFile: file,
                    );
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(
                      context,
                      ok ? 'تم الحفظ.' : 'تعذر الحفظ.',
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );

    title.dispose();
    description.dispose();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأنميات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.data.ratingAnime.length,
        itemBuilder: (_, index) {
          final item = widget.data.ratingAnime[index];

          return Card(
            child: ListTile(
              title: Text(clean(item['title'])),
              subtitle: Text(clean(item['description'])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => edit(item),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    onPressed: () async {
                      await widget.data.deleteAnime(item['id']);
                      if (!mounted) return;
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete),
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
/// إدارة الأخبار
/// =======================================================

class ManageNewsPage extends StatefulWidget {
  final AppData data;

  const ManageNewsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNewsPage> createState() => _ManageNewsPageState();
}

class _ManageNewsPageState extends State<ManageNewsPage> {
  final title = TextEditingController();
  final description = TextEditingController();
  File? image;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> add() async {
    title.clear();
    description.clear();
    image = null;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('إضافة خبر'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'العنوان',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (image != null)
                    Image.file(image!, height: 120),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );

                      if (picked != null) {
                        setState(() {
                          image = File(picked.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('إضافة صورة'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await widget.data.addNews(
                    title.text,
                    description.text,
                    imageFile: image,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(
                      context,
                      ok ? 'تمت إضافة الخبر.' : 'تعذر إضافة الخبر.',
                    );
                  }
                },
                child: const Text('نشر'),
              ),
            ],
          );
        },
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأخبار')),
      floatingActionButton: FloatingActionButton(
        onPressed: add,
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.data.news.length,
        itemBuilder: (_, index) {
          final item = widget.data.news[index];

          return Card(
            child: ListTile(
              title: Text(clean(item['title'])),
              subtitle: Text(
                clean(item['description']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () async {
                  await widget.data.deleteNews(item['id']);
                  if (!mounted) return;
                  setState(() {});
                },
                icon: const Icon(Icons.delete),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// =======================================================
/// إدارة الإشعارات
/// =======================================================

class ManageNotificationsPage extends StatefulWidget {
  final AppData data;

  const ManageNotificationsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNotificationsPage> createState() =>
      _ManageNotificationsPageState();
}

class _ManageNotificationsPageState
    extends State<ManageNotificationsPage> {
  final title = TextEditingController();
  final body = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> add() async {
    if (title.text.trim().isEmpty) return;

    final ok = await widget.data.addNotification(
      title.text,
      body.text,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إرسال الإشعار.' : 'تعذر إرسال الإشعار.',
    );

    if (ok) {
      title.clear();
      body.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الإشعارات')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'العنوان',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'نص الإشعار',
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: add,
                child: const Text('إرسال إشعار'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// إدارة الاستطلاع
/// =======================================================

class ManagePollPage extends StatefulWidget {
  final AppData data;

  const ManagePollPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePollPage> createState() => _ManagePollPageState();
}

class _ManagePollPageState extends State<ManagePollPage> {
  final question = TextEditingController();
  final options = List.generate(
    4,
    (_) => TextEditingController(),
  );

  @override
  void dispose() {
    question.dispose();
    for (final controller in options) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> create() async {
    final values = options
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (question.text.trim().isEmpty || values.length < 2) {
      showSnack(context, 'أدخل السؤال وخيارين على الأقل.');
      return;
    }

    final ok = await widget.data.createPoll(
      question.text,
      values,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إنشاء الاستطلاع.' : 'تعذر إنشاء الاستطلاع.',
    );

    if (ok) {
      question.clear();
      for (final item in options) {
        item.clear();
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الاستطلاعات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: question,
            decoration: const InputDecoration(
              labelText: 'السؤال',
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: options[i],
                decoration: InputDecoration(
                  labelText: 'الخيار ${i + 1}',
                ),
              ),
            ),
          FilledButton(
            onPressed: create,
            child: const Text('إنشاء استطلاع'),
          ),
          const SizedBox(height: 20),
          if (widget.data.activePoll != null)
            Card(
              child: ListTile(
                title: const Text('الاستطلاع الحالي'),
                subtitle: Text(
                  clean(widget.data.activePoll!['question']),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// =======================================================
/// إدارة اللاعبين
/// =======================================================

class ManagePointsPage extends StatefulWidget {
  final AppData data;

  const ManagePointsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePointsPage> createState() => _ManagePointsPageState();
}

class _ManagePointsPageState extends State<ManagePointsPage> {
  Future<void> edit([Map<String, dynamic>? player]) async {
    final name = TextEditingController(text: clean(player?['name']));
    final points = TextEditingController(
      text: toInt(player?['points']).toString(),
    );
    final accountId = TextEditingController(
      text: player?['account_id']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(player == null ? 'إضافة حساب' : 'تعديل الحساب'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: accountId,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'معرف الحساب الفريد',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: points,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'النقاط',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final parsedId = accountId.text.trim().isEmpty
                  ? null
                  : int.tryParse(accountId.text.trim());

              final parsedPoints =
                  int.tryParse(points.text.trim()) ?? 0;

              bool ok;

              if (player == null) {
                ok = await widget.data.addPlayer(
                  name.text,
                  parsedPoints,
                  accountId: parsedId,
                );
              } else {
                ok = await widget.data.updatePlayer(
                  player['id'],
                  name.text,
                  parsedPoints,
                  accountId: parsedId,
                );
              }

              if (context.mounted) {
                Navigator.pop(context);
                showSnack(
                  context,
                  ok
                      ? 'تم حفظ الحساب.'
                      : 'فشل الحفظ. قد يكون معرف الحساب مستخدماً بالفعل.',
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    name.dispose();
    points.dispose();
    accountId.dispose();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الحسابات والنقاط')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(),
        child: const Icon(Icons.person_add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.data.players.length,
        itemBuilder: (_, index) {
          final player = widget.data.players[index];

          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(clean(player['name'])),
              subtitle: Text(
                'ID: ${player['account_id'] ?? 'غير مرتبط'}\nالمستوى: ${getUserLevel(toInt(player['points']))}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${toInt(player['points'])}'),
                  IconButton(
                    onPressed: () => edit(player),
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    onPressed: () async {
                      await widget.data.deletePlayer(player['id']);
                      if (!mounted) return;
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete),
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
/// إدارة كل جديد
/// =======================================================

class ManageLatestPage extends StatefulWidget {
  final AppData data;

  const ManageLatestPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageLatestPage> createState() => _ManageLatestPageState();
}

class _ManageLatestPageState extends State<ManageLatestPage> {
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final ok = await widget.data.addLatest(
      title.text,
      description.text,
    );

    if (!mounted) return;

    showSnack(context, ok ? 'تمت الإضافة.' : 'تعذر الإضافة.');

    if (ok) {
      title.clear();
      description.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة كل جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(
              labelText: 'العنوان',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'الوصف',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: add,
            child: const Text('إضافة'),
          ),
          const SizedBox(height: 15),
          ...widget.data.latest.map(
            (item) => Card(
              child: ListTile(
                title: Text(clean(item['title'])),
                subtitle: Text(clean(item['description'])),
                trailing: IconButton(
                  onPressed: () async {
                    await widget.data.deleteLatest(item['id']);
                    if (!mounted) return;
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =======================================================
/// إدارة الرسائل
/// =======================================================

class ManageMessagesPage extends StatefulWidget {
  final AppData data;

  const ManageMessagesPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageMessagesPage> createState() =>
      _ManageMessagesPageState();
}

class _ManageMessagesPageState extends State<ManageMessagesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رسائل المستخدمين')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.data.messages.length,
        itemBuilder: (_, index) {
          final item = widget.data.messages[index];

          return Card(
            child: ListTile(
              title: Text(clean(item['name'])),
              subtitle: Text(clean(item['message'])),
              trailing: IconButton(
                onPressed: () async {
                  await widget.data.deleteMessage(item['id']);
                  if (!mounted) return;
                  setState(() {});
                },
                icon: const Icon(Icons.delete),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// =======================================================
/// إدارة طلبات المتجر
/// =======================================================

class ManagePurchaseRequestsPage extends StatefulWidget {
  final AppData data;

  const ManagePurchaseRequestsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePurchaseRequestsPage> createState() =>
      _ManagePurchaseRequestsPageState();
}

class _ManagePurchaseRequestsPageState
    extends State<ManagePurchaseRequestsPage> {
  Future<void> refresh() async {
    await widget.data.loadData();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات المتجر'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: widget.data.purchaseRequests.isEmpty
          ? const Center(child: Text('لا توجد طلبات.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.data.purchaseRequests.length,
              itemBuilder: (_, index) {
                final item =
                    widget.data.purchaseRequests[index];
                final status = clean(item['status']);

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اللاعب: ${item['player_id']}'),
                        Text(
                          'العنصر: ${clean(item['item_type'])}',
                        ),
                        Text(
                          'التكلفة: ${toInt(item['cost'])}',
                        ),
                        Text('الحالة: $status'),
                        if (status == 'pending')
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    await widget.data
                                        .approvePurchase(item);
                                    await refresh();
                                  },
                                  child: const Text('موافقة'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await widget.data
                                        .rejectPurchase(item['id']);
                                    await refresh();
                                  },
                                  child: const Text('رفض'),
                                ),
                              ),
                            ],
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
/// SnackBar
/// =======================================================

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ),
  );
}