# JasoGuard
## 시작 전 권한/스캔 확인

앱은 이제 실행 직후 바로 감시하지 않습니다. 먼저 감시 대상 경로를 실제로 읽어 보며 권한 상태를 확인하고, 다음 안내에 동의한 뒤에만 감시와 시작 스캔을 실행합니다.

- 감시 대상 경로 안의 파일/폴더 **이름만** 확인합니다.
- 파일 내용은 읽거나 수정하지 않습니다.
- 파일 삭제, 덮어쓰기, 업로드, 네트워크 전송을 하지 않습니다.
- 같은 이름 충돌이 있으면 변경하지 않고 건너뜁니다.
- `scanExistingOnStart`가 켜져 있으면 동의 후 기존 파일/폴더 이름을 한 번 스캔합니다.

권한이 부족하면 시작 전 확인 창의 권한 확인 결과에 표시됩니다. 이 경우 macOS에서 `System Settings → Privacy & Security → Full Disk Access`에 `JasoGuard.app`을 추가한 뒤 앱을 다시 실행하거나 메뉴의 `감시 재시작`을 누르세요.

Manual scans from the menu also show the same privacy and scan notice before running.

JasoGuard는 macOS에서 한글 파일명이 자소분리되어 보이는 문제를 줄이기 위해, 감시 폴더의 파일명/폴더명을 NFD에서 NFC로 자동 정규화하는 메뉴바 백그라운드 앱입니다.

`hsol/jaso`, `elgar328/nfd2nfc`의 목표를 참고했지만, 구현은 Swift + AppKit + FSEvents 기반으로 새로 작성했습니다.

## 주요 기능

- 메뉴바 아이콘 위젯으로 실행 여부 확인
  - 정상 실행 중: 체크 아이콘
  - 오류 발생: 느낌표 아이콘
  - 메뉴바에는 텍스트 없이 아이콘만 표시
- 영어/한국어 UI 지원
  - 기본값은 macOS 시스템 언어 자동 감지
  - 메뉴바에서 `Language` / `언어`를 직접 선택 가능
- 미니멀 앱 아이콘 포함
- 앱 실행 시 실행 확인 창 표시
- 메뉴바 위젯 숨기기
- 백그라운드 감시 완전 종료
- 로그인 시 자동 실행 토글
- Desktop, Documents, Downloads 기본 감시
- 설정 파일 기반 감시 폴더 추가/무시 폴더 관리
- 앱 시작 시 기존 감시 경로 1회 스캔
- 메뉴바에서 즉시 전체 스캔 실행
- 기존 파일 수동 일괄 변환 CLI 유지
- 인증서, Team ID, 노터라이즈 없이 Xcode에서 빌드 가능

## 요구 사항

- macOS 13 이상
- Xcode 15 이상 권장
- Apple Developer 계정은 기본 빌드에 필요하지 않음

## Xcode에서 빌드

1. `JasoGuard.xcodeproj`를 엽니다.
2. Scheme을 `JasoGuard`로 선택합니다.
3. Destination을 `My Mac`으로 선택합니다.
4. 다음을 실행합니다.

```text
Product -> Build
```

빌드 결과는 Xcode에서 다음 메뉴로 찾을 수 있습니다.

```text
Product -> Show Build Folder in Finder
```

일반적으로 Debug 빌드는 다음 위치에 있습니다.

```text
Products/Debug/JasoGuard.app
```

Release 빌드는 Scheme 설정에서 변경합니다.

```text
Product -> Scheme -> Edit Scheme... -> Run -> Info -> Build Configuration -> Release
```

그 다음 다시 빌드하면 보통 다음 위치에 생성됩니다.

```text
Products/Release/JasoGuard.app
```

이 프로젝트는 기본적으로 ad-hoc/unsigned 로컬 빌드가 가능하도록 설정되어 있습니다. `DEVELOPMENT_TEAM`이 비어 있고, `CODE_SIGN_IDENTITY`는 `-`로 설정되어 있습니다.

## GitHub Release용 ZIP 만들기

