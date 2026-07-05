import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WeekScheduleApp());
}

class WeekScheduleApp extends StatelessWidget {
  const WeekScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Week Schedule',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEF7D72),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD9DFE7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD9DFE7)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const ScheduleHomePage(),
    );
  }
}

enum ScheduleCategory {
  work('근로', Icons.badge_outlined, Color(0xFFF17D72)),
  lecture('수업', Icons.menu_book_outlined, Color(0xFF79CDBF)),
  writing('글쓰기', Icons.edit_note_outlined, Color(0xFFEFC75F)),
  practice('실습', Icons.movie_creation_outlined, Color(0xFFFFA65E)),
  culture('교양', Icons.auto_stories_outlined, Color(0xFF9A7DE0)),
  travel('여행', Icons.flight_takeoff_outlined, Color(0xFF6FB6E8)),
  personal('개인', Icons.person_outline, Color(0xFF9CCB75));

  const ScheduleCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

/// 일정 유형: 매주 반복되는 [fixed] 고정 시간표와 특정 날짜의 [oneTime] 일회성 스케줄.
enum ScheduleType {
  fixed('고정', Icons.repeat),
  oneTime('일회성', Icons.event_available_outlined);

  const ScheduleType(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum ViewMode { week, month }

class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.title,
    required this.type,
    required this.start,
    required this.end,
    required this.category,
    int? weekday,
    List<int>? weekdays,
    this.date,
    DateTime? endDate,
    Color? color,
    this.note = '',
    this.done = false,
  }) : assert(
         type == ScheduleType.fixed
             ? (weekday != null || (weekdays != null && weekdays.isNotEmpty))
             : date != null,
         '고정 일정은 요일이, 일회성 일정은 날짜가 필요합니다.',
       ),
       weekdays =
           type == ScheduleType.fixed
               ? _normalizeWeekdays(weekdays ?? <int>[weekday!])
               : <int>[_validWeekday(date!.weekday)],
       endDate = _normalizeEndDate(type, date, endDate),
       color = color ?? category.color;

  final String id;
  final String title;
  final ScheduleType type;

  /// 고정 일정의 반복 요일들(DateTime.monday~sunday). 일회성은 [date]에서 파생.
  final List<int> weekdays;

  /// 기존 단일 요일 접근을 위한 대표 요일.
  int get weekday => weekdays.first;

  /// 일회성 일정의 날짜(시각 정보 제외). 고정 일정은 null.
  final DateTime? date;

  /// 일회성 일정이 여러 날에 걸칠 때의 마지막 날짜(포함). 하루짜리면 null.
  final DateTime? endDate;

  final TimeOfDay start;
  final TimeOfDay end;
  final ScheduleCategory category;
  final Color color;
  final String note;
  bool done;

  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;
  int get durationMinutes => endMinutes - startMinutes;

  /// 여러 날에 걸친 일정(여행 등)인지 여부. 종일 일정으로 취급한다.
  bool get isMultiDay => endDate != null;

  /// 일정이 차지하는 일수. 하루짜리는 1.
  int get dayCount =>
      isMultiDay ? endDate!.difference(_dateOnly(date!)).inDays + 1 : 1;

  /// 해당 일자에 이 일정이 나타나는지 여부.
  bool occursOn(DateTime day) {
    if (type == ScheduleType.fixed) {
      return weekdays.contains(day.weekday);
    }
    if (date == null) {
      return false;
    }
    if (endDate != null) {
      final target = _dateOnly(day);
      return !target.isBefore(_dateOnly(date!)) && !target.isAfter(endDate!);
    }
    return _isSameDate(date!, day);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'type': type.name,
      'weekday': weekday,
      'weekdays': type == ScheduleType.fixed ? weekdays : null,
      'date': date == null ? null : _storageDate(date!),
      'endDate': endDate == null ? null : _storageDate(endDate!),
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'category': category.name,
      'color': color.toARGB32(),
      'note': note,
      'done': done,
    };
  }

  factory ScheduleItem.fromJson(Map<String, Object?> json) {
    final type = _enumByName(
      ScheduleType.values,
      json['type'],
      ScheduleType.fixed,
    );
    final category = _enumByName(
      ScheduleCategory.values,
      json['category'],
      ScheduleCategory.personal,
    );
    final date = _dateFromStorage(json['date']);
    final fallbackDate = _dateOnly(DateTime.now());
    final weekday = _validWeekday(
      _jsonInt(json['weekday'], fallbackDate.weekday),
    );
    final weekdays = _jsonWeekdays(json['weekdays'], fallback: <int>[weekday]);

    return ScheduleItem(
      id: _jsonString(
        json['id'],
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      title: _jsonString(json['title'], '제목 없음'),
      type: type,
      weekdays: type == ScheduleType.fixed ? weekdays : null,
      date: type == ScheduleType.oneTime ? (date ?? fallbackDate) : null,
      endDate: _dateFromStorage(json['endDate']),
      start: _timeFromMinutes(_jsonInt(json['startMinutes'], 9 * 60)),
      end: _timeFromMinutes(_jsonInt(json['endMinutes'], 10 * 60)),
      category: category,
      color: Color(_jsonInt(json['color'], category.color.toARGB32())),
      note: _jsonString(json['note'], ''),
      done: json['done'] == true,
    );
  }
}

class _LocalScheduleState {
  const _LocalScheduleState({
    required this.items,
    required this.startHour,
    required this.endHour,
  });

  final List<ScheduleItem> items;
  final int startHour;
  final int endHour;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'items': items.map((item) => item.toJson()).toList(),
      'startHour': startHour,
      'endHour': endHour,
    };
  }

  factory _LocalScheduleState.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final items = <ScheduleItem>[];
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is Map) {
          items.add(ScheduleItem.fromJson(Map<String, Object?>.from(rawItem)));
        }
      }
    }

    return _LocalScheduleState(
      items: items,
      startHour: _jsonInt(json['startHour'], 8),
      endHour: _jsonInt(json['endHour'], 24),
    );
  }
}

class _ScheduleStorage {
  const _ScheduleStorage();

  static const _storageKey = 'week_schedule.local_state.v1';

