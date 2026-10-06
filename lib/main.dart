import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sekchgllbimoedsjoumi.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNla2NoZ2xsYmltb2Vkc2pvdW1pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTExNzQ3NzcsImV4cCI6MjEwNjc1MDc3N30.2KyojN-jT9-7QV0SME6tKQOc030mCx1diz7aP31MA3E',
  );

  runApp(const MrOtakuApp());
}

final supabase = Supabase.instance.client;

/// صوت النقر العام
Future<void> playClickSound() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

/// ===============================
/// الشارات
/// ===============================

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
  BadgeInfo(
    points: 30,
    icon: '🥉',
    name: 'أوتاكو ممتاز',
  ),
  BadgeInfo(
    points: 60,
    icon: '⚔️',
    name: 'محارب الأنمي',
  ),
  BadgeInfo(
    points: 100,
    icon: '🥈',
    name: 'أوتاكو متقدم',
  ),
  BadgeInfo(
    points: 150,
    icon: '🔥',
    name: 'عاشق الأنمي',
  ),
  BadgeInfo(
    points: 250,
    icon: '💎',
    name: 'أوتاكو نادر',
  ),
  BadgeInfo(
    points: 400,
    icon: '👑',
    name: 'سيد الأوتاكو',
  ),
  BadgeInfo(
    points: 600,
    icon: '🌟',
    name: 'أسطورة الأنمي',
  ),
  BadgeInfo(
    points: 1000,
    icon: '🏆',
    name: 'إمبراطور الأنمي',
  ),
];

List<BadgeInfo> getEarnedBadges(int points) {
  return otakuBadges.where((badge) {
    return points >= badge.points;
  }).toList();
}

BadgeInfo? getCurrentBadge(int points) {
  BadgeInfo? current;

  for (final badge in otakuBadges) {
    if (points >= badge.points) {
      current = badge;
    }
  }

  return current;
}

/// ===============================
/// فحص المدير
/// ===============================

Future<bool> checkAdminSession() async {
  final user = supabase.auth.currentUser;

  if (user == null) return false;

  try {
    final admin = await supabase
        .from('admins')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    return admin != null;
  } catch (e) {
    debugPrint('Admin session check error: $e');
    return false;
  }
}

/// ===============================
/// AppData
/// ===============================

class AppData extends ChangeNotifier {
  List<Map<String, dynamic>> news = [];
  List<Map<String, dynamic>> players = [];
  List<Map<String, dynamic>> latest = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> purchaseRequests = [];

  List<Map<String, dynamic>> notifications = [];

  Map<dynamic, int> likeCounts = {};
  Set<String> likedNews = {};

  Map<dynamic, int> commentCounts = {};

  Map<String, dynamic>? activePoll;
  List<Map<String, dynamic>> activePollOptions = [];
  Map<dynamic, int> pollVoteCounts = {};
  String? votedPollId;

  bool loading = true;
  bool _isAdmin = false;

  bool get isAdmin => _isAdmin;

  int get unreadNotificationCount {
    return notifications.where((notification) {
      final id = notification['id'].toString();
      return !_readNotifications.contains(id);
    }).length;
  }

  final Set<String> _readNotifications = {};

  void setAdminSession(bool value) {
    _isAdmin = value;
  }

  /// ===============================
  /// المتصدر
  /// ===============================

  Map<String, dynamic>? get leader {
    if (players.isEmpty) return null;

    final sorted = [...players];

    sorted.sort((a, b) {
      final aPoints =
          int.tryParse(a['points'].toString()) ?? 0;

      final bPoints =
          int.tryParse(b['points'].toString()) ?? 0;

      return bPoints.compareTo(aPoints);
    });

    return sorted.first;
  }

  /// ===============================
  /// تحميل كل البيانات
  /// ===============================

