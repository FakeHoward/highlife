/// Supported UI locales. English is the default.
enum AppLocale {
  en('en'),
  ru('ru');

  const AppLocale(this.code);
  final String code;

  static AppLocale fromCode(String? code) {
    final normalized = (code ?? 'en').toLowerCase();
    if (normalized.startsWith('ru')) return AppLocale.ru;
    return AppLocale.en;
  }
}

/// Typed accessors over EN/RU message maps.
class AppStrings {
  AppStrings(this.locale);

  final AppLocale locale;

  String _(String key) {
    final byLocale = _messages[key];
    if (byLocale == null) return key;
    return byLocale[locale] ?? byLocale[AppLocale.en] ?? key;
  }

  /// Map-style lookup used by dialogs and tests.
  String t(String key) => _(key);

  String format(String key, Map<String, String> params) {
    var value = _(key);
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  // Brand / common
  String get appName => _('appName');
  String get startupFailed => _('startupFailed');
  String get cancel => _('cancel');
  String get done => _('done');
  String get open => _('open');
  String get back => _('back');
  String get language => _('language');
  String get languageEnglish => _('languageEnglish');
  String get languageRussian => _('languageRussian');
  String get theme => _('theme');
  String get themeSystem => _('themeSystem');
  String get themeLight => _('themeLight');
  String get themeDark => _('themeDark');
  String get deviceId => _('deviceId');
  String get retry => _('retry');

  // Login
  String get loginTagline => _('loginTagline');
  String get homeserver => _('homeserver');
  String get homeserverHint => _('homeserverHint');
  String get userId => _('userId');
  String get userIdHint => _('userIdHint');
  String get usernameHint => _('usernameHint');
  String get roomAliasHint => _('roomAliasHint');
  String get password => _('password');
  String get showPassword => _('showPassword');
  String get hidePassword => _('hidePassword');
  String get encryptionSection => _('encryptionSection');
  String get encryptionSectionHint => _('encryptionSectionHint');
  String get signIn => _('signIn');
  String get signingIn => _('signingIn');
  String get registerTitle => _('registerTitle');
  String get registerHint => _('registerHint');
  String get username => _('username');
  String get createAccount => _('createAccount');
  String get registering => _('registering');
  String get registerMasHint => _('registerMasHint');
  String get registerMasOpened => _('registerMasOpened');
  String get registerMasOpenFailed => _('registerMasOpenFailed');
  String get createAccountOnServer => _('createAccountOnServer');
  String get loginSessionNote => _('loginSessionNote');
  String get continueWithSso => _('continueWithSso');
  String get ssoPasteTokenHint => _('ssoPasteTokenHint');
  String get ssoLoginToken => _('ssoLoginToken');
  String get ssoCompleteWithToken => _('ssoCompleteWithToken');
  String get ssoUnavailable => _('ssoUnavailable');
  String get ssoOpenFailed => _('ssoOpenFailed');
  String get ssoTokenRequired => _('ssoTokenRequired');
  String get ssoWaitingRedirect => _('ssoWaitingRedirect');
  String get ssoPasteInstead => _('ssoPasteInstead');
  String get pushDistributor => _('pushDistributor');
  String get pushDistributorHint => _('pushDistributorHint');
  String get displayName => _('displayName');
  String get changeAvatar => _('changeAvatar');
  String get authForbidden => _('auth.forbidden');
  String get authUserInUse => _('auth.userInUse');
  String get authInvalidUsername => _('auth.invalidUsername');
  String get authWeakPassword => _('auth.weakPassword');
  String get authPasswordLoginUnsupported => _('auth.passwordLoginUnsupported');
  String get authUiaUnsupported => _('auth.uiaUnsupported');
  String get authRegisterIncomplete => _('auth.registerIncomplete');
  String get authUsernameRequired => _('auth.usernameRequired');
  String get authHomeserverRequired => _('auth.homeserverRequired');
  String get authUserRequired => _('auth.userRequired');
  String get authPasswordRequired => _('auth.passwordRequired');
  String get authPasswordTooShort => _('auth.passwordTooShort');
  String get authLogoutFailed => _('auth.logoutFailed');
  String get authLoginFailed => _('auth.loginFailed');
  String get authRegisterFailed => _('auth.registerFailed');
  String get authNetwork => _('auth.network');

  String authError(String? key) {
    return switch (key) {
      'auth.forbidden' => authForbidden,
      'auth.userInUse' => authUserInUse,
      'auth.invalidUsername' => authInvalidUsername,
      'auth.weakPassword' => authWeakPassword,
      'auth.passwordLoginUnsupported' => authPasswordLoginUnsupported,
      'auth.uiaUnsupported' => authUiaUnsupported,
      'auth.registerIncomplete' => authRegisterIncomplete,
      'auth.usernameRequired' => authUsernameRequired,
      'auth.homeserverRequired' => authHomeserverRequired,
      'auth.userRequired' => authUserRequired,
      'auth.passwordRequired' => authPasswordRequired,
      'auth.passwordTooShort' => authPasswordTooShort,
      'auth.logoutFailed' => authLogoutFailed,
      'auth.loginFailed' => authLoginFailed,
      'auth.registerFailed' => authRegisterFailed,
      'auth.network' => authNetwork,
      null => '',
      _ => key,
    };
  }
  String get editDisplayName => _('editDisplayName');
  String get about => _('about');
  String get editAbout => _('editAbout');
  String get muteThread => _('muteThread');
  String get save => _('save');
  String get confirmLeaveRoom => _('confirmLeaveRoom');
  String get miniAppEmbedUnsupported => _('miniAppEmbedUnsupported');
  String get couldNotOpenMiniApp => _('couldNotOpenMiniApp');
  String get appVersion => _('appVersion');
  String get checkForUpdates => _('checkForUpdates');
  String get checkingUpdates => _('checkingUpdates');
  String get upToDate => _('upToDate');
  String get updateAvailable => _('updateAvailable');
  String get downloadUpdate => _('downloadUpdate');
  String get updateLater => _('updateLater');
  String get updateCheckFailed => _('updateCheckFailed');

  // Room list / search
  String get roomActions => _('roomActions');
  String get newRoom => _('newRoom');
  String get joinRoom => _('joinRoom');
  String get settings => _('settings');
  String get profile => _('profile');
  String get copied => _('copied');
  String get searchConversations => _('searchConversations');
  String get searchMessages => _('searchMessages');
  String get searchHint => _('searchHint');
  String get searchAction => _('searchAction');
  String get searchEmpty => _('searchEmpty');
  String get searchFailed => _('searchFailed');
  String get roomName => _('roomName');
  String get optionalRoomAlias => _('optionalRoomAlias');
  String get roomIdOrAlias => _('roomIdOrAlias');
  String get create => _('create');
  String get join => _('join');
  String get noMessagesYet => _('noMessagesYet');
  String get noConversations => _('noConversations');
  String get noConversationsTitle => _('noConversationsTitle');
  String get selectConversation => _('selectConversation');
  String get selectConversationHint => _('selectConversationHint');
  String get joinServerBanned => _('joinServerBanned');
  String get joinFailed => _('joinFailed');
  String get roomActionFailed => _('roomActionFailed');
  String get invites => _('invites');
  String get invitation => _('invitation');
  String get accept => _('accept');
  String get today => _('today');
  String get yesterday => _('yesterday');
  String get decline => _('decline');
  String get enableEncryption => _('enableEncryption');
  String get startDirectMessage => _('startDirectMessage');
  String get startDmAction => _('startDmAction');
  String get spaces => _('spaces');
  String get allChats => _('allChats');
  String get noRoomsInSpace => _('noRoomsInSpace');
  String get createSpace => _('createSpace');
  String get spaceName => _('spaceName');
  String get spacesFolderHint => _('spacesFolderHint');
  String get folderSection => _('folderSection');
  String get folderHint => _('folderHint');
  String get addToFolder => _('addToFolder');
  String get addToSpacePlaceholder => _('addToSpacePlaceholder');
  String get noSpacesYet => _('noSpacesYet');
  String get addToSpaceDone => _('addToSpaceDone');

  // Settings / crypto / calls
  String get encryptionAvailable => _('encryptionAvailable');
  String get webEncryptionUnavailable => _('webEncryptionUnavailable');
  String get webEncryptionHint => _('webEncryptionHint');
  String get cryptoUnavailableBanner => _('cryptoUnavailableBanner');
  String cryptoInitErrorDetail(String detail) =>
      _('cryptoInitErrorDetail').replaceAll('{detail}', detail);
  String get elementCallConfigured => _('elementCallConfigured');
  String get matrixRtcUnavailable => _('matrixRtcUnavailable');
  String get callsNeedUrl => _('callsNeedUrl');
  String get signOut => _('signOut');
  String get startCall => _('startCall');
  String get startVideoCall => _('startVideoCall');
  String get callsUnavailable => _('callsUnavailable');
  String get callNeedsUrl => _('callNeedsUrl');
  String get couldNotOpenCall => _('couldNotOpenCall');
  String get callIncoming => _('callIncoming');
  String get callConnecting => _('callConnecting');
  String get callConnected => _('callConnected');
  String get callEnded => _('callEnded');
  String get callFailed => _('callFailed');
  String get callUnknownPeer => _('callUnknownPeer');
  String get callAnswer => _('callAnswer');
  String get callReject => _('callReject');
  String get callMute => _('callMute');
  String get callUnmute => _('callUnmute');
  String get callHangup => _('callHangup');
  String get callCameraOn => _('callCameraOn');
  String get callCameraOff => _('callCameraOff');
  String get callFallback => _('callFallback');
  String get callParticipants => _('callParticipants');
  String get devicesVerification => _('devicesVerification');
  String get keyBackup => _('keyBackup');
  String get devicesTitle => _('devicesTitle');
  String get noDevices => _('noDevices');
  String get verify => _('verify');
  String get thisDevice => _('thisDevice');
  String get signOutDevice => _('signOutDevice');
  String get passwordToConfirm => _('passwordToConfirm');
  String get incomingVerification => _('incomingVerification');
  String get cryptoAccept => _('cryptoAccept');
  String get cryptoReject => _('cryptoReject');
  String get confirmSas => _('confirmSas');
  String get theyMatch => _('theyMatch');
  String get noMatch => _('noMatch');
  String get cryptoWaiting => _('cryptoWaiting');
  String get cryptoDone => _('cryptoDone');
  String get cryptoError => _('cryptoError');
  String get chooseSas => _('chooseSas');
  String get backupUnavailable => _('backupUnavailable');
  String get backupInit => _('backupInit');
  String get backupRestore => _('backupRestore');
  String get recoveryKey => _('recoveryKey');
  String get recoveryCreated => _('recoveryCreated');
  String get identityConnected => _('identityConnected');
  String get identityInitialized => _('identityInitialized');
  String get identityMissing => _('identityMissing');
  String get copy => _('copy');

  // Chat / invites / members
  String get inviteMember => _('inviteMember');
  String get members => _('members');
  String get roomDetails => _('roomDetails');
  String get roomIdLabel => _('roomIdLabel');
  String get roomAliasLabel => _('roomAliasLabel');
  String get editRoomAlias => _('editRoomAlias');
  String get roomAvatar => _('roomAvatar');
  String get encryptionLabel => _('encryptionLabel');
  String get encryptionOn => _('encryptionOn');
  String get encryptionOff => _('encryptionOff');
  String get noMembersYet => _('noMembersYet');
  String powerLevel(int level) =>
      _('powerLevel').replaceAll('{level}', '$level');
  String get invitePlaceholder => _('invitePlaceholder');
  String get invitationSent => _('invitationSent');
  String get topic => _('topic');
  String get kick => _('kick');
  String confirmKick(String name) =>
      _('confirmKick').replaceAll('{name}', name);
  String get leaveRoom => _('leaveRoom');
  String miniAppAvailable(String title) =>
      _('miniAppAvailable').replaceAll('{title}', title);
  String get loadEarlierMessages => _('loadEarlierMessages');
  String get editingMessage => _('editingMessage');
  String replyingTo(String userId) =>
      _('replyingTo').replaceAll('{user}', userId);
  String get typing => _('typing');
  String typingUsers(String users) =>
      _('typingUsers').replaceAll('{users}', users);
  String get attachFile => _('attachFile');
  String get messageHint => _('messageHint');
  String get sendMessage => _('sendMessage');
  String get matrixUserId => _('matrixUserId');
  String get invite => _('invite');
  String get reply => _('reply');
  String get react => _('react');
  String get edit => _('edit');
  String get delete => _('delete');
  String get openMedia => _('openMedia');
  String get muteNotifications => _('muteNotifications');
  String get unmuteNotifications => _('unmuteNotifications');
  String get pinMessage => _('pinMessage');
  String get unpinMessage => _('unpinMessage');
  String get forwardMessage => _('forwardMessage');
  String get unreadMessages => _('unreadMessages');
  String get userProfile => _('userProfile');
  String get ignoreUser => _('ignoreUser');
  String get unignoreUser => _('unignoreUser');
  String lastSeen(String when) => _('lastSeen').replaceAll('{when}', when);
  String get userOffline => _('userOffline');
  String get userOnline => _('userOnline');
  String get userAway => _('userAway');
  String get pinned => _('pinned');
  String get mutedRoom => _('mutedRoom');
  String get sharedMedia => _('sharedMedia');
  String get noSharedMedia => _('noSharedMedia');
  String get copyMxid => _('copyMxid');
  String get copyMessage => _('copyMessage');
  String get confirmDelete => _('confirmDelete');
  String get verifyUser => _('verifyUser');
  String get allDevicesVerified => _('allDevicesVerified');
  String get recordVoice => _('recordVoice');
  String get stopRecording => _('stopRecording');
  String get recordingVoice => _('recordingVoice');
  String get retrySend => _('retrySend');
  String get encryptedMessage => _('encryptedMessage');

  String get thread => _('thread');
  String threadCount(int count) =>
      _('threadCount').replaceAll('{count}', '$count');
  String get shareLocation => _('shareLocation');
  String get stickers => _('stickers');
  String get noStickers => _('noStickers');
  String get knock => _('knock');
  String get knockSent => _('knockSent');
  String get approveKnock => _('approveKnock');
  String get denyKnock => _('denyKnock');
  String get pendingKnocks => _('pendingKnocks');
  String get noKnocks => _('noKnocks');
  String get roomPreview => _('roomPreview');
  String get linkNewDevice => _('linkNewDevice');
  String get signInQr => _('signInQr');
  String get qrLoginHint => _('qrLoginHint');
  String get qrLoginUnsupported => _('qrLoginUnsupported');
  String get linkNewDeviceHint => _('linkNewDeviceHint');
  String get callMicBlocked => _('callMicBlocked');
  String get callCryptoUnavailable => _('callCryptoUnavailable');
  String callFailed(String detail) => _('callFailed').replaceAll('{detail}', detail);
  String get openMap => _('openMap');
  String get prompts => _('prompts');
  String get latitude => _('latitude');
  String get longitude => _('longitude');
  String get sendLocation => _('sendLocation');
  String get locationHint => _('locationHint');
  String get geoUri => _('geoUri');
  String memberCount(int count) =>
      _('memberCount').replaceAll('{count}', '$count');
  String get declinedCall => _('declinedCall');
  String get miniApp => _('miniApp');
  String get edited => _('edited');
  String get attachment => _('attachment');
  String get roomUpdate => _('roomUpdate');

  // Calls surface
  String get callTitle => _('callTitle');
  String get leaveCall => _('leaveCall');
  String get openExternally => _('openExternally');
  String get embedUnsupported => _('embedUnsupported');
  String get widgetReady => _('widgetReady');
  String get callBannerActive => _('callBannerActive');
  String get joinCall => _('joinCall');

  // Polls
  String get createPoll => _('createPoll');
  String get pollQuestion => _('pollQuestion');
  String pollOption(int n) => _('pollOption').replaceAll('{n}', '$n');
  String get addPollOption => _('addPollOption');
  String get pollAllowMultiple => _('pollAllowMultiple');
  String get pollEnded => _('pollEnded');
  String get endPoll => _('endPoll');
  String pollSelectUpTo(int n) =>
      _('pollSelectUpTo').replaceAll('{n}', '$n');
  String pollVoters(int n) => _('pollVoters').replaceAll('{n}', '$n');

  // Sync
  String get syncWaiting => _('syncWaiting');
  String get syncSyncing => _('syncSyncing');
  String get syncError => _('syncError');
  String syncErrorDetail(String error) =>
      _('syncErrorDetail').replaceAll('{error}', error);

  // Errors / status
  String get blockedUnsafeUrl => _('blockedUnsafeUrl');
  String get sending => _('sending');
  String get sent => _('sent');
  String get failed => _('failed');

  String callbackFeedback(String? key) {
    return switch (key) {
      'sending' => sending,
      'sent' => sent,
      'failed' => failed,
      null => '',
      _ => key,
    };
  }

  /// Keys present in the message table (for unit tests).
  static Iterable<String> get keys => _messages.keys;

  static bool hasKeyInBoth(String key) {
    final entry = _messages[key];
    if (entry == null) return false;
    return entry.containsKey(AppLocale.en) && entry.containsKey(AppLocale.ru);
  }
}

/// Alias kept for call-sites that prefer the HighLifeStrings name.
typedef HighLifeStrings = AppStrings;

const Map<String, Map<AppLocale, String>> _messages = {
  'appName': {AppLocale.en: 'HighLife', AppLocale.ru: 'HighLife'},
  'startupFailed': {
    AppLocale.en: 'HighLife failed to start',
    AppLocale.ru: 'HighLife не удалось запустить',
  },
  'cancel': {AppLocale.en: 'Cancel', AppLocale.ru: 'Отмена'},
  'done': {AppLocale.en: 'Done', AppLocale.ru: 'Готово'},
  'open': {AppLocale.en: 'Open', AppLocale.ru: 'Открыть'},
  'back': {AppLocale.en: 'Back', AppLocale.ru: 'Назад'},
  'language': {AppLocale.en: 'Language', AppLocale.ru: 'Язык'},
  'languageEnglish': {AppLocale.en: 'English', AppLocale.ru: 'English'},
  'languageRussian': {AppLocale.en: 'Русский', AppLocale.ru: 'Русский'},
  'theme': {AppLocale.en: 'Theme', AppLocale.ru: 'Тема'},
  'themeSystem': {AppLocale.en: 'System', AppLocale.ru: 'Системная'},
  'themeLight': {AppLocale.en: 'Light', AppLocale.ru: 'Светлая'},
  'themeDark': {AppLocale.en: 'Dark', AppLocale.ru: 'Тёмная'},
  'deviceId': {AppLocale.en: 'Device ID', AppLocale.ru: 'ID устройства'},
  'retry': {AppLocale.en: 'Retry', AppLocale.ru: 'Повторить'},
  'loginTagline': {
    AppLocale.en: 'Sign in to any Matrix server.',
    AppLocale.ru: 'Войдите на любой сервер Matrix.',
  },
  'homeserver': {AppLocale.en: 'Homeserver', AppLocale.ru: 'Сервер'},
  'homeserverHint': {
    AppLocale.en: 'https://matrix.example.org',
    AppLocale.ru: 'https://matrix.example.org',
  },
  'userIdHint': {
    AppLocale.en: '@name:matrix.example.org',
    AppLocale.ru: '@name:matrix.example.org',
  },
  'usernameHint': {
    AppLocale.en: 'alice',
    AppLocale.ru: 'alice',
  },
  'roomAliasHint': {
    AppLocale.en: '#alias:server',
    AppLocale.ru: '#alias:server',
  },
  'userId': {AppLocale.en: 'User ID', AppLocale.ru: 'Идентификатор'},
  'password': {AppLocale.en: 'Password', AppLocale.ru: 'Пароль'},
  'showPassword': {
    AppLocale.en: 'Show password',
    AppLocale.ru: 'Показать пароль',
  },
  'hidePassword': {
    AppLocale.en: 'Hide password',
    AppLocale.ru: 'Скрыть пароль',
  },
  'encryptionSection': {
    AppLocale.en: 'Encryption',
    AppLocale.ru: 'Шифрование',
  },
  'encryptionSectionHint': {
    AppLocale.en: 'Devices, verification, and key backup',
    AppLocale.ru: 'Устройства, проверка и резерв ключей',
  },
  'signIn': {AppLocale.en: 'Sign in', AppLocale.ru: 'Войти'},
  'signingIn': {AppLocale.en: 'Signing in…', AppLocale.ru: 'Вход…'},
  'registerTitle': {
    AppLocale.en: 'Create account',
    AppLocale.ru: 'Регистрация',
  },
  'registerHint': {
    AppLocale.en:
        'Open registration only (no email/captcha). Many public servers need Sign in instead.',
    AppLocale.ru:
        'Только открытая регистрация (без email/captcha). На многих серверах нужен обычный вход.',
  },
  'username': {AppLocale.en: 'Username', AppLocale.ru: 'Имя пользователя'},
  'createAccount': {
    AppLocale.en: 'Create account',
    AppLocale.ru: 'Создать аккаунт',
  },
  'registering': {
    AppLocale.en: 'Creating account…',
    AppLocale.ru: 'Создание аккаунта…',
  },
  'registerMasHint': {
    AppLocale.en:
        'This server creates accounts in Matrix Authentication Service. Finish signup in the next screen, then sign in here with the same username and password.',
    AppLocale.ru:
        'Этот сервер создаёт аккаунты через Matrix Authentication Service. Завершите регистрацию на следующем экране, затем войдите здесь тем же именем и паролем.',
  },
  'registerMasOpened': {
    AppLocale.en:
        'If the account is ready, sign in here with the same username and password.',
    AppLocale.ru:
        'Если аккаунт уже создан, войдите здесь тем же именем и паролем.',
  },
  'yesterday': {AppLocale.en: 'Yesterday', AppLocale.ru: 'Вчера'},
  'registerMasOpenFailed': {
    AppLocale.en: 'Could not open the registration page. Try again or paste the auth server URL in a browser.',
    AppLocale.ru:
        'Не удалось открыть страницу регистрации. Попробуйте снова или откройте адрес auth-сервера в браузере.',
  },
  'createAccountOnServer': {
    AppLocale.en: 'Create account on server',
    AppLocale.ru: 'Создать аккаунт на сервере',
  },
  'loginSessionNote': {
    AppLocale.en:
        'Session stays on this device. Rooms that block this server need an account on another one.',
    AppLocale.ru:
        'Сессия на этом устройстве. Если комната блокирует этот сервер — войдите с другого.',
  },
  'continueWithSso': {
    AppLocale.en: 'Continue with SSO',
    AppLocale.ru: 'Войти через SSO',
  },
  'ssoPasteTokenHint': {
    AppLocale.en:
        'After signing in with SSO, paste the loginToken from the redirect URL (highlife://login?loginToken=…).',
    AppLocale.ru:
        'После входа через SSO вставьте loginToken из URL перенаправления (highlife://login?loginToken=…).',
  },
  'ssoLoginToken': {
    AppLocale.en: 'SSO login token',
    AppLocale.ru: 'Токен входа SSO',
  },
  'ssoCompleteWithToken': {
    AppLocale.en: 'Complete SSO sign-in',
    AppLocale.ru: 'Завершить вход SSO',
  },
  'ssoUnavailable': {
    AppLocale.en: 'This homeserver does not offer SSO login.',
    AppLocale.ru: 'Этот homeserver не предлагает вход через SSO.',
  },
  'ssoOpenFailed': {
    AppLocale.en: 'Could not open the SSO page in a browser.',
    AppLocale.ru: 'Не удалось открыть страницу SSO в браузере.',
  },
  'ssoTokenRequired': {
    AppLocale.en: 'Paste the loginToken from the SSO redirect.',
    AppLocale.ru: 'Вставьте loginToken из перенаправления SSO.',
  },
  'ssoWaitingRedirect': {
    AppLocale.en:
        'Finish signing in in the browser. HighLife continues when the server sends you back.',
    AppLocale.ru:
        'Завершите вход в браузере. HighLife продолжит, когда сервер вернёт вас в приложение.',
  },
  'ssoPasteInstead': {
    AppLocale.en: 'Paste token instead',
    AppLocale.ru: 'Вставить токен вручную',
  },
  'pushDistributor': {
    AppLocale.en: 'Notification delivery',
    AppLocale.ru: 'Доставка уведомлений',
  },
  'pushDistributorHint': {
    AppLocale.en: 'Choose which UnifiedPush app delivers notifications.',
    AppLocale.ru: 'Выберите приложение UnifiedPush для уведомлений.',
  },
  'auth.forbidden': {
    AppLocale.en: 'Incorrect username or password.',
    AppLocale.ru: 'Неверное имя пользователя или пароль.',
  },
  'auth.userInUse': {
    AppLocale.en: 'That username is already taken.',
    AppLocale.ru: 'Это имя пользователя уже занято.',
  },
  'auth.invalidUsername': {
    AppLocale.en: 'That username is not valid on this homeserver.',
    AppLocale.ru: 'Такое имя недопустимо на этом сервере.',
  },
  'auth.weakPassword': {
    AppLocale.en: 'Password is too weak. Use at least 8 characters.',
    AppLocale.ru: 'Пароль слишком слабый. Используйте не менее 8 символов.',
  },
  'auth.passwordLoginUnsupported': {
    AppLocale.en: 'This homeserver does not support password login.',
    AppLocale.ru: 'Этот сервер не поддерживает вход по паролю.',
  },
  'auth.uiaUnsupported': {
    AppLocale.en:
        'This homeserver needs extra verification (email, captcha, or SSO). HighLife currently supports open registration with dummy auth only.',
    AppLocale.ru:
        'Серверу нужна дополнительная проверка (email, captcha или SSO). HighLife сейчас поддерживает только открытую регистрацию с dummy auth.',
  },
  'auth.registerIncomplete': {
    AppLocale.en: 'Registration finished without a usable session. Try signing in.',
    AppLocale.ru: 'Регистрация завершилась без сессии. Попробуйте войти.',
  },
  'auth.usernameRequired': {
    AppLocale.en: 'Username is required.',
    AppLocale.ru: 'Укажите имя пользователя.',
  },
  'auth.homeserverRequired': {
    AppLocale.en: 'Homeserver is required.',
    AppLocale.ru: 'Укажите homeserver.',
  },
  'auth.userRequired': {
    AppLocale.en: 'Matrix ID is required.',
    AppLocale.ru: 'Укажите Matrix ID.',
  },
  'auth.passwordRequired': {
    AppLocale.en: 'Password is required.',
    AppLocale.ru: 'Укажите пароль.',
  },
  'auth.passwordTooShort': {
    AppLocale.en: 'Password must be at least 8 characters.',
    AppLocale.ru: 'Пароль должен быть не короче 8 символов.',
  },
  'auth.logoutFailed': {
    AppLocale.en: 'Signed out locally, but the server logout request failed.',
    AppLocale.ru: 'Локальный выход выполнен, но сервер не подтвердил logout.',
  },
  'auth.loginFailed': {
    AppLocale.en: 'Could not sign in. Check the homeserver and try again.',
    AppLocale.ru: 'Не удалось войти. Проверьте homeserver и попробуйте снова.',
  },
  'auth.registerFailed': {
    AppLocale.en: 'Could not create the account. Try another username.',
    AppLocale.ru: 'Не удалось создать аккаунт. Попробуйте другое имя.',
  },
  'auth.network': {
    AppLocale.en: 'Network error. Check your connection and homeserver URL.',
    AppLocale.ru: 'Ошибка сети. Проверьте соединение и URL homeserver.',
  },
  'displayName': {AppLocale.en: 'Display name', AppLocale.ru: 'Отображаемое имя'},
  'editDisplayName': {
    AppLocale.en: 'Edit display name',
    AppLocale.ru: 'Изменить имя',
  },
  'about': {AppLocale.en: 'About', AppLocale.ru: 'О себе'},
  'editAbout': {AppLocale.en: 'Edit about', AppLocale.ru: 'Изменить «о себе»'},
  'muteThread': {AppLocale.en: 'Mute thread', AppLocale.ru: 'Выключить тред'},
  'save': {AppLocale.en: 'Save', AppLocale.ru: 'Сохранить'},
  'confirmLeaveRoom': {
    AppLocale.en: 'Leave this room? You can rejoin later if invited again.',
    AppLocale.ru:
        'Покинуть комнату? Вернуться можно будет по новому приглашению.',
  },
  'miniAppEmbedUnsupported': {
    AppLocale.en:
        'In-app MiniApp is unavailable here. You can open it externally.',
    AppLocale.ru:
        'Встроенное мини-приложение здесь недоступно. Можно открыть снаружи.',
  },
  'couldNotOpenMiniApp': {
    AppLocale.en: 'Could not open MiniApp',
    AppLocale.ru: 'Не удалось открыть мини-приложение',
  },
  'appVersion': {
    AppLocale.en: 'Version {version} (build {build})',
    AppLocale.ru: 'Версия {version} (сборка {build})',
  },
  'checkForUpdates': {
    AppLocale.en: 'Check for updates',
    AppLocale.ru: 'Проверить обновления',
  },
  'checkingUpdates': {
    AppLocale.en: 'Checking for updates…',
    AppLocale.ru: 'Проверка обновлений…',
  },
  'upToDate': {
    AppLocale.en: 'You’re up to date',
    AppLocale.ru: 'У вас актуальная версия',
  },
  'updateAvailable': {
    AppLocale.en: 'Update available: {version}',
    AppLocale.ru: 'Доступно обновление: {version}',
  },
  'downloadUpdate': {AppLocale.en: 'Download', AppLocale.ru: 'Скачать'},
  'updateLater': {AppLocale.en: 'Later', AppLocale.ru: 'Позже'},
  'updateCheckFailed': {
    AppLocale.en: 'Could not check for updates',
    AppLocale.ru: 'Не удалось проверить обновления',
  },
  'roomActions': {
    AppLocale.en: 'Room actions',
    AppLocale.ru: 'Действия с комнатами',
  },
  'newRoom': {AppLocale.en: 'New room', AppLocale.ru: 'Новая комната'},
  'joinRoom': {AppLocale.en: 'Join room', AppLocale.ru: 'Присоединиться'},
  'settings': {AppLocale.en: 'Settings', AppLocale.ru: 'Настройки'},
  'profile': {AppLocale.en: 'Profile', AppLocale.ru: 'Профиль'},
  'copied': {AppLocale.en: 'Copied', AppLocale.ru: 'Скопировано'},
  'searchConversations': {
    AppLocale.en: 'Search conversations',
    AppLocale.ru: 'Поиск бесед',
  },
  'searchMessages': {
    AppLocale.en: 'Search messages',
    AppLocale.ru: 'Поиск сообщений',
  },
  'searchHint': {AppLocale.en: 'Search term', AppLocale.ru: 'Строка поиска'},
  'searchAction': {AppLocale.en: 'Search', AppLocale.ru: 'Искать'},
  'searchEmpty': {AppLocale.en: 'No results', AppLocale.ru: 'Ничего не найдено'},
  'searchFailed': {AppLocale.en: 'Search failed', AppLocale.ru: 'Ошибка поиска'},
  'roomName': {AppLocale.en: 'Room name', AppLocale.ru: 'Название комнаты'},
  'roomIdOrAlias': {
    AppLocale.en: 'Room ID or alias',
    AppLocale.ru: 'ID или псевдоним комнаты',
  },
  'create': {AppLocale.en: 'Create', AppLocale.ru: 'Создать'},
  'join': {AppLocale.en: 'Join', AppLocale.ru: 'Присоединиться'},
  'noMessagesYet': {
    AppLocale.en: 'No messages yet',
    AppLocale.ru: 'Сообщений пока нет',
  },
  'noConversations': {
    AppLocale.en: 'Join with #alias:server or create a room.',
    AppLocale.ru: 'Вступите по #alias:server или создайте комнату.',
  },
  'noConversationsTitle': {
    AppLocale.en: 'No conversations yet',
    AppLocale.ru: 'Пока нет переписок',
  },
  'selectConversation': {
    AppLocale.en: 'Select a conversation',
    AppLocale.ru: 'Выберите беседу',
  },
  'selectConversationHint': {
    AppLocale.en: 'Choose a conversation or join a room.',
    AppLocale.ru: 'Выберите беседу или вступите в комнату.',
  },
  'joinServerBanned': {
    AppLocale.en:
        'Your server is blocked from this room by that room’s rules. Sign in on another server (for example matrix.org) to join.',
    AppLocale.ru:
        'Ваш сервер заблокирован в этой комнате её правилами. Чтобы вступить, войдите с другого сервера (например matrix.org).',
  },
  'joinFailed': {
    AppLocale.en: 'Could not join room',
    AppLocale.ru: 'Не удалось вступить в комнату',
  },
  'roomActionFailed': {
    AppLocale.en: 'Room action failed',
    AppLocale.ru: 'Действие с комнатой не удалось',
  },
  'invites': {AppLocale.en: 'Invites', AppLocale.ru: 'Приглашения'},
  'invitation': {
    AppLocale.en: 'Invitation',
    AppLocale.ru: 'Приглашение',
  },
  'accept': {AppLocale.en: 'Accept', AppLocale.ru: 'Принять'},
  'today': {AppLocale.en: 'Today', AppLocale.ru: 'Сегодня'},
  'decline': {AppLocale.en: 'Decline', AppLocale.ru: 'Отклонить'},
  'enableEncryption': {
    AppLocale.en: 'Enable encryption',
    AppLocale.ru: 'Включить шифрование',
  },
  'startDirectMessage': {
    AppLocale.en: 'Start direct message',
    AppLocale.ru: 'Начать личный чат',
  },
  'startDmAction': {
    AppLocale.en: 'Start chat',
    AppLocale.ru: 'Начать чат',
  },
  'spaces': {AppLocale.en: 'Spaces', AppLocale.ru: 'Пространства'},
  'allChats': {AppLocale.en: 'All', AppLocale.ru: 'Все'},
  'noRoomsInSpace': {
    AppLocale.en: 'No joined rooms in this space yet',
    AppLocale.ru: 'В этом пространстве пока нет комнат',
  },
  'createSpace': {
    AppLocale.en: 'New space',
    AppLocale.ru: 'Новое пространство',
  },
  'spaceName': {
    AppLocale.en: 'Space name',
    AppLocale.ru: 'Название пространства',
  },
  'spacesFolderHint': {
    AppLocale.en: 'Like Telegram folders — create a space, then add chats to it.',
    AppLocale.ru: 'Как папки в Telegram: создайте пространство и добавьте чаты.',
  },
  'folderSection': {
    AppLocale.en: 'Folder (space)',
    AppLocale.ru: 'Папка (пространство)',
  },
  'folderHint': {
    AppLocale.en: 'Spaces work like chat folders: put this room in one to filter the list.',
    AppLocale.ru: 'Пространства как папки чатов: добавьте комнату, чтобы фильтровать список.',
  },
  'addToFolder': {
    AppLocale.en: 'Add to folder',
    AppLocale.ru: 'В папку',
  },
  'addToSpacePlaceholder': {
    AppLocale.en: 'Choose a space',
    AppLocale.ru: 'Выберите пространство',
  },
  'noSpacesYet': {
    AppLocale.en: 'Create a space from the folder button first',
    AppLocale.ru: 'Сначала создайте пространство кнопкой с папкой',
  },
  'addToSpaceDone': {
    AppLocale.en: 'Added to space',
    AppLocale.ru: 'Добавлено в пространство',
  },
  'encryptionAvailable': {
    AppLocale.en: 'Encryption available',
    AppLocale.ru: 'Шифрование доступно',
  },
  'webEncryptionUnavailable': {
    AppLocale.en: 'Encryption unavailable',
    AppLocale.ru: 'Шифрование недоступно',
  },
  'webEncryptionHint': {
    AppLocale.en:
        'Crypto backend failed to initialize. Encrypted messages will not decrypt until vodozemac is available.',
    AppLocale.ru:
        'Не удалось инициализировать crypto. Зашифрованные сообщения не будут расшифрованы, пока недоступен vodozemac.',
  },
  'cryptoUnavailableBanner': {
    AppLocale.en: 'End-to-end encryption is unavailable on this device',
    AppLocale.ru: 'Сквозное шифрование на этом устройстве недоступно',
  },
  'cryptoInitErrorDetail': {
    AppLocale.en: 'Crypto init failed: {detail}',
    AppLocale.ru: 'Ошибка инициализации crypto: {detail}',
  },
  'elementCallConfigured': {
    AppLocale.en: 'Element Call configured',
    AppLocale.ru: 'Element Call настроен',
  },
  'matrixRtcUnavailable': {
    AppLocale.en: 'MatrixRTC unavailable',
    AppLocale.ru: 'MatrixRTC недоступен',
  },
  'callsNeedUrl': {
    AppLocale.en: 'Calls need HIGHLIFE_ELEMENT_CALL_URL in this build.',
    AppLocale.ru: 'Для звонков нужен HIGHLIFE_ELEMENT_CALL_URL в этой сборке.',
  },
  'signOut': {AppLocale.en: 'Sign out', AppLocale.ru: 'Выйти'},
  'startCall': {AppLocale.en: 'Start call', AppLocale.ru: 'Начать звонок'},
  'startVideoCall': {
    AppLocale.en: 'Video call',
    AppLocale.ru: 'Видеозвонок',
  },
  'callsUnavailable': {
    AppLocale.en: 'Calls unavailable',
    AppLocale.ru: 'Звонки недоступны',
  },
  'callNeedsUrl': {
    AppLocale.en:
        'MatrixRTC needs a trusted Element Call URL in this build.',
    AppLocale.ru:
        'Для MatrixRTC нужен доверенный URL Element Call в этой сборке.',
  },
  'couldNotOpenCall': {
    AppLocale.en: 'Could not open Element Call',
    AppLocale.ru: 'Не удалось открыть Element Call',
  },
  'callIncoming': {
    AppLocale.en: 'Incoming call',
    AppLocale.ru: 'Входящий звонок',
  },
  'callConnecting': {
    AppLocale.en: 'Connecting',
    AppLocale.ru: 'Подключение',
  },
  'callConnected': {
    AppLocale.en: 'Connected',
    AppLocale.ru: 'Соединение установлено',
  },
  'callEnded': {
    AppLocale.en: 'Call ended',
    AppLocale.ru: 'Звонок завершён',
  },
  'callFailed': {
    AppLocale.en: 'Call failed',
    AppLocale.ru: 'Ошибка звонка',
  },
  'callUnknownPeer': {
    AppLocale.en: 'Matrix call',
    AppLocale.ru: 'Matrix-звонок',
  },
  'callAnswer': {AppLocale.en: 'Answer', AppLocale.ru: 'Ответить'},
  'callReject': {AppLocale.en: 'Reject', AppLocale.ru: 'Отклонить'},
  'callMute': {
    AppLocale.en: 'Mute',
    AppLocale.ru: 'Выключить микрофон',
  },
  'callUnmute': {
    AppLocale.en: 'Unmute',
    AppLocale.ru: 'Включить микрофон',
  },
  'callHangup': {
    AppLocale.en: 'Hang up',
    AppLocale.ru: 'Завершить',
  },
  'callCameraOn': {AppLocale.en: 'Camera', AppLocale.ru: 'Камера'},
  'callCameraOff': {
    AppLocale.en: 'Camera off',
    AppLocale.ru: 'Камера выкл.',
  },
  'callFallback': {
    AppLocale.en: 'Use Element Call',
    AppLocale.ru: 'Открыть Element Call',
  },
  'callParticipants': {
    AppLocale.en: '{count} in call',
    AppLocale.ru: 'В звонке: {count}',
  },
  'devicesVerification': {
    AppLocale.en: 'Devices & verification',
    AppLocale.ru: 'Устройства и проверка',
  },
  'keyBackup': {
    AppLocale.en: 'Key backup / recovery',
    AppLocale.ru: 'Резерв ключей / восстановление',
  },
  'devicesTitle': {
    AppLocale.en: 'Your devices',
    AppLocale.ru: 'Ваши устройства',
  },
  'noDevices': {
    AppLocale.en: 'No other devices found yet.',
    AppLocale.ru: 'Другие устройства пока не найдены.',
  },
  'verify': {AppLocale.en: 'Verify', AppLocale.ru: 'Проверить'},
  'thisDevice': {AppLocale.en: 'This device', AppLocale.ru: 'Это устройство'},
  'signOutDevice': {
    AppLocale.en: 'End session',
    AppLocale.ru: 'Завершить сессию',
  },
  'passwordToConfirm': {AppLocale.en: 'Password', AppLocale.ru: 'Пароль'},
  'incomingVerification': {
    AppLocale.en: 'Incoming verification',
    AppLocale.ru: 'Входящая проверка',
  },
  'cryptoAccept': {AppLocale.en: 'Accept', AppLocale.ru: 'Принять'},
  'cryptoReject': {AppLocale.en: 'Reject', AppLocale.ru: 'Отклонить'},
  'confirmSas': {
    AppLocale.en: 'Do these match the other device?',
    AppLocale.ru: 'Совпадает ли это с другим устройством?',
  },
  'theyMatch': {AppLocale.en: 'They match', AppLocale.ru: 'Совпадает'},
  'noMatch': {AppLocale.en: 'No match', AppLocale.ru: 'Не совпадает'},
  'cryptoWaiting': {
    AppLocale.en: 'Waiting for the other device…',
    AppLocale.ru: 'Ожидание другого устройства…',
  },
  'cryptoDone': {AppLocale.en: 'Verified', AppLocale.ru: 'Проверено'},
  'cryptoError': {
    AppLocale.en: 'Verification failed',
    AppLocale.ru: 'Ошибка проверки',
  },
  'chooseSas': {
    AppLocale.en: 'Continue with emoji comparison',
    AppLocale.ru: 'Продолжить сравнением эмодзи',
  },
  'backupUnavailable': {
    AppLocale.en:
        'Key backup is unavailable on this platform (encryption not enabled).',
    AppLocale.ru:
        'Резерв ключей недоступен на этой платформе (шифрование выключено).',
  },
  'backupInit': {
    AppLocale.en: 'Set up new recovery',
    AppLocale.ru: 'Настроить восстановление',
  },
  'backupRestore': {
    AppLocale.en: 'Restore with recovery key',
    AppLocale.ru: 'Восстановить ключом',
  },
  'recoveryKey': {
    AppLocale.en: 'Recovery key or passphrase',
    AppLocale.ru: 'Ключ восстановления или фраза',
  },
  'recoveryCreated': {
    AppLocale.en:
        'Save this recovery key now. It will not be shown again:',
    AppLocale.ru:
        'Сохраните этот ключ восстановления. Он больше не будет показан:',
  },
  'identityConnected': {
    AppLocale.en: 'Crypto identity connected',
    AppLocale.ru: 'Крипто-идентичность подключена',
  },
  'identityInitialized': {
    AppLocale.en: 'Crypto identity initialized (not connected here)',
    AppLocale.ru:
        'Крипто-идентичность инициализирована (здесь не подключена)',
  },
  'identityMissing': {
    AppLocale.en: 'No crypto identity yet',
    AppLocale.ru: 'Крипто-идентичность ещё не создана',
  },
  'copy': {AppLocale.en: 'Copy', AppLocale.ru: 'Копировать'},
  'changeAvatar': {
    AppLocale.en: 'Change avatar',
    AppLocale.ru: 'Изменить аватар',
  },
  'optionalRoomAlias': {
    AppLocale.en: 'Address (optional)',
    AppLocale.ru: 'Адрес (необязательно)',
  },
  'inviteMember': {
    AppLocale.en: 'Invite member',
    AppLocale.ru: 'Пригласить участника',
  },
  'members': {AppLocale.en: 'Members', AppLocale.ru: 'Участники'},
  'roomDetails': {
    AppLocale.en: 'Details',
    AppLocale.ru: 'Сведения',
  },
  'roomIdLabel': {AppLocale.en: 'Room ID', AppLocale.ru: 'ID комнаты'},
  'roomAliasLabel': {
    AppLocale.en: 'Canonical address',
    AppLocale.ru: 'Основной адрес',
  },
  'editRoomAlias': {
    AppLocale.en: 'Edit canonical address',
    AppLocale.ru: 'Изменить основной адрес',
  },
  'roomAvatar': {
    AppLocale.en: 'Room avatar',
    AppLocale.ru: 'Аватар комнаты',
  },
  'encryptionLabel': {
    AppLocale.en: 'Encryption',
    AppLocale.ru: 'Шифрование',
  },
  'encryptionOn': {AppLocale.en: 'Enabled', AppLocale.ru: 'Включено'},
  'encryptionOff': {AppLocale.en: 'Off', AppLocale.ru: 'Выкл.'},
  'noMembersYet': {
    AppLocale.en: 'No joined members yet.',
    AppLocale.ru: 'Пока нет участников.',
  },
  'powerLevel': {
    AppLocale.en: 'PL {level}',
    AppLocale.ru: 'Ур. {level}',
  },
  'invitePlaceholder': {
    AppLocale.en: '@person:server',
    AppLocale.ru: '@person:server',
  },
  'invitationSent': {
    AppLocale.en: 'Invitation sent.',
    AppLocale.ru: 'Приглашение отправлено.',
  },
  'topic': {AppLocale.en: 'Topic', AppLocale.ru: 'Тема'},
  'kick': {AppLocale.en: 'Kick', AppLocale.ru: 'Исключить'},
  'confirmKick': {
    AppLocale.en: 'Remove {name} from this room?',
    AppLocale.ru: 'Исключить {name} из комнаты?',
  },
  'leaveRoom': {AppLocale.en: 'Leave room', AppLocale.ru: 'Покинуть комнату'},
  'miniAppAvailable': {
    AppLocale.en: 'Mini App available: {title}',
    AppLocale.ru: 'Доступно мини-приложение: {title}',
  },
  'loadEarlierMessages': {
    AppLocale.en: 'Load earlier messages',
    AppLocale.ru: 'Загрузить более ранние сообщения',
  },
  'editingMessage': {
    AppLocale.en: 'Editing message',
    AppLocale.ru: 'Редактирование сообщения',
  },
  'replyingTo': {
    AppLocale.en: 'Replying to {user}',
    AppLocale.ru: 'Ответ {user}',
  },
  'typing': {AppLocale.en: 'typing…', AppLocale.ru: 'печатает…'},
  'typingUsers': {
    AppLocale.en: '{users} typing…',
    AppLocale.ru: '{users} печатает…',
  },
  'attachFile': {AppLocale.en: 'Attach file', AppLocale.ru: 'Прикрепить файл'},
  'messageHint': {
    AppLocale.en: 'Message…  / for bot commands',
    AppLocale.ru: 'Сообщение…  / для команд бота',
  },
  'sendMessage': {
    AppLocale.en: 'Send message',
    AppLocale.ru: 'Отправить сообщение',
  },
  'matrixUserId': {
    AppLocale.en: 'Matrix user ID',
    AppLocale.ru: 'Matrix ID пользователя',
  },
  'invite': {AppLocale.en: 'Invite', AppLocale.ru: 'Пригласить'},
  'reply': {AppLocale.en: 'Reply', AppLocale.ru: 'Ответить'},
  'react': {AppLocale.en: 'React 👍', AppLocale.ru: 'Реакция 👍'},
  'edit': {AppLocale.en: 'Edit', AppLocale.ru: 'Изменить'},
  'delete': {AppLocale.en: 'Delete', AppLocale.ru: 'Удалить'},
  'openMedia': {AppLocale.en: 'Open media', AppLocale.ru: 'Открыть медиа'},
  'miniApp': {AppLocale.en: 'MiniApp', AppLocale.ru: 'Мини-приложение'},
  'edited': {AppLocale.en: 'edited', AppLocale.ru: 'изм.'},
  'attachment': {AppLocale.en: 'Attachment', AppLocale.ru: 'Вложение'},
  'roomUpdate': {
    AppLocale.en: 'Room update',
    AppLocale.ru: 'Изменение комнаты',
  },
  'callTitle': {AppLocale.en: 'Call', AppLocale.ru: 'Звонок'},
  'leaveCall': {AppLocale.en: 'Leave call', AppLocale.ru: 'Выйти из звонка'},
  'openExternally': {
    AppLocale.en: 'Open externally',
    AppLocale.ru: 'Открыть снаружи',
  },
  'embedUnsupported': {
    AppLocale.en:
        'In-app call surface is unavailable here. You can open Element Call externally.',
    AppLocale.ru:
        'Встроенный звонок здесь недоступен. Можно открыть Element Call снаружи.',
  },
  'widgetReady': {
    AppLocale.en: 'Call widget ready',
    AppLocale.ru: 'Виджет звонка готов',
  },
  'callBannerActive': {
    AppLocale.en: 'Call in progress',
    AppLocale.ru: 'Идёт звонок',
  },
  'joinCall': {AppLocale.en: 'Join', AppLocale.ru: 'Присоединиться'},
  'createPoll': {AppLocale.en: 'Create poll', AppLocale.ru: 'Создать опрос'},
  'pollQuestion': {AppLocale.en: 'Question', AppLocale.ru: 'Вопрос'},
  'pollOption': {
    AppLocale.en: 'Option {n}',
    AppLocale.ru: 'Вариант {n}',
  },
  'addPollOption': {
    AppLocale.en: 'Add option',
    AppLocale.ru: 'Добавить вариант',
  },
  'pollAllowMultiple': {
    AppLocale.en: 'Allow multiple answers',
    AppLocale.ru: 'Несколько ответов',
  },
  'pollEnded': {AppLocale.en: 'Poll ended', AppLocale.ru: 'Опрос завершён'},
  'endPoll': {AppLocale.en: 'End poll', AppLocale.ru: 'Завершить опрос'},
  'pollSelectUpTo': {
    AppLocale.en: 'Select up to {n}',
    AppLocale.ru: 'Выберите до {n}',
  },
  'pollVoters': {
    AppLocale.en: '{n} votes',
    AppLocale.ru: 'Голосов: {n}',
  },
  'syncWaiting': {
    AppLocale.en: 'Connecting to homeserver…',
    AppLocale.ru: 'Подключение к серверу…',
  },
  'syncSyncing': {
    AppLocale.en: 'Syncing…',
    AppLocale.ru: 'Синхронизация…',
  },
  'syncError': {
    AppLocale.en: 'Offline or sync error',
    AppLocale.ru: 'Офлайн или ошибка синхронизации',
  },
  'syncErrorDetail': {
    AppLocale.en: 'Sync error: {error}',
    AppLocale.ru: 'Ошибка sync: {error}',
  },
  'blockedUnsafeUrl': {
    AppLocale.en: 'Blocked unsafe URL',
    AppLocale.ru: 'Небезопасный URL заблокирован',
  },
  'sending': {AppLocale.en: 'Sending…', AppLocale.ru: 'Отправка…'},
  'sent': {AppLocale.en: 'Sent', AppLocale.ru: 'Отправлено'},
  'failed': {AppLocale.en: 'Failed', AppLocale.ru: 'Ошибка'},
  'muteNotifications': {
    AppLocale.en: 'Mute notifications',
    AppLocale.ru: 'Выключить уведомления',
  },
  'unmuteNotifications': {
    AppLocale.en: 'Unmute',
    AppLocale.ru: 'Включить уведомления',
  },
  'pinMessage': {AppLocale.en: 'Pin', AppLocale.ru: 'Закрепить'},
  'unpinMessage': {AppLocale.en: 'Unpin', AppLocale.ru: 'Открепить'},
  'forwardMessage': {AppLocale.en: 'Forward', AppLocale.ru: 'Переслать'},
  'unreadMessages': {
    AppLocale.en: 'Unread messages',
    AppLocale.ru: 'Непрочитанные',
  },
  'userProfile': {AppLocale.en: 'Profile', AppLocale.ru: 'Профиль'},
  'ignoreUser': {AppLocale.en: 'Ignore', AppLocale.ru: 'Игнорировать'},
  'unignoreUser': {
    AppLocale.en: 'Stop ignoring',
    AppLocale.ru: 'Перестать игнорировать',
  },
  'lastSeen': {
    AppLocale.en: 'Last seen {when}',
    AppLocale.ru: 'Был(а) {when}',
  },
  'userOffline': {AppLocale.en: 'Offline', AppLocale.ru: 'Не в сети'},
  'userOnline': {AppLocale.en: 'Online', AppLocale.ru: 'В сети'},
  'userAway': {AppLocale.en: 'Away', AppLocale.ru: 'Отошёл'},
  'pinned': {AppLocale.en: 'Pinned', AppLocale.ru: 'Закреплено'},
  'mutedRoom': {AppLocale.en: 'Muted', AppLocale.ru: 'Без уведомлений'},
  'sharedMedia': {AppLocale.en: 'Shared media', AppLocale.ru: 'Общие медиа'},
  'noSharedMedia': {
    AppLocale.en: 'No photos, files, or voice notes in the loaded history.',
    AppLocale.ru: 'В загруженной истории нет фото, файлов и голосовых.',
  },
  'copyMxid': {AppLocale.en: 'Copy Matrix ID', AppLocale.ru: 'Скопировать MXID'},
  'copyMessage': {AppLocale.en: 'Copy', AppLocale.ru: 'Копировать'},
  'confirmDelete': {
    AppLocale.en: 'Delete this message for everyone in the room?',
    AppLocale.ru: 'Удалить это сообщение у всех в комнате?',
  },
  'verifyUser': {AppLocale.en: 'Verify', AppLocale.ru: 'Проверить'},
  'allDevicesVerified': {
    AppLocale.en: 'Every device for this user is already verified.',
    AppLocale.ru: 'Все устройства этого пользователя уже проверены.',
  },
  'recordVoice': {AppLocale.en: 'Voice message', AppLocale.ru: 'Голосовое'},
  'stopRecording': {AppLocale.en: 'Send voice', AppLocale.ru: 'Отправить голос'},
  'recordingVoice': {AppLocale.en: 'Recording…', AppLocale.ru: 'Запись…'},
  'retrySend': {AppLocale.en: 'Retry send', AppLocale.ru: 'Повторить отправку'},
  'encryptedMessage': {
    AppLocale.en: 'Encrypted',
    AppLocale.ru: 'Зашифровано',
  },
  'thread': {AppLocale.en: 'Thread', AppLocale.ru: 'Ветка'},
  'threadCount': {
    AppLocale.en: '{count} replies',
    AppLocale.ru: 'Ответов: {count}',
  },
  'shareLocation': {
    AppLocale.en: 'Share location',
    AppLocale.ru: 'Поделиться местом',
  },
  'stickers': {AppLocale.en: 'Stickers', AppLocale.ru: 'Стикеры'},
  'noStickers': {
    AppLocale.en: 'No sticker packs in this account yet.',
    AppLocale.ru: 'В этом аккаунте пока нет наборов стикеров.',
  },
  'knock': {AppLocale.en: 'Knock', AppLocale.ru: 'Постучаться'},
  'knockSent': {
    AppLocale.en: 'Knock sent. Wait for an invite.',
    AppLocale.ru: 'Запрос отправлен. Дождитесь приглашения.',
  },
  'approveKnock': {AppLocale.en: 'Approve', AppLocale.ru: 'Принять'},
  'denyKnock': {AppLocale.en: 'Deny', AppLocale.ru: 'Отклонить'},
  'pendingKnocks': {
    AppLocale.en: 'Pending knocks',
    AppLocale.ru: 'Запросы на вход',
  },
  'noKnocks': {
    AppLocale.en: 'No pending knocks.',
    AppLocale.ru: 'Нет запросов на вход.',
  },
  'roomPreview': {
    AppLocale.en: 'Room preview',
    AppLocale.ru: 'Предпросмотр комнаты',
  },
  'linkNewDevice': {
    AppLocale.en: 'Link new device',
    AppLocale.ru: 'Привязать устройство',
  },
  'signInQr': {
    AppLocale.en: 'Show sign-in QR',
    AppLocale.ru: 'QR для входа',
  },
  'qrLoginHint': {
    AppLocale.en:
        'Scan this with an existing Element X or HighLife session. The dart Matrix SDK has no MSC4108 rendezvous yet, so this QR carries a local matrix: login payload.',
    AppLocale.ru:
        'Отсканируйте это существующей сессией Element X или HighLife. В dart SDK пока нет MSC4108 rendezvous, поэтому QR содержит локальный matrix: payload для входа.',
  },
  'qrLoginUnsupported': {
    AppLocale.en:
        'QR login needs MSC4108 rendezvous, which this Flutter build does not implement yet. Use password or SSO.',
    AppLocale.ru:
        'Вход по QR требует MSC4108 rendezvous — в этой сборке Flutter его ещё нет. Войдите паролем или SSO.',
  },
  'callMicBlocked': {
    AppLocale.en: 'Microphone permission was denied.',
    AppLocale.ru: 'Нет доступа к микрофону.',
  },
  'callCryptoUnavailable': {
    AppLocale.en: 'Encryption is not ready for this call.',
    AppLocale.ru: 'Шифрование для звонка ещё не готово.',
  },
  'callFailed': {
    AppLocale.en: 'Call failed: {detail}',
    AppLocale.ru: 'Звонок не удался: {detail}',
  },
  'linkNewDeviceHint': {
    AppLocale.en:
        'Show this QR on a signed-in HighLife so another device can link. Without MSC4108 in the dart SDK this is a local matrix: payload, not a live rendezvous.',
    AppLocale.ru:
        'Покажите этот QR на вошедшем HighLife, чтобы привязать другое устройство. Без MSC4108 в dart SDK это локальный matrix: payload, а не живой rendezvous.',
  },
  'openMap': {AppLocale.en: 'Open map', AppLocale.ru: 'Открыть карту'},
  'prompts': {AppLocale.en: 'Prompts', AppLocale.ru: 'Подсказки'},
  'latitude': {AppLocale.en: 'Latitude', AppLocale.ru: 'Широта'},
  'longitude': {AppLocale.en: 'Longitude', AppLocale.ru: 'Долгота'},
  'sendLocation': {
    AppLocale.en: 'Send location',
    AppLocale.ru: 'Отправить место',
  },
  'locationHint': {
    AppLocale.en: 'Latitude and longitude, or a geo: URI.',
    AppLocale.ru: 'Широта и долгота или geo: URI.',
  },
  'geoUri': {AppLocale.en: 'geo: URI', AppLocale.ru: 'geo: URI'},
  'memberCount': {
    AppLocale.en: '{count} members',
    AppLocale.ru: 'Участников: {count}',
  },
  'declinedCall': {
    AppLocale.en: 'Declined a call',
    AppLocale.ru: 'Отклонил(а) звонок',
  },
};
