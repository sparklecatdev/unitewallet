import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/dto.dart' as dto;
import 'package:solana/base58.dart';
import 'package:solana/solana.dart';

void main() {
  runApp(const UniteApp());
}

const _ink = Color(0xFF000000);
const _panel = Color(0xFF050505);
const _panelRaised = Color(0xFF111111);
const _control = Color(0xFF171717);
const _line = Color(0xFF242424);
const _softLine = Color(0xFF303030);
const _muted = Color(0xFF8E8E93);
const _softText = Color(0xFFC8C8C8);
const _positive = Color(0xFF41D98D);
const _warning = Color(0xFFFFC766);
const _danger = Color(0xFFFF6B6B);
const _lavender = Color(0xFFA7B0FF);
const _mint = Color(0xFF75F0C8);
const _sky = Color(0xFF64B5FF);

const _walletMnemonicKey = 'unite.solana.mnemonic';
const _walletPrivateKeyKey = 'unite.solana.private_key';
const _walletImportTypeKey = 'unite.solana.import_type';
const _clusterKey = 'unite.solana.cluster';
const _diagnosticsEnabledKey = 'unite.diagnostics.enabled';
const _pinSaltKey = 'unite.lock.pin_salt';
const _pinHashKey = 'unite.lock.pin_hash';
const _pinFailedCountKey = 'unite.lock.failed_count';
const _pinLockedUntilKey = 'unite.lock.locked_until';
const _backupConfirmedKey = 'unite.backup.confirmed';
const _knownRecipientsKey = 'unite.solana.known_recipients';
const _addressBookKey = 'unite.solana.address_book';
const _mainnetSendConfirmedKey = 'unite.solana.mainnet_send_confirmed';
const _privacyModeKey = 'unite.privacy_mode';
const _autoLockKey = 'unite.auto_lock';
const _customRpcUrlKey = 'unite.solana.custom_rpc_url';
const _customWsUrlKey = 'unite.solana.custom_ws_url';
const _pinHashRounds = 45000;

class UniteApp extends StatelessWidget {
  const UniteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unite',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: const ColorScheme.dark(
          surface: _ink,
          primary: Colors.white,
          secondary: _positive,
          error: _danger,
        ),
        fontFamily: 'SF Pro Display',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 52, fontWeight: FontWeight.w900),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _control,
          hintStyle: const TextStyle(color: _muted),
          labelStyle: const TextStyle(color: _muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _line),
            borderRadius: BorderRadius.circular(18),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white, width: 1.2),
            borderRadius: BorderRadius.circular(18),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _danger),
            borderRadius: BorderRadius.circular(18),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _danger),
            borderRadius: BorderRadius.circular(18),
\how          ),
        ),
      ),
      home: WalletScope(
        controller: SolanaWalletController()..load(),
        child: const WalletHome(),
      ),
    );
  }
}

class WalletScope extends InheritedNotifier<SolanaWalletController> {
  const WalletScope({
    super.key,
    required SolanaWalletController controller,
    required super.child,
  }) : super(notifier: controller);

  static SolanaWalletController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WalletScope>();
    assert(scope != null, 'WalletScope is missing.');
    return scope!.notifier!;
  }
}

class SolanaWalletController extends ChangeNotifier {
  SolanaWalletController();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  SharedPreferences? _prefs;
  Ed25519HDKeyPair? _wallet;
  String? _mnemonic;
  String? _privateKeyBase58;
  int _lamports = 0;
  bool _loading = true;
  bool _locked = false;
  bool _busy = false;
  bool _diagnosticsEnabled = true;
  bool _hasStoredWallet = false;
  bool _pinEnabled = false;
  bool _biometricsAvailable = false;
  bool _backupConfirmed = false;
  bool _mainnetSendConfirmed = false;
  bool _privacyMode = false;
  bool _autoLockEnabled = true;
  String? _status;
  String _cluster = SolanaCluster.devnet.id;
  String? _customRpcUrl;
  String? _customWsUrl;
  int? _rpcSlot;
  Map<String, String> _addressBook = {};
  List<TokenBalance> _tokens = [];
  List<ActivityEntry> _activity = [];
  List<AppNotification> _notifications = [];
  List<MarketAsset> _marketAssets = MarketAsset.defaults;
  bool _marketLoading = false;
  String? _marketStatus;
  DateTime? _marketUpdatedAt;
  final List<DiagnosticEntry> _logs = [];

  bool get loading => _loading;
  bool get locked => _locked;
  bool get busy => _busy;
  bool get hasWallet => _wallet != null;
  bool get hasStoredWallet => _hasStoredWallet;
  bool get pinEnabled => _pinEnabled;
  bool get biometricsAvailable => _biometricsAvailable;
  bool get backupConfirmed => _backupConfirmed;
  bool get backupRequired => hasWallet && !backupConfirmed;
  bool get mainnetSendConfirmed => _mainnetSendConfirmed;
  bool get privacyMode => _privacyMode;
  bool get autoLockEnabled => _autoLockEnabled;
  String? get status => _status;
  String get cluster => _cluster;
  String? get customRpcUrl => _customRpcUrl;
  String? get customWsUrl => _customWsUrl;
  String get address => _wallet?.address ?? '';
  String? get mnemonic => _mnemonic;
  String? get privateKeyBase58 => _privateKeyBase58;
  bool get diagnosticsEnabled => _diagnosticsEnabled;
  List<DiagnosticEntry> get logs => List.unmodifiable(_logs.reversed);
  List<TokenBalance> get tokens => List.unmodifiable(_tokens);
  List<ActivityEntry> get activity => List.unmodifiable(_activity);
  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  Map<String, String> get addressBook => Map.unmodifiable(_addressBook);
  List<MarketAsset> get marketAssets => List.unmodifiable(_marketAssets);
  bool get marketLoading => _marketLoading;
  String? get marketStatus => _marketStatus;
  DateTime? get marketUpdatedAt => _marketUpdatedAt;
  int get lamports => _lamports;
  int? get rpcSlot => _rpcSlot;
  double get solBalance => _lamports / lamportsPerSol;
  int get maxSendLamports => max(0, _lamports - 5000);
  SolanaCluster get activeCluster {
    if (_cluster == SolanaCluster.custom.id &&
        _customRpcUrl != null &&
        _customRpcUrl!.isNotEmpty) {
      return SolanaCluster(
        SolanaCluster.custom.id,
        'Custom RPC',
        _customRpcUrl!,
        _customWsUrl?.isNotEmpty == true
            ? _customWsUrl!
            : websocketFromRpc(_customRpcUrl!),
      );
    }
    return SolanaCluster.byId(_cluster);
  }

  SolanaClient get _client => SolanaClient(
    rpcUrl: Uri.parse(activeCluster.rpcUrl),
    websocketUrl: Uri.parse(activeCluster.websocketUrl),
  );

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _cluster = _prefs?.getString(_clusterKey) ?? SolanaCluster.devnet.id;
    _diagnosticsEnabled = _prefs?.getBool(_diagnosticsEnabledKey) ?? true;
    _backupConfirmed = _prefs?.getBool(_backupConfirmedKey) ?? false;
    _mainnetSendConfirmed = _prefs?.getBool(_mainnetSendConfirmedKey) ?? false;
    _privacyMode = _prefs?.getBool(_privacyModeKey) ?? false;
    _autoLockEnabled = _prefs?.getBool(_autoLockKey) ?? true;
    _customRpcUrl = _prefs?.getString(_customRpcUrlKey);
    _customWsUrl = _prefs?.getString(_customWsUrlKey);
    _addressBook = decodeAddressBook(_prefs?.getString(_addressBookKey));
    try {
      await _migratePlaintextSecrets();
      _pinEnabled = await _secureStorage.read(key: _pinHashKey) != null;
      _biometricsAvailable = await _canUseBiometrics();
      _hasStoredWallet = await _storedImportType() != null;
      if (_hasStoredWallet && _pinEnabled) {
        _locked = true;
        _status = 'Unlock Unite to continue.';
      } else if (_hasStoredWallet) {
        await _restoreStoredWallet(refresh: false);
        await refreshBalance();
        _log('Wallet restored from secure storage.');
      }
      unawaited(refreshMarket());
    } catch (error, stackTrace) {
      _setFriendlyError(
        'We could not unlock the saved wallet on this device. Import it again to continue.',
        error,
        stackTrace,
      );
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> createWallet() async {
    await _run('Created Solana wallet.', () async {
      final newMnemonic = bip39.generateMnemonic();
      await _secureStorage.write(key: _walletMnemonicKey, value: newMnemonic);
      await _secureStorage.delete(key: _walletPrivateKeyKey);
      await _prefs?.setString(_walletImportTypeKey, 'mnemonic');
      await _restoreMnemonic(newMnemonic);
      _hasStoredWallet = true;
      _locked = false;
      _backupConfirmed = false;
      await _prefs?.setBool(_backupConfirmedKey, false);
    });
  }

  Future<void> importWallet(String phrase) async {
    final normalized = phrase.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!bip39.validateMnemonic(normalized)) {
      _status =
          'That recovery phrase does not look right. Check the word order and try again.';
      notifyListeners();
      return;
    }
    await _run('Imported Solana wallet.', () async {
      await _secureStorage.write(key: _walletMnemonicKey, value: normalized);
      await _secureStorage.delete(key: _walletPrivateKeyKey);
      await _prefs?.setString(_walletImportTypeKey, 'mnemonic');
      await _restoreMnemonic(normalized);
      _hasStoredWallet = true;
      _locked = false;
      _backupConfirmed = true;
      await _prefs?.setBool(_backupConfirmedKey, true);
    });
  }

