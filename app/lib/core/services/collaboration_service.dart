import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import 'encryption_service.dart';

/// Collaboration service for shared folders and team features
class CollaborationService {
  final AppDatabase _database;
  final EncryptionService _encryption;
  final Dio _dio;
  
  // Current user
  String? _userId;
  
  // Shared folders cache
  final Map<String, SharedFolder> _sharedFolders = {};
  final Map<String, List<FolderMember>> _folderMembers = {};
  
  // Real-time updates
  final _sharingController = StreamController<SharingEvent>.broadcast();
  
  CollaborationService({
    required AppDatabase database,
    required EncryptionService encryption,
  }) : _database = database,
       _encryption = encryption,
       _dio = Dio();

  /// Initialize with user
  void initialize(String userId) {
    _userId = userId;
  }
  
  /// Create shared folder
  Future<SharedFolder> createSharedFolder({
    required String name,
    required String description,
    required List<String> feedIds,
    SharedFolderPermissions permissions = const SharedFolderPermissions(),
    bool isPublic = false,
  }) async {
    final folderId = const Uuid().v4();
    
    // Generate encryption key for folder
    final encryptionKey = await _encryption.generateSharingKey();
    
    // Create folder in database
    final folder = Folder(
      id: folderId,
      name: name,
      icon: 'folder_shared',
      color: '#2196F3',
      createdAt: DateTime.now(),
    );
    
    await _database.foldersDao.insertFolder(folder);
    
    // Create shared folder metadata
    final sharedFolder = SharedFolder(
      id: folderId,
      name: name,
      description: description,
      ownerId: _userId!,
      ownerName: 'You',
      feedIds: feedIds,
      permissions: permissions,
      isPublic: isPublic,
      encryptionKey: encryptionKey,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      memberCount: 1,
      articleCount: 0,
    );
    
    _sharedFolders[folderId] = sharedFolder;
    
    // Add owner as member
    await _addMember(
      folderId: folderId,
      userId: _userId!,
      role: MemberRole.owner,
    );
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.folderCreated,
      folderId: folderId,
      message: 'Created shared folder: $name',
    ));
    
    return sharedFolder;
  }
  
  /// Share folder with user
  Future<ShareInvite> shareFolder({
    required String folderId,
    required String email,
    MemberRole role = MemberRole.viewer,
    String? message,
    DateTime? expiresAt,
  }) async {
    final folder = _sharedFolders[folderId];
    if (folder == null) {
      throw Exception('Folder not found');
    }
    
    // Check permissions
    if (!await _hasPermission(folderId, FolderPermission.invite)) {
      throw Exception('No permission to invite members');
    }
    
    // Create invite
    final invite = ShareInvite(
      id: const Uuid().v4(),
      folderId: folderId,
      folderName: folder.name,
      invitedBy: _userId!,
      invitedEmail: email,
      role: role,
      message: message,
      token: _generateInviteToken(),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 7)),
      createdAt: DateTime.now(),
    );
    
    // Send invite email (mock)
    print('Sending invite to $email for folder ${folder.name}');
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.inviteSent,
      folderId: folderId,
      message: 'Invited $email to folder',
      data: invite,
    ));
    
    return invite;
  }
  
  /// Accept folder invite
  Future<void> acceptInvite(String inviteToken) async {
    // Validate invite token
    // In real implementation, this would check against server
    
    // For demo, extract folder ID from token
    final parts = inviteToken.split('-');
    if (parts.length < 2) {
      throw Exception('Invalid invite token');
    }
    
    final folderId = parts[1];
    final folder = _sharedFolders[folderId];
    if (folder == null) {
      throw Exception('Folder not found');
    }
    
    // Add user as member
    await _addMember(
      folderId: folderId,
      userId: _userId!,
      role: MemberRole.viewer, // Default role from invite
    );
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.memberJoined,
      folderId: folderId,
      message: 'Joined shared folder: ${folder.name}',
    ));
  }
  
  /// Leave shared folder
  Future<void> leaveFolder(String folderId) async {
    final members = _folderMembers[folderId] ?? [];
    final myMembership = members.firstWhere(
      (m) => m.userId == _userId,
      orElse: () => throw Exception('Not a member of this folder'),
    );
    
    if (myMembership.role == MemberRole.owner) {
      throw Exception('Owner cannot leave folder. Transfer ownership first.');
    }
    
    // Remove membership
    _folderMembers[folderId] = members.where((m) => m.userId != _userId).toList();
    
    // Remove folder from local database
    await _database.foldersDao.deleteFolder(folderId);
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.memberLeft,
      folderId: folderId,
      message: 'Left shared folder',
    ));
  }
  
  /// Update member role
  Future<void> updateMemberRole({
    required String folderId,
    required String userId,
    required MemberRole newRole,
  }) async {
    // Check permissions
    if (!await _hasPermission(folderId, FolderPermission.manageMember)) {
      throw Exception('No permission to manage members');
    }
    
    final members = _folderMembers[folderId] ?? [];
    final memberIndex = members.indexWhere((m) => m.userId == userId);
    
    if (memberIndex == -1) {
      throw Exception('Member not found');
    }
    
    // Update role
    members[memberIndex] = members[memberIndex].copyWith(role: newRole);
    _folderMembers[folderId] = members;
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.roleChanged,
      folderId: folderId,
      message: 'Updated member role',
      data: {'userId': userId, 'role': newRole},
    ));
  }
  
  /// Remove member from folder
  Future<void> removeMember({
    required String folderId,
    required String userId,
  }) async {
    // Check permissions
    if (!await _hasPermission(folderId, FolderPermission.manageMember)) {
      throw Exception('No permission to remove members');
    }
    
    final members = _folderMembers[folderId] ?? [];
    final member = members.firstWhere(
      (m) => m.userId == userId,
      orElse: () => throw Exception('Member not found'),
    );
    
    if (member.role == MemberRole.owner) {
      throw Exception('Cannot remove owner');
    }
    
    // Remove member
    _folderMembers[folderId] = members.where((m) => m.userId != userId).toList();
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.memberRemoved,
      folderId: folderId,
      message: 'Removed member from folder',
      data: {'userId': userId},
    ));
  }
  
  /// Transfer folder ownership
  Future<void> transferOwnership({
    required String folderId,
    required String newOwnerId,
  }) async {
    final members = _folderMembers[folderId] ?? [];
    
    // Verify current user is owner
    final currentOwner = members.firstWhere(
      (m) => m.userId == _userId && m.role == MemberRole.owner,
      orElse: () => throw Exception('Not the owner of this folder'),
    );
    
    // Verify new owner is a member
    final newOwnerIndex = members.indexWhere((m) => m.userId == newOwnerId);
    if (newOwnerIndex == -1) {
      throw Exception('New owner must be a member of the folder');
    }
    
    // Update roles
    members[members.indexOf(currentOwner)] = currentOwner.copyWith(role: MemberRole.editor);
    members[newOwnerIndex] = members[newOwnerIndex].copyWith(role: MemberRole.owner);
    
    _folderMembers[folderId] = members;
    
    // Update folder metadata
    final folder = _sharedFolders[folderId]!;
    _sharedFolders[folderId] = folder.copyWith(
      ownerId: newOwnerId,
      ownerName: members[newOwnerIndex].userName,
    );
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.ownershipTransferred,
      folderId: folderId,
      message: 'Ownership transferred',
      data: {'newOwnerId': newOwnerId},
    ));
  }
  
  /// Add comment to article
  Future<ArticleComment> addComment({
    required String folderId,
    required String articleId,
    required String content,
    String? parentId,
  }) async {
    // Check permissions
    if (!await _hasPermission(folderId, FolderPermission.comment)) {
      throw Exception('No permission to comment');
    }
    
    final comment = ArticleComment(
      id: const Uuid().v4(),
      articleId: articleId,
      userId: _userId!,
      userName: 'Current User', // Get from user profile
      content: content,
      parentId: parentId,
      createdAt: DateTime.now(),
      likes: 0,
      isEdited: false,
    );
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.commentAdded,
      folderId: folderId,
      message: 'Added comment',
      data: comment,
    ));
    
    return comment;
  }
  
  /// Add annotation to article
  Future<ArticleAnnotation> addAnnotation({
    required String folderId,
    required String articleId,
    required String selectedText,
    required String note,
    required AnnotationPosition position,
    AnnotationType type = AnnotationType.highlight,
    String? color,
  }) async {
    // Check permissions
    if (!await _hasPermission(folderId, FolderPermission.annotate)) {
      throw Exception('No permission to annotate');
    }
    
    final annotation = ArticleAnnotation(
      id: const Uuid().v4(),
      articleId: articleId,
      userId: _userId!,
      userName: 'Current User',
      selectedText: selectedText,
      note: note,
      position: position,
      type: type,
      color: color ?? '#FFEB3B',
      createdAt: DateTime.now(),
    );
    
    _sharingController.add(SharingEvent(
      type: SharingEventType.annotationAdded,
      folderId: folderId,
      message: 'Added annotation',
      data: annotation,
    ));
    
    return annotation;
  }
  
  /// Get folder activity feed
  Stream<List<FolderActivity>> getFolderActivity(String folderId) async* {
    // Mock activity feed
    yield [
      FolderActivity(
        id: '1',
        folderId: folderId,
        userId: 'user1',
        userName: 'John Doe',
        action: ActivityAction.addedArticle,
        targetName: 'Interesting Article Title',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      FolderActivity(
        id: '2',
        folderId: folderId,
        userId: 'user2',
        userName: 'Jane Smith',
        action: ActivityAction.commented,
        targetName: 'Another Article',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      FolderActivity(
        id: '3',
        folderId: folderId,
        userId: 'user3',
        userName: 'Bob Johnson',
        action: ActivityAction.joinedFolder,
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
  }
  
  /// Check if user has permission
  Future<bool> _hasPermission(String folderId, FolderPermission permission) async {
    final folder = _sharedFolders[folderId];
    if (folder == null) return false;
    
    final members = _folderMembers[folderId] ?? [];
    final member = members.firstWhere(
      (m) => m.userId == _userId,
      orElse: () => throw Exception('Not a member of this folder'),
    );
    
    // Owner has all permissions
    if (member.role == MemberRole.owner) return true;
    
    // Check role-based permissions
    switch (permission) {
      case FolderPermission.read:
        return true; // All members can read
        
      case FolderPermission.write:
        return member.role == MemberRole.editor ||
               (member.role == MemberRole.contributor && folder.permissions.allowContributorWrite);
               
      case FolderPermission.delete:
        return member.role == MemberRole.editor && folder.permissions.allowEditorDelete;
        
      case FolderPermission.invite:
        return member.role == MemberRole.editor && folder.permissions.allowEditorInvite;
        
      case FolderPermission.manageMember:
        return false; // Only owner
        
      case FolderPermission.comment:
        return folder.permissions.allowComments &&
               (member.role != MemberRole.viewer || folder.permissions.allowViewerComment);
               
      case FolderPermission.annotate:
        return folder.permissions.allowAnnotations &&
               (member.role != MemberRole.viewer || folder.permissions.allowViewerAnnotate);
    }
  }
  
  /// Add member to folder
  Future<void> _addMember({
    required String folderId,
    required String userId,
    required MemberRole role,
  }) async {
    final members = _folderMembers[folderId] ?? [];
    
    // Check if already a member
    if (members.any((m) => m.userId == userId)) {
      return;
    }
    
    members.add(FolderMember(
      userId: userId,
      userName: userId == _userId ? 'You' : 'User $userId',
      email: '$userId@example.com',
      role: role,
      joinedAt: DateTime.now(),
    ));
    
    _folderMembers[folderId] = members;
    
    // Update member count
    final folder = _sharedFolders[folderId];
    if (folder != null) {
      _sharedFolders[folderId] = folder.copyWith(
        memberCount: members.length,
      );
    }
  }
  
  /// Generate invite token
  String _generateInviteToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return 'invite-${base64Url.encode(bytes)}';
  }
  
  /// Get shared folders
  List<SharedFolder> get sharedFolders => _sharedFolders.values.toList();
  
  /// Get folder members
  List<FolderMember> getFolderMembers(String folderId) {
    return _folderMembers[folderId] ?? [];
  }
  
  /// Get sharing events stream
  Stream<SharingEvent> get events => _sharingController.stream;
  
  /// Dispose service
  void dispose() {
    _sharingController.close();
  }
}

/// Shared folder model
class SharedFolder {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String ownerName;
  final List<String> feedIds;
  final SharedFolderPermissions permissions;
  final bool isPublic;
  final EncryptionKey encryptionKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final int articleCount;
  
  SharedFolder({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.ownerName,
    required this.feedIds,
    required this.permissions,
    required this.isPublic,
    required this.encryptionKey,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.articleCount,
  });
  
  SharedFolder copyWith({
    String? ownerId,
    String? ownerName,
    int? memberCount,
    int? articleCount,
  }) {
    return SharedFolder(
      id: id,
      name: name,
      description: description,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      feedIds: feedIds,
      permissions: permissions,
      isPublic: isPublic,
      encryptionKey: encryptionKey,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      memberCount: memberCount ?? this.memberCount,
      articleCount: articleCount ?? this.articleCount,
    );
  }
}

/// Shared folder permissions
class SharedFolderPermissions {
  final bool allowContributorWrite;
  final bool allowEditorDelete;
  final bool allowEditorInvite;
  final bool allowComments;
  final bool allowAnnotations;
  final bool allowViewerComment;
  final bool allowViewerAnnotate;
  final bool allowDownload;
  final bool allowPrint;
  
  const SharedFolderPermissions({
    this.allowContributorWrite = true,
    this.allowEditorDelete = true,
    this.allowEditorInvite = true,
    this.allowComments = true,
    this.allowAnnotations = true,
    this.allowViewerComment = false,
    this.allowViewerAnnotate = false,
    this.allowDownload = true,
    this.allowPrint = true,
  });
}

/// Folder member model
class FolderMember {
  final String userId;
  final String userName;
  final String email;
  final String? avatarUrl;
  final MemberRole role;
  final DateTime joinedAt;
  final DateTime? lastActiveAt;
  
  FolderMember({
    required this.userId,
    required this.userName,
    required this.email,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
    this.lastActiveAt,
  });
  
  FolderMember copyWith({MemberRole? role}) {
    return FolderMember(
      userId: userId,
      userName: userName,
      email: email,
      avatarUrl: avatarUrl,
      role: role ?? this.role,
      joinedAt: joinedAt,
      lastActiveAt: lastActiveAt,
    );
  }
}

/// Member roles
enum MemberRole {
  owner,
  editor,
  contributor,
  viewer,
}

/// Folder permissions
enum FolderPermission {
  read,
  write,
  delete,
  invite,
  manageMember,
  comment,
  annotate,
}

/// Share invite model
class ShareInvite {
  final String id;
  final String folderId;
  final String folderName;
  final String invitedBy;
  final String invitedEmail;
  final MemberRole role;
  final String? message;
  final String token;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  
  ShareInvite({
    required this.id,
    required this.folderId,
    required this.folderName,
    required this.invitedBy,
    required this.invitedEmail,
    required this.role,
    this.message,
    required this.token,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedAt,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isAccepted => acceptedAt != null;
}

/// Article comment model
class ArticleComment {
  final String id;
  final String articleId;
  final String userId;
  final String userName;
  final String content;
  final String? parentId;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int likes;
  final bool isEdited;
  final List<ArticleComment> replies;
  
  ArticleComment({
    required this.id,
    required this.articleId,
    required this.userId,
    required this.userName,
    required this.content,
    this.parentId,
    required this.createdAt,
    this.editedAt,
    required this.likes,
    required this.isEdited,
    this.replies = const [],
  });
}

/// Article annotation model
class ArticleAnnotation {
  final String id;
  final String articleId;
  final String userId;
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
}

/// Annotation position
class AnnotationPosition {
  final int startOffset;
  final int endOffset;
  final String? elementPath;
  
  AnnotationPosition({
    required this.startOffset,
    required this.endOffset,
    this.elementPath,
  });
}

/// Annotation types
enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  note,
}

/// Folder activity model
class FolderActivity {
  final String id;
  final String folderId;
  final String userId;
  final String userName;
  final ActivityAction action;
  final String? targetId;
  final String? targetName;
  final DateTime timestamp;
  
  FolderActivity({
    required this.id,
    required this.folderId,
    required this.userId,
    required this.userName,
    required this.action,
    this.targetId,
    this.targetName,
    required this.timestamp,
  });
}

/// Activity actions
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

/// Sharing event types
enum SharingEventType {
  folderCreated,
  folderDeleted,
  inviteSent,
  inviteAccepted,
  memberJoined,
  memberLeft,
  memberRemoved,
  roleChanged,
  ownershipTransferred,
  commentAdded,
  annotationAdded,
  permissionsChanged,
}

/// Sharing event
class SharingEvent {
  final SharingEventType type;
  final String folderId;
  final String message;
  final dynamic data;
  final DateTime timestamp;
  
  SharingEvent({
    required this.type,
    required this.folderId,
    required this.message,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}