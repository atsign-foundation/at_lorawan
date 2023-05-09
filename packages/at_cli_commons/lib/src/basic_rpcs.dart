// RequestListener
//     Listener will send an ACK if the request payload looks reasonable, NACK otherwise
//     Required: atClient, namespace, requestHandler, responseAckHandler
//     Optional: rpcs sub-namespace - defaults to '__rpcs'
//   Listen for request
//   Send response, responseAckHandler for response ACK/NACK

// Listen for responses
//   Listener will send an ACK if the response payload looks reasonable, NACK otherwise
//   Required: atClient, namespace, responseHandler, requestAckHandler
//   Optional: rpcs sub-namespace - defaults to '__rpcs'

// In general going to listen for requests and responses

// Send request, callback for ack/nack/response
// Listen for requests, ack/nack sent automatically, need to

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_utils.dart';

class AtRpcReq {
  final int reqId;
  final Map<String, dynamic> payload;

  AtRpcReq({required this.reqId, required this.payload});


  static AtRpcReq create(Map<String, dynamic>payload) {
    return AtRpcReq(reqId: DateTime.now().microsecondsSinceEpoch, payload: payload);
  }

  Map<String, dynamic> toJson() =>
      {'reqId': reqId, 'payload': payload};

  static AtRpcReq fromJson(Map<String, dynamic> json) {
    return AtRpcReq(
        reqId: json['reqId'],
        payload: json['payload']);
  }
}

enum AtRpcRespType { ack, nack, success, error }

class AtRpcResp {
  final int reqId;
  final AtRpcRespType respType;
  final Map<String, dynamic> payload;
  final String? message;

  AtRpcResp({required this.reqId, required this.respType, required this.payload, this.message});

  static AtRpcResp ack({required AtRpcReq request}) {
    return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.ack, payload: {});
  }
  static AtRpcResp nack({required AtRpcReq request, String? message, Map<String, dynamic>? payload}) {
    return AtRpcResp(reqId: request.reqId, respType: AtRpcRespType.nack, payload: payload ?? {}, message: message);
  }
  static AtRpcResp respond(
  {required AtRpcReq request, required Map<String, dynamic> payload, String? message}) {
    return AtRpcResp(
        reqId: request.reqId,
        respType: AtRpcRespType.success,
        payload: payload,
        message: message);
  }

  static AtRpcResp fromJson(Map<String, dynamic> json) {
    return AtRpcResp(
        reqId: json['reqId'],
        respType: AtRpcRespType.values.byName(json['respType']),
        payload: json['payload']);
  }

  Map<String, dynamic> toJson() =>
      {'reqId': reqId, 'respType': respType.name, 'payload': payload};
}

abstract class AtRpcCallbacks {
  Future<AtRpcResp> handleRequest (AtRpcReq request);
  Future<void> handleResponse (AtRpcResp response);
}

class AtRpc {
  static final AtSignLogger logger = AtSignLogger('AtRpc');

  final AtClient atClient;
  final String baseNameSpace;
  final String rpcsNameSpace;
  final String domainNameSpace;
  final Set<String> allowList;
  final AtRpcCallbacks callbacks;


  AtRpc({
    required this.atClient,
    required this.baseNameSpace,
    this.rpcsNameSpace = '__rpcs',
    required this.domainNameSpace,
    required this.callbacks,
    required this.allowList
  });

  Future<void> start() async {
    logger.info('allowList is $allowList');
    var regex = 'request.\\d+.$domainNameSpace.$rpcsNameSpace.$baseNameSpace@';
    logger.info('Subscribing to $regex');
    atClient.notificationService
        .subscribe(
            regex: regex,
            shouldDecrypt: true)
        .listen(_handleRequestNotification,
            onError: (e) => logger.severe('Notification Failed: $e'),
            onDone: () => logger.info('RPC request listener stopped'));

    regex = '(success|error|ack|nack).\\d+.$domainNameSpace.$rpcsNameSpace.$baseNameSpace@';
    logger.info('Subscribing to $regex');
    atClient.notificationService
        .subscribe(
            regex: regex,
            shouldDecrypt: true)
        .listen(_handleResponseNotification,
            onError: (e) => logger.severe('Notification Failed: $e'),
            onDone: () => logger.info('RPC response listener stopped'));
  }

  Future<void> sendRequest({required String toAtSign, required AtRpcReq request}) async {
    try {
      toAtSign = AtUtils.fixAtSign(toAtSign);
      String requestRecordIDName =
          'request.${request.reqId}.$domainNameSpace.$rpcsNameSpace';
      var requestRecordID = AtKey()
        ..key = requestRecordIDName
        ..sharedBy = atClient.getCurrentAtSign()
        ..sharedWith = AtUtils.fixAtSign(toAtSign)
        ..namespace = baseNameSpace
        ..metadata = defaultMetaData;

      allowList.add(toAtSign); // Need to be able to receive responses from the atSigns we're sending requests to

      var requestJson = jsonEncode(request.toJson());
      logger.info('Sending notification ${requestRecordID.toString()} with payload $requestJson');
      await atClient.notificationService.notify(
          NotificationParams.forUpdate(requestRecordID,
              value: requestJson),
          checkForFinalDeliveryStatus: false,
          waitForFinalDeliveryStatus: false);
      logger.info('Notification ${requestRecordID.toString()} sent');
    } catch (e, st) {
      logger.warning('Exception $e sending request $request');
      logger.warning(st);
    }
  }

