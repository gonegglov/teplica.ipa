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

  // ==================== ВЕРХНЯЯ ПАНЕЛЬ (ЧАСЫ НАЖИМАЮТСЯ ДЛЯ УСТАНОВКИ ВРЕМЕНИ!) ====================
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
              // Нажатие на часы открывает установку времени на ESP32
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
                                espOk ? 'В сети (Синхр.)' : 'Контроллер оффлайн',
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

  // ==================== БАННЕР ОШИБОК И ТРЕВОГ (ПУНКТ 7 ERRORS) ====================
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
                activeColor: const Color(0xFFFFD54F),
                icon: Icons.lightbulb,
                onTap: _mqtt.toggleWhiteLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Быстрые кнопки таймера помпы (как в пункте 4 на энкодере)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Таймер помпы:', style: TextStyle(fontSize: 12, color: Colors.white60)),
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

  // ==================== МОДАЛЬНОЕ ОКНО НАСТРОЙКИ ВРЕМЕНИ КОНТРОЛЛЕРА ====================
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

  Widget _buildActuatorButton({
    required String title,
    required bool isActive,
    required bool isPending,
    required Color activeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isPending ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.22)
              : const Color(0xFF171D26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPending
                ? Colors.amberAccent
                : (isActive ? activeColor : Colors.white12),
            width: 1.4,
          ),
        ),
        child: Column(
          children: [
            if (isPending)
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
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isPending ? 'Отклик...' : (isActive ? 'ВКЛ' : 'ВЫКЛ'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isPending
                    ? Colors.amberAccent
                    : (isActive ? activeColor : Colors.white38),
              ),
            ),
          ],
        ),
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

  // ==================== ВКЛАДКА 2: СЦЕНАРИИ ====================
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
            'АВТОМАТИЗАЦИЯ И СЦЕНАРИИ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          ..._mqtt.rules.map((rule) => _buildScenarioCard(rule)),
        ],
      ),
    );
  }

  Widget _buildScenarioCard(AutomationRule rule) {
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: rule.actions
                .map((act) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        act.describe(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ))
                .toList(),
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
                icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                onPressed: () => _mqtt.deleteRule(rule.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА 3: СИСТЕМА, ОШИБКИ (ERRORS) И НАСТРОЙКИ ====================
  Widget _buildSettingsAndLogsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Меню активных ошибок (Пункт 7 ERRORS)
        _buildErrorsBanner(),

        // 2. Быстрая синхронизация времени
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

        // 3. Настройки MQTT
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
                    child: const Text('Настроить'),
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

        // 4. Журнал событий
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
                      child: const Text('Сохранить порог в ESP32'),
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

  void _openRuleEditor(AutomationRule? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? 'Новый сценарий');
    double angleVal = 120;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171D26),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Название сценария'),
                  ),
                  const SizedBox(height: 12),
                  Text('Открыть окна на: ${angleVal.toInt()}°'),
                  Slider(
                    value: angleVal,
                    min: 0,
                    max: 180,
                    onChanged: (v) => setModalState(() => angleVal = v),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      _mqtt.saveOrUpdateRule(
                        AutomationRule(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameCtrl.text.trim(),
                          sensorType: 'airTemp',
                          operatorType: '>',
                          threshold: 26.0,
                          actions: [RuleAction(target: 'roofAngle', value: angleVal)],
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text('Сохранить и отправить на ESP32'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

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
    final accent = isAuto ? const Color(0xFF00E676) : Colors.orangeAccent;

    return GestureDetector(
      onTapDown: (_) {
        if (!isPending) _holdController.forward();
      },
      onTapUp: (_) => _holdController.reverse(),
      onTapCancel: () => _holdController.reverse(),
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isAuto ? Icons.hdr_auto : Icons.pan_tool_alt, color: accent),
                    const SizedBox(width: 10),
                    Text(
                      isPending
                          ? 'Синхронизация с ESP32...'
                          : (isAuto
                              ? 'РЕЖИМ: АВТО (удерж. 1.5с)'
                              : 'РЕЖИМ: РУЧНОЙ (удерж. 1.5с)'),
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