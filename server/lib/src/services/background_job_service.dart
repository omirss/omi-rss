import 'dart:async';
import 'package:serverpod/serverpod.dart';
import 'package:cron/cron.dart';
import 'feed_service.dart';
import 'cleanup_service.dart';
import 'notification_service.dart';
import '../protocol/protocol.dart';

/// Background job service for scheduled tasks
class BackgroundJobService {
  final Serverpod _pod;
  final _cron = Cron();
  final List<ScheduledTask> _tasks = [];
  bool _isRunning = false;

  BackgroundJobService(this._pod);

  /// Start background jobs
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    _pod.log('Starting background job service');

    // Schedule feed refresh job (every 15 minutes)
    _scheduleTask(
      name: 'Feed Refresh',
      schedule: '*/15 * * * *', // Every 15 minutes
      job: _refreshFeeds,
    );

    // Schedule feed health check (every hour)
    _scheduleTask(
      name: 'Feed Health Check',
      schedule: '0 * * * *', // Every hour
      job: _checkFeedHealth,
    );

    // Schedule cleanup job (daily at 3 AM)
    _scheduleTask(
      name: 'Daily Cleanup',
      schedule: '0 3 * * *', // 3 AM daily
      job: _performDailyCleanup,
    );

    // Schedule digest emails (daily at 8 AM)
    _scheduleTask(
      name: 'Daily Digest',
      schedule: '0 8 * * *', // 8 AM daily
      job: _sendDailyDigests,
    );

    // Schedule statistics update (every 6 hours)
    _scheduleTask(
      name: 'Statistics Update',
      schedule: '0 */6 * * *', // Every 6 hours
      job: _updateStatistics,
    );

    // Schedule sync cleanup (weekly on Sunday at 2 AM)
    _scheduleTask(
      name: 'Sync Cleanup',
      schedule: '0 2 * * 0', // Sunday 2 AM
      job: _cleanupSyncData,
    );

