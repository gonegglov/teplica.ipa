import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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
}

class RuleAction {
  String target;
  double value;

  RuleAction({required this.target, required this.value});

  String describe() {
    switch (target) {
      case 'roofAngle':
        return 'Окна крыши → ${value.toInt()}°';
      case 'doorAngle':
        return 'Двери → ${value.toInt()}°';
      case 'allServos':
        return 'Все приводы → ${value.toInt()}°';
      case 'pump':
        return 'Полив → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      case 'phytoLight':
        return 'Фито-LED → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      case 'whiteLight':
        return 'Белый LED → ${value >= 1 ? "ВКЛ" : "ВЫКЛ"}';
      default:
        return '$target: $value';
    }
  }

  Map<String, dynamic> toJson() => {'target': target, 'value': value};
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
        'isEnabled': isEnabled,
      };
}

class GreenhouseMqttService extends ChangeNotifier {
  static const Duration modeHoldDuration = Duration(milliseconds: 1500);

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

  bool isPendingMode = false;
  bool isPendingWatering = false;
  bool isPendingPhyto = false;
  bool isPendingWhite = false;

  double roofLeftAngle = 0.0;
  double roofRightAngle = 0.0;
  double doorFrontAngle = 0.0;
  double doorBackAngle = 0.0;

  double maxRoofAngleLimit = 180.0;
  double maxDoorAngleLimit = 180.0;

  bool isDeveloperUnlocked = false;
  static const String _adminPin = '1234';

