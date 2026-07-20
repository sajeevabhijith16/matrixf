# Native Google Sign-In (Credential Manager) — Implementation Plan (Modules E1–E5)

> **Why**: Replaces the Custom Tab / browser-redirect Google sign-in flow with Google's native Android Credential Manager sheet — rendered directly inside the app's own window, no browser, no separate task/activity, so there is no "return to app" problem at all (the class of issue we spent a long time debugging on the Vivo device simply cannot occur here).
> **What changes**: `google_sign_in` package (v7+, Credential-Manager-backed) gets an ID token natively on-device. That ID token is sent to Supabase's `/auth/v1/token?grant_type=id_token` endpoint to complete the session — no browser redirect anywhere in this flow.
> **What stays**: Your existing email/password sign-in, and the deep-link handling for other flows (email confirmation, password reset) are untouched.

---

## Module Map

```
E1 → Google Cloud Console: Android OAuth Client + Supabase Skip Nonce Check (manual dashboard steps, no code)
E2 → Add google_sign_in package + initialize at app startup
E3 → MatrixApi: signInWithGoogleIdToken()
E4 → Wire profile_screen.dart to the native flow
E5 → End-to-end verification
```

---
---

# MODULE E1 — Dashboard Setup (No Code)

### Step 1 — Get your app's package name (applicationId)

Open `android/app/build.gradle` (or `build.gradle.kts`), find the `applicationId` line, e.g.:
```
applicationId "com.example.matrixf"
```
Copy this exact value.

### Step 2 — Get your app's SHA-1 signing fingerprint (debug)

In your project root, run:
```bash
cd android
./gradlew signingReport
```
(On Windows: `gradlew.bat signingReport`)

Look for the `Variant: debug` section, and copy the `SHA1:` value shown there (looks like `AB:CD:12:34:...`).

> Note: this is your **debug** fingerprint, fine for development/testing. Before a real Play Store release, you'll need to repeat this with your **release** keystore's SHA-1 and add that as a second fingerprint to the same Android OAuth Client — don't worry about that now.

### Step 3 — Create an Android OAuth Client in Google Cloud Console

1. [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services → Credentials**
2. **Create Credentials → OAuth client ID**
3. Application type: **Android**
4. **Package name**: paste the `applicationId` from Step 1
5. **SHA-1 certificate fingerprint**: paste the value from Step 2
6. Click **Create**

You don't need to copy anything from this new Android client — it has no Client ID/Secret you'll paste into code. Its only purpose is telling Google "this specific signed APK is allowed to request sign-in for this project."

### Step 4 — Confirm you still have your existing Web Client ID handy

This is the **same** Web application OAuth Client ID you already created and pasted into Supabase's Google provider settings earlier (the one ending in `.apps.googleusercontent.com`). We'll reuse it — copy it somewhere handy, we'll need it in Module E2.

### Step 5 — Enable "Skip Nonce Check" in Supabase

Supabase Dashboard → **Authentication → Providers → Google** → find **Skip Nonce Check** → enable it → **Save**.

> Why: this is Supabase's own documented setting for exactly this situation — native mobile SDKs (including Google's official Android library) have known inconsistencies in how they handle the nonce field during ID-token sign-in, and Supabase explicitly recommends this toggle rather than fighting nonce coordination between two different SDKs. It does slightly weaken replay-attack protection in theory, but is a standard, sanctioned setting for this exact use case, not a hack.

### ✅ Verification — E1
- [ ] Android OAuth Client visible in Google Cloud Console credentials list, type "Android", correct package name and SHA-1
- [ ] Web Client ID copied and available for Module E2
- [ ] Skip Nonce Check toggle is ON and saved in Supabase

---
---

# MODULE E2 — Add Package + Initialize

### Step 1 — Add the dependency

In `pubspec.yaml`:
```yaml
  google_sign_in: ^7.1.0
```
Run:
```bash
flutter pub get
```

### Step 2 — Initialize once at app startup

In `lib/src/app.dart`, add the import:
```dart
import 'package:google_sign_in/google_sign_in.dart';
```

Find `_initApi()`:
```dart
  Future<void> _initApi() async {
    await api.init();
    if (api.isSignedIn) {
```

Add initialization right before it, inside `initState()`. Find:
```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApi();
    _initDeepLinks();
  }
```

Replace with:
```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGoogleSignIn();
    _initApi();
    _initDeepLinks();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
      );
    } catch (e) {
      debugPrint('GoogleSignIn init failed: $e');
    }
  }
```
Replace `'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com'` with the actual Web Client ID from Module E1 Step 4.

### Step 3 — Analyze
```bash
flutter analyze lib/src/app.dart
```
Expect zero warnings.

## ✅ Verification — E2
- [ ] App launches without crashing (this alone doesn't trigger sign-in, just confirms initialization doesn't throw)
- [ ] No `GoogleSignIn init failed` printed in the debug console on a normal launch

---
---

