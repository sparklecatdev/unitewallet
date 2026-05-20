import 'dart:async';
import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/solana.dart';

void main() {
  runApp(const UniteApp());
}

const _ink = Color(0xFF000000);
const _panel = Color(0xFF080808);
const _panelRaised = Color(0xFF101010);
const _line = Color(0xFF242424);
const _muted = Color(0xFF8B8B8B);
const _positive = Color(0xFF41D98D);
const _warning = Color(0xFFFFC766);
const _danger = Color(0xFFFF6B6B);

const _walletMnemonicKey = 'unite.solana.mnemonic';
const _clusterKey = 'unite.solana.cluster';

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
          displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panelRaised,
          hintStyle: const TextStyle(color: _muted),
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _line),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white),
            borderRadius: BorderRadius.circular(8),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _danger),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _danger),
            borderRadius: BorderRadius.circular(8),
          ),
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
  const WalletScope({super.key, required SolanaWalletController controller, required super.child})
    : super(notifier: controller);

  static SolanaWalletController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WalletScope>();
    assert(scope != null, 'WalletScope is missing.');
    return scope!.notifier!;
  }
}

class SolanaWalletController extends ChangeNotifier {
  SolanaWalletController();

  SharedPreferences? _prefs;
  Ed25519HDKeyPair? _wallet;
  String? _mnemonic;
  int _lamports = 0;
  bool _loading = true;
  bool _busy = false;
  String? _status;
  String _cluster = SolanaCluster.devnet.id;

  bool get loading => _loading;
  bool get busy => _busy;
  bool get hasWallet => _wallet != null;
  String? get status => _status;
  String get cluster => _cluster;
  String get address => _wallet?.address ?? '';
  String? get mnemonic => _mnemonic;
  int get lamports => _lamports;
  double get solBalance => _lamports / lamportsPerSol;
  SolanaCluster get activeCluster => SolanaCluster.byId(_cluster);

  SolanaClient get _client => SolanaClient(
    rpcUrl: Uri.parse(activeCluster.rpcUrl),
    websocketUrl: Uri.parse(activeCluster.websocketUrl),
  );

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _cluster = _prefs?.getString(_clusterKey) ?? SolanaCluster.devnet.id;
    final savedMnemonic = _prefs?.getString(_walletMnemonicKey);
    if (savedMnemonic != null && bip39.validateMnemonic(savedMnemonic)) {
      await _restoreMnemonic(savedMnemonic, refresh: false);
      await refreshBalance();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> createWallet() async {
    await _run('Created Solana wallet.', () async {
      final newMnemonic = bip39.generateMnemonic();
      await _prefs?.setString(_walletMnemonicKey, newMnemonic);
      await _restoreMnemonic(newMnemonic);
    });
  }

  Future<void> importWallet(String phrase) async {
    final normalized = phrase.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!bip39.validateMnemonic(normalized)) {
      _status = 'Import failed: enter a valid 12 or 24 word recovery phrase.';
      notifyListeners();
      return;
    }
    await _run('Imported Solana wallet.', () async {
      await _prefs?.setString(_walletMnemonicKey, normalized);
      await _restoreMnemonic(normalized);
    });
  }

  Future<void> switchCluster(String id) async {
    if (_cluster == id) return;
    await _run('Switched to ${SolanaCluster.byId(id).label}.', () async {
      _cluster = id;
      await _prefs?.setString(_clusterKey, id);
      await refreshBalance();
    });
  }

  Future<void> refreshBalance() async {
    if (_wallet == null) return;
    await _run('Balance refreshed.', () async {
      final result = await _client.rpcClient.getBalance(
        address,
        commitment: Commitment.confirmed,
      );
      _lamports = result.value;
    });
  }

