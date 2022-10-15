import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:win32_gamepad/win32_gamepad.dart';

class ThumbData {
  static const zero = ThumbData(position: Offset.zero, angle: 0, distance: 0);

  final Offset position;
  final double angle;
  final double distance;
  const ThumbData({
    required this.position,
    required this.angle,
    required this.distance,
  });
}

class WordData {
  final String word;
  final String upperWord;
  double startAngle = 0.0;
  double endAngle = 0.0;
  double startDistance = 0.0;
  double endDistance = 0.0;

  WordData({
    required this.word,
  }) : upperWord = word.toUpperCase();

  bool contains({
    required double angle,
    required double distance,
  }) {
    return angle >= startAngle && angle <= endAngle && distance >= 0.3333;
  }

  @override
  int get hashCode => Object.hash(word, upperWord);

  @override
  bool operator ==(Object other) {
    return other is WordData &&
        word == other.word &&
        upperWord == other.upperWord;
  }

  @override
  String toString() {
    return word;
  }
}

class CircleData {
  final List<WordData> inside;
  final List<WordData> outside;

  CircleData.empty()
      : inside = [],
        outside = [];

  CircleData({
    required this.inside,
    required this.outside,
  }) {
    if (inside.isEmpty || outside.isEmpty) {
      return;
    }
    const sweepOutside = pi * 2 / 7;
    const sweepInside = pi * 2 / 6;
    for (int i = 0; i < 7; i++) {
      outside[i].startAngle = sweepOutside * i / pi * 180;
      outside[i].endAngle = sweepOutside * (i + 1) / pi * 180;
      outside[i].startDistance = 1 / 3 * 2;
      outside[i].endDistance = 1;
    }
    for (int i = 0; i < 6; i++) {
      inside[i].startAngle = sweepInside * i / pi * 180;
      inside[i].endAngle = sweepInside * (i + 1) / pi * 180;
      inside[i].startDistance = 1 / 3;
      inside[i].endDistance = 1 / 3 * 2;
    }
  }
}

enum GamePadButton {
  shoulderLeft,
  shoulderRight,
  buttonB,
}

enum GamePadLinearButton {
  triggerLeft,
  triggerRight,
  thumbLX,
  thumbLY,
  thumbRX,
  thumbRY
}

class JoystickInput extends StatefulWidget {
  final ValueChanged<String>? onChanged;

  const JoystickInput({
    super.key,
    this.onChanged,
  });

  @override
  State<JoystickInput> createState() => _JoystickInputState();
}

