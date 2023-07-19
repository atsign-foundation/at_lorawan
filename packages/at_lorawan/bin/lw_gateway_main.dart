import 'dart:io';

// atPlatform packages
import 'package:at_lorawan/lw_gateway.dart';
import 'package:at_utils/at_logger.dart';

// external packages
import 'package:args/args.dart';

// Local Packages
import 'package:at_cli_commons/at_cli_commons.dart';

void main(List<String> args) async {
  late LoraWanGateway gateway;

  ArgParser argsParser = CLIBase.argsParser
    ..addOption('manager-atsigns',
        abbr: 'm',
        mandatory: true,
        help:
            'Comma-separated list of atSigns which are allowed to manage this device');

  try {
    CLIBase cliBase = await CLIBase.fromCommandLineArgs(args, parser: argsParser);

    gateway = LoraWanGateway(
        atClient: cliBase.atClient,
        managerAtsigns:
        argsParser.parse(args)['manager-atsigns'].toString().split(',').toSet());
  } catch (e) {
    print(argsParser.usage);
    print(e);
    exit(1);
  }

  try {

    await gateway.listenForRequests();

  } catch (error, stackTrace) {
    AtSignLogger logger = AtSignLogger('LoraWanGateway.main');
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
  }
}
