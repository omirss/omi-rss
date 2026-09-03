import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final extensionServiceProvider = Provider((ref) => ExtensionService());

class ExtensionService {
  bool get isRunningInExtension => 
      html.window.location.protocol == 'chrome-extension:';

  void initialize() {
    if (!isRunningInExtension) return;

    // Listen for messages from extension
    html.window.addEventListener('message', (event) {
      final messageEvent = event as html.MessageEvent;
      if (messageEvent.data is Map && messageEvent.data['type'] == 'TO_FLUTTER') {
        _handleExtensionMessage(messageEvent.data['payload']);
      }
    });

    // Send ready message
    sendToExtension({'action': 'flutterReady'});
  }

  void sendToExtension(Map<String, dynamic> message) {
    if (!isRunningInExtension) return;

    html.window.postMessage({
      'type': 'FROM_FLUTTER',
      'payload': message,
    }, '*');
  }

  void _handleExtensionMessage(Map<String, dynamic> message) {
    switch (message['action']) {
      case 'addFeed':
        _handleAddFeed(message['feed']);
        break;
      case 'saveArticle':
        _handleSaveArticle(message['article']);
        break;
      case 'analyzeArticle':
        _handleAnalyzeArticle(message['article']);
        break;
      case 'openReader':
        _handleOpenReader(message['view']);
        break;
    }
  }

  void _handleAddFeed(Map<String, dynamic> feedData) {
    // Add feed through feed service
    sendToExtension({
      'action': 'feedAdded',
      'feed': feedData,
    });
  }

  void _handleSaveArticle(Map<String, dynamic> articleData) {
    // Save article through article service
    sendToExtension({
      'action': 'articleSaved',
      'article': articleData,
    });
  }

  void _handleAnalyzeArticle(Map<String, dynamic> articleData) {
    // Analyze article through AI service
    sendToExtension({
      'action': 'analysisComplete',
      'analysis': {
        'sentiment': 'positive',
        'bias': 'low',
        'topics': ['technology', 'innovation'],
      },
    });
  }

  void _handleOpenReader(String? view) {
    // Navigate to specific view
    if (view != null) {
      // Handle navigation
    }
  }

  // Extension-specific features
  void requestPermission(String permission) {
    sendToExtension({
      'action': 'requestPermission',
      'permission': permission,
    });
  }

  void updateBadge(String text, String color) {
    sendToExtension({
      'action': 'updateBadge',
      'text': text,
      'color': color,
    });
  }

  void createNotification(String title, String message, {String? iconUrl}) {
    sendToExtension({
      'action': 'createNotification',
      'title': title,
      'message': message,
      'iconUrl': iconUrl,
    });
  }

  void openTab(String url) {
    sendToExtension({
      'action': 'openTab',
      'url': url,
    });
  }

  void getCurrentTab() {
    sendToExtension({
      'action': 'getCurrentTab',
    });
  }

  void detectFeeds() {
    sendToExtension({
      'action': 'detectFeeds',
    });
  }

  void runBypass() {
    sendToExtension({
      'action': 'runBypass',
    });
  }
}