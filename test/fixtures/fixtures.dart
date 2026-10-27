/// Every fixture of every milestone.
///
/// New in jet_office. The fixture tests and `tool/write_fixtures.dart` read
/// this list, so a fixture added to a milestone list is checked, written and
/// validated without further wiring.
library;

import 'fixture.dart';
import 'm1_fixtures.dart';
import 'm2_fixtures.dart';
import 'm3_fixtures.dart';
import 'm4_fixtures.dart';
import 'm5_fixtures.dart';

export 'fixture.dart';

/// The fixtures of all milestones, in milestone order.
List<Fixture> allFixtures() => <Fixture>[
  ...m1Fixtures(),
  ...m2Fixtures(),
  ...m3Fixtures(),
  ...m4Fixtures(),
  ...m5Fixtures(),
];
