import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/reading_statistics.dart';
import '../core/models/article.dart';
import '../core/models/feed.dart';
import 'database_provider.dart';
import 'dart:math';

// Provider for reading statistics
final readingStatisticsProvider = FutureProvider<ReadingStatistics>((ref) async {
  final database = ref.watch(databaseProvider);
  
  // Get all read articles
  final allArticles = await database.articleDao.getAllArticles();
  final readArticles = allArticles.where((a) => a.isRead).toList();
  final feeds = await database.feedDao.getAllFeeds();
  
  // Calculate basic stats
  final totalArticlesRead = readArticles.length;
  
  // Calculate daily reading data (last 30 days)
  final now = DateTime.now();
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));
  final dailyReadingData = List.generate(30, (index) {
    final date = thirtyDaysAgo.add(Duration(days: index));
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    
    return readArticles.where((article) {
      final readAt = article.updatedAt ?? article.createdAt;
      return readAt.isAfter(dayStart) && readAt.isBefore(dayEnd);
    }).length;
  });
  
  // Calculate reading streak
  int currentStreak = 0;
  int longestStreak = 0;
  int tempStreak = 0;
  
  for (int i = dailyReadingData.length - 1; i >= 0; i--) {
    if (dailyReadingData[i] > 0) {
      tempStreak++;
      if (i == dailyReadingData.length - 1 || 
          (i < dailyReadingData.length - 1 && currentStreak > 0)) {
        currentStreak = tempStreak;
      }
      longestStreak = max(longestStreak, tempStreak);
    } else {
      if (currentStreak == 0 && tempStreak > 0) {
        currentStreak = tempStreak;
      }
      tempStreak = 0;
    }
  }
  
  // Calculate average articles per day
  final daysWithReading = dailyReadingData.where((count) => count > 0).length;
  final averageArticlesPerDay = daysWithReading > 0 
    ? totalArticlesRead / daysWithReading 
    : 0.0;
  
  // Calculate top sources
  final sourceStats = <String, SourceStatistics>{};
  for (final article in readArticles) {
    final feedId = article.feedId;
    if (feedId != null) {
      if (!sourceStats.containsKey(feedId)) {
        final feed = feeds.firstWhere(
          (f) => f.id == feedId,
          orElse: () => Feed(
            id: feedId,
            title: 'Unknown Feed',
            url: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        sourceStats[feedId] = SourceStatistics(
          feedId: feedId,
          feedTitle: feed.title,
          articlesRead: 0,
          readingTime: 0,
          percentage: 0,
        );
      }
      
      final stats = sourceStats[feedId]!;
      sourceStats[feedId] = SourceStatistics(
        feedId: stats.feedId,
        feedTitle: stats.feedTitle,
        articlesRead: stats.articlesRead + 1,
        readingTime: stats.readingTime + article.estimatedReadTime,
        percentage: 0,
      );
    }
  }
  
  // Calculate percentages and sort
  final topSources = sourceStats.values.toList();
  for (final source in topSources) {
    sourceStats[source.feedId] = SourceStatistics(
      feedId: source.feedId,
      feedTitle: source.feedTitle,
      articlesRead: source.articlesRead,
      readingTime: source.readingTime,
      percentage: (source.articlesRead / totalArticlesRead * 100),
    );
  }
  topSources.sort((a, b) => b.articlesRead.compareTo(a.articlesRead));
  
  // Calculate time distribution
  final timeDistribution = {
    'Morning': 0,
    'Afternoon': 0,
    'Evening': 0,
    'Night': 0,
  };
  
  for (final article in readArticles) {
    final hour = (article.updatedAt ?? article.createdAt).hour;
    if (hour >= 6 && hour < 12) {
      timeDistribution['Morning'] = timeDistribution['Morning']! + 1;
    } else if (hour >= 12 && hour < 18) {
      timeDistribution['Afternoon'] = timeDistribution['Afternoon']! + 1;
    } else if (hour >= 18 && hour < 22) {
      timeDistribution['Evening'] = timeDistribution['Evening']! + 1;
    } else {
      timeDistribution['Night'] = timeDistribution['Night']! + 1;
    }
  }
  
  // Convert to percentages
  if (totalArticlesRead > 0) {
    timeDistribution.forEach((key, value) {
      timeDistribution[key] = ((value / totalArticlesRead) * 100).round();
    });
  }
  
  // Calculate most active day
  final dayActivity = <String, int>{
    'Monday': 0,
    'Tuesday': 0,
    'Wednesday': 0,
    'Thursday': 0,
    'Friday': 0,
    'Saturday': 0,
    'Sunday': 0,
  };
  
  final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  for (final article in readArticles) {
    final weekday = (article.updatedAt ?? article.createdAt).weekday;
    final dayName = weekdays[weekday - 1];
    dayActivity[dayName] = dayActivity[dayName]! + 1;
  }
  
  final mostActiveDay = dayActivity.entries
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;
  
  // Calculate peak reading time
  final hourActivity = List.filled(24, 0);
  for (final article in readArticles) {
    final hour = (article.updatedAt ?? article.createdAt).hour;
    hourActivity[hour]++;
  }
  
  final peakHour = hourActivity.indexOf(hourActivity.reduce(max));
  final peakReadingTime = '${peakHour % 12 == 0 ? 12 : peakHour % 12}:00 ${peakHour < 12 ? 'AM' : 'PM'}';
  
  // Calculate total reading time
  final totalReadingTime = readArticles.fold<int>(
    0, 
    (sum, article) => sum + article.estimatedReadTime,
  );
  
  // Calculate average article length (mock data for now)
  final averageArticleLength = 500; // words
  final readingSpeed = 250; // words per minute
  
  // Create milestones
  final milestones = <ReadingMilestone>[];
  if (totalArticlesRead >= 10) {
    milestones.add(ReadingMilestone(
      title: 'First 10 Articles',
      description: 'Read your first 10 articles',
      achievedAt: DateTime.now(),
      iconName: 'star',
    ));
  }
  if (totalArticlesRead >= 100) {
    milestones.add(ReadingMilestone(
      title: 'Century Reader',
      description: 'Read 100 articles',
      achievedAt: DateTime.now(),
      iconName: 'trophy',
    ));
  }
  if (currentStreak >= 7) {
    milestones.add(ReadingMilestone(
      title: 'Week Warrior',
      description: '7 day reading streak',
      achievedAt: DateTime.now(),
      iconName: 'fire',
    ));
  }
  
  return ReadingStatistics(
    totalArticlesRead: totalArticlesRead,
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    averageArticlesPerDay: averageArticlesPerDay,
    totalReadingTime: totalReadingTime,
    dailyReadingData: dailyReadingData,
    topSources: topSources.take(10).toList(),
    timeDistribution: timeDistribution,
    mostActiveDay: mostActiveDay,
    peakReadingTime: peakReadingTime,
    averageArticleLength: averageArticleLength,
    readingSpeed: readingSpeed,
    categoryDistribution: {},
    milestones: milestones,
  );
});

