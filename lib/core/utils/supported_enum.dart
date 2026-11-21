import 'package:hive/hive.dart';
import 'package:purevideo/core/services/captcha_service.dart';

enum SupportedService { filman, obejrzyjto, ekino, docchi, bajeczki }

class SupportedServiceAdapter extends TypeAdapter<SupportedService> {
  @override
  final int typeId = 8;

  @override
  SupportedService read(BinaryReader reader) {
    final idx = reader.readInt();
    if (idx >= 0 && idx < SupportedService.values.length) {
      return SupportedService.values[idx];
    }
    return SupportedService.filman;
  }

  @override
  void write(BinaryWriter writer, SupportedService obj) {
    writer.writeInt(obj.index);
  }
}

enum InputType { text, password, recaptcha }

extension SupportedServiceExtension on SupportedService {
  String get displayName => switch (this) {
        SupportedService.filman => 'Filman.cc',
        SupportedService.obejrzyjto => 'Obejrzyj.to',
        SupportedService.ekino => 'Ekino.ws',
        SupportedService.docchi => 'Docchi.pl (Anime)',
        SupportedService.bajeczki => 'Bajeczki.org',
      };

  String get image => switch (this) {
        SupportedService.filman =>
          'https://filman.cc/public/dist/images/logo.png',
        SupportedService.obejrzyjto =>
          'https://obejrzyj.to/storage/branding_media/ead386d3-fca5-4082-8754-2a0992ae8c22.png',
        SupportedService.ekino => 'https://ekino.ws/views/img/logo.png',
        SupportedService.docchi => 'https://docchi.pl/logo192.png',
        SupportedService.bajeczki =>
          'https://bajeczki.org/wp-content/uploads/2026/06/logo.png',
      };

  List<Map<String, InputType>> get loginRequiredFields => switch (this) {
        SupportedService.filman => [
            {'login': InputType.text},
            {'password': InputType.password},
          ],
        SupportedService.obejrzyjto => [
            {'email': InputType.text},
            {'password': InputType.password},
          ],
        SupportedService.ekino => [
            {'login': InputType.text},
            {'password': InputType.password},
          ],
        SupportedService.docchi => const [],
        SupportedService.bajeczki => const [],
      };

  bool get canBeAnonymous => switch (this) {
        SupportedService.filman => false,
        SupportedService.obejrzyjto => true,
        SupportedService.ekino => true,
        SupportedService.docchi => true,
        SupportedService.bajeczki => true,
      };

  String get baseUrl => switch (this) {
        SupportedService.filman => 'https://filman.cc',
        SupportedService.obejrzyjto => 'https://obejrzyj.to',
        SupportedService.ekino => 'https://ekino.ws',
        SupportedService.docchi => 'https://docchi.pl',
        SupportedService.bajeczki => 'https://bajeczki.org',
      };

  CaptchaConfig get loginCaptchaConfig => switch (this) {
        SupportedService.filman => CaptchaConfig(
            service: CaptchaServiceProvider.recaptcha,
            siteKey: '6LcQs24iAAAAALFibpEQwpQZiyhOCn-zdc-eFout',
            isInvisible: false,
          ),
        SupportedService.obejrzyjto => CaptchaConfig(
            service: CaptchaServiceProvider.recaptcha,
            siteKey: '',
            isInvisible: false,
          ),
        SupportedService.ekino => CaptchaConfig(
            service: CaptchaServiceProvider.recaptcha,
            siteKey: '6Lfk0J0aAAAAACxgxuV0XOQsGUq3w-CX3TZUULuC',
            isInvisible: true,
          ),
        SupportedService.docchi => CaptchaConfig(
            service: CaptchaServiceProvider.recaptcha,
            siteKey: '',
            isInvisible: false,
          ),
        SupportedService.bajeczki => CaptchaConfig(
            service: CaptchaServiceProvider.recaptcha,
            siteKey: '',
            isInvisible: false,
          ),
      };
}