  // Список активных ошибок, приходящий с ESP32 (Пункт 7 ERRORS)
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
    _initDefaultRules();
    connect();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final onlineNow =
          DateTime.now().difference(_lastEspPacketTime).inSeconds < 12;
      if (onlineNow != isControllerOnline) {
        isControllerOnline = onlineNow;
        notifyListeners();
      }
    });
  }

  void _initDefaultRules() {
    rules.add(
      AutomationRule(
        id: '1',
        name: 'Проветривание при жаре',
        sensorType: 'airTemp',
        operatorType: '>',
        threshold: 26.0,
        actions: [
          RuleAction(target: 'roofAngle', value: 120),
          RuleAction(target: 'doorAngle', value: 60),
        ],
      ),
    );
  }

  Future<void> connect() async {
    _client?.disconnect();
    final clientId = 'Flutter_GH_${Random().nextInt(99999)}';
    _client = MqttServerClient.withPort(broker, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
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
      lastConnectionError = 'Ошибка подключения: $e';
      isConnected = false;
      _client?.disconnect();
      notifyListeners();
      return;
    }

    if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
      isConnected = true;
      _addLog('Подключено к MQTT ($broker:$port)');
      _subscribeAllTopics();
      requestFullStatus();
      notifyListeners();
    } else {
      isConnected = false;
      lastConnectionError =
          'Статус: ${_client!.connectionStatus?.returnCode}';
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
    _client!.subscribe('greenhouse/threshold/#', MqttQos.atLeastOnce);

    _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      final recMess = c[0].payload as MqttPublishMessage;
      final topic = c[0].topic;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      _handleIncomingMessage(topic, payload);
    });
  }

  void _handleIncomingMessage(String topic, String payload) {
    _lastEspPacketTime = DateTime.now();
    isControllerOnline = true;

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

        if (data['pump'] != null) {
          isWateringActive = (data['pump'] == 1 || data['pump'] == true);
          isPendingWatering = false;
        }
        if (data['phyto'] != null) {
          isPhytoLightActive = (data['phyto'] == 1 || data['phyto'] == true);
          isPendingPhyto = false;
        }
        if (data['white'] != null) {
          isWhiteLightActive = (data['white'] == 1 || data['white'] == true);
          isPendingWhite = false;
        }
        if (data['mode'] != null) {
          isAutoModeActive = (data['mode'].toString() == 'auto');
          isPendingMode = false;
        }

        // Синхронизация углов сервоприводов, выставленных с энкодера ESP32
        if (data['roofLeft'] != null) roofLeftAngle = (data['roofLeft'] as num).toDouble();
        if (data['roofRight'] != null) roofRightAngle = (data['roofRight'] as num).toDouble();
        if (data['doorFront'] != null) doorFrontAngle = (data['doorFront'] as num).toDouble();
        if (data['doorBack'] != null) doorBackAngle = (data['doorBack'] as num).toDouble();

        // Синхронизация порогов датчиков, выставленных с энкодера ESP32
        if (data['thresholds'] is Map) {
          final thrMap = data['thresholds'] as Map;
          thrMap.forEach((k, v) {
            if (sensorConfigs.containsKey(k) && v is num) {
              sensorConfigs[k]!.threshold = v.toDouble();
            }
          });
        }

        // Синхронизация списка активных ошибок (ERRORS)
        if (data['errors'] is List) {
          activeErrors = (data['errors'] as List).map((e) => e.toString()).toList();
          isAlarmActive = activeErrors.isNotEmpty;
        }
      } catch (_) {}
      notifyListeners();
      return;
    }

    // Отдельные state-топики для мгновенного отклика при вращении энкодера
    if (topic == 'greenhouse/state/time') {
      rtcTimeString = payload.trim();
    } else if (topic == 'greenhouse/state/mode') {
      isAutoModeActive = (payload.trim() == 'auto');
      isPendingMode = false;
    } else if (topic == 'greenhouse/state/pump') {
      isWateringActive = (payload.trim() == '1');
      isPendingWatering = false;
    } else if (topic == 'greenhouse/state/phyto') {
      isPhytoLightActive = (payload.trim() == '1');
      isPendingPhyto = false;
    } else if (topic == 'greenhouse/state/white') {
      isWhiteLightActive = (payload.trim() == '1');
      isPendingWhite = false;
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
          final d = jsonDecode(payload);
          if (d['threshold'] != null) {
            sensorConfigs[key]!.threshold = (d['threshold'] as num).toDouble();
          }
          if (d['alertWhenHigh'] != null) {
            sensorConfigs[key]!.alertWhenHigh = d['alertWhenHigh'] == true;
          }
        } catch (_) {}
      }
    } else if (topic == 'greenhouse/errors/list') {
      try {
        final list = jsonDecode(payload) as List;
        activeErrors = list.map((e) => e.toString()).toList();
        isAlarmActive = activeErrors.isNotEmpty;
      } catch (_) {}
    }

    notifyListeners();
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

  // Установка времени контроллера с телефона ("HH:MM")
  void setControllerTime(int hour, int minute) {
    final formatted =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    rtcTimeString = formatted;
    _publish('greenhouse/time/set', formatted, retain: true);
    _addLog('Время контроллера установлено на $formatted');
    notifyListeners();
  }

  void syncPhoneTimeToController() {
    final now = DateTime.now();
    setControllerTime(now.hour, now.minute);
  }

  void toggleControlMode() {
    isPendingMode = true;
    final nextMode = isAutoModeActive ? 'manual' : 'auto';
    _publish('greenhouse/mode/set', nextMode, retain: true);
    _addLog('Запрос смены режима → ${nextMode.toUpperCase()}');
    notifyListeners();
  }

  void toggleWatering() {
    isPendingWatering = true;
    final next = !isWateringActive;
    _publish('greenhouse/pump/set', next ? '1' : '0', retain: true);
    _addLog('Полив → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();
  }

  void runPumpTimer(int seconds) {
    isPendingWatering = true;
    _publish('greenhouse/pump/timer/set', seconds.toString());
    _addLog('Запуск полива по таймеру на $seconds сек');
    notifyListeners();
  }

  void togglePhytoLight() {
    isPendingPhyto = true;
    final next = !isPhytoLightActive;
    _publish('greenhouse/light/phyto/set', next ? '1' : '0', retain: true);
    _addLog('Фито-LED → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();
  }

  void toggleWhiteLight() {
    isPendingWhite = true;
    final next = !isWhiteLightActive;
    _publish('greenhouse/light/white/set', next ? '1' : '0', retain: true);
    _addLog('Белый LED → ${next ? "ВКЛ" : "ВЫКЛ"}');
    notifyListeners();
  }

  void setRoofLeftAngle(double val, {bool log = true}) {
    roofLeftAngle = val.clamp(0.0, maxRoofAngleLimit);
    _publish('greenhouse/servo/roof_left/set', roofLeftAngle.toInt().toString());
    if (log) _addLog('Левое окно: ${roofLeftAngle.toInt()}°');
    notifyListeners();
  }

  void setRoofRightAngle(double val, {bool log = true}) {
    roofRightAngle = val.clamp(0.0, maxRoofAngleLimit);
    _publish('greenhouse/servo/roof_right/set', roofRightAngle.toInt().toString());
    if (log) _addLog('Правое окно: ${roofRightAngle.toInt()}°');
    notifyListeners();
  }

  void setDoorFrontAngle(double val, {bool log = true}) {
    doorFrontAngle = val.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/door_front/set', doorFrontAngle.toInt().toString());
    if (log) _addLog('Передняя дверь: ${doorFrontAngle.toInt()}°');
    notifyListeners();
  }

  void setDoorBackAngle(double val, {bool log = true}) {
    doorBackAngle = val.clamp(0.0, maxDoorAngleLimit);
    _publish('greenhouse/servo/door_back/set', doorBackAngle.toInt().toString());
    if (log) _addLog('Задняя дверь: ${doorBackAngle.toInt()}°');
    notifyListeners();
  }

  void openAllServos() {
    setRoofLeftAngle(maxRoofAngleLimit, log: false);
    setRoofRightAngle(maxRoofAngleLimit, log: false);
    setDoorFrontAngle(maxDoorAngleLimit, log: false);
    setDoorBackAngle(maxDoorAngleLimit, log: false);
    _addLog('Открыты все окна и двери');
  }

  void closeAllServos() {
    setRoofLeftAngle(0, log: false);
    setRoofRightAngle(0, log: false);
    setDoorFrontAngle(0, log: false);
    setDoorBackAngle(0, log: false);
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
      default:
        return 0.0;
    }
  }

  void saveOrUpdateRule(AutomationRule rule) {
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    _syncRulesToEsp();
    notifyListeners();
  }

  void toggleRule(String id, bool enabled) {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      rules[idx].isEnabled = enabled;
      _syncRulesToEsp();
      notifyListeners();
    }
  }

  void deleteRule(String id) {
    rules.removeWhere((r) => r.id == id);
    _syncRulesToEsp();
    notifyListeners();
  }

  void _syncRulesToEsp() {
    final payload = jsonEncode(rules.map((r) => r.toJson()).toList());
    _publish('greenhouse/scenarios/sync', payload, retain: true);
  }

  void executeRuleActions(AutomationRule rule, {bool manualTest = false}) {
    for (final act in rule.actions) {
      if (act.target == 'roofAngle') {
        setRoofLeftAngle(act.value, log: false);
        setRoofRightAngle(act.value, log: false);
      } else if (act.target == 'doorAngle') {
        setDoorFrontAngle(act.value, log: false);
        setDoorBackAngle(act.value, log: false);
      } else if (act.target == 'allServos') {
        setRoofLeftAngle(act.value, log: false);
        setRoofRightAngle(act.value, log: false);
        setDoorFrontAngle(act.value, log: false);
        setDoorBackAngle(act.value, log: false);
      } else if (act.target == 'pump') {
        _publish('greenhouse/pump/set', act.value >= 1 ? '1' : '0', retain: true);
      } else if (act.target == 'phytoLight') {
        _publish('greenhouse/light/phyto/set', act.value >= 1 ? '1' : '0', retain: true);
      } else if (act.target == 'whiteLight') {
        _publish('greenhouse/light/white/set', act.value >= 1 ? '1' : '0', retain: true);
      }
    }
    _addLog('Выполнен сценарий: ${rule.name}');
  }

  bool unlockDeveloperMode(String pin) {
    if (pin.trim() == _adminPin) {
      isDeveloperUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
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
    _client?.disconnect();
    super.dispose();
  }
}