# 예쁜 가변 블러와 화면 전환 — 2026-09-14 조사

현재 native 후보는 사용자 외형 acceptance 실패임. 목표는 탁한 색조나 원본의 단순 투명 혼합으로 대체하지 않고, 원래 화면의 색을 유지하며 위치별 흐림 정도가 연속으로 바뀌는 보호와 자연스러운 Space 전환을 함께 얻는 것임. 이 문서는 조사·실험 설계이며 새 구현의 성공 기록이 아님.

## 핵심 구분

‘블러를 그리는 도구’와 ‘다른 앱의 최신 화면을 가져오는 방법’은 별개임. Glur/Metal 필터가 예쁜 이미지를 만들더라도 입력이 늦은 캡처라면 이전 화면 재표시 문제를 자동으로 해결하지 않음. 반대로 native material의 투명도 마스크는 흐림 반경을 위치별로 바꾸는 필터와 같지 않음. 기존 두 출력의 외형 차이는 이 구분으로 설명됨.

```text
공개 캡처 경로: 다른 앱 → 화면 캡처 → 가변 블러 → 가림 창 → OS 화면 합성
시스템 backdrop 후보: 다른 앱 + 블러 반경/마스크 → OS 화면 합성
```

두 번째 경로가 앱의 캡처 재표시를 없애는 점은 유망하지만, 해당 레이어가 전환 중에도 올바르게 합성된다는 보장은 별도임.

## 라이브러리·대안 비교

Luna 3개가 공개 shader, compositor, 캡처 수명을 독립 조사했고 메인이 실제 소스를 대조함. 아래는 현재 확인한 후보의 범위이며 전체 생태계의 불가능 증명은 아님.

