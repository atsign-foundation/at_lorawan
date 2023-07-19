import 'dart:io';

// atPlatform packages
import 'package:at_lorawan/lw_manager.dart';
import 'package:at_utils/at_logger.dart';

// external packages
import 'package:args/args.dart';

// Local Packages
import 'package:at_cli_commons/at_cli_commons.dart';

void main(List<String> args) async {
  AtSignLogger logger = AtSignLogger('LoraWanGateway.main');

  late LoraWanManager manager;

  ArgParser argsParser = CLIBase.argsParser
    ..addOption('configs-dir',
        mandatory: true,
        help: 'directory with sub-directories for each managed gateway');

  try {
    CLIBase cliBase = await CLIBase.fromCommandLineArgs(args, parser:argsParser);
    manager = LoraWanManager(
      atClient: cliBase.atClient,
      configsDir: argsParser.parse(args)['configs-dir'],
    );
  } catch (e) {
    print(argsParser.usage);
    print(e);
    exit(1);
  }

  try {
    await manager.init();

    while (true) {
      logger.info('Scanning for changes in ${manager.configsDir}');
      var changeList = await manager.scanForChanges();

      if (changeList.isEmpty) {
        logger.info('No changed configs');
      } else {
        logger.info('Changed configs: $changeList');
        for (String gatewayAtSign in changeList) {
          logger.info('Uploading config for $gatewayAtSign');
          await manager.uploadConfigForGateway(gatewayAtSign);
        }

        var timeout = Duration(seconds: 10);
        logger.info(
            'Waiting for ${timeout.inSeconds} seconds for'
                ' responses from all gateways');
        var report = await manager.waitThenGetReport(timeout: timeout);
        logger.info('Report:\n\t${report.join('\n\t')}');
      }
      var sleep = Duration(seconds:30);
      logger.info('Sleeping for ${sleep.inSeconds} seconds');
      await Future.delayed(sleep);
    }
  } catch (error, stackTrace) {
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
    exit(1);
  }
}
