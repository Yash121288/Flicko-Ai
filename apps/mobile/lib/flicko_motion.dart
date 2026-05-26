import 'package:flutter/material.dart';

class FlickoMotion {
  const FlickoMotion._();

  static const Duration routeForwardDuration = Duration(milliseconds: 260);
  static const Duration routeReverseDuration = Duration(milliseconds: 220);
  static const Duration inlineDuration = Duration(milliseconds: 180);
  static const Duration pageSnapDuration = Duration(milliseconds: 250);

  static const Curve routeCurve = Curves.easeOutCubic;
  static const Curve routeFadeCurve = Curves.easeOutCubic;
  static const Curve routeReverseCurve = Curves.easeInOutCubic;
  static const Curve pageSnapCurve = Curves.easeOutCubic;
}

class FlickoPageRoute<T> extends PageRouteBuilder<T> {
  FlickoPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
         transitionDuration: FlickoMotion.routeForwardDuration,
         reverseTransitionDuration: FlickoMotion.routeReverseDuration,
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return FlickoPageTransitionsBuilder.buildSmoothTransition(
             animation: animation,
             child: child,
           );
         },
       );
}

class FlickoPageTransitionsBuilder extends PageTransitionsBuilder {
  const FlickoPageTransitionsBuilder();

  static Widget buildSmoothTransition({
    required Animation<double> animation,
    required Widget child,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: FlickoMotion.routeCurve,
      reverseCurve: FlickoMotion.routeReverseCurve,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: FlickoMotion.routeFadeCurve,
      reverseCurve: FlickoMotion.routeReverseCurve,
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.045, 0),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return buildSmoothTransition(animation: animation, child: child);
  }
}
