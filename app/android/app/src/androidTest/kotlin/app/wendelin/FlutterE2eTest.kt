package app.wendelin

import androidx.test.rule.ActivityTestRule
import dev.flutter.plugins.integration_test.FlutterTestRunner
import org.junit.Rule
import org.junit.runner.RunWith

/**
 * Runs a Flutter device test (`app/integration_test/…`) through Android instrumentation (WP19).
 *
 * Needed for tests that start a second Flutter engine of the app, e.g. the assistant overlay: the
 * engine looks up its Dart entrypoint (`assistantMain`) in the root library. With
 * `flutter test` the root is a generated listener, with
 * `flutter build apk -t integration_test/<test>.dart` it is the test file, which then defines the
 * entrypoint. `tool/e2e_android.sh` builds and runs this for such tests.
 */
@RunWith(FlutterTestRunner::class)
class FlutterE2eTest {
    @Rule
    @JvmField
    val rule = ActivityTestRule(MainActivity::class.java, true, false)
}
