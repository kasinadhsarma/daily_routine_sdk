/// Formats a "minutes since midnight" value as `h:mm AM/PM`.
String formatMinuteOfDay(int minuteOfDay) {
  final hour24 = (minuteOfDay ~/ 60) % 24;
  final minute = minuteOfDay % 60;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minuteStr = minute.toString().padLeft(2, '0');
  return '$hour12:$minuteStr $period';
}

int nowAsMinuteOfDay([DateTime? now]) {
  final t = now ?? DateTime.now();
  return t.hour * 60 + t.minute;
}