# MODULE E3 — MatrixApi: `signInWithGoogleIdToken`

### Step 1 — Add the method

In `lib/src/api.dart`, add this near the existing `signIn`/`signUp` methods:
```dart
  /// Completes sign-in using a native Google ID token obtained via
  /// Credential Manager (google_sign_in package). No browser/redirect
  /// involved — Skip Nonce Check must be enabled in Supabase's Google
  /// provider settings for this to work reliably (see Module E1).
  Future<void> signInWithGoogleIdToken(String idToken) async {
    final data = await _authPost('/token?grant_type=id_token', {
      'provider': 'google',
      'id_token': idToken,
    });
    session = Session.fromJson(data);
    await _saveSession();
  }
```

### Step 2 — Analyze
```bash
flutter analyze lib/src/api.dart
```
Expect zero warnings.

## ✅ Verification — E3

This can't be meaningfully tested standalone without a real ID token (which only comes from the native sign-in flow itself) — verification happens end-to-end in Module E5. Just confirm it compiles cleanly for now.

---
---

# MODULE E4 — Wire `profile_screen.dart`

### Step 1 — Add the import

```dart
import 'package:google_sign_in/google_sign_in.dart';
```

### Step 2 — Replace the Google sign-in handler

Find your current `_googleSignIn` (Custom Tab version) and the confirmation-dialog wrapper we added earlier. Replace the **entire** flow with:

```dart
Future<void> _googleSignIn(BuildContext context) async {
  final scope = MatrixScope.of(context);
  try {
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      if (context.mounted) {
        showSnack(context, 'Google sign-in did not return a token. Please try again.');
      }
      return;
    }
    await scope.api.signInWithGoogleIdToken(idToken);
    await scope.refreshProfile();
  } on GoogleSignInException catch (e) {
    if (context.mounted) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User closed the picker — no error message needed.
        return;
      }
      showSnack(context, 'Google sign-in failed: ${e.description ?? e.code}');
    }
  } catch (e) {
    if (context.mounted) {
      showSnack(context, 'Google sign-in failed: $e');
    }
  }
}
```

### Step 3 — Simplify the button (remove the confirmation dialog and fallback button from before — no longer needed, since there's no browser step to explain)

Find:
```dart
// ─── Google OAuth button ────────────────────────────────────────────
OutlinedButton.icon(
  icon: const Icon(Icons.account_circle_outlined),
  label: const Text('Continue with Google'),
  onPressed: loading ? null : () => _confirmAndGoogleSignIn(context),
),
const SizedBox(height: 8),
TextButton(
  onPressed: loading ? null : () => _checkGoogleSignInStatus(context),
  child: const Text(
    'Already signed in with Google? Tap to check',
    style: TextStyle(fontSize: 12),
  ),
),
```

Replace with:
```dart
// ─── Google OAuth button ────────────────────────────────────────────
OutlinedButton.icon(
  icon: const Icon(Icons.account_circle_outlined),
  label: const Text('Continue with Google'),
  onPressed: loading ? null : () => _googleSignIn(context),
),
```

You can also remove the now-unused `_confirmAndGoogleSignIn` and `_checkGoogleSignInStatus` methods entirely, since the whole reason they existed (explaining the manual swipe-back) no longer applies.

### Step 4 — Analyze
```bash
flutter analyze lib/src/screens/profile_screen.dart
```
Expect zero warnings. If `flutter_web_auth_2` is now unused anywhere in this file, remove that import too.

---
---

# MODULE E5 — End-to-End Verification

Full stop, full re-run (`flutter clean` first, since native config changed):
```bash
flutter clean
flutter run --dart-define=GEMINI_API_KEY=<your_key>
```

## ✅ Final Checklist

- [ ] Tap "Continue with Google" → a native Android bottom sheet appears (Credential Manager UI), NOT a browser tab, NOT a separate app
- [ ] Select an account → sheet closes immediately, you're signed in — **no manual swipe-back needed, on ANY device including the Vivo**
- [ ] Confirm your profile loads correctly
- [ ] Test cancellation: open the sheet, dismiss it without picking an account → no crash, no confusing error (per the `GoogleSignInExceptionCode.canceled` handling)
- [ ] Sign out, sign in with Google again → works repeatedly, not just once
- [ ] Confirm email/password sign-in still works unaffected
- [ ] Confirm other deep links (email confirmation, password reset) still work unaffected
- [ ] Specifically re-test on the Vivo/iQOO device that had the original issue → confirms this fully resolves it
- [ ] `flutter analyze` on the whole project → zero errors

## Optional cleanup (not required, but worth doing once E5 passes)
- Remove `flutter_web_auth_2` from `pubspec.yaml` if nothing else in the app uses it
- Remove the now-unused `CallbackActivity` intent-filter block from `AndroidManifest.xml` (the one with `android:scheme="matrixfauth"`) — no longer needed
- Keep the `<queries>` block we added — that's a generally-good Android 11+ practice unrelated to this specific flow