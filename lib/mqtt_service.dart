import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorThresholdConfig {
  String key;
  String name;
  String unit;
  double threshold;
  double hysteresisPercent; // 2% .. 35%
  bool alertWhenHigh;
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

class RuleAction {
  String target; // 'roofAngle', 'doorAngle', 'allServos', 'pump', 'phytoLight', 'whiteLight'
  double value;  // Для сервоприводов: 0..180, для реле/света: 1 (ВКЛ) или 0 (ВЫКЛ)

  RuleAction({
    required this.target,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'target': target,
        'value': value,
      };

  factory RuleAction.fromJson(Map<String, dynamic> json) => RuleAction(
        target: json['target'] ?? 'allServos',
        value: (json['value'] ?? 0).toDouble(),
      );

  String describe() {
    switch (target) {
      case 'roofAngle':
        return 'Окна крыши → ${value.toInt()}°';
      case 'doorAngle':
        return 'Двери → ${value.toInt()}°';
      case 'allServos':
        return 'Все приводы → ${value.toInt()}°';
      case 'pump':
        return value >= 1 ? 'Полив ВКЛ' : 'Полив ВЫКЛ';
      case 'phytoLight':
        return value >= 1 ? 'Фито-LED ВКЛ' : 'Фито-LED ВЫКЛ';
      case 'whiteLight':
        return value >= 1 ? 'Белый LED ВКЛ' : 'Белый LED ВЫКЛ';
      default:
        return '$target = ${value.toInt()}';
    }
  }
}

class AutomationRule {
  String id;
  String name;
  String sensorType;
  String operatorType; // '>', '<', '>=', '<='
  double threshold;

  bool hasSecondCondition;
  String logicOperator; // 'AND', 'OR'
  String secondSensorType;
  String secondOperatorType;
  double secondThreshold;

  List<RuleAction> actions;
  bool isEnabled;
  bool wasTriggered;

  AutomationRule({
    required this.id,
    required this.name,
    this.sensorType = 'airTemp',
    this.operatorType = '>',
    this.threshold = 26.0,
    this.hasSecondCondition = false,
    this.logicOperator = 'AND',
    this.secondSensorType = 'lightLux',
    this.secondOperatorType = '>',
    this.secondThreshold = 300.0,
    required this.actions,
    this.isEnabled = true,
    this.wasTriggered = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sensorType': sensorType,
        'operatorType': operatorType,
        'threshold': threshold,
        'hasSecondCondition': hasSecondCondition,
        'logicOperator': logicOperator,
        'secondSensorType': secondSensorType,
        'secondOperatorType': secondOperatorType,
        'secondThreshold': secondThreshold,
        'actions': actions.map((a) => a.toJson()).toList(),
        'isEnabled': isEnabled,
      };

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    List<RuleAction> parsedActions = [];
    if (json['actions'] != null && json['actions'] is List) {
      parsedActions = (json['actions'] as List)
          .map((e) => RuleAction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else if (json['actionType'] != null) {
      // Совместимость со старым форматом правил
      switch (json['actionType']) {
        case 'openVents':
          parsedActions.add(RuleAction(target: 'allServos', value: 180));
          break;
        case 'closeVents':
          parsedActions.add(RuleAction(target: 'allServos', value: 0));
          break;
        case 'waterOn':
          parsedActions.add(RuleAction(target: 'pump', value: 1));
          break;
        case 'phytoOn':
          parsedActions.add(RuleAction(target: 'phytoLight', value: 1));
          break;
        case 'whiteOn':
          parsedActions.add(RuleAction(target: 'whiteLight', value: 1));
          break;
      }
    }
    if (parsedActions.isEmpty) {
      parsedActions.add(RuleAction(target: 'roofAngle', value: 90));
    }

    String op1 = json['operatorType'] ?? ((json['isGreater'] ?? true) ? '>' : '<');

    return AutomationRule(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Сценарий',
      sensorType: json['sensorType'] ?? 'airTemp',
      operatorType: op1,
      threshold: (json['threshold'] ?? 26.0).toDouble(),
      hasSecondCondition: json['hasSecondCondition'] ?? false,
      logicOperator: json['logicOperator'] ?? 'AND',
      secondSensorType: json['secondSensorType'] ?? 'lightLux',
      secondOperatorType: json['secondOperatorType'] ?? '>',
      secondThreshold: (json['secondThreshold'] ?? 300.0).toDouble(),
      actions: parsedActions,
      isEnabled: json['isEnabled'] ?? true,
    );
  }
}

class GreenhouseMqttService extends ChangeNotifier {
  MqttServerClient? _client;
  StreamSubscription? _updatesSubscription;
  Timer? _watchdogTimer;

  // Статус подключения телефона и контроллера
  bool isConnected = false; // Телефон -> MQTT брокер
  bool isControllerOnline = false; // ESP32-S3 -> MQTT брокер
  DateTime? lastControllerPacketTime;
  String? lastConnectionError;

  // Время удержания кнопки смены режима (1.5 секунды)
  static const Duration modeHoldDuration = Duration(milliseconds: 1500);

  // Параметры подключения к MQTT
  String broker = 'your-cluster.s1.eu.hivemq.cloud';
  int port = 8883;
  String username = 'greenhouse_user';
  String password = 'your_password';

  // Телеметрия датчиков и RTC
  double airTemp = 24.5;
  double outdoorTemp = 16.4;
  double airHumidity = 58.0;
  double soilMoisture = 42.0;
  int lightLux = 650;
  int co2Level = 410;
  double voltage = 12.4;

  double timeOfDayHours = 14.5;
  String rtcTimeString = '14:30';

  // 4 сервопривода SG90 (0..180°)
  double roofLeftAngle = 0.0;
  double roofRightAngle = 0.0;
  double doorFrontAngle = 0.0;
  double doorBackAngle = 0.0;

  double maxRoofAngleLimit = 180.0;
  double maxDoorAngleLimit = 180.0;

  // Подтверждённые состояния исполнительных механизмов
  bool isWateringActive = false;
  bool isPhytoLightActive = false;
  bool isWhiteLightActive = false;
  bool isAutoModeActive = true;

  // Флаги ожидания подтверждения от контроллера
  bool isPendingWatering = false;
  bool isPendingPhyto = false;
  bool isPendingWhite = false;
  bool isPendingMode = false;

  bool isDeveloperUnlocked = false;

  late Map<String, SensorThresholdConfig> sensorConfigs;

  final List<String> eventLogs = [
    '[Старт] Система инициализирована',
  ];

  List<AutomationRule> rules = [
    AutomationRule(
      id: '1',
      name: 'Дневное проветривание',
      sensorType: 'airTemp',
      operatorType: '>',
      threshold: 26.0,
      hasSecondCondition: true,
      logicOperator: 'AND',
      secondSensorType: 'outdoorTemp',
      secondOperatorType: '>',
      secondThreshold: 14.0,
      actions: [
        RuleAction(target: 'roofAngle', value: 120),
      ],
      isEnabled: true,
    ),
    AutomationRule(
      id: '2',
      name: 'Прикорневой авто-полив',
      sensorType: 'soilMoisture',
      operatorType: '<',
      threshold: 35.0,
      actions: [
        RuleAction(target: 'pump', value: 1),
      ],
      isEnabled: false,
    ),
    AutomationRule(
      id: '3',
      name: 'Вечерняя фито-досветка',
      sensorType: 'lightLux',
      operatorType: '<',
      threshold: 300.0,
      hasSecondCondition: true,
      logicOperator: 'AND',
      secondSensorType: 'timeHour',
      secondOperatorType: '<',
      secondThreshold: 22.0,
      actions: [
        RuleAction(target: 'phytoLight', value: 1),
      ],
      isEnabled: true,
    ),
    AutomationRule(
      id: '4',
      name: 'Защита от заморозков',
      sensorType: 'outdoorTemp',
      operatorType: '<',
      threshold: 10.0,
      actions: [
        RuleAction(target: 'allServos', value: 0),
      ],
      isEnabled: true,
    ),
  ];

  GreenhouseMqttService() {
    _initDefaultThresholds();
    _initService();
  }

  Future<void> _initService() async {
    await _loadFromCache();
    _startControllerWatchdog();
    await connect();
  }

  void _startControllerWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isConnected) {
        if (isControllerOnline) {
          isControllerOnline = false;
          notifyListeners();
        }
        return;
      }
      if (lastControllerPacketTime != null) {
        final diff = DateTime.now().difference(lastControllerPacketTime!);
        if (diff.inSeconds > 45 && isControllerOnline) {
          isControllerOnline = false;
          addLog('Потеряна связь с контроллером ESP32 (таймаут)');
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _updatesSubscription?.cancel();
    _client?.disconnect();
    super.dispose();
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
        'Порог ${cfg.name}: ${cfg.alertWhenHigh ? ">" : "<"} ${cfg.threshold.toInt()}${cfg.unit}');
    saveToCache();
    notifyListeners();
  }

  void addLog(String msg) {
    final now = DateTime.now();
    final t =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    eventLogs.insert(0, '[$t] $msg');
    if (eventLogs.length > 60) eventLogs.removeLast();
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
    isPhytoLightActive = prefs.getBool('isPhytoLightActive') ?? false;
    isWhiteLightActive = prefs.getBool('isWhiteLightActive') ?? false;
    isAutoModeActive = prefs.getBool('isAutoModeActive') ?? true;

    broker = prefs.getString('broker') ?? broker;
    port = prefs.getInt('port') ?? port;
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
    await prefs.setInt('port', port);
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

  // ==================== ОБНОВЛЕНИЕ НАСТРОЕК БРОКЕРА MQTT ====================
  Future<void> updateMqttCredentials({
    required String newBroker,
    required int newPort,
    required String newUsername,
    required String newPassword,
  }) async {
    broker = newBroker.trim();
    port = newPort;
    username = newUsername.trim();
    password = newPassword;

    await saveToCache();
    addLog('Параметры MQTT обновлены ($broker:$port)');

    // Принудительно разрываем старое соединение и подключаемся заново
    _updatesSubscription?.cancel();
    if (_client != null) {
      try {
        _client!.autoReconnect = false;
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }

    isConnected = false;
    isControllerOnline = false;
    lastConnectionError = null;
    notifyListeners();

    await connect(forceReconnect: true);
  }

  // ==================== УПРАВЛЕНИЕ 4 СЕРВОПРИВОДАМИ (0-180°) ====================
  void setRoofLeftAngle(double angle, {bool log = false}) {
    final target = angle.clamp(0.0, maxRoofAngleLimit);
    if (log) {
      _publish('greenhouse/servo/roof_left/set', target.toInt().toString());
      addLog('Левое окно → ${target.toInt()}°');
      if (!isConnected || !isControllerOnline || kIsWeb) {
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
      addLog('Правое окно → ${target.toInt()}°');
      if (!isConnected || !isControllerOnline || kIsWeb) {
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
      addLog('Передняя дверь → ${target.toInt()}°');
      if (!isConnected || !isControllerOnline || kIsWeb) {
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
      addLog('Задняя дверь → ${target.toInt()}°');
      if (!isConnected || !isControllerOnline || kIsWeb) {
        doorBackAngle = target;
        saveToCache();
      }
    } else {
      doorBackAngle = target;
    }
    notifyListeners();
  }

  void setRoofBothAngle(double angle) {
    final target = angle.clamp(0.0, maxRoofAngleLimit);
    _publish('greenhouse/servo/roof_left/set', target.toInt().toString());
    _publish('greenhouse/servo/roof_right/set', target.toInt().toString());
    if (!isConnected || !isControllerOnline || kIsWeb) {
      roofLeftAngle = target;
      roofRightAngle = target;
      saveToCache();
    }
    notifyListeners();
  }

  void setDoorBothAngle(double angle) {
    final target = angle.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/door_front/set', target.toInt().toString());
    _publish('greenhouse/servo/door_back/set', target.toInt().toString());
    if (!isConnected || !isControllerOnline || kIsWeb) {
      doorFrontAngle = target;
      doorBackAngle = target;
      saveToCache();
    }
    notifyListeners();
  }

  void setAllServosAngle(double angle) {
    final rTarget = angle.clamp(0.0, maxRoofAngleLimit);
    final dTarget = angle.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/roof_left/set', rTarget.toInt().toString());
    _publish('greenhouse/servo/roof_right/set', rTarget.toInt().toString());
    _publish('greenhouse/servo/door_front/set', dTarget.toInt().toString());
    _publish('greenhouse/servo/door_back/set', dTarget.toInt().toString());

    if (!isConnected || !isControllerOnline || kIsWeb) {
      roofLeftAngle = rTarget;
      roofRightAngle = rTarget;
      doorFrontAngle = dTarget;
      doorBackAngle = dTarget;
      saveToCache();
    }
    notifyListeners();
  }

  void openAllServos() {
    setAllServosAngle(180.0);
    addLog('Открыть все приводы (${maxRoofAngleLimit.toInt()}° / ${maxDoorAngleLimit.toInt()}°)');
  }

  void closeAllServos() {
    setAllServosAngle(0.0);
    addLog('Закрыть все окна и двери (0°)');
  }

  void setServoLimits(double newRoofMax, double newDoorMax) {
    maxRoofAngleLimit = newRoofMax.clamp(10.0, 180.0);
    maxDoorAngleLimit = newDoorMax.clamp(10.0, 180.0);
    roofLeftAngle = roofLeftAngle.clamp(0.0, maxRoofAngleLimit);
    roofRightAngle = roofRightAngle.clamp(0.0, maxRoofAngleLimit);
    doorFrontAngle = doorFrontAngle.clamp(0.0, maxDoorAngleLimit);
    doorBackAngle = doorBackAngle.clamp(0.0, maxDoorAngleLimit);
    addLog(
        'Новые лимиты: Окна=${maxRoofAngleLimit.toInt()}°, Двери=${maxDoorAngleLimit.toInt()}°');
    saveToCache();
    notifyListeners();
  }

  // ==================== УПРАВЛЕНИЕ СВЕТОМ, ПОЛИВОМ И РЕЖИМОМ ====================
  void setWateringState(bool targetState) {
    _publish('greenhouse/pump/set', targetState ? '1' : '0', retain: false);
    if (isConnected && isControllerOnline && !kIsWeb) {
      isPendingWatering = true;
      addLog('Запрос насоса (${targetState ? "ВКЛ" : "ВЫКЛ"}) → ждём ESP32...');
    } else {
      isWateringActive = targetState;
      addLog(isWateringActive ? 'Полив ВКЛ (локально)' : 'Полив ВЫКЛ (локально)');
      saveToCache();
    }
    notifyListeners();
  }

  void toggleWatering() => setWateringState(!isWateringActive);

  void setPhytoLightState(bool targetState) {
    _publish('greenhouse/light/phyto/set', targetState ? '1' : '0', retain: false);
    if (isConnected && isControllerOnline && !kIsWeb) {
      isPendingPhyto = true;
      addLog('Запрос Фито-LED (${targetState ? "ВКЛ" : "ВЫКЛ"}) → ждём ESP32...');
    } else {
      isPhytoLightActive = targetState;
      addLog(isPhytoLightActive ? 'Фито-LED ВКЛ (локально)' : 'Фито-LED ВЫКЛ (локально)');
      saveToCache();
    }
    notifyListeners();
  }

  void togglePhytoLight() => setPhytoLightState(!isPhytoLightActive);

  void setWhiteLightState(bool targetState) {
    _publish('greenhouse/light/white/set', targetState ? '1' : '0', retain: false);
    if (isConnected && isControllerOnline && !kIsWeb) {
      isPendingWhite = true;
      addLog('Запрос Белого LED (${targetState ? "ВКЛ" : "ВЫКЛ"}) → ждём ESP32...');
    } else {
      isWhiteLightActive = targetState;
      addLog(isWhiteLightActive ? 'Белый LED ВКЛ (локально)' : 'Белый LED ВЫКЛ (локально)');
      saveToCache();
    }
    notifyListeners();
  }

  void toggleWhiteLight() => setWhiteLightState(!isWhiteLightActive);

  void toggleControlMode() {
    final targetMode = !isAutoModeActive;
    _publish('greenhouse/mode/set', targetMode ? 'auto' : 'manual', retain: false);

    if (isConnected && isControllerOnline && !kIsWeb) {
      isPendingMode = true;
      addLog('Смена режима → ${targetMode ? "АВТО" : "РУЧНОЙ"} (ждём ESP32)...');
    } else {
      isAutoModeActive = targetMode;
      addLog('Режим: ${isAutoModeActive ? "АВТО" : "РУЧНОЙ"} (локально)');
      saveToCache();
    }
    notifyListeners();
  }

  // ==================== ГИБКИЙ ДВИЖОК СЦЕНАРИЕВ ====================
  double _getSensorNumericValue(String sensorType) {
    switch (sensorType) {
      case 'airTemp':
        return airTemp;
      case 'outdoorTemp':
        return outdoorTemp;
      case 'airHumidity':
        return airHumidity;
      case 'soilMoisture':
        return soilMoisture;
      case 'lightLux':
        return lightLux.toDouble();
      case 'co2':
        return co2Level.toDouble();
      case 'voltage':
        return voltage;
      case 'timeHour':
        return timeOfDayHours;
      default:
        return airTemp;
    }
  }

  bool _checkSingleCondition(String sensorType, String op, double target) {
    final val = _getSensorNumericValue(sensorType);
    switch (op) {
      case '>':
        return val > target;
      case '<':
        return val < target;
      case '>=':
        return val >= target;
      case '<=':
        return val <= target;
      default:
        return val > target;
    }
  }

  void executeRuleActions(AutomationRule rule, {bool manualTest = false}) {
    for (final action in rule.actions) {
      switch (action.target) {
        case 'roofAngle':
          setRoofBothAngle(action.value);
          break;
        case 'doorAngle':
          setDoorBothAngle(action.value);
          break;
        case 'allServos':
          setAllServosAngle(action.value);
          break;
        case 'pump':
          setWateringState(action.value >= 1);
          break;
        case 'phytoLight':
          setPhytoLightState(action.value >= 1);
          break;
        case 'whiteLight':
          setWhiteLightState(action.value >= 1);
          break;
      }
    }
    addLog(manualTest
        ? 'Ручной запуск сценария: "${rule.name}"'
        : 'Сработал сценарий: "${rule.name}"');
  }

  void evaluateAutomationRules() {
    for (final rule in rules) {
      if (!rule.isEnabled) continue;

      final cond1 = _checkSingleCondition(
          rule.sensorType, rule.operatorType, rule.threshold);

      bool finalCondition = cond1;
      if (rule.hasSecondCondition) {
        final cond2 = _checkSingleCondition(
            rule.secondSensorType, rule.secondOperatorType, rule.secondThreshold);
        finalCondition = (rule.logicOperator == 'OR') ? (cond1 || cond2) : (cond1 && cond2);
      }

      if (finalCondition && !rule.wasTriggered) {
        rule.wasTriggered = true;
        executeRuleActions(rule);
      } else if (!finalCondition && rule.wasTriggered) {
        rule.wasTriggered = false;
      }
    }
    notifyListeners();
  }

  void toggleRule(String id, bool val) {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx].isEnabled = val;
      rules[idx].wasTriggered = false;
      addLog('Сценарий "${rules[idx].name}": ${val ? "ВКЛ" : "ВЫКЛ"}');
      _syncRulesToController();
      evaluateAutomationRules();
      saveToCache();
      notifyListeners();
    }
  }

  void saveOrUpdateRule(AutomationRule newRule) {
    final idx = rules.indexWhere((r) => r.id == newRule.id);
    if (idx != -1) {
      rules[idx] = newRule;
      addLog('Обновлён сценарий: "${newRule.name}"');
    } else {
      rules.add(newRule);
      addLog('Создан сценарий: "${newRule.name}"');
    }
    _syncRulesToController();
    evaluateAutomationRules();
    saveToCache();
    notifyListeners();
  }

  void deleteRule(String id) {
    rules.removeWhere((r) => r.id == id);
    addLog('Сценарий удалён');
    _syncRulesToController();
    saveToCache();
    notifyListeners();
  }

  void _syncRulesToController() {
    final payload = jsonEncode(rules.map((r) => r.toJson()).toList());
    _publish('greenhouse/config/rules', payload);
  }

  // ==================== СИМУЛЯЦИЯ И РЕЖИМ АДМИНИСТРАТОРА ====================
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
      addLog('Режим администратора разблокирован');
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockDeveloperMode() {
    isDeveloperUnlocked = false;
    notifyListeners();
  }

  // ==================== MQTT ПОДКЛЮЧЕНИЕ И ОБМЕН ====================
  Future<void> connect({bool forceReconnect = false}) async {
    await saveToCache();
    if (kIsWeb) {
      isConnected = true;
      lastConnectionError = null;
      notifyListeners();
      return;
    }

    if (_client != null && isConnected && !forceReconnect) {
      requestFullStatus();
      return;
    }

    if (broker.isEmpty || broker == 'your-cluster.s1.eu.hivemq.cloud') {
      lastConnectionError = 'Укажите адрес вашего кластера HiveMQ';
      isConnected = false;
      isControllerOnline = false;
      notifyListeners();
      return;
    }

    final clientId = 'gh_ios_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(broker, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 25;
    _client!.connectTimeoutPeriod = 8000;
    _client!.secure = (port == 8883 || port == 8884);
    _client!.autoReconnect = true;

    _client!.onConnected = () {
      isConnected = true;
      lastConnectionError = null;
      addLog('Телефон подключен к MQTT ($broker)');
      _subscribeToTopics();
      requestFullStatus();
      notifyListeners();
    };

    _client!.onAutoReconnected = () {
      isConnected = true;
      lastConnectionError = null;
      _subscribeToTopics();
      requestFullStatus();
      notifyListeners();
    };

    _client!.onDisconnected = () {
      isConnected = false;
      isControllerOnline = false;
      isPendingWatering = false;
      isPendingPhyto = false;
      isPendingWhite = false;
      isPendingMode = false;
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
      if (_client!.connectionStatus?.state != MqttConnectionState.connected) {
        lastConnectionError =
            'Отказ брокера: ${_client!.connectionStatus?.returnCode ?? "ошибка авторизации"}';
        isConnected = false;
        isControllerOnline = false;
        notifyListeners();
      }
    } catch (e) {
      lastConnectionError = 'Ошибка соединения: $e';
      isConnected = false;
      isControllerOnline = false;
      addLog('Ошибка подключения MQTT: $e');
      try {
        _client?.disconnect();
      } catch (_) {}
      notifyListeners();
    }
  }

  void requestFullStatus() {
    _publish('greenhouse/status/get', '1', retain: false);
  }

  void _subscribeToTopics() {
    if (_client == null) return;

    _client!.subscribe('greenhouse/telemetry/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/state/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/status/online', MqttQos.atLeastOnce);

    _updatesSubscription?.cancel();
    _updatesSubscription =
        _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      for (final msg in c) {
        final recMsg = msg.payload as MqttPublishMessage?;
        if (recMsg == null) continue;

        final payload =
            MqttPublishPayload.bytesToStringAsString(recMsg.payload.message).trim();
        _handleIncomingMessage(msg.topic, payload);
      }
    });
  }

  void _handleIncomingMessage(String topic, String payload) {
    try {
      // Отслеживание онлайн-статуса контроллера ESP32-S3
      if (topic == 'greenhouse/status/online') {
        final online = (payload == '1' ||
            payload.toLowerCase() == 'true' ||
            payload.toLowerCase() == 'online');
        if (isControllerOnline != online) {
          isControllerOnline = online;
          addLog(online
              ? 'Контроллер ESP32-S3 в сети'
              : 'Контроллер ESP32-S3 отключился от MQTT');
        }
        if (online) lastControllerPacketTime = DateTime.now();
        notifyListeners();
        return;
      }

      // Любой свежий пакет с телеметрией или статусом подтверждает, что ESP32 в сети
      lastControllerPacketTime = DateTime.now();
      if (!isControllerOnline) {
        isControllerOnline = true;
      }

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
        isWateringActive = (payload == '1' ||
            payload.toLowerCase() == 'true' ||
            payload.toLowerCase() == 'on');
        isPendingWatering = false;
        addLog('ESP32 подтвердил: Насос ${isWateringActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/phyto') {
        isPhytoLightActive = (payload == '1' ||
            payload.toLowerCase() == 'true' ||
            payload.toLowerCase() == 'on');
        isPendingPhyto = false;
        addLog('ESP32 подтвердил: Фито-свет ${isPhytoLightActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/white') {
        isWhiteLightActive = (payload == '1' ||
            payload.toLowerCase() == 'true' ||
            payload.toLowerCase() == 'on');
        isPendingWhite = false;
        addLog('ESP32 подтвердил: Белый свет ${isWhiteLightActive ? "ВКЛ" : "ВЫКЛ"}');
        saveToCache();
        notifyListeners();
        return;
      }
      if (topic == 'greenhouse/state/mode') {
        isAutoModeActive = (payload.toLowerCase() == 'auto' || payload == '1');
        isPendingMode = false;
        addLog('ESP32 подтвердил режим: ${isAutoModeActive ? "АВТО" : "РУЧНОЙ"}');
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
      addLog('Ошибка разбора ($topic): $e');
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