  Future<_LocalScheduleState?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawState = preferences.getString(_storageKey);
    if (rawState == null) {
      return null;
    }
    final decoded = jsonDecode(rawState);
    if (decoded is! Map) {
      return null;
    }
    return _LocalScheduleState.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> save(_LocalScheduleState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
  }
}

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({super.key});

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage> {
  final _storage = const _ScheduleStorage();
  ViewMode _viewMode = ViewMode.week;
  late DateTime _anchor;
  int _startHour = 8;
  int _endHour = 24;

  List<ScheduleItem> _items = <ScheduleItem>[
    // 고정 시간표 (매주 반복)
    ScheduleItem(
      id: 'seed-1',
      title: '근로',
      type: ScheduleType.fixed,
      weekday: DateTime.monday,
      start: const TimeOfDay(hour: 8, minute: 30),
      end: const TimeOfDay(hour: 14, minute: 0),
      category: ScheduleCategory.work,
    ),
    ScheduleItem(
      id: 'seed-2',
      title: '문화이론과 대중문화',
      type: ScheduleType.fixed,
      weekday: DateTime.tuesday,
      start: const TimeOfDay(hour: 10, minute: 30),
      end: const TimeOfDay(hour: 12, minute: 0),
      category: ScheduleCategory.lecture,
      note: '5남532',
    ),
    ScheduleItem(
      id: 'seed-3',
      title: '문화이론과 대중문화',
      type: ScheduleType.fixed,
      weekday: DateTime.thursday,
      start: const TimeOfDay(hour: 10, minute: 30),
      end: const TimeOfDay(hour: 12, minute: 0),
      category: ScheduleCategory.lecture,
      note: '5남532',
    ),
    ScheduleItem(
      id: 'seed-4',
      title: '캐릭터 유형론',
      type: ScheduleType.fixed,
      weekday: DateTime.tuesday,
      start: const TimeOfDay(hour: 13, minute: 30),
      end: const TimeOfDay(hour: 15, minute: 0),
      category: ScheduleCategory.lecture,
      color: const Color(0xFF72A1E8),
      note: '5남533',
    ),
    ScheduleItem(
      id: 'seed-5',
      title: '캐릭터 유형론',
      type: ScheduleType.fixed,
      weekday: DateTime.thursday,
      start: const TimeOfDay(hour: 13, minute: 30),
      end: const TimeOfDay(hour: 15, minute: 0),
      category: ScheduleCategory.lecture,
      color: const Color(0xFF72A1E8),
      note: '5남533',
    ),
    ScheduleItem(
      id: 'seed-6',
      title: '비평적 글쓰기',
      type: ScheduleType.fixed,
      weekday: DateTime.monday,
      start: const TimeOfDay(hour: 15, minute: 0),
      end: const TimeOfDay(hour: 16, minute: 30),
      category: ScheduleCategory.writing,
      note: '5남535',
    ),
    ScheduleItem(
      id: 'seed-7',
      title: '비평적 글쓰기',
      type: ScheduleType.fixed,
      weekday: DateTime.wednesday,
      start: const TimeOfDay(hour: 15, minute: 0),
      end: const TimeOfDay(hour: 16, minute: 30),
      category: ScheduleCategory.writing,
      note: '5남535',
    ),
    ScheduleItem(
      id: 'seed-8',
      title: '영상문화콘텐츠 기획 개발',
      type: ScheduleType.fixed,
      weekday: DateTime.tuesday,
      start: const TimeOfDay(hour: 15, minute: 0),
      end: const TimeOfDay(hour: 18, minute: 0),
      category: ScheduleCategory.practice,
      note: '5남533',
    ),
    ScheduleItem(
      id: 'seed-9',
      title: '문학의 이해',
      type: ScheduleType.fixed,
      weekday: DateTime.thursday,
      start: const TimeOfDay(hour: 15, minute: 0),
      end: const TimeOfDay(hour: 18, minute: 0),
      category: ScheduleCategory.culture,
      note: '5동102',
    ),
    ScheduleItem(
      id: 'seed-10',
      title: '인하인스타',
      type: ScheduleType.fixed,
      weekday: DateTime.monday,
      start: const TimeOfDay(hour: 17, minute: 0),
      end: const TimeOfDay(hour: 18, minute: 0),
      category: ScheduleCategory.personal,
    ),
    // 일회성 스케줄 (특정 날짜)
    ScheduleItem(
      id: 'seed-once-1',
      title: '팀 프로젝트 회의',
      type: ScheduleType.oneTime,
      date: DateTime(2026, 6, 16),
      start: const TimeOfDay(hour: 16, minute: 30),
      end: const TimeOfDay(hour: 17, minute: 30),
      category: ScheduleCategory.personal,
      note: '도서관 그룹실',
    ),
    ScheduleItem(
      id: 'seed-once-2',
      title: '치과 예약',
      type: ScheduleType.oneTime,
      date: DateTime(2026, 6, 19),
      start: const TimeOfDay(hour: 9, minute: 0),
      end: const TimeOfDay(hour: 10, minute: 0),
      category: ScheduleCategory.personal,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _anchor = _dateOnly(DateTime.now());
    unawaited(_loadLocalState());
  }

  Future<void> _loadLocalState() async {
    try {
      final savedState = await _storage.load();
      if (!mounted || savedState == null) {
        return;
      }
      setState(() {
        _items = savedState.items;
        _startHour = savedState.startHour;
        _endHour = savedState.endHour;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장된 일정을 불러오지 못했습니다.')));
    }
  }

  void _saveLocalState() {
    unawaited(() async {
      try {
        await _storage.save(
          _LocalScheduleState(
            items: _items,
            startHour: _startHour,
            endHour: _endHour,
          ),
        );
      } catch (_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('일정을 로컬에 저장하지 못했습니다.')));
      }
    }());
  }

  void _setItemDone(ScheduleItem item, bool? value) {
    setState(() {
      item.done = value ?? false;
    });
    _saveLocalState();
  }

  /// 특정 날짜에 발생하는 일정 목록(시작 시각순 정렬).
  List<ScheduleItem> _itemsOn(DateTime day) {
    final list = _items.where((item) => item.occursOn(day)).toList();
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final weekStart = _startOfWeek(_anchor);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final month = DateTime(_anchor.year, _anchor.month, 1);

    final String yearLabel;
    final String titleLabel;
    final String subtitleLabel;
    final String rangeLabel;

    if (_viewMode == ViewMode.week) {
      var weekCount = 0;
      var weekDone = 0;
      for (var i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        for (final item in _items) {
          if (item.occursOn(day)) {
            weekCount++;
            if (item.done) weekDone++;
          }
        }
      }
      yearLabel = '${weekStart.year}년';
      titleLabel = '${weekStart.month}월';
      subtitleLabel = '이번 주 $weekCount개 · 완료 $weekDone';
      rangeLabel = '${_formatDate(weekStart)} - ${_formatDate(weekEnd)}';
    } else {
      var monthCount = 0;
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      for (var day = 1; day <= daysInMonth; day++) {
        final date = DateTime(month.year, month.month, day);
        for (final item in _items) {
          if (item.occursOn(date)) monthCount++;
        }
      }
      yearLabel = '${month.year}년';
      titleLabel = '${month.month}월';
      subtitleLabel = '이번 달 $monthCount개 일정';
      rangeLabel = '${month.year}.${month.month}';
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openScheduleSheet(),
        tooltip: '일정 추가',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth =
                constraints.maxWidth >= 720 ? 560.0 : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    children: [
                      _HeaderBar(
                        yearLabel: yearLabel,
                        titleLabel: titleLabel,
                        subtitleLabel: subtitleLabel,
                        showSettings: _viewMode == ViewMode.week,
                        onAdd: () => _openScheduleSheet(),
                        onSettings: _openSettingsSheet,
                        onList: _openAgendaSheet,
                      ),
                      const SizedBox(height: 12),
                      _ControlBar(
                        viewMode: _viewMode,
                        rangeLabel: rangeLabel,
                        onViewChanged: (mode) {
                          setState(() => _viewMode = mode);
                        },
                        onPrev: _goPrev,
                        onNext: _goNext,
                        onToday: _goToday,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            _viewMode == ViewMode.week
                                ? SingleChildScrollView(
                                  child: _TimetableView(
                                    items: _items,
                                    weekStart: weekStart,
                                    today: today,
                                    startHour: _startHour,
                                    endHour: _endHour,
                                    onSlotTap: (weekday, date, hour) {
                                      _openScheduleSheet(
                                        weekday: weekday,
                                        date: date,
                                        start: TimeOfDay(hour: hour, minute: 0),
                                        end: TimeOfDay(
                                          hour: math.min(hour + 1, 23),
                                          minute: 0,
                                        ),
                                      );
                                    },
                                    onItemTap: _openItemDetailSheet,
                                  ),
                                )
                                : _MonthView(
                                  month: month,
                                  today: today,
                                  itemsOn: _itemsOn,
                                  onDayTap: _openDaySheet,
                                ),
                      ),
                      const SizedBox(height: 10),
                      _CategoryLegend(items: _items),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _goPrev() {
    setState(() {
      if (_viewMode == ViewMode.week) {
        _anchor = _anchor.subtract(const Duration(days: 7));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month - 1, 1);
      }
    });
  }

  void _goNext() {
    setState(() {
      if (_viewMode == ViewMode.week) {
        _anchor = _anchor.add(const Duration(days: 7));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + 1, 1);
      }
    });
  }

  void _goToday() {
    setState(() {
      _anchor = _dateOnly(DateTime.now());
    });
  }

  void _saveItem(ScheduleItem savedItem) {
    setState(() {
      final index = _items.indexWhere(
        (schedule) => schedule.id == savedItem.id,
      );
      if (index == -1) {
        _items.add(savedItem);
      } else {
        _items[index] = savedItem;
      }
      // 새로 저장한 일정이 보이도록 시점을 이동.
      if (savedItem.type == ScheduleType.oneTime && savedItem.date != null) {
        _anchor = _dateOnly(savedItem.date!);
      }
    });
    _saveLocalState();
  }

  void _deleteItem(ScheduleItem item) {
    setState(() {
      _items.removeWhere((schedule) => schedule.id == item.id);
    });
    _saveLocalState();
  }

  Future<void> _openScheduleSheet({
    ScheduleType? type,
    int? weekday,
    DateTime? date,
    TimeOfDay? start,
    TimeOfDay? end,
    ScheduleItem? item,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _ScheduleFormSheet(
          initialItem: item,
          initialType: type ?? item?.type ?? ScheduleType.fixed,
          initialWeekdays: item?.weekdays ?? <int>[weekday ?? _anchor.weekday],
          initialDate: date ?? item?.date ?? _anchor,
          initialEndDate: item?.endDate,
          initialStart:
              start ?? item?.start ?? const TimeOfDay(hour: 9, minute: 0),
          initialEnd: end ?? item?.end ?? const TimeOfDay(hour: 10, minute: 0),
          onSave: _saveItem,
        );
      },
    );
  }

  Future<void> _openSettingsSheet() async {
    var startHour = _startHour;
    var endHour = _endHour;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void save() {
              if (endHour <= startHour) {
                setSheetState(() {
                  errorText = '종료 시간이 시작 시간보다 늦어야 합니다.';
                });
                return;
              }
              setState(() {
                _startHour = startHour;
                _endHour = endHour;
              });
              _saveLocalState();
              Navigator.of(context).pop();
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '주간 표시 시간',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: startHour,
                          decoration: const InputDecoration(labelText: '시작'),
                          items:
                              List.generate(8, (index) => index + 6).map((
                                hour,
                              ) {
                                return DropdownMenuItem<int>(
                                  value: hour,
                                  child: Text('${_hourLabel(hour)}시'),
                                );
                              }).toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setSheetState(() {
                              startHour = value;
                              errorText = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: endHour,
                          decoration: const InputDecoration(labelText: '종료'),
                          items:
                              List.generate(13, (index) => index + 12).map((
                                hour,
                              ) {
                                return DropdownMenuItem<int>(
                                  value: hour,
                                  child: Text(
                                    hour == 24 ? '24시 (자정)' : '$hour시',
                                  ),
                                );
                              }).toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setSheetState(() {
                              endHour = value;
                              errorText = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: save,
                      icon: const Icon(Icons.check),
                      label: const Text('저장'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAgendaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggle(ScheduleItem item, bool? value) {
              _setItemDone(item, value);
              setSheetState(() {});
            }

            void delete(ScheduleItem item) {
              _deleteItem(item);
              setSheetState(() {});
            }

            return _AgendaSheet(
              items: _items,
              onToggleDone: toggle,
              onDelete: delete,
            );
          },
        );
      },
    );
  }

  Future<void> _openDaySheet(DateTime day) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggle(ScheduleItem item, bool? value) {
              _setItemDone(item, value);
              setSheetState(() {});
            }

            void delete(ScheduleItem item) {
              _deleteItem(item);
              setSheetState(() {});
            }

            void addForDay() {
              Navigator.of(context).pop();
              Future<void>.microtask(() {
                if (mounted) {
                  _openScheduleSheet(
                    type: ScheduleType.oneTime,
                    date: day,
                    weekday: day.weekday,
                  );
                }
              });
            }

            void editItem(ScheduleItem item) {
              Navigator.of(context).pop();
              Future<void>.microtask(() {
                if (mounted) {
                  _openScheduleSheet(item: item);
                }
              });
            }

            return _DaySheet(
              day: day,
              items: _itemsOn(day),
              onToggleDone: toggle,
              onDelete: delete,
              onEdit: editItem,
              onAdd: addForDay,
            );
          },
        );
      },
    );
  }

  Future<void> _openItemDetailSheet(ScheduleItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggle(bool? value) {
              _setItemDone(item, value);
              setSheetState(() {});
            }

            void delete() {
              _deleteItem(item);
              Navigator.of(context).pop();
            }

            void edit() {
              Navigator.of(context).pop();
              Future<void>.microtask(() {
                if (mounted) {
                  _openScheduleSheet(item: item);
                }
              });
            }

            return _ItemDetailSheet(
              item: item,
              onToggleDone: toggle,
              onEdit: edit,
              onDelete: delete,
            );
          },
        );
      },
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.yearLabel,
    required this.titleLabel,
    required this.subtitleLabel,
    required this.showSettings,
    required this.onAdd,
    required this.onSettings,
    required this.onList,
  });

  final String yearLabel;
  final String titleLabel;
  final String subtitleLabel;
  final bool showSettings;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                yearLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFE84B43),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                titleLabel,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF23262F),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitleLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B93A1),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _HeaderIconButton(
          tooltip: '일정 추가',
          icon: Icons.add_box_outlined,
          onPressed: onAdd,
        ),
        if (showSettings) ...[
          const SizedBox(width: 10),
          _HeaderIconButton(
            tooltip: '시간표 설정',
            icon: Icons.settings_outlined,
            onPressed: onSettings,
          ),
        ],
        const SizedBox(width: 10),
        _HeaderIconButton(
          tooltip: '전체 일정',
          icon: Icons.format_list_bulleted,
          onPressed: onList,
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 27),
        padding: EdgeInsets.zero,
        color: const Color(0xFF2C3038),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.viewMode,
    required this.rangeLabel,
    required this.onViewChanged,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final ViewMode viewMode;
  final String rangeLabel;
  final ValueChanged<ViewMode> onViewChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SegmentedButton<ViewMode>(
          segments: const [
            ButtonSegment<ViewMode>(value: ViewMode.week, label: Text('주간')),
            ButtonSegment<ViewMode>(value: ViewMode.month, label: Text('월간')),
          ],
          selected: {viewMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onViewChanged(selection.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
              Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _NavIconButton(
                icon: Icons.chevron_left,
                tooltip: '이전',
                onTap: onPrev,
              ),
              Flexible(
                child: GestureDetector(
                  onTap: onToday,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      rangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF3A3F4B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              _NavIconButton(
                icon: Icons.chevron_right,
                tooltip: '다음',
                onTap: onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 24),
        padding: EdgeInsets.zero,
        color: const Color(0xFF667085),
      ),
    );
  }
}

class _TimetableView extends StatelessWidget {
  const _TimetableView({
    required this.items,
    required this.weekStart,
    required this.today,
    required this.startHour,
    required this.endHour,
    required this.onSlotTap,
    required this.onItemTap,
  });

  static const double _headerHeight = 44;
  static const double _timeRailWidth = 28;
  static const int _dayCount = 7;
  static const double _bannerRowHeight = 22;

  final List<ScheduleItem> items;
  final DateTime weekStart;
  final DateTime today;
  final int startHour;
  final int endHour;
  final void Function(int weekday, DateTime date, int hour) onSlotTap;
  final ValueChanged<ScheduleItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = constraints.maxWidth < 420 ? 40.0 : 52.0;
        final dayWidth = math.max(
          48.0,
          (constraints.maxWidth - _timeRailWidth) / _dayCount,
        );
        final width = _timeRailWidth + dayWidth * _dayCount;
        final hourCount = endHour - startHour;
        // 여러 날 일정은 요일 헤더 아래 배너 줄로 표시한다.
        final bannerPlacements = _bannerPlacements();
        final laneCount =
            bannerPlacements.isEmpty
                ? 0
                : bannerPlacements
                        .map((placement) => placement.lane)
                        .reduce(math.max) +
                    1;
        final bannerAreaHeight =
            laneCount == 0 ? 0.0 : laneCount * _bannerRowHeight + 4;
        final gridTop = _headerHeight + bannerAreaHeight;
        final height = gridTop + rowHeight * hourCount;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E8EE)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TimetableGridPainter(
                          startHour: startHour,
                          endHour: endHour,
                          rowHeight: rowHeight,
                          timeRailWidth: _timeRailWidth,
                          dayWidth: dayWidth,
                          dayCount: _dayCount,
                          headerHeight: gridTop,
                        ),
                      ),
                    ),
                    for (var index = 0; index < _dayCount; index++)
                      _buildDayHeader(context, index, dayWidth),
                    for (var index = 0; index < hourCount; index++)
                      Positioned(
                        left: 0,
                        top: gridTop + rowHeight * index + 5,
                        width: _timeRailWidth - 5,
                        child: Text(
                          _hourLabel(startHour + index),
                          textAlign: TextAlign.right,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF9AA2AF),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    for (var day = 0; day < _dayCount; day++)
                      for (var hour = 0; hour < hourCount; hour++)
                        Positioned(
                          left: _timeRailWidth + dayWidth * day,
                          top: gridTop + rowHeight * hour,
                          width: dayWidth,
                          height: rowHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              final date = weekStart.add(Duration(days: day));
                              onSlotTap(date.weekday, date, startHour + hour);
                            },
                          ),
                        ),
                    for (final placement in bannerPlacements)
                      _buildBanner(
                        context: context,
                        placement: placement,
                        dayWidth: dayWidth,
                      ),
                    for (var day = 0; day < _dayCount; day++)
                      for (final item in _itemsForColumn(day))
                        _buildPositionedBlock(
                          item: item,
                          dayIndex: day,
                          dayWidth: dayWidth,
                          rowHeight: rowHeight,
                          gridTop: gridTop,
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayHeader(BuildContext context, int index, double dayWidth) {
    final date = weekStart.add(Duration(days: index));
    final isToday = _isSameDate(date, today);
    final weekend = date.weekday == DateTime.saturday;
    final sunday = date.weekday == DateTime.sunday;
    final color =
        isToday
            ? const Color(0xFFE84B43)
            : sunday
            ? const Color(0xFFE07A74)
            : weekend
            ? const Color(0xFF6E8FD6)
            : const Color(0xFF8B93A1);

    return Positioned(
      left: _timeRailWidth + dayWidth * index,
      top: 0,
      width: dayWidth,
      height: _headerHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _weekdayLabel(date.weekday),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 20,
            height: 18,
            alignment: Alignment.center,
            decoration:
                isToday
                    ? const BoxDecoration(
                      color: Color(0xFFE84B43),
                      shape: BoxShape.circle,
                    )
                    : null,
            child: Text(
              '${date.day}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isToday ? Colors.white : const Color(0xFFAEB4BF),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Iterable<ScheduleItem> _itemsForColumn(int dayIndex) {
    final date = weekStart.add(Duration(days: dayIndex));
    final startMinutes = startHour * 60;
    final endMinutes = endHour * 60;
    return items.where((item) {
      return !item.isMultiDay &&
          item.occursOn(date) &&
          item.endMinutes > startMinutes &&
          item.startMinutes < endMinutes;
    });
  }

  /// 이번 주에 걸치는 여러 날 일정들을 겹치지 않는 줄(lane)에 배치한다.
  List<_BannerPlacement> _bannerPlacements() {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final multiDayItems =
        items.where((item) {
            if (!item.isMultiDay) {
              return false;
            }
            final start = _dateOnly(item.date!);
            return !item.endDate!.isBefore(weekStart) &&
                !start.isAfter(weekEnd);
          }).toList()
          ..sort((a, b) {
            final startCompare = a.date!.compareTo(b.date!);
            if (startCompare != 0) return startCompare;
            return b.endDate!.compareTo(a.endDate!); // 긴 일정 먼저
          });

    final placements = <_BannerPlacement>[];
    final laneEnds = <DateTime>[];
    for (final item in multiDayItems) {
      final start = _dateOnly(item.date!);
      final clippedStart = start.isBefore(weekStart) ? weekStart : start;
      final clippedEnd =
          item.endDate!.isAfter(weekEnd) ? weekEnd : item.endDate!;
      final startIndex = clippedStart.difference(weekStart).inDays;
      final span = clippedEnd.difference(clippedStart).inDays + 1;

      var lane = laneEnds.indexWhere((end) => end.isBefore(clippedStart));
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(clippedEnd);
      } else {
        laneEnds[lane] = clippedEnd;
      }
      placements.add(
        _BannerPlacement(
          item: item,
          lane: lane,
          startIndex: startIndex,
          span: span,
          continuesBefore: start.isBefore(weekStart),
          continuesAfter: item.endDate!.isAfter(weekEnd),
        ),
      );
    }
    return placements;
  }

  Widget _buildBanner({
    required BuildContext context,
    required _BannerPlacement placement,
    required double dayWidth,
  }) {
    final item = placement.item;
    final alpha = item.done ? 130 : 235;
    return Positioned(
      left: _timeRailWidth + dayWidth * placement.startIndex + 2,
      top: _headerHeight + _bannerRowHeight * placement.lane + 1,
      width: dayWidth * placement.span - 4,
      height: _bannerRowHeight - 3,
      child: GestureDetector(
        onTap: () => onItemTap(item),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: item.color.withAlpha(alpha),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            '${placement.continuesBefore ? '◂ ' : ''}${item.title}'
            '${placement.continuesAfter ? ' ▸' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              decoration:
                  item.done ? TextDecoration.lineThrough : TextDecoration.none,
              decorationColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPositionedBlock({
    required ScheduleItem item,
    required int dayIndex,
    required double dayWidth,
    required double rowHeight,
    required double gridTop,
  }) {
    final gridStart = startHour * 60;
    final gridEnd = endHour * 60;
    final clippedStart = math.max(item.startMinutes, gridStart);
    final clippedEnd = math.min(item.endMinutes, gridEnd);
    final top = gridTop + ((clippedStart - gridStart) / 60.0) * rowHeight;
    final height = math.max(
      30.0,
      ((clippedEnd - clippedStart) / 60.0) * rowHeight,
    );

    return Positioned(
      left: _timeRailWidth + dayWidth * dayIndex + 1,
      top: top + 1,
      width: dayWidth - 1,
      height: height - 1,
      child: _TimetableBlock(
        item: item,
        height: height,
        onTap: () => onItemTap(item),
      ),
    );
  }
}

/// 주간 뷰 배너 한 개의 배치 정보.
class _BannerPlacement {
  const _BannerPlacement({
    required this.item,
    required this.lane,
    required this.startIndex,
    required this.span,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final ScheduleItem item;
  final int lane;
  final int startIndex;
  final int span;

  /// 일정이 이번 주 이전/이후로 이어지는지 여부(화살표 표시용).
  final bool continuesBefore;
  final bool continuesAfter;
}

class _TimetableGridPainter extends CustomPainter {
  const _TimetableGridPainter({
    required this.startHour,
    required this.endHour,
    required this.rowHeight,
    required this.timeRailWidth,
    required this.dayWidth,
    required this.dayCount,
    required this.headerHeight,
  });

  final int startHour;
  final int endHour;
  final double rowHeight;
  final double timeRailWidth;
  final double dayWidth;
  final int dayCount;
  final double headerHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint =
        Paint()
          ..color = const Color(0xFFE9EDF2)
          ..strokeWidth = 1;
    final headerPaint =
        Paint()
          ..color = const Color(0xFFFDFDFE)
          ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, headerHeight), headerPaint);

    canvas.drawLine(
      Offset(0, headerHeight),
      Offset(size.width, headerHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(timeRailWidth, 0),
      Offset(timeRailWidth, size.height),
      gridPaint,
    );

    for (var day = 0; day <= dayCount; day++) {
      final x = timeRailWidth + dayWidth * day;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (var hour = 0; hour <= endHour - startHour; hour++) {
      final y = headerHeight + rowHeight * hour;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimetableGridPainter oldDelegate) {
    return oldDelegate.startHour != startHour ||
        oldDelegate.endHour != endHour ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.timeRailWidth != timeRailWidth ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.dayCount != dayCount ||
        oldDelegate.headerHeight != headerHeight;
  }
}

class _TimetableBlock extends StatelessWidget {
  const _TimetableBlock({
    required this.item,
    required this.height,
    required this.onTap,
  });

  final ScheduleItem item;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = height < 52;
    final titleLines = height < 76 ? 2 : 3;
    final textColor = Colors.white.withAlpha(item.done ? 190 : 255);
    final oneTime = item.type == ScheduleType.oneTime;

    return Material(
      color: item.color.withAlpha(item.done ? 145 : 245),
      borderRadius: BorderRadius.circular(2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          decoration:
              oneTime
                  ? BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withAlpha(220),
                        width: 3,
                      ),
                    ),
                  )
                  : null,
          padding: EdgeInsets.fromLTRB(oneTime ? 4 : 5, compact ? 4 : 5, 4, 3),
          child:
              compact
                  ? Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: textColor,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      decoration:
                          item.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                      decorationColor: Colors.white,
                    ),
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: titleLines,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor,
                          height: 1.04,
                          fontWeight: FontWeight.w900,
                          decoration:
                              item.done
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                          decorationColor: Colors.white,
                        ),
                      ),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withAlpha(
                              item.done ? 165 : 230,
                            ),
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.today,
    required this.itemsOn,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime today;
  final List<ScheduleItem> Function(DateTime day) itemsOn;
  final ValueChanged<DateTime> onDayTap;

  static const List<String> _weekdayHeaders = [
    '일',
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
  ];

  @override
  Widget build(BuildContext context) {
    final days = _monthGridDays(month);
    final weeks = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8EE)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          _weekdayHeaders[i],
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color:
                                i == 0
                                    ? const Color(0xFFE07A74)
                                    : i == 6
                                    ? const Color(0xFF6E8FD6)
                                    : const Color(0xFF8B93A1),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1, color: Color(0xFFE9EDF2)),
            Expanded(
              child: Column(
                children: [
                  for (final week in weeks)
                    Expanded(
                      child: Row(
                        children: [
                          for (final day in week)
                            Expanded(
                              child: _MonthDayCell(
                                day: day,
                                inMonth: day.month == month.month,
                                isToday: _isSameDate(day, today),
                                items: itemsOn(day),
                                onTap: () => onDayTap(day),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.items,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<ScheduleItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sunday = day.weekday == DateTime.sunday;
    final saturday = day.weekday == DateTime.saturday;
    final numberColor =
        !inMonth
            ? const Color(0xFFCDD2DA)
            : sunday
            ? const Color(0xFFE07A74)
            : saturday
            ? const Color(0xFF6E8FD6)
            : const Color(0xFF3A3F4B);

    const maxChips = 3;
    final visible = items.take(maxChips).toList();
    final extra = items.length - visible.length;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: Color(0xFFEFF2F6)),
            bottom: BorderSide(color: Color(0xFFEFF2F6)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration:
                    isToday
                        ? const BoxDecoration(
                          color: Color(0xFFE84B43),
                          shape: BoxShape.circle,
                        )
                        : null,
                child: Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isToday ? Colors.white : numberColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in visible)
                        _MonthChip(item: item, dimmed: !inMonth),
                      if (extra > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '+$extra',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF9AA2AF),
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.item, required this.dimmed});

  final ScheduleItem item;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final alpha = dimmed ? 90 : (item.done ? 130 : 235);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: item.color.withAlpha(alpha),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 9,
          height: 1.1,
          decoration:
              item.done ? TextDecoration.lineThrough : TextDecoration.none,
          decorationColor: Colors.white,
        ),
      ),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({required this.items});

  final List<ScheduleItem> items;

  @override
  Widget build(BuildContext context) {
    final present =
        ScheduleCategory.values
            .where((c) => items.any((item) => item.category == c))
            .toList();
    if (present.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: present.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = present[index];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                category.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF8B93A1),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleFormSheet extends StatefulWidget {
  const _ScheduleFormSheet({
    required this.initialItem,
    required this.initialType,
    required this.initialWeekdays,
    required this.initialDate,
    required this.initialEndDate,
    required this.initialStart,
    required this.initialEnd,
    required this.onSave,
  });

  final ScheduleItem? initialItem;
  final ScheduleType initialType;
  final List<int> initialWeekdays;
  final DateTime initialDate;
  final DateTime? initialEndDate;
  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;
  final ValueChanged<ScheduleItem> onSave;

  @override
  State<_ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends State<_ScheduleFormSheet> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late ScheduleType _type;
  late Set<int> _weekdays;
  late DateTime _date;
  late DateTime _endDate;
  var _category = ScheduleCategory.lecture;
  var _start = const TimeOfDay(hour: 9, minute: 0);
  var _end = const TimeOfDay(hour: 10, minute: 0);
  String? _timeError;
  String? _weekdayError;

  /// 종료일이 시작일보다 뒤면 여러 날(종일) 일정이다.
  bool get _isMultiDay =>
      _type == ScheduleType.oneTime && _endDate.isAfter(_date);

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _type = widget.initialType;
    _weekdays = _normalizeWeekdays(widget.initialWeekdays).toSet();
    _date = _dateOnly(widget.initialDate);
    _endDate = _dateOnly(widget.initialEndDate ?? widget.initialDate);
    if (_endDate.isBefore(_date)) {
      _endDate = _date;
    }
    _start = widget.initialStart;
    _end = widget.initialEnd;
    if (item != null) {
      _titleController.text = item.title;
      _noteController.text = item.note;
      _category = item.category;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialItem == null ? '일정 추가' : '일정 수정',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              SegmentedButton<ScheduleType>(
                segments: const [
                  ButtonSegment<ScheduleType>(
                    value: ScheduleType.fixed,
                    label: Text('고정 (매주 반복)'),
                    icon: Icon(Icons.repeat, size: 18),
                  ),
                  ButtonSegment<ScheduleType>(
                    value: ScheduleType.oneTime,
                    label: Text('일회성'),
                    icon: Icon(Icons.event_available_outlined, size: 18),
                  ),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    if (_type == ScheduleType.fixed) {
                      // 기존 선택이 없으면 날짜의 요일을 기본값으로 사용.
                      _weekdays =
                          _weekdays.isEmpty ? <int>{_date.weekday} : _weekdays;
                    } else {
                      // 요일만 골랐다면 해당 요일의 가까운 날짜로 맞춤.
                      _date = _nextDateForWeekday(_primaryWeekday);
                    }
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '제목',
                  prefixIcon: Icon(Icons.event_note_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '제목을 입력하세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (_type == ScheduleType.fixed)
                _WeekdaySelector(
                  weekdays: _weekdays,
                  errorText: _weekdayError,
                  onChanged: (weekdays) {
                    setState(() {
                      _weekdays = weekdays;
                      _weekdayError = null;
                    });
                  },
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _DateButton(
                        label: '시작일',
                        date: _date,
                        compact: true,
                        onPressed: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateButton(
                        label: '종료일',
                        date: _endDate,
                        compact: true,
                        onPressed: _pickEndDate,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ScheduleCategory>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: '분류',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                items:
                    ScheduleCategory.values.map((category) {
                      return DropdownMenuItem<ScheduleCategory>(
                        value: category,
                        child: Row(
                          children: [
                            Icon(
                              category.icon,
                              size: 18,
                              color: category.color,
                            ),
                            const SizedBox(width: 8),
                            Text(category.label),
                          ],
                        ),
                      );
                    }).toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _category = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_isMultiDay)
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF8B93A1),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '여러 날 일정은 종일 일정으로 표시됩니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8B93A1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: '시작',
                        time: _start,
                        onPressed:
                            () => _pickTime(
                              initial: _start,
                              onPicked: (picked) => _start = picked,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeButton(
                        label: '종료',
                        time: _end,
                        onPressed:
                            () => _pickTime(
                              initial: _end,
                              onPicked: (picked) => _end = picked,
                            ),
                      ),
                    ),
                  ],
                ),
              if (_timeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _timeError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '장소/메모',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        onPicked(picked);
        _timeError = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _date = _dateOnly(picked);
        _weekdays = <int>{_date.weekday};
        if (_endDate.isBefore(_date)) {
          _endDate = _date;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_date) ? _date : _endDate,
      firstDate: _date,
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _endDate = _dateOnly(picked);
      });
    }
  }

  int get _primaryWeekday {
    if (_weekdays.isEmpty) {
      return _date.weekday;
    }
    final weekdays = _weekdays.toList()..sort();
    return weekdays.first;
  }

  DateTime _nextDateForWeekday(int weekday) {
    final today = _dateOnly(DateTime.now());
    final diff = (weekday - today.weekday + 7) % 7;
    return today.add(Duration(days: diff));
  }

  void _save() {
    final validForm = _formKey.currentState?.validate() ?? false;
    if (_type == ScheduleType.fixed && _weekdays.isEmpty) {
      setState(() {
        _weekdayError = '반복 요일을 하나 이상 선택하세요.';
      });
      return;
    }
    // 여러 날(종일) 일정은 시각을 쓰지 않으므로 시간 검증을 건너뛴다.
    if (!_isMultiDay && _minutesOf(_end) <= _minutesOf(_start)) {
      setState(() {
        _timeError = '종료 시간이 시작 시간보다 늦어야 합니다.';
      });
      return;
    }
    if (!validForm) {
      return;
    }

    final reuseColor =
        widget.initialItem?.category == _category
            ? widget.initialItem?.color
            : null;

    widget.onSave(
      ScheduleItem(
        id:
            widget.initialItem?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        type: _type,
        weekdays:
            _type == ScheduleType.fixed ? _normalizeWeekdays(_weekdays) : null,
        date: _type == ScheduleType.oneTime ? _date : null,
        endDate: _isMultiDay ? _endDate : null,
        start: _start,
        end: _end,
        category: _category,
        color: reuseColor,
        note: _noteController.text.trim(),
        done: widget.initialItem?.done ?? false,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({
    required this.weekdays,
    required this.onChanged,
    this.errorText,
  });

  final Set<int> weekdays;
  final ValueChanged<Set<int>> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final selected =
        weekdays
            .where(
              (weekday) =>
                  weekday >= DateTime.monday && weekday <= DateTime.sunday,
            )
            .toSet();

    return InputDecorator(
      decoration: InputDecoration(
        labelText: '반복 요일',
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        errorText: errorText,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var value = DateTime.monday; value <= DateTime.sunday; value++)
            FilterChip(
              label: Text(_weekdayLabel(value)),
              selected: selected.contains(value),
              showCheckmark: false,
              onSelected: (checked) {
                final next = Set<int>.of(selected);
                if (checked) {
                  next.add(value);
                } else {
                  next.remove(value);
                }
                onChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPressed,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.schedule),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: const Color(0xFF667085)),
            ),
            Text(
              _formatTime(time),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0xFFD9DFE7)),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.date,
    required this.onPressed,
    this.label = '날짜',
    this.compact = false,
  });

  final DateTime date;
  final VoidCallback onPressed;
  final String label;

  /// 좁은 자리(시작일/종료일 나란히)용 짧은 날짜 표기.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF667085),
                  ),
                ),
                Text(
                  compact
                      ? '${date.year}.${date.month}.${date.day} (${_weekdayLabel(date.weekday)})'
                      : _formatFullDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: const BorderSide(color: Color(0xFFD9DFE7)),
        ),
      ),
    );
  }
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({
    required this.day,
    required this.items,
    required this.onToggleDone,
    required this.onDelete,
    required this.onEdit,
    required this.onAdd,
  });

  final DateTime day;
  final List<ScheduleItem> items;
  final void Function(ScheduleItem item, bool? value) onToggleDone;
  final ValueChanged<ScheduleItem> onDelete;
  final ValueChanged<ScheduleItem> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatFullDate(day),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '이 날에 일정 추가',
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline),
                color: const Color(0xFFE84B43),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '등록된 일정이 없습니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF9AA2AF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _DayRow(
                    item: item,
                    onToggleDone: (value) => onToggleDone(item, value),
                    onEdit: () => onEdit(item),
                    onDelete: () => onDelete(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.item,
    required this.onToggleDone,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleItem item;
  final ValueChanged<bool?> onToggleDone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: item.done,
            onChanged: onToggleDone,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          decoration:
                              item.done
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TypeBadge(type: item.type),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.isMultiDay ? '종일 · ${_formatDate(item.date!)} ~ ${_formatDate(item.endDate!)}' : '${_formatTime(item.start)}-${_formatTime(item.end)}'}${item.note.isEmpty ? '' : ' · ${item.note}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '수정',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: const Color(0xFF667085),
          ),
          IconButton(
            tooltip: '삭제',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: const Color(0xFF667085),
          ),
        ],
      ),
    );
  }
}

