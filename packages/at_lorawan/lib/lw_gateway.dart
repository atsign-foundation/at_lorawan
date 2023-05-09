import 'dart:convert';
import 'dart:io';

// external imports
import 'package:at_client/at_client.dart';
import 'package:chalkdart/chalk.dart';

// at_lorawan imports
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_lorawan/lorawan_rpcs.dart';

class LoraWanGateway extends CLIBase implements AtRpcCallbacks {
  static const String defaultNameSpace = 'lorawan_demo';
  static const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

  final Set<String> managerAtsigns;

  bool stopRequested = false;

  LoraWanGateway(
      {required super.atSign,
        required super.nameSpace,
        required super.rootDomain,
        super.atKeysFilePath,
        super.homeDir,
        super.storageDir,
        super.downloadDir,
        super.verbose,
        super.cramSecret,
        super.syncDisabled,
        required this.managerAtsigns});

  @override
  Future<void> init() async {
    await super.init();
  }

  Future<void> listenForRequests() async {
    _writeListening();

    AtRpc rpc = AtRpc(
        atClient: atClient,
        baseNameSpace: nameSpace,
        domainNameSpace: 'control_plane',
        callbacks: this,
        allowList: managerAtsigns);

    await rpc.start();

    while (!stopRequested) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request) async {
    stdout.writeln(chalk.brightGreen(
        'Received request ${jsonPrettyPrinter.convert(request.toJson())}'));

    GatewayRequestPayload payload = GatewayRequestPayload.fromJson(request.payload);

    AtKey sharedConfigRecordID = AtKey.fromString(payload.sharedConfigID!);

    // Get the shared config and write it to a file
    String configBase64 = (await atClient.get(sharedConfigRecordID)).value.toString();
    File configFile = File(sharedConfigRecordID.toString());
    configFile.writeAsBytesSync(base64Decode(configBase64));

    // Execute the shell script
    ProcessResult reloadResult = await Process.run('reloadConfig', [configFile.path]);

    // Response type should be 'NACK' if there was an error (i.e. non-zero exit code)
    final AtRpcRespType respType = reloadResult.exitCode == 0
        ? AtRpcRespType.response
        : AtRpcRespType.nack;
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

    _writeListening();

    return response;
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    stdout.writeln(chalk.brightGreen(
        'Received response ${jsonPrettyPrinter.convert(response.toJson())}'));
  }

  void _writeListening() {
    stdout.write(chalk.brightBlue.bold('Listening ... '));
  }
}