Xcode에서 Release 빌드 후 `JasoGuard.app`이 있는 폴더에서 직접 압축합니다.

```bash
cd /path/to/Products/Release
ditto -c -k --keepParent JasoGuard.app JasoGuard-unsigned.zip
shasum -a 256 JasoGuard-unsigned.zip > JasoGuard-unsigned.zip.sha256
```

GitHub Release에는 다음 파일을 올리면 됩니다.

```text
JasoGuard-unsigned.zip
JasoGuard-unsigned.zip.sha256
```

## 설치 및 실행

1. `JasoGuard.app`을 `/Applications`로 복사합니다.
2. 앱을 엽니다.
3. 첫 실행 시 실행 확인 창이 뜹니다.
4. 메뉴바에 JasoGuard 아이콘 위젯이 표시되면 실행 중입니다. 정상 상태는 체크 아이콘, 오류 상태는 느낌표 아이콘입니다.

메뉴바 위젯에서 할 수 있는 일:

- 상태 확인
- 로그인 시 자동 실행 켜기/끄기
- 실행 확인 창 표시 켜기/끄기
- 언어 선택: 시스템 언어 / English / 한국어
- 감시 재시작
- 지금 감시 경로 스캔
- 설정 파일 열기
- 로그 폴더 열기
- 위젯 숨기기
- 완전 종료

## 언어 설정

JasoGuard는 영어와 한국어 UI를 지원합니다. 기본값은 macOS 시스템 언어를 따릅니다.

메뉴바에서 다음 항목을 선택할 수 있습니다.

```text
JasoGuard 아이콘 -> 언어 -> 시스템 언어 / English / 한국어
```

영어 환경에서는 다음처럼 표시됩니다.

```text
JasoGuard -> Language -> System Language / English / 한국어
```

선택값은 `UserDefaults`에 저장되며, 메뉴와 알림 창에 즉시 반영됩니다.


## 메뉴바 아이콘

메뉴바 위젯은 텍스트를 표시하지 않고 아이콘만 표시합니다.

```text
정상 실행: 체크 아이콘
오류 발생: 느낌표 아이콘
```

아이콘에 마우스를 올리면 현재 상태가 툴팁으로 표시됩니다. VoiceOver 같은 접근성 도구에서는 `JasoGuard - 실행 중` 또는 `JasoGuard - 오류` 상태 라벨을 읽을 수 있습니다.

## 앱 아이콘

프로젝트에는 미니멀한 앱 아이콘 Asset Catalog가 포함되어 있습니다.

```text
Resources/Assets.xcassets/AppIcon.appiconset
```

Xcode 빌드 설정에는 다음 값이 들어 있습니다.

```text
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
```

따라서 별도 스크립트 없이 Xcode 빌드 시 앱 아이콘이 번들에 포함됩니다.

## 로그인 시 자동 실행

메뉴바 위젯에서 다음 항목을 켜면 됩니다.

```text
로그인 시 자동 실행
```

이 기능은 다음 LaunchAgent 파일을 생성합니다.

```text
~/Library/LaunchAgents/io.github.local.jasoguard.plist
```

이번 버전부터 LaunchAgent는 `watch` 명령만 실행하지 않고, 앱 자체를 실행합니다. 따라서 로그인 후 메뉴바 위젯도 함께 표시됩니다.

## 위젯 숨기기

메뉴바에서 다음 항목을 선택합니다.

```text
위젯 숨기기
```

위젯을 숨겨도 백그라운드 감시는 계속 실행됩니다.

다시 표시하려면 Finder에서 `/Applications/JasoGuard.app`을 다시 열면 됩니다.

## 완전 종료

메뉴바에서 다음 항목을 선택합니다.

```text
완전 종료
```

완전 종료는 다음 작업을 수행합니다.

- 백그라운드 감시 중지
- 로그인 자동 실행 LaunchAgent 제거
- 앱 종료

단순히 위젯을 숨기는 것과 다릅니다.

## Gatekeeper 우회 안내

