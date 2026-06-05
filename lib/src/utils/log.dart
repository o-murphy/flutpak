import 'dart:io';

bool get _ansi => stderr.supportsAnsiEscapes;

String _fmt(String code, String level, String msg) =>
    _ansi ? '\x1b[${code}m$level  $msg\x1b[0m' : '$level  $msg';

void logDebug(String msg) => stderr.writeln(_fmt('90', 'DEBUG', msg));
void logInfo(String msg)  => stderr.writeln(_fmt('32', 'INFO ', msg));
void logWarn(String msg)  => stderr.writeln(_fmt('33', 'WARN ', msg));
void logError(String msg) => stderr.writeln(_fmt('31', 'ERROR', msg));
