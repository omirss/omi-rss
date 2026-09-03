import 'dart:async';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:serverpod/serverpod.dart';
import '../protocol/protocol.dart';

class NotificationService {
  final Session session;
  late final SmtpServer? _smtpServer;
  late final String _fromEmail;
  late final String _fromName;
  
  // Push notification providers
  late final String? _fcmKey;
  late final String? _apnsKey;
  
  NotificationService(this.session) {
    final config = session.serverpod.config;
    final emailConfig = config['email'];
    
    if (emailConfig != null) {
      _fromEmail = emailConfig['fromEmail'] ?? 'noreply@omi-rss.com';
      _fromName = emailConfig['fromName'] ?? 'Omi RSS';
      
      if (emailConfig['smtp'] != null) {
        final smtp = emailConfig['smtp'];
        _smtpServer = SmtpServer(
          smtp['host'],
          port: smtp['port'],
          username: smtp['username'],
          password: smtp['password'],
          ssl: smtp['ssl'] ?? true,
        );
      } else {
        _smtpServer = null;
      }
    } else {
      _smtpServer = null;
      _fromEmail = 'noreply@omi-rss.com';
      _fromName = 'Omi RSS';
    }
    
    // Push notification keys
    _fcmKey = config['push']?['fcm']?['serverKey'];
    _apnsKey = config['push']?['apns']?['key'];
  }

