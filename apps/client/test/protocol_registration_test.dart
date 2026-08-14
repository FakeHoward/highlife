import 'package:flutter_test/flutter_test.dart';
import 'package:highlife_client/domain/protocol_registration.dart';

void main() {
  test('Windows protocol commands point the scheme at this executable', () {
    final commands = windowsProtocolRegCommands(
      scheme: 'highlife',
      executable: r'C:\HighLife\highlife_client.exe',
    );
    expect(commands, hasLength(3));
    expect(commands[0][1], 'Software\\Classes\\highlife');
    expect(commands.last[4], contains('highlife_client.exe'));
    expect(commands.last[4], contains('%1'));
  });

  test('Linux desktop entry claims the highlife scheme', () {
    final body = linuxDesktopEntry(
      name: 'HighLife',
      executable: '/opt/highlife/highlife_client',
      applicationId: highLifeLinuxApplicationId,
      scheme: highLifeUrlScheme,
    );
    expect(body, contains('x-scheme-handler/highlife'));
    expect(body, contains('/opt/highlife/highlife_client'));
    expect(body, contains(highLifeLinuxApplicationId));
  });
}