class _AgendaSheet extends StatelessWidget {
  const _AgendaSheet({
    required this.items,
    required this.onToggleDone,
    required this.onDelete,
  });

  final List<ScheduleItem> items;
  final void Function(ScheduleItem item, bool? value) onToggleDone;
  final ValueChanged<ScheduleItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final fixedItems =
        items.where((item) => item.type == ScheduleType.fixed).toList()
          ..sort((a, b) {
            final dayCompare = a.weekday.compareTo(b.weekday);
            if (dayCompare != 0) return dayCompare;
            return a.startMinutes.compareTo(b.startMinutes);
          });
    final oneTimeItems =
        items.where((item) => item.type == ScheduleType.oneTime).toList()
          ..sort((a, b) {
            final dateCompare = a.date!.compareTo(b.date!);
            if (dateCompare != 0) return dateCompare;
            return a.startMinutes.compareTo(b.startMinutes);
          });

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '전체 일정',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: ListView(
              shrinkWrap: true,
              children: [
                _AgendaSectionLabel(
                  icon: Icons.repeat,
                  label: '고정 시간표 (${fixedItems.length})',
                ),
                if (fixedItems.isEmpty)
                  const _AgendaEmpty()
                else
                  for (final item in fixedItems)
                    _AgendaRow(
                      item: item,
                      onToggleDone: (value) => onToggleDone(item, value),
                      onDelete: () => onDelete(item),
                    ),
                const SizedBox(height: 14),
                _AgendaSectionLabel(
                  icon: Icons.event_available_outlined,
                  label: '일회성 스케줄 (${oneTimeItems.length})',
                ),
                if (oneTimeItems.isEmpty)
                  const _AgendaEmpty()
                else
                  for (final item in oneTimeItems)
                    _AgendaRow(
                      item: item,
                      onToggleDone: (value) => onToggleDone(item, value),
                      onDelete: () => onDelete(item),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSectionLabel extends StatelessWidget {
  const _AgendaSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8B93A1)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF8B93A1),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaEmpty extends StatelessWidget {
  const _AgendaEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        '없음',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFAEB4BF),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.item,
    required this.onToggleDone,
    required this.onDelete,
  });

