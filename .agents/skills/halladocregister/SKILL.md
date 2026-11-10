---
name: halladocregister
description: Prepare a Halla SPOC records-ledger entry from user-provided values. Use when the user invokes $halladocregister or asks to register a document in the records ledger.
---

# 제주한라대학교 기록물등록대장 입력

## 고정 경로

- 시작 주소는 `https://spoc.halla.ac.kr`로 고정한다.
- 로그인 후 왼쪽 메뉴 **기록물등록대장**을 연다.
- 목록에서 **추가**를 눌러 입력 행을 만든다.
- 주소가 열리지 않거나 화면이 다르면 다른 주소나 메뉴를 임의로 대입하지 말고 멈춰 보고한다.

## 입력 변수

사용자가 요청한 값을 같은 이름의 화면 필드에 입력한다. 누락된 값을 추정하거나 기존 기록에서 복사하지 않는다.

- `production_number`: 생산번호
- `category`: 구분
- `registration_type`: 등록구분
- `production_date`: 생산일자. 사용자가 지정하지 않으면 실행일의 한국 날짜(Asia/Seoul)를 `YYYY-MM-DD`로 입력한다.
- `title`: 제목
- `approver`: 결재권자
- `drafter`: 기안자 또는 담당자
- `recipient_or_sender`: 수신자 또는 발신자
- `source_registration_number`: 생산기관 등록번호
- `attachments`: 첨부 파일

사용자가 값을 제공하지 않은 선택·입력 필드는 건드리지 않는다. 화면에서 필수로 표시된 값이 제공되지 않았으면 해당 값을 묻고 멈춘다. 생산번호를 자동 계산하거나 등록구분을 임의로 선택하지 않는다.

## 로그인과 정보 보호

- 인증정보는 스킬에 저장하지 않는다. 사용자가 현재 실행에서 제공한 경우에만 사용하고, 답변·로그에 다시 노출하지 않는다.
- 시작 주소에서 별도 SSO 도메인으로 이동하면, 그 도메인에 인증정보를 입력하기 전에 사용자의 명시적 확인을 받는다.
- CAPTCHA, 보안 경고, 예상하지 못한 권한 요청이 나오면 우회하지 말고 멈춘다.

## 진행 순서와 중단 기준

1. 고정 주소에 접속하고, 필요한 로그인 절차를 진행한다.
2. **기록물등록대장 → 추가**까지 이동한다.
3. 제공된 변수값을 입력하고, 생산일자는 지정값 또는 오늘 날짜인지 확인한다.
4. 입력 행의 값을 확인한 뒤 **저장·등록·제출 등 최종 확정 버튼은 누르지 않는다.** 최종 버튼 직전에서 멈추고 어떤 값이 입력되었는지와 미등록 상태를 보고한다.

입력 중 자동 저장으로 기록이 확정될 가능성이 보이거나, 화면 요소와 필드의 의미를 확신할 수 없으면 추가 입력 전에 멈춘다.

