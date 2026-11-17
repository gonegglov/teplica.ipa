import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorThresholdConfig {
  final String key;
  final String name;
  final String unit;
  final double minLimit;
  final double maxLimit;
  double threshold;
  double hysteresisPercent;
  bool alertWhenHigh;

  SensorThresholdConfig({
    required this.key,
    required this.name,
    required this.unit,
    required this.minLimit,
    required this.maxLimit,
    required this.threshold,
    this.hysteresisPercent = 10.0,
    required this.alertWhenHigh,
  });

  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'hysteresisPercent': hysteresisPercent,
        'alertWhenHigh': alertWhenHigh,
      };

  void applyFromJson(Map<String, dynamic> json) {
    if (json['threshold'] != null) {
      threshold = (json['threshold'] as num).toDouble();
    }
    if (json['hysteresisPercent'] != null) {
      hysteresisPercent = (json['hysteresisPercent'] as num).toDouble();
    }
    if (json['alertWhenHigh'] != null) {
      alertWhenHigh = json['alertWhenHigh'] == true;
    }
  }
}

class RuleAction {
  String target;
  double value;

  RuleAction({required this.target, required this.value});

  String describe() {
    switch (target) {
      case 'roofAngle':
        return 'Оба окна → ${value.toInt()}°';
      case 'doorAngle':
        return 'Обе двери → ${value.toInt()}°';
      case 'roofLeft':
        return 'Левое окно → ${value.toInt()}°';
      case 'roofRight':
        return 'Правое окно → ${value.toInt()}°';
      case 'doorFront':
        return 'Передняя дверь → ${value.toInt()}°';
      case 'doorBack':
        return 'Задняя дверь → ${value.toInt()}°';
      case 'allServos':
        return 'Все сервоприводы → ${value.toInt()}°';
      case 'pump':
        return 'Полив → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      case 'pumpTimer':
        return 'Полив на ${value.toInt()} сек';
      case 'phytoLight':
        return 'Фито-LED → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      case 'whiteLight':
        return 'Белый LED → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      case 'ledRed':
        return 'Красный LED → ${_ledModeText(value)}';
      case 'ledGreen':
        return 'Зелёный LED → ${_ledModeText(value)}';
      case 'ledBlue':
        return 'Синий LED → ${_ledModeText(value)}';
      case 'ledYellow':
        return 'Жёлтый LED → ${_ledModeText(value)}';
      case 'buzzer':
        return 'Звук пьезо (${value.toInt()} писка)';
      default:
        return '$target: $value';
    }
  }

  String _ledModeText(double v) {
    if (v.toInt() == 2) return 'АВТО';
    return v >= 1 ? 'ВКЛ' : 'ВЫКЛ';
  }

  Map<String, dynamic> toJson() => {'target': target, 'value': value};

