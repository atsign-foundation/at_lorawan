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
    ..addOption('configs-dir', mandatory: true,
        help: 'directory with sub-directories for each managed gateway');

  ArgResults parsedArgs = argsParser.parse(args);

  if (parsedArgs['help'] == true) {
    print(argsParser.usage);
    exit(0);
  }

  try {
    manager = LoraWanManager(
        atSign: parsedArgs['atsign'],
        configsDir: parsedArgs['configs-dir'],
        atKeysFilePath: parsedArgs['key-file'],
        nameSpace: parsedArgs['namespace'] ?? LoraWanManager.defaultNameSpace,
        rootDomain: parsedArgs['root-domain'],
        homeDir: getHomeDirectory(),
        storageDir: parsedArgs['storage-dir'],
        verbose: parsedArgs['verbose'] == true,
        cramSecret: parsedArgs['cram-secret'],
        syncDisabled: parsedArgs['never-sync']);
  } catch (e) {
    print(argsParser.usage);
    print(e);
    exit(1);
  }

  try {
    await manager.init();

    logger.info('Scanning for changes in ${manager.configsDir}');
    var changeList = await manager.scanForChanges();
    logger.info('Changed configs: $changeList');

    for (String gatewayAtSign in changeList) {
      logger.info('Uploading config for $gatewayAtSign');
      await manager.uploadConfigForGateway(gatewayAtSign);
    }

    await manager.waitThenGetReport();
  } catch (error, stackTrace) {
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
  }
}
