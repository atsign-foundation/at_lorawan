import 'dart:convert';
import 'dart:io';

// external imports
import 'package:at_client/at_client.dart';

// at_lorawan imports
import 'package:at_lorawan/lorawan_rpcs.dart';
import 'package:at_utils/at_logger.dart';

class LoraWanGateway implements AtRpcCallbacks {
  static const String defaultNameSpace = 'lorawan_demo';
  static const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

  late final AtSignLogger logger;

  final AtClient atClient;
  final Set<String> managerAtsigns;

  bool stopRequested = false;

  LoraWanGateway({required this.atClient, required this.managerAtsigns}) {
    logger = AtSignLogger(runtimeType.toString());
  }

  Future<void> listenForRequests() async {
    logger.info('Listening for requests');

    AtRpc rpc = AtRpc(
        atClient: atClient,
        baseNameSpace: atClient.getPreferences()!.namespace!,
        domainNameSpace: 'control_plane',
        callbacks: this,
        allowList: managerAtsigns);

    rpc.start();

    while (!stopRequested) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    logger.info('Received request from $fromAtSign: ${jsonPrettyPrinter.convert(request.toJson())}');

    GatewayRequestPayload payload = GatewayRequestPayload.fromJson(request.payload);

    AtKey sharedConfigRecordID = AtKey.fromString(payload.sharedConfigID!);

    // Get the shared config and write it to a file
    String configBase64 = (await atClient.get(sharedConfigRecordID)).value.toString();
    File configFile = File(sharedConfigRecordID.toString());
    configFile.writeAsBytesSync(base64Decode(configBase64));

    // Execute the shell script
    ProcessResult reloadResult = await Process.run('./reloadConfig', [configFile.path]);

    // Response type should be 'error' if there was an error (i.e. non-zero exit code)
    final AtRpcRespType respType = reloadResult.exitCode == 0
        ? AtRpcRespType.success
        : AtRpcRespType.error;
    AtRpcResp response = AtRpcResp(
        reqId: request.reqId,
        respType: respType,
        message:
            'Failed to reloadConfig with exit code ${reloadResult.exitCode}',
        payload: {
          'exitCode': reloadResult.exitCode,
          'stdout': reloadResult.stdout,
          'stderr': reloadResult.stderr
        });

    logger.info('Sending response ${jsonPrettyPrinter.convert(response.toJson())}');
    return response;
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    logger.info(
        'Received response ${jsonPrettyPrinter.convert(response.toJson())}');
  }
}
