from fpbinary import FpBinary, FpBinarySwitchable, RoundingEnum

FP_MODE = True


def get_type_spec(pkg, type_prefix):
    int_attr = f"{type_prefix}_W_INT"
    frac_attr = f"{type_prefix}_W_FRAC"

    return (
        int(getattr(pkg, int_attr).value),
        int(getattr(pkg, frac_attr).value),
    )


def fixp_init(val, type, signed=False):
    int_bits, frac_bits = type

    fp_value = FpBinary(
        int_bits=int_bits, frac_bits=frac_bits, signed=signed, value=val
    )

    return FpBinarySwitchable(
        fp_mode=FP_MODE, fp_value=fp_value, float_value=val
    )


def fixp_expr(expr, num):
    int_bits, frac_bits = num.format

    if type(num.value) is FpBinary:
        fp_value = FpBinary(
            int_bits=int_bits,
            frac_bits=frac_bits,
            signed=num.value.is_signed,
            value=expr,
        )
    else:
        fp_value = expr

    return FpBinarySwitchable(
        fp_mode=FP_MODE, fp_value=fp_value, float_value=expr
    )


def fixp_unsigned(val, type):
    int_bits, frac_bits = type

    fp_value = FpBinary(
        int_bits=int_bits,
        frac_bits=frac_bits,
        signed=False,
        value=val
    )

    return FpBinarySwitchable(
        fp_mode=FP_MODE,
        fp_value=fp_value,
        float_value=val
    )


def fixp_cast(num, fixp_type):
    int_bits, frac_bits = fixp_type
    return num.resize(
        format=(int_bits, frac_bits),
        round_mode=RoundingEnum.direct_neg_inf,
    )
