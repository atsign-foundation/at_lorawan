<img width=250px src="https://atsign.dev/assets/img/atPlatform_logo_gray.svg?sanitize=true">

# at_lorawan
Libraries, demos, samples and examples for the LoraWan ecosystem

Open with intent - we welcome contributions - we want pull requests and to hear about issues.

## Who is this for?
Anyone who is interested in finding ways to efficiently and securely manage 
LoraWan networks and gateways at scale

## Contributing

We welcome all contributions! Feature requests, bug reports, code 
contributions, documentation contributions - all are welcome. See 
[CONTRIBUTING.md](CONTRIBUTING.md) for more information.

## What's here?
This repo contains some example software which will show how a gateway manager,
with its own atSign e.g. `@demo_gateway_manager` can manage many gateways, 
each with their own atSigns e.g. `@demo_gateway_1`, `@demo_gateway_2`, ... 
`@demo_gateway_1000` etc. Initially there are two programs:
* A `gateway` program (to on a LoraWan gateway device) which will
  * On first run, do initial atSign set-up
  * Connect and authenticate to the atServer for this gateway's atSign
  * Listen for requests from the gateway's list of authorized 'manager' 
    atSigns - in our case from the `@demo_gateway_manager` atSign only - to 
    download a new configuration to the gateway
  * Send a message to the manager atSign acknowledging receipt of the request
  * Fetch the config from the gateway's atServer
  * Send a message to the manager atSign indicating whether the download was 
    successful or not
  * Of course there are other things such a program can do, such as 
    respond to requests for telemetry, requests to update itself, restart 
    the device, etc ... 
* A `manager` program which, when run in a directory which in its 
  subdirectories contains the configurations for many gateways, will
  * Scan the subdirectory tree and find the directories which contain 
    gateway configs
  * For each gateway, identify if there have been changes since the last 
    time this `manager` program was run and, if there have been changes:
    * Share the config file (or a tar file if there isn't just one config 
      file) with the gateway's atSign
    * Send a request to the gateway's atSign that it should fetch the 
      updated config
    * Keep track of messages from gateway atSigns which (i) confirm receipt 
      of the request and (ii) confirm the download status
  * Report for each gateway
    * Whether config change had been detected in the local filesystem
    * Whether an 'update your config' request was sent to the gateway
    * Whether the gateway acknowledged receipt within N seconds or not
    * Whether the gateway successfully downloaded its new config or not