  Future<void> requestAirdrop() async {
    final wallet = _wallet;
    if (wallet == null) return;
    if (activeCluster.id != SolanaCluster.devnet.id) {
      _status = 'Airdrop is only available on devnet.';
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

  Future<void> sendSol({required String recipient, required String amount, String? memo}) async {
    final wallet = _wallet;
    if (wallet == null) return;
    final normalizedRecipient = recipient.trim();
    if (!isValidAddress(normalizedRecipient)) {
      _status = 'Send failed: invalid Solana recipient address.';
      notifyListeners();
      return;
    }
    final lamports = solToLamports(amount);
    if (lamports == null || lamports <= 0) {
      _status = 'Send failed: enter a valid SOL amount.';
      notifyListeners();
      return;
    }
    if (lamports >= _lamports) {
      _status = 'Send failed: keep a little SOL for network fees.';
      notifyListeners();
      return;
    }

    await _run('Transfer submitted.', () async {
      final signature = await _client.transferLamports(
        source: wallet,
        destination: Ed25519HDPublicKey.fromBase58(normalizedRecipient),
        lamports: lamports,
        memo: memo?.trim().isEmpty ?? true ? null : memo!.trim(),
        commitment: Commitment.confirmed,
      );
      _status = 'Sent ${formatSol(lamports)} SOL. Signature: ${shortHash(signature)}';
      await refreshBalance();
    });
  }

  Future<void> clearWallet() async {
    await _run('Wallet removed from this device.', () async {
      _wallet?.destroy();
      _wallet = null;
      _mnemonic = null;
      _lamports = 0;
      await _prefs?.remove(_walletMnemonicKey);
    });
  }

  Future<void> _restoreMnemonic(String phrase, {bool refresh = true}) async {
    _mnemonic = phrase;
    _wallet = await Ed25519HDKeyPair.fromMnemonic(phrase);
    if (refresh) await refreshBalance();
  }

  Future<void> _run(String success, Future<void> Function() task) async {
    _busy = true;
    _status = null;
    notifyListeners();
    try {
      await task();
      _status ??= success;
    } catch (error) {
      _status = 'Network error: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key});

  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: wallet.loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final content = wallet.hasWallet ? _WalletContent(wide: wide) : const _Onboarding();

                  if (!wide) {
                    return Column(
                      children: [
                        Expanded(child: content),
                        if (wallet.hasWallet)
                          _BottomNav(
                            selectedTab: _selectedTab,
                            onChanged: (value) => setState(() => _selectedTab = value),
                          ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      if (wallet.hasWallet)
                        _SideNav(
                          selectedTab: _selectedTab,
                          onChanged: (value) => setState(() => _selectedTab = value),
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

  @override
  void dispose() {
    _phraseController.dispose();
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
                  child: Image.asset('assets/brand/unite_logo.png', width: 74, height: 74),
                ),
                const SizedBox(height: 18),
                const Text('Unite', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
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
                  label: 'Import wallet',
                  onPressed: wallet.busy ? null : () => wallet.importWallet(_phraseController.text),
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
        _SecurityCard(),
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
        _SectionHeader(title: 'Assets', action: WalletScope.of(context).activeCluster.label),
        const SizedBox(height: 10),
        const _AssetList(),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 24),
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
                  children: [
                    dashboard,
                    const SizedBox(height: 18),
                    rail,
                  ],
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
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset('assets/brand/unite_logo.png', width: 44, height: 44, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Unite', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(shortAddress(wallet.address), style: const TextStyle(color: _muted)),
            ],
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: wallet.cluster,
            dropdownColor: _panelRaised,
            borderRadius: BorderRadius.circular(8),
            items: [
              for (final cluster in SolanaCluster.values)
                DropdownMenuItem(value: cluster.id, child: Text(cluster.label)),
            ],
            onChanged: wallet.busy || !wallet.hasWallet ? null : (value) => wallet.switchCluster(value!),
          ),
        ),
        const SizedBox(width: 8),
        _IconPill(icon: Icons.refresh_rounded, label: 'Refresh', onTap: wallet.refreshBalance),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Solana balance', style: TextStyle(color: _muted)),
              const Spacer(),
              _Badge(icon: Icons.shield_outlined, label: 'Self-custody'),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${formatSol(wallet.lamports)} SOL', style: Theme.of(context).textTheme.displayLarge),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(wallet.activeCluster.id == SolanaCluster.devnet.id ? Icons.science_outlined : Icons.public_rounded,
                  color: wallet.activeCluster.id == SolanaCluster.devnet.id ? _warning : _positive, size: 18),
              const SizedBox(width: 6),
              Text(
                wallet.activeCluster.id == SolanaCluster.devnet.id ? 'Devnet testing wallet' : 'Mainnet wallet',
                style: TextStyle(
                  color: wallet.activeCluster.id == SolanaCluster.devnet.id ? _warning : _positive,
                  fontWeight: FontWeight.w700,
                ),
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
      _ActionItem(Icons.arrow_downward_rounded, 'Receive', () => copyAddress(context)),
      _ActionItem(Icons.water_drop_outlined, 'Airdrop', wallet.requestAirdrop),
      _ActionItem(Icons.refresh_rounded, 'Refresh', wallet.refreshBalance),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 76,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          onTap: wallet.busy ? null : action.onTap,
          borderRadius: BorderRadius.circular(8),
          child: _Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _CircleIcon(icon: action.icon),
                const SizedBox(width: 10),
                Flexible(child: Text(action.label, style: const TextStyle(fontWeight: FontWeight.w800))),
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
            amount: formatSol(wallet.lamports),
            value: '${wallet.lamports} lamports',
            color: const Color(0xFF66F6C6),
          ),
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
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(symbol[0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('$amount $symbol', style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          Text(value, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Receive SOL', action: 'Copy', onAction: () => copyAddress(context)),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(10),
              child: QrImageView(data: wallet.address, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Solana address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SelectableText(shortAddress(wallet.address), style: const TextStyle(color: _muted)),
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Send SOL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: _recipientController,
            decoration: const InputDecoration(
              labelText: 'Recipient address',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: _muted),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    suffixText: 'SOL',
                    prefixIcon: Icon(Icons.numbers_rounded, color: _muted),
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
                : () => wallet.sendSol(
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

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Recovery', action: 'Copy', onAction: () => copyMnemonic(context)),
          const SizedBox(height: 10),
          const Text(
            'Stored locally for this first Solana build. Treat it like a hot wallet and do not use a mainnet phrase yet.',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          SelectableText(
            wallet.mnemonic ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 14),
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
          _ActivityRow(
            icon: Icons.hub_outlined,
            title: wallet.activeCluster.label,
            subtitle: wallet.activeCluster.rpcUrl,
            value: wallet.busy ? 'Syncing' : 'Ready',
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(subtitle, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
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
      decoration: const BoxDecoration(color: _ink, border: Border(right: BorderSide(color: _line))),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Image.asset('assets/brand/unite_logo.png', width: 38, height: 38),
          const SizedBox(height: 28),
          for (final item in _navItems)
            _NavButton(item: item, selected: selectedTab == item.index, onTap: () => onChanged(item.index)),
          const Spacer(),
          _IconPill(icon: Icons.person_outline_rounded, label: 'Profile', onTap: () {}),
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
      decoration: const BoxDecoration(color: _ink, border: Border(top: BorderSide(color: _line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final item in _navItems)
            _NavButton(item: item, selected: selectedTab == item.index, onTap: () => onChanged(item.index)),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, this.onAction});

  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        InkWell(
          onTap: onAction,
          child: Text(action, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.label, required this.onTap});

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
          backgroundColor: _panelRaised,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      decoration: const BoxDecoration(color: _panelRaised, shape: BoxShape.circle),
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
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.icon, required this.label, required this.onPressed});

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.icon, required this.label, required this.onPressed});

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    final isError = message.toLowerCase().contains('failed') || message.toLowerCase().contains('error');
    return Text(
      message,
      style: TextStyle(color: isError ? _danger : _positive, fontWeight: FontWeight.w700),
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

  static const values = [devnet, mainnet];

  static SolanaCluster byId(String id) {
    return values.firstWhere((cluster) => cluster.id == id, orElse: () => devnet);
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
  _NavItem(3, Icons.explore_outlined, 'Explore'),
];

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
  if (parts.length > 2 || parts.any((part) => part.isEmpty && parts.length == 1)) return null;
  final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 2 ? parts.last : '';
  if (fraction.length > 9 || int.tryParse(fraction.isEmpty ? '0' : fraction) == null) return null;
  return whole * lamportsPerSol + int.parse(fraction.padRight(9, '0'));
}

Future<void> copyAddress(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await Clipboard.setData(ClipboardData(text: wallet.address));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
  }
}

Future<void> copyMnemonic(BuildContext context) async {
  final wallet = WalletScope.of(context);
  await Clipboard.setData(ClipboardData(text: wallet.mnemonic ?? ''));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery phrase copied')));
  }
}
