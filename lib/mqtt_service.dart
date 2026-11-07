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
  bool alertWhenHigh;       // true: тревога при превышении (>, напр. MQ135, T внутри), false: тревога при падении (<, напр. Почва)
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
  bool isConnected = false;

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

  // 4 сервопривода SG90
  double roofLeftAngle = 45.0;
  double roofRightAngle = 45.0;
  double doorFrontAngle = 30.0;
  double doorBackAngle = 0.0;

  double maxRoofAngleLimit = 75.0;
  double maxDoorAngleLimit = 85.0;

  bool isWateringActive = false;
  bool isPhytoLightActive = true;
  bool isWhiteLightActive = false;

  bool isDeveloperUnlocked = false;

  // Настройки порогов и гистерезиса для каждого датчика (доступны без пароля!)
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
    _loadFromCache();
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
        alertWhenHigh: false, // тревога при похолодании ниже порога
        minLimit: -15.0,
        maxLimit: 40.0,
      ),
      'lightLux': SensorThresholdConfig(
        key: 'lightLux',
        name: 'Свет (ФР)',
        unit: ' лк',
        threshold: 300.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: false, // тревога когда темнеет ниже порога
        minLimit: 50.0,
        maxLimit: 1000.0,
      ),
      'co2': SensorThresholdConfig(
        key: 'co2',
        name: 'MQ135 (Газ/CO2)',
        unit: ' ppm',
        threshold: 1000.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: true, // тревога при превышении порога ppm
        minLimit: 400.0,
        maxLimit: 2000.0,
      ),
      'soilMoisture': SensorThresholdConfig(
        key: 'soilMoisture',
        name: 'Почва',
        unit: '%',
        threshold: 35.0,
        hysteresisPercent: 20.0,
        alertWhenHigh: false, // тревога при пересыхании ниже порога
        minLimit: 10.0,
        maxLimit: 90.0,
      ),
    };
  }

  // Расчет уровня тревоги (0 = Норма, 1 = Желтый, 2 = Темно-оранжевый, 3 = Красный)
  int getAlertStage(String key) {
    final cfg = sensorConfigs[key];
    if (cfg == null) return 0;

    double val = airTemp;
    if (key == 'outdoorTemp') val = outdoorTemp;
    if (key == 'lightLux') val = lightLux.toDouble();
    if (key == 'co2') val = co2Level.toDouble();
    if (key == 'soilMoisture') val = soilMoisture;

    // Ширина зоны предтревоги (гистерезиса) в единицах датчика
    final double hystSpan =
        (cfg.threshold.abs() * (cfg.hysteresisPercent / 100.0)).clamp(1.0, 600.0);

    if (cfg.alertWhenHigh) {
      // Тревога по ВЕРХНЕМУ пределу (например, MQ135 или жара)
      if (val >= cfg.threshold) return 3; // Красный (вышло за предел!)
      if (val >= cfg.threshold - hystSpan * 0.5) return 2; // Темно-оранжевый
      if (val >= cfg.threshold - hystSpan) return 1; // Желтый (подходит к порогу)
      return 0;
    } else {
      // Тревога по НИЖНЕМУ пределу (например, влажность почвы или холод на улице)
      if (val <= cfg.threshold) return 3; // Красный (вышло за предел!)
      if (val <= cfg.threshold + hystSpan * 0.5) return 2; // Темно-оранжевый
      if (val <= cfg.threshold + hystSpan) return 1; // Желтый (подходит к порогу)
      return 0;
    }
  }

  // Цвет для ЗНАЧЕНИЯ датчика (Белый -> Желтый -> Темно-оранжевый -> Красный)
  Color getSensorValueColor(String key) {
    switch (getAlertStage(key)) {
      case 1:
        return const Color(0xFFFFD54F); // Желтый
      case 2:
        return const Color(0xFFFF6D00); // Темно-оранжевый
      case 3:
        return const Color(0xFFFF3D00); // Красный
      default:
        return Colors.white;
    }
  }

  // Цвет для ТЕКСТА ПОДПИСИ датчика (Серый -> Желтый -> Темно-оранжевый -> Красный)
  Color getSensorLabelColor(String key) {
    switch (getAlertStage(key)) {
      case 1:
        return const Color(0xFFFFD54F); // Желтый
      case 2:
        return const Color(0xFFFF6D00); // Темно-оранжевый
      case 3:
        return const Color(0xFFFF3D00); // Красный
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

    maxRoofAngleLimit = prefs.getDouble('maxRoofAngleLimit') ?? 75.0;
    maxDoorAngleLimit = prefs.getDouble('maxDoorAngleLimit') ?? 85.0;

    roofLeftAngle =
        (prefs.getDouble('roofLeftAngle') ?? 45.0).clamp(0.0, maxRoofAngleLimit);
    roofRightAngle = (prefs.getDouble('roofRightAngle') ?? 45.0)
        .clamp(0.0, maxRoofAngleLimit);
    doorFrontAngle = (prefs.getDouble('doorFrontAngle') ?? 30.0)
        .clamp(0.0, maxDoorAngleLimit);
    doorBackAngle =
        (prefs.getDouble('doorBackAngle') ?? 0.0).clamp(0.0, maxDoorAngleLimit);

    isWateringActive = prefs.getBool('isWateringActive') ?? false;
    isPhytoLightActive = prefs.getBool('isPhytoLightActive') ?? true;
    isWhiteLightActive = prefs.getBool('isWhiteLightActive') ?? false;

    broker = prefs.getString('broker') ?? broker;
    username = prefs.getString('username') ?? username;

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

    await prefs.setString('broker', broker);
    await prefs.setString('username', username);

    final Map<String, dynamic> threshMap = {};
    sensorConfigs.forEach((k, v) => threshMap[k] = v.toJson());
    await prefs.setString('sensor_thresholds', jsonEncode(threshMap));

    await prefs.setString(
      'custom_rules',
      jsonEncode(rules.map((e) => e.toJson()).toList()),
    );
  }

  // ==================== УПРАВЛЕНИЕ 4 СЕРВОПРИВОДАМИ ====================
  void setRoofLeftAngle(double angle, {bool log = false}) {
    roofLeftAngle = angle.clamp(0.0, maxRoofAngleLimit);
    if (log) {
      _publish('greenhouse/servo/roof_left', roofLeftAngle.toInt().toString());
      addLog('Левое окно: ${roofLeftAngle.toInt()}°');
      saveToCache();
    }
    notifyListeners();
  }

  void setRoofRightAngle(double angle, {bool log = false}) {
    roofRightAngle = angle.clamp(0.0, maxRoofAngleLimit);
    if (log) {
      _publish('greenhouse/servo/roof_right', roofRightAngle.toInt().toString());
      addLog('Правое окно: ${roofRightAngle.toInt()}°');
      saveToCache();
    }
    notifyListeners();
  }

  void setDoorFrontAngle(double angle, {bool log = false}) {
    doorFrontAngle = angle.clamp(0.0, maxDoorAngleLimit);
    if (log) {
      _publish('greenhouse/servo/door_front', doorFrontAngle.toInt().toString());
      addLog('Передняя дверь: ${doorFrontAngle.toInt()}°');
      saveToCache();
    }
    notifyListeners();
  }

  void setDoorBackAngle(double angle, {bool log = false}) {
    doorBackAngle = angle.clamp(0.0, maxDoorAngleLimit);
    if (log) {
      _publish('greenhouse/servo/door_back', doorBackAngle.toInt().toString());
      addLog('Задняя дверь: ${doorBackAngle.toInt()}°');
      saveToCache();
    }
    notifyListeners();
  }

  void openAllServos() {
    roofLeftAngle = maxRoofAngleLimit;
    roofRightAngle = maxRoofAngleLimit;
    doorFrontAngle = maxDoorAngleLimit;
    doorBackAngle = maxDoorAngleLimit;
    addLog(
        'Открыты все приводы до лимита (${maxRoofAngleLimit.toInt()}° / ${maxDoorAngleLimit.toInt()}°)');
    saveToCache();
    notifyListeners();
  }

  void closeAllServos() {
    roofLeftAngle = 0;
    roofRightAngle = 0;
    doorFrontAngle = 0;
    doorBackAngle = 0;
    addLog('Все окна и двери закрыты (0°)');
    saveToCache();
    notifyListeners();
  }

  void setServoLimits(double newRoofMax, double newDoorMax) {
    maxRoofAngleLimit = newRoofMax.clamp(10.0, 90.0);
    maxDoorAngleLimit = newDoorMax.clamp(10.0, 90.0);
    roofLeftAngle = roofLeftAngle.clamp(0.0, maxRoofAngleLimit);
    roofRightAngle = roofRightAngle.clamp(0.0, maxRoofAngleLimit);
    doorFrontAngle = doorFrontAngle.clamp(0.0, maxDoorAngleLimit);
    doorBackAngle = doorBackAngle.clamp(0.0, maxDoorAngleLimit);
    addLog(
        'Новые лимиты углов: Окна=${maxRoofAngleLimit.toInt()}°, Двери=${maxDoorAngleLimit.toInt()}°');
    saveToCache();
    notifyListeners();
  }

  // ==================== УПРАВЛЕНИЕ СВЕТОМ И ПОЛИВОМ ====================
  void toggleWatering() {
    isWateringActive = !isWateringActive;
    _publish('greenhouse/pump/set', isWateringActive ? '1' : '0');
    addLog(isWateringActive
        ? 'Нижний прикорневой полив ВКЛЮЧЕН'
        : 'Полив ВЫКЛЮЧЕН');
    saveToCache();
    notifyListeners();
  }

  void togglePhytoLight() {
    isPhytoLightActive = !isPhytoLightActive;
    _publish('greenhouse/light/phyto', isPhytoLightActive ? '1' : '0');
    addLog(isPhytoLightActive ? 'Фито-лента ВКЛ' : 'Фито-лента ВЫКЛ');
    saveToCache();
    notifyListeners();
  }

  void toggleWhiteLight() {
    isWhiteLightActive = !isWhiteLightActive;
    _publish('greenhouse/light/white', isWhiteLightActive ? '1' : '0');
    addLog(isWhiteLightActive ? 'Белая LED-лента ВКЛ' : 'Белая LED-лента ВЫКЛ');
    saveToCache();
    notifyListeners();
  }

  void toggleAllLights() {
    final bool anyOn = isPhytoLightActive || isWhiteLightActive;
    isPhytoLightActive = !anyOn;
    isWhiteLightActive = !anyOn;
    _publish('greenhouse/light/phyto', isPhytoLightActive ? '1' : '0');
    _publish('greenhouse/light/white', isWhiteLightActive ? '1' : '0');
    addLog(!anyOn
        ? 'Обе светодиодные ленты (Фито + Белая) ВКЛЮЧЕНЫ'
        : 'Всё освещение теплицы ВЫКЛЮЧЕНО');
    saveToCache();
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
            roofLeftAngle = maxRoofAngleLimit;
            roofRightAngle = maxRoofAngleLimit;
            break;
          case 'closeVents':
            roofLeftAngle = 0;
            roofRightAngle = 0;
            doorFrontAngle = 0;
            doorBackAngle = 0;
            break;
          case 'waterOn':
            isWateringActive = true;
            break;
          case 'phytoOn':
            isPhytoLightActive = true;
            break;
          case 'whiteOn':
            isWhiteLightActive = true;
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

  Future<void> connect() async {
    saveToCache();
    if (kIsWeb) {
      addLog('Web-режим: подключено к брокеру $broker');
      isConnected = true;
      notifyListeners();
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
      notifyListeners();
    };

    _client!.onDisconnected = () {
      isConnected = false;
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

  void _publish(String topic, String message) {
    if (_client != null && isConnected && !kIsWeb) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _client!.publishMessage(
          topic, MqttQos.atLeastOnce, builder.payload!, retain: true);
    }
  }
}