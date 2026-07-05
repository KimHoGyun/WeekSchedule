# Week Schedule

iOS, Android, Web에서 동작하는 Flutter 기반 주간 일정표 앱입니다.

## 기능

- 요일별 일정 요약
- 시간대별 주간 시간표 보기
- 빈 시간 칸을 눌러 일정 추가
- 일정 수정, 완료 표시, 삭제
- 수업, 근로, 글쓰기, 실습, 교양, 개인 분류 색상
- 모바일/데스크톱 반응형 레이아웃

## 실행

```bash
flutter run
```

웹으로 확인하려면:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

## 검증

```bash
flutter analyze
flutter test
```
