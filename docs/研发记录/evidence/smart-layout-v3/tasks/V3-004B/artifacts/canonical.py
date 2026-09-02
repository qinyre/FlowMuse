# -*- coding: utf-8 -*-
r"""canonical JSON 哈希（V3-004B vendored 自包含版）。

语义与 FlowMuse-App/tool/smart_layout_v3/src/canonical_artifacts.dart 的
canonicalJson/canonicalJsonSha256 一致：递归键排序、无空白、整数化整数值浮点、
控制字符 \u00xx 转义；已对拍 benchmark-spec.json 内部 content_sha256
（1db65ecd86164231edf535c56476050b95941efd8b75cbbd2de92951722c64a7）验证一致。"""
import hashlib


def _fmt_num(v):
    if isinstance(v, int):
        return str(v)
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    return repr(v)


def _escape(s):
    out = s.replace('\\', '\\\\').replace('"', '\\"')
    res = []
    for ch in out:
        o = ord(ch)
        if o < 0x20:
            res.append('\\u%04x' % o)
        else:
            res.append(ch)
    return ''.join(res)


def canonical(value):
    if isinstance(value, dict):
        keys = sorted(str(k) for k in value.keys())
        parts = []
        for k in keys:
            v = value[k]
            for orig_k in value:
                if str(orig_k) == k:
                    v = value[orig_k]
                    break
            parts.append('"%s":%s' % (_escape(k), canonical(v)))
        return '{' + ','.join(parts) + '}'
    if isinstance(value, list):
        return '[' + ','.join(canonical(x) for x in value) + ']'
    if isinstance(value, str):
        return '"%s"' % _escape(value)
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if value is None:
        return 'null'
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return _fmt_num(value)
    raise TypeError('cannot canonicalize: %r' % (type(value),))


def canonical_sha(value):
    return hashlib.sha256(canonical(value).encode('utf-8')).hexdigest()
