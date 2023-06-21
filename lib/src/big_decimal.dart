// ignore_for_file: constant_identifier_names

/// rounding modes for operations; defaults to [RoundingMode.UNNECESSARY]
enum RoundingMode {
  UP,
  DOWN,
  CEILING,
  FLOOR,
  HALF_UP,
  HALF_DOWN,
  HALF_EVEN,

  /// does not round at all; throws if the result cannot be represented exactly.
  UNNECESSARY,
}

const plusCode = 43;
const minusCode = 45;
const dotCode = 46;
const smallECode = 101;
const capitalECode = 69;
const zeroCode = 48;
const nineCode = 57;

/// make it easier to incrementally change int fields to BigInt
extension _BigIntExtension on int {
  BigInt toBigInt() => BigInt.from(this);
}

/// An arbitrarily large decimal value.
///
/// Big decimals are signed and can have an arbitrary number of
/// significant digits, only limited by memory.
class BigDecimal implements Comparable<BigDecimal> {
  BigDecimal._({
    required this.intVal,
    required BigInt scale,
  }) : _scale = scale;

  /// Converts a [BigInt] to a [BigDecimal].
  factory BigDecimal.fromBigInt(BigInt value) {
    return BigDecimal._(
      intVal: value,
      scale: BigInt.zero,
    );
  }

  /// A big decimal with numerical value 0
  static final zero = BigDecimal.fromBigInt(BigInt.zero);

  /// A big decimal with numerical value 1
  static final one = BigDecimal.fromBigInt(BigInt.one);

  /// A big decimal with numerical value 2
  static final two = BigDecimal.fromBigInt(BigInt.two);

