import 'dart:async';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/playback/application/playback_volume_memory.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global volume survives a new run without changing defaults', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    await repository.save(
      AppSettings(defaultVolume: 60, rememberVolumeGlobally: true),
    );
    PlaybackVolumeMemory newRun(double? volume) => PlaybackVolumeMemory(
      savedVolume: volume,
      saveVolume: repository.saveRememberedVolume,
    )..configure(enabled: true, defaultVolume: 60);
    var memory = newRun(await repository.loadRememberedVolume());
    expect(memory.volumeFor(60), 60);
    for (final volume in [32.5, 0.0, 100.0]) {
      memory.remember(volume, revision: memory.beginChange());
      await memory.flush();
      // A settings snapshot written after a player change cannot erase it.
      await repository.save(
        (await repository.load()).copyWith(defaultVolume: 80),
      );
      memory = newRun(
        await SqliteSettingsRepository(database).loadRememberedVolume(),
      );
      expect(memory.volumeFor(80), volume);
      expect((await repository.load()).defaultVolume, 80);
    }
    await memory.flush();
  });

  test('disabled memory keeps run inheritance and restart defaults', () async {
    final writes = <double>[];
    final memory = PlaybackVolumeMemory(
      savedVolume: 20,
      saveVolume: (volume) async => writes.add(volume),
    );
    expect(memory.volumeFor(60), 60);
    memory.remember(32.5, revision: memory.beginChange());
    expect(memory.volumeFor(60), 32.5);
    await memory.flush();
    expect(writes, isEmpty);
    memory.configure(enabled: true, defaultVolume: 60);
    await memory.flush();
    expect(writes, [32.5]);
    memory.configure(enabled: false, defaultVolume: 60);
    memory.remember(0, revision: memory.beginChange());
    await memory.flush();
    expect(writes, [32.5]);
    final restarted = PlaybackVolumeMemory(savedVolume: writes.last);
    expect(restarted.volumeFor(60), 60);
    restarted.configure(enabled: true, defaultVolume: 60);
    expect(restarted.volumeFor(60), 32.5);
    memory.configure(enabled: true, defaultVolume: 60);
    await memory.flush();
    expect(writes.last, 0);
  });

  test(
    'writes coalesce and late revisions cannot replace newer choices',
    () async {
      final gate = Completer<void>();
      final writes = <double>[];
      final memory = PlaybackVolumeMemory(
        saveVolume: (volume) async {
          writes.add(volume);
          if (writes.length == 1) await gate.future;
        },
      )..configure(enabled: true, defaultVolume: 60);
      await Future<void>.delayed(Duration.zero);
      final older = memory.beginChange();
      final newer = memory.beginChange();
      memory.remember(25, revision: newer);
      memory.remember(90, revision: older);
      expect(memory.volumeFor(60), 25);
      for (var volume = 30.0; volume <= 100; volume += 5) {
        memory.remember(volume, revision: memory.beginChange());
      }
      gate.complete();
      await memory.flush();
      expect(writes, [60, 100]);
    },
  );

  test('failed persistence is reported and later writes can recover', () async {
    final errors = <Object>[];
    var fail = true;
    var saved = 10.0;
    final memory = PlaybackVolumeMemory(
      savedVolume: saved,
      saveVolume: (volume) async {
        if (fail) throw StateError('disk unavailable');
        saved = volume;
      },
      onSaveError: (error, _) => errors.add(error),
    )..configure(enabled: true, defaultVolume: 60);
    memory.remember(25, revision: memory.beginChange());
    await expectLater(memory.flush(), throwsStateError);
    expect(errors, hasLength(1));
    expect(saved, 10);
    expect(memory.volumeFor(60), 25);
    fail = false;
    memory.remember(35, revision: memory.beginChange());
    await memory.flush();
    expect(saved, 35);
  });
}