| 후보 | 실제 처리 대상 | 외형·전환 관점의 판정 | 라이선스/제약 |
| --- | --- | --- | --- |
| [Glur](https://github.com/joogps/Glur), [Inferno](https://github.com/twostraws/Inferno) 공개 모듈 | 자기 SwiftUI layer | 예쁜 가변 반경 shader는 있지만 다른 앱 화면 입력·Space 수명은 제공하지 않음 | MIT, Metal 경로 macOS 14+ |
| [VariableBlurImageView](https://github.com/Eskils/VariableBlurImageView) | NSImage/CGImage | Metal 처리 뒤 texture.getBytes로 이미지화함. 현재 GPU 직접 출력보다 유리하다는 근거 없음 | MIT, AppKit 지원 |
| [MetalPetal](https://github.com/MetalPetal/MetalPetal) | texture/pixel buffer 등 이미지 그래프 | 기존 캡처 경로의 필터 최적화 후보. 화면 전환을 해결하는 라이브러리는 아님 | MIT, macOS 지원. 세부 파일 고지 보존 필요 |
| [GlurBackdrop](https://github.com/joogps/Glur/tree/main/Sources/GlurBackdrop) | backdrop layer와 variableBlur | 위치별 반경 구현을 참고할 가장 구체적인 후보. 다른 앱 데스크톱·전환까지 바로 되는지는 미검증 | Glur와 별도 opt-in 제품, MIT, 비공개 API |
| [CoreAnimationPrivate](https://github.com/kageroumado/core-animation-private) | WindowServer-aware backdrop | 색조 없는 시스템 Gaussian 후보. variableBlur 조합을 별도로 검증해야 함 | MIT, 비공개 API |
| [QuietLens](https://github.com/quietapps/QuietLens/blob/main/QuietLens/Overlay/BlurOverlayView.swift) | native material + tint/gradient | blurRadius 값을 네 material 구간으로 바꿈. true variable-radius 구현의 증거가 아니므로 채택하지 않음 | MIT, 공개 material 외 별도 private 기능도 있음 |
| [CGS 배경 블러](https://github.com/rust-windowing/winit/issues/4205) | 창 전체의 균일 반경 | 색조 없는 기준선 후보지만 픽셀별 반경 기능이 아님. 여러 창으로 쪼개면 경계·합성 문제가 추가되므로 우선순위 낮음 | 비공개 API, 실제 App Store 거절 보고 |

Glur는 일반 모듈과 GlurBackdrop을 반드시 구분함. [Package.swift](https://github.com/joogps/Glur/blob/main/Package.swift)와 [README](https://github.com/joogps/Glur#blurring-the-backdrop)에서 별도 링크를 선택하게 되어 있음. 일반 Glur만 사용하면서 backdrop 기능까지 제공한다고 설명하면 잘못된 결론임.

메인이 추가 확인한 [GlurBackdropNSView](https://github.com/joogps/Glur/blob/main/Sources/GlurBackdrop/GlurBackdropNSView.swift)와 [BackdropBlurFilter](https://github.com/joogps/Glur/blob/main/Sources/GlurBackdrop/BackdropBlurFilter.swift)는 macOS 분기에서 CAFilter variableBlur의 inputRadius/inputMaskImage를 설정함. 따라서 ‘iOS 예제만 존재’라고 할 수 없음. 하지만 backdrop 생성은 단순 init이며 WindowServer-aware 설정은 없음. 이 소스만으로 다른 앱 데스크톱을 샘플링하거나 Space 전환에 견딘다는 주장도 할 수 없음. CoreAnimationPrivate의 [Gaussian helper](https://github.com/kageroumado/core-animation-private/blob/main/Sources/CoreAnimationPrivate/CABackdropLayer%2BBlur.swift)는 windowServerAware를 별도로 지정함. 두 구현의 개념을 결합한 실험이 필요하며 완제품 라이브러리를 발견한 것은 아님.

## 먼저 판정할 실험

아래 수치·횟수는 비교 실험 설계이며 제품 완료 기준을 새로 확정한 것이 아님. 실제 사용자 외형 판정을 유지함.

| 단계 | 비교 조건 | 얻을 증거와 탈락 조건 |
| --- | --- | --- |
| 입력 경로 | 자체 예제 내부/다른 앱 뒤, 정지/스크롤 | 자기 앱 내용만 흐리면 데스크톱 대체 후보에서 제외 |
| 외형 | 균일 색상·작은 한글/영문·아이콘·체크무늬, 반경과 마스크를 각각 변화 | 색조·밝기 변화와 원본 이중 윤곽을 구분. 탁함을 농도만 낮춰 숨긴 결과는 통과로 세지 않음 |
| 전환 | 보호 끔/후보, 일반↔전체/전체↔전체, 양방향·연속 입력 | 이전 fixture ID 재등장, 경계 되돌림, 블러 이중 적용, 선명 노출을 별도로 계측 |
| 다중 화면 | 내장/외장, Retina·노치·세로 화면, 서로 다른 Space | 화면 경계 연속성과 좌표·클릭 위치 확인 |
| 수명 | 보호 끄기, 입력 중단 기본 해제/선택적 최대 가림, 화면 구성 변경 | 창·타이머·캡처가 남거나 중단 후 재표시되면 실패 |
| 비용 | 동일 해상도·각도·전환 반복에서 frame age·GPU/WindowServer 부하 | FPS 설정값을 실측 FPS로 쓰지 않음. 품질을 낮춘 속도 개선을 같은 품질의 개선으로 세지 않음 |

합성 fixture만 사용하고 실제 화면 픽셀은 RAM에서 처리함. 과거의 전체 forceCovered 검증을 낮은 농도·연속 반경의 검증으로 넓히지 않음. 결과의 숫자와 사용자가 보는 품질을 모두 남김.

## 공개 캡처 경로의 남은 실험

현재 앱은 native 단일 출력이며 이전 캡처 코드는 비교 진단용으로만 남아 있음. 이전 GPU 실험은 레이어 교체·타임스탬프 cutoff·native 바닥 등 여러 수명 정책을 거친 경로였음. 따라서 캡처 방식 전체의 불가능을 입증한 결과는 아님.

다음 공개 API 실험은 하나의 CAMetalLayer를 수명 전체에 유지하고 별도 Space 이벤트에서 출력 표면을 교체하지 않는 조건임. 먼저 가공하지 않은 캡처 재표시를 기준으로 측정한 뒤 기존 Gaussian을 붙여 추가 지연·중복 이동의 원인을 분리함. 캡처 도착, 실제 displayTime, GPU 완료, drawable 표시 시각을 구분하며 시각 기반 폐기만으로 Space의 정체를 안다고 가정하지 않음. 임의 sleep·검은 가림·native/GPU 재전환은 추가하지 않음.

한계: 이 경로에서도 캡처부터 표시까지 지연이 존재하며 OS가 가림 창을 이동시키는 방식과 캡처에 이미 담긴 전환이 충돌할 가능성이 있음. `minimumFrameInterval=1/60`은 캡처 간격 설정이지 무지연·전환 동기 보장이 아님. [Apple minimumFrameInterval](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval)

## 시스템 합성 후보와 배포 경계

[CoreAnimationPrivate](https://github.com/kageroumado/core-animation-private)는 CABackdropLayer와 WindowServer-aware 샘플링을 제공한다고 문서화함. 현재 README는 macOS 13+ 패키지, macOS 26.1 확인, MIT 라이선스, 비공개 API임을 명시함. 균일 Gaussian helper가 있다고 해서 macOS의 per-pixel variableBlur와 전체 화면 전환까지 검증된 것은 아님. 외부 라이브러리를 채택하기 전에 실제 필터·마스크 조합을 작은 실험으로 확인해야 함.

[BackdropView 구현](https://gist.github.com/avaidyam/d3c76df710651edbf4da56bad3fea9d2)은 색조 없이 blur/saturation을 조절하는 방법을 보여주지만, 창이 변형되거나 Mission Control에 들어가면 배경 합성이 실패한다는 경고도 포함함. 따라서 오래된 코드를 복사해 전환 문제까지 해결됐다고 할 수 없음. 이 소스는 반례와 구조 조사에 사용하며 명확한 라이선스 확인 없이 그대로 제품에 복사하지 않음.

[NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)는 공개적인 glass style·tintColor·contentView를 제공함. 실제 데스크톱의 임의 per-pixel Gaussian 반경 제어를 제공한다는 근거는 확인하지 못했음. 외형 참고 후보이며 사용자가 요구한 가변 블러의 대체 해결책으로 채택하지 않음.

비공개 API는 시스템이 공개 지원 계약을 제공하지 않는 인터페이스임. [App Review 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)은 공개 API 사용을 요구하므로 이 의존성을 포함한 빌드는 Mac App Store 호환 경로로 취급할 수 없음. 직접 배포·Developer ID 서명·공증 가능 여부와 OS별 안정성은 별도 검증이며, 라이브러리 README의 ‘outside App Store fine’ 문구만으로 배포를 보증하지 않음. 라이브러리 사용 허용을 이 배포 제약의 승인으로 해석하지 않음.


## 추천과 다음 결정

예쁜 외형이 필수라는 최신 지시에 따라 native material을 최종안으로 추천하지 않음. 가장 먼저 검증할 새로운 방식은 색조 없는 시스템 backdrop에 variableBlur와 기존 시야 마스크를 연결하는 작은 별도 실험임. 캡처 재표시를 제거하면서 위치별 실제 반경을 바꾸려는 후보이며 성공 가능성을 검증할 가치가 있음.

구체적인 순서는 (1) 다른 앱 뒤의 균일 Gaussian이 색조 없이 출력되는지, (2) 같은 backdrop에 variableBlur를 적용했을 때 마스크의 0/중간/1이 실제 다른 반경인지, (3) 바로 전체 화면 왕복·연속 전환, (4) 통과한 뒤 실제 고개 회전과 외장 화면임. 1단계에서 자체 뷰만 흐려지거나 2단계가 투명도 혼합에 그치거나 3단계에서 표면이 사라지면 해당 후보를 탈락시킴. 오류 때 다른 시각 효과로 조용히 바꾸지 않음. 정상/실패를 구분하는 독립 시험 창과 명시적 종료로 한정함.

초기 조사 시 비공개 API 허용은 미결이었으며, 후속 실험 승인은 spec에 기록했음. 허용해도 제품 의존성 채택·직접 배포 성공·App Store 포기를 한꺼번에 확정하지 않음. App Store 호환성이 필수라면 공개 API의 GPU 연속 출력 실험을 먼저 진행하는 대안이 더 적합함. 기존 Gaussian의 외형은 재사용하되 native/GPU 교대와 Space별 layer 교체를 누적하지 않고 입력·표시 지연을 다시 분리함.

초기 조사 종료 시점에는 출처·소스 조사와 검증 설계만 완료했음. 앱 재실행·사용자 보정 변경·새 dependency 설치·비공개 API 실행은 수행하지 않았음. 새 후보의 외형과 전환 성공을 아직 주장하지 않음. library 채택 시 조사한 main/master 대신 commit을 고정하고 해당 LICENSE를 함께 보존해야 함.

## 비공개 backdrop 실측 — 후속 승인 뒤

제품 경로에 설치하기 전 별도 진단 앱에서 실행했음. 사용자의 최신 ‘tricky 해도 좋음’은 [spec](spec.md)의 격리 실험 승인으로 반영함. 제품 앱·배포 의존성은 교체하지 않았음.

내장 화면 1728×1117pt에서 다른 두 프로세스의 전체 화면 초록/자홍 줄무늬를 Control+좌/우로 조건당 8회 전환함. 보호 자체에는 캡처 입력이나 전환 시 레이어 교체가 없음. ScreenCaptureKit 두 스트림은 원본(시험 앱 제외)과 표시 결과(포함)를 메모리에서 관측하는 용도로만 사용함. 중앙 4pt 띠를 432×4로 읽고, displayTime이 같은 프레임에서 인접 픽셀 색 대비를 비교함. 따라서 화면 전체·실제 패널 육안·외장 화면·AirPods 회전의 acceptance를 뜻하지 않음.

정지 두 창 시험에서는 CABackdropLayer/windowServerAware와 variableBlur가 작동했음. 알려진 줄무늬의 red-channel 표준편차가 원본 약80에서 균일 반경24 적용 시 약0.5로 감소함. 선형 마스크 적용 시 왼쪽 구간 약30.9, 중간 구간0으로 위치별 결과가 달랐음. 색조 레이어를 넣지 않았지만 색 정확도와 사용자 미감 통과까지 증명한 것은 아님. 별도 프로세스 전체 화면 시험에서도 정지 구간의 줄무늬 대비가 크게 감소했음.

전환 프레임은 초록 화면 비율이 0.05~0.95이고 원본 줄무늬 대비가10보다 큰 경우로 한정함. 아래 비율은 표시 대비/원본 대비임. 1에 가까우면 블러가 없는 원본과 유사한 줄무늬가 남음. 0.5는 관측 요약 구간이지 제품 통과 기준이 아님.

| 조건 | 시각 일치 전환 표본 | 대비 비율 중앙값 | 최대 | 0.5 초과 표본 |
| --- | ---: | ---: | ---: | ---: |
| 직접 backdrop | 121 | 0.3030 | 1.0390 | 40 |
| 창의 flatten 비활성·host 재생성 | 105 | 0.3209 | 1.0390 | 31 |
| 위 조건 + 창 tag 상위 word bit23 | 119 | 0.3209 | 1.0390 | 34 |
| 위 조건 + bit16 | 136 | 0.5428 | 1.0567 | 72 |
| bit23 + view flatten 비활성 | 126 | 0.2548 | 0.9716 | 34 |
| 위 조건에서 stationary 제거 | 106 | 0.3133 | 1.0390 | 35 |

어느 조건도 연속 블러 유지의 근거를 충족하지 못했음. 정지 상태의 강한 블러가 전환 중 풀리는 관측이므로 단순 필터 강도 부족과 구분됨. 창 변형 시 레이어 flatten은 원인 후보이지만 내부 WindowServer 상태를 직접 입증하지 않았으므로 확정 원인으로 쓰지 않음. 역사적 private tag는 현재 OS에서 의미가 보장되지 않으며 성공 반환을 효과의 증거로 쓰지 않음.

무효/실패 실험도 남김. 초기 정지 시험은 예제 창이 isOnScreen=false여서 제외했음. 단색 전환의 이동 비율 일치는 블러 유지 증거가 아니므로 줄무늬로 다시 측정했음. 기존 native panel을 생성한 뒤 contentView만 private view로 바꾼 첫 조건은 정지 블러도 나오지 않았음. 순수 panel 생성과 host 적용 시점을 함께 바꾼 뒤 정지 출력이 나왔으므로 둘 중 하나를 단독 원인으로 확정하지 않음.

재현 코드·측정 해석은 [진단 안내](../scripts/diagnostics/README.md), 요약 도구는 `scripts/diagnostics/summarize-transition.py`임. 원본 수치 로그는 `/tmp/privacy-private-backdrop3.log`, `/tmp/privacy-pattern2-transition-{plain,host}.log`, `/tmp/privacy-pattern3-transition-{tag23,tag16}.log`, `/tmp/privacy-pattern4-transition-{unflattened,moving}.log`에 있음. 임시 경로는 영구 보존을 보장하지 않으며 위 표가 이번 관측의 요약임.

기본 NSVisualEffectView의 실제 레이어 검사에서는 `sdrNormalize/gaussianBlur/colorSaturate` 필터와 `fill/tone/Chameleon` 레이어를 확인했음. 따라서 탁한 외형은 순수 Gaussian 하나만의 결과가 아님. 이 native 계층에서 채움/색조를 숨기고 variableBlur로 바꾸는 일곱 번째 후보도 실행했음. AppKit 하위 레이어 생성 전 최초 접근은 ‘Native backdrop not found’ 오류로 종료했으며 조용히 native 성공으로 대체하지 않았음. 하위 레이어 생성 뒤 별도 실행한 결과(`/tmp/privacy-pattern6-transition-native.log`)는 전환 표본107개, 대비 비율 중앙값0.3027·최대1.0392·0.5 초과31개로 연속 유지에 실패했음. 초기 설치 전150ms 대기는 시험 준비용이며 전환 중 지연·가림 정책으로 넣지 않았음.

이번 판정: 색조 없는 가변 블러의 정지 구현은 가능함을 관측했으나 **끊김 없는 전체 화면 전환 후보는 아직 확보하지 못했음**. private layer를 유지하거나 native 계층을 재사용하는 것만으로 해결되지 않았음. 실패 후보를 제품 기본값으로 교체하지 않았고 검은 가림·강도 중첩·출력 교대를 추가하지 않았음. 다음 유효한 분리 실험은 같은 줄무늬 관측에서 수정하지 않은 native 기준선과 WindowServer 창 단위 blur를 비교하여 ‘필터 레이어 수명’과 ‘캡처 관측 경로’의 영향을 구별하는 것임. 창 단위 균일 blur가 통과하더라도 위치별 가변 반경의 해결로 확대하지 않음. 외장 다중 화면·실제 AirPods·장시간 성능·사용자 외형 acceptance는 미완료임.

## 후속 원인 분리와 Blur Lab

환경을 다시 확인함: Apple M4 Pro, macOS26.6.2(25G83), 내장1728×1117pt·Retina2배, 화면1대. 후속 관측은 원해상도 중앙8pt의 여러 행을 사용함. 두 독립 스트림의 동일 displayTime은 비교 키이며 물리 패널 합성의 동일성을 보증하지 않음. 시각 미일치 표본을 공개하고 실제 사용자 확인과 구분함.

### 공통 원인과 통제 비교

수정하지 않은 native material도 전환 중 같은 대비 상승을 보였음. [winit v0.30.9의 창 blur 선언](https://github.com/rust-windowing/winit/blob/v0.30.9/src/platform_impl/macos/ffi.rs)을 대조해 시험 창에 `CGSSetWindowBackgroundBlurRadius`를 적용했으나 같은 현상이 남았음. 필터 하나의 결함으로 일반화할 수 없었음.

[Apple DTS의 overlay 안내](https://developer.apple.com/forums/thread/826308)를 참고해 accessory 활성화 정책과 높은 창 레벨도 비교했음. 이 안내의 전체 화면 위 표시와 전환 중 좌표·블러 유지 검증을 구별함. 새로 확인한 [CGSWindow 헤더](https://github.com/NUIKit/CGSInternal/blob/master/CGSWindow.h)는 기존 gist와 tag 번호가 다름. upper-word bit13(super-sticky), bit20(never-flatten)도 시험했으며 이름만으로 현재 OS의 효과를 보장하지 않았음.

| 조건 | 유효한 전환 표본 | 대비 비율 중앙값 / 최대 | 관측 |
| --- | ---: | --- | --- |
| 보호 끔, 원해상도 | 143 | 0.9752 / 0.9887 | 두 관측 경로의 기준선 |
| 수정하지 않은 native material | 72 | 0.2839 / 0.9370 | 높은 대비가 다시 나타남 |
| 창 단위 균일 blur | 111 | 0.2611 / 0.9392 | 레이어 필터만의 문제로 한정 불가 |
| accessory + 최대 창 레벨 | 119 | 0.2822 / 0.9335 | 표시 높이만으로 해결되지 않음 |
| 좌우 각각 화면 폭만큼 확장 | 112 | 0.0161 / 0.0172 | 전체 블러 유지의 첫 유효한 후보 |

`CGSGetCatenatedWindowTransform`을 함께 읽자 가림 창 자체의 좌우 이동을 확인했음. 보통 크기의 직접 backdrop은 tx가−1780~1744였음. `.stationary`, 높은 레벨, full-screen collection 옵션 일부 제거, 위 tag 비교로 이동이 사라지지 않았음. 이는 현재 시험의 공백에 영향을 주는 확인된 조건임. 이전 GPU 경로의 모든 재등장 원인을 이 한 가지로 확정한 것은 아님.

```text
Space 이동 → 가림 창에도 이동 적용 → 화면 크기만 한 가림 범위·마스크 위치가 어긋남
확장 후보 → 넓은 범위로 공백 방지 → 마스크 좌표는 따로 보정해야 함
```

확장 조건(`/tmp/privacy-pattern15-transition-overscan.log`)은 실제 fixture8회 전환을 확인했음. 준비 후 시각 일치329표본 전체의 대비 비율 최대도0.0173이었음. 원본/표시의 초록 장면 진행 비율 차이는 전환112표본에서 중앙값0.0119·최대0.0162였음. 임의 시간 지연·검은 가림·캡처 재표시·native/GPU 교대를 사용하지 않았음.

### 부분 경계와 좌표 점프

확장만 적용하면 부분 경계가 함께 이동했음. 시험용 파란 표식으로 창의 역변환 방향을 대조하여 `tx + window.frame.origin.x`로 레이어 위치를 보정했음. 정지 시 origin.x=−1728, tx=1728이므로 보정량0이 됨. 반대 부호 제안은 정지 상태부터 어긋나므로 채택하지 않음.

일차 보정은 반복 실행에서 실패했음. tx가 순간적으로 화면 간격1792pt의 여러 배(7168,8960)만큼 바뀌어 블러 레이어를 화면 밖으로 밀어냈음. 현재 OS에서 관측한 폭1728+간격64pt 주기의 반복 마스크와 나머지 연산으로 이 큰 점프를 흡수하는 후보를 만들었음. 64pt는 조사 기기의 실측 가정이며 시스템 API에서 읽어온 값이라고 쓰지 않음.

고정 부분 마스크의 왼쪽30%는 선명하고 오른쪽30%는 강한 블러가 되도록 입력했음. 장면 색 경계의 저주파 대비가 섞이지 않도록 해당 구간과 이웃2구간을 제외한 결과(`/tmp/privacy-pattern20-transition-periodic.log`):

| 화면 구간 | 전환 중 대비 비율 범위 | 판정 |
| --- | --- | --- |
| 왼쪽 선명 구간(16분할의1·3번) | 약0.959~0.964 | 선명 영역의 큰 반전이 사라짐 |
| 오른쪽 흐림 구간(7·9·12·14번) | 0~0.013 | 흐림 영역 전체가 열리는 점프가 사라짐 |
| 블러 시작 경계 부근(5번) | 0.004~0.992 | 경계 흔들림이 남음. 최종 완료 아님 |

강한 블러로 중복 강도를 숨기지 않도록 반경3의 약한 전체 블러도 비교함(`/tmp/privacy-pattern19-transition-weakoverscan.log`). 같은 순색 구간에서 정지/전환 대비 비율이 모두 약0.111~0.130 범위였음. 이 실행에서 전환 중 강도가 두 배로 겹친다는 근거는 없었으나 모든 이미지·반경·OS에서의 부재 증명은 아님.

### 검사 자체의 보완과 제외한 실행

- 축소432×4 기준선의 위상 영향을 줄이기 위해 원해상도·여러 행으로 변경했음. 새 지표는 총 인접 대비를432 기준으로 정규화함.
- 합성 예제 색이 화면에서 사라지거나 실제8회 전환이 없으면 요약기가 거부함. READY 직전 마지막 안정 장면도 초기 상태에 포함해, 정지 화면의 complete 프레임이 새로 나오지 않는 경우를 처리함.
- pattern13-highvariable은 예제 자동 종료로 다른 Space가 섞여 제외함(원본740프레임 중451개가 예제 색 범위 밖). 그 밖의 주요 비교는 예제 색 합이 최소약0.963이었음.
- pattern18은 System Events 종료 오류(−600)로 입력하지 못해 제외함. 재실행은 새 로그·새 예제로 수행했음.
- 정상 로그3개와 위 무효 로그2개로 요약기의 수용/거부를 확인함. 무효 실행을 통과 수에 합치지 않음.

### 별도 실험 앱

[Blur Lab 소스](../scripts/diagnostics/BlurLab.swift)와 [빌드 안내](../scripts/diagnostics/README.md#최신-비교-앱)를 추가했음. 별도 bundle ID를 사용하며 제품 설정·보정을 읽거나 저장하지 않음. 실제 보호에 캡처를 사용하지 않고, 수동 각도 또는 별도 정면 기준의 AirPods 입력으로 같은 후보를 조절함. 화면1대만 허용하고 화면 변경·입력 중단·오류에서 해제함. 이는 제품의 전체 실패 정책을 바꾼 것이 아니라 격리 렌더 실험의 중단임.

초기 앱 시작 검사에서는 창 표시 확대 애니메이션 때문에 약1.019배 변환을 읽어 명시적으로 중단했음. 가림 창의 `animationBehavior = .none`으로 해당 원인을 제거함. 기다리는 시간을 늘려 통과시키지 않았음. 미지원 회전/확대 변환은 지금도 오류로 종료하며 Mission Control 지원을 완료로 표시하지 않음.

제품 채택·배포는 아직 하지 않았음. 외장 두 대의 중복 가림/연결부, 자동 Space 간격 추정, 경계 흔들림·실제 AirPods·장시간 GPU 부하·사용자 외형 acceptance가 남아 있음. 화면을 넓혀 그리는 방식의 다중 화면 비용과 범위를 확인하기 전에 기존 앱을 교체하지 않음.

후속 각도 갱신 검사에서 초기 구현의 결함도 잡았음. 이미 연결된 filter 객체의 inputMaskImage/radius 값만 바꾸면 WindowServer 출력이 바뀌지 않았음(pattern21). 레이어는 유지하고 새 filter 값 배열을 commit하는 방식으로 수정했음. 최종 pattern22에서는 전체 화면8회 전환과 수동 각도±45°의16회 설정을 함께 실행했음. 장면 색 경계를 제외한 안정 구간의 대비 비율 중앙값은 +45°에서 왼쪽0·오른쪽0.9342, −45°에서 왼쪽0.8971·오른쪽0으로 실제 화면 방향 변경을 확인함. 각도 변경 직후 응답 시간이나 센서 정확도 검사가 아니며, 중간 경계의 흔들림이 사라졌다는 판정도 아님. `summarize-transition.py --profiles`로 같은 로그를 재요약할 수 있음.

최종 Blur Lab 빌드·개발 서명 검증 통과. `/tmp/privacy-blur-lab-smoke6.log`에서 시작, 각도/강도 변경 후 실행 유지, 오래된 sample을 넣은 입력 중단 모사의 가림/기준 해제, 종료를 확인함(`LAB UPDATE true`, `LAB LOSS true true`, `LAB SMOKE true true`). 관리 창의 배치 범위를 벗어난 직접 하위 뷰는0개였음. 이는 시각 디자인의 사용자 acceptance가 아니라 실제 UI 배치/실행 검사임. 실제 AirPods 착용/탈착은 수행하지 않았음. 기존 앱 프로세스는 유지했으며 합성 fixture와 자동 probe는 정리했음.

Blur Lab의 위치 보정 tick은 블러를 켠 동안만 실행하고 해제/종료 시 취소함. 유휴 앱에서 고주기 보정을 계속 돌리지 않음. 이 구조 검사를 CPU/GPU 실측 개선률로 표현하지 않음.


### 간헐적 선명 노출 — 사용자 재보고 후속

사용자는 외형이 이전보다 나아졌으나 어떤 전환에서는 전체 화면이 보인 뒤 블러가 다시 생긴다고 보고함. 현재 후보의 전환 acceptance는 실패 상태임. 직후 Blur Lab AX 상태는 AirPods 입력 중단으로 해제된 상태였음. 이 경로는 자동 재시작하지 않으므로 전환 후 자동 복귀 현상의 원인으로 단정하지 않음.

각도 갱신 빈도와 시작 Space를 분리한 추가 비교를 수행함. 내장 화면1대, 원해상도 중앙8pt 띠, 원본/표시 displayTime 일치 표본 기준임. `fixedangle`은 +45°, `continuous`는 +45° 주변 ±1°를 8ms 대기 간격으로 계속 갱신함. 실제 갱신률을125Hz로 측정한 결과는 아님.

| 로그 | 조건·입력 | 전환 수 | 시각 일치 / 전환 중 표본 | 전체 대비 비율 최대 |
| --- | --- | --- | --- | --- |
| `/tmp/privacy-pattern23-transition-fixedangle.log` | 전체 화면 A↔B, 고정 각도, Control 좌/우 | 8 | 343 / 116 | 0.2499 |
| `/tmp/privacy-pattern23-transition-continuous.log` | 전체 화면 A↔B, 연속 각도, Control 좌/우 | 8 | 332 / 47 | 0.3398 |
| `/tmp/privacy-pattern24-transition-fixedangle.log` | 일반 데스크톱 A에서 시작, 전체 화면 B와 앱 활성화로 이동, 고정 각도 | 8 | 200 / 69 | 0.2502 |
| `/tmp/privacy-pattern24-transition-overscan.log` | 같은 일반↔전체 화면, 위치 보정 없는 전체 블러 | 8 | 180 / 59 | 0.0400 |

세 부분 블러 실행의 순색 왼쪽 강한 블러 구간(1·3·5번)은 일치한 전환 표본에서 대비 비율0을 유지했음. 이는 해당 표본에서 전체 선명 노출을 잡지 못했다는 뜻이며, 경계 흔들림·미일치 프레임·실제 사용자 증상이 해결됐다는 뜻이 아님. 연속 입력 실행은 raw-only468 / shown-only469표본으로 누락이 특히 많았음. 일반↔전체 화면 시험의 앱 활성화 이동을 Control 좌/우 입력과 동일한 시험으로 기록하지 않음.

자동 시험은 관측용 ScreenCaptureKit 스트림을 사용하므로 캡처 없는 사용과 합성 경로가 같다는 보장이 없음. 관측 자체가 증상을 바꾸는지는 아직 가설임. 실제 재현에서 화면 캡처 없이 창 역변환·Space 알림·출력 오류·입력 중단/해제를 대조할 수 있도록 Blur Lab에 `--trace-transitions`를 추가했음. 시작마다 최초90초만 고주기 창 위치를 기록하며 화면 픽셀·앱 제목·머리 각도는 남기지 않음. 기록이 없다는 사실을 화면이 가려졌다는 증거로 사용하지 않음.

빌드·개발 서명 및 `/tmp/privacy-blur-lab-smoke7.log`의 시작/값 변경/오래된 입력 해제/종료 assertions를 확인했음. 진단 출력에 `started`, `input-lost`, `stop`과 창 변환이 실제 남음을 확인했음. 실제 Space 알림과 사용자 증상의 시간 일치 검증은 남음. 제품 렌더 경로·Lab의 블러 외형/실패 정책은 변경하지 않았음. 시험 fixture 프로세스는 정리했음. 다음 관측은 실제 실패하는 출발·도착 앱, 전환 입력 방식, 입력 중단과 무관한 블러 공백의 재현임.


사용자 후속 답변으로 실제 실패 조건은 전체 화면 앱↔전체 화면 앱임을 확인했음. 실제 앱 이름과 키보드/트랙패드 방식은 추가 확인 중임. 자동 probe가 렌더러까지 대신하는 차이를 제거하기 위해 `labobserver` 조건을 추가함. 이 조건은 별도 가림을 만들지 않고 실행 중인 Blur Lab을 원본 스트림에서 제외하며 표시 스트림에만 포함함. 실행 중인 Lab이 없으면 명시적 오류임.

실제 Lab을 수동+45°/반경20으로 켠 상태에서 일반 NSView 합성 fixture8회(`/tmp/privacy-pattern25-transition-labobserver.log`)와 Metal drawable에 같은 줄무늬를 그리는 fixture8회(`/tmp/privacy-pattern26-transition-labobserver.log`)를 Control 좌/우로 비교했음. 시각 일치 표본은 각각265/523, 그중 전환85/105이며 전체 대비 비율 최대0.2475/0.2537임. 왼쪽 강한 블러 구간1·3·5번의 순색 전환 표본은 일반 창0, Metal 창 최대0.0041이었음. Metal 실행의 raw-only319/shown-only324표본도 제외됐음. 총48회 추가 비교에서 관측한 표본은 증상을 재현하지 못했으며 GPU 방식 전체의 무결함을 증명하지 않음.

실제 Lab의 `LAB EVENT`에서도 Space 알림 당시 active true와 명시적 해제 후 stop을 확인했음. 이는 출력 수명 계측 확인이며 픽셀 보호 증거는 아님. 합성 fixture·observer 종료 후 Lab은 열어두고 블러는 해제했음. 센서 입력은 꺼져 있으며 재실행으로 정면 기준을 다시 맞춰야 함. 사용자 재현용 최초90초 창 위치 기록은 다음 블러 시작에서 다시 시작됨.


### 중간 정지 재현과 관측 우선순위 재설정

최신 사용자 관측: 전체 화면 앱끼리 트랙패드와 Control 좌/우 모두에서 발생함. 트랙패드 전환을 중간에 멈추면 출발 앱 쪽에만 블러가 적용됨. 이는 사용자 실물 관측이며 앞선 캡처 지표에서 검출한 결과는 아님. 입력 방식 하나의 이벤트 누락으로 좁히지 않음. 출발 Space에 속한 가림/배경 샘플링 범위가 도착 Space를 포함하지 못한다는 가설을 우선하되, 창 위치·clip·backdrop 샘플링 중 어느 원인인지는 미확정임.

현재 `PrivateCover`는 앱 소유 NSPanel에 backdrop을 붙이고 좌우 확장·반복 마스크·역변환 보정으로 화면 좌표를 유지하려는 후보임. WindowServer가 최종으로 합친 디스플레이 전체에 후처리 필터를 거는 구현은 아님. 창을 높은 레벨에 두는 것과 Space 전환 결과 전체를 연속 샘플링하는 것은 다른 보장임. [Apple DTS의 overlay 안내](https://developer.apple.com/forums/thread/826308)는 전체 화면 위 NSPanel 표시 방법을 제공하지만 전환 중 양쪽 장면의 연속 backdrop 필터링을 검증한 근거로 확대하지 않음.

다음 작업은 렌더 후보 추가 전에 사용자 실패를 검출하는 관측 체계를 마련하는 것임. 기존48회 비교는 화면 중앙 띠와 두 캡처 스트림의 시각 일치 표본에 한정됐으며, 전환 중간 정지·취소·반대 방향 복귀를 검사하지 않았음. 미일치 표본과 Space 색 경계 주변의 제외 구간이 존재함. 이 검사에서 미검출된 사실을 실제 화면의 무노출 증거로 사용하지 않음.

1. 합성 A/B 장면을 다른 색과 알려진 줄무늬로 구별하고, 수동 고정 입력에서 25/50/75% 진행의 유지·취소·역방향 복귀를 포함해 재현함. 트랙패드 중간 유지의 실제 실행 여부를 키보드 왕복으로 대체하지 않음.
2. 먼저 균일한 블러로 출발/도착 장면 모두의 유지 여부를 판정하고 이후 고정 가변 마스크를 검증함. 디스플레이 고정 표식의 위치, 가림 창의 clip 범위, 양쪽 장면의 대비 감소를 각각 관측하여 창 이동과 배경 샘플링 실패를 구분함. 표식·균일 블러는 격리 진단 입력이며 제품 UX 변경이 아님.
3. 검출기는 알려진 합성 입력의 구간별 대비를 독립적으로 판정하도록 설계함. 의도적으로 도착 장면의 블러를 끄거나 일정 프레임 동안 전체 효과를 제거하는 양성 대조군에서 반드시 실패를 검출해야 함. 정상 대조군, 제외/미관측 면적·프레임, 검출한 공백 지속 시간을 함께 보고함. 검출기를 통과시키기 위해 누락 구간을 정상으로 간주하지 않음.
4. 캡처 켠/끈 조건을 분리함. 캡처 없는 실물 관측과 캡처 지표가 일치하는지 사용자 육안 또는 외부 촬영으로 대조하기 전에는 검출 정확도를 확인했다고 쓰지 않음. 외부 촬영 자료는 아직 요청·수집하지 않았음.
5. 알려진 실패를 검출한 뒤에만 ‘전환 전체보다 위에 고정된 하나의 출력’ 후보를 비교함. 원하는 구조는 A/B 전환 합성 결과 위에 한 번 블러를 적용하는 것임. 현재 공개/비공개 창 옵션으로 이를 확보했는지는 미확인이고, OS 제약으로 불가능하다는 결론도 아직 아님.

이 재설정은 사용자 요청에 따른 조사 순서 변경이며 완료 기준 완화가 아님. 화면 전환 감지를 더 빠르게 만드는 일과 실제 블러 공백을 검출하는 일을 구분함. 제품 앱·Lab 렌더 코드는 이번 방안 정리에서 변경하거나 재실행하지 않음.


### 검출기와 실제 중간 정지의 첫 실패 포착

균일 블러 전용 독립 표시 프레임 검출기를 추가했음. 기존 summary의 원본/표시 시각 일치 필터를 사용하지 않으며, 별도 off 예제의 구간별 대비 중앙값으로 표시된16구간을 분류함. 분류용 비율0.15/0.65는 진단 수치이며 제품 acceptance가 아님. 혼합 경계·자료 누락은 unknown, 중간 대비는 uncertain으로 남김. 원본과 시각이 맞지 않는 한 프레임 노출·도착 쪽 한 구간만 선명함·경계 옆 노출·누락·중복·미완료·NaN·주입 후 복구 누락을 검사하는 순수 회귀8개를 메인이 실행했음. 통과는 센서/실물 보호 증명이 아님.

내장1728×1117pt Retina2x, Metal 줄무늬 A/B에서 새 off 기준선을 수집했음. 아래 수치는 중앙8pt 띠의 표시 프레임 단독 관측임.

| 실행 | 관측 프레임 | 노출 프레임 | 의미 |
| --- | --- | --- | --- |
| pattern27-off | 893 | 893 | 블러 없는 양성 기준선, 전환8회 |
| pattern27-plain | 874 | 136 | 화면 크기 창의 기존 실패를 검출, 전환8회 |
| pattern27-overscan | 893 | 0 | 자동 전환8회에서 미검출. uncertain6·unknown708구간이 있어 보호 통과 아님 |
| hold28-overscan | 4796 | 1645 | 사용자가 직접 중간 정지/취소한 구간에서 노출을 포착 |
| fault30 | 913 | 12 | 정지 예제에서200ms 의도적 전체 노출을 검출, 주입 전/후 복구 확인 |

로그는 `/tmp/privacy-pattern27-transition-{off,plain,overscan}.log`, `/tmp/privacy-hold28-overscan.log`, `/tmp/privacy-fault30.log`임. 첫 재활용 시도인 pattern8-off에는 PROFILE/REGIONS가 없어 기준선 부족 오류로 거부됐음. 기준을 낮추지 않고 새 기준선을 수집했음.

hold28에서 노출로 분류된11748구간은 모두 초록 예제였으며 자홍 예제의 노출 분류는0이었음. 사용자는 후속 답변에서 ‘한쪽만 블러이며, 블러된 쪽도 끝부분이 불안정하게 풀리는 경우가 있음’으로 구체화했음. 한쪽 장면의 노출에 집중된 계측과 방향성은 부합하지만, 블러된 쪽 가장자리 해제까지 검출됐다고 확인하지 못했음. 따라서 계측이 사용자 육안과 완전히 일치했다고 주장하지 않음. 가장 긴 표시 표본 간격은1008.34ms로, 이 사이의 실제 패널은 미관측임. 여러 초 동안 양쪽 장면이 함께 보이는 실제 트랙패드 조건을 이전 키보드8회와 구별함.

같은 로그의 역변환 tx는−1856~12480으로 변했음. 25ms 이내 다음 transform과 짝지은 노출 프레임1644개 중1643개는 단순 이동 모델에서 창 범위가 전체 화면을 덮지 않는 tx였음. Space 복제 표면 전부를 이 API 하나가 나타낸다는 보장이 없으므로 최종 clip 원인으로 확정하지 않음. 확장만 하면 모든 전환에서 유지된다는 이전 가정은 이 재현으로 기각됨. 레이어 내부 위치 보정과 창/Space 자체의 범위는 별도 문제로 조사함.

fault30에서는12프레임×16구간 모두 노출됐고 unknown0이었음. 첫 검출은 주입 명령 뒤8.76ms, 첫/마지막 노출 표본 간격183.34ms임. 물리 패널의 응답 지연 측정이라고 쓰지 않음. 주입 전 블러·주입 후 복구·범위 밖 오탐 없음도 검사했음. 앞선 pattern29-faultpulse는 주입 중 원본/표시 모두 예제 색 비율0으로 다른 화면이 관측되어 무효임. 새 양성 검증기는 그 로그를 오류로 거부함. 노출 없음으로 통과시키지 않음.


후속 highoverscan 비교(`/tmp/privacy-hold31-high.log`)는 창 level만25→1000으로 바꿨음. 출력 메타데이터에서 level1000을 확인했으나 raw의 초록 비율20~80%인 중간 전환 표본이0개였음. 따라서 표시6708프레임에서 노출0이라는 수치를 중간 정지 개선으로 해석하지 않음. 사용자가 전환하지 않은 것인지, 전환 입력이 막힌 것인지도 미확인임. 모든 fixture·자동 가림은 종료했고 실행 중인 기존 Lab/제품 앱은 교체하지 않았음.

검출기의 기준선은 동일 예제·해상도·색 조건에서 올바르게 준비됐다는 전제에 의존함. 잘못된 off 라벨이나 다른 환경의 낮은 대비를 수치만으로 확실히 판별할 수 없음. 임의 절대 범위 검사를 추가해 그 보장을 만들었다고 주장하지 않음. 다음 원인 분리는 중간 정지 실패의 창/Space 범위와 실제 블러 구간을 대조하는 것임. 사용자 수동 실험의 다음 개선은 전체 블러 위에도 종료·진행 안내가 읽히는 진단 컨트롤을 준비하는 것임. 현재120초 자동 종료만으로 즉시 종료 조작을 제공했다고 쓰지 않음.


### 한쪽 유지와 가장자리 해제의 분리

최신 사용자 관측으로 두 현상을 구분함. (1) 중간 정지에서 한쪽 장면만 블러가 남음. (2) 블러가 남은 장면도 끝부분이 간헐적으로 풀림. (1)은 hold28의 한 색 노출 집중과 부합함. (2)는 기존16구간 검출에서 혼합 경계를 unknown으로 둔 부분과 중앙 띠 밖을 포함할 수 있으므로 별도 검출 미확인임. unknown을 노출0으로 바꾸거나 가장자리 해제를 이미 잡았다고 쓰지 않음.

이번 재현 입력은 AirPods와 무관한 고정 균일 블러였음. 따라서 센서 각도 변동이나 제품의 가변 마스크 모양만으로 이 실패를 설명할 수 없음. 출력 창의 이동·Space별 clip·backdrop이 읽는 배경 범위를 우선 후보로 유지함. 이 세 후보 중 확정된 단일 원인은 아직 없음.

다음 검출 보강은 scene 색 경계 주변의 넓은 혼합 구간을 그대로 제외하지 않고, 같은 장면으로 식별 가능한 좁은 구간의 대비를 따로 측정하는 것임. 식별 불가능한 혼합 픽셀과 화면 바깥은 미관측으로 유지함. 고정 표식도 함께 관측해 표식까지 잘리는지, 표식은 남고 블러만 풀리는지 구분함. 실제 계측 변경/추가 실험은 이번 사용자 답변 정리에서 실행하지 않았음.


### 제스처 자동화 가능성의 정정과 실측

‘중간 정지는 직접 손으로만 관측해야 함’이라는 앞선 설명은 조사 부족이었음. 현재 Orca computer-use capabilities와 scroll/drag 도움말에는 다중 손가락 진행·유지·취소가 없지만 별도 도구로 Dock 제스처를 합성할 수 있음. [dockswipe 소스](https://github.com/oomol-lab/dockswipe/blob/1a761f6f47bdb3259bdbac5d207fefd82fe364d8/dockswipe.m)와 [Mac Mouse Fix 구현](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m)의 began/changed/cancelled 경로를 조사했음. Hammerspoon의 newGesture도 조사 후보였으나 Dock의 연속 진행 제어를 검증한 대체재로 채택하지 않았음.

macOS26.6.2, 내장1728×1117pt Retina2x에서 이벤트 게시·접근성 기존 권한을 읽기 전용으로 확인했고 둘 다 허용 상태였음. 권한 변경·SIP 변경·전역 설치 없이 격리 wrapper를 빌드함. 빌드·dry-run·잘못된 인자 거부·HOLD 중 SIGTERM 뒤 취소/종료143을 확인했음. 실제 손동작과 같은 모든 이벤트를 만드는 도구라고 주장하지 않음. 현재 wrapper는 유지 뒤 종료 속도0, 취소 재전송200ms 조건이며 원본 구현의 추가500ms 재전송 등과 차이가 있음.

실험32에서 합성 입력−0.5를 보낸 뒤 HOLD 양 끝100ms를 제외한 raw120표본 모두 도착 초록 장면 비율40.74%였고, 취소 뒤 출발 자홍 화면으로 복귀했음. 단순 이벤트 전송 성공이 아니라 실제 중간 화면 유지·취소가 확인됐음. 같은 출발점의+0.5는 바깥 Space 경계에 걸려 유효한 반대 방향 시험이 아니었음. 실험35에서는 출발점을 초록 A로 바꿔+0.5와+0.8을 시험함. 각각102/101표본에서 도착 자홍 화면이44.44%/71.12% 들어온 상태를 유지했고 취소 뒤 초록 비율99.8% 부근으로 복귀했음. 진행 값과 화면 비율은 동일하지 않음.

| 실행 | 조건 | 표시 프레임 | 노출 프레임 | 미판정 구간 |
| --- | --- | --- | --- | --- |
| pattern33-overscan | 안정된 B에서−0.5 유지·취소 | 894 | 0 | uncertain28 / unknown538 |
| pattern33-highoverscan | 같은 입력, 창 level1000 | 697 | 0 | uncertain24 / unknown340 |
| pattern33-marker | 같은 입력, 고정 표식 추가 | 837 | 0 | uncertain28 / unknown497 |
| pattern34-overscan | 제스처 HOLD 시작 뒤 가림 생성 | 859 | 0 | uncertain28 / unknown101 |
| pattern35-overscan | A에서+0.5/+0.8 유지·취소 | 909 | 0 | uncertain56 / unknown962 |

검출 기준선은 같은 환경의 `/tmp/privacy-pattern32-transition-off.log`임. 실행 로그는 `/tmp/privacy-pattern{33,34,35}-transition-{mode}.log`, 입력 시각은 `/tmp/privacy-gesture33-{mode}-events.log`, `/tmp/privacy-gesture34-events.log`, `/tmp/privacy-gesture35-events.log`임. 실험32/33은 임시 prototype의 반복 sleep 유지,34/35는 저장소 wrapper의 단조 시계2초 유지를 사용했음. 실제 유지 시간은 이벤트 로그가 정본임. 33-high의 가장 긴 관측 공백은1008.34ms,35는33.33ms임. 모두 중앙 띠에서 미검출이며 verdict는 not_established임. 수동 hold28 실패를 뒤집거나 level1000의 해결 근거로 쓰지 않음.

원인 조사에서 남은 핵심은 수동 실패와 합성 미재현의 조건 차이임. 센서 없는 균일 블러에서도 실패했으므로 센서/가변 마스크만의 문제는 아님. 창 이동은 확인됐지만 Space의 가림 범위와 backdrop이 읽는 배경 범위 중 무엇이 깨지는지는 미확정임. 다음에는 같은 시작 Space·실제 진행 비율·가림 생성 시점을 고정하고 좁은 색 경계의 노출, 고정 표식, 창 transform/clip을 같은 시간축으로 비교함. 표식도 사라지면 창/Space 범위 쪽, 표식은 남고 블러만 사라지면 배경 샘플링 쪽을 우선 검증하되 단일 지표로 확정하지 않음. CGS의 clip shape 조회 헤더는 조사했으나 실행 계측은 아직 추가하지 않았음. 캡처가 합성 경로에 영향을 주는지도 별도 대조가 남음.

이번 변경은 진단 도구와 문서이며 제품 앱·Lab의 렌더 방식은 변경하지 않았음. 자동화 경로 확보는 완료했지만 사용자 실패의 안정 재현·근본 원인 확정·수정 완료는 아님.


### 빠른 완료 제스처와 여러 전체 화면의 연속 이동

사용자 요청에 따라 중간 유지/취소뿐 아니라 빠른 완료 입력과 앱 활성화가 겹치는 구간을 실측했음. `gesture-hold.m --fast`는 약80ms를 목표로8번 진행 이벤트를 보내고 마지막 이동 속도를 유지해 END로 완료함. 운영체제 스케줄링에 따른 실제 시각은 이벤트 로그로 판정함. 기본2초 유지/취소는 그대로임. 이 옵션의 fast는 제스처 속도이며 agent fast mode가 아님.

내장1728×1117pt Retina2x에서 합성 Metal 전체 화면 A/B의 빠른16회 왕복을 원본 색 변화로 확인했음. 단일3화면 폭의 균일 블러에서는 노출0이었음(pattern36-overscan, 표시877프레임). 제스처 시작60ms 뒤 반대 예제 앱을 활성화한 조건도 노출0이었음(pattern37-overscan,896프레임). 이는 사용자 실패가 없다는 증거가 아니라 두 앱에 한정된 미재현임.

같은 렌더 설정으로 전체 화면 예제를4개로 늘려 한 방향3회 후 반대 방향3회를2번 반복했음. raw 색의 안정 상태 변화12회와 중간 장면을 확인했고, 기존 overscan에서273프레임/3615구간의 노출을 포착했음(pattern39-overscan,902프레임). marker 변형에서도269프레임 노출이 있었음. 두 앱 왕복에만 의존한 이전 검증의 범위 부족을 확인함.

이때 catenated transform의 tx는−3647~1728이었음. 기존 창은5184pt 폭임. 이 변환을 단순 역이동으로 해석하면 화면을 덮지 않는 구간이 생기며, 넓게 분할 배치한 창에서 노출이 크게 줄어 창/Space의 가림 범위 부족 가설을 지지함. 다만 해당 API가 모든 Space 복제 창의 실제 배치를 대표한다는 보장은 없으므로, tx 하나로 최종 합성 범위를 확정하지 않음.

가변 블러는 별도로 실패했음. Lab과 같은 고정+45° 경로에서 시작 전부터 흐렸던 왼쪽4구간만 검사했으며, 의도적으로 선명한 오른쪽은 실패로 세지 않음. 빠른 왕복16회에서23개 표시 프레임의 맨 왼쪽 구간이 다시 선명했음(pattern38-fixedangle). 가장 가까운 END 기준−72.9~+4.5ms에 분포했음. 센서 없이 재현되며 창 위치를 읽어 레이어에 역이동을 전달하는 경로의 시각 차이가 후보임. 전송 직후 CATransaction.flush를 추가한 임시 빌드에서도19프레임이 남아 기각했음(pattern43-fixedangle). CPU 전달 지연이 유일한 원인이라고 확정하지 않음.

| 후보 | 표시/노출 프레임 | 판정 |
| --- | --- | --- |
| 기존3화면 폭,4앱 연속 | 902 / 273 | 재현 기준선 |
| superSticky+neverFlatten | 879 / 268 | 실패 |
| neverFlatten만 | 879 / 264 | 실패 |
| canJoinAllApplications 제거 | 871 / 262 | 실패 |
| isMovable=false | 896 / 271 | 실패 |
| 화면 크기9창, 비중첩 배치 | 904 / 2 | 넓은 노출 감소, 잔여 실패 |
| 위 배치+preallocatesScreenArea | 868 / 2 | 실패 |
| 위 배치+ignoresScreenClip | 863 / 0 | 단일 실행 미검출. 통과 아님 |
| 위 배치+두 속성 모두 | 881 / 2 | 실패 |
| 3화면 폭3창, 같은 전체 배치 범위 | 876 / 1 | 잔여 실패 |
| 위 배치+ignoresScreenClip | 887 / 1 | 잔여 실패 |
| 한 창의 좌표를 Space 간격으로 재배치 | 899 / 7 | 넓은 노출 감소, 재배치 경계 실패 |

무효·기각 구분: 단일7화면 폭 창은 정지 상태부터 효과가 나오지 않았음(pattern40). 이 실행은 C/D fixture가 이미 살아 있어 깨끗한 재배치 비교도 아니므로 정상 대조군으로 사용하지 않음. 큰 표면의 한계는 후보이며 GPU 최대 texture 크기로 원인을 확정하지 않음. identity window mesh 후보는 정지 블러부터 실패했음(pattern45의 두 조건). 메뉴/상태 막대 tag 후보도423프레임씩 노출되어 기각했음(pattern46). ignoresScreenClip을 가변 마스크에 적용한 임시 빌드는 정상 블러부터 사라졌으므로 적용하지 않음(pattern48). weak 타일 조건은 강도가 다른 조사이므로 위 균일 강도 비교표에서 제외함.

`CABackdropLayer`의 ignoresScreenClip/preallocatesScreenArea/disablesOccludedBackdropBlurs 등의 존재와 기본false는 현재 기기에서 직접 만든 레이어의 Objective-C property와 KVC 값으로 확인했음. 이름만으로 동작 보장을 추정하지 않음. [CGSWindow 선언](https://github.com/NUIKit/CGSInternal/blob/master/CGSWindow.h)은 tag·clip·transform 후보의 출처임. [Chromium의 warp 구현](https://chromium.googlesource.com/chromium/src/+/974fbd270d47948c3ebe2a1a98adf0484344bc18/ui/base/cocoa/constrained_window/constrained_window_animation.mm)과 [현행 float mesh 선언](https://github.com/usagimaru/GenieWarpMesh/blob/main/Sources/CGSPrivate/include/CGSPrivate.h)을 참고했으나, 다른 변환을 막는다는 과거 주석을 현재 Space 고정의 보장으로 취급하지 않았음.

로그는 `/tmp/privacy-pattern{36…50}-transition-{mode}.log`, 입력 단계는 대응하는 `/tmp/privacy-gesture{번호}-{mode}-events.log`임. 별도 임시 빌드43은 flush만,48은 ignoresScreenClip 강제만 바꿨으며 저장소의 기본 렌더에는 적용하지 않았음. `/tmp/privacy-fast-transition-results.json`은 완료된 균일 실험25개의 수치 요약이며, 포함된 무효/강도 차이 조건의 판정은 이 문서를 우선함. 중앙 띠의 색 혼합은 unknown이고 대부분의 실행에33.33ms 표본 공백이 있음. 실제 패널 전체·외장 모니터·물리 손동작과의 완전한 동등성을 보장하지 않음.

현재 결과는 재현 성공과 수정 후보의 실패 분리임. 후보를 제품 앱이나 실행 중인 Blur Lab의 기본 동작으로 올리지 않았음. 단일 출력의 공간 범위, Space 복제/clip, 가변 마스크 전달 시각을 함께 만족하는 수정은 미완료임.


후속 clip 계측(2026-09-15): 처음의 pattern50은 `SLSGetWindowTransformAtPlacement` 내부에서 EXC_BAD_ACCESS로 종료됐음. 크래시 보고서 `PrivacyPrivateTransition-2026-09-14-235812.ips`의 faulting thread에서 확인했음. 과거 비공개 헤더의 함수 선언이 현재 ABI/전제와 맞는다고 가정한 실행이었으며 정확한 불일치는 미확정임. 해당 호출을 제거했고 재시도하지 않음. 이 실행은 MEASURE DONE이 없어 무효이며, `open -W` 종료0만 보고 끝났다고 출력한 임시 driver의 DONE 문구도 검증 근거에서 제외함.

저장소의 새 runner는 정상 완료 표식까지 검사함. 위험한 placement 조회를 제거한 clip-only 빌드로 `/tmp/privacy-fast51/`에서 실행했고 정상 종료·fixture 정리·실제 안정 색 변화12회·전체 제스처가 관측 시간 안에 들어감을 확인했음. 표시900프레임 중274개에서 노출됨. `CGSCopyWindowClipShape`와 `CGSGetRegionBounds`는1669회 모두 성공0과 `(0,0,5184,1117)`을 반환했음. 따라서 이번 실행에서 창 자체의 local clip shape가 줄어드는 현상은 관측되지 않았음. 부모 Space의 clip이나 실제 backdrop 샘플링 범위를 읽었다는 뜻은 아니며, 둘의 분리는 여전히 남음. 가장 긴 표시 표본 공백은41.67ms임.

최종 변경은 빠른 입력·독립 검출·반복 실행 도구와 명시적으로 선택하는 진단 후보임. 기본 PrivateCover/Blur Lab 시작 인자의 동작은 바꾸지 않았으며, `rebase`·분할·mesh·비공개 속성 후보는 해결책으로 승격하지 않았음. 수정 완료 조건은 알려진4앱 연속 실패와 고정 가변 마스크의 빠른 전환 노출을 모두 없애고, 정지 외형·강도·중복 합성·실제 패널을 회귀 확인하는 것임.


## 데스크톱 이동과 분리한 출력 — 2026-09-15

기존 실패는 전환을 늦게 감지하는 문제만으로 설명되지 않음. 균일 블러에서도 창이 Space와 함께 이동하며 여러 전체 화면 연속 전환에서 가림 범위를 벗어났음. 새 후보는 앱 소유의 unmanaged composition Space를 만들고 화면 크기의 블러 창 하나를 여기에 부착함. 데스크톱 전환과 별개로 합성되는 공간이며 기존 사용자 Space를 삭제하거나 재배열하지 않음. 창 역이동·3화면 폭 확장·반복 마스크는 이 경로에서 사용하지 않음. 같은 색조 없는 variableBlur 필터와 강도 계산은 유지함.

API 흐름은 [CGSSpace wrapper](https://gist.github.com/julianschiavo/6472bbbe10359133765e95d339e25fb4)와 [CGSSpace 선언](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h)을 참고했음. wrapper 파일 자체를 복사하지 않고 ObjC 수명 객체를 작성했음. 비공개 API 실험이며 OS 간 지원·App Store 적합성·배포 승인을 의미하지 않음. 현재 기기는 SIP 활성 상태이고 SIP나 시스템 설정 변경 없이 부착했음.

`PBIndependentSpace`가 심볼 확인→생성→소유 창 부착/조회→hide/destroy를 담당함. mask7 조회는 unmanaged Space를 제외하여 첫 시험52가 READY 전에 중단됐음. mask15 조회로 실제 부착을 확인한 뒤 시험53부터 정상 실행했음. 시작 실패는 창과 공간을 정리하고 오류를 전달함. 화면 매칭이 없으면 실패하며 이미 시작된 cover의 재시작도 거부함. 이전 membership 제거 역시 mask15를 사용함.

| 실제 내장 화면 실험 | 관측 | 한계 |
| --- | --- | --- |
| 균일 블러, 전체 화면4개 연속12회 (`/tmp/privacy-fast53/`) | 712표시 프레임, 선명 노출0, 혼합/미관측223구간 | 최대 표본 간격58.33ms |
| +45° 고정 가변 블러, 같은12회 (`/tmp/privacy-fast54/`) | 첫 제스처 이후838프레임, 왼쪽4구간 노출0/흐림3211/unknown141 | 최대 간격25.00ms, 의도된 오른쪽 선명 영역 별도 확인 |
| 44~46° 연속 갱신, 같은12회 (`/tmp/privacy-fast54/`) | 전체906프레임의 맨 왼쪽 흐림837/unknown69/노출0, 맨 오른쪽 선명735 | 실제 AirPods 회전 아님 |

세 실행 모두 raw의 내부14구간이 같은 색인 안정 표본에서 녹색/자홍 변화12회를 확인했음. 전체16구간을 모두 같은 색으로 요구하면 자홍 fixture 가장자리 분류가 달라 완료 상태를 놓치므로, 실제 이동 여부 확인은 내부14구간을 사용했음. 노출 검출의 좌우 가장자리 구간은 제외하지 않음. 창 transform은 모든 관측에서 identity(tx0,ty0)였음. fixedangle 오른쪽 끝은 전체900프레임 중728개가 선명 분류여서 전체 블러로 퇴행한 결과가 아님. 출력 픽셀은 저장하지 않고 중앙8pt 띠의 수치만 남겼음.

이 결과로 별도 Blur Lab의 기본 시작을 independent 경로로 변경함. 제품 앱의 native 출력은 별개이며 아직 교체하지 않음. 중앙 띠 미검출은 실제 패널 전체의 무노출 보장이 아니며 혼합 경계·표본 사이·외장 화면·물리 손동작·사용자 미감 acceptance는 남음. WindowServer 내부 clip/샘플링 원인을 직접 읽었다고 주장하지 않음. 기존 이동 경로를 제거했을 때 알려진 실패가 사라진 인과 비교 근거임.


수명 회귀: 수정 Lab 빌드·서명 검증과 `--smoke-test --trace-transitions` 정상 종료0을 확인했음(`/tmp/privacy-independent-lab-smoke{,-errors}.log`). 시작/갱신·stale 입력 후 해제/보정 초기화·시작 직후 취소·3회 재시작/중복 stop·빈 화면 설정의 시작 거부가 모두 기대값을 출력했음. 생성한6개 Space ID에 각각 정리 호출이 대응했고 종료 후 해당 앱 프로세스도 종료됐음. destroy 로그는 호출 완료 근거이며 WindowServer 내부 자원의 독립 전수 검증은 아님. 검출기8개와 고정 마스크 분석4개 검사도 종료0임.


중간 유지 재검증: 시험55/56은 반대 방향이 비예제 데스크톱으로 향해 전체 화면 양방향 증거로 사용하지 않았음. `open -a B` 반환만으로 B 출발을 보장하지 못했음. runner를 A에서 유지/취소→완료 제스처로 B 이동→반대 유지/취소 순서로 고쳤음. 시험57(`/tmp/privacy-fast57/`)은 각2초 유지의 raw110/112프레임 모두 양쪽 예제 색이 동시에 존재했음. +45° 고정 가변 보호 구간은 첫 입력 이후829프레임에서 흐림3249구간/unknown67/선명 노출0, 최대 표본 간격33.34ms였음. 취소2회와 완료 이동1회가 모두 관측 시간 안에서 끝났음. 물리 트랙패드와 합성 입력의 동일성을 보장하지 않음.

실제 Lab UI: 수정 앱을 실행해 computer-use로 시작 버튼을 누르고 적용 중 상태를 확인했음. 출력 활성 후 AX tree가 panel로 바뀌어 제어 창의 최신 스크린샷 좌표로 해제를 누르고 `실험 블러 해제됨`과 owned Space 정리 로그를 확인했음. 창 캡처에서 컨트롤 가독성을 확인한 것이며 물리 패널 전체나 메뉴 드롭다운의 픽셀 검사로 확대하지 않음. 수정 창은 수동 준비/해제 상태로 유지함.


균일 블러 중간 유지 대조(`/tmp/privacy-fast58/`): 같은 양방향 취소 순서에서 유지 중 raw112/111프레임 모두 두 예제 색이 동시에 존재했음. 전체888표시 프레임에서16구간 흐림13593/unknown615/선명 노출0, 최대 간격33.34ms임. 가변 블러의 의도된 선명 영역과 구분해 양쪽 장면에 블러가 남는 조건을 확인했음. 종료0·probe/fixture 정리 후 수정 Lab 창을 앞으로 복구했음. 마지막 상태는 각도45°·강도20·AirPods 입력 꺼짐·블러 해제임.

## 본체 채택 — 2026-09-15

사용자가 본체 통합을 요청해 independent 기본 후보를 Privacy AirPods 실제 보호에 연결했음. 공유 PrivacyBackdrop 어댑터와 ScreenCover 출력 경로를 Lab에서도 재사용함. 앞선 격리 실험 전용 경계는 당시 경과이며 최신 승인 경계는 spec의 본체 통합 절이 소유함. 새 통합 판본의 검증·미검증은 [개발 안내](development.md#본체-통합--2026-09-15)를 참조함. 과거 전환 표본을 새 판본의 실측으로 취급하지 않음.

## 전환 검사 강화 — 2026-09-15

`audit-transition.py`는 기존 노출 분류·제스처 파서를 재사용하는 수치 로그 감사임. 각 제스처의 raw 실제 이동, 출발/도착 및 취소 복귀, raw/shown 관측 공백, protected 구간 unknown/uncertain, 마지막 입력 이후의 표시 표본을 확인함. 입력 DONE과 시각적 완료를 분리함. raw 장면이 진단 기간 동안 안정된 뒤 다른 shown 장면이 나타나면 별도 회귀 신호로 보고하되, 이전 캡처 재표시라는 원인을 확정하지 않음.

진단 기간·관측 간격 기본50ms는 제품의 허용 노출 시간이 아님. 장면 색2개의 합성 예제, 고정 보호 구간, 중앙 띠에만 적용됨. 중복 강도·경계 이동·띠 밖·표본 사이·동적 마스크·안정 판정 전의 짧은 장면 오류는 별도 검증이 필요함. 옵션과 종료코드 정본은 진단 README임.

새 판본으로 과거 수치 로그를 오프라인 재분석했음. 기준선은 `/tmp/privacy-pattern32-transition-off.log`이며 실제 화면을 다시 조작한 결과가 아님.

| 입력 로그 | 강화 감사 결과 | 의미 |
| --- | --- | --- |
| pattern38-fixedangle + gesture38 | 종료1, 노출23프레임 | 과거 부분 블러 실패를 다시 검출함 |
| pattern39-overscan + gesture39 | 종료1, 노출273프레임 | 과거4앱 연속 전환 실패를 다시 검출함 |
| privacy-fast57의 fixedangle | 종료2, 노출0, protected unknown 잔존 | 개선 후보의 미검출을 전체 통과로 바꾸지 않음 |
| privacy-perf-transition의 fixedangle | 종료2, actual motion 미확인·관측 공백·unknown | 실행 종료0뿐이던 무효 시험을 품질 성공으로 사용하지 못하게 함 |

결과 JSON은 `/tmp/privacy-audit-failure38.json`, `/tmp/privacy-audit-failure39.json`, `/tmp/privacy-audit-independent-hold.json`, `/tmp/privacy-audit-invalid-run.json`에 있음. 임시 파일의 영구 보존은 보장하지 않음.

자동 회귀: 기존 노출8개·고정 마스크4개·새 전환 감사11개가 각각 종료0임. 새 검사는 한 프레임 노출, 이동 없는 명령 성공, 혼합 비트3의 취소 복귀, unknown/uncertain, 시계/구간 오류, 꼬리 표본 누락·장면 재등장·관측 공백, 정상 대조를 포함함. 실제 본체 전환의 재검증이나 인간의 미감 판정을 대체하지 않음. 사용자 외장 작업을 보호하기 위해 앱 조작·전역 키/제스처·화면 캡처를 실행하지 않았음.

## 전체 격자와 재현 가능한 검사 실행 — 2026-09-15

전체 화면 영역을16×9셀로 나누는 `GridMetrics`와 `PrivateTransitionProbe --grid`를 추가함. 네 픽셀 간격의 표본에서 셀별 대비·장면색·샘플 수만 남김. 이 방식은 중앙 띠 밖의 상하단도 관측하지만 모든 픽셀·모든 프레임의 보장은 아님. 최종 probe는 `swiftc -O`로 `/tmp/privacy-private-transition-grid`에 빌드·링크 성공했으며 실행하지 않았음.

`audit-grid.py`는 같은 설정의 기준에서 셀/장면색별 대비 감소 비율을 보정함. 관측 전체의 중앙값 대신 각 표시 프레임을 비교하므로 한 프레임의 과도한 흐림/선명 노출을 평균으로 숨기지 않음. 공간적으로 이동한 고정 블러 분포도 비교할 수 있음. 혼합/other 셀, 짝 없는 shown 표본, 기준 부족·불안정·너무 낮은 대비·포화는 불충분으로 남김. 이미 거의0인 기준에서는 더 강한 흐림을 증명할 수 없음을 표시함. raw/shown의 장면 불일치는 허용 매칭 간격 내 정상 전환에서도 가능하므로 곧바로 경계 결함으로 단정하지 않음. 신호에는 raw/shown tick을 남김.

기준과 관측의 해상도·스키마는 자동 대조함. 동일한 렌더 설정으로 수집됐는지는 현재 JSONL만으로 증명하지 못하며 수집 조건으로 유지해야 함. 동적 고개 회전의 시간별 정답 마스크, 실제 물리 패널의 픽셀 전수·시각적 궤적 acceptance는 아직 보장하지 않음.

과거 수치 로그9개를 `scripts/diagnostics/fixtures/transition/`에 압축 보존했음(약284KiB). 픽셀·창 제목·소유 Space ID는 제외함. 네 replay의 기대 판정뿐 아니라 노출 수23/273/0/0을 검사해 판정 문자열만 맞는 잘못된 성공을 막음.

최종 검증은 같은 소스/입력의60개 자동 검사와 과거 replay4개, 총10개 독립 과제임. 실제 Swift BGRA 추출6개, 격자 분석19개, 캐시·스냅샷12개, 기존 노출/고정/전환23개가 포함됨. 세 실행 모두 종료0이고 모든 과제의 판정·검사 수·replay JSON이 동일함.

| 실행 | 실행기 wall time | 실제 실행 / 재사용 |
| --- | --- | --- |
| 순차 fresh (`--jobs 1`) | 5.471초 | 10 / 0 |
| 병렬 fresh (`--jobs 4`) | 1.650초 | 10 / 0 |
| 병렬 warm cache | 0.310초 | 0 / 10 |

이는 동일 Mac의 단회 로컬 측정임. 컴파일러/OS 캐시·다른 작업 부하를 통제한 통계 실험은 아니며 일반적인 속도 향상률이나 모델 비용 절감을 뜻하지 않음. 실행기 보고서는 `/tmp/privacy-diagnostic-{sequential,parallel,cached}.json`임.

캐시는 소스·입력 내용·명령/기대값·Python/Swift 버전과 실제 Swift compiler digest·환경을 키에 포함함. 별도 소스/입력 스냅샷에서 검사하므로 실행 중 원본 변경이 결과에 섞이지 않음. 같은 크기/mtime 변경·강제 실행·실패/손상 영수증·빈 검사·병렬 쓰기·스냅샷 원본 변경·기대 노출 수 오류를 회귀로 검증함. 실제 OS/GPU/전환 실측 결과는 캐시로 새 검증처럼 쓰지 않음.

이번 작업에서는 화면 캡처·앱 조작·전역 제스처를 실행하지 않았음. 새 전체 격자 계측의 실제 WindowServer 부하·실물 캡처 정상성·전체 화면 전환 acceptance는 남아 있음. 코드/합성 검증을 제품의 외형 보장으로 승격하지 않음.

마지막 수집기 검토에서 비완료 상태의 캡처 sample은 이미지 버퍼가 없을 수 있으므로, 상태를 먼저 기록하고 완료 sample에서만 버퍼를 요구하도록 순서를 보강함. 이 수정 뒤 전체60개+replay4건을 다시 fresh 병렬 실행해 종료0을 확인했음(`/tmp/privacy-diagnostic-final.json`). 위 순차/병렬/cache 표는 이 마지막 수집기 순서 보강 전의 동일 판본 비교이며, 실제 수집기 실행 시간 측정이 아님.