  static int nextNonDigit(String value, [int start = 0]) {
    var index = start;
    for (; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code < zeroCode || code > nineCode) {
        break;
      }
    }
    return index;
  }

  /// Parses [source] as a, possibly signed, decimal literal and returns its value. Otherwise returns null.
  static BigDecimal? tryParse(String value) {
    try {
      return BigDecimal.parse(value);
    } catch (e) {
      return null;
    }
  }

  /// Parses [source] as a, possibly signed, decimal literal and returns its value. Otherwise throws [Exception].
  factory BigDecimal.parse(String value) {
    var sign = '';
    var index = 0;
    var nextIndex = 0;

    switch (value.codeUnitAt(index)) {
      case minusCode:
        sign = '-';
        index++;
        break;
      case plusCode:
        index++;
        break;
      default:
        break;
    }

    nextIndex = nextNonDigit(value, index);
    final integerPart = '$sign${value.substring(index, nextIndex)}';
    index = nextIndex;

    if (index >= value.length) {
      return BigDecimal.fromBigInt(BigInt.parse(integerPart));
    }

    var decimalPart = '';
    if (value.codeUnitAt(index) == dotCode) {
      index++;
      nextIndex = nextNonDigit(value, index);
      decimalPart = value.substring(index, nextIndex);
      index = nextIndex;

      if (index >= value.length) {
        return BigDecimal._(
          intVal: BigInt.parse('$integerPart$decimalPart'),
          scale: decimalPart.length.toBigInt(),
        );
      }
    }

    switch (value.codeUnitAt(index)) {
      case smallECode:
      case capitalECode:
        index++;
        final exponent = int.parse(value.substring(index));
        return BigDecimal._(
          intVal: BigInt.parse('$integerPart$decimalPart'),
          scale: (decimalPart.length - exponent).toBigInt(),
        );
    }

    throw Exception(
      'Not a valid BigDecimal string representation: $value.\n'
      'Unexpected ${value.substring(index)}.',
    );
  }

  /// integer value of this big decimal
  final BigInt intVal;
  late final int precision = _calculatePrecision();
  final BigInt _scale;

  @override
  bool operator ==(dynamic other) => other is BigDecimal && compareTo(other) == 0;

  bool exactlyEquals(dynamic other) => other is BigDecimal && intVal == other.intVal && _scale == other._scale;

  BigDecimal operator +(BigDecimal other) => _add(intVal, other.intVal, _scale.toInt(), other._scale.toInt());

  BigDecimal operator *(BigDecimal other) => BigDecimal._(intVal: intVal * other.intVal, scale: _scale + other._scale);

  BigDecimal operator -(BigDecimal other) => _add(intVal, -other.intVal, _scale.toInt(), other._scale.toInt());

  bool operator <(BigDecimal other) => compareTo(other) < 0;

  bool operator <=(BigDecimal other) => compareTo(other) <= 0;

  bool operator >(BigDecimal other) => compareTo(other) > 0;

  bool operator >=(BigDecimal other) => compareTo(other) >= 0;

  BigDecimal operator -() => BigDecimal._(intVal: -intVal, scale: _scale);

  BigDecimal abs() => BigDecimal._(intVal: intVal.abs(), scale: _scale);

  BigDecimal divide(
    BigDecimal divisor, {
    RoundingMode roundingMode = RoundingMode.UNNECESSARY,
    int? scale,
  }) =>
      _divide(
        intVal,
        this._scale.toInt(),
        divisor.intVal,
        divisor._scale.toInt(),
        scale ?? this._scale.toInt(),
        roundingMode,
      );

  BigDecimal pow(int n) {
    if (n >= 0 && n <= 999999999) {
      // TODO: Check scale of this multiplication
      final newScale = _scale * n.toBigInt();
      return BigDecimal._(intVal: intVal.pow(n), scale: newScale);
    }
    // why? BigInt is arbitrarily large; BigDecimal should be as well
    throw Exception('Invalid operation: Exponent should be between 0 and 999999999');
  }

  double toDouble() => intVal.toDouble() / BigInt.from(10).pow(_scale.toInt()).toDouble();
  BigInt toBigInt({RoundingMode roundingMode = RoundingMode.UNNECESSARY}) =>
      withScale(0, roundingMode: roundingMode).intVal;
  int toInt({RoundingMode roundingMode = RoundingMode.UNNECESSARY}) => toBigInt(roundingMode: roundingMode).toInt();

  BigDecimal withScale(
    int newScaleValue, {
    RoundingMode roundingMode = RoundingMode.UNNECESSARY,
  }) {
    final newScale = newScaleValue.toBigInt();
    if (_scale == newScale) {
      return this;
    } else if (intVal.sign == 0) {
      return BigDecimal._(intVal: BigInt.zero, scale: newScale);
    } else {
      if (newScale > _scale) {
        final drop = sumScale(newScale, -_scale);
        final intResult = intVal * BigInt.from(10).pow(drop.toInt());
        return BigDecimal._(intVal: intResult, scale: newScale);
      } else {
        final drop = sumScale(_scale, -newScale);
        return _divideAndRound(
          intVal,
          BigInt.from(10).pow(drop.toInt()),
          newScale.toInt(),
          roundingMode,
          newScale.toInt(),
        );
      }
    }
  }

  int _calculatePrecision() {
    if (intVal.sign == 0) {
      return 1;
    }
    final r = ((intVal.bitLength + 1) * 646456993) >> 31;
    return intVal.abs().compareTo(BigInt.from(10).pow(r)) < 0 ? r : r + 1;
  }

  static BigDecimal _add(BigInt intValA, BigInt intValB, int scaleA, int scaleB) {
    final scaleDiff = scaleA - scaleB;
    if (scaleDiff == 0) {
      return BigDecimal._(intVal: intValA + intValB, scale: scaleA.toBigInt());
    } else if (scaleDiff < 0) {
      final scaledX = intValA * BigInt.from(10).pow(-scaleDiff);
      return BigDecimal._(intVal: scaledX + intValB, scale: scaleB.toBigInt());
    } else {
      final scaledY = intValB * BigInt.from(10).pow(scaleDiff);
      return BigDecimal._(intVal: intValA + scaledY, scale: scaleA.toBigInt());
    }
  }

  static BigDecimal _divide(
    BigInt dividend,
    int dividendScale,
    BigInt divisor,
    int divisorScale,
    int scale,
    RoundingMode roundingMode,
  ) {
    if (dividend == BigInt.zero) {
      return BigDecimal._(intVal: BigInt.zero, scale: scale.toBigInt());
    }
    if (sumScale(scale.toBigInt(), divisorScale.toBigInt()) > dividendScale.toBigInt()) {
      final newScale = scale + divisorScale;
      final raise = newScale - dividendScale;
      final scaledDividend = dividend * BigInt.from(10).pow(raise);
      return _divideAndRound(scaledDividend, divisor, scale, roundingMode, scale);
    } else {
      final newScale = sumScale(dividendScale.toBigInt(), -scale.toBigInt());
      final raise = newScale - divisorScale.toBigInt();
      final scaledDivisor = divisor * BigInt.from(10).pow(raise.toInt());
      return _divideAndRound(dividend, scaledDivisor, scale, roundingMode, scale);
    }
  }

  static BigDecimal _divideAndRound(
    BigInt dividend,
    BigInt divisor,
    int scale,
    RoundingMode roundingMode,
    int preferredScale,
  ) {
    final quotient = dividend ~/ divisor;
    final remainder = dividend.remainder(divisor).abs();
    final quotientPositive = dividend.sign == divisor.sign;
    if (remainder != BigInt.zero) {
      if (_needIncrement(divisor, roundingMode, quotientPositive, quotient, remainder)) {
        final intResult = quotient + (quotientPositive ? BigInt.one : -BigInt.one);
        return BigDecimal._(intVal: intResult, scale: scale.toBigInt());
      }
      return BigDecimal._(intVal: quotient, scale: scale.toBigInt());
    } else {
      if (preferredScale != scale) {
        return createAndStripZerosForScale(quotient, scale, preferredScale);
      } else {
        return BigDecimal._(intVal: quotient, scale: scale.toBigInt());
      }
    }
  }

  static BigDecimal createAndStripZerosForScale(
    BigInt intVal,
    int scale,
    int preferredScale,
  ) {
    final ten = BigInt.from(10);
    var intValMut = intVal;
    var scaleMut = scale.toBigInt();

    while (intValMut.compareTo(ten) >= 0 && scaleMut > preferredScale.toBigInt()) {
      if (intValMut.isOdd) {
        break;
      }
      final remainder = intValMut.remainder(ten);

      if (remainder.sign != 0) {
        break;
      }
      intValMut = intValMut ~/ ten;
      scaleMut = sumScale(scaleMut, -BigInt.one);
    }

    return BigDecimal._(intVal: intValMut, scale: scaleMut);
  }

  static bool _needIncrement(
    BigInt divisor,
    RoundingMode roundingMode,
    bool quotientPositive,
    BigInt quotient,
    BigInt remainder,
  ) {
    final remainderComparisonToHalfDivisor = (remainder * BigInt.from(2)).compareTo(divisor);
    switch (roundingMode) {
      case RoundingMode.UNNECESSARY:
        throw Exception('Rounding necessary');
      case RoundingMode.UP: // Away from zero
        return true;
      case RoundingMode.DOWN: // Towards zero
        return false;
      case RoundingMode.CEILING: // Towards +infinity
        return quotientPositive;
      case RoundingMode.FLOOR: // Towards -infinity
        return !quotientPositive;
      case RoundingMode.HALF_DOWN:
      case RoundingMode.HALF_EVEN:
      case RoundingMode.HALF_UP:
        if (remainderComparisonToHalfDivisor < 0) {
          return false;
        } else if (remainderComparisonToHalfDivisor > 0) {
          return true;
        } else {
          // Half
          switch (roundingMode) {
            case RoundingMode.HALF_DOWN:
              return false;

            case RoundingMode.HALF_UP:
              return true;

            // At this point it must be HALF_EVEN
            default:
              return quotient.isOdd;
          }
        }
    }
  }

  @override
  int compareTo(BigDecimal other) {
    if (_scale == other._scale) {
      return intVal != other.intVal ? (intVal > other.intVal ? 1 : -1) : 0;
    }

    final thisSign = intVal.sign;
    final otherSign = other.intVal.sign;
    if (thisSign != otherSign) {
      return (thisSign > otherSign) ? 1 : -1;
    }

    if (thisSign == 0) {
      return 0;
    }
    //TODO: Optimize this
    return _add(intVal, -other.intVal, _scale.toInt(), other._scale.toInt()).intVal.sign;
  }

  @override
  int get hashCode => 31 * intVal.hashCode + _scale.toInt();

  @override
  String toString() {
    if (_scale == BigInt.zero) {
      return intVal.toString();
    }

    final intStr = intVal.abs().toString();
    final adjusted = (intStr.length - 1) - _scale.toInt();

    // Java's heuristic to avoid too many decimal places
    if (_scale >= BigInt.zero && adjusted >= -6) {
      return toPlainString();
    }

    // Exponential notation
    final b = StringBuffer(intVal.isNegative ? '-' : '');
    b.write(intStr[0]);
    if (intStr.length > 1) {
      b
        ..write('.')
        ..write(intStr.substring(1));
    }
    if (adjusted != 0) {
      b.write('e');
      if (adjusted > 0) {
        b.write('+');
      }
      b.write(adjusted);
    }

    return b.toString();
  }

  String toPlainString() {
    if (_scale == BigInt.zero) {
      return intVal.toString();
    }

    final intStr = intVal.abs().toString();
    final b = StringBuffer(intVal.isNegative ? '-' : '');

    if (_scale > BigInt.zero) {
      if (intStr.length > _scale.toInt()) {
        final integerPart = intStr.substring(0, intStr.length - _scale.toInt());
        b.write(integerPart);

        final decimalPart = intStr.substring(intStr.length - _scale.toInt());
        if (decimalPart.isNotEmpty) {
          b.write('.$decimalPart');
        }
      } else {
        b
          ..write('0.')
          ..write(intStr.padLeft(_scale.toInt(), '0'));
      }
    } else {
      b.write(intStr.padRight(_scale.toInt().abs() + intStr.length, '0'));
    }

    return b.toString();
  }
}

/// Sum two scales
BigInt sumScale(BigInt scaleA, BigInt scaleB) {
  return scaleA + scaleB;
}

/// Getters to avoid breaking test cases while fixing overflow issues
extension TestGetters on BigDecimal {
  int get scale => _scale.toInt();
}