// Provider to track reading sessions
final readingSessionProvider = StateNotifierProvider<ReadingSessionNotifier, ReadingSession?>((ref) {
  return ReadingSessionNotifier(ref);
});

class ReadingSession {
  final String articleId;
  final DateTime startTime;
  DateTime? endTime;
  int wordsRead;
  
  ReadingSession({
    required this.articleId,
    required this.startTime,
    this.endTime,
    this.wordsRead = 0,
  });
}

class ReadingSessionNotifier extends StateNotifier<ReadingSession?> {
  final Ref ref;
  
  ReadingSessionNotifier(this.ref) : super(null);
  
  void startSession(String articleId) {
    state = ReadingSession(
      articleId: articleId,
      startTime: DateTime.now(),
    );
  }
  
  Future<void> endSession(int wordsRead) async {
    if (state == null) return;
    
    final session = state!;
    session.endTime = DateTime.now();
    session.wordsRead = wordsRead;
    
    // Calculate reading time in minutes
    final readingTime = session.endTime!.difference(session.startTime).inMinutes;
    
    // Update article with estimated read time
    final database = ref.read(databaseProvider);
    await database.articleDao.updateArticle(
      session.articleId,
      {'estimatedReadTime': readingTime},
    );
    
    state = null;
  }
  
  void pauseSession() {
    // Implement pause logic if needed
  }
  
  void resumeSession() {
    // Implement resume logic if needed
  }
}