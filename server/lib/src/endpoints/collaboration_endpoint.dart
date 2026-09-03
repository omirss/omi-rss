import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../protocol/protocol.dart';
import '../services/collaboration_service.dart';
import '../services/notification_service.dart';

class CollaborationEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// Create a shared folder
  Future<SharedFolder> createSharedFolder(
    Session session,
    String name,
    String description,
    List<int> feedIds, {
    SharedFolderPermissions? permissions,
    bool isPublic = false,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Verify user owns all feeds
    final feeds = await session.db.find<Feed>(
      where: (t) => t.id.inSet(feedIds) & t.userId.equals(userId),
    );

    if (feeds.length != feedIds.length) {
      throw Exception('Some feeds not found or unauthorized');
    }

    final collaborationService = CollaborationService(session);
    final folder = await collaborationService.createSharedFolder(
      ownerId: userId,
      name: name,
      description: description,
      feedIds: feedIds,
      permissions: permissions ?? SharedFolderPermissions.defaultPermissions(),
      isPublic: isPublic,
    );

    return folder;
  }

  /// Get shared folders
  Future<List<SharedFolder>> getSharedFolders(Session session) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    return await collaborationService.getSharedFolders(userId);
  }

  /// Get shared folder details
  Future<SharedFolder?> getSharedFolder(Session session, int folderId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    final folder = await collaborationService.getSharedFolder(folderId);

    // Check access
    if (folder != null && !await collaborationService.hasAccess(userId, folderId)) {
      throw Exception('Unauthorized access to folder');
    }

    return folder;
  }

  /// Update shared folder
  Future<SharedFolder> updateSharedFolder(
    Session session,
    int folderId,
    String? name,
    String? description,
    SharedFolderPermissions? permissions,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check if user is owner
    final folder = await collaborationService.getSharedFolder(folderId);
    if (folder == null || folder.ownerId != userId) {
      throw Exception('Only owner can update folder');
    }

    return await collaborationService.updateSharedFolder(
      folderId: folderId,
      name: name,
      description: description,
      permissions: permissions,
    );
  }

  /// Delete shared folder
  Future<void> deleteSharedFolder(Session session, int folderId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check if user is owner
    final folder = await collaborationService.getSharedFolder(folderId);
    if (folder == null || folder.ownerId != userId) {
      throw Exception('Only owner can delete folder');
    }

    await collaborationService.deleteSharedFolder(folderId);
  }

  /// Invite member to folder
  Future<ShareInvite> inviteMember(
    Session session,
    int folderId,
    String email,
    MemberRole role, {
    String? message,
    DateTime? expiresAt,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check permission
    if (!await collaborationService.canInvite(userId, folderId)) {
      throw Exception('No permission to invite members');
    }

    final invite = await collaborationService.createInvite(
      folderId: folderId,
      invitedBy: userId,
      email: email,
      role: role,
      message: message,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
    );

    // Send invitation email
    final notificationService = session.serverpod.getSingleton<NotificationService>();
    await notificationService.sendInviteEmail(email, invite);

    return invite;
  }

  /// Accept folder invite
  Future<void> acceptInvite(Session session, String inviteToken) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    await collaborationService.acceptInvite(userId, inviteToken);
  }

  /// Get folder members
  Future<List<FolderMember>> getFolderMembers(Session session, int folderId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check access
    if (!await collaborationService.hasAccess(userId, folderId)) {
      throw Exception('Unauthorized access to folder');
    }

    return await collaborationService.getFolderMembers(folderId);
  }

  /// Update member role
  Future<void> updateMemberRole(
    Session session,
    int folderId,
    int memberId,
    MemberRole newRole,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check permission
    if (!await collaborationService.canManageMembers(userId, folderId)) {
      throw Exception('No permission to manage members');
    }

    await collaborationService.updateMemberRole(folderId, memberId, newRole);
  }

  /// Remove member from folder
  Future<void> removeMember(
    Session session,
    int folderId,
    int memberId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check permission
    if (!await collaborationService.canManageMembers(userId, folderId)) {
      throw Exception('No permission to manage members');
    }

    await collaborationService.removeMember(folderId, memberId);
  }

  /// Leave shared folder
  Future<void> leaveFolder(Session session, int folderId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    await collaborationService.leaveFolder(userId, folderId);
  }

  /// Transfer folder ownership
  Future<void> transferOwnership(
    Session session,
    int folderId,
    int newOwnerId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check if user is owner
    final folder = await collaborationService.getSharedFolder(folderId);
    if (folder == null || folder.ownerId != userId) {
      throw Exception('Only owner can transfer ownership');
    }

    await collaborationService.transferOwnership(folderId, newOwnerId);
  }

  /// Add comment to article
  Future<ArticleComment> addComment(
    Session session,
    int folderId,
    int articleId,
    String content, {
    int? parentId,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check permission
    if (!await collaborationService.canComment(userId, folderId)) {
      throw Exception('No permission to comment');
    }

    return await collaborationService.addComment(
      userId: userId,
      folderId: folderId,
      articleId: articleId,
      content: content,
      parentId: parentId,
    );
  }

  /// Get article comments
  Future<List<ArticleComment>> getComments(
    Session session,
    int folderId,
    int articleId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check access
    if (!await collaborationService.hasAccess(userId, folderId)) {
      throw Exception('Unauthorized access to folder');
    }

    return await collaborationService.getComments(articleId);
  }

  /// Add annotation to article
  Future<ArticleAnnotation> addAnnotation(
    Session session,
    int folderId,
    int articleId,
    String selectedText,
    String note,
    AnnotationPosition position, {
    AnnotationType type = AnnotationType.highlight,
    String? color,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check permission
    if (!await collaborationService.canAnnotate(userId, folderId)) {
      throw Exception('No permission to annotate');
    }

    return await collaborationService.addAnnotation(
      userId: userId,
      folderId: folderId,
      articleId: articleId,
      selectedText: selectedText,
      note: note,
      position: position,
      type: type,
      color: color,
    );
  }

  /// Get article annotations
  Future<List<ArticleAnnotation>> getAnnotations(
    Session session,
    int folderId,
    int articleId,
  ) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check access
    if (!await collaborationService.hasAccess(userId, folderId)) {
      throw Exception('Unauthorized access to folder');
    }

    return await collaborationService.getAnnotations(articleId);
  }

  /// Get folder activity
  Future<List<FolderActivity>> getFolderActivity(
    Session session,
    int folderId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check access
    if (!await collaborationService.hasAccess(userId, folderId)) {
      throw Exception('Unauthorized access to folder');
    }

    return await collaborationService.getFolderActivity(
      folderId,
      limit: limit,
      offset: offset,
    );
  }

  /// Search public folders
  Future<List<SharedFolder>> searchPublicFolders(
    Session session,
    String query, {
    int limit = 20,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    return await collaborationService.searchPublicFolders(query, limit: limit);
  }

  /// Join public folder
  Future<void> joinPublicFolder(Session session, int folderId) async {
    final userId = await session.auth.authenticatedUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final collaborationService = CollaborationService(session);
    
    // Check if folder is public
    final folder = await collaborationService.getSharedFolder(folderId);
    if (folder == null || !folder.isPublic) {
      throw Exception('Folder not found or not public');
    }

    await collaborationService.joinPublicFolder(userId, folderId);
  }
}

// Supporting models
class ShareInvite {
  final String id;
  final int folderId;
  final String folderName;
  final int invitedBy;
  final String email;
  final MemberRole role;
  final String? message;
  final String token;
  final DateTime expiresAt;
  final DateTime createdAt;

  ShareInvite({
    required this.id,
    required this.folderId,
    required this.folderName,
    required this.invitedBy,
    required this.email,
    required this.role,
    this.message,
    required this.token,
    required this.expiresAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'folderName': folderName,
    'invitedBy': invitedBy,
    'email': email,
    'role': role.name,
    'message': message,
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };
}

enum MemberRole {
  owner,
  editor,
  contributor,
  viewer,
}

class FolderMember {
  final int id;
  final int userId;
  final String userName;
  final String email;
  final String? avatarUrl;
  final MemberRole role;
  final DateTime joinedAt;

  FolderMember({
    required this.id,
    required this.userId,
    required this.userName,
    required this.email,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'userName': userName,
    'email': email,
    'avatarUrl': avatarUrl,
    'role': role.name,
    'joinedAt': joinedAt.toIso8601String(),
  };
}

class ArticleComment {
  final int id;
  final int articleId;
  final int userId;
  final String userName;
  final String content;
  final int? parentId;
  final DateTime createdAt;
  final int likes;
  final List<ArticleComment> replies;

  ArticleComment({
    required this.id,
    required this.articleId,
    required this.userId,
    required this.userName,
    required this.content,
    this.parentId,
    required this.createdAt,
    required this.likes,
    this.replies = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'userId': userId,
    'userName': userName,
    'content': content,
    'parentId': parentId,
    'createdAt': createdAt.toIso8601String(),
    'likes': likes,
    'replies': replies.map((r) => r.toJson()).toList(),
  };
}

class ArticleAnnotation {
  final int id;
  final int articleId;
  final int userId;
  final String userName;
  final String selectedText;
  final String note;
  final AnnotationPosition position;
  final AnnotationType type;
  final String color;
  final DateTime createdAt;

  ArticleAnnotation({
    required this.id,
    required this.articleId,
    required this.userId,
    required this.userName,
    required this.selectedText,
    required this.note,
    required this.position,
    required this.type,
    required this.color,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'userId': userId,
    'userName': userName,
    'selectedText': selectedText,
    'note': note,
    'position': position.toJson(),
    'type': type.name,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };
}

class AnnotationPosition {
  final int startOffset;
  final int endOffset;
  final String? elementPath;

  AnnotationPosition({
    required this.startOffset,
    required this.endOffset,
    this.elementPath,
  });

  Map<String, dynamic> toJson() => {
    'startOffset': startOffset,
    'endOffset': endOffset,
    'elementPath': elementPath,
  };
}

enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  note,
}

class FolderActivity {
  final int id;
  final int folderId;
  final int userId;
  final String userName;
  final ActivityAction action;
  final String? targetName;
  final DateTime timestamp;

  FolderActivity({
    required this.id,
    required this.folderId,
    required this.userId,
    required this.userName,
    required this.action,
    this.targetName,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'userId': userId,
    'userName': userName,
    'action': action.name,
    'targetName': targetName,
    'timestamp': timestamp.toIso8601String(),
  };
}

enum ActivityAction {
  joinedFolder,
  leftFolder,
  addedArticle,
  removedArticle,
  commented,
  annotated,
  invitedMember,
  roleChanged,
}