import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows audio backend leaves SMTC ownership to Verse', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final playerSource = File(
      'third_party/just_audio_windows/windows/player.hpp',
    ).readAsStringSync();

    expect(
      pubspec,
      contains('path: third_party/just_audio_windows'),
      reason: 'The patched Windows audio backend must be reproducible.',
    );
    expect(
      playerSource,
      contains('mediaPlayer.CommandManager().IsEnabled(false);'),
      reason: 'Only Verse should publish a Windows media session.',
    );
  });

  test('Windows runner publishes the Verse application identity', () {
    final mainSource = File('windows/runner/main.cpp').readAsStringSync();
    final identitySource = File(
      'windows/runner/app_identity.cpp',
    ).readAsStringSync();
    final identityHeader = File(
      'windows/runner/app_identity.h',
    ).readAsStringSync();
    final windowSource = File(
      'windows/runner/flutter_window.cpp',
    ).readAsStringSync();
    final resources = File('windows/runner/Runner.rc').readAsStringSync();

    expect(mainSource, contains('SetCurrentProcessExplicitAppUserModelID'));
    expect(identityHeader, contains('Verse.Player'));
    expect(windowSource, contains('PKEY_AppUserModel_ID'));
    expect(
      windowSource,
      contains('PKEY_AppUserModel_RelaunchDisplayNameResource'),
    );
    expect(resources, contains('VALUE "FileDescription", "Verse"'));
    expect(resources, contains('VALUE "ProductName", "Verse"'));
    expect(identitySource, contains('FOLDERID_Programs'));
    expect(identitySource, contains('IShellLinkW'));
    expect(identitySource, contains('IPersistFile'));
    expect(identitySource, contains('PKEY_AppUserModel_ID'));
    expect(identitySource, contains('Verse.lnk'));
    expect(identitySource, contains('CheckExistingShortcut'));
    expect(identitySource, contains('ERROR_FILE_EXISTS'));
    expect(mainSource, contains('RegisterVerseAppIdentity'));
    expect(mainSource, contains('kVerseAppUserModelId'));
  });
}
