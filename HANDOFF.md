# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-06 (locus 리브랜딩 직후) · **기준**: 워킹 트리 (리브랜딩 커밋 대기)
- **상태**: v0.1.0 → v0.3.0 + **이름 확정 `locus`**. 코드 리뷰 + P0(실전 검증) +
  P1(동적 스냅샷) + P2(문서·버전·이름) 완료. 3커밋+태그 v0.3.0 완료 후 리브랜딩 반영 중.
  테스트 50개 그린. 푸시/공개는 **사용자 승인 전까지 금지**.

## 이번 세션에서 완료된 것

### 코드 리뷰 (구조·성능·보안·정확성)
- 결함 3건 수정: `--help` 버전 하드코딩(단일 소스 위반), git option 인젝션
  (`--ref --output=...` → 거부 + `--end-of-options`), GUI 앱 PATH 문제
  (`/usr/bin/git` 우선). 회귀 테스트 동반.
- 잔여 관찰(수정 안 함, 기록용): 심볼 앵커는 extension에서 타입명을 못 얻음
  (v0.1부터 동일), `Glob` `**` 중첩의 이론적 백트래킹, MCP 무제한 라인 버퍼,
  `SourceTree` 심볼릭 링크 순환 무방어(실전 리스크 낮음).

### P0 — 실전 검증 (element-x-ios, Swift 1,385파일)
- **치명 발견**: 식별자 콜사이트 158곳 중 리터럴 1곳 — 나머지는 전부 상수
  (`enum A11yIdentifiers` 네임스페이스). 상수 해석 없이 elements 0개.
- **v0.2 기능으로 해결**: `ConstantTable` — struct/enum 멤버 리터럴, String
  raw-value enum(암시 케이스명), `static let ns = Type()` 별칭, 백틱 멤버,
  레이블드 인자(`accessibilityIdentifier:` 파라미터), 테스트의 상수 참조.
  충돌 선언은 그 항목 버림(모호 > 오답).
- **노이즈 실측·조정**: orphan 243→6 (파일명·번들ID 노이즈 → UI-쿼리 위치로 제한),
  missing 1,349→424 (비인터랙티브 종류 제외 — Text/Image/Label는 라벨 매칭 가능).
- **성능**: 릴리스 크롤 4.6초/1,385파일. 병렬화 불필요.
- **정밀도**: 표본 검수 전부 정확(오추출 0건 확인). 잔차 12곳은 동적 형태
  (함수형 상수, 계산 속성+switch — `session_verification-*` 사례)로 정당한 잔차.

### P1 — v0.3 동적 스냅샷
- `Snapshot.swift`: 덤프 파싱(배열/`{elements:[]}` + 필드 별칭 idb `AX*` 흡수),
  `SnapshotMatcher`(identifier high / 고유 라벨 medium·kind 불일치 low /
  중복 라벨 매칭 안 함), 잔차(화면상 미식별·미매칭 id·unseen·커버리지).
- CLI `snapshot <dump.json|-> [--udid]` (idb 캡처는 선택 의존, 미설치 시 안내).
- MCP 5번째 툴 `match_snapshot(dump)` — 에이전트 interop 경로.
- E2E 스모크: Element X 맵 + 시뮬레이션 덤프 → 매칭·잔차 정상.

### P2 — 공개 준비 (문서·버전)
- 버전 0.3.0, CHANGELOG(0.2.0+0.3.0), README(스냅샷 섹션·한계 갱신·실전 검증
  수치·로드맵), AGENTS.md(구조·테스트 수), DemoApp 트랜스크립트 재검증(카운트 불변).

### 이름 확정 — `locus` (2026-09-06, 사용자 결정)
- breadcrumb → locus 전면 리브랜딩: 패키지명, 모듈(`LocusCore`/`LocusCLI`),
  바이너리 `locus`, 맵 디렉터리 `.locus/`, MCP serverInfo, 문서 전부.
  태그라인: "locus — where every UI element lives in source".
- 사유: 검색 유니크성 > 서사 정합(breadcrumb은 웹 검색 오염). 결정 배경은 기획서
  "이름 결정" 섹션. **이름은 이것으로 최종.**

## 다음 세션 할 일 (우선순위)

### P2 잔여 — 공개 gate (사용자 결정 사항)
- 리모트 생성(제안: `locus`, GitHub org 확정 필요)·push → CI 실작동 확인 →
  태그 재정리(리브랜딩 커밋으로 v0.3.0 태그 이동 여부 포함).

### 이후 (v1.x 후보, 우선순위 미정)
- 확장/조건부 컴파일 심볼 앵커(리뷰 관찰), IndexStoreDB 심볼 앵커
- 화면 경계 유추, identifier 코드젠, Android/Kotlin 확장
- 해자 관점(메모리 참조): 정밀도 실증 데이터 축적(저장소 추가 검증),
  Arbigent/XcodeBuildMCP 어댑터 접근, CI 통합 스토리

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 백그라운드 + 폴링 필수.
- **DemoApp에 직접 `git init` 금지** — `Scripts/setup-demo.sh`만 사용.
- **경로 기준계** — 새 비교 로직은 `repoRelativePrefix` 정렬 필수.
  회귀 테스트: `testNestedSourceRootAvoidsCrossModuleFalsePositives`.
- **버전 단일 소스**: `MapFormat.releaseVersion` (현재 "0.3.0").
- **상수 해석 경계**: 타입 이름을 중첩 경로 없이 키로 씀 — 다른 타입이 같은
  이름+멤버를 가지면 해석 생략(README "정직한 한계"에 기록).
- **orphan은 UI-쿼리 위치 한정** — 형태 기반 판별은 실전에서 95% 노이즈였음.
- **idb는 선택 의존** — 코어는 파일/stdin 덤프만으로 성립. idb 미설치 환경
  테스트 불가(이 머신에도 없음) — `--udid` 경로는 설치 후 수동 검증 필요.
- 셸 cwd 잔류 주의 — 항상 `cd`부터.

## 참조

- 기획서/차별화 전략: `기획서.md` · 에이전트 작업 지침: `AGENTS.md` · 사용법: `README.md`
- 실전 검증 대상: element-x-ios (클론 위치 /tmp/locus-p0/ — 휘발성)
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검)와의 접점은 기획서 차별화 표.
