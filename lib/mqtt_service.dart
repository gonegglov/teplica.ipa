import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorThresholdConfig {
  String key;
  String name;
  String unit;
  double threshold;
  double hysteresisPercent; // 2% .. 35%
  bool alertWhenHigh;       // true: >, false: <
  double minLimit;
  double maxLimit;

  SensorThresholdConfig({
    required this.key,
    required this.name,
    required this.unit,
    required this.threshold,
    this.hysteresisPercent = 15.0,
    required this.alertWhenHigh,
    required this.minLimit,
    required this.maxLimit,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'threshold': threshold,
        'hysteresisPercent': hysteresisPercent,
        'alertWhenHigh': alertWhenHigh,
      };
}

class AutomationRule {
  String id;
  String name;
  String subtitle;
  String sensorType;
  bool isGreater;
  double threshold;
  String actionType;
  bool isEnabled;

  AutomationRule({
    required this.id,
    required this.name,
    required this.subtitle,
    this.sensorType = 'airTemp',
    this.isGreater = true,
    this.threshold = 26.0,
    this.actionType = 'openVents',
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'sensorType': sensorType,
        'isGreater': isGreater,
        'threshold': threshold,
        'actionType': actionType,
        'isEnabled': isEnabled,
      };

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
        id: json['id'],
        name: json['name'],
        subtitle: json['subtitle'],
        sensorType: json['sensorType'] ?? 'airTemp',
        isGreater: json['isGreater'] ?? true,
        threshold: (json['threshold'] ?? 26.0).toDouble(),
        actionType: json['actionType'] ?? 'openVents',
        isEnabled: json['isEnabled'] ?? true,
      );
}

class GreenhouseMqttService extends ChangeNotifier {
  MqttServerClient? _client;
  StreamSubscription? _updatesSubscription;
  bool isConnected = false;

  static const Duration modeHoldDuration = Duration(milliseconds: 1500);

  String broker = 'your-cluster.s1.eu.hivemq.cloud';
  int port = 8883;
  String username = 'greenhouse_user';
  String password = 'your_password';

  // Телеметрия датчиков
  double airTemp = 24.5;
  double outdoorTemp = 16.4;
  double airHumidity = 58.0;
  double soilMoisture = 42.0;
  int lightLux = 650;
  int co2Level = 410;
  double voltage = 12.4;

  double timeOfDayHours = 14.5;
  String rtcTimeString = '14:30';

  // 4 сервопривода SG90 (полный диапазон 0-180°)
  double roofLeftAngle = 0.0;
  double roofRightAngle = 0.0;
  double doorFrontAngle = 0.0;
  double doorBackAngle = 0.0;

  double maxRoofAngleLimit = 180.0;
  double maxDoorAngleLimit = 180.0;

  bool isWateringActive = false;
  bool isPhytoLightActive = true;
  bool isWhiteLightActive = false;
  bool isAutoModeActive = true;

  bool isPendingWatering = false;
  bool isPendingPhyto = false;
  bool isPendingWhite = false;
  bool isPendingMode = false;

  bool isDeveloperUnlocked = false;

  late Map<String, SensorThresholdConfig> sensorConfigs;

  final List<String> eventLogs = [
    '[14:40] Контроллер ESP32-S3 запущен',
    '[14:41] Пороги и гистерезис датчиков загружены',
  ];

  List<AutomationRule> rules = [
    AutomationRule(
      id: '1',
      name: 'Авто-проветривание',
      subtitle: 'Если T внутри > 26°C → Открыть форточки',
      sensorType: 'airTemp',
      isGreater: true,
      threshold: 26.0,
      actionType: 'openVents',
      isEnabled: true,
    ),
    AutomationRule(
      id: '2',
      name: 'Прикорневой авто-полив',
      subtitle: 'Если Почва < 35% → Включить насос 5В',
      sensorType: 'soilMoisture',
      isGreater: false,
      threshold: 35.0,
      actionType: 'waterOn',
      isEnabled: false,
    ),
    AutomationRule(
      id: '3',
      name: 'Вечерняя фито-досветка',
      subtitle: 'Если Свет < 300 лк → Включить Фито-LED',
      sensorType: 'lightLux',
      isGreater: false,
      threshold: 300.0,
      actionType: 'phytoOn',
      isEnabled: true,
    ),
    AutomationRule(
      id: '4',
      name: 'Защита от холода (DS18B20)',
      subtitle: 'Если T улицы < 10°C → Закрыть все окна/двери',
      sensorType: 'outdoorTemp',
      isGreater: false,
      threshold: 10.0,
      actionType: 'closeVents',
      isEnabled: true,
    ),
  ];

  GreenhouseMqttService() {
    _initDefaultThresholds();
    _initService();
  }

  Future<void> _initService() async {
    await _loadFromCache();
    await connect();
  }

  void _initDefaultThresholds() {
    sensorConfigs = {
      'airTemp': SensorThresholdConfig(
        key: 'airTemp',
        name: 'Внутри (DHT22)',
        unit: '°C',
        threshold: 28.0,
        hysteresisPercent: 15.0,
        alertWhenHigh: true,
        minLimit: 10.0,
        maxLimit: 45.0,
      ),
      'outdoorTemp': SensorThresholdConfig(
        key: 'outdoorTemp',
        name: 'Улица (DS18B20)',
        unit: '°C',
        threshold: 10.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: false,
        minLimit: -15.0,
        maxLimit: 40.0,
      ),
      'lightLux': SensorThresholdConfig(
        key: 'lightLux',
        name: 'Свет (ФР)',
        unit: ' лк',
        threshold: 300.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: false,
        minLimit: 50.0,
        maxLimit: 1000.0,
      ),
      'co2': SensorThresholdConfig(
        key: 'co2',
        name: 'MQ135 (Газ/CO2)',
        unit: ' ppm',
        threshold: 1000.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: true,
        minLimit: 400.0,
        maxLimit: 2000.0,
      ),
      'soilMoisture': SensorThresholdConfig(
        key: 'soilMoisture',
        name: 'Почва',
        unit: '%',
        threshold: 35.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: false,
        minLimit: 10.0,
        maxLimit: 90.0,
      ),
    };
  }

  int getAlertStage(String key) {
    final cfg = sensorConfigs[key];
    if (cfg == null) return 0;

    double val = airTemp;
    if (key == 'outdoorTemp') val = outdoorTemp;
    if (key == 'lightLux') val = lightLux.toDouble();
    if (key == 'co2') val = co2Level.toDouble();
    if (key == 'soilMoisture') val = soilMoisture;

    final double hystSpan =
        (cfg.threshold.abs() * (cfg.hysteresisPercent / 100.0)).clamp(1.0, 600.0);

    if (cfg.alertWhenHigh) {
      if (val >= cfg.threshold) return 3;
      if (val >= cfg.threshold - hystSpan * 0.5) return 2;
      if (val >= cfg.threshold - hystSpan) return 1;
      return 0;
    } else {
      if (val <= cfg.threshold) return 3;
      if (val <= cfg.threshold + hystSpan * 0.5) return 2;
      if (val <= cfg.threshold + hystSpan) return 1;
      return 0;
    }
  }

  Color getSensorValueColor(String key) {
    switch (getAlertStage(key)) {
      case 1:
        return const Color(0xFFFFD54F);
      case 2:
        return const Color(0xFFFF6D00);
      case 3:
        return const Color(0xFFFF3D00);
      default:
        return Colors.white;
    }
  }

  Color getSensorLabelColor(String key) {
    switch (getAlertStage(key)) {
      case 1:
        return const Color(0xFFFFD54F);
      case 2:
        return const Color(0xFFFF6D00);
      case 3:
        return const Color(0xFFFF3D00);
      default:
        return Colors.white54;
    }
  }

  void updateSensorThreshold(
    String key, {
    required double threshold,
    required double hysteresisPercent,
    required bool alertWhenHigh,
  }) {
    final cfg = sensorConfigs[key];
    if (cfg == null) return;
    cfg.threshold = threshold.clamp(cfg.minLimit, cfg.maxLimit);
    cfg.hysteresisPercent = hysteresisPercent.clamp(2.0, 35.0);
    cfg.alertWhenHigh = alertWhenHigh;

    _publish('greenhouse/config/threshold/$key', jsonEncode(cfg.toJson()));
    addLog(
        'Порог ${cfg.name}: ${cfg.alertWhenHigh ? ">" : "<"} ${cfg.threshold.toInt()}${cfg.unit} (Гистерезис ${cfg.hysteresisPercent.toInt()}%)');
    saveToCache();
    notifyListeners();
  }

  void addLog(String msg) {
    final now = DateTime.now();
    final t =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    eventLogs.insert(0, '[$t] $msg');
    if (eventLogs.length > 50) eventLogs.removeLast();
    notifyListeners();
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    airTemp = prefs.getDouble('airTemp') ?? 24.5;
    outdoorTemp = prefs.getDouble('outdoorTemp') ?? 16.4;
    airHumidity = prefs.getDouble('airHumidity') ?? 58.0;
    soilMoisture = prefs.getDouble('soilMoisture') ?? 42.0;
    lightLux = prefs.getInt('lightLux') ?? 650;
    co2Level = prefs.getInt('co2Level') ?? 410;
    voltage = prefs.getDouble('voltage') ?? 12.4;
    timeOfDayHours = prefs.getDouble('timeOfDayHours') ?? 14.5;

    maxRoofAngleLimit = prefs.getDouble('maxRoofAngleLimit') ?? 180.0;
    maxDoorAngleLimit = prefs.getDouble('maxDoorAngleLimit') ?? 180.0;

    roofLeftAngle =
        (prefs.getDouble('roofLeftAngle') ?? 0.0).clamp(0.0, maxRoofAngleLimit);
    roofRightAngle = (prefs.getDouble('roofRightAngle') ?? 0.0)
        .clamp(0.0, maxRoofAngleLimit);
    doorFrontAngle = (prefs.getDouble('doorFrontAngle') ?? 0.0)
        .clamp(0.0, maxDoorAngleLimit);
    doorBackAngle =
        (prefs.getDouble('doorBackAngle') ?? 0.0).clamp(0.0, maxDoorAngleLimit);

    isWateringActive = prefs.getBool('isWateringActive') ?? false;
    isPhytoLightActive = prefs.getBool('isPhytoLightActive') ?? true;
    isWhiteLightActive = prefs.getBool('isWhiteLightActive') ?? false;
    isAutoModeActive = prefs.getBool('isAutoModeActive') ?? true;

    broker = prefs.getString('broker') ?? broker;
    username = prefs.getString('username') ?? username;
    password = prefs.getString('password') ?? password;

    final savedThresholds = prefs.getString('sensor_thresholds');
    if (savedThresholds != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(savedThresholds);
        decoded.forEach((k, v) {
          if (sensorConfigs.containsKey(k)) {
            sensorConfigs[k]!.threshold =
                (v['threshold'] ?? sensorConfigs[k]!.threshold).toDouble();
            sensorConfigs[k]!.hysteresisPercent =
                (v['hysteresisPercent'] ?? 15.0).toDouble();
            sensorConfigs[k]!.alertWhenHigh =
                v['alertWhenHigh'] ?? sensorConfigs[k]!.alertWhenHigh;
          }
        });
      } catch (_) {}
    }

    final savedRules = prefs.getString('custom_rules');
    if (savedRules != null) {
      try {
        final List decoded = jsonDecode(savedRules);
        rules = decoded.map((e) => AutomationRule.fromJson(e)).toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('airTemp', airTemp);
    await prefs.setDouble('outdoorTemp', outdoorTemp);
    await prefs.setDouble('airHumidity', airHumidity);
    await prefs.setDouble('soilMoisture', soilMoisture);
    await prefs.setInt('lightLux', lightLux);
    await prefs.setInt('co2Level', co2Level);
    await prefs.setDouble('voltage', voltage);
    await prefs.setDouble('timeOfDayHours', timeOfDayHours);

    await prefs.setDouble('maxRoofAngleLimit', maxRoofAngleLimit);
    await prefs.setDouble('maxDoorAngleLimit', maxDoorAngleLimit);

    await prefs.setDouble('roofLeftAngle', roofLeftAngle);
    await prefs.setDouble('roofRightAngle', roofRightAngle);
    await prefs.setDouble('doorFrontAngle', doorFrontAngle);
    await prefs.setDouble('doorBackAngle', doorBackAngle);

    await prefs.setBool('isWateringActive', isWateringActive);
    await prefs.setBool('isPhytoLightActive', isPhytoLightActive);
    await prefs.setBool('isWhiteLightActive', isWhiteLightActive);
    await prefs.setBool('isAutoModeActive', isAutoModeActive);

    await prefs.setString('broker', broker);
    await prefs.setString('username', username);
    await prefs.setString('password', password);

    final Map<String, dynamic> threshMap = {};
    sensorConfigs.forEach((k, v) => threshMap[k] = v.toJson());
    await prefs.setString('sensor_thresholds', jsonEncode(threshMap));

    await prefs.setString(
      'custom_rules',
      jsonEncode(rules.map((e) => e.toJson()).toList()),
    );
  }

  // ==================== УПРАВЛЕНИЕ 4 СЕРВОПРИВОДАМИ (0-180°) ====================
  void setRoofLeftAngle(double angle, {bool log = false}) {
    final target = angle.clamp(0.0, maxRoofAngleLimit);
    if (log) {
      _publish('greenhouse/servo/roof_left/set', target.toInt().toString());
      addLog('Запрос: Левое окно → ${target.toInt()}°');
      if (!isConnected || kIsWeb) {
        roofLeftAngle = target;
        saveToCache();
      }
    } else {
      roofLeftAngle = target;
    }
    notifyListeners();
  }

  void setRoofRightAngle(double angle, {bool log = false}) {
    final target = angle.clamp(0.0, maxRoofAngleLimit);
    if (log) {
      _publish('greenhouse/servo/roof_right/set', target.toInt().toString());
      addLog('Запрос: Правое окно → ${target.toInt()}°');
      if (!isConnected || kIsWeb) {
        roofRightAngle = target;
        saveToCache();
      }
    } else {
      roofRightAngle = target;
    }
    notifyListeners();
  }

  void setDoorFrontAngle(double angle, {bool log = false}) {
    final target = angle.clamp(0.0, maxDoorAngleLimit);
    if (log) {
      _publish('greenhouse/servo/door_front/set', target.toInt().toString());
      addLog('Запрос: Передняя дверь → ${target.toInt()}°');
      if (!isConnected || kIsWeb) {
        doorFrontAngle = target;
        saveToCache();
      }
    } else {
      doorFrontAngle = target;
    }
    notifyListeners();
  }

  void setDoorBackAngle(double angle, {bool log = false}) {
    final target = angle.clamp(0.0, maxDoorAngleLimit);
    if (log) {
      _publish('greenhouse/servo/door_back/set', target.toInt().toString());
      addLog('Запрос: Задняя дверь → ${target.toInt()}°');
      if (!isConnected || kIsWeb) {
        doorBackAngle = target;
        saveToCache();
      }
    } else {
      doorBackAngle = target;
    }
    notifyListeners();
  }

  void openAllServos() {
    final rMax = maxRoofAngleLimit.toInt().toString();
    final dMax = maxDoorAngleLimit.toInt().toString();
    _publish('greenhouse/servo/roof_left/set', rMax);
    _publish('greenhouse/servo/roof_right/set', rMax);
    _publish('greenhouse/servo/door_front/set', dMax);
    _publish('greenhouse/servo/door_back/set', dMax);
    addLog('Запрос: Открыть все приводы ($rMax° / $dMax°)');

    if (!isConnected || kIsWeb) {
      roofLeftAngle = maxRoofAngleLimit;
      roofRightAngle = maxRoofAngleLimit;
      doorFrontAngle = maxDoorAngleLimit;
      doorBackAngle = maxDoorAngleLimit;
      saveToCache();
    }
    notifyListeners();
  }

  void closeAllServos() {
    _publish('greenhouse/servo/roof_left/set', '0');
    _publish('greenhouse/servo/roof_right/set', '0');
    _publish('greenhouse/servo/door_front/set', '0');
    _publish('greenhouse/servo/door_back/set', '0');
    addLog('Запрос: Закрыть все окна и двери (0°)');

    if (!isConnected || kIsWeb) {
      roofLeftAngle = 0;
      roofRightAngle = 0;
      doorFrontAngle = 0;
      doorBackAngle = 0;
      saveToCache();
    }
    notifyListeners();
  }

  void setServoLimits(double newRoofMax, double newDoorMax) {
    maxRoofAngleLimit = newRoofMax.clamp(10.0, 180.0);
    maxDoorAngleLimit = newDoorMax.clamp(10.0, 180.0);
    roofLeftAngle = roofLeftAngle.clamp(0.0, maxRoofAngleLimit);
    roofRightAngle = roofRightAngle.clamp(0.0, maxRoofAngleLimit);
    doorFrontAngle = doorFrontAngle.clamp(0.0, maxDoorAngleLimit);
    doorBackAngle = doorBackAngle.clamp(0.0, maxDoorAngleLimit);
    addLog(
        'Новые лимиты углов: Окна=${maxRoofAngleLimit.toInt()}°, Двери=${maxDoorAngleLimit.toInt()}°');
    saveToCache();
    notifyListeners();
  }

  // ==================== УПРАВЛЕНИЕ СВЕТОМ, ПОЛИВОМ И РЕЖИМОМ ====================
  void toggleWatering() {
    final targetState = !isWateringActive;
    _publish('greenhouse/pump/set', targetState ? '1' : '0', retain: false);

    if (isConnected && !kIsWeb) {
      isPendingWatering = true;
      addLog('Ожидание отклика насоса от ESP32...');
    } else {
      isWateringActive = targetState;
      addLog(isWateringActive ? 'Полив ВКЛЮЧЕН (демо)' : 'Полив ВЫКЛЮЧЕН (демо)');
      saveToCache();
    }
    notifyListeners();
  }

  void togglePhytoLight() {
    final targetState = !isPhytoLightActive;
    _publish('greenhouse/light/phyto/set', targetState ? '1' : '0', retain: false);

    if (isConnected && !kIsWeb) {
      isPendingPhyto = true;
      addLog('Ожидание отклика Фито-ленты от ESP32...');
    } else {
      isPhytoLightActive = targetState;
      addLog(isPhytoLightActive ? 'Фито-лента ВКЛ (демо)' : 'Фито-лента ВЫКЛ (демо)');
      saveToCache();
    }
    notifyListeners();
  }

  void toggleWhiteLight() {
    final targetState = !isWhiteLightActive;
    _publish('greenhouse/light/white/set', targetState ? '1' : '0', retain: false);

    if (isConnected && !kIsWeb) {
      isPendingWhite = true;
      addLog('Ожидание отклика Белой ленты от ESP32...');
    } else {
      isWhiteLightActive = targetState;
      addLog(isWhiteLightActive ? 'Белая LED-лента ВКЛ (демо)' : 'Белая LED-лента ВЫКЛ (демо)');
      saveToCache();
    }
    notifyListeners();
  }

  void toggleAllLights() {
    final bool anyOn = isPhytoLightActive || isWhiteLightActive;
    final targetState = !anyOn;
    _publish('greenhouse/light/phyto/set', targetState ? '1' : '0', retain: false);
    _publish('greenhouse/light/white/set', targetState ? '1' : '0', retain: false);

    if (isConnected && !kIsWeb) {
      isPendingPhyto = true;
      isPendingWhite = true;
      addLog('Ожидание переключения освещения...');
    } else {
      isPhytoLightActive = targetState;
      isWhiteLightActive = targetState;
      saveToCache();
    }
    notifyListeners();
  }

  void toggleControlMode() {
    final targetMode = !isAutoModeActive;
    _publish('greenhouse/mode/set', targetMode ? 'auto' : 'manual', retain: false);

    if (isConnected && !kIsWeb) {
      isPendingMode = true;
      addLog('Запрос смены режима → ${targetMode ? "АВТО" : "РУЧНОЙ"} (ждём ESP32)...');
    } else {
      isAutoModeActive = targetMode;
      addLog('Режим изменен: ${isAutoModeActive ? "АВТО" : "РУЧНОЙ"} (демо)');
      saveToCache();
    }
    notifyListeners();
  }

  // ==================== АВТОСЦЕНАРИИ ====================
  void toggleRule(String id, bool val) {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx].isEnabled = val;
      addLog('Сценарий "${rules[idx].name}": ${val ? "Активен" : "Отключен"}');
      evaluateAutomationRules();
      saveToCache();
      notifyListeners();
    }
  }

  void addCustomRule({
    required String name,
    required String sensorType,
    required bool isGreater,
    required double threshold,
    required String actionType,
  }) {
    final sensorNames = {
      'airTemp': 'T внутри (DHT22)',
      'outdoorTemp': 'T улицы (DS18B20)',
      'soilMoisture': 'Влажность почвы',
      'lightLux': 'Освещенность',
      'co2': 'MQ135 (CO2)',
    };
    final units = {
      'airTemp': '°C',
      'outdoorTemp': '°C',
      'soilMoisture': '%',
      'lightLux': ' лк',
      'co2': ' ppm',
    };
    final actionNames = {
      'openVents': 'Открыть окна/двери',
      'closeVents': 'Закрыть окна/двери',
      'waterOn': 'Включить полив',
      'phytoOn': 'Включить Фито-LED',
      'whiteOn': 'Включить Белый LED',
    };

    final sign = isGreater ? '>' : '<';
    final sub =
        'Если ${sensorNames[sensorType]} $sign ${threshold.toInt()}${units[sensorType]} → ${actionNames[actionType]}';

    rules.add(
      AutomationRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        subtitle: sub,
        sensorType: sensorType,
        isGreater: isGreater,
        threshold: threshold,
        actionType: actionType,
        isEnabled: true,
      ),
    );
    addLog('Создан сценарий: "$name"');
    evaluateAutomationRules();
    saveToCache();
    notifyListeners();
  }

  void deleteRule(String id) {
    rules.removeWhere((r) => r.id == id);
    addLog('Сценарий удален');
    saveToCache();
    notifyListeners();
  }

  void evaluateAutomationRules() {
    for (final rule in rules) {
      if (!rule.isEnabled) continue;
      double currentVal = airTemp;
      if (rule.sensorType == 'outdoorTemp') currentVal = outdoorTemp;
      if (rule.sensorType == 'soilMoisture') currentVal = soilMoisture;
      if (rule.sensorType == 'lightLux') currentVal = lightLux.toDouble();
      if (rule.sensorType == 'co2') currentVal = co2Level.toDouble();

      final triggered = rule.isGreater
          ? (currentVal > rule.threshold)
          : (currentVal < rule.threshold);

      if (triggered) {
        switch (rule.actionType) {
          case 'openVents':
            openAllServos();
            break;
          case 'closeVents':
            closeAllServos();
            break;
          case 'waterOn':
            if (!isWateringActive) toggleWatering();
            break;
          case 'phytoOn':
            if (!isPhytoLightActive) togglePhytoLight();
            break;
          case 'whiteOn':
            if (!isWhiteLightActive) toggleWhiteLight();
            break;
        }
      }
    }
    notifyListeners();
  }

  void updateSimulatedSensor({
    double? newAirTemp,
    double? newOutdoorTemp,
    double? newSoil,
    int? newLux,
    int? newCo2,
    double? newVoltage,
  }) {
    if (newAirTemp != null) airTemp = newAirTemp;
    if (newOutdoorTemp != null) outdoorTemp = newOutdoorTemp;
    if (newSoil != null) soilMoisture = newSoil;
    if (newLux != null) lightLux = newLux;
    if (newCo2 != null) co2Level = newCo2;
    if (newVoltage != null) voltage = newVoltage;
    evaluateAutomationRules();
    notifyListeners();
  }

  void setTimeOfDay(double hours) {
    timeOfDayHours = hours.clamp(0.0, 24.0);
    final int h = timeOfDayHours.floor();
    final int m = ((timeOfDayHours - h) * 60).round();
    rtcTimeString = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

    if (timeOfDayHours >= 6.0 && timeOfDayHours <= 20.0) {
      final norm = (timeOfDayHours - 6.0) / 14.0;
      final sunCurve = (1.0 - ((norm - 0.5).abs() * 2.0)).clamp(0.0, 1.0);
      lightLux = (80 + sunCurve * 850).toInt();
    } else {
      lightLux = 25;
    }
    evaluateAutomationRules();
    notifyListeners();
  }

  bool unlockDeveloperMode(String pin) {
    if (pin.trim() == '0000') {
      isDeveloperUnlocked = true;
      addLog('Открыт Режим Разработчика (PIN: 0000)');
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockDeveloperMode() {
    isDeveloperUnlocked = false;
    notifyListeners();
  }

  // ==================== MQTT ПОДКЛЮЧЕНИЕ ====================
  Future<void> connect() async {
    saveToCache();
    if (kIsWeb) {
      addLog('Web-режим: эмуляция брокера $broker');
      isConnected = true;
      notifyListeners();
      return;
    }

    if (_client != null && isConnected) {
      requestFullStatus();
      return;
    }

    final clientId = 'gh_ios_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(broker, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 30;
    _client!.secure = true;
    _client!.autoReconnect = true;

    _client!.onConnected = () {
      isConnected = true;
      addLog('MQTT подключен к HiveMQ');
      _subscribeToTopics();
      requestFullStatus();
      notifyListeners();
    };

    _client!.onAutoReconnected = () {
      isConnected = true;
      _subscribeToTopics();
      requestFullStatus();
      notifyListeners();
    };

    _client!.onDisconnected = () {
      isConnected = false;
      isPendingWatering = false;
      isPendingPhyto = false;
      isPendingWhite = false;
      isPendingMode = false;
      addLog('MQTT отключен');
      notifyListeners();
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
    } catch (e) {
      addLog('Ошибка MQTT: $e');
      _client!.disconnect();
    }
  }

  void requestFullStatus() {
    _publish('greenhouse/status/get', '1', retain: false);
  }

  void _subscribeToTopics() {
    if (_client == null) return;

    _client!.subscribe('greenhouse/telemetry/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/state/#', MqttQos.atLeastOnce);

    _updatesSubscription?.cancel();
    _updatesSubscription = _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      for (final msg in c) {
        final recMsg = msg.payload as MqttPublishMessage?;
        if (recMsg == null) continue;

        final payload = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message).trim();
        final topic = msg.topic;

        _handleIncomingMessage(topic, payload);
      }
    });
  }

  void _handleIncomingMessage(String topic, String payload) {
    try {
      if (topic == 'greenhouse/telemetry/all' || payload.startsWith('{')) {
        final Map<String, dynamic> data = jsonDecode(payload);
        if (data.containsKey('airTemp')) airTemp = (data['airTemp'] as num).toDouble();
        if (data.containsKey('outdoorTemp')) outdoorTemp = (data['outdoorTemp'] as num).toDouble();
        if (data.containsKey('airHumidity')) airHumidity = (data['airHumidity'] as num).toDouble();
        if (data.containsKey('soilMoisture')) soilMoisture = (data['soilMoisture'] as num).toDouble();
        if (data.containsKey('lightLux')) lightLux = (data['lightLux'] as num).toInt();
        if (data.containsKey('co2')) co2Level = (data['co2'] as num).toInt();
        if (data.containsKey('voltage')) voltage = (data['voltage'] as num).toDouble();
        if (data.containsKey('time')) _parseIncomingTime(data['time'].toString());

        if (data.containsKey('pump')) {
          isWateringActive = data['pump'] == 1 || data['pump'] == true;
          isPendingWatering = false;
        }
        if (data.containsKey('phyto')) {
          isPhytoLightActive = data['phyto'] == 1 || data['phyto'] == true;
          isPendingPhyto = false;
        }
        if (data.containsKey('white')) {
          isWhiteLightActive = data['white'] == 1 || data['white'] == true;
          isPendingWhite = false;
        }
        if (data.containsKey('mode')) {
          isAutoModeActive = data['mode'] == 'auto' || data['mode'] == 1;
          isPendingMode = false;
        }
        saveToCache();
        notifyListeners();
        return;
      }

      if (topic.endsWith('/time')) {
        _parseIncomingTime(payload);
        notifyListeners();
        return;
      }

      if (topic == 'greenhouse/state/pump') {
        isWateringActive = (payload == '1' || payload.toLowerCase() == 'true' || payload.toLowerCase() == 'on');
        isPendingWatering = false;
        addLog('Контроллер подтвердил: Насос ${isWateringActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/phyto') {
        isPhytoLightActive = (payload == '1' || payload.toLowerCase() == 'true' || payload.toLowerCase() == 'on');
        isPendingPhyto = false;
        addLog('Контроллер подтвердил: Фито-свет ${isPhytoLightActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/white') {
        isWhiteLightActive = (payload == '1' || payload.toLowerCase() == 'true' || payload.toLowerCase() == 'on');
        isPendingWhite = false;
        addLog('Контроллер подтвердил: Белый свет ${isWhiteLightActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/mode') {
        isAutoModeActive = (payload.toLowerCase() == 'auto' || payload == '1');
        isPendingMode = false;
        addLog('Контроллер переключил режим: ${isAutoModeActive ? "АВТО" : "РУЧНОЙ"}');
        saveToCache();
        notifyListeners();
        return;
      }

      final val = double.tryParse(payload);
      if (val == null) return;

      if (topic.endsWith('air_temp')) {
        airTemp = val;
      } else if (topic.endsWith('outdoor_temp')) {
        outdoorTemp = val;
      } else if (topic.endsWith('air_humidity') || topic.endsWith('humidity')) {
        airHumidity = val;
      } else if (topic.endsWith('soil_moisture') || topic.endsWith('soil')) {
        soilMoisture = val;
      } else if (topic.endsWith('light_lux') || topic.endsWith('lux')) {
        lightLux = val.toInt();
      } else if (topic.endsWith('co2')) {
        co2Level = val.toInt();
      } else if (topic.endsWith('voltage') || topic.endsWith('vcc')) {
        voltage = val;
      } else if (topic.endsWith('servo/roof_left')) {
        roofLeftAngle = val.clamp(0.0, maxRoofAngleLimit);
      } else if (topic.endsWith('servo/roof_right')) {
        roofRightAngle = val.clamp(0.0, maxRoofAngleLimit);
      } else if (topic.endsWith('servo/door_front')) {
        doorFrontAngle = val.clamp(0.0, maxDoorAngleLimit);
      } else if (topic.endsWith('servo/door_back')) {
        doorBackAngle = val.clamp(0.0, maxDoorAngleLimit);
      }

      saveToCache();
      notifyListeners();
    } catch (e) {
      addLog('Ошибка разбора пакета ($topic): $e');
    }
  }

  void _parseIncomingTime(String timeStr) {
    rtcTimeString = timeStr;
    if (timeStr.contains(':')) {
      final parts = timeStr.split(':');
      final h = double.tryParse(parts[0]) ?? 12.0;
      final m = double.tryParse(parts[1]) ?? 0.0;
      timeOfDayHours = (h + (m / 60.0)).clamp(0.0, 24.0);
    } else {
      final dec = double.tryParse(timeStr);
      if (dec != null) timeOfDayHours = dec.clamp(0.0, 24.0);
    }
  }

  void _publish(String topic, String message, {bool retain = true}) {
    if (_client != null && isConnected && !kIsWeb) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _client!.publishMessage(
          topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
    }
  }
}