이 빌드는 Apple Developer ID로 서명/노터라이즈되지 않은 unsigned 배포본입니다. GitHub Release에서 내려받은 앱을 처음 실행하면 macOS가 다음과 비슷한 경고를 표시할 수 있습니다.

```text
Apple cannot check it for malicious software.
```

신뢰할 수 있는 릴리즈에서 받았고 체크섬이 일치할 때만 아래 절차로 열어 주세요.

### 권장 방법

1. `JasoGuard-unsigned.zip`을 압축 해제합니다.
2. `JasoGuard.app`을 `/Applications`로 옮깁니다.
3. 앱을 한 번 실행합니다. macOS가 차단할 수 있습니다.
4. 다음으로 이동합니다.

```text
System Settings -> Privacy & Security
```

5. Security 영역에서 JasoGuard에 대해 `Open Anyway`를 클릭합니다.
6. Touch ID 또는 Mac 로그인 비밀번호로 확인합니다.
7. 앱을 다시 실행합니다.

### 우클릭으로 열기

1. `/Applications/JasoGuard.app`을 Control-click 또는 우클릭합니다.
2. `Open`을 선택합니다.
3. 다시 한 번 `Open`을 확인합니다.

### 터미널 방식

고급 사용자용입니다.

```bash
xattr -dr com.apple.quarantine /Applications/JasoGuard.app
open /Applications/JasoGuard.app
```


## 업데이트 속도와 기존 파일 변환

기본 이벤트 처리 지연 시간은 다음과 같습니다.

```json
"latencySeconds": 0.25
```

새로 생성되거나 이름이 바뀐 파일은 보통 이벤트 수신 후 약 0.25초 뒤 배치 처리됩니다. 파일을 다운로드하는 중에는 브라우저가 임시 파일명을 쓰다가 완료 후 이름을 바꾸는 경우가 있어서 실제 변환은 다운로드 완료 직후에 일어납니다.

중요: FSEvents 감시는 앱이 켜진 이후의 이벤트를 기준으로 동작합니다. 그래서 앱 실행 전에 이미 `~/Downloads`에 있던 파일은 예전 버전에서는 자동 변환되지 않을 수 있었습니다. 이번 버전은 앱 시작 시 기존 감시 경로를 한 번 스캔합니다.

```json
"scanExistingOnStart": true,
"startupScanDepth": 8
```

메뉴바에서 즉시 다시 스캔할 수도 있습니다.

```text
JasoGuard 아이콘 -> 지금 감시 경로 스캔
```

CLI로도 가능합니다.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard scan
```

다운로드 폴더만 수동 확인하려면 먼저 dry-run으로 확인하세요.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive --dry-run
```

