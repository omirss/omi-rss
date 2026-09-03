class ReadingStatistics {
  final int totalArticlesRead;
  final int currentStreak;
  final int longestStreak;
  final double averageArticlesPerDay;
  final int totalReadingTime; // in minutes
  final List<int> dailyReadingData; // Last 30 days
  final List<SourceStatistics> topSources;
  final Map<String, int> timeDistribution; // Morning, Afternoon, Evening, Night
  final String mostActiveDay;
  final String peakReadingTime;
  final int averageArticleLength; // in words
  final int readingSpeed; // words per minute
  final Map<String, int> categoryDistribution;
  final List<ReadingMilestone> milestones;
  
  ReadingStatistics({
    required this.totalArticlesRead,
    required this.currentStreak,
    required this.longestStreak,
    required this.averageArticlesPerDay,
    required this.totalReadingTime,
    required this.dailyReadingData,
    required this.topSources,
    required this.timeDistribution,
    required this.mostActiveDay,
    required this.peakReadingTime,
    required this.averageArticleLength,
    required this.readingSpeed,
    required this.categoryDistribution,
    required this.milestones,
  });
  
  factory ReadingStatistics.empty() {
    return ReadingStatistics(
      totalArticlesRead: 0,
      currentStreak: 0,
      longestStreak: 0,
      averageArticlesPerDay: 0,
      totalReadingTime: 0,
      dailyReadingData: List.filled(30, 0),
      topSources: [],
      timeDistribution: {
        'Morning': 0,
        'Afternoon': 0,
        'Evening': 0,
        'Night': 0,
      },
      mostActiveDay: 'Monday',
      peakReadingTime: '9:00 AM',
      averageArticleLength: 0,
      readingSpeed: 250,
      categoryDistribution: {},
      milestones: [],
    );
  }
}

class SourceStatistics {
  final String feedId;
  final String feedTitle;
  final int articlesRead;
  final int readingTime;
  final double percentage;
  
  SourceStatistics({
    required this.feedId,
    required this.feedTitle,
    required this.articlesRead,
    required this.readingTime,
    required this.percentage,
  });
}

class ReadingMilestone {
  final String title;
  final String description;
  final DateTime achievedAt;
  final String iconName;
  
  ReadingMilestone({
    required this.title,
    required this.description,
    required this.achievedAt,
    required this.iconName,
  });
}