  // Send email notification
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String htmlBody,
    String? textBody,
    List<Attachment>? attachments,
  }) async {
    if (_smtpServer == null) {
      session.log('Email not configured');
      return false;
    }
    
    try {
      final message = Message()
        ..from = Address(_fromEmail, _fromName)
        ..recipients.add(to)
        ..subject = subject
        ..html = htmlBody
        ..text = textBody ?? _stripHtml(htmlBody);
      
      if (attachments != null) {
        message.attachments.addAll(attachments);
      }
      
      final sendReports = await send(message, _smtpServer!);
      
      // Log send report
      for (final report in sendReports) {
        if (report.sent) {
          session.log('Email sent to $to: ${report.message}');
        } else {
          session.log('Email failed to $to: ${report.message}');
          return false;
        }
      }
      
      return true;
    } catch (e) {
      session.log('Email error: $e');
      return false;
    }
  }

  // Send push notification
  Future<bool> sendPushNotification({
    required int userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
  }) async {
    try {
      // Get user's push tokens
      final pushTokens = await _getUserPushTokens(userId);
      
      if (pushTokens.isEmpty) {
        session.log('No push tokens for user $userId');
        return false;
      }
      
      bool anySuccess = false;
      
      for (final token in pushTokens) {
        if (token.platform == 'android' || token.platform == 'web') {
          // Send FCM notification
          if (_fcmKey != null) {
            final success = await _sendFcmNotification(
              token: token.token,
              title: title,
              body: body,
              data: data,
              imageUrl: imageUrl,
            );
            if (success) anySuccess = true;
          }
        } else if (token.platform == 'ios') {
          // Send APNS notification
          if (_apnsKey != null) {
            final success = await _sendApnsNotification(
              token: token.token,
              title: title,
              body: body,
              data: data,
              imageUrl: imageUrl,
            );
            if (success) anySuccess = true;
          }
        }
      }
      
      return anySuccess;
    } catch (e) {
      session.log('Push notification error: $e');
      return false;
    }
  }

  // Send collaboration invitation email
  Future<bool> sendCollaborationInvite({
    required String toEmail,
    required String inviterName,
    required String folderName,
    required String inviteCode,
    required String role,
  }) async {
    final subject = '$inviterName invited you to collaborate on "$folderName"';
    
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 10px 10px; }
    .button { display: inline-block; padding: 12px 30px; background: #667eea; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 14px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>You're invited to collaborate!</h1>
    </div>
    <div class="content">
      <p>Hi there,</p>
      <p><strong>$inviterName</strong> has invited you to collaborate on the folder "<strong>$folderName</strong>" as a <strong>$role</strong>.</p>
      <p>With Omi RSS, you can:</p>
      <ul>
        <li>Share and discuss articles with your team</li>
        <li>Add comments and annotations</li>
        <li>Stay updated with real-time collaboration</li>
      </ul>
      <center>
        <a href="https://omi-rss.com/invite/$inviteCode" class="button">Accept Invitation</a>
      </center>
      <p>Or use this invite code in the app: <code>$inviteCode</code></p>
    </div>
    <div class="footer">
      <p>This invitation will expire in 7 days.</p>
      <p>&copy; 2024 Omi RSS. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''';
    
    return await sendEmail(
      to: toEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  // Send daily digest email
  Future<bool> sendDailyDigest({
    required int userId,
    required String userEmail,
    required String userName,
    required List<Article> articles,
    required Map<int, Feed> feeds,
    required DigestStats stats,
  }) async {
    final subject = 'Your Omi RSS Daily Digest - ${articles.length} new articles';
    
    final articleItems = articles.take(10).map((article) {
      final feed = feeds[article.feedId];
      return '''
<div style="margin-bottom: 20px; padding: 15px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
  <h3 style="margin: 0 0 10px 0;"><a href="${article.url}" style="color: #667eea; text-decoration: none;">${_escapeHtml(article.title)}</a></h3>
  <p style="color: #666; font-size: 14px; margin: 0 0 10px 0;">
    ${feed?.title ?? 'Unknown Feed'} • ${_formatDate(article.publishedAt)}
  </p>
  <p style="margin: 0; color: #333;">${_escapeHtml(article.description ?? '').substring(0, 200)}...</p>
</div>
''';
    }).join('\n');
    
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; background: #f5f5f5; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px; margin-bottom: 20px; }
    .stats { display: flex; justify-content: space-around; margin: 20px 0; }
    .stat { text-align: center; background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .stat-number { font-size: 24px; font-weight: bold; color: #667eea; }
    .stat-label { font-size: 14px; color: #666; }
    .footer { text-align: center; color: #666; font-size: 14px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Good morning, $userName!</h1>
      <p>Here's what's new in your feeds today</p>
    </div>
    
    <div class="stats">
      <div class="stat">
        <div class="stat-number">${stats.newArticles}</div>
        <div class="stat-label">New Articles</div>
      </div>
      <div class="stat">
        <div class="stat-number">${stats.activeFeeds}</div>
        <div class="stat-label">Active Feeds</div>
      </div>
      <div class="stat">
        <div class="stat-number">${stats.readYesterday}</div>
        <div class="stat-label">Read Yesterday</div>
      </div>
    </div>
    
    <h2 style="color: #333; margin: 30px 0 20px 0;">Top Articles</h2>
    $articleItems
    
    ${articles.length > 10 ? '<p style="text-align: center; margin: 30px 0;"><a href="https://omi-rss.com" style="color: #667eea;">View all ${articles.length} new articles →</a></p>' : ''}
    
    <div class="footer">
      <p>You're receiving this because you have email digests enabled.</p>
      <p><a href="https://omi-rss.com/settings/notifications" style="color: #667eea;">Manage notification preferences</a></p>
      <p>&copy; 2024 Omi RSS. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''';
    
    return await sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  // Send market alert email
  Future<bool> sendMarketAlert({
    required String userEmail,
    required String userName,
    required String symbol,
    required String alertType,
    required double currentPrice,
    required double targetPrice,
    required double changePercent,
  }) async {
    final direction = currentPrice > targetPrice ? 'above' : 'below';
    final subject = '🔔 Price Alert: $symbol is $direction \$${targetPrice.toStringAsFixed(2)}';
    
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .alert-box { background: ${changePercent > 0 ? '#e8f5e9' : '#ffebee'}; border-left: 4px solid ${changePercent > 0 ? '#4caf50' : '#f44336'}; padding: 20px; border-radius: 5px; }
    .price { font-size: 36px; font-weight: bold; color: ${changePercent > 0 ? '#4caf50' : '#f44336'}; }
    .change { font-size: 18px; color: ${changePercent > 0 ? '#4caf50' : '#f44336'}; }
  </style>
</head>
<body>
  <div class="container">
    <h2>Hi $userName,</h2>
    <div class="alert-box">
      <h3>$symbol Price Alert Triggered!</h3>
      <p class="price">\$${currentPrice.toStringAsFixed(2)}</p>
      <p class="change">${changePercent > 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%</p>
      <p>Your alert for $symbol to go $direction \$${targetPrice.toStringAsFixed(2)} has been triggered.</p>
    </div>
    <p style="margin-top: 30px;">
      <a href="https://omi-rss.com/market/$symbol" style="background: #667eea; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px;">View Details</a>
    </p>
  </div>
</body>
</html>
''';
    
    return await sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  // Send new comment notification
  Future<bool> sendCommentNotification({
    required String userEmail,
    required String userName,
    required String commenterName,
    required String articleTitle,
    required String commentText,
    required String articleUrl,
  }) async {
    final subject = '$commenterName commented on "$articleTitle"';
    
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .comment-box { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #667eea; margin: 20px 0; }
    .commenter { font-weight: bold; color: #667eea; }
  </style>
</head>
<body>
  <div class="container">
    <h2>Hi $userName,</h2>
    <p><span class="commenter">$commenterName</span> commented on an article you're following:</p>
    <h3>"$articleTitle"</h3>
    <div class="comment-box">
      <p>${_escapeHtml(commentText)}</p>
    </div>
    <p>
      <a href="$articleUrl" style="background: #667eea; color: white; padding: 12px 24px; text-decoration: none; border-radius: 5px;">View Article & Reply</a>
    </p>
  </div>
</body>
</html>
''';
    
    return await sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  // Private helper methods
  Future<List<PushToken>> _getUserPushTokens(int userId) async {
    // In a real implementation, fetch from database
    // For now, return empty list
    return [];
  }

  Future<bool> _sendFcmNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
  }) async {
    // FCM implementation
    // Would use firebase_admin SDK or HTTP API
    session.log('FCM notification would be sent to $token');
    return true;
  }

  Future<bool> _sendApnsNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
  }) async {
    // APNS implementation
    // Would use APNS HTTP/2 API
    session.log('APNS notification would be sent to $token');
    return true;
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// Supporting classes
class PushToken {
  final String token;
  final String platform;
  
  PushToken({required this.token, required this.platform});
}

class DigestStats {
  final int newArticles;
  final int activeFeeds;
  final int readYesterday;
  
  DigestStats({
    required this.newArticles,
    required this.activeFeeds,
    required this.readYesterday,
  });
}