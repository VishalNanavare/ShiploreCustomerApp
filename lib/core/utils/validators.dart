/// Client-side input validation (defense-in-depth; the server validates too).
class Validators {
  Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^\+?[0-9]{10,15}$');
  static final _pincode = RegExp(r'^[0-9]{6}$');

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // optional
    return _email.hasMatch(s) ? null : 'Enter a valid email';
  }

  static String? phone(String? v, {bool required = false}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'Phone is required' : null;
    return _phone.hasMatch(s) ? null : 'Enter a valid phone number';
  }

  static String? identifier(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your email or phone';
    if (_email.hasMatch(s) || _phone.hasMatch(s)) return null;
    return 'Enter a valid email or phone';
  }

  static String? pincode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Pincode is required';
    return _pincode.hasMatch(s) ? null : 'Pincode must be 6 digits';
  }

  static String? otp(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 4) return 'Enter the code';
    return null;
  }

  static String? required(String? v, [String field = 'This field']) {
    return (v ?? '').trim().isEmpty ? '$field is required' : null;
  }
}