  Future<void> importPrivateKey(String keyText) async {
    final parsed = parsePrivateKey(keyText);
    if (parsed == null) {
      _status =
          'That private key could not be read. Use a Solana base58 key or JSON byte array.';
      notifyListeners();
      return;
    }
    await _run('Imported Solana private key.', () async {
      final encoded = base58encode(parsed);
      await _secureStorage.write(key: _walletPrivateKeyKey, value: encoded);
      await _secureStorage.delete(key: _walletMnemonicKey);
      await _prefs?.setString(_walletImportTypeKey, 'private_key');
      await _restorePrivateKey(encoded);
      _hasStoredWallet = true;
      _locked = false;
      _backupConfirmed = true;
      await _prefs?.setBool(_backupConfirmedKey, true);
    });
  }

  Future<void> confirmBackupSaved() async {
    _backupConfirmed = true;
    await _prefs?.setBool(_backupConfirmedKey, true);
    _notify('Recovery backup confirmed.');
    notifyListeners();
  }

  Future<void> confirmMainnetSends() async {
    _mainnetSendConfirmed = true;
    await _prefs?.setBool(_mainnetSendConfirmedKey, true);
    _notify('Mainnet send warning acknowledged.');
    notifyListeners();
  }

  Future<void> switchCluster(String id) async {
    if (_cluster == id) return;
    if (id == SolanaCluster.custom.id &&
        (_customRpcUrl == null || _customRpcUrl!.isEmpty)) {
      _status =
          'Add a custom RPC URL in Profile before switching to Custom RPC.';
      notifyListeners();
      return;
    }
    await _run('Switched to ${SolanaCluster.byId(id).label}.', () async {
      _cluster = id;
      await _prefs?.setString(_clusterKey, id);
      await refreshBalance();
    });
  }

  Future<void> saveCustomRpc({
    required String rpcUrl,
    required String websocketUrl,
  }) async {
    final rpc = rpcUrl.trim();
    final ws = websocketUrl.trim();
    if (!isValidUrl(rpc) || !rpc.startsWith('http')) {
      _status = 'Enter a valid HTTPS RPC URL from your provider.';
      notifyListeners();
      return;
    }
    if (ws.isNotEmpty && (!isValidUrl(ws) || !ws.startsWith('ws'))) {
      _status = 'Enter a valid websocket URL, or leave it blank.';
      notifyListeners();
      return;
    }
    await _run('Custom RPC saved.', () async {
      _customRpcUrl = rpc;
      _customWsUrl = ws.isEmpty ? websocketFromRpc(rpc) : ws;
      _cluster = SolanaCluster.custom.id;
      await _prefs?.setString(_customRpcUrlKey, _customRpcUrl!);
      await _prefs?.setString(_customWsUrlKey, _customWsUrl!);
      await _prefs?.setString(_clusterKey, _cluster);
      if (_wallet != null) await refreshBalance();
    });
  }

  Future<void> refreshBalance() async {
    if (_wallet == null) return;
    await _run('Balance refreshed.', () async {
      final result = await _client.rpcClient.getBalance(
        address,
        commitment: Commitment.confirmed,
      );
      _rpcSlot = await _client.rpcClient.getSlot(
        commitment: Commitment.confirmed,
      );
      final previousLamports = _lamports;
      _lamports = result.value;
      if (_lamports > previousLamports && previousLamports != 0) {
        _notify('Received ${formatSol(_lamports - previousLamports)} SOL.');
      }
      if (_lamports > 0 && _lamports < 10000000) {
        _notify('SOL balance is low.');
      }
      await _refreshTokens();
      await _refreshActivity();
    });
  }