실제 변환:

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive
```

## 설정 파일

설정 파일 위치:

```text
~/.config/jasoguard/config.json
```

기본 감시 폴더:

```text
~/Desktop
~/Documents
~/Downloads
```

기본 무시 폴더:

```text
~/Library
~/.Trash
```

중요 설정:

- `watch`: 감시할 폴더 목록
- `ignore`: 무시할 폴더 목록
- `latencySeconds`: 파일 이벤트 배치 지연 시간. 기본값은 `0.25`초입니다.
- `directoryEventDepth`: 새 파일/폴더 이벤트 발생 시 하위 탐색 깊이. 기본값은 `2`입니다.
- `scanExistingOnStart`: 앱 시작 시 기존 감시 경로를 1회 스캔할지 여부. 기본값은 `true`입니다.
- `startupScanDepth`: 앱 시작 시 기존 파일 스캔 깊이. 기본값은 `8`입니다.
- `skipHiddenFiles`: 숨김 파일 무시 여부


## `/Users` 전체를 감시하려면

`/Users`를 감시 대상으로 둘 수 있습니다. 다만 사용자 홈 전체를 훑기 때문에 `Library`, 휴지통, 공유 폴더는 무시하는 것을 권장합니다.

설정 파일 `~/.config/jasoguard/config.json`에서 예시는 다음과 같습니다.

```json
{
  "watch": [
    {
      "path": "/Users",
      "recursive": true
    }
  ],
  "ignore": [
    "~/Library",
    "~/.Trash",
    "/Users/Shared"
  ],
  "latencySeconds": 0.25,
  "directoryEventDepth": 2,
  "scanExistingOnStart": true,
  "startupScanDepth": 5,
  "skipHiddenFiles": false
}
```

`/Users` 전체에서 시작 시 스캔 깊이를 너무 크게 잡으면 첫 실행 때 오래 걸릴 수 있습니다. 처음에는 `startupScanDepth`를 `3`~`5` 정도로 두고, 필요한 경우 메뉴바의 `지금 감시 경로 스캔` 또는 CLI `convert` 명령으로 특정 폴더만 수동 변환하는 방식을 권장합니다.

현재 로그인 사용자 홈만 대상으로 하려면 `/Users`보다 아래 설정이 더 안전합니다.

```json
{
  "watch": [
    {
      "path": "~",
      "recursive": true
    }
  ],
  "ignore": [
    "~/Library",
    "~/.Trash"
  ],
  "latencySeconds": 0.25,
  "directoryEventDepth": 2,
  "scanExistingOnStart": true,
  "startupScanDepth": 6,
  "skipHiddenFiles": false
}
```

설정 변경 후에는 메뉴바에서 `감시 재시작`을 눌러 반영하세요.

## CLI 명령

메뉴바 앱으로만 써도 되지만, 기존 CLI 명령도 유지됩니다.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard status
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard scan
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard add ~/Projects
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard ignore ~/Library
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive --dry-run
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard install-agent --app-path /Applications/JasoGuard.app
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard uninstall-agent
```

`install-agent`는 이제 로그인 시 앱 자체를 실행하도록 등록합니다. 즉 메뉴바 위젯도 같이 뜹니다.

## 로그

로그 폴더:

```text
~/.local/state/jasoguard/
```

메뉴바 위젯에서 `로그 폴더 열기`로 바로 열 수 있습니다.

## Full Disk Access

일부 폴더 접근이 막히면 다음 경로에 Full Disk Access를 주세요.

```text
System Settings -> Privacy & Security -> Full Disk Access -> +
```

선택할 파일:

```text
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard
```

Finder 선택 창에서 `Cmd + Shift + G`를 누른 뒤 위 경로를 붙여넣으면 됩니다.


## nfd2nfc 방식 반영: 실제 디스크 파일명 기준 변환

이번 버전은 `nfd2nfc`의 핵심 아이디어를 Swift 구현에 반영했습니다.
macOS에서는 FSEvents나 `URL.lastPathComponent`로 받은 문자열이 실제 디렉터리 엔트리에 저장된 정규화 형태와 다르게 보일 수 있습니다. 그래서 JasoGuard는 이제 변환 판단 전에 macOS `fcntl(F_GETPATH)`로 파일시스템이 가진 실제 경로를 다시 읽고, 그 마지막 파일명을 기준으로 NFC 변환 필요 여부를 판단합니다.

처리 순서는 다음과 같습니다.

1. 이벤트 또는 스캔으로 받은 경로를 연다.
2. `fcntl(F_GETPATH)`로 실제 디스크 경로를 가져온다.
3. 실제 파일명에 `precomposedStringWithCanonicalMapping`을 적용한다.
4. 실제 파일명과 NFC 파일명이 다르면 rename한다.
5. macOS가 같은 파일을 목적지 충돌처럼 인식하면 임시 이름으로 한 번 바꾼 뒤 최종 NFC 이름으로 다시 바꾼다.
6. 진짜 다른 파일과 이름이 충돌하면 덮어쓰지 않고 건너뛴다.

이 방식은 특히 `~/Downloads`에서 이미 존재하는 자소분리 파일이나, 브라우저/메신저가 다운로드 완료 후 이름을 바꾸는 파일을 더 안정적으로 처리하기 위한 변경입니다.

## 주의 사항