class _JoystickInputState extends State<JoystickInput>
    with TickerProviderStateMixin {
  String text = '';
  final _words = [
    for (int i = 0; i < 26; i++)
      WordData(
        word: String.fromCharCode('a'.codeUnitAt(0) + i),
      ),
  ];
  late final _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();
  final _gamePad = Gamepad(0);

  final _pressedButtons = ValueNotifier<Set<GamePadButton>>({});
  final _buttonState = <GamePadButton, bool>{};
  final _leftThumb = ValueNotifier<ThumbData>(ThumbData.zero);
  final _rightThumb = ValueNotifier<ThumbData>(ThumbData.zero);
  final _leftTrigger = ValueNotifier<double>(0.0);
  final _rightTrigger = ValueNotifier<double>(0.0);
  final _leftOutside = ValueNotifier<bool>(false);
  final _rightOutside = ValueNotifier<bool>(false);
  final _leftUpper = ValueNotifier<bool>(false);
  final _rightUpper = ValueNotifier<bool>(false);
  final _leftWord = ValueNotifier<WordData?>(null);
  final _rightWord = ValueNotifier<WordData?>(null);

  final _leftCircleData = ValueNotifier<CircleData>(CircleData.empty());
  final _rightCircleData = ValueNotifier<CircleData>(CircleData.empty());

  late final buttonsMapping = {
    GamePadButton.buttonB: () => _onButtonDown(GamePadButton.buttonB),
    GamePadButton.shoulderLeft: () => _onButtonDown(GamePadButton.shoulderLeft),
    GamePadButton.shoulderRight: () =>
        _onButtonDown(GamePadButton.shoulderRight),
  };

  late final variableKeysMapping = {
    GamePadLinearButton.triggerLeft: (value) =>
        _onLinear(GamePadLinearButton.triggerLeft, value),
    GamePadLinearButton.triggerRight: (value) =>
        _onLinear(GamePadLinearButton.triggerRight, value),
    GamePadLinearButton.thumbLX: (value) =>
        _onLinear(GamePadLinearButton.thumbLX, value),
    GamePadLinearButton.thumbLY: (value) =>
        _onLinear(GamePadLinearButton.thumbLY, value),
    GamePadLinearButton.thumbRX: (value) =>
        _onLinear(GamePadLinearButton.thumbRX, value),
    GamePadLinearButton.thumbRY: (value) =>
        _onLinear(GamePadLinearButton.thumbRY, value),
  };

  void _layout() {
    _leftCircleData.value = _genCircleData(_words.sublist(0, 13));
    _rightCircleData.value = _genCircleData(_words.sublist(13, 26));
  }

  CircleData _genCircleData(List<WordData> words) {
    return CircleData(
      inside: words.sublist(0, 6),
      outside: words.sublist(6, 13),
    );
  }

  void _addPressedButton(GamePadButton button) {
    _pressedButtons.value.add(button);
    _pressedButtons.notifyListeners();
    switch (button) {
      case GamePadButton.shoulderLeft:
        _leftUpper.value = true;
        break;
      case GamePadButton.shoulderRight:
        _rightUpper.value = true;
        break;
      default:
        break;
    }
  }

  void _removePressedButton(GamePadButton button) {
    _pressedButtons.value.remove(button);
    _pressedButtons.notifyListeners();
    switch (button) {
      case GamePadButton.shoulderLeft:
        _leftUpper.value = false;
        break;
      case GamePadButton.shoulderRight:
        _rightUpper.value = false;
        break;
      default:
        break;
    }
  }

  void _input(String text) {
    this.text = '${this.text}$text';
    widget.onChanged?.call(this.text);
  }

  void _deleteWord() {
    if (text.isEmpty) {
      return;
    }
    text = text.substring(0, text.length - 1);
    widget.onChanged?.call(text);
  }

  void _inputLeft(WordData word, bool upper) {
    if (_leftWord.value == word) {
      return;
    }
    _leftWord.value = word;
    _input(upper ? word.upperWord : word.word);
  }

  void _inputRight(WordData word, bool upper) {
    if (_rightWord.value == word) {
      return;
    }
    _rightWord.value = word;
    _input(upper ? word.upperWord : word.word);
  }

  void _handleThumb({
    required bool left,
    double? x,
    double? y,
  }) {
    final oldValue = left ? _leftThumb.value : _rightThumb.value;
    final position =
        Offset(x ?? oldValue.position.dx, y ?? oldValue.position.dy);
    final vector = v.Vector2(position.dx, position.dy);
    final distance = vector.distanceTo(v.Vector2.all(0)) / 32767;
    final dot = vector.normalized().dot(v.Vector2(1, 0));
    final rad = acos(dot);
    double angle = rad / pi * 180;
    if (position.dy > 0) {
      angle = 180 + (180 - angle);
    }
    final newValue =
        ThumbData(position: position, angle: angle, distance: distance);
    if (left) {
      _leftThumb.value = newValue;
      final list = _leftOutside.value
          ? _leftCircleData.value.outside
          : _leftCircleData.value.inside;
      bool finded = false;
      for (final word in list) {
        if (word.contains(angle: angle, distance: distance)) {
          _inputLeft(word, _leftUpper.value);
          finded = true;
          break;
        }
      }
      if (!finded) {
        _leftWord.value = null;
      }
    } else {
      _rightThumb.value = newValue;
      final list = _rightOutside.value
          ? _rightCircleData.value.outside
          : _rightCircleData.value.inside;
      bool finded = false;
      for (final word in list) {
        if (word.contains(angle: angle, distance: distance)) {
          _inputRight(word, _rightUpper.value);
          finded = true;
          break;
        }
      }
      if (!finded) {
        _rightWord.value = null;
      }
    }
  }

  void _onButtonDown(GamePadButton button) {
    _addPressedButton(button);
    switch (button) {
      case GamePadButton.buttonB:
        _deleteWord();
        break;
      default:
        break;
    }
  }

  void _onButtonUp(GamePadButton button) {
    _removePressedButton(button);
  }

  void _onLinear(GamePadLinearButton key, int value) {
    switch (key) {
      case GamePadLinearButton.triggerLeft:
        _leftTrigger.value = value.toDouble();
        _leftOutside.value = value > 127;
        break;
      case GamePadLinearButton.triggerRight:
        _rightTrigger.value = value.toDouble();
        _rightOutside.value = value > 127;
        break;
      case GamePadLinearButton.thumbLX:
        _handleThumb(left: true, x: value.toDouble());
        break;
      case GamePadLinearButton.thumbLY:
        _handleThumb(left: true, y: value.toDouble());
        break;
      case GamePadLinearButton.thumbRX:
        _handleThumb(left: false, x: value.toDouble());
        break;
      case GamePadLinearButton.thumbRY:
        _handleThumb(left: false, y: value.toDouble());
        break;
    }
  }

  void _handleState(GamepadState state) {
    if (state.buttonB) {
      if (!_buttonState.containsKey(GamePadButton.buttonB)) {
        _onButtonDown(GamePadButton.buttonB);
        _buttonState[GamePadButton.buttonB] = true;
      }
    } else {
      if (_buttonState[GamePadButton.buttonB] == true) {
        _onButtonUp(GamePadButton.buttonB);
        _buttonState.remove(GamePadButton.buttonB);
      }
    }
    if (state.leftShoulder) {
      if (!_buttonState.containsKey(GamePadButton.shoulderLeft)) {
        _onButtonDown(GamePadButton.shoulderLeft);
        _buttonState[GamePadButton.shoulderLeft] = true;
      }
    } else {
      if (_buttonState[GamePadButton.shoulderLeft] == true) {
        _onButtonUp(GamePadButton.shoulderLeft);
        _buttonState.remove(GamePadButton.shoulderLeft);
      }
    }
    if (state.rightShoulder) {
      if (!_buttonState.containsKey(GamePadButton.shoulderRight)) {
        _onButtonDown(GamePadButton.shoulderRight);
        _buttonState[GamePadButton.shoulderRight] = true;
      }
    } else {
      if (_buttonState[GamePadButton.shoulderRight] == true) {
        _onButtonUp(GamePadButton.shoulderRight);
        _buttonState.remove(GamePadButton.shoulderRight);
      }
    }
    _onLinear(GamePadLinearButton.triggerLeft, state.leftTrigger);
    _onLinear(GamePadLinearButton.triggerRight, state.rightTrigger);

    _onLinear(GamePadLinearButton.thumbLX, state.leftThumbstickX);
    _onLinear(GamePadLinearButton.thumbLY, state.leftThumbstickY);

    _onLinear(GamePadLinearButton.thumbRX, state.rightThumbstickX);
    _onLinear(GamePadLinearButton.thumbRY, state.rightThumbstickY);
  }

  void _loadController() {
    _controller.addListener(() {
      _gamePad.updateState();
      final state = _gamePad.state;
      _handleState(state);
    });
  }

  @override
  void initState() {
    super.initState();
    _layout();
    _loadController();
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return JoystickStatusContainer(
      connected: _gamePad.isConnected,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildPanel(),
          ),
          JoystickStatusBar(
            pressedButtons: _pressedButtons,
            leftThumb: _leftThumb,
            rightThumb: _rightThumb,
            leftTrigger: _leftTrigger,
            rightTrigger: _rightTrigger,
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return ValueListenableBuilder<ThumbData>(
      valueListenable: _leftThumb,
      builder: (context, leftThumb, child) {
        return ValueListenableBuilder<ThumbData>(
          valueListenable: _rightThumb,
          builder: (context, rightThumb, child) {
            return ValueListenableBuilder<double>(
              valueListenable: _leftTrigger,
              builder: (context, leftTrigger, child) {
                return ValueListenableBuilder<double>(
                  valueListenable: _rightTrigger,
                  builder: (context, rightTrigger, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _leftOutside,
                      builder: (context, leftOutside, child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _rightOutside,
                          builder: (context, rightOutside, child) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _leftUpper,
                              builder: (context, leftUpper, child) {
                                return ValueListenableBuilder<bool>(
                                  valueListenable: _rightUpper,
                                  builder: (context, rightUpper, child) {
                                    return ValueListenableBuilder<WordData?>(
                                      valueListenable: _leftWord,
                                      builder: (context, leftWord, child) {
                                        return ValueListenableBuilder<
                                            WordData?>(
                                          valueListenable: _rightWord,
                                          builder: (context, rightWord, child) {
                                            return LayoutBuilder(
                                              builder: (context, constraints) {
                                                final width =
                                                    constraints.biggest;
                                                return CustomPaint(
                                                  painter:
                                                      _JoystickPanelPainter(
                                                    leftThumb: leftThumb,
                                                    rightThumb: rightThumb,
                                                    leftTrigger: leftTrigger,
                                                    rightTrigger: rightTrigger,
                                                    leftOutside: leftOutside,
                                                    rightOutside: rightOutside,
                                                    leftUpper: leftUpper,
                                                    rightUpper: rightUpper,
                                                    leftCircleData:
                                                        _leftCircleData.value,
                                                    rightCircleData:
                                                        _rightCircleData.value,
                                                    leftWord: leftWord,
                                                    rightWord: rightWord,
                                                  ),
                                                  size: Size(width.width,
                                                      width.width / 2),
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _JoystickPanelPainter extends CustomPainter {
  final ThumbData leftThumb;
  final ThumbData rightThumb;

  final double leftTrigger;
  final double rightTrigger;

  final CircleData leftCircleData;
  final CircleData rightCircleData;

  final bool leftOutside;
  final bool rightOutside;

  final bool leftUpper;
  final bool rightUpper;

  final WordData? leftWord;
  final WordData? rightWord;

  late Rect leftArea;
  late Rect rightArea;

  late Alignment leftNormal;
  late Alignment rightNormal;

  _JoystickPanelPainter({
    required this.leftThumb,
    required this.rightThumb,
    required this.leftTrigger,
    required this.rightTrigger,
    required this.leftCircleData,
    required this.rightCircleData,
    required this.leftOutside,
    required this.rightOutside,
    required this.leftUpper,
    required this.rightUpper,
    required this.leftWord,
    required this.rightWord,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _initData(size);
    _drawArea(canvas, size);
    _drawCircleData(
      circleData: leftCircleData,
      area: leftArea,
      thumb: leftThumb,
      normal: leftNormal,
      canvas: canvas,
      size: size,
      outside: leftOutside,
      upper: leftUpper,
      selectedWord: leftWord,
    );
    _drawCircleData(
      circleData: rightCircleData,
      area: rightArea,
      thumb: rightThumb,
      normal: rightNormal,
      canvas: canvas,
      size: size,
      outside: rightOutside,
      upper: rightUpper,
      selectedWord: rightWord,
    );
    _drawPoint(canvas, size);
  }

  void _drawCircleData({
    required CircleData circleData,
    required Rect area,
    required ThumbData thumb,
    required Alignment normal,
    required Canvas canvas,
    required Size size,
    required bool outside,
    required bool upper,
    required WordData? selectedWord,
  }) {
    final selectedPaint = Paint()
      ..color = Color.fromARGB(255, 0, 119, 255)
      ..style = PaintingStyle.fill;
    final activePaint = Paint()
      ..color = Color.fromARGB(255, 82, 82, 82)
      ..style = PaintingStyle.fill;

    final deactivePaint = Paint()
      ..color = Color.fromARGB(255, 190, 190, 190)
      ..style = PaintingStyle.fill;

    final height = area.width / 2 / 3;
    const sweepOutside = pi * 2 / 7;
    const sweepInside = pi * 2 / 6;

    for (int i = 0; i < 7; i++) {
      final word = circleData.outside[i];
      canvas.drawArc(
        area,
        0 + sweepOutside * i,
        sweepOutside - 0.01,
        true,
        word == selectedWord
            ? selectedPaint
            : (outside ? activePaint : deactivePaint),
      );
    }

    for (int i = 0; i < 7; i++) {
      final word = circleData.outside[i];
      canvas.save();
      canvas.translate(area.center.dx, area.center.dy);
      canvas.rotate(i / 7 * (pi * 2) + sweepOutside / 2);
      canvas.translate(-area.center.dx, -area.center.dy);
      _drawText(
        text: upper ? word.upperWord : word.word,
        position: area.centerRight.translate(-height / 2, 0),
        canvas: canvas,
        size: size,
      );
      canvas.restore();
    }

    for (int i = 0; i < 6; i++) {
      final word = circleData.inside[i];
      canvas.drawArc(
        area.deflate(height),
        0 + sweepInside * i,
        sweepInside - 0.01,
        true,
        word == selectedWord
            ? selectedPaint
            : (outside ? deactivePaint : activePaint),
      );
    }
    for (int i = 0; i < 6; i++) {
      final word = circleData.inside[i];
      canvas.save();
      canvas.translate(area.center.dx, area.center.dy);
      canvas.rotate(i / 6 * (pi * 2) + sweepInside / 2);
      canvas.translate(-area.center.dx, -area.center.dy);
      _drawText(
        text: upper ? word.upperWord : word.word,
        position: area.deflate(height).centerRight.translate(-height / 2, 0),
        canvas: canvas,
        size: size,
      );
      canvas.restore();
    }

    canvas.drawCircle(area.center, height, Paint()..color = Colors.white);
    _drawText(
      text: 'A',
      position: leftArea.center,
      canvas: canvas,
      size: size,
    );
  }

  void _drawText({
    required String text,
    required Offset position,
    required Canvas canvas,
    required Size size,
  }) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 22),
      ),
    )..layout();
    textPainter.paint(
      canvas,
      position.translate(
        -textPainter.size.width / 2,
        -textPainter.size.height / 2,
      ),
    );
  }

  void _initData(Size size) {
    leftArea = Rect.fromLTWH(0, 0, size.width / 2, size.height);
    rightArea = Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
    leftNormal = Alignment(
        leftThumb.position.dx / 32767, -leftThumb.position.dy / 32767);
    rightNormal = Alignment(
        rightThumb.position.dx / 32767, -rightThumb.position.dy / 32767);
  }

  void _drawArea(Canvas canvas, Size size) {
    final areaPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(leftArea, areaPaint);
    canvas.drawRect(rightArea, areaPaint);

    final circleFillPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(leftArea.center, leftArea.width / 2, circleFillPaint);
    canvas.drawCircle(rightArea.center, rightArea.width / 2, circleFillPaint);

    final circlePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(leftArea.center, leftArea.width / 2, circlePaint);
    canvas.drawCircle(rightArea.center, rightArea.width / 2, circlePaint);
  }

  void _drawPoint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(leftArea.center.dx, leftArea.center.dy);
    canvas.rotate(leftThumb.angle / 180 * pi);
    canvas.translate(-leftArea.center.dx, -leftArea.center.dy);
    canvas.drawLine(leftArea.center, leftArea.centerRight, pointPaint);
    canvas.restore();

    canvas.save();
    canvas.translate(rightArea.center.dx, rightArea.center.dy);
    canvas.rotate(rightThumb.angle / 180 * pi);
    canvas.translate(-rightArea.center.dx, -rightArea.center.dy);
    canvas.drawLine(rightArea.center, rightArea.centerRight, pointPaint);
    canvas.restore();

    canvas.drawCircle(leftNormal.withinRect(leftArea), 10, pointPaint);
    canvas.drawCircle(rightNormal.withinRect(rightArea), 10, pointPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPanelPainter oldDelegate) {
    return leftThumb != oldDelegate.leftThumb ||
        rightThumb != oldDelegate.rightThumb ||
        leftTrigger != oldDelegate.leftTrigger ||
        rightTrigger != oldDelegate.rightTrigger;
  }
}

class JoystickStatusBar extends StatelessWidget {
  final ValueNotifier<Set<GamePadButton>> pressedButtons;

  final ValueNotifier<ThumbData> leftThumb;

  final ValueNotifier<ThumbData> rightThumb;

  final ValueNotifier<double> leftTrigger;

  final ValueNotifier<double> rightTrigger;

  const JoystickStatusBar({
    super.key,
    required this.pressedButtons,
    required this.leftThumb,
    required this.rightThumb,
    required this.leftTrigger,
    required this.rightTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 22,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder(
                valueListenable: pressedButtons,
                builder: (context, buttons, child) {
                  return Text(
                    buttons.map((e) => e.name).join(','),
                    style: const TextStyle(color: Colors.black87, fontSize: 12),
                  );
                }),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<ThumbData>(
            valueListenable: leftThumb,
            builder: (context, thumb, child) {
              return Text(
                'left: (${thumb.position.dx.toInt()},${thumb.position.dy.toInt()})',
                style: const TextStyle(color: Colors.green, fontSize: 10),
              );
            },
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<ThumbData>(
            valueListenable: rightThumb,
            builder: (context, thumb, child) {
              return Text(
                'right: (${thumb.position.dx.toInt()},${thumb.position.dy.toInt()})',
                style: const TextStyle(color: Colors.red, fontSize: 10),
              );
            },
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<double>(
            valueListenable: leftTrigger,
            builder: (context, trigger, child) {
              return Text(
                'left trigger: ${trigger.toInt()}',
                style: const TextStyle(color: Colors.green, fontSize: 10),
              );
            },
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<double>(
            valueListenable: rightTrigger,
            builder: (context, trigger, child) {
              return Text(
                'right trigger: ${trigger.toInt()}',
                style: const TextStyle(color: Colors.red, fontSize: 10),
              );
            },
          ),
        ],
      ),
    );
  }
}

class JoystickStatusContainer extends StatelessWidget {
  final bool connected;
  final Widget? child;

  const JoystickStatusContainer({
    super.key,
    this.connected = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