  Future<void> _handleRequestNotification(AtNotification notification) async {
    if (! allowList.contains(notification.from)) {
      logger.info('Ignoring notification from non-allowed atSign ${notification.from} : $notification');
      return;
    }

    // request key should be @gateway:request.<id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@manager
    // strip off the prefix `@gateway:request.`
    String requestKey = notification.key.replaceFirst('${notification.to}:request.', '');
    // We should now have something like <id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@manager
    // To leave us just with the <id>, strip off the suffix `.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@manager`
    requestKey = requestKey.replaceAll('.$domainNameSpace.$rpcsNameSpace.$baseNameSpace${notification.from}', '');

    int requestId = -1;
    try {
      requestId = int.parse(requestKey);
    } catch (e) {
      logger.warning('Failed to get request ID from ${notification.key} - $e');
      return;
    }

    // print('Received request with id ${notification.key} and value ${chalk.brightGreen.bold(notification.value)}');
    late AtRpcReq request;

    try {
      request = AtRpcReq.fromJson(jsonDecode(notification.value!));
    } catch (e, st) {
      var message = 'Failed to deserialize AtRpcReq from ${notification.value}: $e';
      logger.warning(message);
      logger.warning(st);
      // send NACK
      await _sendResponse(notification, request, AtRpcResp.nack(request: request, message: message));
      return;
    }

    if (request.reqId != requestId) {
      var message = 'Ignoring request: requestID from the notification key $requestId'
          ' does not match requestID from notification payload ${request.reqId}';
      logger.warning(message);
      // send NACK
      await _sendResponse(notification, request, AtRpcResp.nack(request:request, message:message));
      return;
    }

    // send ACK
    await _sendResponse(notification, request, AtRpcResp.ack(request:request));

    late AtRpcResp response;
    try {
      response = await callbacks.handleRequest(request);
      await _sendResponse(notification, request, response);
    } catch (e, st) {
      var message = 'Exception $e from callbacks.handleRequest for request $request';
      logger.warning(message);
      logger.warning(st);
      await _sendResponse(notification, request, AtRpcResp.nack(request: request, message:message));
    }

  }

  Future<void> _handleResponseNotification(AtNotification notification) async {
    if (! allowList.contains(notification.from)) {
      logger.info('Ignoring notification from non-allowed atSign ${notification.from} : $notification');
      return;
    }

    // request key should be @manager:response.<id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@gateway
    // strip off the prefix `@manager:response.`
    String requestKey = notification.key
        .replaceFirst('${notification.to}:success.', '')
        .replaceFirst('${notification.to}:error.', '')
        .replaceFirst('${notification.to}:ack.', '')
        .replaceFirst('${notification.to}:nack.', '');
    // We should now have something like <id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@manager
    // To leave us just with the <id>, strip off the suffix `.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@manager`
    requestKey = requestKey.replaceAll('.$domainNameSpace.$rpcsNameSpace.$baseNameSpace${notification.from}', '');

    int requestId = -1;
    try {
      requestId = int.parse(requestKey);
    } catch (e) {
      logger.warning('Failed to get request ID from ${notification.key} - $e');
      return;
    }

    late AtRpcResp response;

    try {
      response = AtRpcResp.fromJson(jsonDecode(notification.value!));
    } catch (e, st) {
      var message = 'Failed to deserialize AtRpcResp from ${notification.value}: $e';
      logger.warning(message);
      logger.warning(st);
      return;
    }

    if (response.reqId != requestId) {
      var message = 'Ignoring response: requestID from the notification key $requestId'
          ' does not match requestID from the response notification payload ${response.reqId}';
      logger.warning(message);
      return;
    }

    try {
      await callbacks.handleResponse(response);
    } catch (e, st) {
      logger.warning('Exception $e from callbacks.handleResponse for response $response');
      logger.warning(st);
    }
  }

  Future<void> _sendResponse(AtNotification notification, AtRpcReq request, AtRpcResp response) async {
    try {
      String responseAtID =
          '${response.respType.name}.${request.reqId}.$domainNameSpace.$rpcsNameSpace';
      var responseAtKey = AtKey()
        ..key = responseAtID
        ..sharedBy = atClient.getCurrentAtSign()
        ..sharedWith = notification.from
        ..namespace = baseNameSpace
        ..metadata = defaultMetaData;

      logger.info("Sending notification $responseAtKey with payload ${response.toJson()}");
      await atClient.notificationService.notify(
          NotificationParams.forUpdate(responseAtKey,
              value: jsonEncode(response.toJson())),
          checkForFinalDeliveryStatus: false,
          waitForFinalDeliveryStatus: false);
    } catch (e, st) {
      logger.warning('Exception $e sending response $response');
      logger.warning(st);
    }
  }

  Metadata defaultMetaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true
    ..ttr = -1
    ..ttl = 60 * 60 * 1000; // 1 hour
}