- 같은 이름의 NFC 파일이 이미 있으면 덮어쓰지 않습니다.
- 충돌 파일은 그대로 두고 로그에 기록합니다.
- 앱 실행 중 설정 파일을 수정했다면 메뉴바에서 `감시 재시작`을 눌러 반영하세요.
- unsigned 배포본은 사용자가 Gatekeeper 예외를 직접 허용해야 합니다.

## License

MIT. See `LICENSE`.
### 자소가 바뀌지 않는 것처럼 보일 때

이번 버전은 macOS의 대소문자/정규화 비구분 파일시스템에서 발생하던 문제를 보완했습니다.
이전 버전은 `한글.txt` → `한글.txt`처럼 **문자열만 다르고 파일시스템상 같은 항목으로 인식되는 경우**를 충돌로 보고 건너뛸 수 있었습니다.
현재 버전은 같은 파일 항목인지 확인한 뒤, 같은 항목이면 임시 이름을 거쳐 NFC 이름으로 다시 rename합니다.

바로 확인하려면 먼저 dry-run을 실행하세요.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive --dry-run
```

실제 변환은 다음 명령입니다.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive
```

메뉴바에서는 `지금 감시 경로 스캔`을 누르면 기존 파일까지 다시 검사합니다.


## 자소 변환이 안 되는 것처럼 보일 때

이번 버전은 Swift `String ==` 비교를 사용하지 않고 Unicode scalar 배열을 직접 비교합니다. Swift 문자열 비교는 정규화된 문자 동등성을 기준으로 동작할 수 있어서, `한글`(NFC)과 `한글`(NFD)이 서로 다른 파일명 바이트/스칼라여도 같은 문자열처럼 판단될 수 있습니다. 그래서 이전 빌드는 변환이 필요한 이름을 “이미 정상”으로 건너뛸 수 있었습니다.

확인은 먼저 dry-run으로 하세요.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive --dry-run
```

`DRY-RUN ... -> ...` 줄이 보이면 실제 변환 대상이 있다는 뜻입니다. 실제 변환은 다음 명령으로 실행합니다.

```bash
/Applications/JasoGuard.app/Contents/MacOS/JasoGuard convert ~/Downloads --recursive
```

앱 위젯에서는 메뉴바 아이콘을 클릭한 뒤 `지금 감시 경로 스캔`을 실행하면 됩니다.

주의: macOS/Finder는 화면 표시에서 Unicode 정규화 차이를 눈으로 구분하기 어렵습니다. 변환 여부는 앱 로그 또는 `--dry-run` 결과로 확인하는 것이 가장 정확합니다.

## Windows와 같은 조합형(NFC)으로 저장하기

이번 버전은 변환 대상 경로를 만들 때 `URL.appendingPathComponent(...).path`를 사용하지 않습니다. macOS Foundation URL 경로 처리는 파일시스템 표현에 맞춰 문자열을 다시 정규화할 수 있어서, 코드상으로 NFC 이름을 만들었더라도 최종 `rename()`에 NFD처럼 분해된 경로가 전달될 수 있습니다.

JasoGuard는 이제 다음 방식으로 처리합니다.

1. `fcntl(F_GETPATH)`로 실제 디스크 경로를 읽습니다.
2. 실제 파일명만 NFC, 즉 Windows에서 쓰는 조합형 이름으로 변환합니다.
3. `실제 부모 경로 + "/" + NFC 파일명`을 문자열 결합으로 직접 만듭니다.
4. 이 값을 URL로 다시 만들지 않고 POSIX `rename()`에 바로 전달합니다.
5. 정규화 차이만 있는 같은 파일은 ASCII 임시 이름을 거쳐 최종 NFC 이름으로 다시 바꿉니다.

검증하려면 dry-run 출력의 `to scalars` 줄을 확인하세요. 예를 들어 `한`은 Windows 호환 조합형이면 `U+D55C`처럼 한 글자 스칼라로 표시되고, 분해형이면 `U+1112 U+1161 U+11AB`처럼 여러 스칼라로 표시됩니다.