  factory RuleAction.fromJson(Map<String, dynamic> json) {
    return RuleAction(
      target: json['target']?.toString() ?? 'roofAngle',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AutomationRule {
  String id;
  String name;
  String sensorType;
  String operatorType;
  double threshold;
  bool hasSecondCondition;
  String logicOperator;
  String secondSensorType;
  String secondOperatorType;
  double secondThreshold;
  List<RuleAction> actions;
  bool isEnabled;
  bool _wasTriggered = false;

  AutomationRule({
    required this.id,
    required this.name,
    required this.sensorType,
    required this.operatorType,
    required this.threshold,
    this.hasSecondCondition = false,
    this.logicOperator = 'AND',
    this.secondSensorType = 'lightLux',
    this.secondOperatorType = '>',
    this.secondThreshold = 300.0,
    required this.actions,
    this.isEnabled = true,
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
    final rawActions = (json['actions'] as List?) ?? [];
    return AutomationRule(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Сценарий',
      sensorType: json['sensorType']?.toString() ?? 'airTemp',
      operatorType: json['operatorType']?.toString() ?? '>',
      threshold: (json['threshold'] as num?)?.toDouble() ?? 26.0,
      hasSecondCondition: json['hasSecondCondition'] == true,
      logicOperator: json['logicOperator']?.toString() ?? 'AND',
      secondSensorType: json['secondSensorType']?.toString() ?? 'lightLux',
      secondOperatorType: json['secondOperatorType']?.toString() ?? '>',
      secondThreshold: (json['secondThreshold'] as num?)?.toDouble() ?? 300.0,
      actions: rawActions
          .map((e) => RuleAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      isEnabled: json['isEnabled'] != false,
    );
  }
}

class GreenhouseMqttService extends ChangeNotifier {
  static const Duration modeHoldDuration = Duration(milliseconds: 1500);
  static const Duration actuatorTimeoutDuration = Duration(milliseconds: 7500); // 7.5 сек таймаут
  static const Duration errorDisplayDuration = Duration(seconds: 2); // 2 сек показ ошибки

  String broker = 'test.mosquitto.org';
  int port = 1883;
  String username = '';
  String password = '';

  MqttServerClient? _client;
  bool isConnected = false;
  bool isControllerOnline = false;
  String? lastConnectionError;
  DateTime _lastEspPacketTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _watchdogTimer;

  // Показания датчиков и часов ESP32
  double airTemp = 24.5;
  double outdoorTemp = 16.0;
  double airHumidity = 55.0;
  double soilMoisture = 50.0;
  int lightLux = 600;
  int co2Level = 420;
  double voltage = 12.4;
  String rtcTimeString = '12:00';

  // Состояния устройств
  bool isAutoModeActive = true;
  bool isWateringActive = false;
  bool isPhytoLightActive = false;
  bool isWhiteLightActive = false;

  // Флаги ожидания ответа (Pending) и ошибки таймаута (Error на 2 сек)
  bool isPendingMode = false;
  bool isErrorMode = false;
  Timer? _modeTimeoutTimer;

  bool isPendingWatering = false;
  bool isErrorWatering = false;
  Timer? _wateringTimeoutTimer;

  bool isPendingPhyto = false;
  bool isErrorPhyto = false;
  Timer? _phytoTimeoutTimer;

  bool isPendingWhite = false;
  bool isErrorWhite = false;
  Timer? _whiteTimeoutTimer;

  double roofLeftAngle = 0.0;
  double roofRightAngle = 0.0;
  double doorFrontAngle = 0.0;
  double doorBackAngle = 0.0;

  double maxRoofAngleLimit = 180.0;
  double maxDoorAngleLimit = 180.0;

  bool isDeveloperUnlocked = false;
  static const String _adminPin = '1234';

  // Список активных ошибок с ESP32 (Пункт 7 ERRORS)
  List<String> activeErrors = [];
  bool isAlarmActive = false;

  final List<String> eventLogs = [];
  final List<AutomationRule> rules = [];

  final Map<String, SensorThresholdConfig> sensorConfigs = {
    'airTemp': SensorThresholdConfig(
      key: 'airTemp',
      name: 'Температура внутри',
      unit: '°C',
      minLimit: 5,
      maxLimit: 50,
      threshold: 26.0,
      alertWhenHigh: true,
    ),
    'outdoorTemp': SensorThresholdConfig(
      key: 'outdoorTemp',
      name: 'Температура на улице',
      unit: '°C',
      minLimit: -20,
      maxLimit: 45,
      threshold: 12.0,
      alertWhenHigh: false,
    ),
    'airHumidity': SensorThresholdConfig(
      key: 'airHumidity',
      name: 'Влажность воздуха',
      unit: '%',
      minLimit: 10,
      maxLimit: 100,
      threshold: 70.0,
      alertWhenHigh: true,
    ),
    'soilMoisture': SensorThresholdConfig(
      key: 'soilMoisture',
      name: 'Влажность почвы',
      unit: '%',
      minLimit: 5,
      maxLimit: 100,
      threshold: 35.0,
      alertWhenHigh: false,
    ),
    'lightLux': SensorThresholdConfig(
      key: 'lightLux',
      name: 'Освещённость',
      unit: ' лк',
      minLimit: 0,
      maxLimit: 1200,
      threshold: 300.0,
      alertWhenHigh: false,
    ),
    'co2': SensorThresholdConfig(
      key: 'co2',
      name: 'Уровень CO₂',
      unit: ' ppm',
      minLimit: 350,
      maxLimit: 2500,
      threshold: 900.0,
      alertWhenHigh: true,
    ),
  };

  GreenhouseMqttService() {
    _initService();
  }

  Future<void> _initService() async {
    await _loadFromCache();
    await connect();

    // Частый опрос состояния подключения ESP32 к MQTT (каждые 2 секунды)
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (isConnected) {
        _publish('greenhouse/status/ping', '1');
      }
      final onlineNow =
          isConnected && DateTime.now().difference(_lastEspPacketTime).inSeconds < 5;
      if (onlineNow != isControllerOnline) {
        isControllerOnline = onlineNow;
        notifyListeners();
      }
    });
  }

  // ==================== СОХРАНЕНИЕ И ЗАГРУЗКА ИЗ ПАМЯТИ ТЕЛЕФОНА ====================
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      broker = prefs.getString('mqtt_broker') ?? broker;
      port = prefs.getInt('mqtt_port') ?? port;
      username = prefs.getString('mqtt_user') ?? username;
      password = prefs.getString('mqtt_pass') ?? password;

      isAutoModeActive = prefs.getBool('state_auto_mode') ?? isAutoModeActive;
      isWateringActive = prefs.getBool('state_pump') ?? isWateringActive;
      isPhytoLightActive = prefs.getBool('state_phyto') ?? isPhytoLightActive;
      isWhiteLightActive = prefs.getBool('state_white') ?? isWhiteLightActive;

      roofLeftAngle = prefs.getDouble('servo_roof_l') ?? 0.0;
      roofRightAngle = prefs.getDouble('servo_roof_r') ?? 0.0;
      doorFrontAngle = prefs.getDouble('servo_door_f') ?? 0.0;
      doorBackAngle = prefs.getDouble('servo_door_b') ?? 0.0;

      maxRoofAngleLimit = prefs.getDouble('limit_roof') ?? 180.0;
      maxDoorAngleLimit = prefs.getDouble('limit_door') ?? 180.0;

      // Загрузка порогов датчиков
      final thrJson = prefs.getString('sensor_thresholds');
      if (thrJson != null && thrJson.isNotEmpty) {
        final decoded = jsonDecode(thrJson) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (sensorConfigs.containsKey(key) && val is Map) {
            sensorConfigs[key]!.applyFromJson(Map<String, dynamic>.from(val));
          }
        });
      }

      // Загрузка сценариев и их состояний (ВКЛ / ВЫКЛ)
      final rulesJson = prefs.getString('automation_rules');
      if (rulesJson != null && rulesJson.isNotEmpty) {
        final list = jsonDecode(rulesJson) as List;
        rules
          ..clear()
          ..addAll(
            list.map((e) => AutomationRule.fromJson(Map<String, dynamic>.from(e as Map))),
          );
      } else {
        _initDefaultRules();
      }
      notifyListeners();
    } catch (_) {
      if (rules.isEmpty) _initDefaultRules();
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_broker', broker);
      await prefs.setInt('mqtt_port', port);
      await prefs.setString('mqtt_user', username);
      await prefs.setString('mqtt_pass', password);

      await prefs.setBool('state_auto_mode', isAutoModeActive);
      await prefs.setBool('state_pump', isWateringActive);
      await prefs.setBool('state_phyto', isPhytoLightActive);
      await prefs.setBool('state_white', isWhiteLightActive);

      await prefs.setDouble('servo_roof_l', roofLeftAngle);
      await prefs.setDouble('servo_roof_r', roofRightAngle);
      await prefs.setDouble('servo_door_f', doorFrontAngle);
      await prefs.setDouble('servo_door_b', doorBackAngle);

      await prefs.setDouble('limit_roof', maxRoofAngleLimit);
      await prefs.setDouble('limit_door', maxDoorAngleLimit);

      final thrMap = <String, dynamic>{};
      sensorConfigs.forEach((k, v) => thrMap[k] = v.toJson());
      await prefs.setString('sensor_thresholds', jsonEncode(thrMap));

      final rulesList = rules.map((r) => r.toJson()).toList();
      await prefs.setString('automation_rules', jsonEncode(rulesList));
    } catch (_) {}
  }

  void _initDefaultRules() {
    rules.addAll([
      AutomationRule(
        id: '1',
        name: 'Проветривание при жаре',
        sensorType: 'airTemp',
        operatorType: '>',
        threshold: 26.0,
        actions: [
          RuleAction(target: 'roofAngle', value: 120),
          RuleAction(target: 'doorAngle', value: 60),
          RuleAction(target: 'buzzer', value: 1),
        ],
      ),
      AutomationRule(
        id: '2',
        name: 'Автополив сухой почвы',
        sensorType: 'soilMoisture',
        operatorType: '<',
        threshold: 35.0,
        actions: [
          RuleAction(target: 'pumpTimer', value: 30),
          RuleAction(target: 'ledBlue', value: 1),
        ],
      ),
    ]);
  }

  // ==================== ПОДКЛЮЧЕНИЕ К MQTT ====================
  Future<void> connect() async {
    _client?.disconnect();
    final clientId = 'Flutter_GH_${Random().nextInt(99999)}';
    _client = MqttServerClient.withPort(broker, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 15;
    _client!.secure = (port == 8883);
    _client!.onDisconnected = _onDisconnected;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      lastConnectionError = null;
      if (username.trim().isNotEmpty) {
        await _client!.connect(username.trim(), password);
      } else {
        await _client!.connect();
      }
    } catch (e) {
      lastConnectionError = 'Ошибка сети: $e';
      isConnected = false;
      isControllerOnline = false;
      _client?.disconnect();
      notifyListeners();
      return;
    }

    if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
      isConnected = true;
      _addLog('Подключено к MQTT ($broker:$port)');
      _subscribeAllTopics();
      _syncRulesToEsp();
      requestFullStatus();
      notifyListeners();
    } else {
      isConnected = false;
      isControllerOnline = false;
      lastConnectionError = 'Код ответа: ${_client!.connectionStatus?.returnCode}';
      _client?.disconnect();
      notifyListeners();
    }
  }

  void _subscribeAllTopics() {
    if (_client == null) return;
    _client!.subscribe('greenhouse/telemetry/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/state/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/status/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/errors/#', MqttQos.atLeastOnce);
    _client!.subscribe('greenhouse/scenarios/state', MqttQos.atLeastOnce);

    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      final recMess = c[0].payload as MqttPublishMessage;
      final topic = c[0].topic;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      _handleIncomingMessage(topic, payload);
    });
  }

  // ==================== ПРИЁМ ДАННЫХ ОТ ESP32 ====================
  void _handleIncomingMessage(String topic, String payload) {
    _lastEspPacketTime = DateTime.now();
    if (!isControllerOnline) {
      isControllerOnline = true;
    }

    if (topic == 'greenhouse/status/online') {
      isControllerOnline = (payload.trim() == '1');
      notifyListeners();
      return;
    }

    if (topic == 'greenhouse/status/pong') {
      isControllerOnline = true;
      notifyListeners();
      return;
    }

    if (topic == 'greenhouse/telemetry/all') {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        if (data['airTemp'] != null) airTemp = (data['airTemp'] as num).toDouble();
        if (data['outdoorTemp'] != null) outdoorTemp = (data['outdoorTemp'] as num).toDouble();
        if (data['airHumidity'] != null) airHumidity = (data['airHumidity'] as num).toDouble();
        if (data['soilMoisture'] != null) soilMoisture = (data['soilMoisture'] as num).toDouble();
        if (data['lightLux'] != null) lightLux = (data['lightLux'] as num).toInt();
        if (data['co2'] != null) co2Level = (data['co2'] as num).toInt();
        if (data['voltage'] != null) voltage = (data['voltage'] as num).toDouble();
        if (data['time'] != null) rtcTimeString = data['time'].toString();

        // Если состояние подтверждено контроллером (или изменено вручную на ESP32)
        if (data['pump'] != null) {
          final newPump = (data['pump'] == 1 || data['pump'] == true);
          if (!isPendingWatering || newPump != isWateringActive) {
            _confirmWateringState(newPump);
          }
        }
        if (data['phyto'] != null) {
          final newPhyto = (data['phyto'] == 1 || data['phyto'] == true);
          if (!isPendingPhyto || newPhyto != isPhytoLightActive) {
            _confirmPhytoState(newPhyto);
          }
        }
        if (data['white'] != null) {
          final newWhite = (data['white'] == 1 || data['white'] == true);
          if (!isPendingWhite || newWhite != isWhiteLightActive) {
            _confirmWhiteState(newWhite);
          }
        }
        if (data['mode'] != null) {
          final newAuto = (data['mode'].toString() == 'auto');
          if (!isPendingMode || newAuto != isAutoModeActive) {
            _confirmModeState(newAuto);
          }
        }

        if (data['roofLeft'] != null) roofLeftAngle = (data['roofLeft'] as num).toDouble();
        if (data['roofRight'] != null) roofRightAngle = (data['roofRight'] as num).toDouble();
        if (data['doorFront'] != null) doorFrontAngle = (data['doorFront'] as num).toDouble();
        if (data['doorBack'] != null) doorBackAngle = (data['doorBack'] as num).toDouble();

        if (data['thresholds'] is Map) {
          final thrMap = data['thresholds'] as Map;
          thrMap.forEach((k, v) {
            if (sensorConfigs.containsKey(k) && v is num) {
              sensorConfigs[k]!.threshold = v.toDouble();
            }
          });
        }

        if (data['errors'] is List) {
          activeErrors = (data['errors'] as List).map((e) => e.toString()).toList();
          isAlarmActive = activeErrors.isNotEmpty;
        }

        _saveToCache();
        _evaluateAutoRules();
      } catch (_) {}
      notifyListeners();
      return;
    }

    // Мгновенные подтверждения от ESP32 (снимают таймер ожидания 7.5с)
    if (topic == 'greenhouse/state/time') {
      rtcTimeString = payload.trim();
    } else if (topic == 'greenhouse/state/mode') {
      _confirmModeState(payload.trim() == 'auto');
    } else if (topic == 'greenhouse/state/pump') {
      _confirmWateringState(payload.trim() == '1');
    } else if (topic == 'greenhouse/state/phyto') {
      _confirmPhytoState(payload.trim() == '1');
    } else if (topic == 'greenhouse/state/white') {
      _confirmWhiteState(payload.trim() == '1');
    } else if (topic == 'greenhouse/state/roof_left') {
      roofLeftAngle = double.tryParse(payload) ?? roofLeftAngle;
    } else if (topic == 'greenhouse/state/roof_right') {
      roofRightAngle = double.tryParse(payload) ?? roofRightAngle;
    } else if (topic == 'greenhouse/state/door_front') {
      doorFrontAngle = double.tryParse(payload) ?? doorFrontAngle;
    } else if (topic == 'greenhouse/state/door_back') {
      doorBackAngle = double.tryParse(payload) ?? doorBackAngle;
    } else if (topic.startsWith('greenhouse/state/threshold/')) {
      final key = topic.split('/').last;
      if (sensorConfigs.containsKey(key)) {
        try {
          final d = jsonDecode(payload) as Map<String, dynamic>;
          sensorConfigs[key]!.applyFromJson(d);
        } catch (_) {}
      }
    } else if (topic == 'greenhouse/errors/list') {
      try {
        final list = jsonDecode(payload) as List;
        activeErrors = list.map((e) => e.toString()).toList();
        isAlarmActive = activeErrors.isNotEmpty;
      } catch (_) {}
    }

    _saveToCache();
    notifyListeners();
  }

  // Подтверждение команд от ESP32 (отмена таймаута ошибки)
  void _confirmModeState(bool autoMode) {
    _modeTimeoutTimer?.cancel();
    isPendingMode = false;
    isErrorMode = false;
    isAutoModeActive = autoMode;
  }

  void _confirmWateringState(bool active) {
    _wateringTimeoutTimer?.cancel();
    isPendingWatering = false;
    isErrorWatering = false;
    isWateringActive = active;
  }

  void _confirmPhytoState(bool active) {
    _phytoTimeoutTimer?.cancel();
    isPendingPhyto = false;
    isErrorPhyto = false;
    isPhytoLightActive = active;
  }

  void _confirmWhiteState(bool active) {
    _whiteTimeoutTimer?.cancel();
    isPendingWhite = false;
    isErrorWhite = false;
    isWhiteLightActive = active;
  }

  void _onDisconnected() {
    isConnected = false;
    isControllerOnline = false;
    notifyListeners();
  }

  void _publish(String topic, String message, {bool retain = false}) {
    if (_client == null || !isConnected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(message);
    _client!.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  void requestFullStatus() {
    _publish('greenhouse/status/get', '1');
  }

  // ==================== УПРАВЛЕНИЕ С ТАЙМАУТОМ 7.5 СЕК И ОШИБКОЙ НА 2 СЕК ====================
  void toggleControlMode() {
    if (isPendingMode || isErrorMode) return;
    isPendingMode = true;
    isErrorMode = false;
    final nextMode = isAutoModeActive ? 'manual' : 'auto';
    _publish('greenhouse/mode/set', nextMode);
    _addLog('Запрос смены режима → ${nextMode.toUpperCase()}');
    notifyListeners();

    _modeTimeoutTimer?.cancel();
    _modeTimeoutTimer = Timer(actuatorTimeoutDuration, () {
      if (isPendingMode) {
        isPendingMode = false;
        isErrorMode = true;
        _addLog('Ошибка: ESP32 не ответила на смену режима');
        notifyListeners();
        Timer(errorDisplayDuration, () {
          isErrorMode = false;
          notifyListeners();
        });
      }
    });
  }

  void toggleWatering() {
    if (isPendingWatering || isErrorWatering) return;
    isPendingWatering = true;
    isErrorWatering = false;
    final next = !isWateringActive;
    _publish('greenhouse/pump/set', next ? '1' : '0');
    _addLog('Запрос: Полив → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();

    _wateringTimeoutTimer?.cancel();
    _wateringTimeoutTimer = Timer(actuatorTimeoutDuration, () {
      if (isPendingWatering) {
        isPendingWatering = false;
        isErrorWatering = true;
        _addLog('Ошибка: нет отклика от помпы полива (7.5 с)');
        notifyListeners();
        Timer(errorDisplayDuration, () {
          isErrorWatering = false;
          notifyListeners();
        });
      }
    });
  }

  void runPumpTimer(int seconds) {
    if (isPendingWatering || isErrorWatering) return;
    isPendingWatering = true;
    isErrorWatering = false;
    _publish('greenhouse/pump/timer/set', seconds.toString());
    _addLog('Запуск полива на $seconds сек');
    notifyListeners();

    _wateringTimeoutTimer?.cancel();
    _wateringTimeoutTimer = Timer(actuatorTimeoutDuration, () {
      if (isPendingWatering) {
        isPendingWatering = false;
        isErrorWatering = true;
        _addLog('Ошибка: помпа не ответила на таймер');
        notifyListeners();
        Timer(errorDisplayDuration, () {
          isErrorWatering = false;
          notifyListeners();
        });
      }
    });
  }

  void togglePhytoLight() {
    if (isPendingPhyto || isErrorPhyto) return;
    isPendingPhyto = true;
    isErrorPhyto = false;
    final next = !isPhytoLightActive;
    _publish('greenhouse/light/phyto/set', next ? '1' : '0');
    _addLog('Запрос: Фито-LED → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();

    _phytoTimeoutTimer?.cancel();
    _phytoTimeoutTimer = Timer(actuatorTimeoutDuration, () {
      if (isPendingPhyto) {
        isPendingPhyto = false;
        isErrorPhyto = true;
        _addLog('Ошибка: нет отклика от Фито-LED (7.5 с)');
        notifyListeners();
        Timer(errorDisplayDuration, () {
          isErrorPhyto = false;
          notifyListeners();
        });
      }
    });
  }

  void toggleWhiteLight() {
    if (isPendingWhite || isErrorWhite) return;
    isPendingWhite = true;
    isErrorWhite = false;
    final next = !isWhiteLightActive;
    _publish('greenhouse/light/white/set', next ? '1' : '0');
    _addLog('Запрос: Белый LED → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();

    _whiteTimeoutTimer?.cancel();
    _whiteTimeoutTimer = Timer(actuatorTimeoutDuration, () {
      if (isPendingWhite) {
        isPendingWhite = false;
        isErrorWhite = true;
        _addLog('Ошибка: нет отклика от Белого LED (7.5 с)');
        notifyListeners();
        Timer(errorDisplayDuration, () {
          isErrorWhite = false;
          notifyListeners();
        });
      }
    });
  }

  // ==================== ВРЕМЯ, СЕРВОПРИВОДЫ И ПОРОГИ ====================
  void setControllerTime(int hour, int minute) {
    final formatted =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    rtcTimeString = formatted;
    _publish('greenhouse/time/set', formatted, retain: true);
    _addLog('Время контроллера изменено на $formatted');
    notifyListeners();
  }

  void syncPhoneTimeToController() {
    final now = DateTime.now();
    setControllerTime(now.hour, now.minute);
  }

  void setRoofLeftAngle(double val, {bool log = true}) {
    roofLeftAngle = val.clamp(0.0, maxRoofAngleLimit);
    _publish('greenhouse/servo/roof_left/set', roofLeftAngle.toInt().toString());
    if (log) {
      _addLog('Левое окно: ${roofLeftAngle.toInt()}°');
      _saveToCache();
    }
    notifyListeners();
  }

  void setRoofRightAngle(double val, {bool log = true}) {
    roofRightAngle = val.clamp(0.0, maxRoofAngleLimit);
    _publish('greenhouse/servo/roof_right/set', roofRightAngle.toInt().toString());
    if (log) {
      _addLog('Правое окно: ${roofRightAngle.toInt()}°');
      _saveToCache();
    }
    notifyListeners();
  }

  void setDoorFrontAngle(double val, {bool log = true}) {
    doorFrontAngle = val.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/door_front/set', doorFrontAngle.toInt().toString());
    if (log) {
      _addLog('Передняя дверь: ${doorFrontAngle.toInt()}°');
      _saveToCache();
    }
    notifyListeners();
  }

  void setDoorBackAngle(double val, {bool log = true}) {
    doorBackAngle = val.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/door_back/set', doorBackAngle.toInt().toString());
    if (log) {
      _addLog('Задняя дверь: ${doorBackAngle.toInt()}°');
      _saveToCache();
    }
    notifyListeners();
  }

  void openAllServos() {
    setRoofLeftAngle(maxRoofAngleLimit, log: false);
    setRoofRightAngle(maxRoofAngleLimit, log: false);
    setDoorFrontAngle(maxDoorAngleLimit, log: false);
    setDoorBackAngle(maxDoorAngleLimit, log: false);
    _saveToCache();
    _addLog('Открыты все окна и двери');
  }

  void closeAllServos() {
    setRoofLeftAngle(0, log: false);
    setRoofRightAngle(0, log: false);
    setDoorFrontAngle(0, log: false);
    setDoorBackAngle(0, log: false);
    _saveToCache();
    _addLog('Закрыты все окна и двери');
  }

  void updateSensorThreshold(
    String key, {
    required double threshold,
    required double hysteresisPercent,
    required bool alertWhenHigh,
  }) {
    final cfg = sensorConfigs[key];
    if (cfg == null) return;
    cfg.threshold = threshold;
    cfg.hysteresisPercent = hysteresisPercent;
    cfg.alertWhenHigh = alertWhenHigh;

    final payload = jsonEncode({
      'threshold': double.parse(threshold.toStringAsFixed(1)),
      'hysteresisPercent': hysteresisPercent,
      'alertWhenHigh': alertWhenHigh,
    });
    _publish('greenhouse/threshold/$key', payload, retain: true);
    _saveToCache();
    _addLog('Порог ${cfg.name}: ${threshold.toStringAsFixed(1)}${cfg.unit}');
    notifyListeners();
  }

  Color getSensorValueColor(String key) {
    final cfg = sensorConfigs[key];
    if (cfg == null) return const Color(0xFF00E676);
    final val = _getSensorValueByKey(key);
    final breached =
        cfg.alertWhenHigh ? (val > cfg.threshold) : (val < cfg.threshold);
    if (breached) return Colors.redAccent;
    return const Color(0xFF00E676);
  }

  Color getSensorLabelColor(String key) => Colors.white70;

  double _getSensorValueByKey(String key) {
    switch (key) {
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
        final p = rtcTimeString.split(':');
        return double.tryParse(p.first) ?? 12.0;
      default:
        return 0.0;
    }
  }

  // ==================== ГИБКИЕ СЦЕНАРИИ И ИХ ВЫПОЛНЕНИЕ ====================
  void saveOrUpdateRule(AutomationRule rule) {
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    _saveToCache();
    _syncRulesToEsp();
    notifyListeners();
  }

  void toggleRule(String id, bool enabled) {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      rules[idx].isEnabled = enabled;
      _saveToCache();
      _syncRulesToEsp();
      notifyListeners();
    }
  }

  void deleteRule(String id) {
    rules.removeWhere((r) => r.id == id);
    _saveToCache();
    _syncRulesToEsp();
    notifyListeners();
  }

  void _syncRulesToEsp() {
    final payload = jsonEncode(rules.map((r) => r.toJson()).toList());
    _publish('greenhouse/scenarios/sync', payload, retain: true);
  }

  bool _checkSingleCondition(String sensor, String op, double thr) {
    final v = _getSensorValueByKey(sensor);
    switch (op) {
      case '>':
        return v > thr;
      case '<':
        return v < thr;
      case '>=':
        return v >= thr;
      case '<=':
        return v <= thr;
      default:
        return false;
    }
  }

  void _evaluateAutoRules() {
    if (!isAutoModeActive) return;
    for (final rule in rules) {
      if (!rule.isEnabled) {
        rule._wasTriggered = false;
        continue;
      }
      final c1 = _checkSingleCondition(
        rule.sensorType,
        rule.operatorType,
        rule.threshold,
      );
      bool matched = c1;
      if (rule.hasSecondCondition) {
        final c2 = _checkSingleCondition(
          rule.secondSensorType,
          rule.secondOperatorType,
          rule.secondThreshold,
        );
        matched = (rule.logicOperator == 'OR') ? (c1 || c2) : (c1 && c2);
      }

      if (matched && !rule._wasTriggered) {
        rule._wasTriggered = true;
        executeRuleActions(rule);
      } else if (!matched) {
        rule._wasTriggered = false;
      }
    }
  }

  void executeRuleActions(AutomationRule rule, {bool manualTest = false}) {
    for (final act in rule.actions) {
      switch (act.target) {
        case 'roofAngle':
          setRoofLeftAngle(act.value, log: false);
          setRoofRightAngle(act.value, log: false);
          break;
        case 'doorAngle':
          setDoorFrontAngle(act.value, log: false);
          setDoorBackAngle(act.value, log: false);
          break;
        case 'roofLeft':
          setRoofLeftAngle(act.value, log: false);
          break;
        case 'roofRight':
          setRoofRightAngle(act.value, log: false);
          break;
        case 'doorFront':
          setDoorFrontAngle(act.value, log: false);
          break;
        case 'doorBack':
          setDoorBackAngle(act.value, log: false);
          break;
        case 'allServos':
          setRoofLeftAngle(act.value, log: false);
          setRoofRightAngle(act.value, log: false);
          setDoorFrontAngle(act.value, log: false);
          setDoorBackAngle(act.value, log: false);
          break;
        case 'pump':
          _publish('greenhouse/pump/set', act.value >= 1 ? '1' : '0');
          break;
        case 'pumpTimer':
          _publish('greenhouse/pump/timer/set', act.value.toInt().toString());
          break;
        case 'phytoLight':
          _publish('greenhouse/light/phyto/set', act.value >= 1 ? '1' : '0');
          break;
        case 'whiteLight':
          _publish('greenhouse/light/white/set', act.value >= 1 ? '1' : '0');
          break;
        case 'ledRed':
          _publish('greenhouse/led/red/set', _ledPayload(act.value));
          break;
        case 'ledGreen':
          _publish('greenhouse/led/green/set', _ledPayload(act.value));
          break;
        case 'ledBlue':
          _publish('greenhouse/led/blue/set', _ledPayload(act.value));
          break;
        case 'ledYellow':
          _publish('greenhouse/led/yellow/set', _ledPayload(act.value));
          break;
        case 'buzzer':
          _publish('greenhouse/buzzer/beep', act.value.toInt().toString());
          break;
      }
    }
    _addLog('Сценарий выполнен: ${rule.name}');
    notifyListeners();
  }

  String _ledPayload(double val) {
    if (val.toInt() == 2) return 'auto';
    return val >= 1 ? '1' : '0';
  }

  // ==================== ПАРОЛЬ РАЗРАБОТЧИКА (4 ПИСКА ПРИ ОШИБКЕ) ====================
  bool unlockDeveloperMode(String pin) {
    if (pin.trim() == _adminPin) {
      isDeveloperUnlocked = true;
      _addLog('Вход в панель администратора выполнен');
      notifyListeners();
      return true;
    } else {
      // Отправляем сигнал на ESP32: пропищать 4 раза с задержкой 0.2 сек!
      _publish('greenhouse/buzzer/alert', 'wrong_pin');
      _addLog('ОШИБКА: Неверный ввод пароля администратора!');
      notifyListeners();
      return false;
    }
  }

  void lockDeveloperMode() {
    isDeveloperUnlocked = false;
    notifyListeners();
  }

  void setServoLimits(double roofMax, double doorMax) {
    maxRoofAngleLimit = roofMax;
    maxDoorAngleLimit = doorMax;
    _publish(
      'greenhouse/limits/set',
      jsonEncode({'roof': roofMax.toInt(), 'door': doorMax.toInt()}),
      retain: true,
    );
    _saveToCache();
    notifyListeners();
  }

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
    await _saveToCache();
    await connect();
  }

  void _addLog(String msg) {
    final t = rtcTimeString;
    eventLogs.insert(0, '[$t] $msg');
    if (eventLogs.length > 60) eventLogs.removeLast();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _modeTimeoutTimer?.cancel();
    _wateringTimeoutTimer?.cancel();
    _phytoTimeoutTimer?.cancel();
    _whiteTimeoutTimer?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}