import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:at_lorawan/lorawan_rpcs.dart';

class LoraWanManager implements AtRpcCallbacks {
  static const String defaultNameSpace = 'lorawan_demo';
  static const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

  late final AtSignLogger logger;
  final AtClient atClient;
  final String configsDir;

  Map<int, GatewayRequest> awaitingResponse = {};
  Map<int, GatewayResponses> responses = {};

  late AtRpc rpc;

  LoraWanManager({required this.atClient, required this.configsDir}) {
    logger = AtSignLogger(runtimeType.toString());
  }

  final configShareOptions = PutRequestOptions()..useRemoteAtServer = true;

  Future<void> init() async {
    await startRpcListener();
  }

  /// In the [configsDir]
  /// - Iterate through sub-directories
  /// - Each sub-directory name is the atSign of a gateway
  /// - Each sub-directory contains a single file called 'config'
  /// - And each sub-directory contains a file .lastSentHash which has the hash
  ///   of the config that was last 'sent' to the gateway
  /// - Compute hash of the config file
  /// - If computed hash is not same as the .lastSentHash, then we've found a change
  Future<List<String>> scanForChanges() async {
    awaitingResponse = {};
    responses = {};
    List<String> changed = [];

    final dir = Directory(configsDir);
    final List<FileSystemEntity> entities = await dir.list().toList();
    for (var subDir in entities) {
      logger.finer('Scanning ${subDir.path}');
      if (subDir is! Directory) {
        continue;
      }

      var gatewayAtSign = p.basename(subDir.path);
      if (gatewayAtSign.startsWith('@')) {
        File configFile = getConfigFile(gatewayAtSign);
        if (!configFile.existsSync()) {
          logger.warning('No "config" file found in ${subDir.path} - ignoring');
          continue;
        }
        String latestDigest = getFileDigest(configFile);

        String? lastSentDigest;
        File hashFile = getLastConfigHashFile(gatewayAtSign);
        if (hashFile.existsSync()) {
          lastSentDigest = hashFile.readAsStringSync();
        }

        logger.finer(
            'HashCode of config file is $latestDigest - last sent hashCode is $lastSentDigest');
        if (latestDigest != lastSentDigest) {
          changed.add(gatewayAtSign);
        }
      }
    }

    return changed;
  }

  File getConfigFile(String gatewayAtSign) {
    return File(p.join(configsDir, gatewayAtSign, 'config'));
  }

  File getLastConfigHashFile(String gatewayAtSign) {
    return File(p.join(configsDir, gatewayAtSign, '.lastHashSent'));
  }

  String getFileDigest(File file) {
    return sha256.convert(file.readAsBytesSync()).toString();
  }

  /// - Calculate hashCode of the config
  /// - Store the config to remoteSecondary
  /// - Send request to the gateway to reload its config
  /// - Add to [awaitingResponse] and create new entry in [responses]
  /// - In [handleResponse], once the gateway has responded positively, we will
  ///   write the hash to .lastSentHash
  Future<void> uploadConfigForGateway(String gatewayAtSign) async {
    int reqId = DateTime.now().microsecondsSinceEpoch;
    AtKey sharedConfigID =
        await shareConfigWithGatewayAtSign(gatewayAtSign, reqId);

    GatewayRequestPayload payload = GatewayRequestPayload(
        reqType: GatewayRequestType.reloadConfig,
        sharedConfigID: sharedConfigID.toString());
    var req = AtRpcReq(reqId: reqId, payload: payload.toJson());
    await rpc.sendRequest(toAtSign: gatewayAtSign, request: req);

    awaitingResponse[req.reqId] = GatewayRequest(gatewayAtSign, req);
    responses[req.reqId] = GatewayResponses(gatewayAtSign, []);

    return;
  }

  static const Duration defaultTimeout = Duration(seconds: 30);

  Future<List<String>> waitThenGetReport(
      {Duration timeout = defaultTimeout}) async {
    DateTime deadline = DateTime.now().add(timeout);

    while (awaitingResponse.isNotEmpty && deadline.isAfter(DateTime.now())) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    return getReport();
  }

  List<String> getReport() {
    List<String> reports = [];
    // Now build a report for the caller
    // Only things left in 'awaitingResponse' should be timed out
    // Everything else will be in 'responses'
    for (var timedOut in awaitingResponse.values) {
      reports.add('${timedOut.gatewayAtSign} : NO RESPONSE');
    }
    for (var responded in responses.values) {
      if (responded.responses.isNotEmpty) {
        reports.add('${responded.gatewayAtSign}'
            ' : ${responded.responses.last.respType.name.toUpperCase()}'
            ' : ${responded.responses.last.message}'
            ' : ${responded.responses.last.payload}');
      }
    }
    return reports;
  }

  @visibleForTesting
  Future<void> startRpcListener() async {
    rpc = AtRpc(
        atClient: atClient,
        baseNameSpace: atClient.getPreferences()!.namespace!,
        domainNameSpace: 'control_plane',
        callbacks: this,
        allowList: {});

    rpc.start();
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    logger.warning(
        'Received unexpected request from $fromAtSign : ${jsonPrettyPrinter.convert(request.toJson())}');
    AtRpcResp response =
        AtRpcResp.nack(request: request, message: 'Not expecting requests');
    return response;
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    logger.info(
        'Received response ${jsonPrettyPrinter.convert(response.toJson())}');
    if (awaitingResponse.containsKey(response.reqId)) {
      var gatewayResponses = responses[response.reqId]!;
      gatewayResponses.responses.add(response);
      switch (response.respType) {
        case AtRpcRespType.ack:
          break;
        case AtRpcRespType.nack:
          awaitingResponse.remove(response.reqId);
          break;
        case AtRpcRespType.error:
          awaitingResponse.remove(response.reqId);
          break;
        case AtRpcRespType.success:
          awaitingResponse.remove(response.reqId);

          // Update the .lastHashSent
          File configFile = getConfigFile(gatewayResponses.gatewayAtSign);
          String latestDigest = getFileDigest(configFile);
          File hashFile = getLastConfigHashFile(gatewayResponses.gatewayAtSign);
          hashFile.writeAsStringSync(latestDigest);
          break;
      }
    }
  }

  Future<AtKey> shareConfigWithGatewayAtSign(
      String gatewayAtSign, int reqId) async {
    File configFile = getConfigFile(gatewayAtSign);
    String configBase64 = base64Encode(configFile.readAsBytesSync());

    // Store the config to remoteSecondary for retrieval by the gateway
    String configRecordIDName = '$reqId.configs';
    Metadata metadata = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..namespaceAware = true
      ..ttr = -1 // cacheable by recipient
      ..ttl = 60 * 60 * 1000; // 1 hour
    var configRecordID = AtKey()
      ..key = configRecordIDName
      ..sharedBy = atClient.getCurrentAtSign()
      ..sharedWith = gatewayAtSign
      ..namespace = atClient.getPreferences()!.namespace!
      ..metadata = metadata;

    logger.info('Putting $configRecordID');
    await atClient.put(configRecordID, configBase64,
        putRequestOptions: configShareOptions);

    return configRecordID;
  }
}

class GatewayRequest {
  final String gatewayAtSign;
  final AtRpcReq request;
  bool sent = false;

  GatewayRequest(this.gatewayAtSign, this.request);
}

class GatewayResponses {
  final String gatewayAtSign;
  final List<AtRpcResp> responses;

  GatewayResponses(this.gatewayAtSign, this.responses);
}
