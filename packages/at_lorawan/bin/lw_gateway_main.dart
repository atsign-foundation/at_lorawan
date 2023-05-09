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

  ArgResults parsedArgs = argsParser.parse(args);

  if (parsedArgs['help'] == true) {
    print(argsParser.usage);
    exit(0);
  }

  try {
    gateway = LoraWanGateway(
        atSign: parsedArgs['atsign'],
        atKeysFilePath: parsedArgs['key-file'],
        nameSpace: parsedArgs['namespace'] ?? LoraWanGateway.defaultNameSpace,
        rootDomain: parsedArgs['root-domain'],
        homeDir: getHomeDirectory(),
        storageDir: parsedArgs['storage-dir'],
        verbose: parsedArgs['verbose'] == true,
        managerAtsigns: parsedArgs['manager-atsigns'].toString().split(',').toSet(),
        cramSecret: parsedArgs['cram-secret'],
        syncDisabled: parsedArgs['never-sync']);
  } catch (e) {
    print(argsParser.usage);
    print(e);
    exit(1);
  }

  try {
    await gateway.init();

    await gateway.listenForRequests();
  } catch (error, stackTrace) {
    AtSignLogger logger = AtSignLogger('LoraWanGateway.main');
    logger.severe('Uncaught error: $error');
    logger.severe(stackTrace.toString());
  }
}