    _pod.log('Background job service started with ${_tasks.length} scheduled tasks');
  }

  /// Stop background jobs
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    _pod.log('Stopping background job service');
    
    await _cron.close();
    _tasks.clear();
  }

  /// Schedule a task
  void _scheduleTask({
    required String name,
    required String schedule,
    required Future<void> Function() job,
  }) {
    try {
      final scheduledJob = _cron.schedule(Schedule.parse(schedule), () async {
        await _runJob(name, job);
      });

      _tasks.add(ScheduledTask(
        name: name,
        schedule: schedule,
        job: scheduledJob,
      ));

      _pod.log('Scheduled task: $name with schedule: $schedule');
    } catch (e) {
      _pod.log('Failed to schedule task $name: $e', level: LogLevel.error);
    }
  }

  /// Run a job with error handling
  Future<void> _runJob(String name, Future<void> Function() job) async {
    _pod.log('Running job: $name');
    final startTime = DateTime.now();

    try {
      await job();
      
      final duration = DateTime.now().difference(startTime);
      _pod.log('Job $name completed in ${duration.inMilliseconds}ms');
      
      // Record job execution
      await _recordJobExecution(name, true, duration);
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      _pod.log(
        'Job $name failed after ${duration.inMilliseconds}ms: $e',
        level: LogLevel.error,
        stackTrace: stackTrace,
      );
      
      // Record job failure
      await _recordJobExecution(name, false, duration, error: e.toString());
    }
  }

  /// Refresh all active feeds
  Future<void> _refreshFeeds() async {
    final session = await _pod.createSession();
    
    try {
      // Get all enabled feeds
      final feeds = await Feed.db.findEnabledFeeds(session);
      _pod.log('Refreshing ${feeds.length} feeds');

      final feedService = _pod.getSingleton<FeedService>();
      
      // Process feeds in batches
      const batchSize = 10;
      for (var i = 0; i < feeds.length; i += batchSize) {
        final batch = feeds.skip(i).take(batchSize).toList();
        
        await Future.wait(
          batch.map((feed) => feedService.fetchFeedArticles(session, feed.id!)),
          eagerError: false,
        );
        
        // Small delay between batches
        if (i + batchSize < feeds.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      await session.close();
    }
  }

  /// Check feed health and disable problematic feeds
  Future<void> _checkFeedHealth() async {
    final session = await _pod.createSession();
    
    try {
      // Get feeds with errors
      final feeds = await session.db.find<Feed>(
        where: (t) => t.errorCount.greaterThan(0) & t.isEnabled.equals(true),
      );

      _pod.log('Checking health of ${feeds.length} feeds with errors');

      for (final feed in feeds) {
        // Disable feeds with too many consecutive errors
        if (feed.errorCount >= 10) {
          feed.isEnabled = false;
          feed.updatedAt = DateTime.now();
          await session.db.updateRow<Feed>(feed);
          
          _pod.log('Disabled feed ${feed.id} (${feed.title}) due to ${feed.errorCount} errors');
          
          // TODO: Notify user about disabled feed
        }
      }
    } finally {
      await session.close();
    }
  }

  /// Perform daily cleanup tasks
  Future<void> _performDailyCleanup() async {
    final session = await _pod.createSession();
    
    try {
      final cleanupService = CleanupService(session);
      
      // Clean old deleted items
      await cleanupService.cleanDeletedItems(olderThan: const Duration(days: 30));
      
      // Clean old sync data
      await cleanupService.cleanOldSyncData(olderThan: const Duration(days: 90));
      
      // Clean expired invites
      await cleanupService.cleanExpiredInvites();
      
      // Clean orphaned data
      await cleanupService.cleanOrphanedData();
      
      // Optimize database
      await cleanupService.optimizeDatabase();
    } finally {
      await session.close();
    }
  }

  /// Send daily digest emails
  Future<void> _sendDailyDigests() async {
    final session = await _pod.createSession();
    
    try {
      // Get users with daily digest enabled
      final users = await session.db.find<UserSettings>(
        where: (t) => t.preferences['emailDigest'].equals(true),
      );

      _pod.log('Sending daily digests to ${users.length} users');

      final notificationService = _pod.getSingleton<NotificationService>();
      
      for (final userSettings in users) {
        try {
          // Get user's unread articles from last 24 hours
          final yesterday = DateTime.now().subtract(const Duration(days: 1));
          
          final articles = await session.db.find<Article>(
            where: (t) => t.userId.equals(userSettings.userId) &
                t.isRead.equals(false) &
                t.createdAt.afterThan(yesterday),
            limit: 20,
            orderBy: Article.t.publishedAt.descending,
          );

          if (articles.isNotEmpty) {
            await notificationService.sendDailyDigest(
              userSettings.userId,
              articles,
            );
          }
        } catch (e) {
          _pod.log('Failed to send digest to user ${userSettings.userId}: $e');
        }
      }
    } finally {
      await session.close();
    }
  }

  /// Update statistics
  Future<void> _updateStatistics() async {
    final session = await _pod.createSession();
    
    try {
      // Update feed statistics
      final feeds = await session.db.find<Feed>();
      
      for (final feed in feeds) {
        // Count articles
        final articleCount = await session.db.count<Article>(
          where: (t) => t.feedId.equals(feed.id!) & t.deletedAt.equals(null),
        );
        
        // Count unread articles
        final unreadCount = await session.db.count<Article>(
          where: (t) => t.feedId.equals(feed.id!) & 
              t.isRead.equals(false) & 
              t.deletedAt.equals(null),
        );
        
        // Update if changed
        if (feed.articleCount != articleCount || feed.unreadCount != unreadCount) {
          await Feed.db.updateArticleCounts(
            session,
            feed.id!,
            articleCount,
            unreadCount,
          );
        }
      }
      
      // Update user statistics
      // TODO: Implement user statistics update
    } finally {
      await session.close();
    }
  }

  /// Clean up old sync data
  Future<void> _cleanupSyncData() async {
    final session = await _pod.createSession();
    
    try {
      // Delete old sync changes
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      
      final deletedCount = await session.db.deleteWhere<SyncChange>(
        where: (t) => t.timestamp.beforeThan(cutoffDate),
      );
      
      _pod.log('Deleted $deletedCount old sync changes');
      
      // Clean inactive devices
      final inactiveDate = DateTime.now().subtract(const Duration(days: 90));
      
      final devicesDeleted = await session.db.deleteWhere<UserDevice>(
        where: (t) => t.lastActiveAt.beforeThan(inactiveDate),
      );
      
      _pod.log('Removed $devicesDeleted inactive devices');
    } finally {
      await session.close();
    }
  }

  /// Record job execution
  Future<void> _recordJobExecution(
    String jobName,
    bool success,
    Duration duration, {
    String? error,
  }) async {
    final session = await _pod.createSession();
    
    try {
      await session.db.insertRow<JobExecution>(
        JobExecution(
          jobName: jobName,
          success: success,
          duration: duration.inMilliseconds,
          error: error,
          executedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _pod.log('Failed to record job execution: $e');
    } finally {
      await session.close();
    }
  }
}

/// Scheduled task info
class ScheduledTask {
  final String name;
  final String schedule;
  final ScheduledTask job;

  ScheduledTask({
    required this.name,
    required this.schedule,
    required this.job,
  });
}

/// Job execution record
class JobExecution extends TableRow {
  int? id;
  String jobName;
  bool success;
  int duration; // milliseconds
  String? error;
  DateTime executedAt;

  JobExecution({
    this.id,
    required this.jobName,
    required this.success,
    required this.duration,
    this.error,
    required this.executedAt,
  });

  static final t = JobExecutionTable();

  @override
  String get tableName => 'job_executions';

  factory JobExecution.fromJson(Map<String, dynamic> json) {
    return JobExecution(
      id: json['id'] as int?,
      jobName: json['jobName'] as String,
      success: json['success'] as bool,
      duration: json['duration'] as int,
      error: json['error'] as String?,
      executedAt: DateTime.parse(json['executedAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'jobName': jobName,
      'success': success,
      'duration': duration,
      if (error != null) 'error': error,
      'executedAt': executedAt.toIso8601String(),
    };
  }

  @override
  Map<String, dynamic> toJsonForDatabase() {
    return {
      if (id != null) 'id': id,
      'job_name': jobName,
      'success': success,
      'duration': duration,
      'error': error,
      'executed_at': executedAt,
    };
  }

  @override
  void setColumn(String columnName, value) {
    switch (columnName) {
      case 'id':
        id = value;
        return;
      case 'job_name':
        jobName = value;
        return;
      case 'success':
        success = value;
        return;
      case 'duration':
        duration = value;
        return;
      case 'error':
        error = value;
        return;
      case 'executed_at':
        executedAt = value;
        return;
      default:
        throw UnimplementedError();
    }
  }
}

class JobExecutionTable extends Table {
  JobExecutionTable() : super(tableName: 'job_executions');

  late final id = ColumnInt('id', this, isPrimaryKey: true);
  late final jobName = ColumnString('job_name', this);
  late final success = ColumnBool('success', this);
  late final duration = ColumnInt('duration', this);
  late final error = ColumnString('error', this);
  late final executedAt = ColumnDateTime('executed_at', this);

  @override
  List<Column> get columns => [
    id,
    jobName,
    success,
    duration,
    error,
    executedAt,
  ];
}