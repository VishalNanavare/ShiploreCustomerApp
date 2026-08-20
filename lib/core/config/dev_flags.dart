// DEV FLAGS — login OTP delivery
// ─────────────────────────────────────────────────────────────────────────────
// Two OTP paths are fully wired:
//   • Firebase phone auth — Firebase sends the SMS; the app exchanges the ID
//     token at /auth/firebase for the backend JWT. (Real auth.)
//   • Dev OTP bypass      — backend /auth/otp/request generates the code and
//     echoes it so it can be SHOWN ON THE LOGIN SCREEN. (For the iOS simulator,
//     which cannot receive a real SMS.)
//
// Runtime toggle — no code edit needed:
//   flutter run/build --dart-define=USE_FIREBASE_OTP=true   → real Firebase
//   (default / no flag)                                     → dev OTP on screen
// Release/profile builds ALWAYS use Firebase (the dev OTP is never shown there).
//
// NOTE: Firebase never exposes the OTP to the app (it is sent only via SMS), so
// the on-screen OTP only appears in the dev-OTP path. To test Firebase OTP on the
// SIMULATOR, add a test phone number in the Firebase Console
// (Authentication → Sign-in method → Phone → numbers for testing).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

/// Set via --dart-define=USE_FIREBASE_OTP=true to force real Firebase in debug too.
const bool _useFirebaseOtpOverride = bool.fromEnvironment('USE_FIREBASE_OTP', defaultValue: false);

/// True when the app uses REAL Firebase phone auth. Always on outside debug builds.
const bool kUseFirebaseOtp = !kDebugMode || _useFirebaseOtpOverride;

/// True when the app uses the backend dev-OTP bypass (code generated server-side
/// and shown on the login screen). Never true in release/profile.
const bool kDummyOtpEnabled = !kUseFirebaseOtp;
