import 'package:flutter/material.dart';
import 'mqtt_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GreenhouseApp());
}

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Greenhouse Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1217),
        cardColor: const Color(0xFF171D26),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF29B6F6),
          surface: Color(0xFF171D26),
        ),
      ),
      home: const GreenhouseDashboard(),
    );
  }
}

class GreenhouseDashboard extends StatefulWidget {
  const GreenhouseDashboard({super.key});

  @override
  State<GreenhouseDashboard> createState() => _GreenhouseDashboardState();
}

class _GreenhouseDashboardState extends State<GreenhouseDashboard> {
  final GreenhouseMqttService _mqtt = GreenhouseMqttService();
  int _selectedTab = 0;

  @override
  void dispose() {
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _mqtt,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildTopStatusHeader(context),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      _buildControlTab(),
                      _buildScenariosTab(),
                      _buildSettingsAndLogsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF131820),
            indicatorColor: const Color(0xFF00E676).withValues(alpha: 0.18),
            selectedIndex: _selectedTab,
            onDestinationSelected: (idx) => setState(() => _selectedTab = idx),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard, color: Color(0xFF00E676)),
                label: 'Управление',
              ),
              const NavigationDestination(
                icon: Icon(Icons.auto_fix_high_outlined),
                selectedIcon: Icon(Icons.auto_fix_high, color: Color(0xFF00E676)),
                label: 'Сценарии',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _mqtt.activeErrors.isNotEmpty,
                  label: Text('${_mqtt.activeErrors.length}'),
                  child: const Icon(Icons.tune_outlined),
                ),
                selectedIcon: const Icon(Icons.tune, color: Color(0xFF00E676)),
                label: 'Система / Ошибки',
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== ВЕРХНЯЯ ПАНЕЛЬ СТАТУСА И ВРЕМЕНИ ====================
  Widget _buildTopStatusHeader(BuildContext context) {
    final phoneOk = _mqtt.isConnected;
    final espOk = _mqtt.isConnected && _mqtt.isControllerOnline;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF131820),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.eco, color: Color(0xFF00E676), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Умная Теплица',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showTimeSettingSheet(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 15, color: Color(0xFF00E676)),
                      const SizedBox(width: 5),
                      Text(
                        _mqtt.rtcTimeString,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showMqttSettingsSheet(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (phoneOk ? const Color(0xFF00E676) : Colors.redAccent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (phoneOk ? const Color(0xFF00E676) : Colors.redAccent)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.smartphone,
                          size: 18,
                          color: phoneOk ? const Color(0xFF00E676) : Colors.redAccent,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Телефон → MQTT',
                                style: TextStyle(fontSize: 10, color: Colors.white60),
                              ),
                              Text(
                                phoneOk ? 'Подключен' : 'Нет связи',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: phoneOk
                                      ? const Color(0xFF00E676)
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (phoneOk) _mqtt.requestFullStatus();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (espOk ? const Color(0xFF29B6F6) : Colors.orangeAccent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (espOk ? const Color(0xFF29B6F6) : Colors.orangeAccent)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 18,
                          color: espOk ? const Color(0xFF29B6F6) : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ESP32 → MQTT',
                                style: TextStyle(fontSize: 10, color: Colors.white60),
                              ),
                              Text(
                                espOk ? 'Контроллер в сети' : 'Контроллер оффлайн',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: espOk
                                      ? const Color(0xFF29B6F6)
                                      : Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== БАННЕР ОШИБОК И ТРЕВОГ ====================
  Widget _buildErrorsBanner() {
    final hasErr = _mqtt.activeErrors.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (hasErr ? Colors.redAccent : const Color(0xFF00E676))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (hasErr ? Colors.redAccent : const Color(0xFF00E676))
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasErr ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: hasErr ? Colors.redAccent : const Color(0xFF00E676),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasErr
                      ? 'ТРЕВОГА / ОШИБКИ (${_mqtt.activeErrors.length})'
                      : 'ОШИБОК НЕТ — ВСЕ СИСТЕМЫ В НОРМЕ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: hasErr ? Colors.redAccent : const Color(0xFF00E676),
                  ),
                ),
              ),
            ],
          ),
          if (hasErr) ...[
            const SizedBox(height: 8),
            ..._mqtt.activeErrors.map(
              (err) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• $err',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА 1: УПРАВЛЕНИЕ И ДАТЧИКИ ====================
  Widget _buildControlTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildErrorsBanner(),
        HoldModeButton(mqtt: _mqtt),
        const SizedBox(height: 16),
        const Text(
          'ПОКАЗАНИЯ ДАТЧИКОВ (НАЖМИТЕ ДЛЯ ПОРОГА)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _buildSensorCard(
              configKey: 'airTemp',
              title: 'T внутри / Влажн.',
              value:
                  '${_mqtt.airTemp.toStringAsFixed(1)}°C / ${_mqtt.airHumidity.toInt()}%',
              icon: Icons.thermostat,
            ),
            _buildSensorCard(
              configKey: 'outdoorTemp',
              title: 'T на улице',
              value: '${_mqtt.outdoorTemp.toStringAsFixed(1)}°C',
              icon: Icons.ac_unit,
            ),
            _buildSensorCard(
              configKey: 'soilMoisture',
              title: 'Влажность почвы',
              value: '${_mqtt.soilMoisture.toInt()}%',
              icon: Icons.water_drop,
            ),
            _buildSensorCard(
              configKey: 'lightLux',
              title: 'Освещённость',
              value: '${_mqtt.lightLux} лк',
              icon: Icons.wb_sunny,
            ),
            _buildSensorCard(
              configKey: 'co2',
              title: 'Газ / CO₂ (MQ135)',
              value: '${_mqtt.co2Level} ppm',
              icon: Icons.air,
            ),
            _buildStaticInfoCard(
              title: 'Питание системы',
              value: '${_mqtt.voltage.toStringAsFixed(1)} В',
              icon: Icons.bolt,
              accent: Colors.amberAccent,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'ПОЛИВ И ОСВЕЩЕНИЕ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActuatorButton(
                title: 'Полив',
                isActive: _mqtt.isWateringActive,
                isPending: _mqtt.isPendingWatering,
                isError: _mqtt.isErrorWatering,
                activeColor: const Color(0xFF29B6F6),
                icon: Icons.water,
                onTap: _mqtt.toggleWatering,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActuatorButton(
                title: 'Фито-LED',
                isActive: _mqtt.isPhytoLightActive,
                isPending: _mqtt.isPendingPhyto,
                isError: _mqtt.isErrorPhyto,
                activeColor: const Color(0xFFE040FB),
                icon: Icons.wb_incandescent,
                onTap: _mqtt.togglePhytoLight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActuatorButton(
                title: 'Белый LED',
                isActive: _mqtt.isWhiteLightActive,
                isPending: _mqtt.isPendingWhite,
                isError: _mqtt.isErrorWhite,
                activeColor: const Color(0xFFFFD54F),
                icon: Icons.lightbulb,
                onTap: _mqtt.toggleWhiteLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Таймер помпы:',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
            OutlinedButton(
              onPressed: () => _mqtt.runPumpTimer(5),
              child: const Text('5 сек', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton(
              onPressed: () => _mqtt.runPumpTimer(30),
              child: const Text('30 сек', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton(
              onPressed: () => _mqtt.runPumpTimer(60),
              child: const Text('60 сек', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ПРИВОДЫ ОКОН И ДВЕРЕЙ (0–180°)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.0,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: _mqtt.openAllServos,
                  child: const Text('Открыть все', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: _mqtt.closeAllServos,
                  child: const Text(
                    'Закрыть',
                    style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
        _buildServoCard(
          label: 'Левое окно крыши',
          angle: _mqtt.roofLeftAngle,
          maxAngle: _mqtt.maxRoofAngleLimit,
          onChanged: (v) => _mqtt.setRoofLeftAngle(v, log: false),
          onChangeEnd: (v) => _mqtt.setRoofLeftAngle(v, log: true),
        ),
        _buildServoCard(
          label: 'Правое окно крыши',
          angle: _mqtt.roofRightAngle,
          maxAngle: _mqtt.maxRoofAngleLimit,
          onChanged: (v) => _mqtt.setRoofRightAngle(v, log: false),
          onChangeEnd: (v) => _mqtt.setRoofRightAngle(v, log: true),
        ),
        _buildServoCard(
          label: 'Передняя дверь',
          angle: _mqtt.doorFrontAngle,
          maxAngle: _mqtt.maxDoorAngleLimit,
          onChanged: (v) => _mqtt.setDoorFrontAngle(v, log: false),
          onChangeEnd: (v) => _mqtt.setDoorFrontAngle(v, log: true),
        ),
        _buildServoCard(
          label: 'Задняя дверь',
          angle: _mqtt.doorBackAngle,
          maxAngle: _mqtt.maxDoorAngleLimit,
          onChanged: (v) => _mqtt.setDoorBackAngle(v, log: false),
          onChangeEnd: (v) => _mqtt.setDoorBackAngle(v, log: true),
        ),
      ],
    );
  }

  // ==================== КНОПКА АКТУАТОРА С ИНДИКАЦИЕЙ ОШИБКИ НА 2 СЕК ====================
  Widget _buildActuatorButton({
    required String title,
    required bool isActive,
    required bool isPending,
    required bool isError,
    required Color activeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final Color borderColor = isError
        ? Colors.redAccent
        : (isPending
            ? Colors.amberAccent
            : (isActive ? activeColor : Colors.white12));

    final Color bgColor = isError
        ? Colors.redAccent.withValues(alpha: 0.20)
        : (isActive
            ? activeColor.withValues(alpha: 0.22)
            : const Color(0xFF171D26));

    return InkWell(
      onTap: (isPending || isError) ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          children: [
            if (isError)
              // Красный восклицательный знак в круге при таймауте 7.5 сек
              const Icon(
                Icons.error_outline,
                size: 26,
                color: Colors.redAccent,
              )
            else if (isPending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Icon(
                icon,
                size: 24,
                color: isActive ? activeColor : Colors.white54,
              ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isError
                    ? Colors.redAccent
                    : (isActive ? Colors.white : Colors.white70),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isError
                  ? 'Ошибка'
                  : (isPending ? 'Отклик...' : (isActive ? 'ВКЛ' : 'ВЫКЛ')),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isError
                    ? Colors.redAccent
                    : (isPending
                        ? Colors.amberAccent
                        : (isActive ? activeColor : Colors.white38)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА 2: ПОЛНОЦЕННЫЕ ГИБКИЕ СЦЕНАРИИ ====================
  Widget _buildScenariosTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00E676),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Новый сценарий',
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openRuleEditor(null),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          const Text(
            'АВТОМАТИЗАЦИЯ И СЦЕНАРИИ (СОХРАНЯЮТСЯ В ПАМЯТИ)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Условия И/ИЛИ + управление сервоприводами, поливом, светом, светодиодами и пьезо.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 14),
          if (_mqtt.rules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Сценариев пока нет. Нажмите «Новый сценарий».',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ..._mqtt.rules.map((rule) => _buildScenarioCard(rule)),
        ],
      ),
    );
  }

  Widget _buildScenarioCard(AutomationRule rule) {
    final cond1Text =
        '${_sensorTitle(rule.sensorType)} ${rule.operatorType} ${_formatSensorValue(rule.sensorType, rule.threshold)}';
    final cond2Text = rule.hasSecondCondition
        ? ' ${rule.logicOperator == "OR" ? "ИЛИ" : "И"} ${_sensorTitle(rule.secondSensorType)} ${rule.secondOperatorType} ${_formatSensorValue(rule.secondSensorType, rule.secondThreshold)}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171D26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rule.isEnabled
              ? const Color(0xFF00E676).withValues(alpha: 0.35)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: rule.isEnabled ? Colors.white : Colors.white54,
                  ),
                ),
              ),
              Switch(
                value: rule.isEnabled,
                activeThumbColor: const Color(0xFF00E676),
                onChanged: (v) => _mqtt.toggleRule(rule.id, v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'ЕСЛИ: $cond1Text$cond2Text',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF82B1FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: rule.actions.map((act) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ТО: ${act.describe()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 18, color: Colors.white10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _mqtt.executeRuleActions(rule, manualTest: true),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Выполнить', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Редактировать',
                icon: const Icon(Icons.edit_outlined, size: 19, color: Colors.white70),
                onPressed: () => _openRuleEditor(rule),
              ),
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                onPressed: () => _mqtt.deleteRule(rule.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== ПОЛНЫЙ РЕДАКТОР СЦЕНАРИЕВ ====================
  void _openRuleEditor(AutomationRule? existing) {
    final nameCtrl = TextEditingController(
      text: existing?.name ?? 'Новый сценарий',
    );

    String sensor1 = existing?.sensorType ?? 'airTemp';
    String op1 = existing?.operatorType ?? '>';
    double thresh1 = existing?.threshold ?? 26.0;

    bool hasCond2 = existing?.hasSecondCondition ?? false;
    String logicOp = existing?.logicOperator ?? 'AND';
    String sensor2 = existing?.secondSensorType ?? 'lightLux';
    String op2 = existing?.secondOperatorType ?? '>';
    double thresh2 = existing?.secondThreshold ?? 300.0;

    List<RuleAction> actions = existing != null
        ? existing.actions
            .map((a) => RuleAction(target: a.target, value: a.value))
            .toList()
        : [RuleAction(target: 'roofAngle', value: 120)];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171D26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.88,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      existing == null
                          ? 'Создание гибкого сценария'
                          : 'Редактирование сценария',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Название сценария',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '1. УСЛОВИЕ СРАБАТЫВАНИЯ (ЕСЛИ)',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF82B1FF)),
                    ),
                    const SizedBox(height: 8),
                    _buildConditionEditorBlock(
                      sensor: sensor1,
                      operatorType: op1,
                      threshold: thresh1,
                      onSensorChanged: (s) {
                        setModalState(() {
                          sensor1 = s;
                          thresh1 = _defaultSensorThreshold(s);
                        });
                      },
                      onOpChanged: (o) => setModalState(() => op1 = o),
                      onThreshChanged: (v) => setModalState(() => thresh1 = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Добавить второе условие (И / ИЛИ)'),
                      value: hasCond2,
                      activeThumbColor: const Color(0xFF00E676),
                      onChanged: (v) => setModalState(() => hasCond2 = v),
                    ),
                    if (hasCond2) ...[
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('И (оба верны)'),
                            selected: logicOp == 'AND',
                            onSelected: (_) => setModalState(() => logicOp = 'AND'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('ИЛИ (хотя бы одно)'),
                            selected: logicOp == 'OR',
                            onSelected: (_) => setModalState(() => logicOp = 'OR'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildConditionEditorBlock(
                        sensor: sensor2,
                        operatorType: op2,
                        threshold: thresh2,
                        onSensorChanged: (s) {
                          setModalState(() {
                            sensor2 = s;
                            thresh2 = _defaultSensorThreshold(s);
                          });
                        },
                        onOpChanged: (o) => setModalState(() => op2 = o),
                        onThreshChanged: (v) => setModalState(() => thresh2 = v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '2. ДЕЙСТВИЯ (ЧТО ВКЛЮЧИТЬ / ОТКРЫТЬ)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              actions.add(RuleAction(target: 'pump', value: 1));
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Добавить действие'),
                        ),
                      ],
                    ),
                    ...actions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final act = entry.value;
                      final isServo = act.target == 'roofAngle' ||
                          act.target == 'doorAngle' ||
                          act.target == 'roofLeft' ||
                          act.target == 'roofRight' ||
                          act.target == 'doorFront' ||
                          act.target == 'doorBack' ||
                          act.target == 'allServos';
                      final isPumpTimer = act.target == 'pumpTimer';
                      final isLed = act.target.startsWith('led');
                      final isBuzzer = act.target == 'buzzer';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E1217),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButton<String>(
                                    value: act.target,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF171D26),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'roofAngle',
                                          child: Text('Оба окна крыши (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'doorAngle',
                                          child: Text('Обе двери (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'roofLeft',
                                          child: Text('Левое окно крыши (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'roofRight',
                                          child: Text('Правое окно крыши (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'doorFront',
                                          child: Text('Передняя дверь (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'doorBack',
                                          child: Text('Задняя дверь (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'allServos',
                                          child: Text('Все 4 сервопривода (0–180°)')),
                                      DropdownMenuItem(
                                          value: 'pump',
                                          child: Text('Помпа полива (ВКЛ/ВЫКЛ)')),
                                      DropdownMenuItem(
                                          value: 'pumpTimer',
                                          child: Text('Помпа на время (5/30/60 сек)')),
                                      DropdownMenuItem(
                                          value: 'phytoLight',
                                          child: Text('Фито-лента LED')),
                                      DropdownMenuItem(
                                          value: 'whiteLight',
                                          child: Text('Белая лента LED')),
                                      DropdownMenuItem(
                                          value: 'ledRed',
                                          child: Text('Красный светодиод платы')),
                                      DropdownMenuItem(
                                          value: 'ledGreen',
                                          child: Text('Зелёный светодиод платы')),
                                      DropdownMenuItem(
                                          value: 'ledBlue',
                                          child: Text('Синий светодиод платы')),
                                      DropdownMenuItem(
                                          value: 'ledYellow',
                                          child: Text('Жёлтый светодиод платы')),
                                      DropdownMenuItem(
                                          value: 'buzzer',
                                          child: Text('Звуковой сигнал пьезо')),
                                    ],
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setModalState(() {
                                        act.target = val;
                                        if (val == 'pumpTimer') {
                                          act.value = 30.0;
                                        } else if (val == 'buzzer') {
                                          act.value = 2.0;
                                        } else if (val.contains('Angle') ||
                                            val.contains('roof') ||
                                            val.contains('door') ||
                                            val == 'allServos') {
                                          act.value = 90.0;
                                        } else {
                                          act.value = 1.0;
                                        }
                                      });
                                    },
                                  ),
                                ),
                                if (actions.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.redAccent, size: 20),
                                    onPressed: () =>
                                        setModalState(() => actions.removeAt(i)),
                                  ),
                              ],
                            ),
                            if (isServo) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Угол открытия:',
                                      style: TextStyle(fontSize: 12)),
                                  Text('${act.value.toInt()}°',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF00E676))),
                                ],
                              ),
                              Slider(
                                value: act.value.clamp(0.0, 180.0),
                                min: 0,
                                max: 180,
                                divisions: 36,
                                onChanged: (v) =>
                                    setModalState(() => act.value = v),
                              ),
                            ] else if (isPumpTimer) ...[
                              Wrap(
                                spacing: 8,
                                children: [5, 30, 60].map((sec) {
                                  return ChoiceChip(
                                    label: Text('$sec сек'),
                                    selected: act.value.toInt() == sec,
                                    onSelected: (_) => setModalState(
                                        () => act.value = sec.toDouble()),
                                  );
                                }).toList(),
                              ),
                            ] else if (isBuzzer) ...[
                              Wrap(
                                spacing: 8,
                                children: [1, 2, 3, 5].map((cnt) {
                                  return ChoiceChip(
                                    label: Text('$cnt писка'),
                                    selected: act.value.toInt() == cnt,
                                    onSelected: (_) => setModalState(
                                        () => act.value = cnt.toDouble()),
                                  );
                                }).toList(),
                              ),
                            ] else if (isLed) ...[
                              Wrap(
                                spacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('ВКЛ'),
                                    selected: act.value.toInt() == 1,
                                    onSelected: (_) =>
                                        setModalState(() => act.value = 1),
                                  ),
                                  ChoiceChip(
                                    label: const Text('ВЫКЛ'),
                                    selected: act.value.toInt() == 0,
                                    onSelected: (_) =>
                                        setModalState(() => act.value = 0),
                                  ),
                                  ChoiceChip(
                                    label: const Text('АВТО (штатно)'),
                                    selected: act.value.toInt() == 2,
                                    onSelected: (_) =>
                                        setModalState(() => act.value = 2),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Включить (ВКЛ)'),
                                    selected: act.value >= 1,
                                    onSelected: (_) =>
                                        setModalState(() => act.value = 1),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Выключить (ВЫКЛ)'),
                                    selected: act.value < 1,
                                    onSelected: (_) =>
                                        setModalState(() => act.value = 0),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          final rule = AutomationRule(
                            id: existing?.id ??
                                DateTime.now().millisecondsSinceEpoch.toString(),
                            name: nameCtrl.text.trim().isEmpty
                                ? 'Сценарий'
                                : nameCtrl.text.trim(),
                            sensorType: sensor1,
                            operatorType: op1,
                            threshold: thresh1,
                            hasSecondCondition: hasCond2,
                            logicOperator: logicOp,
                            secondSensorType: sensor2,
                            secondOperatorType: op2,
                            secondThreshold: thresh2,
                            actions: actions,
                            isEnabled: existing?.isEnabled ?? true,
                          );
                          _mqtt.saveOrUpdateRule(rule);
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Сохранить сценарий в память',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildConditionEditorBlock({
    required String sensor,
    required String operatorType,
    required double threshold,
    required ValueChanged<String> onSensorChanged,
    required ValueChanged<String> onOpChanged,
    required ValueChanged<double> onThreshChanged,
  }) {
    final range = _sensorRange(sensor);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1217),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButton<String>(
                  value: sensor,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF171D26),
                  items: const [
                    DropdownMenuItem(value: 'airTemp', child: Text('T внутри (°C)')),
                    DropdownMenuItem(value: 'outdoorTemp', child: Text('T улицы (°C)')),
                    DropdownMenuItem(
                        value: 'airHumidity', child: Text('Влажность возд. (%)')),
                    DropdownMenuItem(
                        value: 'soilMoisture', child: Text('Влажность почвы (%)')),
                    DropdownMenuItem(
                        value: 'lightLux', child: Text('Освещённость (лк)')),
                    DropdownMenuItem(value: 'co2', child: Text('Газ / CO₂ (ppm)')),
                    DropdownMenuItem(value: 'voltage', child: Text('Питание (В)')),
                    DropdownMenuItem(value: 'timeHour', child: Text('Время суток (ч)')),
                  ],
                  onChanged: (v) {
                    if (v != null) onSensorChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: DropdownButton<String>(
                  value: operatorType,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF171D26),
                  items: const [
                    DropdownMenuItem(value: '>', child: Text('>')),
                    DropdownMenuItem(value: '<', child: Text('<')),
                    DropdownMenuItem(value: '>=', child: Text('≥')),
                    DropdownMenuItem(value: '<=', child: Text('≤')),
                  ],
                  onChanged: (v) {
                    if (v != null) onOpChanged(v);
                  },
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Пороговое значение:', style: TextStyle(fontSize: 12)),
              Text(
                _formatSensorValue(sensor, threshold),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF82B1FF)),
              ),
            ],
          ),
          Slider(
            value: threshold.clamp(range.$1, range.$2),
            min: range.$1,
            max: range.$2,
            onChanged: onThreshChanged,
          ),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА 3: СИСТЕМА, АДМИНКА (С ПЬЕЗО ПРИ ОШИБКЕ) И ЛОГИ ====================
  Widget _buildSettingsAndLogsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildErrorsBanner(),
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF171D26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Color(0xFF00E676)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Время на ESP32: ${_mqtt.rtcTimeString}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _showTimeSettingSheet(context),
                child: const Text('Изменить'),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF171D26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_sync, color: Color(0xFF00E676)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Подключение к MQTT Брокеру',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showMqttSettingsSheet(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Изменить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Сервер: ${_mqtt.broker}:${_mqtt.port}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Блок администратора (при неверном пароле ESP32 пищит 4 раза с задержкой 0.2с)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF171D26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _mqtt.isDeveloperUnlocked ? Icons.lock_open : Icons.lock_outline,
                    color: _mqtt.isDeveloperUnlocked
                        ? const Color(0xFF00E676)
                        : Colors.amberAccent,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Панель администратора',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_mqtt.isDeveloperUnlocked)
                    TextButton(
                      onPressed: _mqtt.lockDeveloperMode,
                      child: const Text('Заблокировать',
                          style: TextStyle(color: Colors.redAccent)),
                    )
                  else
                    ElevatedButton(
                      onPressed: _showAdminPinDialog,
                      child: const Text('Войти'),
                    ),
                ],
              ),
              if (_mqtt.isDeveloperUnlocked) ...[
                const Divider(height: 22, color: Colors.white10),
                Text(
                  'Максимальный угол окон: ${_mqtt.maxRoofAngleLimit.toInt()}°',
                  style: const TextStyle(fontSize: 13),
                ),
                Slider(
                  value: _mqtt.maxRoofAngleLimit,
                  min: 10,
                  max: 180,
                  divisions: 170,
                  onChanged: (v) =>
                      _mqtt.setServoLimits(v, _mqtt.maxDoorAngleLimit),
                ),
                Text(
                  'Максимальный угол дверей: ${_mqtt.maxDoorAngleLimit.toInt()}°',
                  style: const TextStyle(fontSize: 13),
                ),
                Slider(
                  value: _mqtt.maxDoorAngleLimit,
                  min: 10,
                  max: 180,
                  divisions: 170,
                  onChanged: (v) =>
                      _mqtt.setServoLimits(_mqtt.maxRoofAngleLimit, v),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'ЖУРНАЛ СОБЫТИЙ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF171D26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _mqtt.eventLogs
                .take(25)
                .map((log) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        log,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _showAdminPinDialog() {
    final pinCtrl = TextEditingController();
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF171D26),
              title: const Text('Доступ администратора'),
              content: TextField(
                controller: pinCtrl,
                obscureText: true,
                obscuringCharacter: '•',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  errorText: errorMsg,
                  border: const OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (_mqtt.unlockDeveloperMode(pinCtrl.text)) {
                      Navigator.pop(ctx);
                    } else {
                      setDialogState(
                          () => errorMsg = 'Неверный пароль! (Сигнал на ESP32)');
                    }
                  },
                  child: const Text('Подтвердить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ КАРТОЧКИ И ДИАЛОГИ ====================
  Widget _buildSensorCard({
    required String configKey,
    required String title,
    required String value,
    required IconData icon,
  }) {
    final valColor = _mqtt.getSensorValueColor(configKey);
    final lblColor = _mqtt.getSensorLabelColor(configKey);
    final thr = _mqtt.sensorConfigs[configKey]?.threshold;

    return InkWell(
      onTap: () => _showThresholdSheet(configKey),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF171D26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: valColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: lblColor),
                  ),
                ),
                if (thr != null)
                  Text(
                    '(${thr.toInt()})',
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: valColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171D26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServoCard({
    required String label,
    required double angle,
    required double maxAngle,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF171D26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(
                '${angle.toInt()}° / ${maxAngle.toInt()}°',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E676),
                ),
              ),
            ],
          ),
          Slider(
            value: angle.clamp(0.0, maxAngle),
            min: 0.0,
            max: maxAngle,
            divisions: maxAngle.toInt(),
            activeColor: const Color(0xFF00E676),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }

  void _showTimeSettingSheet(BuildContext context) {
    final parts = _mqtt.rtcTimeString.split(':');
    int selHour = int.tryParse(parts.first) ?? 12;
    int selMin = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171D26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Время на контроллере ESP32',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Выбрано: ${selHour.toString().padLeft(2, '0')}:${selMin.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E676),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Часы (0–23):'),
                  Slider(
                    value: selHour.toDouble(),
                    min: 0,
                    max: 23,
                    divisions: 23,
                    onChanged: (v) => setModalState(() => selHour = v.toInt()),
                  ),
                  const Text('Минуты (0–59):'),
                  Slider(
                    value: selMin.toDouble(),
                    min: 0,
                    max: 59,
                    divisions: 59,
                    onChanged: (v) => setModalState(() => selMin = v.toInt()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.smartphone, size: 18),
                          label: const Text('Время телефона'),
                          onPressed: () {
                            _mqtt.syncPhoneTimeToController();
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Сохранить'),
                          onPressed: () {
                            _mqtt.setControllerTime(selHour, selMin);
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMqttSettingsSheet(BuildContext context) {
    final brokerCtrl = TextEditingController(text: _mqtt.broker);
    final portCtrl = TextEditingController(text: _mqtt.port.toString());
    final userCtrl = TextEditingController(text: _mqtt.username);
    final passCtrl = TextEditingController(text: _mqtt.password);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171D26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: brokerCtrl,
                decoration: const InputDecoration(labelText: 'Адрес брокера'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Порт (1883 / 8883)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final parsedPort = int.tryParse(portCtrl.text.trim()) ?? 1883;
                    Navigator.pop(ctx);
                    await _mqtt.updateMqttCredentials(
                      newBroker: brokerCtrl.text,
                      newPort: parsedPort,
                      newUsername: userCtrl.text,
                      newPassword: passCtrl.text,
                    );
                  },
                  child: const Text('Сохранить и подключиться'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showThresholdSheet(String key) {
    final cfg = _mqtt.sensorConfigs[key];
    if (cfg == null) return;

    double tempThresh = cfg.threshold;
    double tempHyst = cfg.hysteresisPercent;
    bool tempHigh = cfg.alertWhenHigh;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171D26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Порог тревоги: ${cfg.name}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text('Значение порога: ${tempThresh.toStringAsFixed(1)}${cfg.unit}'),
                  Slider(
                    value: tempThresh.clamp(cfg.minLimit, cfg.maxLimit),
                    min: cfg.minLimit,
                    max: cfg.maxLimit,
                    onChanged: (v) => setModalState(() => tempThresh = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tempHigh
                        ? 'Тревога при ПРЕВЫШЕНИИ (>)'
                        : 'Тревога при ПАДЕНИИ (<)'),
                    value: tempHigh,
                    onChanged: (v) => setModalState(() => tempHigh = v),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        _mqtt.updateSensorThreshold(
                          key,
                          threshold: tempThresh,
                          hysteresisPercent: tempHyst,
                          alertWhenHigh: tempHigh,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('Сохранить порог в память и ESP32'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _sensorTitle(String key) {
    switch (key) {
      case 'airTemp':
        return 'T внутри';
      case 'outdoorTemp':
        return 'T улицы';
      case 'airHumidity':
        return 'Влажность возд.';
      case 'soilMoisture':
        return 'Почва';
      case 'lightLux':
        return 'Свет';
      case 'co2':
        return 'CO₂';
      case 'voltage':
        return 'Напряжение';
      case 'timeHour':
        return 'Время';
      default:
        return key;
    }
  }

  String _formatSensorValue(String key, double val) {
    switch (key) {
      case 'airTemp':
      case 'outdoorTemp':
        return '${val.toStringAsFixed(1)}°C';
      case 'airHumidity':
      case 'soilMoisture':
        return '${val.toInt()}%';
      case 'lightLux':
        return '${val.toInt()} лк';
      case 'co2':
        return '${val.toInt()} ppm';
      case 'voltage':
        return '${val.toStringAsFixed(1)} В';
      case 'timeHour':
        return '${val.toInt().toString().padLeft(2, '0')}:00';
      default:
        return val.toStringAsFixed(1);
    }
  }

  (double, double) _sensorRange(String key) {
    switch (key) {
      case 'airTemp':
        return (5.0, 50.0);
      case 'outdoorTemp':
        return (-20.0, 45.0);
      case 'airHumidity':
      case 'soilMoisture':
        return (0.0, 100.0);
      case 'lightLux':
        return (0.0, 1200.0);
      case 'co2':
        return (350.0, 2500.0);
      case 'voltage':
        return (9.0, 15.0);
      case 'timeHour':
        return (0.0, 23.0);
      default:
        return (0.0, 100.0);
    }
  }

  double _defaultSensorThreshold(String key) {
    switch (key) {
      case 'airTemp':
        return 26.0;
      case 'outdoorTemp':
        return 12.0;
      case 'airHumidity':
        return 70.0;
      case 'soilMoisture':
        return 35.0;
      case 'lightLux':
        return 300.0;
      case 'co2':
        return 900.0;
      case 'voltage':
        return 11.2;
      case 'timeHour':
        return 18.0;
      default:
        return 20.0;
    }
  }
}

// ==================== КНОПКА РЕЖИМА С ИНДИКАЦИЕЙ ОШИБКИ (2 СЕК) ====================
class HoldModeButton extends StatefulWidget {
  final GreenhouseMqttService mqtt;
  const HoldModeButton({super.key, required this.mqtt});

  @override
  State<HoldModeButton> createState() => _HoldModeButtonState();
}

class _HoldModeButtonState extends State<HoldModeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: GreenhouseMqttService.modeHoldDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.mqtt.toggleControlMode();
          _holdController.reset();
        }
      });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuto = widget.mqtt.isAutoModeActive;
    final isPending = widget.mqtt.isPendingMode;
    final isError = widget.mqtt.isErrorMode;

    final Color accent = isError
        ? Colors.redAccent
        : (isAuto ? const Color(0xFF00E676) : Colors.orangeAccent);

    return GestureDetector(
      onTapDown: (_) {
        if (!isPending && !isError) _holdController.forward();
      },
      onTapUp: (_) => _holdController.reverse(),
      onTapCancel: () => _holdController.reverse(),
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.65), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isError)
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 22)
                    else if (isPending)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(isAuto ? Icons.hdr_auto : Icons.pan_tool_alt, color: accent),
                    const SizedBox(width: 10),
                    Text(
                      isError
                          ? 'ОШИБКА: НЕТ ОТКЛИКА'
                          : (isPending
                              ? 'Ожидание ответа ESP32...'
                              : (isAuto
                                  ? 'РЕЖИМ: АВТО (удерж. 1.5с)'
                                  : 'РЕЖИМ: РУЧНОЙ (удерж. 1.5с)')),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                if (_holdController.value > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _holdController.value,
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    color: accent,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}