  Future<void> refreshMarket() async {
    _marketLoading = true;
    _marketStatus = null;
    notifyListeners();
    try {
      final ids = _marketAssets.map((asset) => asset.id).join(',');
      final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
        'vs_currency': 'usd',
        'ids': ids,
        'order': 'market_cap_desc',
        'per_page': _marketAssets.length.toString(),
        'page': '1',
        'sparkline': 'true',
        'price_change_percentage': '1h,24h,7d',
        'precision': '4',
      });
      final response = await http
          .get(uri, headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw HttpException(
          'Market request failed with status ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Unexpected market response.');
      }
      final byId = <String, Map<String, dynamic>>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic> && item['id'] is String) {
          byId[item['id'] as String] = item;
        }
      }
      _marketAssets = [
        for (final asset in _marketAssets)
          asset.copyWith(
            name: byId[asset.id]?['name']?.toString(),
            symbol: byId[asset.id]?['symbol']?.toString().toUpperCase(),
            imageUrl: byId[asset.id]?['image']?.toString(),
            priceUsd: readDouble(byId[asset.id], 'current_price'),
            change1h: readDouble(
              byId[asset.id],
              'price_change_percentage_1h_in_currency',
            ),
            change24h: readDouble(
              byId[asset.id],
              'price_change_percentage_24h_in_currency',
            ),
            change7d: readDouble(
              byId[asset.id],
              'price_change_percentage_7d_in_currency',
            ),
            volume24h: readDouble(byId[asset.id], 'total_volume'),
            marketCap: readDouble(byId[asset.id], 'market_cap'),
            high24h: readDouble(byId[asset.id], 'high_24h'),
            low24h: readDouble(byId[asset.id], 'low_24h'),
            rank: readInt(byId[asset.id], 'market_cap_rank'),
            sparkline: readSparkline(byId[asset.id]),
          ),
      ];
      _marketUpdatedAt = DateTime.now();
      _marketStatus = 'Market updated.';
      _log('Market data refreshed with icons and 7d sparklines.');
    } catch (error, stackTrace) {
      _marketStatus = 'Market data is temporarily unavailable.';
      _log('Market refresh failed.\n$error\n$stackTrace', isError: true);
    } finally {
      _marketLoading = false;
      notifyListeners();
    }
  }

  Future<void> requestAirdrop() async {
    final wallet = _wallet;
    if (wallet == null) return;
    if (activeCluster.id != SolanaCluster.devnet.id) {
      _status =
          'Airdrop only works on Devnet. Switch back to Devnet to test with free SOL.';
      notifyListeners();
      return;
    }
    await _run('Requested 1 devnet SOL.', () async {
      await _client.requestAirdrop(
        address: wallet.publicKey,
        lamports: lamportsPerSol,
        commitment: Commitment.confirmed,
      );
      await refreshBalance();
    });
  }

  Future<void> sendSol({
    required String recipient,
    required String amount,
    String? memo,
  }) async {
    final wallet = _wallet;
    if (wallet == null) return;
    final normalizedRecipient = recipient.trim();
    if (!isValidAddress(normalizedRecipient)) {
      _status = 'That recipient is not a valid Solana address.';
      notifyListeners();
      return;
    }
    final lamports = solToLamports(amount);
    if (lamports == null || lamports <= 0) {
      _status = 'Enter a SOL amount greater than zero.';
      notifyListeners();
      return;
    }
    if (lamports >= _lamports) {
      _status = 'Keep a little SOL in the wallet for network fees.';
      notifyListeners();
      return;
    }

    await _run('Transfer submitted.', () async {
      final simulation = await simulateSolTransfer(
        recipient: normalizedRecipient,
        lamports: lamports,
        memo: memo,
      );
      if (!simulation.ok) {
        _status = simulation.message;
        return;
      }
      final signature = await _client.transferLamports(
        source: wallet,
        destination: Ed25519HDPublicKey.fromBase58(normalizedRecipient),
        lamports: lamports,
        memo: memo?.trim().isEmpty ?? true ? null : memo!.trim(),
        commitment: Commitment.confirmed,
      );
      _status =
          'Sent ${formatSol(lamports)} SOL. Signature: ${shortHash(signature)}';
      await _rememberRecipient(normalizedRecipient);
      _notify('Transfer submitted.');
      await refreshBalance();
    });
  }

  Future<SimulationPreview> simulateSolTransfer({
    required String recipient,
    required int lamports,
    String? memo,
  }) async {
    final wallet = _wallet;
    if (wallet == null) {
      return const SimulationPreview(false, 'Wallet is locked.', null);
    }
    try {
      final latest = await _client.rpcClient
          .getLatestBlockhash(commitment: Commitment.confirmed)
          .value;
      final message = Message(
        instructions: [
          SystemInstruction.transfer(
            fundingAccount: wallet.publicKey,
            recipientAccount: Ed25519HDPublicKey.fromBase58(recipient),
            lamports: lamports,
          ),
          if (memo?.trim().isNotEmpty == true)
            MemoInstruction(signers: [wallet.publicKey], memo: memo!.trim()),
        ],
      );
      final signed = await wallet.signMessage(
        message: message,
        recentBlockhash: latest.blockhash,
      );
      final result = await _client.rpcClient.simulateTransaction(
        signed.encode(),
        commitment: Commitment.confirmed,
        sigVerify: false,
      );
      if (result.value.err != null) {
        return const SimulationPreview(
          false,
          'Simulation failed. This transfer may not complete.',
          null,
        );
      }
      return SimulationPreview(
        true,
        'Simulation passed.',
        result.value.unitsConsumed,
      );
    } catch (error, stackTrace) {
      _log('Simulation failed.\n$error\n$stackTrace', isError: true);
      return const SimulationPreview(
        false,
        'Simulation could not run. Check RPC health and try again.',
        null,
      );
    }
  }

  Future<void> clearWallet() async {
    await _run('Wallet removed from this device.', () async {
      _wallet?.destroy();
      _wallet = null;
      _mnemonic = null;
      _privateKeyBase58 = null;
      _lamports = 0;
      _hasStoredWallet = false;
      _locked = false;
      _backupConfirmed = false;
      _tokens = [];
      _activity = [];
      _rpcSlot = null;
      await _secureStorage.delete(key: _walletMnemonicKey);
      await _secureStorage.delete(key: _walletPrivateKeyKey);
      await _prefs?.remove(_walletImportTypeKey);
      await _prefs?.remove(_backupConfirmedKey);
    });
  }

  Future<void> unlockWithPin(String pin) async {
    if (!_pinEnabled) {
      await _unlock('Wallet opened.');
      return;
    }
    final lockout = _pinLockedUntil();
    if (lockout != null && DateTime.now().isBefore(lockout)) {
      _status = 'Too many attempts. Try again at ${formatTime(lockout)}.';
      notifyListeners();
      return;
    }
    if (!await _verifyPin(pin)) {
      await _recordFailedPin();
      _status = 'That PIN was not correct.';
      notifyListeners();
      return;
    }
    await _clearFailedPins();
    await _unlock('Unlocked with PIN.');
  }

  Future<void> unlockWithBiometrics() async {
    if (!_biometricsAvailable) {
      _status = 'Biometric unlock is not available on this device.';
      notifyListeners();
      return;
    }
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock Unite wallet',
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        await _unlock('Unlocked with biometrics.');
      } else {
        _status = 'Unlock was cancelled.';
        notifyListeners();
      }
    } catch (error, stackTrace) {
      _setFriendlyError(
        'Biometric unlock did not work. Use your PIN instead.',
        error,
        stackTrace,
      );
      notifyListeners();
    }
  }

  Future<void> lock() async {
    if (!_pinEnabled) return;
    _wallet?.destroy();
    _wallet = null;
    _mnemonic = null;
    _privateKeyBase58 = null;
    _lamports = 0;
    _locked = true;
    _status = 'Unite is locked.';
    _log('Wallet locked.');
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      _status = 'Choose a PIN with at least 6 digits.';
      notifyListeners();
      return;
    }
    await _run('PIN lock enabled.', () async {
      final salt = generateSalt();
      await _secureStorage.write(key: _pinSaltKey, value: salt);
      await _secureStorage.write(key: _pinHashKey, value: hashPin(pin, salt));
      _pinEnabled = true;
    });
  }

  Future<void> removePin() async {
    await _run('PIN lock removed.', () async {
      await _secureStorage.delete(key: _pinSaltKey);
      await _secureStorage.delete(key: _pinHashKey);
      _pinEnabled = false;
      _locked = false;
    });
  }

  Future<void> setDiagnosticsEnabled(bool value) async {
    _diagnosticsEnabled = value;
    await _prefs?.setBool(_diagnosticsEnabledKey, value);
    if (!value) _logs.clear();
    if (value) _log('Diagnostics enabled.');
    notifyListeners();
  }

  Future<void> setPrivacyMode(bool value) async {
    _privacyMode = value;
    await _prefs?.setBool(_privacyModeKey, value);
    notifyListeners();
  }

  Future<void> setAutoLockEnabled(bool value) async {
    _autoLockEnabled = value;
    await _prefs?.setBool(_autoLockKey, value);
    notifyListeners();
  }

  Future<void> saveAddressLabel(String address, String label) async {
    final normalized = address.trim();
    final cleanLabel = label.trim();
    if (!isValidAddress(normalized) || cleanLabel.isEmpty) return;
    _addressBook = {..._addressBook, normalized: cleanLabel};
    await _prefs?.setString(_addressBookKey, jsonEncode(_addressBook));
    await _rememberRecipient(normalized);
    _notify('Saved $cleanLabel to address book.');
    notifyListeners();
  }

  Future<void> removeAddressLabel(String address) async {
    _addressBook = {..._addressBook}..remove(address);
    await _prefs?.setString(_addressBookKey, jsonEncode(_addressBook));
    notifyListeners();
  }

  String? labelForAddress(String address) => _addressBook[address.trim()];

  Future<void> clearLogs() async {
    _logs.clear();
    notifyListeners();
  }

  Future<void> _restoreMnemonic(String phrase, {bool refresh = true}) async {
    _mnemonic = phrase;
    _wallet = await Ed25519HDKeyPair.fromMnemonic(phrase);
    final data = await _wallet!.extract();
    _privateKeyBase58 = base58encode(data.bytes);
    if (refresh) await refreshBalance();
  }

  Future<void> _restorePrivateKey(String encoded, {bool refresh = true}) async {
    final bytes = parsePrivateKey(encoded);
    if (bytes == null) {
      throw const FormatException('Invalid Solana private key.');
    }
    _mnemonic = null;
    _privateKeyBase58 = base58encode(bytes);
    _wallet = await Ed25519HDKeyPair.fromPrivateKeyBytes(privateKey: bytes);
    if (refresh) await refreshBalance();
  }

  Future<void> _restoreStoredWallet({bool refresh = true}) async {
    final importType = await _storedImportType();
    if (importType == 'private_key') {
      final savedPrivateKey = await _secureStorage.read(
        key: _walletPrivateKeyKey,
      );
      if (savedPrivateKey == null) {
        throw const FormatException('Missing saved private key.');
      }
      await _restorePrivateKey(savedPrivateKey, refresh: refresh);
    } else if (importType == 'mnemonic') {
      final savedMnemonic = await _secureStorage.read(key: _walletMnemonicKey);
      if (savedMnemonic == null || !bip39.validateMnemonic(savedMnemonic)) {
        throw const FormatException('Missing saved recovery phrase.');
      }
      await _restoreMnemonic(savedMnemonic, refresh: refresh);
    }
  }

  Future<void> _unlock(String message) async {
    await _run(message, () async {
      await _restoreStoredWallet(refresh: false);
      _locked = false;
      await refreshBalance();
    });
  }

  Future<bool> _verifyPin(String pin) async {
    final salt = await _secureStorage.read(key: _pinSaltKey);
    final hash = await _secureStorage.read(key: _pinHashKey);
    return salt != null && hash != null && hashPin(pin, salt) == hash;
  }

  DateTime? _pinLockedUntil() {
    final millis = _prefs?.getInt(_pinLockedUntilKey);
    if (millis == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(millis);
    if (DateTime.now().isAfter(until)) {
      _prefs?.remove(_pinLockedUntilKey);
      return null;
    }
    return until;
  }

  Future<void> _recordFailedPin() async {
    final count = (_prefs?.getInt(_pinFailedCountKey) ?? 0) + 1;
    await _prefs?.setInt(_pinFailedCountKey, count);
    if (count >= 5) {
      await _prefs?.setInt(
        _pinLockedUntilKey,
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
      await _prefs?.setInt(_pinFailedCountKey, 0);
      _log('PIN temporarily locked after failed attempts.', isError: true);
    }
  }

  Future<void> _clearFailedPins() async {
    await _prefs?.remove(_pinFailedCountKey);
    await _prefs?.remove(_pinLockedUntilKey);
  }

  Future<void> _rememberRecipient(String recipient) async {
    final recipients = _knownRecipients().toSet()..add(recipient);
    await _prefs?.setStringList(
      _knownRecipientsKey,
      recipients.toList()..sort(),
    );
  }

  List<String> _knownRecipients() =>
      _prefs?.getStringList(_knownRecipientsKey) ?? const [];

  bool isKnownRecipient(String recipient) =>
      _knownRecipients().contains(recipient.trim());

  Future<void> _refreshActivity() async {
    try {
      final signatures = await _client.rpcClient.getSignaturesForAddress(
        address,
        limit: 8,
        commitment: Commitment.confirmed,
      );
      _activity = [
        for (final item in signatures)
          ActivityEntry(
            signature: item.signature,
            subtitle: item.err == null
                ? (item.confirmationStatus?.name ?? 'confirmed')
                : 'failed',
            memo: item.memo,
            time: item.blockTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(item.blockTime! * 1000),
            failed: item.err != null,
          ),
      ];
    } catch (error, stackTrace) {
      _setFriendlyError(
        'Activity could not be refreshed right now.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _refreshTokens() async {
    try {
      final result = await _client.rpcClient.getTokenAccountsByOwner(
        address,
        const dto.TokenAccountsFilter.byProgramId(TokenProgram.programId),
        commitment: Commitment.confirmed,
        encoding: dto.Encoding.jsonParsed,
      );
      final balances = <TokenBalance>[];
      for (final account in result.value.take(12)) {
        try {
          final balance = await _client.rpcClient.getTokenAccountBalance(
            account.pubkey,
            commitment: Commitment.confirmed,
          );
          final amount = balance.value.uiAmountString ?? balance.value.amount;
          if (amount == '0' || amount == '0.0') continue;
          balances.add(
            TokenBalance(account.pubkey, amount, balance.value.decimals),
          );
        } catch (_) {
          continue;
        }
      }
      _tokens = balances;
    } catch (error, stackTrace) {
      _log('Token refresh failed.\n$error\n$stackTrace', isError: true);
    }
  }

  Future<String?> _storedImportType() async {
    final importType = _prefs?.getString(_walletImportTypeKey);
    if (importType != null) return importType;
    if (await _secureStorage.read(key: _walletPrivateKeyKey) != null) {
      return 'private_key';
    }
    if (await _secureStorage.read(key: _walletMnemonicKey) != null) {
      return 'mnemonic';
    }
    return null;
  }

  Future<void> _migratePlaintextSecrets() async {
    final oldPrivateKey = _prefs?.getString(_walletPrivateKeyKey);
    final oldMnemonic = _prefs?.getString(_walletMnemonicKey);
    if (oldPrivateKey != null &&
        await _secureStorage.read(key: _walletPrivateKeyKey) == null) {
      await _secureStorage.write(
        key: _walletPrivateKeyKey,
        value: oldPrivateKey,
      );
      await _prefs?.setString(_walletImportTypeKey, 'private_key');
      await _prefs?.remove(_walletPrivateKeyKey);
      _log('Migrated private key into secure storage.');
    }
    if (oldMnemonic != null &&
        await _secureStorage.read(key: _walletMnemonicKey) == null) {
      await _secureStorage.write(key: _walletMnemonicKey, value: oldMnemonic);
      await _prefs?.setString(_walletImportTypeKey, 'mnemonic');
      await _prefs?.remove(_walletMnemonicKey);
      _log('Migrated recovery phrase into secure storage.');
    }
  }

  Future<bool> _canUseBiometrics() async {
    try {
      return await _localAuth.isDeviceSupported().timeout(
            const Duration(milliseconds: 400),
            onTimeout: () => false,
          ) &&
          await _localAuth.canCheckBiometrics.timeout(
            const Duration(milliseconds: 400),
            onTimeout: () => false,
          );
    } catch (_) {
      return false;
    }
  }

  Future<void> _run(String success, Future<void> Function() task) async {
    _busy = true;
    _status = null;
    notifyListeners();
    try {
      await task();
      _status ??= success;
      _log(success);
    } catch (error) {
      _setFriendlyError(friendlyError(error), error, StackTrace.current);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _setFriendlyError(String message, Object error, StackTrace stackTrace) {
    _status = message;
    _log('$message\n$error\n$stackTrace', isError: true);
  }

  void _log(String message, {bool isError = false}) {
    if (!_diagnosticsEnabled) return;
    _logs.add(DiagnosticEntry(DateTime.now(), message, isError: isError));
    if (_logs.length > 80) _logs.removeAt(0);
  }

  void _notify(String message) {
    _notifications = [
      AppNotification(DateTime.now(), message),
      ..._notifications,
    ].take(8).toList();
    _log(message);
  }
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key});

  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> with WidgetsBindingObserver {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final wallet = WalletScope.of(context);
      if (wallet.autoLockEnabled && wallet.pinEnabled && wallet.hasWallet) {
        wallet.lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: wallet.loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final content =
                      wallet.locked ||
                          (wallet.hasStoredWallet && !wallet.hasWallet)
                      ? const _UnlockScreen()
                      : wallet.backupRequired
                      ? const _BackupRequiredScreen()
                      : wallet.hasWallet
                      ? switch (_selectedTab) {
                          1 => _MarketPage(wide: wide),
                          3 => _ProfilePage(wide: wide),
                          _ => _WalletContent(wide: wide),
                        }
                      : const _Onboarding();

                  if (!wide) {
                    return Column(
                      children: [
                        Expanded(child: content),
                        if (wallet.hasWallet && !wallet.locked)
                          _BottomNav(
                            selectedTab: _selectedTab,
                            onChanged: (value) =>
                                setState(() => _selectedTab = value),
                          ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      if (wallet.hasWallet && !wallet.locked)
                        _SideNav(
                          selectedTab: _selectedTab,
                          onChanged: (value) =>
                              setState(() => _selectedTab = value),
                        ),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding();

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _phraseController = TextEditingController();
  final _privateKeyController = TextEditingController();

  @override
  void dispose() {
    _phraseController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _Panel(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    'assets/brand/unite_logo.png',
                    width: 74,
                    height: 74,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unite',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create or import a Solana wallet. Unite starts on devnet so transfers can be tested without real SOL.',
                  style: TextStyle(color: _muted, height: 1.35),
                ),
                const SizedBox(height: 18),
                _PrimaryButton(
                  icon: Icons.add_rounded,
                  label: 'Create Solana wallet',
                  onPressed: wallet.busy ? null : wallet.createWallet,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _phraseController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Recovery phrase',
                    hintText: 'twelve or twenty four words',
                  ),
                ),
                const SizedBox(height: 10),
                _SecondaryButton(
                  icon: Icons.input_rounded,
                  label: 'Import recovery phrase',
                  onPressed: wallet.busy
                      ? null
                      : () => wallet.importWallet(_phraseController.text),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _privateKeyController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Private key',
                    hintText: 'base58 key or JSON byte array',
                  ),
                ),
                const SizedBox(height: 10),
                _SecondaryButton(
                  icon: Icons.vpn_key_outlined,
                  label: 'Import private key',
                  onPressed: wallet.busy
                      ? null
                      : () =>
                            wallet.importPrivateKey(_privateKeyController.text),
                ),
                if (wallet.status != null) ...[
                  const SizedBox(height: 12),
                  _StatusLine(message: wallet.status!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen();

  @override
  State<_UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<_UnlockScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _Panel(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    'assets/brand/unite_logo.png',
                    width: 64,
                    height: 64,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unlock Unite',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your wallet is stored on this device.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 18),
                if (wallet.pinEnabled) ...[
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: _muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryButton(
                    icon: Icons.lock_open_rounded,
                    label: wallet.busy ? 'Unlocking...' : 'Unlock',
                    onPressed: wallet.busy
                        ? null
                        : () => wallet.unlockWithPin(_pinController.text),
                  ),
                  if (wallet.biometricsAvailable) ...[
                    const SizedBox(height: 10),
                    _SecondaryButton(
                      icon: Icons.fingerprint_rounded,
                      label: 'Use biometrics',
                      onPressed: wallet.busy
                          ? null
                          : wallet.unlockWithBiometrics,
                    ),
                  ],
                ] else
                  _PrimaryButton(
                    icon: Icons.lock_open_rounded,
                    label: 'Open wallet',
                    onPressed: wallet.busy
                        ? null
                        : () => wallet.unlockWithPin(''),
                  ),
                if (wallet.status != null) ...[
                  const SizedBox(height: 12),
                  _StatusLine(message: wallet.status!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupRequiredScreen extends StatefulWidget {
  const _BackupRequiredScreen();

  @override
  State<_BackupRequiredScreen> createState() => _BackupRequiredScreenState();
}

class _BackupRequiredScreenState extends State<_BackupRequiredScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: _Panel(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Back up your wallet',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This recovery phrase is the only way to recover this wallet on a new device. Store it offline and never share it.',
                  style: TextStyle(
                    color: _warning,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _Panel(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    wallet.mnemonic ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SecondaryButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy recovery phrase',
                  onPressed: () => copyMnemonic(context),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _saved,
                  activeColor: Colors.white,
                  checkColor: Colors.black,
                  title: const Text(
                    'I saved this recovery phrase somewhere safe.',
                  ),
                  onChanged: (value) => setState(() => _saved = value ?? false),
                ),
                _PrimaryButton(
                  icon: Icons.check_rounded,
                  label: 'Continue to wallet',
                  onPressed: _saved ? wallet.confirmBackupSaved : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletContent extends StatelessWidget {
  const _WalletContent({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final rail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _ReceiveCard(),
        SizedBox(height: 14),
        _SendCard(),
        SizedBox(height: 14),
        _ActivityCard(),
      ],
    );

    final dashboard = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 20),
        const _BalanceCard(),
        const SizedBox(height: 16),
        const _QuickActions(),
        const SizedBox(height: 18),
        _SectionHeader(
          title: 'Assets',
          action: WalletScope.of(context).activeCluster.label,
        ),
        const SizedBox(height: 10),
        const _AssetList(),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 34 : 16,
        16,
        wide ? 34 : 16,
        wide ? 28 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: dashboard),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: rail),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [dashboard, const SizedBox(height: 18), rail],
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    Widget identity({required bool expanded}) {
      final content = Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/brand/unite_logo.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unite',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  shortAddress(wallet.address),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
      return expanded ? Expanded(child: content) : content;
    }

    Widget networkPicker() {
      return DropdownButtonHideUnderline(
        child: Container(
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: _control,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: DropdownButton<String>(
            value: wallet.cluster,
            dropdownColor: _panelRaised,
            borderRadius: BorderRadius.circular(18),
            items: [
              for (final cluster in SolanaCluster.values)
                DropdownMenuItem(
                  value: cluster.id,
                  child: Text(
                    cluster.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
            onChanged: wallet.busy || !wallet.hasWallet
                ? null
                : (value) => wallet.switchCluster(value!),
          ),
        ),
      );
    }

    final refreshButton = _IconPill(
      icon: Icons.refresh_rounded,
      label: 'Refresh',
      onTap: wallet.refreshBalance,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity(expanded: false),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: networkPicker()),
                  const SizedBox(width: 8),
                  refreshButton,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            identity(expanded: true),
            networkPicker(),
            const SizedBox(width: 8),
            refreshButton,
          ],
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SoftLabel(icon: Icons.wallet_rounded, label: 'Solana'),
              const Spacer(),
              _Badge(icon: Icons.shield_outlined, label: 'Self-custody'),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              wallet.privacyMode
                  ? '•••• SOL'
                  : '${formatSol(wallet.lamports)} SOL',
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _ToneChip(
                icon: wallet.activeCluster.id == SolanaCluster.devnet.id
                    ? Icons.science_outlined
                    : Icons.public_rounded,
                label: wallet.activeCluster.id == SolanaCluster.devnet.id
                    ? 'Devnet testing'
                    : 'Mainnet wallet',
                color: wallet.activeCluster.id == SolanaCluster.devnet.id
                    ? _warning
                    : _positive,
              ),
            ],
          ),
          if (wallet.status != null) ...[
            const SizedBox(height: 12),
            _StatusLine(message: wallet.status!),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final actions = [
      _ActionItem(Icons.arrow_upward_rounded, 'Send', () {}),
      _ActionItem(
        Icons.arrow_downward_rounded,
        'Receive',
        () => copyAddress(context),
      ),
      _ActionItem(Icons.water_drop_outlined, 'Airdrop', wallet.requestAirdrop),
      _ActionItem(Icons.refresh_rounded, 'Refresh', wallet.refreshBalance),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          onTap: wallet.busy ? null : action.onTap,
          borderRadius: BorderRadius.circular(22),
          child: _Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _CircleIcon(icon: action.icon),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AssetList extends StatelessWidget {
  const _AssetList();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _AssetTile(
            name: 'Solana',
            symbol: 'SOL',
            amount: wallet.privacyMode ? '••••' : formatSol(wallet.lamports),
            value: wallet.privacyMode
                ? 'Hidden'
                : '${wallet.lamports} lamports',
            color: _mint,
          ),
          for (final token in wallet.tokens) ...[
            const Divider(color: _line, height: 1),
            _AssetTile(
              name: 'SPL Token',
              symbol: 'SPL',
              amount: wallet.privacyMode ? '••••' : token.amount,
              value: '${token.decimals} decimals',
              color: const Color(0xFF8EA7FF),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.name,
    required this.symbol,
    required this.amount,
    required this.value,
    required this.color,
  });

  final String name;
  final String symbol;
  final String amount;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              symbol[0],
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '$amount $symbol',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _control,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: _softText,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiveCard extends StatelessWidget {
  const _ReceiveCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Receive SOL',
            action: 'Copy',
            onAction: () => copyAddress(context),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: solanaPayUri(wallet.address),
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Solana address',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SelectableText(
            shortAddress(wallet.address),
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            icon: Icons.qr_code_rounded,
            label: 'Copy payment link',
            onPressed: () => copyPaymentLink(context),
          ),
        ],
      ),
    );
  }
}

class _SendCard extends StatefulWidget {
  const _SendCard();

  @override
  State<_SendCard> createState() => _SendCardState();
}

class _SendCardState extends State<_SendCard> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Send SOL',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _recipientController,
            decoration: const InputDecoration(
              labelText: 'Recipient address',
              prefixIcon: Icon(
                Icons.account_balance_wallet_outlined,
                color: _muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    suffixText: 'SOL',
                    prefixIcon: Icon(Icons.numbers_rounded, color: _muted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 68,
                height: 52,
                child: OutlinedButton(
                  onPressed: wallet.maxSendLamports > 0
                      ? () => _amountController.text = formatSol(
                          wallet.maxSendLamports,
                        )
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Max',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _memoController,
                  decoration: const InputDecoration(
                    labelText: 'Memo',
                    prefixIcon: Icon(Icons.notes_rounded, color: _muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PrimaryButton(
            icon: Icons.lock_outline_rounded,
            label: wallet.busy ? 'Working...' : 'Sign and send',
            onPressed: wallet.busy
                ? null
                : () => showSendPreview(
                    context: context,
                    recipient: _recipientController.text,
                    amount: _amountController.text,
                    memo: _memoController.text,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 34 : 16,
        16,
        wide ? 34 : 16,
        wide ? 28 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 20),
              _Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ProfileRow(
                      label: 'Address',
                      value: wallet.address,
                      action: 'Copy',
                      onAction: () => copyAddress(context),
                    ),
                    const Divider(color: _line, height: 24),
                    _ProfileRow(
                      label: 'Network',
                      value: wallet.activeCluster.label,
                    ),
                    const Divider(color: _line, height: 24),
                    _ProfileRow(
                      label: 'Balance',
                      value: wallet.privacyMode
                          ? 'Hidden'
                          : '${formatSol(wallet.lamports)} SOL',
                    ),
                    const Divider(color: _line, height: 24),
                    _ProfileRow(
                      label: 'RPC slot',
                      value: wallet.rpcSlot?.toString() ?? 'Not checked',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _SettingsCard(),
              const SizedBox(height: 14),
              const _AddressBookCard(),
              const SizedBox(height: 14),
              const _SecretVaultCard(),
              const SizedBox(height: 14),
              const _DiagnosticsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketPage extends StatelessWidget {
  const _MarketPage({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final sol = wallet.marketAssets.firstWhere(
      (asset) => asset.symbol == 'SOL',
      orElse: () => MarketAsset.defaults.first,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 34 : 16,
        16,
        wide ? 34 : 16,
        wide ? 28 : 104,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 20),
              _Panel(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Market',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _IconPill(
                          icon: Icons.refresh_rounded,
                          label: 'Refresh market',
                          onTap: wallet.marketLoading
                              ? null
                              : wallet.refreshMarket,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      wallet.marketUpdatedAt == null
                          ? 'Public CoinGecko market data'
                          : 'Updated ${formatTime(wallet.marketUpdatedAt!)}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        sol.priceUsd == null
                            ? 'SOL price unavailable'
                            : '\$${formatUsd(sol.priceUsd!)}',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ChangeText(change: sol.change24h),
                    if (wallet.marketStatus != null) ...[
                      const SizedBox(height: 12),
                      _StatusLine(message: wallet.marketStatus!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: wallet.marketAssets.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: columns == 1 ? 3.55 : 3.25,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemBuilder: (context, index) =>
                        _MarketAssetTile(asset: wallet.marketAssets[index]),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketAssetTile extends StatelessWidget {
  const _MarketAssetTile({required this.asset});

  final MarketAsset asset;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => showMarketAssetSheet(context, asset),
      child: _Panel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _MarketIcon(asset: asset, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    asset.rank == null
                        ? asset.symbol
                        : '${asset.symbol}  #${asset.rank}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted),
                  ),
                ],
              ),
            ),
            if (asset.sparkline.length > 2) ...[
              SizedBox(
                width: 96,
                height: 42,
                child: _SparklineChart(
                  points: asset.sparkline,
                  color: (asset.change7d ?? asset.change24h ?? 0) >= 0
                      ? _positive
                      : _danger,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  asset.priceUsd == null
                      ? '--'
                      : '\$${formatUsd(asset.priceUsd!)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                _ChangeText(change: asset.change24h),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketIcon extends StatelessWidget {
  const _MarketIcon({required this.asset, required this.size});

  final MarketAsset asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: asset.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: asset.color.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        asset.symbol[0],
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    if (asset.imageUrl == null || asset.imageUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        asset.imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

class _SparklineChart extends StatelessWidget {
  const _SparklineChart({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(points: points, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    final minValue = points.reduce(min);
    final maxValue = points.reduce(max);
    final range = max(maxValue - minValue, 0.00000001);
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = index / (points.length - 1) * size.width;
      final y =
          size.height - ((points[index] - minValue) / range * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

void showMarketAssetSheet(BuildContext context, MarketAsset asset) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _ink,
    barrierColor: Colors.black87,
    builder: (context) => _MarketAssetSheet(asset: asset),
  );
}

class _MarketAssetSheet extends StatelessWidget {
  const _MarketAssetSheet({required this.asset});

  final MarketAsset asset;

  @override
  Widget build(BuildContext context) {
    final graphColor = (asset.change7d ?? asset.change24h ?? 0) >= 0
        ? _positive
        : _danger;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _MarketIcon(asset: asset, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            asset.rank == null
                                ? asset.symbol
                                : '${asset.symbol} rank #${asset.rank}',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    asset.priceUsd == null
                        ? '--'
                        : '\$${formatUsd(asset.priceUsd!)}',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ChangeChip(label: '1h', change: asset.change1h),
                    _ChangeChip(label: '24h', change: asset.change24h),
                    _ChangeChip(label: '7d', change: asset.change7d),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  height: 190,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _control,
                    border: Border.all(color: _softLine),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: asset.sparkline.length < 2
                      ? const Center(
                          child: Text(
                            'Chart unavailable',
                            style: TextStyle(color: _muted),
                          ),
                        )
                      : _SparklineChart(
                          points: asset.sparkline,
                          color: graphColor,
                        ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MarketStat(
                      label: 'Market cap',
                      value: asset.marketCap == null
                          ? '--'
                          : '\$${formatCompactUsd(asset.marketCap!)}',
                    ),
                    _MarketStat(
                      label: '24h volume',
                      value: asset.volume24h == null
                          ? '--'
                          : '\$${formatCompactUsd(asset.volume24h!)}',
                    ),
                    _MarketStat(
                      label: '24h high',
                      value: asset.high24h == null
                          ? '--'
                          : '\$${formatUsd(asset.high24h!)}',
                    ),
                    _MarketStat(
                      label: '24h low',
                      value: asset.low24h == null
                          ? '--'
                          : '\$${formatUsd(asset.low24h!)}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Charts and prices are third-party market data, not trading advice.',
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.label, required this.change});

  final String label;
  final double? change;

  @override
  Widget build(BuildContext context) {
    final positive = (change ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _control,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        change == null
            ? '$label --'
            : '$label ${positive ? '+' : ''}${change!.toStringAsFixed(2)}%',
        style: TextStyle(
          color: change == null ? _muted : (positive ? _positive : _danger),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MarketStat extends StatelessWidget {
  const _MarketStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _control,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ChangeText extends StatelessWidget {
  const _ChangeText({required this.change});

  final double? change;

  @override
  Widget build(BuildContext context) {
    if (change == null) {
      return const Text('--', style: TextStyle(color: _muted));
    }
    final positive = change! >= 0;
    return Text(
      '${positive ? '+' : ''}${change!.toStringAsFixed(2)}% 24h',
      style: TextStyle(
        color: positive ? _positive : _danger,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
    this.action,
    this.onAction,
  });

  final String label;
  final String value;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(color: _muted)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: wallet.diagnosticsEnabled,
            activeThumbColor: Colors.white,
            title: const Text('Diagnostics logs'),
            subtitle: const Text(
              'Keep local troubleshooting logs. Secrets are never logged.',
              style: TextStyle(color: _muted),
            ),
            onChanged: wallet.setDiagnosticsEnabled,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: wallet.privacyMode,
            activeThumbColor: Colors.white,
            title: const Text('Privacy mode'),
            subtitle: const Text(
              'Hide balances from the main screens.',
              style: TextStyle(color: _muted),
            ),
            onChanged: wallet.setPrivacyMode,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: wallet.autoLockEnabled,
            activeThumbColor: Colors.white,
            title: const Text('Auto-lock on background'),
            subtitle: const Text(
              'Lock Unite when the app leaves the foreground.',
              style: TextStyle(color: _muted),
            ),
            onChanged: wallet.pinEnabled ? wallet.setAutoLockEnabled : null,
          ),
          const Divider(color: _line, height: 24),
          _ProfileRow(
            label: 'RPC',
            value: wallet.activeCluster.rpcUrl,
            action: 'Edit',
            onAction: () => showRpcDialog(context),
          ),
          const Divider(color: _line, height: 24),
          Text(
            wallet.pinEnabled ? 'PIN lock is on' : 'PIN lock is off',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.pin_outlined,
                  label: wallet.pinEnabled ? 'Change PIN' : 'Set PIN',
                  onPressed: wallet.busy ? null : () => showPinDialog(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.lock_outline_rounded,
                  label: 'Lock now',
                  onPressed: wallet.pinEnabled && !wallet.busy
                      ? wallet.lock
                      : null,
                ),
              ),
            ],
          ),
          if (wallet.pinEnabled) ...[
            const SizedBox(height: 10),
            _SecondaryButton(
              icon: Icons.lock_open_rounded,
              label: 'Remove PIN lock',
              onPressed: wallet.busy ? null : wallet.removePin,
            ),
          ],
          const SizedBox(height: 10),
          _SecondaryButton(
            icon: Icons.delete_outline_rounded,
            label: 'Remove wallet from device',
            onPressed: wallet.busy ? null : wallet.clearWallet,
          ),
        ],
      ),
    );
  }
}

class _AddressBookCard extends StatefulWidget {
  const _AddressBookCard();

  @override
  State<_AddressBookCard> createState() => _AddressBookCardState();
}

class _AddressBookCardState extends State<_AddressBookCard> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Address book',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Solana address',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            icon: Icons.bookmark_add_outlined,
            label: 'Save address',
            onPressed: () async {
              await wallet.saveAddressLabel(
                _addressController.text,
                _labelController.text,
              );
              _addressController.clear();
              _labelController.clear();
            },
          ),
          const SizedBox(height: 12),
          if (wallet.addressBook.isEmpty)
            const Text(
              'No saved addresses yet.',
              style: TextStyle(color: _muted),
            )
          else
            for (final entry in wallet.addressBook.entries)
              _ProfileRow(
                label: entry.value,
                value: shortAddress(entry.key),
                action: 'Remove',
                onAction: () => wallet.removeAddressLabel(entry.key),
              ),
        ],
      ),
    );
  }
}

class _SecretVaultCard extends StatefulWidget {
  const _SecretVaultCard();

  @override
  State<_SecretVaultCard> createState() => _SecretVaultCardState();
}

class _SecretVaultCardState extends State<_SecretVaultCard> {
  bool _acceptedWarning = false;
  bool _showSecrets = false;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final hasMnemonic = wallet.mnemonic != null;
    final privateKey = wallet.privateKeyBase58 ?? '';
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Secret vault',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            'Never share your recovery phrase or private key. Unite support will never ask for it. Anyone with these secrets can steal every asset in this wallet.',
            style: TextStyle(
              color: _warning,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acceptedWarning,
            activeColor: Colors.white,
            checkColor: Colors.black,
            title: const Text(
              'I understand this can give full control of my wallet.',
            ),
            onChanged: (value) {
              setState(() {
                _acceptedWarning = value ?? false;
                if (!_acceptedWarning) _showSecrets = false;
              });
            },
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            icon: _showSecrets
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            label: _showSecrets ? 'Hide secrets' : 'Reveal secrets',
            onPressed: _acceptedWarning
                ? () => setState(() => _showSecrets = !_showSecrets)
                : null,
          ),
          if (_showSecrets) ...[
            const SizedBox(height: 14),
            if (hasMnemonic) ...[
              _SectionHeader(
                title: 'Recovery phrase',
                action: 'Copy',
                onAction: () => copyMnemonic(context),
              ),
              const SizedBox(height: 8),
              SelectableText(
                wallet.mnemonic!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
            ],
            _SectionHeader(
              title: 'Private key',
              action: 'Copy',
              onAction: () => copyPrivateKey(context),
            ),
            const SizedBox(height: 8),
            SelectableText(
              privateKey,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Diagnostics',
            action: 'Clear',
            onAction: wallet.clearLogs,
          ),
          const SizedBox(height: 10),
          if (!wallet.diagnosticsEnabled)
            const Text(
              'Diagnostics are turned off.',
              style: TextStyle(color: _muted),
            )
          else if (wallet.logs.isEmpty)
            const Text(
              'No diagnostic events yet.',
              style: TextStyle(color: _muted),
            )
          else
            for (final entry in wallet.logs.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${formatTime(entry.time)}  ${entry.message}',
                  style: TextStyle(
                    color: entry.isError ? _danger : _muted,
                    height: 1.3,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Network', action: 'Live RPC'),
          const SizedBox(height: 12),
          if (wallet.notifications.isNotEmpty) ...[
            for (final note in wallet.notifications.take(3))
              _ActivityRow(
                icon: Icons.notifications_none_rounded,
                title: note.message,
                subtitle: formatTime(note.time),
                value: 'New',
                color: _positive,
              ),
            const Divider(color: _line),
          ],
          if (wallet.activity.isNotEmpty) ...[
            for (final activity in wallet.activity.take(4))
              InkWell(
                onTap: () =>
                    copyText(context, activity.signature, 'Signature copied'),
                child: _ActivityRow(
                  icon: activity.failed
                      ? Icons.error_outline_rounded
                      : Icons.receipt_long_outlined,
                  title: shortHash(activity.signature),
                  subtitle: activity.memo?.isNotEmpty == true
                      ? activity.memo!
                      : (activity.time == null
                            ? 'Recent transaction'
                            : formatTime(activity.time!)),
                  value: activity.failed ? 'Failed' : activity.subtitle,
                  color: activity.failed ? _danger : _positive,
                ),
              ),
            const Divider(color: _line),
          ],
          _ActivityRow(
            icon: Icons.hub_outlined,
            title: wallet.activeCluster.label,
            subtitle: wallet.rpcSlot == null
                ? wallet.activeCluster.rpcUrl
                : 'Slot ${wallet.rpcSlot}',
            value: wallet.busy
                ? 'Syncing'
                : (wallet.rpcSlot == null ? 'Unchecked' : 'Ready'),
            color: wallet.busy ? _warning : _positive,
          ),
          _ActivityRow(
            icon: Icons.payments_outlined,
            title: 'Spendable balance',
            subtitle: 'Network fees are paid in SOL',
            value: '${formatSol(max(0, wallet.lamports - 5000))} SOL',
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _CircleIcon(icon: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.selectedTab, required this.onChanged});

  final int selectedTab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Image.asset('assets/brand/unite_logo.png', width: 38, height: 38),
          const SizedBox(height: 28),
          for (final item in _navItems)
            _NavButton(
              item: item,
              selected: selectedTab == item.index,
              onTap: () => onChanged(item.index),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedTab, required this.onChanged});

  final int selectedTab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final item in _navItems)
            _NavButton(
              item: item,
              selected: selectedTab == item.index,
              onTap: () => onChanged(item.index),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.transparent,
          foregroundColor: selected ? Colors.black : _muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          fixedSize: const Size(48, 48),
        ),
        icon: Icon(item.icon),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(999),
          child: Text(
            action,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: _control,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _line),
          ),
          fixedSize: const Size(44, 44),
        ),
        icon: Icon(icon, size: 21),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _control,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Icon(icon, size: 18),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _control,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SoftLabel extends StatelessWidget {
  const _SoftLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _muted, size: 16),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ToneChip extends StatelessWidget {
  const _ToneChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: _line,
          disabledForegroundColor: _muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final isError =
        lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('not ') ||
        lower.contains('could not') ||
        lower.contains('wrong') ||
        lower.contains('try again') ||
        lower.contains('keep a little');
    return Text(
      message,
      style: TextStyle(
        color: isError ? _danger : _positive,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SolanaCluster {
  const SolanaCluster(this.id, this.label, this.rpcUrl, this.websocketUrl);

  final String id;
  final String label;
  final String rpcUrl;
  final String websocketUrl;

  static const devnet = SolanaCluster(
    'devnet',
    'Devnet',
    'https://api.devnet.solana.com',
    'wss://api.devnet.solana.com',
  );

  static const mainnet = SolanaCluster(
    'mainnet',
    'Mainnet',
    'https://api.mainnet-beta.solana.com',
    'wss://api.mainnet-beta.solana.com',
  );

  static const custom = SolanaCluster(
    'custom',
    'Custom RPC',
    'https://api.devnet.solana.com',
    'wss://api.devnet.solana.com',
  );

  static const values = [devnet, mainnet, custom];

  static SolanaCluster byId(String id) {
    return values.firstWhere(
      (cluster) => cluster.id == id,
      orElse: () => devnet,
    );
  }
}

class _ActionItem {
  const _ActionItem(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _NavItem {
  const _NavItem(this.index, this.icon, this.label);

  final int index;
  final IconData icon;
  final String label;
}

const _navItems = [
  _NavItem(0, Icons.account_balance_wallet_outlined, 'Wallet'),
  _NavItem(1, Icons.candlestick_chart_outlined, 'Market'),
  _NavItem(2, Icons.credit_card_outlined, 'Cards'),
  _NavItem(3, Icons.person_outline_rounded, 'Profile'),
];

class DiagnosticEntry {
  const DiagnosticEntry(this.time, this.message, {required this.isError});

  final DateTime time;
  final String message;
  final bool isError;
}

class TokenBalance {
  const TokenBalance(this.account, this.amount, this.decimals);

  final String account;
  final String amount;
  final int decimals;
}

class ActivityEntry {
  const ActivityEntry({
    required this.signature,
    required this.subtitle,
    required this.memo,
    required this.time,
    required this.failed,
  });

  final String signature;
  final String subtitle;
  final String? memo;
  final DateTime? time;
  final bool failed;
}

class AppNotification {
  const AppNotification(this.time, this.message);

  final DateTime time;
  final String message;
}

class SimulationPreview {
  const SimulationPreview(this.ok, this.message, this.unitsConsumed);

  final bool ok;
  final String message;
  final int? unitsConsumed;
}

class MarketAsset {
  const MarketAsset({
    required this.id,
    required this.name,
    required this.symbol,
    required this.color,
    this.imageUrl,
    this.priceUsd,
    this.change1h,
    this.change24h,
    this.change7d,
    this.volume24h,
    this.marketCap,
    this.high24h,
    this.low24h,
    this.rank,
    this.sparkline = const [],
  });

  final String id;
  final String name;
  final String symbol;
  final Color color;
  final String? imageUrl;
  final double? priceUsd;
  final double? change1h;
  final double? change24h;
  final double? change7d;
  final double? volume24h;
  final double? marketCap;
  final double? high24h;
  final double? low24h;
  final int? rank;
  final List<double> sparkline;

  MarketAsset copyWith({
    String? name,
    String? symbol,
    String? imageUrl,
    double? priceUsd,
    double? change1h,
    double? change24h,
    double? change7d,
    double? volume24h,
    double? marketCap,
    double? high24h,
    double? low24h,
    int? rank,
    List<double>? sparkline,
  }) {
    return MarketAsset(
      id: id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      color: color,
      imageUrl: imageUrl ?? this.imageUrl,
      priceUsd: priceUsd ?? this.priceUsd,
      change1h: change1h ?? this.change1h,
      change24h: change24h ?? this.change24h,
      change7d: change7d ?? this.change7d,
      volume24h: volume24h ?? this.volume24h,
      marketCap: marketCap ?? this.marketCap,
      high24h: high24h ?? this.high24h,
      low24h: low24h ?? this.low24h,
      rank: rank ?? this.rank,
      sparkline: sparkline ?? this.sparkline,
    );
  }

  static const defaults = [
    MarketAsset(id: 'solana', name: 'Solana', symbol: 'SOL', color: _mint),
    MarketAsset(
      id: 'jupiter-exchange-solana',
      name: 'Jupiter',
      symbol: 'JUP',
      color: Color(0xFFFFC766),
    ),
    MarketAsset(
      id: 'jito-governance-token',
      name: 'Jito',
      symbol: 'JTO',
      color: _lavender,
    ),
    MarketAsset(
      id: 'bonk',
      name: 'Bonk',
      symbol: 'BONK',
      color: Color(0xFFFF8E8E),
    ),
    MarketAsset(
      id: 'pyth-network',
      name: 'Pyth Network',
      symbol: 'PYTH',
      color: Color(0xFFB99CFF),
    ),
    MarketAsset(id: 'helium', name: 'Helium', symbol: 'HNT', color: _sky),
  ];
}

String shortAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 5)}...${address.substring(address.length - 5)}';
}

String shortHash(String hash) {
  if (hash.length <= 14) return hash;
  return '${hash.substring(0, 7)}...${hash.substring(hash.length - 7)}';
}

String formatSol(int lamports) {
  final whole = lamports ~/ lamportsPerSol;
  final fractional = (lamports % lamportsPerSol).toString().padLeft(9, '0');
  final trimmed = fractional.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
}

int? solToLamports(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean.startsWith('-')) return null;
  final parts = clean.split('.');
  if (parts.length > 2 ||
      parts.any((part) => part.isEmpty && parts.length == 1)) {
    return null;
  }
  final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 2 ? parts.last : '';
  if (fraction.length > 9 ||
      int.tryParse(fraction.isEmpty ? '0' : fraction) == null) {
    return null;
  }
  return whole * lamportsPerSol + int.parse(fraction.padRight(9, '0'));
}

List<int>? parsePrivateKey(String input) {
  final clean = input.trim();
  if (clean.isEmpty) return null;
  try {
    if (clean.startsWith('[')) {
      final decoded = jsonDecode(clean);
      if (decoded is! List) return null;
      final bytes = decoded
          .map((value) => value is int ? value : -1)
          .toList(growable: false);
      if (bytes.any((value) => value < 0 || value > 255)) return null;
      if (bytes.length == 64) return bytes.take(32).toList(growable: false);
      if (bytes.length == 32) return bytes;
      return null;
    }
    final bytes = base58decode(clean);
    if (bytes.length == 64) return bytes.take(32).toList(growable: false);
    if (bytes.length == 32) return bytes;
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, String> decodeAddressBook(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return {};
    return decoded.map((key, value) => MapEntry(key, value.toString()))
      ..removeWhere(
        (key, value) => !isValidAddress(key) || value.trim().isEmpty,
      );
  } catch (_) {
    return {};
  }
}

double? readDouble(Object? source, String key) {
  if (source is! Map<String, dynamic>) return null;
  final value = source[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? readInt(Object? source, String key) {
  if (source is! Map<String, dynamic>) return null;
  final value = source[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<double> readSparkline(Object? source) {
  if (source is! Map<String, dynamic>) return const [];
  final sparkline = source['sparkline_in_7d'];
  if (sparkline is! Map<String, dynamic>) return const [];
  final prices = sparkline['price'];
  if (prices is! List) return const [];
  return [
    for (final price in prices)
      if (price is num)
        price.toDouble()
      else if (price is String && double.tryParse(price) != null)
        double.parse(price),
  ];
}

String formatUsd(double value) {
  if (value >= 1000) return value.toStringAsFixed(2);
  if (value >= 1) return value.toStringAsFixed(4);
  return value.toStringAsFixed(8);
}

String formatCompactUsd(double value) {
  final absolute = value.abs();
  if (absolute >= 1000000000000) {
    return '${(value / 1000000000000).toStringAsFixed(2)}T';
  }
  if (absolute >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}B';
  }
  if (absolute >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (absolute >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
  return formatUsd(value);
}

String friendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('xmlhttprequest') ||
      text.contains('failed host lookup')) {
    return 'Unite could not reach the Solana network. Check your connection and try again.';
  }
  if (text.contains('airdrop')) {
    return 'Devnet airdrop is busy right now. Wait a moment and try again.';
  }
  if (text.contains('insufficient') || text.contains('funds')) {
    return 'This wallet does not have enough SOL for that transfer and network fees.';
  }
  if (text.contains('blockhash') || text.contains('transaction simulation')) {
    return 'The network rejected this transfer. Refresh your balance and try again.';
  }
  return 'Something went wrong. Try again or check diagnostics in Profile.';
}

String formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String solanaPayUri(String address) => 'solana:$address';

bool isValidUrl(String value) =>
    Uri.tryParse(value.trim())?.hasAbsolutePath == true;

String websocketFromRpc(String rpcUrl) {
  final uri = Uri.parse(rpcUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri.replace(scheme: scheme).toString();
}

bool isValidPin(String pin) => RegExp(r'^\d{6,}$').hasMatch(pin);

String generateSalt() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  return base64UrlEncode(bytes);
}

String hashPin(String pin, String salt) {
  var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
  for (var i = 0; i < _pinHashRounds; i += 1) {
    digest = sha256.convert([...digest, ...utf8.encode('$salt:$pin:$i')]).bytes;
  }
  return base64UrlEncode(digest);
}

Future<void> showPinDialog(BuildContext context) async {
  final wallet = WalletScope.of(context);
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Set PIN lock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN',
                hintText: '6 or more digits',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (pinController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PINs do not match')),
                );
                return;
              }
              await wallet.setPin(pinController.text);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save PIN'),
          ),
        ],
      );
    },
  );
  pinController.dispose();
  confirmController.dispose();
}

Future<void> showRpcDialog(BuildContext context) async {
  final wallet = WalletScope.of(context);
  final rpcController = TextEditingController(text: wallet.customRpcUrl ?? '');
  final wsController = TextEditingController(text: wallet.customWsUrl ?? '');
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Custom RPC'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use your own Helius, QuickNode, Alchemy, Infura, or self-hosted Solana endpoint. Never paste private keys here.',
              style: TextStyle(color: _muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rpcController,
              decoration: const InputDecoration(labelText: 'HTTPS RPC URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: wsController,
              decoration: const InputDecoration(
                labelText: 'Websocket URL optional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await wallet.saveCustomRpc(
                rpcUrl: rpcController.text,
                websocketUrl: wsController.text,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
  rpcController.dispose();
  wsController.dispose();
}

Future<void> showSendPreview({
  required BuildContext context,
  required String recipient,
  required String amount,
  required String memo,
}) async {
  final wallet = WalletScope.of(context);
  final normalizedRecipient = recipient.trim();
  final lamports = solToLamports(amount);
  if (!isValidAddress(normalizedRecipient) ||
      lamports == null ||
      lamports <= 0) {
    await wallet.sendSol(recipient: recipient, amount: amount, memo: memo);
    return;
  }
  final warnings = <String>[
    if (wallet.activeCluster.id == SolanaCluster.mainnet.id &&
        !wallet.mainnetSendConfirmed)
      'Mainnet uses real funds. Review the recipient carefully.',
    if (!wallet.isKnownRecipient(normalizedRecipient))
      'This is a new recipient address.',
    if (lamports > wallet.lamports * 0.9)
      'This transfer uses most of your SOL balance.',
    if (normalizedRecipient == wallet.address)
      'The recipient is your own wallet address.',
  ];
  final recipientLabel = wallet.labelForAddress(normalizedRecipient);
  final simulation = await wallet.simulateSolTransfer(
    recipient: normalizedRecipient,
    lamports: lamports,
    memo: memo,
  );
  if (!context.mounted) return;
  if (!simulation.ok) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(simulation.message)));
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var mainnetAccepted =
          wallet.activeCluster.id != SolanaCluster.mainnet.id ||
          wallet.mainnetSendConfirmed;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text('Review transfer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewLine(
                  label: 'To',
                  value: shortAddress(normalizedRecipient),
                ),
                if (recipientLabel != null)
                  _PreviewLine(label: 'Saved as', value: recipientLabel),
                _PreviewLine(
                  label: 'Amount',
                  value: '${formatSol(lamports)} SOL',
                ),
                _PreviewLine(
                  label: 'Network',
                  value: wallet.activeCluster.label,
                ),
                const _PreviewLine(
                  label: 'Estimated fee',
                  value: '0.000005 SOL',
                ),
                _PreviewLine(
                  label: 'Simulation',
                  value: simulation.unitsConsumed == null
                      ? simulation.message
                      : '${simulation.unitsConsumed} CU',
                ),
                if (memo.trim().isNotEmpty)
                  _PreviewLine(label: 'Memo', value: memo.trim()),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        warning,
                        style: const TextStyle(
                          color: _warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
                if (wallet.activeCluster.id == SolanaCluster.mainnet.id &&
                    !wallet.mainnetSendConfirmed)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: mainnetAccepted,
                    activeColor: Colors.white,
                    checkColor: Colors.black,
                    title: const Text(
                      'I understand this sends real mainnet funds.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => mainnetAccepted = value ?? false),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: mainnetAccepted
                    ? () async {
                        if (wallet.activeCluster.id ==
                                SolanaCluster.mainnet.id &&
                            !wallet.mainnetSendConfirmed) {
                          await wallet.confirmMainnetSends();
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        await wallet.sendSol(
                          recipient: recipient,
                          amount: amount,
                          memo: memo,
                        );
                      }
                    : null,
                child: const Text('Sign and send'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(color: _muted)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> copyAddress(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await Clipboard.setData(ClipboardData(text: wallet.address));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Address copied')));
  }
}

Future<void> copyPaymentLink(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await copyText(context, solanaPayUri(wallet.address), 'Payment link copied');
}

Future<void> copyText(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> copyMnemonic(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await Clipboard.setData(ClipboardData(text: wallet.mnemonic ?? ''));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recovery phrase copied')));
  }
}

Future<void> copyPrivateKey(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await Clipboard.setData(ClipboardData(text: wallet.privateKeyBase58 ?? ''));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Private key copied')));
  }
}