  Future<void> loadData() async {
    loading = true;
    notifyListeners();

    try {
      final newsData = await supabase
          .from('news')
          .select()
          .order('created_at', ascending: false);

      final playersData = await supabase
          .from('players')
          .select()
          .order('points', ascending: false);

      final latestData = await supabase
          .from('latest')
          .select()
          .order('created_at', ascending: false);

      news = List<Map<String, dynamic>>.from(newsData);

      players = List<Map<String, dynamic>>.from(playersData);

      players.sort((a, b) {
        final aPoints =
            int.tryParse(a['points'].toString()) ?? 0;

        final bPoints =
            int.tryParse(b['points'].toString()) ?? 0;

        return bPoints.compareTo(aPoints);
      });

      latest = List<Map<String, dynamic>>.from(latestData);

      await loadLikes();
      await loadCommentCounts();
      await loadNotifications();
      await loadPoll();

      if (_isAdmin) {
        final messagesData = await supabase
            .from('messages')
            .select()
            .order('created_at', ascending: false);

        messages =
            List<Map<String, dynamic>>.from(messagesData);

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
      debugPrint('Load error: $e');
    }

    loading = false;
    notifyListeners();
  }

  /// ===============================
  /// Client ID
  /// ===============================

  Future<String> getClientId() async {
    final prefs =
        await SharedPreferences.getInstance();

    String? id =
        prefs.getString('mr_otaku_client_id');

    if (id == null || id.isEmpty) {
      id = DateTime.now()
          .microsecondsSinceEpoch
          .toString();

      await prefs.setString(
        'mr_otaku_client_id',
        id,
      );
    }

    return id;
  }

  /// ===============================
  /// الإعجابات
  /// ===============================

  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId();

      final data = await supabase
          .from('news_likes')
          .select('news_id, client_id');

      likeCounts = {};
      likedNews = {};

      for (final item in data) {
        final newsId = item['news_id'];

        likeCounts[newsId] =
            (likeCounts[newsId] ?? 0) + 1;

        if (item['client_id'].toString() == clientId) {
          likedNews.add(newsId.toString());
        }
      }
    } catch (e) {
      debugPrint('Likes load error: $e');
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

        likeCounts[newsId] =
            ((likeCounts[newsId] ?? 1) - 1)
                .clamp(0, 999999)
                .toInt();
      } else {
        await supabase.from('news_likes').insert({
          'news_id': newsId,
          'client_id': clientId,
        });

        likedNews.add(key);

        likeCounts[newsId] =
            (likeCounts[newsId] ?? 0) + 1;
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Like error: $e');
      return false;
    }
  }

  /// ===============================
  /// التعليقات
  /// ===============================

  Future<void> loadCommentCounts() async {
    try {
      final data = await supabase
          .from('news_comments')
          .select('news_id');

      commentCounts = {};

      for (final item in data) {
        final newsId = item['news_id'];

        commentCounts[newsId] =
            (commentCounts[newsId] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('Comment count error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getComments(
    dynamic newsId,
  ) async {
    try {
      final data = await supabase
          .from('news_comments')
          .select()
          .eq('news_id', newsId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Get comments error: $e');
      return [];
    }
  }

  Future<bool> addComment(
    dynamic newsId,
    String userName,
    String commentText,
  ) async {
    try {
      final clientId = await getClientId();

      await supabase.from('news_comments').insert({
        'news_id': newsId,
        'client_id': clientId,
        'user_name':
            userName.trim().isEmpty
                ? 'مستخدم'
                : userName.trim(),
        'comment_text': commentText.trim(),
      });

      commentCounts[newsId] =
          (commentCounts[newsId] ?? 0) + 1;

      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('Add comment error: $e');
      return false;
    }
  }

  /// ===============================
  /// الإشعارات
  /// ===============================

  Future<void> loadNotifications() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      final saved =
          prefs.getStringList(
        'mr_otaku_read_notifications',
      );

      _readNotifications.clear();

      if (saved != null) {
        _readNotifications.addAll(saved);
      }

      final data = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      notifications =
          List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Notifications error: $e');
    }
  }

  Future<void> markNotificationRead(
    dynamic notificationId,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    _readNotifications.add(
      notificationId.toString(),
    );

    await prefs.setStringList(
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final prefs =
        await SharedPreferences.getInstance();

    for (final notification in notifications) {
      _readNotifications.add(
        notification['id'].toString(),
      );
    }

    await prefs.setStringList(
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

    notifyListeners();
  }

  Future<bool> addNotification(
    String title,
    String body,
  ) async {
    try {
      if (!_isAdmin) return false;

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

  /// ===============================
  /// استطلاعات الرأي
  /// ===============================

  Future<void> loadPoll() async {
    try {
      final pollsData = await supabase
          .from('polls')
          .select()
          .eq('active', true)
          .order('created_at', ascending: false);

      if (pollsData.isEmpty) {
        activePoll = null;
        activePollOptions = [];
        pollVoteCounts = {};
        votedPollId = null;
        return;
      }

      activePoll =
          Map<String, dynamic>.from(
        pollsData.first,
      );

      final pollId = activePoll!['id'];

      final optionsData = await supabase
          .from('poll_options')
          .select()
          .eq('poll_id', pollId)
          .order('position', ascending: true);

      activePollOptions =
          List<Map<String, dynamic>>.from(
        optionsData,
      );

      final votesData = await supabase
          .from('poll_votes')
          .select('option_id, client_id')
          .eq('poll_id', pollId);

      pollVoteCounts = {};

      final clientId = await getClientId();

      votedPollId = null;

      for (final vote in votesData) {
        final optionId = vote['option_id'];

        pollVoteCounts[optionId] =
            (pollVoteCounts[optionId] ?? 0) + 1;

        if (vote['client_id'].toString() ==
            clientId) {
          votedPollId = pollId.toString();
        }
      }
    } catch (e) {
      debugPrint('Poll load error: $e');
    }
  }

  bool get hasVotedInActivePoll {
    if (activePoll == null) return false;

    return votedPollId ==
        activePoll!['id'].toString();
  }

  int get totalPollVotes {
    return pollVoteCounts.values.fold(
      0,
      (sum, value) => sum + value,
    );
  }

  double getPollPercentage(dynamic optionId) {
    final total = totalPollVotes;

    if (total == 0) return 0;

    return ((pollVoteCounts[optionId] ?? 0) /
            total) *
        100;
  }

  Future<bool> votePoll(dynamic optionId) async {
    try {
      if (activePoll == null) return false;

      if (hasVotedInActivePoll) {
        return false;
      }

      final clientId = await getClientId();

      await supabase.from('poll_votes').insert({
        'poll_id': activePoll!['id'],
        'option_id': optionId,
        'client_id': clientId,
      });

      votedPollId =
          activePoll!['id'].toString();

      pollVoteCounts[optionId] =
          (pollVoteCounts[optionId] ?? 0) + 1;

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
    try {
      if (!_isAdmin) return false;

      if (question.trim().isEmpty ||
          options.length < 2) {
        return false;
      }

      await supabase
          .from('polls')
          .update({'active': false})
          .eq('active', true);

      final pollResponse =
          await supabase
              .from('polls')
              .insert({
                'question': question.trim(),
                'active': true,
              })
              .select()
              .single();

      final pollId = pollResponse['id'];

      for (int i = 0;
          i < options.length;
          i++) {
        if (options[i].trim().isEmpty) {
          continue;
        }

        await supabase
            .from('poll_options')
            .insert({
          'poll_id': pollId,
          'option_text':
              options[i].trim(),
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

  /// ===============================
  /// الرسائل
  /// ===============================

  Future<bool> sendMessage(
    String name,
    String message,
  ) async {
    try {
      await supabase.from('messages').insert({
        'name': name,
        'message': message,
      });

      return true;
    } catch (e) {
      debugPrint('Send message error: $e');
      return false;
    }
  }

  /// ===============================
  /// الأخبار
  /// ===============================

  Future<bool> addNews(
    String title,
    String description, {
    File? imageFile,
  }) async {
    try {
      if (!_isAdmin) return false;

      String? imageUrl;

      if (imageFile != null) {
        final extension =
            imageFile.path
                .split('.')
                .last
                .toLowerCase();

        final path =
            'news_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await supabase.storage
            .from('news-images')
            .upload(
              path,
              imageFile,
              fileOptions:
                  const FileOptions(
                upsert: false,
              ),
            );

        imageUrl = supabase.storage
            .from('news-images')
            .getPublicUrl(path);
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
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('news')
          .delete()
          .eq('id', id);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Delete news error: $e');
      return false;
    }
  }

  /// ===============================
  /// اللاعبين
  /// ===============================

  Future<bool> addPlayer(
    String name,
    int points,
  ) async {
    try {
      if (!_isAdmin) return false;

      await supabase.from('players').insert({
        'name': name,
        'points': points,
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
    int points,
  ) async {
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('players')
          .update({
            'name': name,
            'points': points,
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
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('players')
          .delete()
          .eq('id', id);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Delete player error: $e');
      return false;
    }
  }

  /// ===============================
  /// كل جديد
  /// ===============================

  Future<bool> addLatest(
    String title,
    String description,
  ) async {
    try {
      if (!_isAdmin) return false;

      await supabase.from('latest').insert({
        'title': title.trim(),
        'description': description.trim(),
      });

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Add latest error: $e');
      return false;
    }
  }

  Future<bool> deleteLatest(dynamic id) async {
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('latest')
          .delete()
          .eq('id', id);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Delete latest error: $e');
      return false;
    }
  }

  /// ===============================
  /// الرسائل
  /// ===============================

  Future<bool> deleteMessage(dynamic id) async {
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('messages')
          .delete()
          .eq('id', id);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Delete message error: $e');
      return false;
    }
  }

  /// ===============================
  /// المشتريات
  /// ===============================

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
      debugPrint('Purchase request error: $e');
      return false;
    }
  }

  Future<bool> approvePurchase(
    Map<String, dynamic> request,
  ) async {
    try {
      if (!_isAdmin) return false;

      if (request['status'] != 'pending') {
        return false;
      }

      final playerId =
          request['player_id'];

      final cost =
          int.tryParse(
                request['cost'].toString(),
              ) ??
              0;

      final player = await supabase
          .from('players')
          .select()
          .eq('id', playerId)
          .maybeSingle();

      if (player == null) return false;

      final currentPoints =
          int.tryParse(
                player['points'].toString(),
              ) ??
              0;

      if (currentPoints < cost) {
        return false;
      }

      await supabase
          .from('players')
          .update({
        'points': currentPoints - cost,
      }).eq('id', playerId);

      await supabase
          .from('purchase_requests')
          .update({
        'status': 'approved',
      }).eq('id', request['id']);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Approve purchase error: $e');
      return false;
    }
  }

  Future<bool> rejectPurchase(dynamic id) async {
    try {
      if (!_isAdmin) return false;

      await supabase
          .from('purchase_requests')
          .update({
        'status': 'rejected',
      }).eq('id', id);

      await loadData();

      return true;
    } catch (e) {
      debugPrint('Reject purchase error: $e');
      return false;
    }
  }
}

/// ===============================
/// التطبيق
/// ===============================

class MrOtakuApp extends StatefulWidget {
  const MrOtakuApp({super.key});

  @override
  State<MrOtakuApp> createState() =>
      _MrOtakuAppState();
}

class _MrOtakuAppState
    extends State<MrOtakuApp> {
  final AppData data = AppData();

  bool checkingSession = true;
  bool adminSession = false;

  @override
  void initState() {
    super.initState();
    checkSession();
  }

  Future<void> checkSession() async {
    adminSession =
        await checkAdminSession();

    data.setAdminSession(
      adminSession,
    );

    await data.loadData();

    if (!mounted) return;

    setState(() {
      checkingSession = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Mr Otaku',
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor:
                const Color(0xFF0D0808),
            colorScheme:
                ColorScheme.fromSeed(
              seedColor:
                  const Color(0xFF9B111E),
              brightness:
                  Brightness.dark,
            ),
            appBarTheme:
                const AppBarTheme(
              backgroundColor:
                  Color(0xFF160909),
              foregroundColor:
                  Colors.white,
            ),
            navigationBarTheme:
                const NavigationBarThemeData(
              backgroundColor:
                  Color(0xFF120707),
              indicatorColor:
                  Color(0xFF7F101B),
            ),
            cardTheme: CardTheme(
              color:
                  const Color(0xFF181010),
              elevation: 2,
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(16),
                side:
                    const BorderSide(
                  color:
                      Color(0xFF351414),
                ),
              ),
            ),
            inputDecorationTheme:
                InputDecorationTheme(
              filled: true,
              fillColor:
                  const Color(0xFF191010),
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(14),
                borderSide:
                    BorderSide.none,
              ),
              focusedBorder:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(14),
                borderSide:
                    const BorderSide(
                  color:
                      Color(0xFFB71C2A),
                ),
              ),
            ),
            filledButtonTheme:
                FilledButtonThemeData(
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    const Color(0xFF8F1521),
              ),
            ),
          ),
          home: checkingSession
              ? const Scaffold(
                  body: Center(
                    child:
                        CircularProgressIndicator(),
                  ),
                )
              : adminSession
                  ? AdminPanelPage(
                      data: data,
                    )
                  : HomePage(
                      data: data,
                    ),
        );
      },
    );
  }
}

/// ===============================
/// الصفحة الرئيسية
/// ===============================

class HomePage extends StatefulWidget {
  final AppData data;

  const HomePage({
    super.key,
    required this.data,
  });

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState
    extends State<HomePage> {
  int currentIndex = 0;

  final List<String> titles = const [
    'الرئيسية',
    'الأخبار',
    'الخدمات',
    'الإعدادات',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(data: widget.data),
      NewsPage(data: widget.data),
      ServicesPage(data: widget.data),
      SettingsPage(data: widget.data),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[currentIndex],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Stack(
            children: [
              IconButton(
                tooltip: 'الإشعارات',
                onPressed: () async {
                  await playClickSound();

                  if (!context.mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NotificationsPage(
                        data: widget.data,
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.notifications_outlined,
                ),
              ),
              if (widget.data
                      .unreadNotificationCount >
                  0)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Container(
                    constraints:
                        const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 4,
                    ),
                    decoration:
                        const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      widget.data
                                  .unreadNotificationCount >
                              99
                          ? '99+'
                          : widget.data
                              .unreadNotificationCount
                              .toString(),
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: pages[currentIndex],
      bottomNavigationBar:
          NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected:
            (index) async {
          await playClickSound();

          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.home_outlined,
            ),
            selectedIcon: Icon(
              Icons.home,
            ),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.newspaper_outlined,
            ),
            selectedIcon: Icon(
              Icons.newspaper,
            ),
            label: 'الأخبار',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.apps_outlined,
            ),
            selectedIcon: Icon(
              Icons.apps,
            ),
            label: 'الخدمات',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.settings_outlined,
            ),
            selectedIcon: Icon(
              Icons.settings,
            ),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Home Tab
/// ===============================

class HomeTab extends StatelessWidget {
  final AppData data;

  const HomeTab({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.loading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    final leader = data.leader;

    final leaderPoints = leader == null
        ? 0
        : int.tryParse(
              leader['points'].toString(),
            ) ??
            0;

    final leaderBadge =
        getCurrentBadge(
      leaderPoints,
    );

    return RefreshIndicator(
      onRefresh: data.loadData,
      child: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          /// مستطيل المطور
          Card(
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              decoration:
                  BoxDecoration(
                borderRadius:
                    BorderRadius.circular(16),
                gradient:
                    const LinearGradient(
                  colors: [
                    Color(0xFF3A090E),
                    Color(0xFF7F101B),
                  ],
                ),
              ),
              child: const Text(
                'من تطوير برهان البريهي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          /// الترحيب
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(22),
              child: Column(
                children: const [
                  Icon(
                    Icons.auto_awesome,
                    size: 55,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'مرحباً بك في Mr Otaku',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'كل ما يخص عالم الأنمي في مكان واحد',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          /// المتصدر
          if (leader != null)
            Card(
              elevation: 5,
              child: Container(
                padding:
                    const EdgeInsets.all(18),
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(16),
                  gradient:
                      const LinearGradient(
                    colors: [
                      Color(0xFF4D0A10),
                      Color(0xFF8F1521),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(
                          '🏆',
                          style:
                              TextStyle(
                            fontSize: 28,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'متصدر النقاط',
                          style:
                              TextStyle(
                            fontSize: 21,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 15,
                    ),
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor:
                          Colors.white12,
                      child: Icon(
                        Icons.person,
                        size: 34,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      (leader['name'] ?? '')
                          .toString(),
                      style:
                          const TextStyle(
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      '⭐ $leaderPoints نقطة',
                      style:
                          const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    if (leaderBadge !=
                        null) ...[
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        '${leaderBadge.icon} ${leaderBadge.name}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 18),

          /// استطلاع الرأي
          if (data.activePoll != null)
            PollCard(data: data),

          const SizedBox(height: 22),

          const Text(
            'كل جديد',
            style: TextStyle(
              fontSize: 21,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          if (data.latest.isEmpty)
            const EmptyState(
              text:
                  'لا توجد منشورات جديدة حالياً.',
            )
          else
            ...data.latest.take(5).map(
              (item) =>
                  LatestCard(item: item),
            ),
        ],
      ),
    );
  }
}

/// ===============================
/// Poll Card
/// ===============================

class PollCard extends StatefulWidget {
  final AppData data;

  const PollCard({
    super.key,
    required this.data,
  });

  @override
  State<PollCard> createState() =>
      _PollCardState();
}

class _PollCardState
    extends State<PollCard> {
  dynamic selectedOption;
  bool voting = false;

  Future<void> vote() async {
    if (selectedOption == null) {
      showSnack(
        context,
        'اختر إجابة أولاً.',
      );
      return;
    }

    await playClickSound();

    setState(() {
      voting = true;
    });

    final success =
        await widget.data.votePoll(
      selectedOption,
    );

    if (!mounted) return;

    setState(() {
      voting = false;
    });

    if (!success) {
      showSnack(
        context,
        'تعذر التصويت. ربما قمت بالتصويت مسبقاً.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.data.activePoll!;

    final voted =
        widget.data.hasVotedInActivePoll;

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.poll,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Text(
                  'استطلاع الرأي',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              (poll['question'] ?? '')
                  .toString(),
              style:
                  const TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            ...widget.data.activePollOptions
                .map(
              (option) {
                final optionId =
                    option['id'];

                final votes = widget
                        .data
                        .pollVoteCounts[
                            optionId] ??
                    0;

                final percentage =
                    widget.data
                        .getPollPercentage(
                  optionId,
                );

                if (voted) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(
                      bottom: 10,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (option[
                                            'option_text'] ??
                                        '')
                                    .toString(),
                              ),
                            ),
                            Text(
                              '$votes صوت',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        ClipRRect(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            20,
                          ),
                          child:
                              LinearProgressIndicator(
                            minHeight: 9,
                            value:
                                percentage /
                                    100,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Align(
                          alignment:
                              Alignment
                                  .centerRight,
                          child: Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RadioListTile<
                    dynamic>(
                  value: optionId,
                  groupValue:
                      selectedOption,
                  onChanged: (value) {
                    setState(() {
                      selectedOption =
                          value;
                    });
                  },
                  title: Text(
                    (option['option_text'] ??
                            '')
                        .toString(),
                  ),
                  contentPadding:
                      EdgeInsets.zero,
                );
              },
            ),

            if (!voted) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      voting ? null : vote,
                  icon: const Icon(
                    Icons.how_to_vote,
                  ),
                  label: Text(
                    voting
                        ? 'جارٍ التصويت...'
                        : 'تصويت',
                  ),
                ),
              ),
            ] else
              const Text(
                '✓ تم تسجيل تصويتك',
                style: TextStyle(
                  color:
                      Colors.greenAccent,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// الأخبار
/// ===============================

class NewsPage extends StatefulWidget {
  final AppData data;

  const NewsPage({
    super.key,
    required this.data,
  });

  @override
  State<NewsPage> createState() =>
      _NewsPageState();
}

class _NewsPageState
    extends State<NewsPage> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.data.news.where((item) {
      final title =
          (item['title'] ?? '')
              .toString()
              .toLowerCase();

      final description =
          (item['description'] ?? '')
              .toString()
              .toLowerCase();

      return title.contains(
            search.toLowerCase(),
          ) ||
          description.contains(
            search.toLowerCase(),
          );
    }).toList();

    return RefreshIndicator(
      onRefresh:
          widget.data.loadData,
      child: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (value) {
              setState(() {
                search = value;
              });
            },
            decoration:
                const InputDecoration(
              hintText:
                  'ابحث في الأخبار...',
              prefixIcon:
                  Icon(Icons.search),
            ),
          ),

          const SizedBox(height: 16),

          if (filtered.isEmpty)
            const EmptyState(
              text:
                  'لا توجد أخبار مطابقة.',
            )
          else
            ...filtered.map(
              (item) => NewsCard(
                item: item,
                data: widget.data,
              ),
            ),
        ],
      ),
    );
  }
}

/// ===============================
/// News Card
/// ===============================

class NewsCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final AppData data;

  const NewsCard({
    super.key,
    required this.item,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final id = item['id'];

    final liked =
        data.likedNews.contains(
      id.toString(),
    );

    final likes =
        data.likeCounts[id] ?? 0;

    final comments =
        data.commentCounts[id] ?? 0;

    final imageUrl =
        (item['image_url'] ?? '')
            .toString();

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      clipBehavior:
          Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 210,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) {
                  return Container(
                    color:
                        const Color(
                      0xFF230B0E,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons
                            .broken_image,
                        size: 50,
                      ),
                    ),
                  );
                },
                loadingBuilder:
                    (
                  context,
                  child,
                  progress,
                ) {
                  if (progress == null) {
                    return child;
                  }

                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                },
              ),
            ),

          Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  (item['title'] ?? '')
                      .toString(),
                  style:
                      const TextStyle(
                    fontSize: 19,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  (item['description'] ??
                          '')
                      .toString(),
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        await playClickSound();
                        await data
                            .toggleLike(id);
                      },
                      icon: Icon(
                        liked
                            ? Icons.favorite
                            : Icons
                                .favorite_border,
                        color: liked
                            ? Colors.redAccent
                            : Colors
                                .white70,
                      ),
                    ),

                    Text(
                      '$likes',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(width: 6),

                    IconButton(
                      tooltip:
                          'التعليقات',
                      onPressed: () async {
                        await playClickSound();

                        if (!context.mounted) {
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                NewsCommentsPage(
                              data: data,
                              newsId: id,
                              newsTitle:
                                  (item['title'] ??
                                          '')
                                      .toString(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons
                            .chat_bubble_outline,
                      ),
                    ),

                    Text(
                      '$comments',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const Spacer(),

                    Text(
                      formatDate(
                        item['created_at'],
                      ),
                      style:
                          const TextStyle(
                        color:
                            Colors.white38,
                        fontSize: 12,
                      ),
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

/// ===============================
/// التعليقات
/// ===============================

class NewsCommentsPage
    extends StatefulWidget {
  final AppData data;
  final dynamic newsId;
  final String newsTitle;

  const NewsCommentsPage({
    super.key,
    required this.data,
    required this.newsId,
    required this.newsTitle,
  });

  @override
  State<NewsCommentsPage> createState() =>
      _NewsCommentsPageState();
}

class _NewsCommentsPageState
    extends State<NewsCommentsPage> {
  final nameController =
      TextEditingController();

  final commentController =
      TextEditingController();

  List<Map<String, dynamic>>
      comments = [];

  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    loadComments();
  }

  Future<void> loadComments() async {
    setState(() {
      loading = true;
    });

    final result =
        await widget.data.getComments(
      widget.newsId,
    );

    if (!mounted) return;

    setState(() {
      comments = result;
      loading = false;
    });
  }

  Future<void> sendComment() async {
    final comment =
        commentController.text.trim();

    if (comment.isEmpty) {
      showSnack(
        context,
        'اكتب تعليقاً أولاً.',
      );
      return;
    }

    await playClickSound();

    setState(() {
      sending = true;
    });

    final success =
        await widget.data.addComment(
      widget.newsId,
      nameController.text.trim(),
      comment,
    );

    if (!mounted) return;

    setState(() {
      sending = false;
    });

    if (success) {
      commentController.clear();

      await loadComments();

      if (!mounted) return;

      showSnack(
        context,
        'تم نشر تعليقك.',
      );
    } else {
      showSnack(
        context,
        'فشل نشر التعليق.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'التعليقات',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : comments.isEmpty
                    ? const EmptyState(
                        text:
                            'لا توجد تعليقات بعد.\nكن أول من يعلق!',
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        itemCount:
                            comments.length,
                        itemBuilder:
                            (context, index) {
                          final comment =
                              comments[index];

                          return Card(
                            margin:
                                const EdgeInsets
                                    .only(
                              bottom: 10,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets
                                      .all(14),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        child: Icon(
                                          Icons.person,
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 10,
                                      ),
                                      Expanded(
                                        child: Text(
                                          (comment[
                                                      'user_name'] ??
                                                  'مستخدم')
                                              .toString(),
                                          style:
                                              const TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        formatDate(
                                          comment[
                                              'created_at'],
                                        ),
                                        style:
                                            const TextStyle(
                                          color:
                                              Colors.white38,
                                          fontSize:
                                              11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 10,
                                  ),
                                  Text(
                                    (comment[
                                                'comment_text'] ??
                                            '')
                                        .toString(),
                                    style:
                                        const TextStyle(
                                      color:
                                          Colors.white70,
                                      height:
                                          1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          SafeArea(
            child: Container(
              padding:
                  const EdgeInsets.all(10),
              decoration:
                  const BoxDecoration(
                color:
                    Color(0xFF160909),
                border:
                    Border(
                  top: BorderSide(
                    color:
                        Color(0xFF351414),
                  ),
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller:
                        nameController,
                    decoration:
                        const InputDecoration(
                      hintText:
                          'اسمك (اختياري)',
                      prefixIcon:
                          Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller:
                              commentController,
                          maxLines: 2,
                          decoration:
                              const InputDecoration(
                            hintText:
                                'اكتب تعليقك...',
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      IconButton.filled(
                        onPressed:
                            sending
                                ? null
                                : sendComment,
                        icon: const Icon(
                          Icons.send,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// الإشعارات
/// ===============================

class NotificationsPage
    extends StatelessWidget {
  final AppData data;

  const NotificationsPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('الإشعارات'),
        actions: [
          if (data.notifications
              .isNotEmpty)
            TextButton(
              onPressed: () async {
                await playClickSound();

                await data
                    .markAllNotificationsRead();

                if (!context.mounted) return;

                showSnack(
                  context,
                  'تم تعليم جميع الإشعارات كمقروءة.',
                );
              },
              child:
                  const Text('قراءة الكل'),
            ),
        ],
      ),
      body: data.notifications.isEmpty
          ? const EmptyState(
              text:
                  'لا توجد إشعارات حالياً.',
            )
          : ListView.builder(
              padding:
                  const EdgeInsets.all(16),
              itemCount:
                  data.notifications.length,
              itemBuilder:
                  (context, index) {
                final item =
                    data.notifications[
                        index];

                final id = item['id']
                    .toString();

                final read = !data
                    .unreadNotificationCount
                    .toString()
                    .isEmpty &&
                    false;

                return Card(
                  margin:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.all(
                      12,
                    ),
                    leading:
                        const CircleAvatar(
                      child: Icon(
                        Icons.notifications,
                      ),
                    ),
                    title: Text(
                      (item['title'] ?? '')
                          .toString(),
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    subtitle:
                        Padding(
                      padding:
                          const EdgeInsets
                              .only(
                        top: 6,
                      ),
                      child: Text(
                        (item['body'] ?? '')
                            .toString(),
                      ),
                    ),
                    trailing:
                        const Icon(
                      Icons
                          .arrow_forward_ios,
                      size: 14,
                    ),
                    onTap: () async {
                      await playClickSound();

                      await data
                          .markNotificationRead(
                        id,
                      );

                      if (!context.mounted) {
                        return;
                      }

                      showDialog(
                        context: context,
                        builder: (_) =>
                            AlertDialog(
                          title: Text(
                            (item['title'] ??
                                    '')
                                .toString(),
                          ),
                          content: Text(
                            (item['body'] ??
                                    '')
                                .toString(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(
                                context,
                              ),
                              child:
                                  const Text(
                                'إغلاق',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// ===============================
/// آخر الأخبار
/// ===============================

class LatestCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const LatestCard({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: ListTile(
        leading:
            const CircleAvatar(
          child: Icon(
            Icons.campaign,
          ),
        ),
        title: Text(
          (item['title'] ?? '')
              .toString(),
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Padding(
          padding:
              const EdgeInsets.only(
            top: 6,
          ),
          child: Text(
            (item['description'] ??
                    '')
                .toString(),
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// الخدمات
/// ===============================

class ServicesPage
    extends StatelessWidget {
  final AppData data;

  const ServicesPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.all(16),
      children: [
        ServiceTile(
          icon:
              Icons.notifications,
          title: 'الإشعارات',
          subtitle:
              'شاهد آخر إشعارات التطبيق',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NotificationsPage(
                  data: data,
                ),
              ),
            );
          },
        ),
        ServiceTile(
          icon:
              Icons.shopping_bag,
          title: 'متجر النقاط',
          subtitle:
              'استبدل نقاط المسابقة بالمزايا',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PurchaseShopPage(
                  data: data,
                ),
              ),
            );
          },
        ),
        ServiceTile(
          icon: Icons.message,
          title: 'إرسال رسالة',
          subtitle:
              'أرسل رسالة مباشرة إلى الإدارة',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SendMessagePage(
                  data: data,
                ),
              ),
            );
          },
        ),
        ServiceTile(
          icon:
              Icons.emoji_events,
          title: 'نقاط المسابقة',
          subtitle:
              'ابحث عن نقاطك في المسابقة',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PointsPage(
                  data: data,
                ),
              ),
            );
          },
        ),
        ServiceTile(
          icon: Icons.campaign,
          title: 'كل جديد',
          subtitle:
              'آخر المنشورات والأنشطة',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    LatestPage(
                  data: data,
                ),
              ),
            );
          },
        ),
        ServiceTile(
          icon: Icons.newspaper,
          title: 'الأخبار',
          subtitle:
              'آخر أخبار الأنمي',
          onTap: () async {
            await playClickSound();

            if (!context.mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NewsPage(
                  data: data,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// ===============================
/// Service Tile
/// ===============================

class ServiceTile
    extends StatelessWidget {
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
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 8,
        ),
        leading:
            CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          title,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Text(subtitle),
        trailing:
            const Icon(
          Icons.arrow_forward_ios,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// ===============================
/// متجر النقاط
/// ===============================

class PurchaseShopPage
    extends StatefulWidget {
  final AppData data;

  const PurchaseShopPage({
    super.key,
    required this.data,
  });

  @override
  State<PurchaseShopPage> createState() =>
      _PurchaseShopPageState();
}

class _PurchaseShopPageState
    extends State<PurchaseShopPage> {
  String search = '';

  Future<void> requestPurchase(
    Map<String, dynamic> player,
    String type,
    int cost,
  ) async {
    await playClickSound();

    final points =
        int.tryParse(
              player['points'].toString(),
            ) ??
            0;

    if (points < cost) {
      showSnack(
        context,
        'لا تملك نقاطاً كافية.',
      );
      return;
    }

    final success =
        await widget.data
            .createPurchaseRequest(
      player['id'],
      type,
      cost,
    );

    if (!mounted) return;

    showSnack(
      context,
      success
          ? 'تم إرسال طلب الشراء وسيتم مراجعته من الإدارة.'
          : 'فشل إرسال طلب الشراء.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final results =
        widget.data.players.where(
      (player) {
        final name =
            (player['name'] ?? '')
                .toString()
                .toLowerCase();

        return name.contains(
          search.toLowerCase(),
        );
      },
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('متجر النقاط'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          const Text(
            'اختر اسمك أولاً',
            style: TextStyle(
              fontSize: 21,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) {
              setState(() {
                search = value;
              });
            },
            decoration:
                const InputDecoration(
              hintText:
                  'ابحث باسمك...',
              prefixIcon:
                  Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 18),
          if (results.isEmpty)
            const EmptyState(
              text:
                  'لم يتم العثور على اسم.',
            )
          else
            ...results.map(
              (player) =>
                  PlayerShopCard(
                player: player,
                onNamePurchase:
                    () {
                  requestPurchase(
                    player,
                    'group_name',
                    5,
                  );
                },
                onIconPurchase:
                    () {
                  requestPurchase(
                    player,
                    'group_icon',
                    10,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class PlayerShopCard
    extends StatelessWidget {
  final Map<String, dynamic> player;
  final VoidCallback onNamePurchase;
  final VoidCallback onIconPurchase;

  const PlayerShopCard({
    super.key,
    required this.player,
    required this.onNamePurchase,
    required this.onIconPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  child: Icon(
                    Icons.person,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Text(
                    (player['name'] ?? '')
                        .toString(),
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Text(
                  '${player['points'] ?? 0} نقطة',
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  onNamePurchase,
              icon: const Icon(
                Icons.text_fields,
              ),
              label: const Text(
                'شراء اسم المجموعة - 5 نقاط',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  onIconPurchase,
              icon: const Icon(
                Icons.image,
              ),
              label: const Text(
                'شراء أيقونة المجموعة - 10 نقاط',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// إرسال رسالة
/// ===============================

class SendMessagePage
    extends StatefulWidget {
  final AppData data;

  const SendMessagePage({
    super.key,
    required this.data,
  });

  @override
  State<SendMessagePage> createState() =>
      _SendMessagePageState();
}

class _SendMessagePageState
    extends State<SendMessagePage> {
  final nameController =
      TextEditingController();

  final messageController =
      TextEditingController();

  bool sending = false;

  Future<void> send() async {
    await playClickSound();

    if (nameController.text
            .trim()
            .isEmpty ||
        messageController.text
            .trim()
            .isEmpty) {
      showSnack(
        context,
        'أكمل جميع الحقول.',
      );
      return;
    }

    setState(() {
      sending = true;
    });

    final success =
        await widget.data.sendMessage(
      nameController.text.trim(),
      messageController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      sending = false;
    });

    if (success) {
      nameController.clear();
      messageController.clear();

      showSnack(
        context,
        'تم إرسال الرسالة بنجاح.',
      );
    } else {
      showSnack(
        context,
        'حدث خطأ أثناء إرسال الرسالة.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إرسال رسالة'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            controller:
                nameController,
            decoration:
                const InputDecoration(
              labelText: 'الاسم',
              prefixIcon:
                  Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller:
                messageController,
            maxLines: 6,
            decoration:
                const InputDecoration(
              labelText: 'الرسالة',
              alignLabelWithHint:
                  true,
              prefixIcon:
                  Icon(Icons.message),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed:
                sending ? null : send,
            icon:
                const Icon(Icons.send),
            label: Text(
              sending
                  ? 'جارٍ الإرسال...'
                  : 'إرسال',
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// النقاط
/// ===============================

class PointsPage
    extends StatefulWidget {
  final AppData data;

  const PointsPage({
    super.key,
    required this.data,
  });

  @override
  State<PointsPage> createState() =>
      _PointsPageState();
}

class _PointsPageState
    extends State<PointsPage> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final results =
        widget.data.players.where(
      (player) {
        final name =
            (player['name'] ?? '')
                .toString()
                .toLowerCase();

        return name.contains(
          search.toLowerCase(),
        );
      },
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('نقاط المسابقة'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            onChanged: (value) {
              setState(() {
                search = value;
              });
            },
            decoration:
                const InputDecoration(
              hintText:
                  'ابحث باسمك...',
              prefixIcon:
                  Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            const EmptyState(
              text:
                  'لم يتم العثور على اسم.',
            )
          else
            ...results.map(
              (player) {
                final points =
                    int.tryParse(
                          player['points']
                              .toString(),
                        ) ??
                        0;

                final badges =
                    getEarnedBadges(
                  points,
                );

                return Card(
                  margin:
                      const EdgeInsets.only(
                    bottom: 12,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      14,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              const CircleAvatar(
                            child: Icon(
                              Icons.person,
                            ),
                          ),
                          title: Text(
                            (player[
                                        'name'] ??
                                    '')
                                .toString(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          trailing:
                              Text(
                            '$points نقطة',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (badges
                            .isNotEmpty) ...[
                          const Divider(),
                          const Align(
                            alignment:
                                Alignment
                                    .centerRight,
                            child: Text(
                              'الشارات المكتسبة',
                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children:
                                badges.map(
                              (badge) {
                                return Chip(
                                  avatar:
                                      Text(
                                    badge
                                        .icon,
                                  ),
                                  label:
                                      Text(
                                    badge
                                        .name,
                                  ),
                                );
                              },
                            ).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// ===============================
/// كل جديد
/// ===============================

class LatestPage
    extends StatelessWidget {
  final AppData data;

  const LatestPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('كل جديد'),
      ),
      body: RefreshIndicator(
        onRefresh:
            data.loadData,
        child: ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            if (data.latest.isEmpty)
              const EmptyState(
                text:
                    'لا توجد منشورات جديدة حالياً.',
              )
            else
              ...data.latest.map(
                (item) =>
                    LatestCard(
                  item: item,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// الإعدادات
/// ===============================

class SettingsPage
    extends StatelessWidget {
  final AppData data;

  const SettingsPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding:
          const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading:
                const CircleAvatar(
              child: Icon(
                Icons
                    .admin_panel_settings,
              ),
            ),
            title: const Text(
              'مركز التحكم',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            subtitle: const Text(
              'إدارة الأخبار والنقاط والمنشورات والرسائل',
            ),
            trailing:
                const Icon(
              Icons.arrow_forward_ios,
            ),
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AdminLoginPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ===============================
/// تسجيل دخول المدير
/// ===============================

class AdminLoginPage
    extends StatefulWidget {
  final AppData data;

  const AdminLoginPage({
    super.key,
    required this.data,
  });

  @override
  State<AdminLoginPage> createState() =>
      _AdminLoginPageState();
}

class _AdminLoginPageState
    extends State<AdminLoginPage> {
  final emailController =
      TextEditingController();

  final passwordController =
      TextEditingController();

  bool loading = false;
  bool obscure = true;

  Future<void> login() async {
    await playClickSound();

    if (emailController.text
            .trim()
            .isEmpty ||
        passwordController.text
            .isEmpty) {
      showSnack(
        context,
        'أدخل البريد الإلكتروني وكلمة المرور.',
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final response =
          await supabase.auth
              .signInWithPassword(
        email:
            emailController.text.trim(),
        password:
            passwordController.text,
      );

      final user =
          response.user;

      if (user == null) {
        throw Exception(
          'فشل تسجيل الدخول.',
        );
      }

      final admin =
          await supabase
              .from('admins')
              .select('user_id')
              .eq(
                'user_id',
                user.id,
              )
              .maybeSingle();

      if (admin == null) {
        await supabase.auth
            .signOut();

        throw Exception(
          'ليس حساب مدير',
        );
      }

      widget.data
          .setAdminSession(true);

      await widget.data
          .loadData();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AdminPanelPage(
            data: widget.data,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String message =
          'حدث خطأ أثناء تسجيل الدخول.';

      if (e is AuthException) {
        message = e.message;
      } else if (e
          .toString()
          .contains(
            'ليس حساب مدير',
          )) {
        message =
            'هذا الحساب ليس مسجلاً كمدير.';
      }

      showSnack(
        context,
        message,
      );
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
      appBar: AppBar(
        title:
            const Text('دخول الإدارة'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(20),
        children: [
          const SizedBox(
            height: 30,
          ),
          const Icon(
            Icons.admin_panel_settings,
            size: 80,
          ),
          const SizedBox(
            height: 20,
          ),
          const Text(
            'مركز التحكم',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 30,
          ),
          TextField(
            controller:
                emailController,
            keyboardType:
                TextInputType
                    .emailAddress,
            decoration:
                const InputDecoration(
              labelText:
                  'البريد الإلكتروني',
              prefixIcon:
                  Icon(Icons.email),
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          TextField(
            controller:
                passwordController,
            obscureText:
                obscure,
            decoration:
                InputDecoration(
              labelText:
                  'كلمة المرور',
              prefixIcon:
                  const Icon(
                Icons.lock,
              ),
              suffixIcon:
                  IconButton(
                onPressed:
                    () async {
                  await playClickSound();

                  setState(() {
                    obscure =
                        !obscure;
                  });
                },
                icon: Icon(
                  obscure
                      ? Icons.visibility
                      : Icons
                          .visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          FilledButton(
            onPressed:
                loading
                    ? null
                    : login,
            child: Text(
              loading
                  ? 'جارٍ الدخول...'
                  : 'تسجيل الدخول',
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// لوحة الإدارة
/// ===============================

class AdminPanelPage
    extends StatelessWidget {
  final AppData data;

  const AdminPanelPage({
    super.key,
    required this.data,
  });

  Future<void> logout(
    BuildContext context,
  ) async {
    await playClickSound();

    await supabase.auth
        .signOut();

    data.setAdminSession(false);

    await data.loadData();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HomePage(data: data),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('مركز التحكم'),
        actions: [
          IconButton(
            tooltip:
                'تسجيل الخروج',
            onPressed: () =>
                logout(context),
            icon:
                const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          AdminTile(
            icon:
                Icons.shopping_cart,
            title:
                'طلبات الشراء',
            subtitle:
                'مراجعة والموافقة على طلبات النقاط',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManagePurchaseRequestsPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.newspaper,
            title:
                'إدارة الأخبار',
            subtitle:
                'إضافة وحذف الأخبار مع الصور',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageNewsPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.poll,
            title:
                'إدارة الاستطلاعات',
            subtitle:
                'إنشاء استطلاع جديد للصفحة الرئيسية',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManagePollPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.notifications,
            title:
                'إدارة الإشعارات',
            subtitle:
                'إرسال إشعار جديد لجميع المستخدمين',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageNotificationsPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.emoji_events,
            title:
                'إدارة نقاط المسابقة',
            subtitle:
                'إضافة وتعديل وحذف النقاط',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManagePointsPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.campaign,
            title:
                'إدارة كل جديد',
            subtitle:
                'إضافة وحذف المنشورات',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageLatestPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
          AdminTile(
            icon:
                Icons.mail,
            title:
                'الرسائل',
            subtitle:
                'عرض وحذف رسائل المستخدمين',
            onTap: () async {
              await playClickSound();

              if (!context.mounted) {
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageMessagesPage(
                    data: data,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// Admin Tile
/// ===============================

class AdminTile
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.all(14),
        leading:
            CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          title,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Text(subtitle),
        trailing:
            const Icon(
          Icons.arrow_forward_ios,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// ===============================
/// إدارة الأخبار
/// ===============================

class ManageNewsPage
    extends StatefulWidget {
  final AppData data;

  const ManageNewsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNewsPage> createState() =>
      _ManageNewsPageState();
}

class _ManageNewsPageState
    extends State<ManageNewsPage> {
  final titleController =
      TextEditingController();

  final descriptionController =
      TextEditingController();

  XFile? selectedImage;

  bool adding = false;

  Future<void> pickImage() async {
    await playClickSound();

    final picker =
        ImagePicker();

    final image =
        await picker.pickImage(
      source:
          ImageSource.gallery,
      imageQuality: 85,
    );

    if (!mounted) return;

    if (image != null) {
      setState(() {
        selectedImage = image;
      });
    }
  }

  Future<void> addNews() async {
    await playClickSound();

    if (titleController.text
            .trim()
            .isEmpty ||
        descriptionController.text
            .trim()
            .isEmpty) {
      showSnack(
        context,
        'أكمل جميع الحقول.',
      );
      return;
    }

    setState(() {
      adding = true;
    });

    File? imageFile;

    if (selectedImage != null) {
      imageFile =
          File(selectedImage!.path);
    }

    final success =
        await widget.data.addNews(
      titleController.text.trim(),
      descriptionController.text
          .trim(),
      imageFile: imageFile,
    );

    if (!mounted) return;

    setState(() {
      adding = false;
    });

    if (success) {
      titleController.clear();
      descriptionController.clear();

      setState(() {
        selectedImage = null;
      });

      showSnack(
        context,
        'تمت إضافة الخبر بنجاح.',
      );
    } else {
      showSnack(
        context,
        'فشل إضافة الخبر.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إدارة الأخبار'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            controller:
                titleController,
            decoration:
                const InputDecoration(
              labelText:
                  'عنوان الخبر',
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller:
                descriptionController,
            maxLines: 4,
            decoration:
                const InputDecoration(
              labelText:
                  'وصف الخبر',
              alignLabelWithHint:
                  true,
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed:
                pickImage,
            icon: const Icon(
              Icons.photo_library,
            ),
            label: Text(
              selectedImage == null
                  ? 'اختيار صورة من المعرض'
                  : 'تغيير الصورة',
            ),
          ),

          if (selectedImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              child: Image.file(
                File(
                  selectedImage!.path,
                ),
                height: 190,
                width:
                    double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed:
                adding ? null : addNews,
            icon: const Icon(
              Icons.add,
            ),
            label: Text(
              adding
                  ? 'جارٍ إضافة الخبر...'
                  : 'إضافة خبر',
            ),
          ),

          const SizedBox(height: 20),

          ...widget.data.news.map(
            (item) => Card(
              child: ListTile(
                leading:
                    (item['image_url'] ??
                                '')
                            .toString()
                            .isNotEmpty
                        ? ClipRRect(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              8,
                            ),
                            child:
                                Image.network(
                              item[
                                      'image_url']
                                  .toString(),
                              width: 55,
                              height: 55,
                              fit: BoxFit
                                  .cover,
                            ),
                          )
                        : const Icon(
                            Icons
                                .newspaper,
                          ),
                title: Text(
                  (item['title'] ??
                          '')
                      .toString(),
                ),
                subtitle: Text(
                  (item[
                              'description'] ??
                          '')
                      .toString(),
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                ),
                trailing:
                    IconButton(
                  icon:
                      const Icon(
                    Icons.delete,
                  ),
                  onPressed: () async {
                    await playClickSound();

                    await widget.data
                        .deleteNews(
                      item['id'],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// إدارة الإشعارات
/// ===============================

class ManageNotificationsPage
    extends StatefulWidget {
  final AppData data;

  const ManageNotificationsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNotificationsPage>
      createState() =>
          _ManageNotificationsPageState();
}

class _ManageNotificationsPageState
    extends State<
        ManageNotificationsPage> {
  final titleController =
      TextEditingController();

  final bodyController =
      TextEditingController();

  bool sending = false;

  Future<void> sendNotification() async {
    await playClickSound();

    if (titleController.text
            .trim()
            .isEmpty ||
        bodyController.text
            .trim()
            .isEmpty) {
      showSnack(
        context,
        'أكمل جميع الحقول.',
      );
      return;
    }

    setState(() {
      sending = true;
    });

    final success =
        await widget.data
            .addNotification(
      titleController.text.trim(),
      bodyController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      sending = false;
    });

    if (success) {
      titleController.clear();
      bodyController.clear();

      showSnack(
        context,
        'تم إرسال الإشعار.',
      );
    } else {
      showSnack(
        context,
        'فشل إرسال الإشعار.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إدارة الإشعارات'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          const Text(
            'إرسال إشعار جديد',
            style: TextStyle(
              fontSize: 21,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            controller:
                titleController,
            decoration:
                const InputDecoration(
              labelText:
                  'عنوان الإشعار',
              prefixIcon:
                  Icon(Icons.title),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller:
                bodyController,
            maxLines: 5,
            decoration:
                const InputDecoration(
              labelText:
                  'نص الإشعار',
              alignLabelWithHint:
                  true,
            ),
          ),

          const SizedBox(height: 14),

          FilledButton.icon(
            onPressed: sending
                ? null
                : sendNotification,
            icon: const Icon(
              Icons.send,
            ),
            label: Text(
              sending
                  ? 'جارٍ الإرسال...'
                  : 'إرسال الإشعار',
            ),
          ),

          const SizedBox(height: 25),

          const Text(
            'الإشعارات السابقة',
            style: TextStyle(
              fontSize: 19,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          ...widget.data
              .notifications
              .map(
            (item) => Card(
              child: ListTile(
                leading:
                    const CircleAvatar(
                  child: Icon(
                    Icons.notifications,
                  ),
                ),
                title: Text(
                  (item['title'] ??
                          '')
                      .toString(),
                ),
                subtitle: Text(
                  (item['body'] ??
                          '')
                      .toString(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// إدارة الاستطلاعات
/// ===============================

class ManagePollPage
    extends StatefulWidget {
  final AppData data;

  const ManagePollPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePollPage> createState() =>
      _ManagePollPageState();
}

class _ManagePollPageState
    extends State<ManagePollPage> {
  final questionController =
      TextEditingController();

  final List<TextEditingController>
      optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool creating = false;

  void addOption() {
    if (optionControllers.length >=
        6) {
      showSnack(
        context,
        'الحد الأقصى 6 خيارات.',
      );
      return;
    }

    setState(() {
      optionControllers.add(
        TextEditingController(),
      );
    });
  }

  void removeOption(int index) {
    if (optionControllers.length <=
        2) {
      return;
    }

    optionControllers[index]
        .dispose();

    setState(() {
      optionControllers.removeAt(
        index,
      );
    });
  }

  Future<void> createPoll() async {
    await playClickSound();

    final question =
        questionController.text.trim();

    final options =
        optionControllers
            .map(
              (controller) =>
                  controller.text.trim(),
            )
            .where(
              (text) => text.isNotEmpty,
            )
            .toList();

    if (question.isEmpty ||
        options.length < 2) {
      showSnack(
        context,
        'أدخل السؤال وخيارين على الأقل.',
      );
      return;
    }

    setState(() {
      creating = true;
    });

    final success =
        await widget.data.createPoll(
      question,
      options,
    );

    if (!mounted) return;

    setState(() {
      creating = false;
    });

    if (success) {
      questionController.clear();

      for (final controller
          in optionControllers) {
        controller.clear();
      }

      showSnack(
        context,
        'تم إنشاء الاستطلاع وتفعيله.',
      );
    } else {
      showSnack(
        context,
        'فشل إنشاء الاستطلاع.',
      );
    }
  }

  @override
  void dispose() {
    questionController
        .dispose();

    for (final controller
        in optionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.data.activePoll;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إدارة الاستطلاعات'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          const Text(
            'إنشاء استطلاع جديد',
            style: TextStyle(
              fontSize: 21,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller:
                questionController,
            maxLines: 2,
            decoration:
                const InputDecoration(
              labelText:
                  'سؤال الاستطلاع',
              hintText:
                  'مثال: ما أفضل أنمي بالنسبة لك؟',
            ),
          ),

          const SizedBox(height: 14),

          ...List.generate(
            optionControllers.length,
            (index) {
              return Padding(
                padding:
                    const EdgeInsets.only(
                  bottom: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller:
                            optionControllers[
                                index],
                        decoration:
                            InputDecoration(
                          labelText:
                              'الخيار ${index + 1}',
                        ),
                      ),
                    ),
                    if (optionControllers
                            .length >
                        2)
                      IconButton(
                        onPressed: () =>
                            removeOption(
                          index,
                        ),
                        icon:
                            const Icon(
                          Icons
                              .remove_circle,
                          color:
                              Colors.redAccent,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          OutlinedButton.icon(
            onPressed: addOption,
            icon: const Icon(
              Icons.add,
            ),
            label: const Text(
              'إضافة خيار',
            ),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed:
                creating
                    ? null
                    : createPoll,
            icon: const Icon(
              Icons.poll,
            ),
            label: Text(
              creating
                  ? 'جارٍ الإنشاء...'
                  : 'إنشاء الاستطلاع',
            ),
          ),

          const SizedBox(height: 30),

          if (active != null)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'الاستطلاع الحالي',
                      style:
                          TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      (active[
                                  'question'] ??
                              '')
                          .toString(),
                      style:
                          const TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    ...widget.data
                        .activePollOptions
                        .map(
                      (option) =>
                          ListTile(
                        leading:
                            const Icon(
                          Icons
                              .radio_button_checked,
                        ),
                        title: Text(
                          (option[
                                      'option_text'] ??
                                  '')
                              .toString(),
                        ),
                        trailing:
                            Text(
                          '${widget.data.pollVoteCounts[option['id']] ?? 0}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ===============================
/// إدارة النقاط
/// ===============================

class ManagePointsPage
    extends StatefulWidget {
  final AppData data;

  const ManagePointsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePointsPage> createState() =>
      _ManagePointsPageState();
}

class _ManagePointsPageState
    extends State<ManagePointsPage> {
  final nameController =
      TextEditingController();

  final pointsController =
      TextEditingController();

  Future<void> addPlayer() async {
    await playClickSound();

    final name =
        nameController.text.trim();

    final points =
        int.tryParse(
      pointsController.text.trim(),
    );

    if (name.isEmpty ||
        points == null) {
      showSnack(
        context,
        'أدخل الاسم والنقاط بشكل صحيح.',
      );
      return;
    }

    final success =
        await widget.data.addPlayer(
      name,
      points,
    );

    if (!mounted) return;

    if (success) {
      nameController.clear();
      pointsController.clear();

      showSnack(
        context,
        'تمت إضافة اللاعب.',
      );
    } else {
      showSnack(
        context,
        'فشل إضافة اللاعب.',
      );
    }
  }

  Future<void> editPlayer(
    Map<String, dynamic> player,
  ) async {
    final nameController =
        TextEditingController(
      text:
          (player['name'] ?? '')
              .toString(),
    );

    final pointsController =
        TextEditingController(
      text:
          (player['points'] ?? 0)
              .toString(),
    );

    final result =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('تعديل النقاط'),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              TextField(
                controller:
                    nameController,
                decoration:
                    const InputDecoration(
                  labelText: 'الاسم',
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              TextField(
                controller:
                    pointsController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText: 'النقاط',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await playClickSound();

                final points =
                    int.tryParse(
                  pointsController
                      .text
                      .trim(),
                );

                if (nameController
                        .text
                        .trim()
                        .isEmpty ||
                    points == null) {
                  return;
                }

                final success =
                    await widget.data
                        .updatePlayer(
                  player['id'],
                  nameController.text
                      .trim(),
                  points,
                );

                if (context.mounted) {
                  Navigator.pop(
                    context,
                    success,
                  );
                }
              },
              child:
                  const Text('حفظ'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    pointsController.dispose();

    if (result == true &&
        mounted) {
      showSnack(
        context,
        'تم تعديل النقاط.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('نقاط المسابقة'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            controller:
                nameController,
            decoration:
                const InputDecoration(
              labelText:
                  'اسم اللاعب',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller:
                pointsController,
            keyboardType:
                TextInputType.number,
            decoration:
                const InputDecoration(
              labelText: 'النقاط',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: addPlayer,
            icon:
                const Icon(Icons.add),
            label:
                const Text('إضافة'),
          ),
          const SizedBox(height: 20),
          ...widget.data.players.map(
            (player) => Card(
              child: ListTile(
                title: Text(
                  (player['name'] ??
                          '')
                      .toString(),
                ),
                subtitle: Text(
                  '${player['points'] ?? 0} نقطة',
                ),
                trailing: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    IconButton(
                      icon:
                          const Icon(
                        Icons.edit,
                      ),
                      onPressed: () async {
                        await playClickSound();
                        await editPlayer(
                          player,
                        );
                      },
                    ),
                    IconButton(
                      icon:
                          const Icon(
                        Icons.delete,
                      ),
                      onPressed: () async {
                        await playClickSound();

                        await widget.data
                            .deletePlayer(
                          player['id'],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// إدارة كل جديد
/// ===============================

class ManageLatestPage
    extends StatefulWidget {
  final AppData data;

  const ManageLatestPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageLatestPage> createState() =>
      _ManageLatestPageState();
}

class _ManageLatestPageState
    extends State<ManageLatestPage> {
  final titleController =
      TextEditingController();

  final descriptionController =
      TextEditingController();

  Future<void> addLatest() async {
    await playClickSound();

    if (titleController.text
            .trim()
            .isEmpty ||
        descriptionController.text
            .trim()
            .isEmpty) {
      showSnack(
        context,
        'أكمل جميع الحقول.',
      );
      return;
    }

    final success =
        await widget.data.addLatest(
      titleController.text.trim(),
      descriptionController.text
          .trim(),
    );

    if (!mounted) return;

    if (success) {
      titleController.clear();
      descriptionController.clear();

      showSnack(
        context,
        'تمت إضافة المنشور.',
      );
    } else {
      showSnack(
        context,
        'فشل إضافة المنشور.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('إدارة كل جديد'),
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          TextField(
            controller:
                titleController,
            decoration:
                const InputDecoration(
              labelText: 'العنوان',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller:
                descriptionController,
            maxLines: 4,
            decoration:
                const InputDecoration(
              labelText: 'الوصف',
              alignLabelWithHint:
                  true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: addLatest,
            icon:
                const Icon(Icons.add),
            label:
                const Text('إضافة منشور'),
          ),
          const SizedBox(height: 20),
          ...widget.data.latest.map(
            (item) => Card(
              child: ListTile(
                title: Text(
                  (item['title'] ??
                          '')
                      .toString(),
                ),
                subtitle: Text(
                  (item['description'] ??
                          '')
                      .toString(),
                ),
                trailing:
                    IconButton(
                  icon:
                      const Icon(
                    Icons.delete,
                  ),
                  onPressed: () async {
                    await playClickSound();

                    await widget.data
                        .deleteLatest(
                      item['id'],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// إدارة الرسائل
/// ===============================

class ManageMessagesPage
    extends StatelessWidget {
  final AppData data;

  const ManageMessagesPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('رسائل المستخدمين'),
      ),
      body: RefreshIndicator(
        onRefresh:
            data.loadData,
        child: ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            if (data.messages.isEmpty)
              const EmptyState(
                text:
                    'لا توجد رسائل حالياً.',
              )
            else
              ...data.messages.map(
                (message) =>
                    Card(
                  margin:
                      const EdgeInsets.only(
                    bottom: 12,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      14,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                            ),
                            const SizedBox(
                              width: 8,
                            ),
                            Expanded(
                              child:
                                  Text(
                                (message[
                                            'name'] ??
                                        '')
                                    .toString(),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                  fontSize:
                                      17,
                                ),
                              ),
                            ),
                            IconButton(
                              icon:
                                  const Icon(
                                Icons.delete,
                              ),
                              onPressed:
                                  () async {
                                await playClickSound();

                                await data
                                    .deleteMessage(
                                  message[
                                      'id'],
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          (message[
                                      'message'] ??
                                  '')
                              .toString(),
                          style:
                              const TextStyle(
                            color:
                                Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          formatDate(
                            message[
                                'created_at'],
                          ),
                          style:
                              const TextStyle(
                            color:
                                Colors.white38,
                            fontSize:
                                12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// طلبات الشراء
/// ===============================

class ManagePurchaseRequestsPage
    extends StatelessWidget {
  final AppData data;

  const ManagePurchaseRequestsPage({
    super.key,
    required this.data,
  });

  String itemName(String type) {
    if (type ==
        'group_name') {
      return 'اسم المجموعة';
    }

    return 'أيقونة المجموعة';
  }

  String statusName(
    String status,
  ) {
    if (status == 'approved') {
      return 'تمت الموافقة';
    }

    if (status == 'rejected') {
      return 'مرفوض';
    }

    return 'قيد الانتظار';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('طلبات الشراء'),
      ),
      body: RefreshIndicator(
        onRefresh:
            data.loadData,
        child: ListView(
          padding:
              const EdgeInsets.all(16),
          children: [
            if (data.purchaseRequests
                .isEmpty)
              const EmptyState(
                text:
                    'لا توجد طلبات شراء حالياً.',
              )
            else
              ...data.purchaseRequests
                  .map(
                (request) {
                  Map<String,
                      dynamic>? player;

                  for (final p
                      in data.players) {
                    if (p['id']
                            .toString() ==
                        request[
                                'player_id']
                            .toString()) {
                      player = p;
                      break;
                    }
                  }

                  final playerName =
                      player?['name']
                              ?.toString() ??
                          'لاعب غير معروف';

                  final status =
                      request['status']
                              ?.toString() ??
                          'pending';

                  return Card(
                    margin:
                        const EdgeInsets
                            .only(
                      bottom: 12,
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .all(14),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            playerName,
                            style:
                                const TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'الطلب: ${itemName(request['item_type'].toString())}',
                          ),
                          Text(
                            'التكلفة: ${request['cost']} نقاط',
                          ),
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'الحالة: ${statusName(status)}',
                            style:
                                TextStyle(
                              color: status ==
                                      'approved'
                                  ? Colors
                                      .greenAccent
                                  : status ==
                                          'rejected'
                                      ? Colors
                                          .redAccent
                                      : Colors
                                          .orangeAccent,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          if (status ==
                              'pending') ...[
                            const SizedBox(
                              height: 12,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child:
                                      FilledButton(
                                    onPressed:
                                        () async {
                                      await playClickSound();

                                      final success =
                                          await data.approvePurchase(
                                        request,
                                      );

                                      if (!context.mounted) {
                                        return;
                                      }

                                      showSnack(
                                        context,
                                        success
                                            ? 'تمت الموافقة وخصم النقاط.'
                                            : 'تعذر الموافقة. تحقق من رصيد اللاعب.',
                                      );
                                    },
                                    child:
                                        const Text(
                                      'موافقة',
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child:
                                      OutlinedButton(
                                    onPressed:
                                        () async {
                                      await playClickSound();

                                      final success =
                                          await data.rejectPurchase(
                                        request[
                                            'id'],
                                      );

                                      if (!context.mounted) {
                                        return;
                                      }

                                      showSnack(
                                        context,
                                        success
                                            ? 'تم رفض الطلب.'
                                            : 'فشل رفض الطلب.',
                                      );
                                    },
                                    child:
                                        const Text(
                                      'رفض',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// Empty State
/// ===============================

class EmptyState
    extends StatelessWidget {
  final String text;

  const EmptyState({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.all(30),
      child: Center(
        child: Text(
          text,
          textAlign:
              TextAlign.center,
          style:
              const TextStyle(
            color:
                Colors.white54,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// التاريخ
/// ===============================

String formatDate(dynamic value) {
  if (value == null) return '';

  try {
    final date =
        DateTime.parse(
      value.toString(),
    ).toLocal();

    final day =
        date.day.toString().padLeft(
              2,
              '0',
            );

    final month =
        date.month.toString().padLeft(
              2,
              '0',
            );

    final year =
        date.year.toString();

    return '$day/$month/$year';
  } catch (_) {
    return '';
  }
}

/// ===============================
/// SnackBar
/// ===============================

void showSnack(
  BuildContext context,
  String message,
) {
  ScaffoldMessenger.of(context)
      .showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}