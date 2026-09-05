# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-05 · **기준 커밋**: `cbb490e` (main)
- **상태**: v0.1.0 구현·리뷰·문서 완료. 미공개(리모트 없음). 테스트 30개 그린, release 빌드 검증됨.

## 현재까지 완료된 것 (믿어도 되는 상태)

- SwiftSyntax 크롤러: SwiftUI `.accessibilityIdentifier/Label(...)` 수정자 + UIKit
  `x.accessibilityIdentifier = ...` 대입 추출, 구문 컨텍스트 심볼 앵커(`Type.member`), kind 추정
- 테스트 역색인(식별자 정확 일치) + identifier-shaped 고아 리터럴(orphan) 수집
- 맵 저장소: `.breadcrumb/` 아래 5개 JSON — 원자적 쓰기, 바이트 단위 결정적
- 질의 4종: where-is / what-renders / affected-tests(git diff·--ref·--files) / missing-identifiers
- **경로 기준계 정렬 완료** — 요소(sourceRoot 상대) vs 변경파일(저장소 루트 상대)을
  `Engine.repoRelativePrefix`로 정렬. 형제 모듈 오검출 버그의 회귀 테스트 있음
- MCP stdio 서버 4툴(where_is·what_renders·affected_tests·missing_identifiers), `ping` 지원
- 배포 키트: README·기획서·AGENTS.md·CHANGELOG·MIT·CI yaml·Makefile·Examples/DemoApp(일반 파일 추적)+Scripts/setup-demo.sh
- 커밋 계보: `2b37ae5`(초기, subagent 산출) → `243da0a`(1차: GitDiff 교착, DemoApp gitlink 해소)
  → `2849c5f`(2차: 경로 기준계) → `cbb490e`(문서+버전 상수 단일화)

빠른 상태 재확인: `swift test` (수 초) → README Quickstart(데모는 `Scripts/setup-demo.sh` 후).

## 다음 세션 할 일 (우선순위)

### P0 — 실프로젝트 검증 (신뢰도의 마지막 빈칸)
fixture와 6요소 데모로만 검증했다. 실 iOS 저장소 스케일은 미검증.
1. 실제 오픈소스 SwiftUI/UIKit 앱 저장소 하나를 골라 `crawl` — 크롤 시간·메모리 측정(성능 기준선).
2. 추출 정밀도 육안 검수: identifier가 JSON에 있는 파일을 실제 소스와 대조. 특히
   체인 중간의 modifier(`.font(...).accessibilityIdentifier`), 조건부 뷰, 다중 문장에서의 누락.
3. `missing-identifiers`/`orphans` 출력이 실전에서 유용한지 판정 — 과잉 보고(noise)면
   휴리스틱 조정(`ControlKnowledge` 목록, orphan 판별식).
4. 성능 문제가 보이면 파일 단위 병렬 크롤(순수 함수라 안전)이 첫 후보.

### P1 — v0.3: 동적 스냅샷 결합 (기획서 핵심 과제)
정적 맵과 시뮬레이터 접근성 트리 덤프를 매칭해 "지금 화면의 이 요소 → 소스"를 실시간으로.
첫 결정사항은 **덤프 소스**:
- (a) XCUITest 헬퍼 — 자체 번들, 의존성 없음, 덤프 형식 설계 필요
- (b) `idb ui describe-all`(Meta idb) — 즉시 사용 가능, 외부 도구 의존
추천: (b)로 프로토타입 → 매칭 로직(식별자 직매칭 → 라벨+kind 휴리스틱, confidence 표기)을
코어로 확정한 뒤 (a) 전환 검토. 미매칭 잔차는 "기능"(자동화 부채)으로 승화 — 기획서 §데이터 모델.

### P2 — 공개 준비 (사용자 승인 gate)
- 저장소명 `breadcrumb` 가용성 확인(GitHub/SPM 인덱스) — 범용어라 오염 가능성 있음.
- 리모트 생성·push → CI 실작동 확인(현 CI yaml은 미실행 상태).
- 태그 `v0.1.0`. **푸시/공개는 사용자 결정 사항 — 임의 진행 금지.**

### 이후 (v1.x, 우선순위 미정)
IndexStoreDB 심볼 앵커(구문 기반 한계 해소), identifier 코드젠(문자열 부채 소멸),
화면 경계 유추, Android/Kotlin 확장(제작자 크로스플랫폼 자산).

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 포그라운드로 돌리고 기다리면 세션 타임아웃 사망.
  반드시 백그라운드 실행 + 폴링. (AGENTS.md "명령" 섹션에도 경고 있음)
- **DemoApp에 직접 `git init` 금지** — 부모 저장소 gitlink 회귀(커밋 `243da0a` 히스토리).
  git 데모가 필요하면 `Scripts/setup-demo.sh`만 사용.
- **경로 기준계** — 요소는 sourceRoot 상대, git은 저장소 루트 상대. 새 비교 로직은
  반드시 `repoRelativePrefix` 정렬을 거칠 것. 회귀 테스트:
  `testNestedSourceRootAvoidsCrossModuleFalsePositives`.
- 버전 문자열 단일 소스: `MapFormat.releaseVersion` — CLI·MCP serverInfo·tool 문자열이 전부 파생.
- 심볼 앵커는 구문 컨텍스트 유추(IndexStoreDB 아님) — README "정직한 한계"가 경계선.
  새 한계 발견 시 그 섹션에 기록.
- 셸 cwd가 다른 저장소로 남아 `swift test`를 엉뚱한 패키지에 돌린 전례 — 항상 `cd`부터.

## 참조

- 기획서/차별화 전략: `기획서.md` · 에이전트 작업 지침: `AGENTS.md` · 사용법: `README.md`
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검) — 부검 결과의 화면 귀속에
  이 도구가 쓰이는 접점이 기획서 차별화 표에 명시되어 있음.
