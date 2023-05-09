enum GatewayRequestType { reloadConfig, sendDeviceInfo, restart }

class GatewayRequestPayload {
  final GatewayRequestType reqType;
  String? sharedConfigID;

  GatewayRequestPayload({
    required this.reqType,
    this.sharedConfigID});

  static GatewayRequestPayload fromJson(Map<String, dynamic> json) {
    return GatewayRequestPayload(
        reqType: GatewayRequestType.values.byName(json['reqType']),
        sharedConfigID: json['sharedConfigID']);
  }

  Map<String, dynamic> toJson() =>
      {'reqType': reqType.name, 'sharedConfigID': sharedConfigID};
}
