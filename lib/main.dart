import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'mqtt_service.dart';

void main() {
  runApp(const GreenhouseApp());
}

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ГринХаус Про',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090E14),
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const InteractiveGreenhouseScreen(),
    );
  }
}

class InteractiveGreenhouseScreen extends StatefulWidget {
  const InteractiveGreenhouseScreen({super.key});

  @override
  State<InteractiveGreenhouseScreen> createState() =>
      _InteractiveGreenhouseScreenState();
}

class _InteractiveGreenhouseScreenState
    extends State<InteractiveGreenhouseScreen> {
  final GreenhouseMqttService mqtt = GreenhouseMqttService();
  int currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    mqtt.addListener(() {
      if (mounted) setState(() {});
    });
  }

  List<Color> _getSkyGradient(double hour) {
    if (hour >= 5.5 && hour < 8.5) {
      return const [Color(0xFF2B1E38), Color(0xFF4A2934), Color(0xFF0B141C)];
    } else if (hour >= 8.5 && hour < 17.5) {
      return const [Color(0xFF153142), Color(0xFF0E202B), Color(0xFF081016)];
    } else if (hour >= 17.5 && hour <= 20.5) {
      return const [Color(0xFF3A1C2E), Color(0xFF542822), Color(0xFF091118)];
    } else {
      return const [Color(0xFF070C12), Color(0xFF05080C), Color(0xFF030507)];
    }
  }

  String _formatTime(double hours) {
    final int h = hours.floor() % 24;
    final int m = ((hours - hours.floor()) * 60).round() % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _getSunPhaseLabel(double hours) {
    if (hours >= 5.5 && hours < 8.5) return '🌅 Рассвет';
    if (hours >= 8.5 && hours < 17.5) return '☀️ День';
    if (hours >= 17.5 && hours <= 20.5) return '🌇 Закат';
    return '🌙 Ночь';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeTab(),
      _buildScenariosTab(),
      _buildHistoryTab(),
      _buildSettingsTab(),
    ];

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.35),
            radius: 1.2,
            colors: _getSkyGradient(mqtt.timeOfDayHours),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: _buildHeader(),
                  ),
                  Expanded(
                    child: pages[currentTabIndex],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildGlassNavigationBar(),
    );
  }

  // ==================== ВЕРХНЯЯ ПАНЕЛЬ ====================
  Widget _buildHeader() {
    final statusColor =
        mqtt.isConnected ? const Color(0xFF28E070) : const Color(0xFF00E5FF);
    final bool anyLightOn =
        mqtt.isPhytoLightActive || mqtt.isWhiteLightActive;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            anyLightOn ? Icons.lightbulb : Icons.lightbulb_outline,
            color: anyLightOn ? const Color(0xFFFFEE58) : Colors.white38,
            size: 24,
          ),
          tooltip: 'Мастер-свет: ВКЛ/ВЫКЛ обе ленты',
          onPressed: mqtt.toggleAllLights,
        ),
        Column(
          children: [
            const Text(
              'МОЯ ТЕПЛИЦА',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 19,
                letterSpacing: 1.3,
                shadows: [Shadow(color: Color(0x804CA6A8), blurRadius: 12)],
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: statusColor),
                const SizedBox(width: 5),
                Text(
                  '${_getSunPhaseLabel(mqtt.timeOfDayHours)} (${_formatTime(mqtt.timeOfDayHours)}) • Улица ${mqtt.outdoorTemp.toStringAsFixed(1)}°C',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          icon: Icon(
            mqtt.isDeveloperUnlocked ? Icons.developer_mode : Icons.tune,
            color: mqtt.isDeveloperUnlocked
                ? const Color(0xFFFFB300)
                : Colors.white70,
            size: 22,
          ),
          tooltip: 'Настройки',
          onPressed: () => setState(() => currentTabIndex = 3),
        ),
      ],
    );
  }

  // ==================== ВКЛАДКА 1: ГЛАВНАЯ ====================
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          // 3D-сцена теплицы (без желтого штыря сбоку, с нижним прикорневым поливом)
          SizedBox(
            height: 355,
            width: 395,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: InteractiveGreenhouse3DPainter(
                      roofLeftAngle: mqtt.roofLeftAngle,
                      roofRightAngle: mqtt.roofRightAngle,
                      doorFrontAngle: mqtt.doorFrontAngle,
                      doorBackAngle: mqtt.doorBackAngle,
                      isWatering: mqtt.isWateringActive,
                      isPhytoLight: mqtt.isPhytoLightActive,
                      isWhiteLight: mqtt.isWhiteLightActive,
                      timeOfDay: mqtt.timeOfDayHours,
                    ),
                  ),
                ),

                // Выноска 1 (Слева сверху): Форточки и двери
                Positioned(
                  top: 6,
                  left: 4,
                  child: _buildBadge(
                    iconColor: const Color(0xFF00E5FF),
                    title:
                        'Окна: ${mqtt.roofLeftAngle.toInt()}°/${mqtt.roofRightAngle.toInt()}° | Двери: ${mqtt.doorFrontAngle.toInt()}°/${mqtt.doorBackAngle.toInt()}°',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLiquidGlassMiniButton(
                            'Откр все', mqtt.openAllServos),
                        const SizedBox(width: 5),
                        _buildLiquidGlassMiniButton(
                            'Закр все', mqtt.closeAllServos),
                      ],
                    ),
                  ),
                ),

                // Выноска 2 (Справа сверху): DS18B20 + Свет (клик открывает порог)
                Positioned(
                  top: 64,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _showSensorThresholdDialog('outdoorTemp'),
                    child: _buildBadge(
                      iconColor: const Color(0xFF40C4FF),
                      textColor: mqtt.getSensorValueColor('outdoorTemp'),
                      title:
                          'DS18B20: ${mqtt.outdoorTemp.toStringAsFixed(1)}°C | ☀️ ${mqtt.lightLux} лк',
                      icon: Icons.ac_unit,
                    ),
                  ),
                ),

                // Выноска 3 (Справа по центру): DHT22
                Positioned(
                  top: 114,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _showSensorThresholdDialog('airTemp'),
                    child: _buildBadge(
                      iconColor: const Color(0xFF28E070),
                      textColor: mqtt.getSensorValueColor('airTemp'),
                      title:
                          'DHT22: ${mqtt.airTemp.toStringAsFixed(1)}°C | 💧 ${mqtt.airHumidity.toInt()}%',
                      icon: Icons.thermostat,
                    ),
                  ),
                ),

                // Выноска 4 (Слева снизу): MQ135 (значок всегда голубой, меняется только текст!)
                Positioned(
                  bottom: 10,
                  left: 4,
                  child: GestureDetector(
                    onTap: () => _showSensorThresholdDialog('co2'),
                    child: _buildBadge(
                      iconColor: const Color(0xFF00E5FF),
                      textColor: mqtt.getSensorValueColor('co2'),
                      title: 'MQ135: ${mqtt.co2Level} ppm',
                      icon: Icons.cloud_outlined,
                    ),
                  ),
                ),

                // Выноска 5 (Справа снизу): Почва
                Positioned(
                  bottom: 10,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _showSensorThresholdDialog('soilMoisture'),
                    child: _buildBadge(
                      iconColor: const Color(0xFF69F0AE),
                      textColor: mqtt.getSensorValueColor('soilMoisture'),
                      title:
                          'Почва: ${mqtt.soilMoisture.toInt()}% ${mqtt.isWateringActive ? "• Полив💧" : ""}',
                      icon: Icons.water_drop_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ИНТЕРАКТИВНАЯ ПАНЕЛЬ ДАТЧИКОВ: клик по любому датчику открывает настройку порога и гистерезиса!
          _buildQuickSensorsStrip(),
          const SizedBox(height: 10),

          // Блок включения светодиодных лент и полива (С УДЕРЖАНИЕМ 2.5 СЕК)
          _buildLightingAndPumpCard(),
          const SizedBox(height: 10),

          // Карточка управления 4 сервоприводами
          _buildServoControlCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Панель датчиков: иконки НЕ меняют цвет, а текст и цифры меняют (Белый -> Желтый -> Темно-оранжевый -> Красный)
  Widget _buildQuickSensorsStrip() {
    return _buildLiquidGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniSensorChip(
                sensorKey: 'airTemp',
                icon: Icons.thermostat,
                fixedIconColor: const Color(0xFF28E070),
                label: 'Внутри',
                val: '${mqtt.airTemp.toStringAsFixed(1)}°C',
              ),
              _buildMiniSensorChip(
                sensorKey: 'outdoorTemp',
                icon: Icons.ac_unit,
                fixedIconColor: const Color(0xFF40C4FF),
                label: 'DS18B20',
                val: '${mqtt.outdoorTemp.toStringAsFixed(1)}°C',
              ),
              _buildMiniSensorChip(
                sensorKey: 'lightLux',
                icon: Icons.wb_sunny_outlined,
                fixedIconColor: const Color(0xFFFFD54F),
                label: 'Свет (ФР)',
                val: '${mqtt.lightLux} лк',
              ),
              _buildMiniSensorChip(
                sensorKey: 'co2',
                icon: Icons.cloud_outlined,
                fixedIconColor: const Color(0xFF00E5FF), // Иконка всегда голубая!
                label: 'MQ135',
                val: '${mqtt.co2Level} ppm',
              ),
              _buildMiniSensorChip(
                sensorKey: 'soilMoisture',
                icon: Icons.water_drop_outlined,
                fixedIconColor: const Color(0xFF69F0AE),
                label: 'Почва',
                val: '${mqtt.soilMoisture.toInt()}%',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Нажмите на любой датчик для настройки порога тревоги и гистерезиса (%)',
            style: TextStyle(fontSize: 9.5, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSensorChip({
    required String sensorKey,
    required IconData icon,
    required Color fixedIconColor,
    required String label,
    required String val,
  }) {
    final Color valueColor = mqtt.getSensorValueColor(sensorKey);
    final Color labelColor = mqtt.getSensorLabelColor(sensorKey);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showSensorThresholdDialog(sensorKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка ВСЕГДА сохраняет свой цвет fixedIconColor
            Icon(icon, size: 17, color: fixedIconColor),
            const SizedBox(height: 4),
            // Цифра значения меняет цвет (Белый / Желтый / Темно-оранжевый / Красный)
            Text(
              val,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            // Подпись (например, MQ135) тоже меняет цвет синхронно со значением
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    valueColor == Colors.white ? FontWeight.normal : FontWeight.w700,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Диалоговое окно настройки порога и гистерезиса (%) при клике на датчик
  void _showSensorThresholdDialog(String sensorKey) {
    final cfg = mqtt.sensorConfigs[sensorKey];
    if (cfg == null) return;

    double tempThreshold = cfg.threshold;
    double tempHyst = cfg.hysteresisPercent;
    bool tempAlertHigh = cfg.alertWhenHigh;
    final threshCtrl =
        TextEditingController(text: tempThreshold.toInt().toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final double span =
                tempThreshold.abs() * (tempHyst / 100.0);
            final double yellowPoint = tempAlertHigh
                ? (tempThreshold - span)
                : (tempThreshold + span);
            final double orangePoint = tempAlertHigh
                ? (tempThreshold - span * 0.5)
                : (tempThreshold + span * 0.5);

            return AlertDialog(
              backgroundColor: const Color(0xFF0E1822),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
              ),
              title: Text(
                'Порог датчика: ${cfg.name}',
                style:
                    const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Выбор: сработка при превышении или падении
                    DropdownButtonFormField<bool>(
                      initialValue: tempAlertHigh,
                      dropdownColor: const Color(0xFF0E1822),
                      decoration: const InputDecoration(
                        labelText: 'Тип контроля предела',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('Верхний предел (опасно когда > порога)'),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text('Нижний предел (опасно когда < порога)'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => tempAlertHigh = v!),
                    ),
                    const SizedBox(height: 12),

                    // Ввод и ползунок самого порога
                    TextField(
                      controller: threshCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Порог сработки (${cfg.unit})',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          setDialogState(() {
                            tempThreshold =
                                parsed.clamp(cfg.minLimit, cfg.maxLimit);
                          });
                        }
                      },
                    ),
                    _buildNeonSlider(
                      value: tempThreshold.clamp(cfg.minLimit, cfg.maxLimit),
                      min: cfg.minLimit,
                      max: cfg.maxLimit,
                      activeColor: const Color(0xFFFF3D00),
                      onChanged: (v) {
                        setDialogState(() {
                          tempThreshold = v;
                          threshCtrl.text = v.toInt().toString();
                        });
                      },
                      onChangeEnd: (_) {},
                    ),
                    const SizedBox(height: 8),

                    // Ползунок гистерезиса в процентах
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Гистерезис предтревоги:',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          '${tempHyst.toInt()}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFD54F),
                          ),
                        ),
                      ],
                    ),
                    _buildNeonSlider(
                      value: tempHyst,
                      min: 2.0,
                      max: 35.0,
                      activeColor: const Color(0xFFFFD54F),
                      onChanged: (v) => setDialogState(() => tempHyst = v),
                      onChangeEnd: (_) {},
                    ),
                    const SizedBox(height: 8),

                    // Наглядная подсказка, при каких значениях какого цвета будет текст
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Цветовая индикация текста и значения:',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• Желтый: с ${yellowPoint.toStringAsFixed(0)}${cfg.unit}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '• Темно-оранжевый: с ${orangePoint.toStringAsFixed(0)}${cfg.unit}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFF6D00),
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '• Красный (предел): ${tempAlertHigh ? "≥" : "≤"} ${tempThreshold.toStringAsFixed(0)}${cfg.unit}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFFF3D00),
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    mqtt.updateSensorThreshold(
                      sensorKey,
                      threshold: tempThreshold,
                      hysteresisPercent: tempHyst,
                      alertWhenHigh: tempAlertHigh,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Карточка включения LED-лент и Насоса с удержанием 2.5 сек
  Widget _buildLightingAndPumpCard() {
    return _buildLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'СИЛОВЫЕ НАГРУЗКИ (MOSFET IRLZ44N)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                'Удерживайте 2.5 сек',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFFFFD54F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: HoldToToggleGlassButton(
                  label: 'Фито-лента',
                  subtitle: mqtt.isPhytoLightActive ? 'Спектр ВКЛ' : 'ВЫКЛ',
                  icon: Icons.wb_iridescent,
                  isActive: mqtt.isPhytoLightActive,
                  activeColor: const Color(0xFFFF40E5),
                  onConfirmed: mqtt.togglePhytoLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HoldToToggleGlassButton(
                  label: 'Белый LED',
                  subtitle: mqtt.isWhiteLightActive ? 'Дневной ВКЛ' : 'ВЫКЛ',
                  icon: Icons.flourescent,
                  isActive: mqtt.isWhiteLightActive,
                  activeColor: const Color(0xFFFFEE58),
                  onConfirmed: mqtt.toggleWhiteLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HoldToToggleGlassButton(
                  label: 'Полив снизу',
                  subtitle: mqtt.isWateringActive ? 'Насос ВКЛ' : 'ВЫКЛ',
                  icon: Icons.water_drop,
                  isActive: mqtt.isWateringActive,
                  activeColor: const Color(0xFF00E5FF),
                  onConfirmed: mqtt.toggleWatering,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== КАРТОЧКА 4 СЕРВОПРИВОДОВ ====================
  Widget _buildServoControlCard() {
    final bool anyOpen = mqtt.roofLeftAngle > 0 ||
        mqtt.roofRightAngle > 0 ||
        mqtt.doorFrontAngle > 0 ||
        mqtt.doorBackAngle > 0;

    return _buildLiquidGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'УПРАВЛЕНИЕ 4 СЕРВОПРИВОДАМИ (SG90)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Лимиты: Окна до ${mqtt.maxRoofAngleLimit.toInt()}° | Двери до ${mqtt.maxDoorAngleLimit.toInt()}°',
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xFF00E5FF)),
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.82,
                child: Switch(
                  value: anyOpen,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF28E070),
                  onChanged: (val) =>
                      val ? mqtt.openAllServos() : mqtt.closeAllServos(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildServoRow(
            label: '1. Левое окно (дальнее):',
            angle: mqtt.roofLeftAngle,
            maxLimit: mqtt.maxRoofAngleLimit,
            color: const Color(0xFF00E5FF),
            onChanged: (v) => mqtt.setRoofLeftAngle(v),
            onChangeEnd: (v) => mqtt.setRoofLeftAngle(v, log: true),
          ),
          _buildServoRow(
            label: '2. Правое окно (ближе к фасаду):',
            angle: mqtt.roofRightAngle,
            maxLimit: mqtt.maxRoofAngleLimit,
            color: const Color(0xFF40C4FF),
            onChanged: (v) => mqtt.setRoofRightAngle(v),
            onChangeEnd: (v) => mqtt.setRoofRightAngle(v, log: true),
          ),
          _buildServoRow(
            label: '3. Передняя лицевая дверь:',
            angle: mqtt.doorFrontAngle,
            maxLimit: mqtt.maxDoorAngleLimit,
            color: const Color(0xFF28E070),
            onChanged: (v) => mqtt.setDoorFrontAngle(v),
            onChangeEnd: (v) => mqtt.setDoorFrontAngle(v, log: true),
          ),
          _buildServoRow(
            label: '4. Задняя торцевая дверь:',
            angle: mqtt.doorBackAngle,
            maxLimit: mqtt.maxDoorAngleLimit,
            color: const Color(0xFF69F0AE),
            onChanged: (v) => mqtt.setDoorBackAngle(v),
            onChangeEnd: (v) => mqtt.setDoorBackAngle(v, log: true),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildLiquidGlassActionButton(
                  'ОТКРЫТЬ ВСЕ ДО ЛИМИТА',
                  mqtt.openAllServos,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLiquidGlassActionButton(
                  'ЗАКРЫТЬ ВСЕ (0°)',
                  mqtt.closeAllServos,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServoRow({
    required String label,
    required double angle,
    required double maxLimit,
    required Color color,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
            Text(
              '${angle.toInt()}° / макс ${maxLimit.toInt()}°',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        _buildNeonSlider(
          value: angle.clamp(0.0, maxLimit),
          max: maxLimit,
          activeColor: color,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }

  Widget _buildNeonSlider({
    required double value,
    double min = 0.0,
    double max = 90.0,
    Color activeColor = const Color(0xFF00E5FF),
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: activeColor,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        thumbColor: Colors.white,
        overlayColor: activeColor.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
        trackHeight: 3.5,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }

  // ==================== ВКЛАДКА 2: СЦЕНАРИИ ====================
  Widget _buildScenariosTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'АВТОСЦЕНАРИИ ESP32-S3',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70),
            ),
            _buildLiquidGlassMiniButton(
              '+ Добавить сценарий',
              _showAddScenarioDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...mqtt.rules.map(
          (rule) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildLiquidGlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: _buildScenarioTile(
                      title: rule.name,
                      subtitle: rule.subtitle,
                      value: rule.isEnabled,
                      onChanged: (val) => mqtt.toggleRule(rule.id, val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white38, size: 19),
                    tooltip: 'Удалить сценарий',
                    onPressed: () => mqtt.deleteRule(rule.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddScenarioDialog() {
    final nameCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '28');
    String selectedSensor = 'airTemp';
    bool isGreater = true;
    String selectedAction = 'openVents';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF101C26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF00E5FF), width: 1),
              ),
              title: const Text(
                'Новый сценарий автоматики',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Название сценария',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSensor,
                      dropdownColor: const Color(0xFF101C26),
                      decoration:
                          const InputDecoration(labelText: 'Датчик условия'),
                      items: const [
                        DropdownMenuItem(
                            value: 'airTemp',
                            child: Text('T внутри DHT22 (°C)')),
                        DropdownMenuItem(
                            value: 'outdoorTemp',
                            child: Text('T улицы DS18B20 (°C)')),
                        DropdownMenuItem(
                            value: 'soilMoisture',
                            child: Text('Влажность почвы (%)')),
                        DropdownMenuItem(
                            value: 'lightLux',
                            child: Text('Освещенность ФР (Lux)')),
                        DropdownMenuItem(
                            value: 'co2',
                            child: Text('Качество воздуха MQ135 (ppm)')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedSensor = v!),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<bool>(
                            initialValue: isGreater,
                            dropdownColor: const Color(0xFF101C26),
                            decoration:
                                const InputDecoration(labelText: 'Условие'),
                            items: const [
                              DropdownMenuItem(
                                  value: true, child: Text('Больше (>)')),
                              DropdownMenuItem(
                                  value: false, child: Text('Меньше (<)')),
                            ],
                            onChanged: (v) =>
                                setDialogState(() => isGreater = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: thresholdCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Порог'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedAction,
                      dropdownColor: const Color(0xFF101C26),
                      decoration: const InputDecoration(
                          labelText: 'Выполнить действие'),
                      items: const [
                        DropdownMenuItem(
                            value: 'openVents',
                            child: Text('Открыть окна до лимита')),
                        DropdownMenuItem(
                            value: 'closeVents',
                            child: Text('Закрыть все окна и двери')),
                        DropdownMenuItem(
                            value: 'waterOn',
                            child: Text('Включить полив')),
                        DropdownMenuItem(
                            value: 'phytoOn', child: Text('Включить Фито-LED')),
                        DropdownMenuItem(
                            value: 'whiteOn',
                            child: Text('Включить Белый LED')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedAction = v!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim().isEmpty
                        ? 'Пользовательский сценарий'
                        : nameCtrl.text.trim();
                    final th = double.tryParse(thresholdCtrl.text) ?? 25.0;
                    mqtt.addCustomRule(
                      name: name,
                      sensorType: selectedSensor,
                      isGreater: isGreater,
                      threshold: th,
                      actionType: selectedAction,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Создать'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== ВКЛАДКА 3: ИСТОРИЯ И ЖУРНАЛ ====================
  Widget _buildHistoryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ТЕЛЕМЕТРИЯ ВСЕХ ДАТЧИКОВ КОНТРОЛЛЕРА',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricColumn(
                    'Внутри (DHT22)',
                    '${mqtt.airTemp.toStringAsFixed(1)}°C',
                    mqtt.getSensorValueColor('airTemp'),
                  ),
                  _buildMetricColumn(
                    'Улица (DS18B20)',
                    '${mqtt.outdoorTemp.toStringAsFixed(1)}°C',
                    mqtt.getSensorValueColor('outdoorTemp'),
                  ),
                  _buildMetricColumn(
                    'Влажность',
                    '${mqtt.airHumidity.toInt()}%',
                    Colors.white,
                  ),
                  _buildMetricColumn(
                    'Почва',
                    '${mqtt.soilMoisture.toInt()}%',
                    mqtt.getSensorValueColor('soilMoisture'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricColumn(
                    'Свет (ФР)',
                    '${mqtt.lightLux} лк',
                    mqtt.getSensorValueColor('lightLux'),
                  ),
                  _buildMetricColumn(
                    'MQ135',
                    '${mqtt.co2Level} ppm',
                    mqtt.getSensorValueColor('co2'),
                  ),
                  _buildMetricColumn(
                    'Питание',
                    '${mqtt.voltage.toStringAsFixed(1)} В',
                    Colors.white,
                  ),
                  _buildMetricColumn(
                    'Время RTC',
                    _formatTime(mqtt.timeOfDayHours),
                    Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'ЖУРНАЛ СОБЫТИЙ СИСТЕМЫ',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white70),
        ),
        const SizedBox(height: 10),
        _buildLiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: mqtt.eventLogs
                .map(
                  (log) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      log,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: valueColor)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: valueColor == Colors.white ? Colors.white54 : valueColor)),
      ],
    );
  }

  // ==================== ВКЛАДКА 4: НАСТРОЙКИ (ПОРОГИ + ГИСТЕРЕЗИС БЕЗ ПАРОЛЯ) ====================
  Widget _buildSettingsTab() {
    final roofLimitCtrl =
        TextEditingController(text: mqtt.maxRoofAngleLimit.toInt().toString());
    final doorLimitCtrl =
        TextEditingController(text: mqtt.maxDoorAngleLimit.toInt().toString());
    final pinCtrl = TextEditingController();
    final brokerCtrl = TextEditingController(text: mqtt.broker);
    final userCtrl = TextEditingController(text: mqtt.username);
    final passCtrl = TextEditingController(text: mqtt.password);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. НАСТРОЙКА ПОРОГОВ СРАБОТКИ И ГИСТЕРЕЗИСА (%) ДЛЯ ВСЕХ ДАТЧИКОВ (В ОБЫЧНЫХ НАСТРОЙКАХ!)
        _buildLiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ПОРОГИ ТРЕВОГИ И ГИСТЕРЕЗИС ДАТЧИКОВ',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Нажмите на датчик, чтобы задать порог и гистерезис (%). При подходе к порогу текст и цифра станут желтыми, затем темно-оранжевыми, а за пределом — красными.',
                style: TextStyle(fontSize: 10.5, color: Colors.white54),
              ),
              const SizedBox(height: 10),
              ...mqtt.sensorConfigs.entries.map((entry) {
                final cfg = entry.value;
                final valColor = mqtt.getSensorValueColor(cfg.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showSensorThresholdDialog(cfg.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cfg.name,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: valColor,
                                ),
                              ),
                              Text(
                                'Порог: ${cfg.alertWhenHigh ? ">" : "<"} ${cfg.threshold.toInt()}${cfg.unit} • Гистерезис: ${cfg.hysteresisPercent.toInt()}%',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white60),
                              ),
                            ],
                          ),
                          const Icon(Icons.edit_outlined,
                              size: 18, color: Color(0xFF00E5FF)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. ОГРАНИЧЕНИЯ УГЛОВ СЕРВОПРИВОДОВ
        _buildLiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'МЕХАНИЧЕСКИЕ ОГРАНИЧЕНИЯ УГЛОВ (SG90)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: roofLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Макс. угол ОКОН (10..90°)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: doorLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Макс. угол ДВЕРЕЙ (10..90°)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildLiquidGlassActionButton(
                  'ПРИМЕНИТЬ ОГРАНИЧЕНИЯ УГЛОВ',
                  () {
                    final rMax = double.tryParse(roofLimitCtrl.text) ??
                        mqtt.maxRoofAngleLimit;
                    final dMax = double.tryParse(doorLimitCtrl.text) ??
                        mqtt.maxDoorAngleLimit;
                    mqtt.setServoLimits(rMax, dMax);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Лимиты сохранены: Окна до ${mqtt.maxRoofAngleLimit.toInt()}°, Двери до ${mqtt.maxDoorAngleLimit.toInt()}°'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. РЕЖИМ РАЗРАБОТЧИКА (ПАРОЛЬ 0000)
        _buildLiquidGlassCard(
          child: !mqtt.isDeveloperUnlocked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline,
                            color: Color(0xFFFFB300), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'РЕЖИМ РАЗРАБОТЧИКА И СИМУЛЯЦИЯ (DEV)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFB300),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Введите пин-код (0000) для имитации показаний датчиков и проверки цветовой индикации порогов.',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pinCtrl,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Пин-код (0000)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildLiquidGlassActionButton('РАЗБЛОКИРОВАТЬ', () {
                          final ok = mqtt.unlockDeveloperMode(pinCtrl.text);
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Неверный пин-код! Введите 0000')),
                            );
                          }
                        }),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.developer_board,
                                color: Color(0xFF28E070), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'ИНЖЕНЕРНЫЙ СТЕНД СИМУЛЯЦИИ (DEV)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF28E070),
                              ),
                            ),
                          ],
                        ),
                        _buildLiquidGlassMiniButton(
                            'Выйти', mqtt.lockDeveloperMode),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '☀️ Небесный цикл (DS3231): ${_formatTime(mqtt.timeOfDayHours)} (${_getSunPhaseLabel(mqtt.timeOfDayHours)})',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    _buildNeonSlider(
                      value: mqtt.timeOfDayHours,
                      max: 24.0,
                      activeColor: const Color(0xFFFFD54F),
                      onChanged: (v) => mqtt.setTimeOfDay(v),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildLiquidGlassMiniButton(
                            '🌅 Рассвет 07:00', () => mqtt.setTimeOfDay(7.0)),
                        _buildLiquidGlassMiniButton(
                            '☀️ Полдень 13:00', () => mqtt.setTimeOfDay(13.0)),
                        _buildLiquidGlassMiniButton(
                            '🌇 Закат 19:00', () => mqtt.setTimeOfDay(19.0)),
                        _buildLiquidGlassMiniButton(
                            '🌙 Ночь 23:00', () => mqtt.setTimeOfDay(23.0)),
                      ],
                    ),
                    const Divider(height: 20, color: Colors.white12),
                    Text(
                        '🌡️ Температура внутри (DHT22): ${mqtt.airTemp.toStringAsFixed(1)}°C',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: mqtt.getSensorValueColor('airTemp'))),
                    _buildNeonSlider(
                      value: mqtt.airTemp,
                      min: 5.0,
                      max: 45.0,
                      onChanged: (v) =>
                          mqtt.updateSimulatedSensor(newAirTemp: v),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                    Text(
                        '❄️ Температура снаружи (DS18B20): ${mqtt.outdoorTemp.toStringAsFixed(1)}°C',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: mqtt.getSensorValueColor('outdoorTemp'))),
                    _buildNeonSlider(
                      value: mqtt.outdoorTemp,
                      min: -15.0,
                      max: 40.0,
                      activeColor: const Color(0xFF40C4FF),
                      onChanged: (v) =>
                          mqtt.updateSimulatedSensor(newOutdoorTemp: v),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                    Text(
                        '💧 Влажность почвы: ${mqtt.soilMoisture.toInt()}%',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: mqtt.getSensorValueColor('soilMoisture'))),
                    _buildNeonSlider(
                      value: mqtt.soilMoisture,
                      min: 0.0,
                      max: 100.0,
                      activeColor: const Color(0xFF28E070),
                      onChanged: (v) => mqtt.updateSimulatedSensor(newSoil: v),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                    Text(
                        '💡 Уровень освещенности (ФР): ${mqtt.lightLux} Lux',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: mqtt.getSensorValueColor('lightLux'))),
                    _buildNeonSlider(
                      value: mqtt.lightLux.toDouble(),
                      min: 0.0,
                      max: 1000.0,
                      activeColor: const Color(0xFFFF40E5),
                      onChanged: (v) =>
                          mqtt.updateSimulatedSensor(newLux: v.toInt()),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                    Text(
                        '🫧 Качество воздуха (MQ135): ${mqtt.co2Level} ppm',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: mqtt.getSensorValueColor('co2'))),
                    _buildNeonSlider(
                      value: mqtt.co2Level.toDouble(),
                      min: 300.0,
                      max: 2000.0,
                      activeColor: const Color(0xFFFF7043),
                      onChanged: (v) =>
                          mqtt.updateSimulatedSensor(newCo2: v.toInt()),
                      onChangeEnd: (_) => mqtt.saveToCache(),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // 4. НАСТРОЙКИ БРОКЕРА MQTT
        _buildLiquidGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ПАРАМЕТРЫ БРОКЕРА HIVEMQ CLOUD',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00E5FF)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brokerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Хост брокера (Cluster URL)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Логин (Username)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль (Password)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _buildLiquidGlassActionButton(
                  'СОХРАНИТЬ И ПОДКЛЮЧИТЬСЯ К БРОКЕРУ',
                  () {
                    mqtt.broker = brokerCtrl.text.trim();
                    mqtt.username = userCtrl.text.trim();
                    mqtt.password = passCtrl.text.trim();
                    mqtt.connect();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== МЕТОДЫ ЖИДКОГО СТЕКЛА ====================
  Widget _buildLiquidGlassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
              width: 1.2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                const Color(0xFF4CA6A8).withValues(alpha: 0.08),
                Colors.black.withValues(alpha: 0.38),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildLiquidGlassActionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  const Color(0xFF00E5FF).withValues(alpha: 0.22),
                  const Color(0xFF0C222C).withValues(alpha: 0.65),
                ],
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidGlassMiniButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.22),
              const Color(0xFF00E5FF).withValues(alpha: 0.14),
            ],
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // Плашка на 3D-сцене: иконка ВСЕГДА цвета iconColor, а текст окрашивается в textColor
  Widget _buildBadge({
    required String title,
    IconData? icon,
    Widget? child,
    Color iconColor = const Color(0xFF00E5FF),
    Color textColor = Colors.white,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xCC0A131A),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: iconColor.withValues(alpha: 0.55), width: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    // Значок не меняет цвет при тревоге!
                    Icon(icon, size: 13, color: iconColor),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
              if (child != null) ...[
                const SizedBox(height: 4),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScenarioTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: value ? const Color(0xFF28E070) : Colors.white38,
                ),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.82,
          child: Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF28E070),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassNavigationBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: const Color(0xCC080E14),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: BottomNavigationBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                currentIndex: currentTabIndex,
                selectedItemColor: const Color(0xFF00E5FF),
                unselectedItemColor: Colors.white38,
                selectedLabelStyle:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                type: BottomNavigationBarType.fixed,
                onTap: (idx) => setState(() => currentTabIndex = idx),
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.home_filled, size: 22), label: 'Главная'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.auto_awesome_motion, size: 22),
                      label: 'Сценарии'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.history, size: 22), label: 'История'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.settings, size: 22), label: 'Настройки'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// КНОПКА С УДЕРЖАНИЕМ 2.5 СЕКУНДЫ
// =========================================================================
class HoldToToggleGlassButton extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onConfirmed;

  const HoldToToggleGlassButton({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onConfirmed,
  });

  @override
  State<HoldToToggleGlassButton> createState() =>
      _HoldToToggleGlassButtonState();
}

class _HoldToToggleGlassButtonState extends State<HoldToToggleGlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdCtrl;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onConfirmed();
          _holdCtrl.reset();
        }
      });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    super.dispose();
  }

  void _startHold() => _holdCtrl.forward();

  void _cancelHold() {
    if (_holdCtrl.isAnimating) {
      _holdCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      onTap: () {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 1),
            content: Text(
                'Удерживайте кнопку "${widget.label}" 2.5 сек для переключения'),
          ),
        );
      },
      child: AnimatedBuilder(
        animation: _holdCtrl,
        builder: (context, _) {
          final double progress = _holdCtrl.value;
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor: progress,
                    child: Container(
                      color: widget.activeColor.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: progress > 0
                          ? Colors.white
                          : (widget.isActive
                              ? widget.activeColor.withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.16)),
                      width: progress > 0 ? 1.8 : 1.3,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.isActive
                          ? [
                              widget.activeColor.withValues(alpha: 0.35),
                              widget.activeColor.withValues(alpha: 0.10),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.09),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        widget.icon,
                        color: widget.isActive
                            ? widget.activeColor
                            : Colors.white60,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        progress > 0.05
                            ? 'Ждите ${(progress * 100).toInt()}%...'
                            : widget.subtitle,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: progress > 0.05
                              ? Colors.white
                              : (widget.isActive
                                  ? widget.activeColor
                                  : Colors.white38),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// 3D-ДВИЖОК ТЕПЛИЦЫ (БЕЗ ЖЕЛТОГО ШТЫРЯ СБОКУ + НИЖНИЙ ПРИКОРНЕВОЙ ПОЛИВ)
// =========================================================================
class InteractiveGreenhouse3DPainter extends CustomPainter {
  final double roofLeftAngle;
  final double roofRightAngle;
  final double doorFrontAngle;
  final double doorBackAngle;
  final bool isWatering;
  final bool isPhytoLight;
  final bool isWhiteLight;
  final double timeOfDay;

  InteractiveGreenhouse3DPainter({
    required this.roofLeftAngle,
    required this.roofRightAngle,
    required this.doorFrontAngle,
    required this.doorBackAngle,
    required this.isWatering,
    required this.isPhytoLight,
    required this.isWhiteLight,
    required this.timeOfDay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width * 0.48;
    final double cy = size.height * 0.58;

    Offset iso(double x, double y, double z) {
      final double px = cx + (x - y) * 0.866;
      final double py = cy + (x + y) * 0.5 - z;
      return Offset(px, py);
    }

    // 1. НЕБОСВОД
    _drawSkyCelestialBody(canvas, size);

    // 2. ПОДСВЕТКА ОСНОВАНИЯ
    Color ambientColor = const Color(0xFF00E5FF);
    if (isPhytoLight && isWhiteLight) {
      ambientColor = const Color(0xFFFFB2FF);
    } else if (isPhytoLight) {
      ambientColor = const Color(0xFFFF40E5);
    } else if (isWhiteLight) {
      ambientColor = const Color(0xFFFFF59D);
    }

    final baseGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          ambientColor.withValues(
              alpha: (isPhytoLight || isWhiteLight) ? 0.36 : 0.2),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy + 35), radius: 165));
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 40), width: 320, height: 155),
        baseGlow);

    // 3. ФУНДАМЕНТ И ПОЧВА
    _drawPoly(
      canvas,
      [iso(-80, -98, -8), iso(80, -98, -8), iso(80, 98, -8), iso(-80, 98, -8)],
      const Color(0xFF17212A),
      const Color(0xFF3A5060),
    );
    _drawPoly(
      canvas,
      [iso(-74, -92, 0), iso(74, -92, 0), iso(74, 92, 0), iso(-74, 92, 0)],
      const Color(0xFF2B2017),
      const Color(0xFF4CA6A8).withValues(alpha: 0.45),
    );

    // 4. ЗАДНЯЯ СТЕНКА И ЗАДНЯЯ ДВЕРЬ
    final glassFill = const Color(0xFF00E5FF).withValues(alpha: 0.11);
    final frameEdge = const Color(0xFF5CE1E6).withValues(alpha: 0.75);

    _drawPoly(
      canvas,
      [iso(-74, -92, 0), iso(-25, -92, 0), iso(-25, -92, 76), iso(-74, -92, 76)],
      glassFill,
      frameEdge,
    );
    _drawPoly(
      canvas,
      [iso(25, -92, 0), iso(74, -92, 0), iso(74, -92, 76), iso(25, -92, 76)],
      glassFill,
      frameEdge,
    );
    _drawPoly(
      canvas,
      [iso(-74, -92, 76), iso(74, -92, 76), iso(0, -92, 128)],
      glassFill,
      frameEdge,
    );

    const double backDoorW = 50.0;
    final double backRad = doorBackAngle * math.pi / 180.0;
    final double bdx = -25.0 + backDoorW * math.cos(backRad);
    final double bdy = -92.0 - backDoorW * math.sin(backRad);

    _drawPoly(
      canvas,
      [
        iso(-25, -92, 0),
        iso(bdx, bdy, 0),
        iso(bdx, bdy, 74),
        iso(-25, -92, 74),
      ],
      const Color(0xFF69F0AE).withValues(alpha: 0.28),
      const Color(0xFF69F0AE),
      strokeWidth: 2.0,
    );

    // 5. ГРЯДКИ С РАСТЕНИЯМИ
    _drawBedWithPlants(canvas, iso, -56, -16, -78, 74);
    _drawBedWithPlants(canvas, iso, 16, 56, -78, 74);

    // 6. НИЖНИЙ ПРИКОРНЕВОЙ ПОЛИВ (прямо на земле у корней грядок!)
    if (isWatering) {
      _drawGroundLevelWatering(canvas, iso);
    }

    // 7. СВЕТОДИОДНЫЕ ЛЕНТЫ ПОД КОНЬКОМ
    _drawInternalLedStrips(canvas, iso);

    // 8. БОКОВЫЕ СТЕНЫ И КРЫША
    _drawPoly(
      canvas,
      [iso(-74, -92, 0), iso(-74, 92, 0), iso(-74, 92, 76), iso(-74, -92, 76)],
      glassFill,
      frameEdge,
    );
    for (double y = -92; y < 88; y += 46) {
      _drawPoly(
        canvas,
        [iso(74, y, 0), iso(74, y + 46, 0), iso(74, y + 46, 76), iso(74, y, 76)],
        const Color(0xFF00E5FF).withValues(alpha: 0.13),
        frameEdge,
      );
    }

    _drawPoly(
      canvas,
      [iso(0, -92, 128), iso(74, -92, 76), iso(74, 92, 76), iso(0, 92, 128)],
      const Color(0xFF00E5FF).withValues(alpha: 0.15),
      frameEdge,
    );
    _drawPoly(
      canvas,
      [iso(0, -92, 128), iso(-74, -92, 76), iso(-74, 92, 76), iso(0, 92, 128)],
      const Color(0xFF00E5FF).withValues(alpha: 0.12),
      frameEdge,
    );

    // 9. ФОРТОЧКА №1 (Левый дальний скат)
    final double basePitch = math.atan2(52, 74);
    final double openRadLeft =
        basePitch - (roofLeftAngle * math.pi / 180.0) * 0.85;
    const double ventLen = 54.0;
    final double vlx = -math.cos(openRadLeft) * ventLen;
    final double vlz = 128.0 - math.sin(openRadLeft) * ventLen;

    _drawPoly(
      canvas,
      [iso(0, -68, 128), iso(-48, -68, 94), iso(-48, -12, 94), iso(0, -12, 128)],
      const Color(0xFF071016).withValues(alpha: 0.7),
      const Color(0xFF00E5FF).withValues(alpha: 0.4),
    );
    _drawPoly(
      canvas,
      [iso(0, -68, 128), iso(vlx, -68, vlz), iso(vlx, -12, vlz), iso(0, -12, 128)],
      const Color(0xFF00F0FF).withValues(alpha: 0.38),
      const Color(0xFF90FFFF),
      strokeWidth: 2.1,
    );
    canvas.drawLine(
      iso(-25, -40, 110),
      iso(vlx * 0.65, -40, vlz + 2),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 2.0,
    );

    // 10. ФОРТОЧКА №2 (Правый ближний скат)
    final double openRadRight =
        basePitch - (roofRightAngle * math.pi / 180.0) * 0.85;
    final double vrx = math.cos(openRadRight) * ventLen;
    final double vrz = 128.0 - math.sin(openRadRight) * ventLen;

    _drawPoly(
      canvas,
      [iso(0, 12, 128), iso(48, 12, 94), iso(48, 68, 94), iso(0, 68, 128)],
      const Color(0xFF071016).withValues(alpha: 0.7),
      const Color(0xFF40C4FF).withValues(alpha: 0.45),
    );
    _drawPoly(
      canvas,
      [iso(0, 12, 128), iso(vrx, 12, vrz), iso(vrx, 68, vrz), iso(0, 68, 128)],
      const Color(0xFF40C4FF).withValues(alpha: 0.42),
      const Color(0xFFB3E5FC),
      strokeWidth: 2.2,
    );
    canvas.drawLine(
      iso(25, 40, 110),
      iso(vrx * 0.65, 40, vrz + 2),
      Paint()
        ..color = const Color(0xFF40C4FF)
        ..strokeWidth = 2.0,
    );

    // 11. ПЕРЕДНИЙ ФАСАД И ПЕРЕДНЯЯ ДВЕРЬ
    _drawPoly(
      canvas,
      [iso(-74, 92, 0), iso(-25, 92, 0), iso(-25, 92, 76), iso(-74, 92, 76)],
      glassFill,
      frameEdge,
    );
    _drawPoly(
      canvas,
      [iso(25, 92, 0), iso(74, 92, 0), iso(74, 92, 76), iso(25, 92, 76)],
      glassFill,
      frameEdge,
    );
    _drawPoly(
      canvas,
      [iso(-74, 92, 76), iso(74, 92, 76), iso(0, 92, 128)],
      const Color(0xFF00E5FF).withValues(alpha: 0.16),
      frameEdge,
    );

    const double frontDoorW = 50.0;
    final double fRad = doorFrontAngle * math.pi / 180.0;
    final double fdx = -25.0 + frontDoorW * math.cos(fRad);
    final double fdy = 92.0 + frontDoorW * math.sin(fRad);

    _drawPoly(
      canvas,
      [
        iso(-25, 92, 0),
        iso(fdx, fdy, 0),
        iso(fdx, fdy, 74),
        iso(-25, 92, 74),
      ],
      const Color(0xFF28E070).withValues(alpha: 0.30),
      const Color(0xFF76FFAC),
      strokeWidth: 2.2,
    );
  }

  // Нижний прикорневой полив прямо на уровне грядок (z = 6..18)
  void _drawGroundLevelWatering(
      Canvas canvas, Offset Function(double, double, double) iso) {
    final hosePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    // Прикорневые шланги капельно-веерного полива лежат прямо вдоль земли (z = 7)
    canvas.drawLine(iso(-18, -72, 7), iso(-18, 68, 7), hosePaint);
    canvas.drawLine(iso(18, -72, 7), iso(18, 68, 7), hosePaint);

    final streamPaint = Paint()
      ..color = const Color(0xFF80F8FF).withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final dropPaint = Paint()..color = const Color(0xFF00E5FF);

    for (double y = -58; y <= 58; y += 28) {
      // Левая грядка: короткие полосочки струй бьют снизу (z=7) к корням кустов (-36, y, 14)
      final Offset leftNozzle = iso(-18, y, 7);
      canvas.drawLine(leftNozzle, iso(-32, y - 5, 15), streamPaint);
      canvas.drawLine(leftNozzle, iso(-35, y, 16), streamPaint);
      canvas.drawLine(leftNozzle, iso(-32, y + 5, 15), streamPaint);
      canvas.drawCircle(iso(-38, y, 9), 2.6, dropPaint);

      // Правая грядка: короткие полосочки струй бьют снизу (z=7) к корням кустов (36, y, 14)
      final Offset rightNozzle = iso(18, y, 7);
      canvas.drawLine(rightNozzle, iso(32, y - 5, 15), streamPaint);
      canvas.drawLine(rightNozzle, iso(35, y, 16), streamPaint);
      canvas.drawLine(rightNozzle, iso(32, y + 5, 15), streamPaint);
      canvas.drawCircle(iso(38, y, 9), 2.6, dropPaint);
    }
  }

  void _drawInternalLedStrips(
      Canvas canvas, Offset Function(double, double, double) iso) {
    if (isPhytoLight) {
      _drawPoly(
        canvas,
        [
          iso(-24, -76, 102),
          iso(-58, -78, 6),
          iso(-14, 76, 6),
          iso(-24, 76, 102)
        ],
        const Color(0xFFFF00D4).withValues(alpha: 0.14),
        Colors.transparent,
      );
      canvas.drawLine(
        iso(-24, -80, 102),
        iso(-24, 80, 102),
        Paint()
          ..color = const Color(0xFFFF40E5).withValues(alpha: 0.75)
          ..strokeWidth = 10.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    _drawPoly(
      canvas,
      [
        iso(-27, -82, 103),
        iso(-21, -82, 103),
        iso(-21, 82, 103),
        iso(-27, 82, 103)
      ],
      isPhytoLight ? const Color(0xFF4A154B) : const Color(0xFF1C2833),
      isPhytoLight ? const Color(0xFFFF80FC) : Colors.white24,
      strokeWidth: 1.1,
    );

    if (isPhytoLight) {
      canvas.drawLine(
        iso(-24, -80, 102.5),
        iso(-24, 80, 102.5),
        Paint()
          ..color = const Color(0xFFFFB2FF)
          ..strokeWidth = 2.6,
      );
      int idx = 0;
      for (double y = -74; y <= 74; y += 14) {
        final c = idx.isEven
            ? const Color(0xFFFF4081)
            : const Color(0xFFE040FB);
        canvas.drawCircle(iso(-24, y, 102.5), 2.4, Paint()..color = c);
        idx++;
      }
    }

    if (isWhiteLight) {
      _drawPoly(
        canvas,
        [
          iso(24, -76, 102),
          iso(14, -78, 6),
          iso(58, 76, 6),
          iso(24, 76, 102)
        ],
        const Color(0xFFFFF59D).withValues(alpha: 0.15),
        Colors.transparent,
      );
      canvas.drawLine(
        iso(24, -80, 102),
        iso(24, 80, 102),
        Paint()
          ..color = const Color(0xFFFFEE58).withValues(alpha: 0.7)
          ..strokeWidth = 10.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    _drawPoly(
      canvas,
      [
        iso(21, -82, 103),
        iso(27, -82, 103),
        iso(27, 82, 103),
        iso(21, 82, 103)
      ],
      isWhiteLight ? const Color(0xFF4D4422) : const Color(0xFF1C2833),
      isWhiteLight ? const Color(0xFFFFF59D) : Colors.white24,
      strokeWidth: 1.1,
    );

    if (isWhiteLight) {
      canvas.drawLine(
        iso(24, -80, 102.5),
        iso(24, 80, 102.5),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.6,
      );
      for (double y = -74; y <= 74; y += 14) {
        canvas.drawCircle(
            iso(24, y, 102.5), 2.3, Paint()..color = const Color(0xFFFFFDE7));
      }
    }
  }

  void _drawSkyCelestialBody(Canvas canvas, Size size) {
    final bool isDay = timeOfDay >= 6.0 && timeOfDay <= 20.0;
    final double progress = isDay
        ? ((timeOfDay - 6.0) / 14.0).clamp(0.0, 1.0)
        : (((timeOfDay > 20.0 ? timeOfDay - 20.0 : timeOfDay + 4.0)) / 10.0)
            .clamp(0.0, 1.0);

    final double arcX = 45 + progress * (size.width - 90);
    final double arcY = 125 - math.sin(progress * math.pi) * 85;
    final Offset center = Offset(arcX, arcY);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final trackPath = Path();
    for (double t = 0; t <= 1.0; t += 0.05) {
      final px = 45 + t * (size.width - 90);
      final py = 125 - math.sin(t * math.pi) * 85;
      if (t == 0) {
        trackPath.moveTo(px, py);
      } else {
        trackPath.lineTo(px, py);
      }
    }
    canvas.drawPath(trackPath, trackPaint);

    if (isDay) {
      final bool isSunsetOrSunrise = timeOfDay < 8.0 || timeOfDay > 18.0;
      final Color sunColor = isSunsetOrSunrise
          ? const Color(0xFFFF6D3A)
          : const Color(0xFFFFD54F);

      canvas.drawCircle(
        center,
        28,
        Paint()
          ..shader = RadialGradient(
            colors: [
              sunColor.withValues(alpha: 0.55),
              sunColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 28)),
      );
      canvas.drawCircle(center, 11, Paint()..color = sunColor);
    } else {
      final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.45);
      canvas.drawCircle(const Offset(60, 40), 1.2, starPaint);
      canvas.drawCircle(const Offset(140, 25), 1.5, starPaint);
      canvas.drawCircle(const Offset(290, 35), 1.2, starPaint);
      canvas.drawCircle(const Offset(340, 65), 1.4, starPaint);

      canvas.drawCircle(
        center,
        18,
        Paint()..color = const Color(0xFF90CAF9).withValues(alpha: 0.2),
      );
      canvas.drawCircle(center, 9, Paint()..color = const Color(0xFFE3F2FD));
    }
  }

  void _drawBedWithPlants(
      Canvas canvas,
      Offset Function(double, double, double) iso,
      double x1,
      double x2,
      double y1,
      double y2) {
    _drawPoly(
      canvas,
      [iso(x1, y1, 5), iso(x2, y1, 5), iso(x2, y2, 5), iso(x1, y2, 5)],
      const Color(0xFF3E2D20),
      const Color(0xFF5D7A68),
      strokeWidth: 1.0,
    );

    final leafPaint = Paint()
      ..color = const Color(0xFF28E070).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;

    final double mx = (x1 + x2) / 2;
    for (double y = y1 + 20; y < y2 - 10; y += 28) {
      final p = iso(mx, y, 14);
      canvas.drawCircle(p, 6.5, leafPaint);
      canvas.drawCircle(p.translate(-5.5, 3), 4.8, leafPaint);
      canvas.drawCircle(p.translate(5.5, 3), 4.8, leafPaint);
    }
  }

  void _drawPoly(
    Canvas canvas,
    List<Offset> pts,
    Color fill,
    Color stroke, {
    double strokeWidth = 1.3,
  }) {
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    if (stroke != Colors.transparent) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant InteractiveGreenhouse3DPainter oldDelegate) =>
      true;
}