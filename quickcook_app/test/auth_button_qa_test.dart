import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickcook_app/screens/forgot_password_screen.dart';
import 'package:quickcook_app/screens/login_screen.dart';
import 'package:quickcook_app/screens/register_screen.dart';
import 'package:quickcook_app/screens/reset_password_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 2200),
            textScaler: TextScaler.linear(0.65),
          ),
          child: child!,
        );
      },
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPrimaryButton(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _enterLoginValues(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
}

Future<void> _enterRegisterValues(WidgetTester tester, String name, String email, String password) async {
  await tester.enterText(find.byType(TextFormField).at(0), name);
  await tester.enterText(find.byType(TextFormField).at(1), email);
  await tester.enterText(find.byType(TextFormField).at(2), password);
}

Future<void> _enterResetValues(
  WidgetTester tester, {
  required String email,
  required String token,
  required String password,
  required String confirmPassword,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), token);
  await tester.enterText(find.byType(TextFormField).at(2), password);
  await tester.enterText(find.byType(TextFormField).at(3), confirmPassword);
}

void main() {
  group('Login button QA checks (14)', () {
    testWidgets('renders login action buttons', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    testWidgets('Sign In shows required field validation on empty form', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      await _tapPrimaryButton(tester, 'Sign In');
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    final invalidLoginCases = <({String name, String email, String password, String error1, String? error2})>[
      (
        name: 'empty email + short password',
        email: '',
        password: '123',
        error1: 'Email is required',
        error2: 'Minimum 6 characters',
      ),
      (
        name: 'invalid email + valid password',
        email: 'invalid-email',
        password: '123456',
        error1: 'Please enter a valid email',
        error2: null,
      ),
      (
        name: 'valid email + empty password',
        email: 'user@test.com',
        password: '',
        error1: 'Password is required',
        error2: null,
      ),
      (
        name: 'valid email + short password',
        email: 'user@test.com',
        password: '123',
        error1: 'Minimum 6 characters',
        error2: null,
      ),
      (
        name: 'email with spaces',
        email: 'user name',
        password: '123456',
        error1: 'Please enter a valid email',
        error2: null,
      ),
      (
        name: 'both invalid',
        email: 'no-at-symbol',
        password: '12',
        error1: 'Please enter a valid email',
        error2: 'Minimum 6 characters',
      ),
    ];

    for (final c in invalidLoginCases) {
      testWidgets('Sign In validates ${c.name}', (tester) async {
        await _pumpScreen(tester, const LoginScreen());
        await _enterLoginValues(tester, c.email, c.password);
        await _tapPrimaryButton(tester, 'Sign In');
        expect(find.text(c.error1), findsOneWidget);
        if (c.error2 != null) {
          expect(find.text(c.error2!), findsOneWidget);
        }
      });
    }

    testWidgets('Forgot password button navigates to forgot password screen', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      await _tapAndSettle(tester, 'Forgot password?');
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text('Forgot password'), findsOneWidget);
    });

    testWidgets('Sign Up button navigates to register screen', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      await _tapAndSettle(tester, 'Sign Up');
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('login form has exactly two text fields', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('password input presents lock icon', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });
  });

  group('Register button QA checks (16)', () {
    testWidgets('renders register actions and fields', (tester) async {
      await _pumpScreen(tester, const RegisterScreen());
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    testWidgets('Sign Up validates empty register form', (tester) async {
      await _pumpScreen(tester, const RegisterScreen());
      await _tapPrimaryButton(tester, 'Sign Up');
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    final invalidRegisterCases = <({String name, String email, String password, List<String> errors})>[
      (
        name: '',
        email: 'user@test.com',
        password: '123456',
        errors: ['Name is required'],
      ),
      (
        name: 'A',
        email: 'user@test.com',
        password: '123456',
        errors: ['Minimum 2 characters'],
      ),
      (
        name: 'Jane Doe',
        email: '',
        password: '123456',
        errors: ['Email is required'],
      ),
      (
        name: 'Jane Doe',
        email: 'invalid',
        password: '123456',
        errors: ['Please enter a valid email'],
      ),
      (
        name: 'Jane Doe',
        email: 'jane',
        password: '123456',
        errors: ['Please enter a valid email'],
      ),
      (
        name: 'Jane Doe',
        email: 'jane@example.com',
        password: '',
        errors: ['Password is required'],
      ),
      (
        name: 'Jane Doe',
        email: 'jane@example.com',
        password: '123',
        errors: ['Minimum 6 characters'],
      ),
      (
        name: 'A',
        email: 'bad-email',
        password: '12',
        errors: ['Minimum 2 characters', 'Please enter a valid email', 'Minimum 6 characters'],
      ),
      (
        name: '',
        email: '',
        password: '',
        errors: ['Name is required', 'Email is required', 'Password is required'],
      ),
      (
        name: 'Valid Name',
        email: 'space email',
        password: '123456',
        errors: ['Please enter a valid email'],
      ),
    ];

    for (var i = 0; i < invalidRegisterCases.length; i++) {
      final c = invalidRegisterCases[i];
      testWidgets('register case ${i + 1} validates expected errors', (tester) async {
        await _pumpScreen(tester, const RegisterScreen());
        await _enterRegisterValues(tester, c.name, c.email, c.password);
        await _tapPrimaryButton(tester, 'Sign Up');
        for (final err in c.errors) {
          expect(find.text(err), findsOneWidget);
        }
      });
    }

    testWidgets('Log In button is visible and tappable', (tester) async {
      await _pumpScreen(tester, const RegisterScreen());
      expect(find.text('Log In'), findsOneWidget);
      await tester.tap(find.text('Log In'));
      await tester.pump();
      expect(find.text('Log In'), findsOneWidget);
    });

    testWidgets('register password input presents lock icon', (tester) async {
      await _pumpScreen(tester, const RegisterScreen());
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });
  });

  group('Forgot password button QA checks (6)', () {
    testWidgets('screen renders action buttons', (tester) async {
      await _pumpScreen(tester, const ForgotPasswordScreen());
      expect(find.text('Send reset link'), findsOneWidget);
      expect(find.text('I have a reset token'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('Send reset link validates empty email', (tester) async {
      await _pumpScreen(tester, const ForgotPasswordScreen());
      await _tapPrimaryButton(tester, 'Send reset link');
      expect(find.text('Email required'), findsOneWidget);
    });

    testWidgets('I have a reset token button navigates to reset screen', (tester) async {
      await _pumpScreen(tester, const ForgotPasswordScreen());
      await _tapAndSettle(tester, 'I have a reset token');
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
    });

    testWidgets('forgot password app bar title is visible', (tester) async {
      await _pumpScreen(tester, const ForgotPasswordScreen());
      expect(find.text('Forgot password'), findsOneWidget);
    });
  });

  group('Reset password button QA checks (10)', () {
    testWidgets('screen renders all required fields and button', (tester) async {
      await _pumpScreen(tester, const ResetPasswordScreen());
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Update password'), findsOneWidget);
    });

    testWidgets('Update password validates empty form', (tester) async {
      await _pumpScreen(tester, const ResetPasswordScreen());
      await _tapPrimaryButton(tester, 'Update password');
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Min 8 characters'), findsOneWidget);
    });

    final invalidResetCases = <({String email, String token, String password, String confirm, List<String> errors})>[
      (
        email: '',
        token: 'token',
        password: '12345678',
        confirm: '12345678',
        errors: ['Required'],
      ),
      (
        email: 'jane@example.com',
        token: '',
        password: '12345678',
        confirm: '12345678',
        errors: ['Required'],
      ),
      (
        email: 'jane@example.com',
        token: 'token',
        password: '123',
        confirm: '123',
        errors: ['Min 8 characters'],
      ),
      (
        email: 'jane@example.com',
        token: 'token',
        password: '12345678',
        confirm: 'different',
        errors: ['Must match'],
      ),
      (
        email: '',
        token: '',
        password: '123',
        confirm: '1',
        errors: ['Required', 'Min 8 characters', 'Must match'],
      ),
      (
        email: 'jane@example.com',
        token: 'token',
        password: '',
        confirm: '',
        errors: ['Min 8 characters'],
      ),
      (
        email: 'jane@example.com',
        token: 'token',
        password: '1234567',
        confirm: '1234567',
        errors: ['Min 8 characters'],
      ),
    ];

    for (var i = 0; i < invalidResetCases.length; i++) {
      final c = invalidResetCases[i];
      testWidgets('reset case ${i + 1} validates expected errors', (tester) async {
        await _pumpScreen(tester, const ResetPasswordScreen());
        await _enterResetValues(
          tester,
          email: c.email,
          token: c.token,
          password: c.password,
          confirmPassword: c.confirm,
        );
        await _tapPrimaryButton(tester, 'Update password');
        for (final err in c.errors) {
          expect(find.text(err), findsWidgets);
        }
      });
    }

    testWidgets('reset password app bar title is visible', (tester) async {
      await _pumpScreen(tester, const ResetPasswordScreen());
      expect(find.text('Reset password'), findsOneWidget);
    });
  });
}