  final ScheduleItem item;
  final ValueChanged<bool?> onToggleDone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when =
        item.type == ScheduleType.fixed
            ? '매주 ${_formatWeekdays(item.weekdays)} ${_formatTime(item.start)}-${_formatTime(item.end)}'
            : item.isMultiDay
            ? '${_formatDate(item.date!)}(${_weekdayLabel(item.date!.weekday)}) ~ ${_formatDate(item.endDate!)}(${_weekdayLabel(item.endDate!.weekday)}) 종일'
            : '${_formatDate(item.date!)}(${_weekdayLabel(item.weekday)}) ${_formatTime(item.start)}-${_formatTime(item.end)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: item.done,
            onChanged: onToggleDone,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    decoration:
                        item.done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when${item.note.isEmpty ? '' : ' · ${item.note}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '삭제',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final ScheduleType type;

  @override
  Widget build(BuildContext context) {
    final fixed = type == ScheduleType.fixed;
    final color = fixed ? const Color(0xFF79CDBF) : const Color(0xFFEFA45E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ItemDetailSheet extends StatelessWidget {
  const _ItemDetailSheet({
    required this.item,
    required this.onToggleDone,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleItem item;
  final ValueChanged<bool?> onToggleDone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when =
        item.type == ScheduleType.fixed
            ? '매주 ${_formatWeekdays(item.weekdays, includeSuffix: true)} ${_formatTime(item.start)}-${_formatTime(item.end)}'
            : item.isMultiDay
            ? '${_formatFullDate(item.date!)} ~ ${_formatFullDate(item.endDate!)} · ${item.dayCount}일간'
            : '${_formatFullDate(item.date!)} ${_formatTime(item.start)}-${_formatTime(item.end)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const SizedBox(width: 14, height: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _TypeBadge(type: item.type),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            when,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (item.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.note,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          CheckboxListTile(
            value: item.done,
            onChanged: onToggleDone,
            contentPadding: EdgeInsets.zero,
            title: const Text('완료'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('수정'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('삭제'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _weekdayLabel(int weekday) {
  const labels = {
    DateTime.monday: '월',
    DateTime.tuesday: '화',
    DateTime.wednesday: '수',
    DateTime.thursday: '목',
    DateTime.friday: '금',
    DateTime.saturday: '토',
    DateTime.sunday: '일',
  };
  return labels[weekday] ?? '';
}

String _formatWeekdays(Iterable<int> weekdays, {bool includeSuffix = false}) {
  return _normalizeWeekdays(weekdays)
      .map((weekday) {
        final label = _weekdayLabel(weekday);
        return includeSuffix ? '$label요일' : label;
      })
      .join(', ');
}

String _hourLabel(int hour) {
  if (hour == 0 || hour == 24) {
    return '12';
  }
  if (hour <= 12) {
    return '$hour';
  }
  return '$hour';
}

String _formatTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDate(DateTime date) {
  return '${date.month}/${date.day}';
}

String _formatFullDate(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일 (${_weekdayLabel(date.weekday)})';
}

int _minutesOf(TimeOfDay time) {
  return time.hour * 60 + time.minute;
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime _startOfWeek(DateTime date) {
  final d = _dateOnly(date);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

String _storageDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// 일회성 일정에서 시작일보다 뒤인 경우에만 종료일을 유지한다.
DateTime? _normalizeEndDate(ScheduleType type, DateTime? date, DateTime? end) {
  if (type != ScheduleType.oneTime || date == null || end == null) {
    return null;
  }
  final endOnly = _dateOnly(end);
  return endOnly.isAfter(_dateOnly(date)) ? endOnly : null;
}

DateTime? _dateFromStorage(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return null;
  }
  return _dateOnly(parsed);
}

TimeOfDay _timeFromMinutes(int minutes) {
  final safeMinutes = minutes.clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: safeMinutes ~/ 60, minute: safeMinutes % 60);
}

int _validWeekday(int weekday) {
  if (weekday < DateTime.monday || weekday > DateTime.sunday) {
    return DateTime.monday;
  }
  return weekday;
}

List<int> _normalizeWeekdays(Iterable<int> weekdays) {
  final values = weekdays.map(_validWeekday).toSet().toList()..sort();
  if (values.isEmpty) {
    return <int>[DateTime.monday];
  }
  return values;
}

int _jsonInt(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

List<int> _jsonWeekdays(Object? value, {required List<int> fallback}) {
  if (value is Iterable) {
    final weekdays = <int>[];
    for (final item in value) {
      if (item is int) {
        weekdays.add(item);
      } else if (item is num) {
        weekdays.add(item.toInt());
      } else if (item is String) {
        final parsed = int.tryParse(item);
        if (parsed != null) {
          weekdays.add(parsed);
        }
      }
    }
    if (weekdays.isNotEmpty) {
      return _normalizeWeekdays(weekdays);
    }
  }
  return _normalizeWeekdays(fallback);
}

String _jsonString(Object? value, String fallback) {
  if (value is String) {
    return value;
  }
  return fallback;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

/// 월간 달력 격자(일요일 시작, 6주 42칸)에 표시할 날짜 목록.
List<DateTime> _monthGridDays(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final leading = first.weekday % 7; // 일요일(7)->0, 월(1)->1 ... 토(6)->6
  final start = first.subtract(Duration(days: leading));
  return List.generate(42, (index) => start.add(Duration(days: index)));
}
